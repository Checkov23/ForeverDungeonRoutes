local _, DR = ...

-- Where the player and the group stand on the dungeon map. WoW: Forever has no dungeon maps of
-- its own, so the world position (UnitPosition) is converted with the floor rectangles from
-- Data/Floors.lua. Floors of one dungeon often overlap in the world: the floor shown keeps the
-- position as long as it lies on it and its route is not clearly farther away than another one's.
-- Inside dungeons the game gives addons no position (nil since patch 7.1, secret values under
-- the Midnight rules); then nothing is shown and the window follows the boss kills instead.

local MARGIN = 0.02      -- a position this far outside a floor still counts as on it
local NEAR = 0.04        -- the shown floor stays while its route is this close (map widths)
local SWITCH_GAP = 0.05  -- another floor wins only when its route is this much closer
local ASPECT = 668 / 1002

-- UnitPosition returns the north coordinate first, then the west coordinate.
function DR:GetUnitWorldPosition(unit)
	local x, y, _, instanceID = UnitPosition(unit)
	x, y, instanceID = DR.Safe(x), DR.Safe(y), DR.Safe(instanceID)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return x, y, instanceID
end

function DR:WorldToFloor(floor, x, y)
	local info = self.Floors[floor]
	-- picture floors with a map turned against north (Data/Pictures.lua): straight from its frame
	local f = info and info.frame
	if f then
		return f[1] * x + f[2] * y + f[3], f[4] * x + f[5] * y + f[6]
	end
	local rect = info and info.world
	if not rect then return nil end
	local minX, minY, maxX, maxY = rect[1], rect[2], rect[3], rect[4]
	return (maxY - y) / (maxY - minY), (maxX - x) / (maxX - minX)
end

local function inside(u, v)
	return u >= -MARGIN and u <= 1 + MARGIN and v >= -MARGIN and v <= 1 + MARGIN
end

-- Distance from a map point to the active route of a floor, in map widths.
local function routeDistance(key, floor, u, v)
	local route = DR:GetActiveRoute(key)
	if not route then return math.huge end
	local best = math.huge
	local py = v * ASPECT
	for _, path in ipairs(route.paths) do
		if path.floor == floor then
			local pts = path.pts
			for j = 1, #pts - 3, 2 do
				local ax, ay = pts[j], pts[j + 1] * ASPECT
				local dx, dy = pts[j + 2] - ax, pts[j + 3] * ASPECT - ay
				local len2 = dx * dx + dy * dy
				local t = 0
				if len2 > 0 then
					t = DR.Clamp(((u - ax) * dx + (py - ay) * dy) / len2, 0, 1)
				end
				local qx, qy = ax + dx * t - u, ay + dy * t - py
				local d = qx * qx + qy * qy
				if d < best then best = d end
			end
		end
	end
	for _, stop in ipairs(route.stops) do
		if DR.OnFloor(stop, floor) then
			local qx, qy = stop.x - u, stop.y * ASPECT - py
			local d = qx * qx + qy * qy
			if d < best then best = d end
		end
	end
	return math.sqrt(best)
end

-- The floor of a dungeon a world position belongs to, with its map coordinates.
function DR:ChooseFloor(key, x, y, preferred)
	local dungeon = self:GetDungeon(key)
	if not dungeon then return nil end
	local candidates = {}
	for _, floor in ipairs(dungeon.floors) do
		local u, v = self:WorldToFloor(floor, x, y)
		if u and inside(u, v) then
			table.insert(candidates, { floor = floor, u = u, v = v })
		end
	end
	if #candidates == 0 then return nil end
	if #candidates == 1 then
		local only = candidates[1]
		return only.floor, only.u, only.v
	end
	local best, keep
	for _, c in ipairs(candidates) do
		c.dist = routeDistance(key, c.floor, c.u, c.v)
		if not best or c.dist < best.dist then best = c end
		if c.floor == preferred then keep = c end
	end
	if keep and (keep.dist <= NEAR or keep.dist <= best.dist + SWITCH_GAP) then
		return keep.floor, keep.u, keep.v
	end
	return best.floor, best.u, best.v
end

-- The wing the game's map names. Inside instances the game hides the position, but
-- C_Map.GetBestMapForUnit still names the map the player is on (the world map opens on it); in
-- Scarlet Monastery every wing has a map of its own (302 to 305). A map that only one wing of the
-- instance has tells the wing, any other map (or none yet) tells nothing.
function DR:WingFromMap(instanceID)
	local mapID = C_Map and C_Map.GetBestMapForUnit and DR.Safe(C_Map.GetBestMapForUnit("player"))
	if type(mapID) ~= "number" then return nil end
	local found
	for _, dungeon in ipairs(self:GetDungeonsForInstance(instanceID)) do
		for _, floor in ipairs(dungeon.floors) do
			if floor == mapID then
				if found and found ~= dungeon.key then return nil end
				found = dungeon.key
			end
		end
	end
	return found
end

-- The wing by the door used (since 1.2.2). In the antechambers of Scarlet Monastery the game names
-- neither a room nor the wing's map (Oliver, 14.11.2026), but outside, right before the loading
-- screen, the player stood in one of the wings' portals (Data/Entrances.lua: WingPortals). Where the
-- player stands on a zone map with such portals is noted before each loading screen and twice a
-- second outside instances; the portal nearest to it (within PORTAL_NEAR yards, seen in the last
-- PORTAL_FRESH seconds) tells the wing.
local PORTAL_NEAR, PORTAL_FRESH = 15, 120
local outside -- { map, x, y, t }: where the player last stood on a zone map with wing portals

function DR:NoteOutside()
	if DR.Safe(IsInInstance()) or not C_Map or not C_Map.GetPlayerMapPosition then return end
	for _, portals in pairs(DR.WingPortals or {}) do
		local pos = C_Map.GetPlayerMapPosition(portals.map, "player")
		local x, y = pos and DR.Safe(pos.x), pos and DR.Safe(pos.y)
		if type(x) == "number" and type(y) == "number" then
			outside = { map = portals.map, x = x, y = y, t = time() }
			return
		end
	end
end

-- Used once, on entering: the wing found is remembered (db.wings) and holds after that.
function DR:WingFromPortal(instanceID)
	local portals = DR.WingPortals and DR.WingPortals[instanceID]
	if not portals then return nil end
	local seen = outside
	outside = nil
	if not seen or seen.map ~= portals.map or time() - seen.t > PORTAL_FRESH then return nil end
	local best, bestDist
	for _, p in ipairs(portals) do
		local d = math.sqrt(((seen.x - p.x) * portals.w) ^ 2 + ((seen.y - p.y) * portals.h) ^ 2)
		if not bestDist or d < bestDist then best, bestDist = p.key, d end
	end
	if bestDist and bestDist <= PORTAL_NEAR then return best end
	return nil
end

local portalFrame = CreateFrame("Frame")
portalFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
portalFrame:SetScript("OnEvent", function() DR:NoteOutside() end)
local sinceNote = 0
portalFrame:SetScript("OnUpdate", function(_, elapsed)
	sinceNote = sinceNote + elapsed
	if sinceNote >= 0.5 then
		sinceNote = 0
		DR:NoteOutside()
	end
end)

-- The dungeon the player is in: by instance, and for instances with several wings (Scarlet
-- Monastery, Dire Maul) by the game's map (since 1.2.0; before, entering showed the wing seen last
-- until a room or a kill told the wing), by the door used (since 1.2.2), by position, else the wing
-- seen last.
function DR:FindCurrentDungeon(instanceID)
	local x, y, positionInstance = self:GetUnitWorldPosition("player")
	instanceID = instanceID or positionInstance
	local list = self:GetDungeonsForInstance(instanceID)
	if #list == 0 then return nil end
	if #list == 1 then return list[1].key end
	local byMap = self:WingFromMap(instanceID) or self:WingFromPortal(instanceID)
	if byMap then
		self.db.wings[instanceID] = byMap
		return byMap
	end
	if x then
		local bestKey, bestDist
		for _, dungeon in ipairs(list) do
			local floor, u, v = self:ChooseFloor(dungeon.key, x, y)
			if floor then
				local d = routeDistance(dungeon.key, floor, u, v)
				if not bestDist or d < bestDist then
					bestKey, bestDist = dungeon.key, d
				end
			end
		end
		if bestKey then
			self.db.wings[instanceID] = bestKey
			return bestKey
		end
	end
	local remembered = self.db.wings[instanceID]
	if self:GetDungeon(remembered) then return remembered end
	return list[1].key
end

-- Where the player is: dungeon key, floor and map coordinates. Floor and coordinates are nil
-- when the game does not reveal the position.
function DR:LocatePlayer(preferredFloor)
	local key = self.currentKey
	if not key then return nil end
	local x, y = self:GetUnitWorldPosition("player")
	if not x then return key end
	local floor, u, v = self:ChooseFloor(key, x, y, preferredFloor)
	-- Entering a wing the position may come late; once it is there it decides the wing.
	if not floor and #self:GetDungeonsForInstance(self.currentInstanceID) > 1 then
		local wing = self:FindCurrentDungeon(self.currentInstanceID)
		if wing and wing ~= key then
			self.currentKey = wing
			self:Fire("DUNGEON_CHANGED", wing)
			floor, u, v = self:ChooseFloor(wing, x, y)
			return wing, floor, u, v
		end
	end
	return key, floor, u, v
end

function DR:GetPlayerFacing()
	local facing = DR.Safe(GetPlayerFacing())
	if type(facing) ~= "number" then return nil end
	return facing
end

-- Group members whose position lies on the floor: { u, v, r, g, b } each.
function DR:GroupOnFloor(floor)
	local list = {}
	for i = 1, 4 do
		local unit = "party" .. i
		if DR.Safe(UnitExists(unit)) then
			local x, y = self:GetUnitWorldPosition(unit)
			local u, v
			if x then
				u, v = self:WorldToFloor(floor, x, y)
			end
			if u and inside(u, v) then
				local _, class = UnitClass(unit)
				class = DR.Safe(class)
				local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				table.insert(list, {
					u = u, v = v,
					r = color and color.r or 0.55, g = color and color.g or 0.78, b = color and color.b or 1,
				})
			end
		end
	end
	return list
end
