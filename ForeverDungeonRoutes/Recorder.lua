local _, DR = ...
local L = DR.L

-- A route from a run: while the player runs a dungeon, the addon writes down the rooms the game
-- names, which boss died in which room, and the stops ticked by hand. Afterwards one click turns
-- this into a route: the bosses where they fell, the path through the rooms in the order of the
-- run. Where the game names no room, a boss stands where the standard route has it. Good enough
-- for a first route of a new dungeon; the editor makes it fine.

local Recorder = {}
DR.Recorder = Recorder

local MAX_EVENTS = 400
local SPREAD = 0.025 -- bosses that fell in the same room stand side by side

local function current()
	return DR.cdb and DR.cdb.recording
end

local function start(key)
	DR.cdb.recording = { key = key, started = time(), time = time(), events = {} }
end

local function lastRoom(rec)
	for i = #rec.events, 1, -1 do
		if rec.events[i].room then return rec.events[i].room end
	end
	return nil
end

local function add(event)
	local rec = current()
	if not rec or rec.key ~= DR.currentKey or #rec.events >= MAX_EVENTS then return end
	rec.events[#rec.events + 1] = event
	rec.time = time()
end

local function roomNow(rec)
	local room = DR.Room:Get()
	return room and room.name or lastRoom(rec)
end

local function noteRoom()
	local rec, room = current(), DR.Room:Get()
	if rec and room and room.name ~= lastRoom(rec) then
		add({ room = room.name })
	end
end

-- Another dungeon, or the same one after a long pause (like the progress, Core.lua), starts a new
-- recording; so does "New run" inside.
DR:On("DUNGEON_CHANGED", function(key)
	if not key or not DR.cdb then return end
	local rec = current()
	if not rec or rec.key ~= key or time() - (rec.time or rec.started or 0) > DR.PROGRESS_MAX_AGE then
		start(key)
	end
	noteRoom()
end)

DR:On("RUN_RESET", function(key)
	if key and key == DR.currentKey then
		start(key)
		noteRoom()
	end
end)

DR:On("ROOM_CHANGED", noteRoom)

-- The game reports a kill twice (ENCOUNTER_END and BOSS_KILL), and a boss dies once a run.
DR:On("BOSS_KILLED", function(encounterID, name)
	local rec = current()
	if not rec or type(encounterID) ~= "number" then return end
	for _, e in ipairs(rec.events) do
		if e.kill == encounterID then return end
	end
	add({ kill = encounterID, name = name, room = roomNow(rec) })
end)

-- Rares and the like have no boss fight: a tick by hand marks them, at the place of their stop.
DR:On("STOP_DONE_BY_HAND", function(key, route, index, done)
	local rec = current()
	local stop = route and route.stops[index]
	if done and rec and key == DR.currentKey and stop and not stop.encounters and stop.kind ~= "boss" then
		add({ tick = stop.name or "", kind = stop.kind, floor = stop.floor, x = stop.x, y = stop.y, room = roomNow(rec) })
	end
end)

-- Building the route ------------------------------------------------------------------------------

function Recorder:CanBuild(key)
	local rec = current()
	if not rec or rec.key ~= key then return false end
	for _, e in ipairs(rec.events) do
		if e.kill or e.tick then return true end
	end
	return false
end

local function roomPoint(key, name)
	if not name then return nil end
	for _, room in ipairs(DR.Rooms[key] or {}) do
		if room.name == name then
			local floor = DR.Room:MainFloor(room)
			local x, y = DR.Room:Center(room, floor)
			if x then return floor, x, y end
		end
	end
	return nil
end

-- The stop of a standard route of the dungeon with this boss fight.
local function standardStop(key, encounterID)
	for _, route in ipairs(DR:GetRoutes(key)) do
		if DR:IsBuiltIn(route) then
			for _, stop in ipairs(route.stops) do
				for _, id in ipairs(stop.encounters or {}) do
					if id == encounterID then return stop end
				end
			end
		end
	end
	return nil
end

local function encounterFor(key, encounterID)
	for _, encounter in ipairs(DR:GetEncounters(key)) do
		for _, id in ipairs(encounter.ids) do
			if id == encounterID then return encounter end
		end
	end
	return nil
end

local function clamp(v)
	return math.max(0.01, math.min(0.99, v))
end

-- Turns the recording into an own route of the dungeon (active at once). Returns the route.
function Recorder:Build(key)
	if not self:CanBuild(key) then return nil end
	local rec = current()
	local dungeon = DR:GetDungeon(key)
	local points, stops, used, last = {}, {}, {}, nil
	for _, e in ipairs(rec.events) do
		local floor, x, y
		if e.kill then
			local standard = standardStop(key, e.kill)
			floor, x, y = roomPoint(key, e.room)
			if not floor and standard then floor, x, y = standard.floor, standard.x, standard.y end
			if not floor and last then floor, x, y = last[1], last[2], last[3] end
			if not floor then floor, x, y = dungeon.floors[1], 0.5, 0.5 end
			local spot = floor .. ":" .. math.floor(x * 200) .. ":" .. math.floor(y * 200)
			used[spot] = (used[spot] or -1) + 1
			local stop = { kind = standard and standard.kind or "boss", floor = floor,
				x = clamp(x + SPREAD * used[spot]), y = clamp(y) }
			local encounter = encounterFor(key, e.kill)
			if encounter then
				DR.SetNames(stop, encounter)
				stop.encounters = {}
				for i, id in ipairs(encounter.ids) do stop.encounters[i] = id end
			else
				stop.name, stop.encounters = e.name or "?", { e.kill }
			end
			stops[#stops + 1] = stop
			x, y = stop.x, stop.y -- the path leads to each boss
		elseif e.tick then
			floor, x, y = e.floor, e.x, e.y
			if not floor then floor, x, y = roomPoint(key, e.room) end
			if floor then
				stops[#stops + 1] = { kind = e.kind == "optional" and "optional" or "rare", floor = floor,
					x = clamp(x), y = clamp(y), name = e.tick }
			end
		elseif e.room then
			floor, x, y = roomPoint(key, e.room)
		end
		if floor then
			local p = points[#points]
			if not p or p[1] ~= floor or math.abs(p[2] - x) + math.abs(p[3] - y) > 0.002 then
				points[#points + 1] = { floor, clamp(x), clamp(y) }
			end
			last = points[#points]
		end
	end
	-- one main path per stretch on the same floor
	local paths, piece = {}, nil
	for _, p in ipairs(points) do
		if not piece or piece.floor ~= p[1] then
			if piece and #piece.pts >= 4 then paths[#paths + 1] = piece end
			piece = { kind = "main", floor = p[1], pts = {} }
		end
		piece.pts[#piece.pts + 1] = p[2]
		piece.pts[#piece.pts + 1] = p[3]
	end
	if piece and #piece.pts >= 4 then paths[#paths + 1] = piece end
	local route = {
		name = L["Recorded run %s"]:format(date("%Y-%m-%d %H:%M", rec.started)),
		paths = paths, stops = stops, notes = {}, links = {},
	}
	DR:RecalcProgress(route) -- the colour runs over the whole route
	DR:AddImportedRoute(key, route)
	DR:Print(L["Route made from your run: %s. Edit it to refine the paths."], DR:GetRouteName(route))
	return route
end
