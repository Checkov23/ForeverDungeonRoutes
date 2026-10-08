local _, DR = ...
local L = DR.L

-- Route layout (built-in and user routes share it):
--   id      "default" (or "default:<variant>") for built-in routes, "u<number>" for user routes
--   builtin true for the routes that ship with the addon, they are read-only
--   name    route name; built-in routes are shown as "Standard route" plus their variant name
--   paths   { kind = "main"|"side", floor = uiMapID, t0, t1 (main only), title, pts = { x1, y1, x2, y2, ... } }
--   stops   { kind = "boss"|"rare"|"optional", floor, x, y, name, note, noteDE }
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

-- The world map can only show maps with art layers. In WoW Forever the dungeon art comes from
-- an addon such as MapUtils.
function DR.MapHasArt(mapID)
	if not mapID then return false end
	local layers = C_Map.GetMapArtLayers(mapID)
	return type(layers) == "table" and layers[1] ~= nil
end

-- Stops and notes can also show on twin maps with the same art (alt = { uiMapID, ... }).
function DR.OnFloor(entry, mapID)
	if entry.floor == mapID then return true end
	if entry.alt then
		for _, floor in ipairs(entry.alt) do
			if floor == mapID then return true end
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

function DR:GetDungeonForMap(mapID)
	return mapID and self.byFloor[mapID]
end

-- Which route set belongs to this map? Built-in dungeons first, then floors the player has
-- visited inside an unknown dungeon, then routes made directly on this map.
function DR:GetKeyForMap(mapID)
	if not mapID then return nil end
	local dungeon = self.byFloor[mapID]
	if dungeon then return dungeon.key end
	local learned = self.db.learnedFloors[mapID]
	if learned then return learned end
	local own = "map:" .. mapID
	if self.db.routes[own] then return own end
	return nil
end

function DR:GetKeyForInstance(instanceID, mapID)
	local key = self:GetKeyForMap(mapID)
	if key then return key end
	local found
	for _, dungeon in ipairs(self.Dungeons) do
		if dungeon.instanceID == instanceID then
			if found then
				found = nil -- several wings share this instance, the floor decides
				break
			end
			found = dungeon.key
		end
	end
	if found then return found end
	if instanceID then return "instance:" .. instanceID end
	return nil
end

-- Key for a map that has no route set yet, used when the player starts a new route there.
function DR:GetOrCreateKeyForMap(mapID)
	local key = self:GetKeyForMap(mapID)
	if key then return key end
	local inInstance = IsInInstance()
	local playerMap = C_Map.GetBestMapForUnit("player")
	if inInstance and playerMap == mapID then
		key = "instance:" .. select(8, GetInstanceInfo())
		self.db.learnedFloors[mapID] = key
		return key
	end
	return "map:" .. mapID
end

function DR:GetKeyName(key)
	if not key then return "" end
	local dungeon = self.byKey[key]
	if dungeon then
		return (IS_DE and dungeon.nameDE) or dungeon.name
	end
	local instanceID = key:match("^instance:(%d+)$")
	if instanceID then
		local name = GetRealZoneText(tonumber(instanceID))
		if name and name ~= "" then return name end
	end
	local mapID = key:match("^map:(%d+)$")
	if mapID then
		local info = C_Map.GetMapInfo(tonumber(mapID))
		if info and info.name then return info.name end
	end
	return key
end

function DR:GetShownKey()
	if WorldMapFrame and WorldMapFrame:IsShown() then
		local key = self:GetKeyForMap(WorldMapFrame:GetMapID())
		if key then return key end
	end
	return self.currentKey
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
				local dx, dy = pts[j] - pts[j - 2], (pts[j + 1] - pts[j - 1]) * (683 / 1024)
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
	local progress = getProgress(key, route, true)
	if progress.done[index] then
		progress.done[index] = nil
	else
		progress.done[index] = true
	end
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
