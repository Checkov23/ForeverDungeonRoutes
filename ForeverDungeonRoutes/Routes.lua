local _, DR = ...
local L = DR.L

-- Route layout (built-in and user routes share it):
--   id      "default" (or "default:<variant>") for built-in routes, "u<number>" for user routes
--   builtin true for the routes that ship with the addon, they are read-only
--   name    route name; built-in routes are shown as "Standard route" plus their variant name
--   paths   { kind = "main"|"side", floor = uiMapID, t0, t1 (main only), title, pts = { x1, y1, x2, y2, ... } }
--   stops   { kind = "boss"|"rare"|"optional", floor, x, y, name, nameDE, note, noteDE,
--             encounters = { encounterID, ... } (the game's boss fights that tick the stop off) }
--   notes   { floor, x, y, text, textDE }
--   links   { floor, x, y, to = uiMapID, label }
-- Coordinates are normalized to the dungeon map (0..1 across the map art).

local IS_DE = GetLocale() == "deDE"

function DR.LocText(entry, field)
	if IS_DE then
		local de = entry[field .. "DE"]
		if de and de ~= "" then return de end
	end
	return entry[field]
end

-- Stops and notes can also show on twin floors with the same art (alt = { uiMapID, ... }).
function DR.OnFloor(entry, floor)
	if entry.floor == floor then return true end
	if entry.alt then
		for _, other in ipairs(entry.alt) do
			if other == floor then return true end
		end
	end
	return false
end

function DR:BuildIndex()
	self.byKey, self.byFloor = {}, {}
	for _, dungeon in ipairs(self.Dungeons) do
		self.byKey[dungeon.key] = dungeon
		for _, floor in ipairs(dungeon.floors) do
			self.byFloor[floor] = dungeon
		end
	end
end

function DR:GetDungeon(key)
	return key and self.byKey[key]
end

function DR:GetDungeonForFloor(floor)
	return floor and self.byFloor[floor]
end

function DR:GetKeyForFloor(floor)
	local dungeon = self:GetDungeonForFloor(floor)
	return dungeon and dungeon.key
end

-- All dungeons of an instance (Scarlet Monastery and Dire Maul have several wings).
function DR:GetDungeonsForInstance(instanceID)
	local list = {}
	if not instanceID then return list end
	for _, dungeon in ipairs(self.Dungeons) do
		if dungeon.instanceID == instanceID then
			table.insert(list, dungeon)
		end
	end
	return list
end

function DR:GetKeyName(key)
	local dungeon = self:GetDungeon(key)
	if dungeon then
		return (IS_DE and dungeon.nameDE) or dungeon.name
	end
	return key or ""
end

function DR:GetLevelText(key)
	local dungeon = self:GetDungeon(key)
	if dungeon and dungeon.levels then
		return L["Level"] .. " " .. dungeon.levels[1] .. "-" .. dungeon.levels[2]
	end
	return nil
end

function DR:GetFloorName(floor)
	local info = self.Floors[floor]
	if info then
		return (IS_DE and info.nameDE) or info.name
	end
	return tostring(floor)
end

function DR.FloorHasArt(floor)
	local info = floor and DR.Floors[floor]
	return info ~= nil and info.tiles ~= nil and #info.tiles == 12
end

-- Routes ----------------------------------------------------------------------------------

-- A dungeon has one built-in route or a list of them (Stratholme: living and undead side).
function DR:GetBuiltInRoutes(key)
	local builtIn = key and self.DefaultRoutes[key]
	if not builtIn then return {} end
	if builtIn.paths then return { builtIn } end
	return builtIn
end

function DR:GetRoutes(key)
	local list = {}
	if not key then return list end
	for _, route in ipairs(self:GetBuiltInRoutes(key)) do
		table.insert(list, route)
	end
	local user = self.db.routes[key]
	if user then
		local own = {}
		for _, route in pairs(user) do
			table.insert(own, route)
		end
		table.sort(own, function(a, b)
			if (a.created or 0) ~= (b.created or 0) then
				return (a.created or 0) < (b.created or 0)
			end
			return a.id < b.id
		end)
		for _, route in ipairs(own) do
			table.insert(list, route)
		end
	end
	return list
end

function DR:GetRoute(key, id)
	if not key or not id then return nil end
	for _, route in ipairs(self:GetBuiltInRoutes(key)) do
		if route.id == id then return route end
	end
	local user = self.db.routes[key]
	return user and user[id]
end

function DR:GetActiveRoute(key)
	if not key then return nil end
	local route = self:GetRoute(key, self.db.active[key])
	if route then return route end
	return self:GetRoutes(key)[1]
end

function DR:SetActiveRoute(key, id)
	self.db.active[key] = id
	self:Fire("ROUTE_CHANGED", key)
end

function DR:IsBuiltIn(route)
	return route ~= nil and route.builtin == true
end

function DR:GetRouteName(route)
	if not route then return "" end
	if route.builtin then
		local name = self.LocText(route, "name")
		if name and name ~= "" then
			return L["Standard route"] .. ": " .. name
		end
		return L["Standard route"]
	end
	if route.name and route.name ~= "" then
		return route.name
	end
	return L["Unnamed route"]
end

local function nextId()
	local id = "u" .. DR.db.nextRouteId
	DR.db.nextRouteId = DR.db.nextRouteId + 1
	return id
end

local function store(key, route)
	DR.db.routes[key] = DR.db.routes[key] or {}
	DR.db.routes[key][route.id] = route
	DR:SetActiveRoute(key, route.id)
	return route
end

function DR:NewRoute(key, name)
	return store(key, {
		id = nextId(), name = name or L["New route"], created = time(),
		paths = {}, stops = {}, notes = {}, links = {},
	})
end

function DR:CopyRoute(key, source)
	local copy = self.DeepCopy(source)
	copy.builtin = nil
	copy.nameDE = nil
	copy.id = nextId()
	copy.name = self:GetRouteName(source) .. " " .. L["(copy)"]
	copy.created = time()
	copy.basedOn = source.source or source.basedOn
	copy.source = nil
	return store(key, copy)
end

function DR:AddImportedRoute(key, route)
	route.id = nextId()
	route.created = time()
	return store(key, route)
end

function DR:RenameRoute(key, route, name)
	if self:IsBuiltIn(route) then return end
	route.name = name
	self:Fire("ROUTE_CHANGED", key)
end

function DR:DeleteRoute(key, route)
	if self:IsBuiltIn(route) then return end
	local user = self.db.routes[key]
	if not user or not user[route.id] then return end
	user[route.id] = nil
	if next(user) == nil then
		self.db.routes[key] = nil
	end
	if self.db.active[key] == route.id then
		self.db.active[key] = nil
	end
	self.cdb.progress[key] = nil
	self:Fire("ROUTE_CHANGED", key)
end

-- Spread the color gradient of the main path over its pieces in drawing order.
function DR:RecalcProgress(route)
	local total, lengths = 0, {}
	for i, path in ipairs(route.paths) do
		if path.kind == "main" then
			local len, pts = 0, path.pts
			for j = 3, #pts - 1, 2 do
				local dx, dy = pts[j] - pts[j - 2], (pts[j + 1] - pts[j - 1]) * (668 / 1002)
				len = len + math.sqrt(dx * dx + dy * dy)
			end
			lengths[i] = len
			total = total + len
		end
	end
	local run = 0
	for i, path in ipairs(route.paths) do
		if path.kind == "main" then
			path.t0 = total > 0 and run / total or 0
			run = run + lengths[i]
			path.t1 = total > 0 and run / total or 1
		end
	end
end

-- Labels for the stop pins: bosses are numbered in route order, rares get R, optional ones +.
function DR:GetStopLabels(route)
	local labels, n = {}, 0
	for i, stop in ipairs(route.stops) do
		if stop.kind == "boss" then
			n = n + 1
			labels[i] = tostring(n)
		elseif stop.kind == "rare" then
			labels[i] = "R"
		else
			labels[i] = "+"
		end
	end
	return labels
end

function DR:GetStopName(stop)
	local name = DR.LocText(stop, "name")
	if not name or name == "" then
		return L["Boss"]
	end
	return name
end

-- Boss fights (encounters) ----------------------------------------------------------------

-- The game's boss fights of a dungeon: { ids = { encounterID, ... }, name, nameDE } each.
function DR:GetEncounters(key)
	local dungeon = self:GetDungeon(key)
	return dungeon and self.Encounters[dungeon.instanceID] or {}
end

local function plain(text)
	return (text or ""):lower():gsub("[^%w]", "")
end

function DR:FindEncounterByName(key, name)
	local wanted = plain(name)
	if wanted == "" then return nil end
	for _, encounter in ipairs(self:GetEncounters(key)) do
		if plain(encounter.name) == wanted or plain(encounter.nameDE) == wanted then
			return encounter
		end
	end
	return nil
end

function DR:GetStopEncounter(key, stop)
	if not stop.encounters then return nil end
	for _, encounter in ipairs(self:GetEncounters(key)) do
		for _, id in ipairs(encounter.ids) do
			if id == stop.encounters[1] then return encounter end
		end
	end
	return nil
end

local function stopMatches(stop, encounterID, encounterName)
	if stop.encounters then
		for _, id in ipairs(stop.encounters) do
			if id == encounterID then return true end
		end
		return false
	end
	-- stops of own routes without a linked fight: the name decides
	local wanted = plain(encounterName)
	return wanted ~= "" and (plain(stop.name) == wanted or plain(stop.nameDE) == wanted)
end

-- The game reported a boss kill: tick off its stops in the active route of the current dungeon.
-- Returns how many stops were ticked.
local function hasEncounter(route, encounterID, encounterName)
	for _, stop in ipairs(route and route.stops or {}) do
		if stopMatches(stop, encounterID, encounterName) then return true end
	end
	return false
end

-- A boss of the current dungeon died: tick its stop off. In instances with several wings
-- (Scarlet Monastery, Dire Maul) a kill that belongs to another wing shows where the player
-- is, since the game gives no position there: the current dungeon switches to that wing.
function DR:MarkEncounterKilled(encounterID, encounterName)
	local key = self.currentKey
	if not key then return 0 end
	if not hasEncounter(self:GetActiveRoute(key), encounterID, encounterName) then
		for _, wing in ipairs(self:GetDungeonsForInstance(self.currentInstanceID)) do
			if wing.key ~= key and hasEncounter(self:GetActiveRoute(wing.key), encounterID, encounterName) then
				key = wing.key
				self.currentKey = key
				self.db.wings[self.currentInstanceID] = key
				self:Fire("DUNGEON_CHANGED", key)
				break
			end
		end
	end
	local route = self:GetActiveRoute(key)
	if not route then return 0 end
	local count = 0
	for i, stop in ipairs(route.stops) do
		if stopMatches(stop, encounterID, encounterName) and not self:IsStopDone(key, route, i) then
			self:SetStopDone(key, route, i, true)
			count = count + 1
		end
	end
	return count
end

-- The first floor of a route, so a freshly chosen route opens where it starts.
function DR:GetRouteStartFloor(route)
	if not route then return nil end
	for _, path in ipairs(route.paths) do
		if path.kind == "main" then return path.floor end
	end
	local first = route.paths[1] or route.stops[1] or route.notes[1]
	return first and first.floor
end

-- Progress (per character) ----------------------------------------------------------------

local function getProgress(key, route, create)
	local progress = DR.cdb.progress[key]
	if progress and progress.routeId ~= route.id then
		if not create then return nil end
		progress = nil
	end
	if not progress and create then
		progress = { routeId = route.id, done = {}, time = time() }
		DR.cdb.progress[key] = progress
	end
	return progress
end

function DR:IsStopDone(key, route, index)
	if not key or not route then return false end
	local progress = getProgress(key, route, false)
	return progress ~= nil and progress.done[index] == true
end

function DR:ToggleStopDone(key, route, index)
	self:SetStopDone(key, route, index, not self:IsStopDone(key, route, index))
end

function DR:SetStopDone(key, route, index, done)
	local progress = getProgress(key, route, true)
	progress.done[index] = done and true or nil
	progress.time = time()
	self:Fire("PROGRESS_CHANGED", key)
end

function DR:ResetProgress(key)
	self.cdb.progress[key] = nil
	self:Fire("PROGRESS_CHANGED", key)
end

function DR:GetNextStopIndex(key, route)
	if not route then return nil end
	for i, stop in ipairs(route.stops) do
		if stop.kind == "boss" and not self:IsStopDone(key, route, i) then
			return i
		end
	end
	return nil
end
