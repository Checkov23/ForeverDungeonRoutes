local _, DR = ...

-- Where the player and the group stand on the dungeon map. WoW: Forever has no dungeon maps of
-- its own, so the world position (UnitPosition) is converted with the floor rectangles from
-- Data/Floors.lua. Floors of one dungeon often overlap in the world: the floor shown keeps the
-- position as long as it lies on it and its route is not clearly farther away than another one's.
-- In restricted instances the game keeps positions secret; then nothing is shown.

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

-- The dungeon the player is in: by instance, and for instances with several wings (Scarlet
-- Monastery, Dire Maul) by position, else the wing seen last.
function DR:FindCurrentDungeon(instanceID)
	local x, y, positionInstance = self:GetUnitWorldPosition("player")
	instanceID = instanceID or positionInstance
	local list = self:GetDungeonsForInstance(instanceID)
	if #list == 0 then return nil end
	if #list == 1 then return list[1].key end
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
