local _, DR = ...
local L = DR.L

-- Experiment: the own position inside dungeons through a minimap ping. The game gives addons no
-- position there, but the minimap still tells where the last ping lies relative to the player
-- (Minimap:GetPingPosition). One ping at a known place becomes an anchor; the player stands at
-- the anchor minus that offset. The known place is the dungeon entrance (start of the standard
-- route) or a place the player Ctrl-clicks on the map. The anchor ping goes diagonally a little
-- away from the player (each time in another direction) and so also shows how GetPingPosition
-- counts (pixels, parts of the minimap or yards). Off by default: the group sees and hears the
-- ping. If the game does not play along, the experiment stops with a message.
--
-- The state lives in the per-character saved variables, so it survives a /reload (the ping on
-- the minimap does as well).

local Ping = {}
DR.Ping = Ping

local UPDATE = 0.1          -- seconds between position updates
local ENTRY_DELAY = 0.5     -- seconds after entering before the anchor ping
local CALIBRATE_WAIT = 3    -- seconds to wait for the calibration ping to arrive
local SETTLE = 1            -- after this an unchanged but fitting reading counts (old ping on the same spot)
local JUMP_SPEED = 30       -- yards per second nobody walks in a dungeon: a new ping came in
local JUMP_MIN = 12         -- ... but never less than this many yards
local STATIC_MOVING = 4     -- seconds of walking after which an unchanged ping counts as stuck
local FACING_STEP = 1.5     -- yards of walking before the arrow turns to the walking direction
local MAX_AGE = 60 * 60     -- a saved anchor older than this is not used after /reload
local TOLERANCE = 0.15      -- calibration: how far the measured scale may be off

-- How GetPingPosition may count: value per minimap pixel, and back to yards.
-- w = minimap width in pixels, ypp = yards per minimap pixel at the current zoom.
local UNITS = {
	pixel = { perPixel = function() return 1 end, toYards = function(v, w, ypp) return v * ypp end },
	width = { perPixel = function(w) return 1 / w end, toYards = function(v, w, ypp) return v * w * ypp end },
	radius = { perPixel = function(w) return 2 / w end, toYards = function(v, w, ypp) return v * w / 2 * ypp end },
	yards = { perPixel = function(w, ypp) return ypp end, toYards = function(v) return v end },
}
local UNIT_ORDER = { "pixel", "width", "radius", "yards" }
-- Each anchor ping goes diagonally in the next of these directions, so a new ping never lands
-- where the last one from the same spot still sits.
local DIRECTIONS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

local frame = CreateFrame("Frame")
Ping.frame = frame
local elapsedSum = 0

local function state()
	return DR.cdb and DR.cdb.ping
end

local function readPing()
	local x, y = Minimap:GetPingPosition()
	x, y = DR.Safe(x), DR.Safe(y)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

-- Minimap width in pixels and yards per pixel at the current zoom.
local function minimapScale()
	local w = Minimap:GetWidth()
	local radius = C_Minimap and C_Minimap.GetViewRadius and DR.Safe(C_Minimap.GetViewRadius())
	if type(w) ~= "number" or w <= 0 or type(radius) ~= "number" or radius <= 0 then return nil end
	return w, radius / (w / 2)
end

-- Offset of the ping from the player in yards (east, north), from a raw reading.
local function offsetYards(s, x, y)
	local w, ypp = minimapScale()
	if not w then return nil end
	local unit = UNITS[s.units]
	local east, north
	if unit then
		east, north = unit.toYards(x * s.xSign, w, ypp), unit.toYards(y * s.ySign, w, ypp)
	else
		east, north = x * s.xSign / s.k * ypp, y * s.ySign / s.k * ypp
	end
	return east, north
end

function Ping:IsActive()
	local s = state()
	return s ~= nil and s.units ~= nil
end

-- The player's world position (north, west) and the walking direction, while the anchor works.
function Ping:Position()
	local s = state()
	if not s or not s.units or not s.lastNorth then return nil end
	return s.lastNorth, s.lastWest
end

function Ping:Facing()
	local s = state()
	return s and s.units and s.facing or nil
end

function Ping:Stop(message)
	if message then DR:Print(message) end
	if DR.cdb then DR.cdb.ping = nil end
	frame:SetScript("OnUpdate", nil)
end

local function run()
	elapsedSum = 0
	frame:SetScript("OnUpdate", function(_, elapsed) Ping:OnUpdate(elapsed) end)
end

-- Sends the anchor ping while the player stands at world position (north, west).
function Ping:Begin(north, west)
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("rotateMinimap") == "1" then
		return self:Stop(L["The position via minimap ping needs a minimap that does not rotate."])
	end
	local w, ypp = minimapScale()
	if not w then
		return self:Stop(L["The minimap ping gives no values here. The experiment stops."])
	end
	local beforeX, beforeY = readPing()
	DR.db.pingTurn = (DR.db.pingTurn or 0) % #DIRECTIONS + 1
	local dir = DIRECTIONS[DR.db.pingTurn]
	local dx, dy = w / 6 * dir[1], w / 6 * dir[2]
	Minimap:PingLocation(dx, dy)
	DR.cdb.ping = {
		instanceID = DR.currentInstanceID, calibrating = true, waited = 0, dx = dx, dy = dy, w = w, ypp = ypp,
		beforeX = beforeX, beforeY = beforeY, startNorth = north, startWest = west, time = time(),
	}
	run()
end

-- A reading that fits the diagonal calibration ping: both parts equally far.
local function fits(s, x, y)
	if x == 0 or y == 0 then return false end
	local kx, ky = x / s.dx, y / s.dy
	return math.abs(math.abs(ky) / math.abs(kx) - 1) <= 0.2
end

-- The calibration ping arrived: find the units and place the anchor.
local function calibrate(s, x, y)
	local kx, ky = x / s.dx, y / s.dy
	s.xSign, s.ySign = kx > 0 and 1 or -1, ky > 0 and 1 or -1
	s.k = math.abs(kx)
	s.units = "other"
	for _, name in ipairs(UNIT_ORDER) do
		local expect = UNITS[name].perPixel(s.w, s.ypp)
		if math.abs(s.k / expect - 1) <= TOLERANCE then
			s.units = name
			break
		end
	end
	-- the ping sits dx pixels east and dy pixels north of where the player stood
	s.pingNorth = s.startNorth + s.dy * s.ypp
	s.pingWest = s.startWest - s.dx * s.ypp
	s.lastNorth, s.lastWest = s.startNorth, s.startWest
	s.faceNorth, s.faceWest = s.startNorth, s.startWest
	s.calibrating, s.beforeX, s.beforeY = nil, nil, nil
	s.lastRawX, s.lastRawY = x, y
	s.walked, s.followed = 0, false
	DR:Print(L["Position via minimap ping started. Your group sees one ping. Ctrl-click on the map corrects your position."])
end

function Ping:OnUpdate(elapsed)
	elapsedSum = elapsedSum + elapsed
	if elapsedSum < UPDATE then return end
	local dt = elapsedSum
	elapsedSum = 0
	local s = state()
	if not s then
		frame:SetScript("OnUpdate", nil)
		return
	end
	if s.instanceID ~= DR.currentInstanceID then
		return self:Stop()
	end
	local x, y = readPing()
	if s.calibrating then
		s.waited = s.waited + dt
		local changed = x ~= s.beforeX or y ~= s.beforeY
		if x and fits(s, x, y) and (changed or s.waited >= SETTLE) then
			return calibrate(s, x, y)
		end
		if s.waited >= CALIBRATE_WAIT then
			if x and (x ~= 0 or y ~= 0) and changed then
				return self:Stop(L["The minimap ping answers in an unknown way. The experiment stops."])
			end
			return self:Stop(L["The minimap ping gives no values here. The experiment stops."])
		end
		return
	end
	if not x then return end
	local east, north = offsetYards(s, x, y)
	if not east then return end
	local pn, pw = s.pingNorth - north, s.pingWest + east
	-- Nobody walks this fast: someone pinged (or the minimap was clicked). The player stands
	-- where they stood, and the new ping is placed from there.
	local dn, dw = pn - s.lastNorth, pw - s.lastWest
	if math.sqrt(dn * dn + dw * dw) > math.max(JUMP_MIN, JUMP_SPEED * dt) then
		s.pingNorth, s.pingWest = s.pingNorth - dn, s.pingWest - dw
		pn, pw = s.lastNorth, s.lastWest
	end
	-- A ping that never changes while the player walks does not follow the player.
	if IsPlayerMoving and IsPlayerMoving() then
		if x == s.lastRawX and y == s.lastRawY then
			s.walked = s.walked + dt
			if not s.followed and s.walked >= STATIC_MOVING then
				return self:Stop(L["The minimap ping does not move along here. The experiment stops."])
			end
		else
			s.followed = true
		end
	end
	s.lastRawX, s.lastRawY = x, y
	-- walking direction for the arrow (the game keeps the facing secret in dungeons)
	local fn, fw = pn - s.faceNorth, pw - s.faceWest
	if fn * fn + fw * fw >= FACING_STEP * FACING_STEP then
		s.facing = math.atan2(fw, fn) % (2 * math.pi)
		s.faceNorth, s.faceWest = pn, pw
	end
	s.lastNorth, s.lastWest, s.time = pn, pw, time()
end

-- The dungeon entrance: the start of the main path of the first standard route.
local function entrance(key)
	local route = DR:GetBuiltInRoutes(key)[1]
	for _, path in ipairs(route and route.paths or {}) do
		if path.kind == "main" then
			return DR:FloorToWorld(path.floor, path.pts[1], path.pts[2])
		end
	end
	return nil
end

-- Ctrl-click on the map: the player stands here. With an anchor this only moves the anchor
-- (no new ping); without one it sends the anchor ping from here.
function Ping:SetHere(key, floor, u, v)
	if not DR.db.pingPosition or not key or key ~= DR.currentKey then return false end
	local north, west = DR:FloorToWorld(floor, u, v)
	if not north then return false end
	local s = state()
	if s and s.units and s.lastNorth then
		s.pingNorth = s.pingNorth + (north - s.lastNorth)
		s.pingWest = s.pingWest + (west - s.lastWest)
		s.lastNorth, s.lastWest = north, west
		s.faceNorth, s.faceWest = north, west
		DR:Print(L["Position set."])
		return true
	end
	self:Begin(north, west)
	return true
end

-- Entering, reloading or logging in.
function Ping:OnEnteringWorld(isInitialLogin, isReloadingUi)
	local s = state()
	if not DR.db.pingPosition or not DR.currentKey then
		if s then self:Stop() end
		return
	end
	if isReloadingUi and s and s.units and s.instanceID == DR.currentInstanceID
		and (time() - (s.time or 0)) <= MAX_AGE then
		run()
		return
	end
	if s then self:Stop() end
	local single = #DR:GetDungeonsForInstance(DR.currentInstanceID) == 1
	if isInitialLogin or isReloadingUi or not single or (IsPlayerMoving and IsPlayerMoving()) then
		DR:Print(L["Ctrl-click on the map where you stand to start your position."])
		return
	end
	local north, west = entrance(DR.currentKey)
	if north then
		self:Begin(north, west)
	end
end

-- A line for /fdr pos.
function Ping:Describe()
	if not DR.db.pingPosition then return "ping off" end
	local s = state()
	local x, y = readPing()
	local radius = C_Minimap and C_Minimap.GetViewRadius and DR.Safe(C_Minimap.GetViewRadius())
	local raw = x and ("%.4f %.4f"):format(x, y) or "-"
	if not s then return ("ping waiting, raw %s, radius %s"):format(raw, tostring(radius)) end
	if s.calibrating then return ("ping calibrating, raw %s"):format(raw) end
	return ("ping %s k %.4f signs %d %d, raw %s, radius %s, at %.1f %.1f"):format(s.units, s.k, s.xSign, s.ySign,
		raw, tostring(radius), s.lastNorth or 0, s.lastWest or 0)
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi)
	-- after Core has found the dungeon for this zone
	C_Timer.After(ENTRY_DELAY, function()
		if DR.db then Ping:OnEnteringWorld(isInitialLogin, isReloadingUi) end
	end)
end)

DR:On("SETTINGS_CHANGED", function(key)
	if key ~= "pingPosition" then return end
	if not DR.db.pingPosition then
		Ping:Stop()
	elseif DR.currentKey then
		DR:Print(L["Ctrl-click on the map where you stand to start your position."])
	end
end)

DR:On("DUNGEON_CHANGED", function(key)
	local s = state()
	if s and (not key or s.instanceID ~= DR.currentInstanceID) then
		Ping:Stop()
	end
end)
