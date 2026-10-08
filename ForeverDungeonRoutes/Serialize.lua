local _, DR = ...
local L = DR.L

-- Export format: "!FDR1!" followed by base64 of a small line based text:
--   K <key>            dungeon key
--   N <name>
--   P <kind> <floor> <x,y,x,y,...> [title]
--   S <kind> <floor> <x> <y> <name> [note] [encounterID,encounterID,...]
--   O <floor> <x> <y> <text>                 (note)
--   L <floor> <x> <y> <to> <label>           (link to another floor)
-- Fields are tab separated, coordinates are integers 0..10000.

local PREFIX = "!FDR1!"
local SCALE = 10000
local LIMITS = { paths = 300, points = 20000, stops = 120, notes = 200, links = 60, text = 200 }

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, 64 do
	B64_DECODE[B64:byte(i)] = i - 1
end

local function base64Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

local function base64Decode(text)
	text = text:gsub("%s", "")
	if #text % 4 ~= 0 or text:find("[^%w%+/=]") then
		return nil
	end
	local out = {}
	for i = 1, #text, 4 do
		local a, b, c, d = text:byte(i, i + 3)
		local va, vb = B64_DECODE[a], B64_DECODE[b]
		local vc, vd = B64_DECODE[c], B64_DECODE[d]
		if not va or not vb then return nil end
		local n = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
		if c ~= 61 then
			if not vc then return nil end
			out[#out + 1] = string.char(math.floor(n / 256) % 256)
		end
		if d ~= 61 then
			if not vd then return nil end
			out[#out + 1] = string.char(n % 256)
		end
	end
	return table.concat(out)
end

local function clean(text)
	text = tostring(text or "")
	text = text:gsub("[\t\r\n|]", " ")
	return text:sub(1, LIMITS.text)
end

local function int(v)
	return tostring(math.floor(DR.Clamp(v, 0, 1) * SCALE + 0.5))
end

function DR:ExportRoute(key, route)
	local lines = { "K\t" .. clean(key), "N\t" .. clean(self:GetRouteName(route)) }
	for _, path in ipairs(route.paths) do
		local nums = {}
		for i = 1, #path.pts do
			nums[i] = int(path.pts[i])
		end
		lines[#lines + 1] = table.concat({ "P", path.kind, tostring(path.floor), table.concat(nums, ","), clean(path.title) }, "\t")
	end
	for _, stop in ipairs(route.stops) do
		local fights = {}
		for i, id in ipairs(stop.encounters or {}) do
			fights[i] = tostring(id)
		end
		lines[#lines + 1] = table.concat({ "S", stop.kind, tostring(stop.floor), int(stop.x), int(stop.y),
			clean(stop.name), clean(self.LocText(stop, "note")), table.concat(fights, ",") }, "\t")
	end
	for _, note in ipairs(route.notes) do
		lines[#lines + 1] = table.concat({ "O", tostring(note.floor), int(note.x), int(note.y),
			clean(self.LocText(note, "text")) }, "\t")
	end
	for _, link in ipairs(route.links or {}) do
		lines[#lines + 1] = table.concat({ "L", tostring(link.floor), int(link.x), int(link.y),
			tostring(link.to), clean(link.label) }, "\t")
	end
	return PREFIX .. base64Encode(table.concat(lines, "\n"))
end

local VALID_PATH = { main = true, side = true }
local VALID_STOP = { boss = true, rare = true, optional = true }

local function split(line)
	local fields = {}
	for field in (line .. "\t"):gmatch("([^\t]*)\t") do
		fields[#fields + 1] = field
	end
	return fields
end

local function coord(text)
	local n = tonumber(text)
	if not n or n < 0 or n > SCALE then return nil end
	return n / SCALE
end

local function floorID(text)
	local n = tonumber(text)
	if not n or n < 1 or n ~= math.floor(n) then return nil end
	return n
end

local function validKey(key)
	return DR:GetDungeon(key) ~= nil
end

-- Returns key, route or nil, error message.
function DR:ImportRoute(text)
	text = strtrim(text or "")
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil, L["This is not a Forever Dungeon Routes export."]
	end
	local data = base64Decode(text:sub(#PREFIX + 1))
	if not data then
		return nil, L["The text is damaged or incomplete."]
	end
	local key
	local route = { paths = {}, stops = {}, notes = {}, links = {} }
	local points = 0
	for line in data:gmatch("[^\n]+") do
		local f = split(line)
		local tag = f[1]
		if tag == "K" then
			key = f[2]
		elseif tag == "N" then
			route.name = f[2]
		elseif tag == "P" then
			local floor = floorID(f[3])
			if not VALID_PATH[f[2]] or not floor then return nil, L["The text is damaged or incomplete."] end
			local pts = {}
			for num in (f[4] or ""):gmatch("[^,]+") do
				local v = coord(num)
				if not v then return nil, L["The text is damaged or incomplete."] end
				pts[#pts + 1] = v
			end
			if #pts >= 4 and #pts % 2 == 0 then
				points = points + #pts / 2
				local title = f[5] ~= "" and f[5] or nil
				table.insert(route.paths, { kind = f[2], floor = floor, title = title, pts = pts })
			end
		elseif tag == "S" then
			local floor, x, y = floorID(f[3]), coord(f[4]), coord(f[5])
			if not VALID_STOP[f[2]] or not floor or not x or not y then return nil, L["The text is damaged or incomplete."] end
			local note = f[7] ~= "" and f[7] or nil
			local stop = { kind = f[2], floor = floor, x = x, y = y, name = f[6] or "", note = note }
			for id in (f[8] or ""):gmatch("%d+") do
				stop.encounters = stop.encounters or {}
				if #stop.encounters < 8 then
					table.insert(stop.encounters, tonumber(id))
				end
			end
			table.insert(route.stops, stop)
		elseif tag == "O" then
			local floor, x, y = floorID(f[2]), coord(f[3]), coord(f[4])
			if not floor or not x or not y then return nil, L["The text is damaged or incomplete."] end
			table.insert(route.notes, { floor = floor, x = x, y = y, text = f[5] or "" })
		elseif tag == "L" then
			local floor, x, y, to = floorID(f[2]), coord(f[3]), coord(f[4]), floorID(f[5])
			if not floor or not x or not y or not to then return nil, L["The text is damaged or incomplete."] end
			table.insert(route.links, { floor = floor, x = x, y = y, to = to, label = f[6] or "" })
		end
		if #route.paths > LIMITS.paths or points > LIMITS.points or #route.stops > LIMITS.stops
			or #route.notes > LIMITS.notes or #route.links > LIMITS.links then
			return nil, L["The route is too large."]
		end
	end
	if not key or not validKey(key) then
		return nil, L["The text is damaged or incomplete."]
	end
	-- Only what lies on a floor of this dungeon can be shown.
	local dungeon = self:GetDungeon(key)
	for _, list in ipairs({ route.paths, route.stops, route.notes, route.links }) do
		for i = #list, 1, -1 do
			if self:GetDungeonForFloor(list[i].floor) ~= dungeon then
				table.remove(list, i)
			end
		end
	end
	-- names of the game's bosses come back in the player's language
	for _, stop in ipairs(route.stops) do
		local encounter = self:FindEncounterByName(key, stop.name)
		if encounter and encounter.name == stop.name and encounter.nameDE ~= stop.name then
			stop.nameDE = encounter.nameDE
		end
	end
	if #route.paths == 0 and #route.stops == 0 and #route.notes == 0 then
		return nil, L["The route is empty."]
	end
	self:RecalcProgress(route)
	return key, route
end
