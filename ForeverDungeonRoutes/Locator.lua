local _, DR = ...

-- Where the player stands inside a dungeon (since 1.4.0). Inside instances the game gives addons no position
-- (UnitPosition and the map position stay empty), but it still says how far it is to the map pin the player tracks
-- (C_Navigation.GetDistance). The locator has the game track a few flight masters in turn (super-tracking a map pin
-- of the kind TaxiNode), reads the distance to each and works out the position from these distances and the places
-- of the flight masters (Data/TaxiNodes.lua, from the game's TaxiNodes table). Assumed: the game measures the
-- straight distance between the two points in world coordinates, also from inside an instance; a fix whose distances
-- do not fit one place (MAX_RESIDUAL) is dropped, so a wrong assumption shows nothing instead of a wrong place.
--
-- Limits, on purpose: only the player's own position; only while one of the addon's maps is shown and the setting
-- is on; never in combat, as a ghost or where the game gives a position anyway. In combat the last place stays on the
-- map, faint (Held), until the first fix after the fight (at most FRESH seconds). The player's own tracking (quest,
-- map pin, waypoint) is noted before each round and put back after it. Should the game stop answering (a patch can
-- close this), the locator stops for the session, without errors.

local Locator = {}
DR.Locator = Locator

local TAXI = (Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.TaxiNode) or 2
-- the kinds of tracking (SuperTrackManagerSharedDocumentation of 1.60.1.71091), for clients without the enum
local TYPE = Enum and Enum.SuperTrackingType
	or { Quest = 0, UserWaypoint = 1, Corpse = 2, Scenario = 3, Content = 4, PartyMember = 5, MapPin = 6, Vignette = 7 }
local ANCHORS = 6        -- flight masters per round
local MIN_READINGS = 4   -- distances needed for a fix
local PAUSE = 0.5        -- seconds between two rounds
local FRESH = 2.5        -- seconds a fix counts
local WAIT_FRAMES = 5    -- frames to wait for the game's distance to one flight master
local MAX_RESIDUAL = 4   -- yards: distances that disagree more than this give no fix
local GIVE_UP = 6        -- rounds in a row without a single distance: the game no longer answers
local BACK_OFF = 5       -- seconds without rounds after the player (or another addon) changed the tracking

local fix         -- { x, y, z, instance, t, residual, n }
local holding = false -- the last fix is kept while the locator pauses in combat (Oliver 28.11.2026: "blass lassen")
local holdUntil = 0   -- after the fight it stays until the next fix, at most FRESH seconds
local round       -- the round under way
local blocked     -- why the locator stopped for the session ("no answer"), or nil
local silent = 0  -- rounds in a row without a single distance
local waitUntil = 0
local anchorsFor = {} -- [instanceID .. faction] = { nodeID, ... }
local refused = {}    -- [nodeID] = true: the game did not track this flight master
local last            -- the last round, for /fdr pos: { readings = n, residual, anchors = n, refused = n, why }

local function now()
	return GetTime and GetTime() or time()
end

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local result = { pcall(fn, ...) }
	if not result[1] then return nil end
	return unpack(result, 2)
end

local function supported()
	return C_SuperTrack and C_Navigation and type(C_SuperTrack.SetSuperTrackedMapPin) == "function"
		and type(C_SuperTrack.GetSuperTrackedMapPin) == "function" and type(C_Navigation.GetDistance) == "function"
		and DR.TaxiNodes ~= nil
end

-- What the player tracks now, to put it back after a round; nil where something of it is secret (then no round).
local function noteTracking()
	local st = C_SuperTrack
	local saved = {}
	saved.kind = call(st.GetHighestPrioritySuperTrackingType)
	saved.pinType, saved.pinID = call(st.GetSuperTrackedMapPin)
	saved.quest = call(st.GetSuperTrackedQuestID)
	saved.waypoint = call(st.IsSuperTrackingUserWaypoint)
	saved.contentType, saved.contentID = call(st.GetSuperTrackedContent)
	saved.vignette = call(st.GetSuperTrackedVignette)
	for _, v in pairs(saved) do
		if issecretvalue and issecretvalue(v) then return nil end
	end
	return saved
end

local function restoreTracking(saved)
	local st = C_SuperTrack
	if not saved then return end
	local kind = saved.kind
	if kind == TYPE.MapPin and saved.pinType and saved.pinID then
		call(st.SetSuperTrackedMapPin, saved.pinType, saved.pinID)
	elseif (kind == TYPE.UserWaypoint or (kind == nil and saved.waypoint)) and saved.waypoint then
		call(st.SetSuperTrackedUserWaypoint, true)
	elseif kind == TYPE.Content and saved.contentType and saved.contentID then
		call(st.SetSuperTrackedContent, saved.contentType, saved.contentID)
	elseif kind == TYPE.Vignette and saved.vignette then
		call(st.SetSuperTrackedVignette, saved.vignette)
	elseif type(saved.quest) == "number" and saved.quest > 0 then
		call(st.SetSuperTrackedQuestID, saved.quest)
	else
		call(st.ClearSuperTrackedMapPin)
	end
end

-- The middle of an instance's floors in world coordinates (x north, y west): of the world rectangles, or of the
-- frame of a picture floor (Data/Pictures.lua) at the middle of the map.
local function instanceMiddle(instanceID)
	local sx, sy, n = 0, 0, 0
	for _, dungeon in ipairs(DR:GetDungeonsForInstance(instanceID)) do
		for _, floor in ipairs(dungeon.floors) do
			local info = DR.Floors[floor]
			local w, f = info and info.world, info and info.frame
			if w then
				sx, sy, n = sx + (w[1] + w[3]) / 2, sy + (w[2] + w[4]) / 2, n + 1
			elseif f then
				local det = f[1] * f[5] - f[2] * f[4]
				if det ~= 0 then
					local du, dv = 0.5 - f[3], 0.5 - f[6]
					sx, sy, n = sx + (du * f[5] - f[2] * dv) / det, sy + (f[1] * dv - du * f[4]) / det, n + 1
				end
			end
		end
	end
	if n == 0 then return nil end
	return sx / n, sy / n
end

-- Flight masters of the player's side around the instance's middle, one per direction (ANCHORS sectors), the
-- nearest in each: distances from all sides fix a place best.
local function pickAnchors(instanceID)
	local faction = DR.Safe(UnitFactionGroup and UnitFactionGroup("player"))
	local side = faction == "Alliance" and 1 or faction == "Horde" and 2 or 3
	local cacheKey = tostring(instanceID) .. ":" .. side
	local list = anchorsFor[cacheKey]
	if list then return list end
	local mx, my = instanceMiddle(instanceID)
	if not mx then return nil end
	local sectors, rest = {}, {}
	for id, node in pairs(DR.TaxiNodes) do
		if node[2] == 3 or side == 3 or node[2] == side then
			local dx, dy = node[3] - mx, node[4] - my
			local dist = math.sqrt(dx * dx + dy * dy)
			local s = math.floor(((math.atan2(dy, dx) + math.pi) / (2 * math.pi)) * ANCHORS) % ANCHORS + 1
			local entry = { id = id, dist = dist }
			if not sectors[s] or dist < sectors[s].dist then
				if sectors[s] then table.insert(rest, sectors[s]) end
				sectors[s] = entry
			else
				table.insert(rest, entry)
			end
		end
	end
	list = {}
	for s = 1, ANCHORS do
		if sectors[s] then table.insert(list, sectors[s].id) end
	end
	table.sort(rest, function(a, b) return a.dist < b.dist end)
	for _, entry in ipairs(rest) do
		if #list >= ANCHORS + 3 then break end -- a few spares for flight masters the game refuses
		table.insert(list, entry.id)
	end
	anchorsFor[cacheKey] = list
	return list
end

-- Solve a 3 x 3 system A p = b (Gauss with pivoting); nil when it has no single answer.
local function solve3(A, b)
	local m = { { A[1][1], A[1][2], A[1][3], b[1] }, { A[2][1], A[2][2], A[2][3], b[2] }, { A[3][1], A[3][2], A[3][3], b[3] } }
	for col = 1, 3 do
		local pivot = col
		for r = col + 1, 3 do
			if math.abs(m[r][col]) > math.abs(m[pivot][col]) then pivot = r end
		end
		if math.abs(m[pivot][col]) < 1e-12 then return nil end
		m[col], m[pivot] = m[pivot], m[col]
		for r = col + 1, 3 do
			local f = m[r][col] / m[col][col]
			for c = col, 4 do m[r][c] = m[r][c] - f * m[col][c] end
		end
	end
	local p = {}
	for r = 3, 1, -1 do
		local s = m[r][4]
		for c = r + 1, 3 do s = s - m[r][c] * p[c] end
		p[r] = s / m[r][r]
	end
	return p
end

-- Gauss-Newton from one start: x, y, z and the root mean square misfit in yards, or nil.
local function newton(readings, x, y, z)
	for _ = 1, 25 do
		local JtJ = { { 1e-6, 0, 0 }, { 0, 1e-6, 0 }, { 0, 0, 1e-6 } }
		local Jtr = { 0, 0, 0 }
		for _, r in ipairs(readings) do
			local dx, dy, dz = x - r.x, y - r.y, z - r.z
			local range = math.sqrt(dx * dx + dy * dy + dz * dz)
			if range < 1e-6 then return nil end
			local j = { dx / range, dy / range, dz / range }
			local misfit = range - r.d
			for a = 1, 3 do
				Jtr[a] = Jtr[a] + j[a] * misfit
				for b = 1, 3 do JtJ[a][b] = JtJ[a][b] + j[a] * j[b] end
			end
		end
		local step = solve3(JtJ, Jtr)
		if not step then return nil end
		x, y, z = x - step[1], y - step[2], z - step[3]
		if x ~= x or y ~= y or z ~= z then return nil end -- not a number: the start led nowhere
		if math.abs(step[1]) + math.abs(step[2]) + math.abs(step[3]) < 1e-4 then break end
	end
	local sum = 0
	for _, r in ipairs(readings) do
		local range = math.sqrt((x - r.x) ^ 2 + (y - r.y) ^ 2 + (z - r.z) ^ 2)
		sum = sum + (range - r.d) ^ 2
	end
	return x, y, z, math.sqrt(sum / #readings)
end

-- x and y from the differences of the equations (straight lines, least squares), the height taken as the flight
-- masters' mean height: a start close to the answer.
local function linearStart(readings, meanZ)
	local a1 = readings[1]
	local q1 = a1.x * a1.x + a1.y * a1.y + (a1.z - meanZ) ^ 2
	local s11, s12, s22, v1, v2 = 0, 0, 0, 0, 0
	for i = 2, #readings do
		local r = readings[i]
		local ax, ay = r.x - a1.x, r.y - a1.y
		local rhs = (a1.d * a1.d - r.d * r.d + r.x * r.x + r.y * r.y + (r.z - meanZ) ^ 2 - q1) / 2
		s11, s12, s22 = s11 + ax * ax, s12 + ax * ay, s22 + ay * ay
		v1, v2 = v1 + ax * rhs, v2 + ay * rhs
	end
	local det = s11 * s22 - s12 * s12
	if math.abs(det) < 1e-9 then return nil end
	return (v1 * s22 - s12 * v2) / det, (s11 * v2 - v1 * s12) / det
end

-- The place whose straight distances to the flight masters fit the measured ones best (least squares). The flight
-- masters stand at much the same height, so a place below them fits nearly as well as its mirror image above them:
-- Gauss-Newton runs from four heights (HEIGHT_STARTS around their mean) and the best fit wins. Checked in a copy of
-- this calculation (28.11.2026) at 2,130 random places on the 71 floors with a world rectangle, both factions: always
-- the right place (from one start only, 12 to 23 % were wrong); with the distances rounded to whole yards (1,420
-- places) within 1.6 yards. Returns x, y, z and the misfit in yards.
local HEIGHT_STARTS = { -900, -300, 300, 900 }
function Locator.Solve(readings, startX, startY)
	if #readings < MIN_READINGS then return nil end
	local meanZ = 0
	for _, r in ipairs(readings) do meanZ = meanZ + r.z end
	meanZ = meanZ / #readings
	local sx, sy = linearStart(readings, meanZ)
	if not sx or sx ~= sx or sy ~= sy then sx, sy = startX or 0, startY or 0 end
	local best
	for _, dz in ipairs(HEIGHT_STARTS) do
		local x, y, z, misfit = newton(readings, sx, sy, meanZ + dz)
		if x and (not best or misfit < best[4]) then best = { x, y, z, misfit } end
	end
	if not best then return nil end
	return best[1], best[2], best[3], best[4]
end

local function inCombat()
	return DR.Safe(InCombatLockdown and InCombatLockdown()) == true
		or DR.Safe(UnitAffectingCombat and UnitAffectingCombat("player")) == true
end

-- Whether a round makes sense now.
function Locator:Wanted()
	if blocked or not supported() or not DR.db or DR.db.locate == false or not DR.db.showPlayer then return false end
	if not DR.currentKey or not DR.currentInstanceID or not DR.Window or not DR.Window:IsShown() then return false end
	local inInstance = DR.Safe(IsInInstance())
	if inInstance ~= true then return false end
	local x, y = UnitPosition("player")
	if type(DR.Safe(x)) == "number" and type(DR.Safe(y)) == "number" then return false end -- the game tells it
	if inCombat() or DR.Safe(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) == true then return false end
	return true
end

local function distanceNow()
	local d = DR.Safe(call(C_Navigation.GetDistance))
	if type(d) == "number" and d > 0 and d < 1e6 then return d end
	return nil
end

local function trackedIs(id)
	local kind, typeID = call(C_SuperTrack.GetSuperTrackedMapPin)
	return DR.Safe(kind) == TAXI and DR.Safe(typeID) == id
end

local function track(id)
	round.expect = id
	round.frames = 0
	call(C_SuperTrack.SetSuperTrackedMapPin, TAXI, id)
end

local function nextAnchor()
	round.i = round.i + 1
	while round.anchors[round.i] and refused[round.anchors[round.i]] do
		round.i = round.i + 1
	end
	local id = round.anchors[round.i]
	if id and #round.readings < ANCHORS then
		track(id)
		return true
	end
	return false
end

-- The round is over: the player's tracking comes back, the distances give a fix or none.
local function finish(why)
	local r = round
	round = nil
	restoreTracking(r.saved)
	waitUntil = now() + PAUSE
	local n = #r.readings
	if n == 0 then
		silent = silent + 1
		if silent >= GIVE_UP then blocked = "no answer" end
	else
		silent = 0
	end
	local x, y, z, residual = Locator.Solve(r.readings, r.mx, r.my)
	local good = x and residual <= MAX_RESIDUAL
	if good then
		fix = { x = x, y = y, z = z, instance = r.instance, t = now(), residual = residual, n = n }
		holding = false
	end
	local refusedCount = 0
	for _ in pairs(refused) do refusedCount = refusedCount + 1 end
	last = { readings = n, residual = residual, anchors = #r.anchors, refused = refusedCount,
		why = why or (good and "fix") or (x and "misfit") or "too few" }
end

-- Stop a round now: in combat, on leaving or when the setting goes off (the player's tracking comes back).
local function abort(why)
	if round then finish(why) end
end

-- A frame: the game's distance to the flight master tracked since the last frame, or wait for it.
local function step()
	local r = round
	r.frames = r.frames + 1
	local id = r.anchors[r.i]
	local d = distanceNow()
	if trackedIs(id) and d and d ~= r.previous then
		local node = DR.TaxiNodes[id]
		table.insert(r.readings, { x = node[3], y = node[4], z = node[5], d = d, id = id })
		r.previous = d
		if not nextAnchor() then finish() end
		return
	end
	if r.frames >= WAIT_FRAMES then
		if not trackedIs(id) then refused[id] = true end
		if not nextAnchor() then finish() end
	end
end

local function start()
	local instanceID = DR.currentInstanceID
	local anchors = pickAnchors(instanceID)
	if not anchors or #anchors < MIN_READINGS then return end
	local saved = noteTracking()
	if not saved then
		waitUntil = now() + BACK_OFF
		return
	end
	local mx, my = instanceMiddle(instanceID)
	round = { anchors = anchors, i = 0, readings = {}, saved = saved, instance = instanceID, mx = mx, my = my,
		previous = distanceNow() }
	if not nextAnchor() then
		round = nil
	end
end

local frame = CreateFrame("Frame")
Locator.frame = frame
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("SUPER_TRACKING_CHANGED")
frame:SetScript("OnEvent", function(_, event)
	if event == "SUPER_TRACKING_CHANGED" then
		-- while a round runs, only its own flight masters may be tracked: anything else is the player's (or another
		-- addon's) choice, which stays; no rounds for a while then
		if round then
			local kind, typeID = call(C_SuperTrack.GetSuperTrackedMapPin)
			kind, typeID = DR.Safe(kind), DR.Safe(typeID)
			local ours = false
			if kind == TAXI then
				for _, id in ipairs(round.anchors) do
					if id == typeID then ours = true break end
				end
			end
			if not ours then
				round = nil
				waitUntil = now() + BACK_OFF
			end
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		-- the fight is over: the kept place stays until the next fix, at most FRESH seconds
		holdUntil = now() + FRESH
		return
	end
	abort(event == "PLAYER_REGEN_DISABLED" and "combat" or "left")
	if event == "PLAYER_REGEN_DISABLED" then
		-- the last place stays on the map, faint (MapView), as long as the fight lasts
		holding, holdUntil = fix ~= nil, math.huge
	else
		fix, holding = nil, false
	end
end)
local IDLE_CHECK = 0.25 -- seconds between two looks whether a round is wanted
frame:SetScript("OnUpdate", function()
	if round then
		if not Locator:Wanted() then
			abort("paused")
			return
		end
		step()
	elseif now() >= waitUntil then
		if Locator:Wanted() then
			start()
		else
			waitUntil = now() + IDLE_CHECK
		end
	end
end)

-- Whether the place shown is the one kept from before a fight (no rounds in combat): the map draws it faint.
function Locator:Held()
	return holding and fix ~= nil and (inCombat() or now() <= holdUntil)
end

-- The position found, if it is fresh (or kept through a fight) and in the instance the player is in: x (north),
-- y (west), instanceID.
function Locator:Get()
	if not fix or blocked or not DR.db or DR.db.locate == false then return nil end
	if fix.instance ~= DR.currentInstanceID then return nil end
	if now() - fix.t > FRESH and not self:Held() then return nil end
	return fix.x, fix.y, fix.instance
end

-- For /fdr pos: a short line about the locator.
function Locator:Describe()
	if not supported() then return "locator: not available in this client" end
	if blocked then return "locator: stopped (" .. blocked .. ")" end
	local state = DR.db and DR.db.locate == false and "off" or (round and "measuring" or "on")
	local text = "locator: " .. state
	if fix then
		text = text .. (", fix %.1fs old, misfit %.1f yd from %d distances"):format(now() - fix.t, fix.residual, fix.n)
		if self:Held() then text = text .. ", kept through the fight" end
	end
	if last then
		text = text .. (", last round %s: %d distances, %d flight masters, %d refused"):format(tostring(last.why),
			last.readings, last.anchors, last.refused)
	end
	return text
end

-- For the tests: whether a round is under way, and the flight masters chosen for an instance.
function Locator:Busy()
	return round ~= nil
end
Locator.PickAnchors = pickAnchors

-- For the tests: forget everything (fix, refusals, stop) as after a reload.
function Locator:Reset()
	if round then finish("reset") end
	fix, blocked, silent, waitUntil, last = nil, nil, 0, 0, nil
	holding, holdUntil = false, 0
	anchorsFor, refused = {}, {}
end
