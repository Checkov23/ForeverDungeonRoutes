local _, DR = ...
local L = DR.L

-- The route list: own routes that players put up for everyone, to take over with one click.
-- Blizzard lets addons talk to the group, the guild and single players, but not send hidden
-- messages to a chat channel (since Classic 1.13.3). So the list travels three ways:
--   guild    putting a route in the list tells the guild members online, and so does logging in
--   group    joining a party asks the others for their routes
--   channel  "Refresh the list" posts a short line in the chat channel FDRoutes, which the addon
--            joins and hides; every addon there answers with whispers
-- Only short entries travel like this. The route itself comes by whisper from a player who has
-- it (its author, or someone who took it over and so can hand it on), once someone takes it over.
--
-- Addon messages (prefix FDRList, fields separated by tabs):
--   L <key> <hash> <stops> <author> <name> <likes>   a route in the list (likes: as its author counts them)
--   Q [<key>]                                 which routes do you have (of this dungeon)?
--   G <hash>                                  send me this route (whisper)
--   T <hash> <index> <parts> <piece>          a piece of its export text (whisper)
--   V <hash>                                  I recommend your route (whisper to its author)
--   A <hash>                                  recommendation received (the author's answer)
-- In the channel the line "FDR:Q" (optionally followed by a dungeon key) asks everyone there.

local PREFIX = "FDRList"
local CHANNEL = "FDRoutes"
local REQUEST = "FDR:Q"
local PIECE = 220           -- characters of export text per message
local MAX_PARTS = 300
local MAX_ENTRIES = 300     -- routes of others the list remembers
local MAX_HOLDERS = 5       -- players remembered per route who can hand it on
local ANSWER_ENTRIES = 12   -- entries in one answer
local ANSWER_DELAY = 4      -- answers wait up to this many seconds, so not all arrive at once
local QUIET = 60            -- seconds before the same player gets another answer or the same route
local FETCH_TIMEOUT = 10    -- seconds without a piece before asking the next player who has it
local GROUP_ASK = 120       -- seconds between two asks in the same group

local List = {}
DR.RouteList = List

local lastAnswer, lastServe = {}, {}
local fetch -- the route being taken over: { hash, holders, next, from, pieces, got, parts, last }

-- A short fingerprint of an export text: two polynomial hashes. Floats stay exact up to 2^53 in
-- every Lua, and both parts stay below 2^31, where "%x" works everywhere (also with a 32-bit long).
function List.Hash(text)
	local a, b = 0.0, 0.0
	for i = 1, #text do
		local c = text:byte(i)
		a = (a * 31 + c) % 2147483647
		b = (b * 131 + c) % 2147483629
	end
	return ("%08x%08x"):format(a, b)
end

-- Text for a message field: no tabs, line breaks or "|", at most n bytes and no cut letter.
local function clean(s, n)
	s = tostring(s or ""):gsub("[\t\r\n|]", " ")
	if #s <= n then return s end
	s = s:sub(1, n)
	for i = #s, math.max(1, #s - 3), -1 do
		local c = s:byte(i)
		if c < 0x80 then break end
		if c >= 0xC0 then
			local length = c >= 0xF0 and 4 or c >= 0xE0 and 3 or 2
			if #s - i + 1 < length then s = s:sub(1, i - 1) end
			break
		end
	end
	return s
end

local function me()
	local name = DR.Safe(UnitName("player")) or "?"
	local realm = GetNormalizedRealmName and DR.Safe(GetNormalizedRealmName())
	if type(realm) == "string" and realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

-- Whispers of the list can go to players who went offline since. The game then prints "No player
-- named ... is currently playing", which would only puzzle here (see the filter below).
local whispered = {} -- [player] = time of the last whisper

local function send(channel, texts, target)
	if channel == "WHISPER" and target then whispered[target] = time() end
	DR.Share:Queue(PREFIX, channel, texts, target)
end

local function entryMessage(key, hash, stops, author, name, likes)
	return table.concat({ "L", key, hash, tostring(stops), clean(author, 48), clean(name, 50), tostring(likes or 0) }, "\t")
end

-- Recommendations of an own route: the author's addon counts them, at the route itself, so they
-- stay when the author improves the route.
local function likesOf(route)
	local n = 0
	for _ in pairs(route.likes or {}) do n = n + 1 end
	return n
end

-- Own routes in the list (of one dungeon or all): { key, route, text, hash }.
local function published(key)
	local out = {}
	for dungeonKey, ids in pairs(DR.db.published) do
		if not key or dungeonKey == key then
			for id in pairs(ids) do
				local route = DR:GetRoute(dungeonKey, id)
				if route and not DR:IsBuiltIn(route) then
					local text = DR:ExportRoute(dungeonKey, route)
					out[#out + 1] = { key = dungeonKey, route = route, text = text, hash = List.Hash(text) }
				else
					ids[id] = nil -- deleted since
				end
			end
		end
	end
	return out
end

-- The entries this addon can hand on: own routes first, then routes of others it has the text of
-- (not for the whole server channel: there only the authors answer, so a request stays small).
local function offerable(key, ownOnly)
	local texts = {}
	for _, p in ipairs(published(key)) do
		if #texts >= ANSWER_ENTRIES then break end
		texts[#texts + 1] = entryMessage(p.key, p.hash, #p.route.stops, me(), DR:GetRouteName(p.route), likesOf(p.route))
	end
	if ownOnly then return texts end
	local cached = {}
	for hash, e in pairs(DR.db.list) do
		if e.text and (not key or e.key == key) then cached[#cached + 1] = hash end
	end
	table.sort(cached, function(a, b) return (DR.db.list[a].seen or 0) > (DR.db.list[b].seen or 0) end)
	for _, hash in ipairs(cached) do
		if #texts >= ANSWER_ENTRIES then break end
		local e = DR.db.list[hash]
		texts[#texts + 1] = entryMessage(e.key, hash, e.stops, e.author, e.name, e.likes)
	end
	return texts
end

-- Forget the oldest routes when the list grows too long (first those it cannot hand on).
local function trim()
	local hashes = {}
	for hash in pairs(DR.db.list) do hashes[#hashes + 1] = hash end
	if #hashes <= MAX_ENTRIES then return end
	table.sort(hashes, function(a, b)
		local ea, eb = DR.db.list[a], DR.db.list[b]
		if (ea.text ~= nil) ~= (eb.text ~= nil) then return eb.text ~= nil end
		return (ea.seen or 0) < (eb.seen or 0)
	end)
	for i = 1, #hashes - MAX_ENTRIES do
		DR.db.list[hashes[i]] = nil
	end
end

-- Publishing --------------------------------------------------------------------------------------

function List:IsPublished(key, route)
	return route ~= nil and DR.db.published[key] ~= nil and DR.db.published[key][route.id] == true
end

-- Puts an own route in the list (or takes it out) and tells guild and group at once.
function List:Publish(key, route, on)
	if not key or not route or DR:IsBuiltIn(route) then return end
	DR.db.published[key] = DR.db.published[key] or {}
	DR.db.published[key][route.id] = on and true or nil
	local name = DR:GetRouteName(route)
	if on then
		local hash = List.Hash(DR:ExportRoute(key, route))
		local message = entryMessage(key, hash, #route.stops, me(), name, likesOf(route))
		if DR.Share:InGuild() then send("GUILD", { message }) end
		local group = DR.Share:Channel()
		if group then send(group, { message }) end
		DR:Print(L["\"%s\" is in the route list now."], name)
	else
		DR:Print(L["\"%s\" is no longer in the route list."], name)
	end
	DR:Fire("ROUTE_LIST_CHANGED", key)
end

-- Routes of others for a dungeon, newest first: { hash, entry }.
function List:Entries(key)
	local own = {}
	for _, p in ipairs(published(key)) do own[p.hash] = true end
	local out, myself = {}, me()
	for hash, e in pairs(DR.db.list) do
		-- not the own ones, also not those taken out of the list again that others still hand on
		if e.key == key and not own[hash] and e.author ~= myself then out[#out + 1] = { hash = hash, entry = e } end
	end
	-- recommended routes first, then the newest
	table.sort(out, function(a, b)
		local la, lb = a.entry.likes or 0, b.entry.likes or 0
		if la ~= lb then return la > lb end
		return (a.entry.seen or 0) > (b.entry.seen or 0)
	end)
	return out
end

-- The channel ---------------------------------------------------------------------------------

local function channelId()
	local id = GetChannelName and DR.Safe(GetChannelName(CHANNEL))
	if type(id) == "number" and id > 0 then return id end
	return nil
end

-- The channel is for the addon: its lines do not show in the chat windows.
local function hideChannel()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.RemoveChannel then
			pcall(frame.RemoveChannel, frame, CHANNEL)
		elseif frame and ChatFrame_RemoveChannel then
			pcall(ChatFrame_RemoveChannel, frame, CHANNEL)
		end
	end
end

local function joinChannel()
	if not DR.db.listChannel or channelId() then return end
	local join = JoinTemporaryChannel or JoinChannelByName or JoinPermanentChannel
	if join then
		pcall(join, CHANNEL)
		C_Timer.After(1, hideChannel)
	end
end

local function leaveChannel()
	if channelId() and LeaveChannelByName then
		pcall(LeaveChannelByName, CHANNEL)
	end
end

function List:SetChannel(on)
	if on then joinChannel() else leaveChannel() end
end

local function isOurChannel(channelName, baseName)
	baseName, channelName = DR.Safe(baseName), DR.Safe(channelName)
	if type(baseName) == "string" and baseName ~= "" then return baseName == CHANNEL end
	return type(channelName) == "string" and (channelName == CHANNEL or channelName:match("^%d+%. (.+)$") == CHANNEL)
end

local function filter(_, _, _, _, _, channelName, _, _, _, _, baseName)
	return isOurChannel(channelName, baseName)
end
-- "No player named ... is currently playing" right after a whisper of the list
local function offlineFilter(_, _, text)
	text = DR.Safe(text)
	if type(text) ~= "string" or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return false end
	local now = time()
	for player, at in pairs(whispered) do
		if now - at > 30 then
			whispered[player] = nil
		elseif text == ERR_CHAT_PLAYER_NOT_FOUND_S:format(player)
			or text == ERR_CHAT_PLAYER_NOT_FOUND_S:format((player:match("^[^-]+"))) then
			return true
		end
	end
	return false
end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
	for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
		"CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
		addFilter(event, filter)
	end
	addFilter("CHAT_MSG_SYSTEM", offlineFilter)
end

-- Asking and answering ------------------------------------------------------------------------

-- Asks guild, group and the channel for routes (of the shown dungeon). Called by a click: the
-- game lets addons write in a chat channel only then.
function List:Refresh(key)
	local ask = "Q\t" .. (key or "")
	local group = DR.Share:Channel()
	if group then send(group, { ask }) end
	if DR.Share:InGuild() then send("GUILD", { ask }) end
	local id = DR.db.listChannel and channelId()
	if id and not (C_ChatInfo.InChatMessagingLockdown and DR.Safe(C_ChatInfo.InChatMessagingLockdown())) then
		pcall(C_ChatInfo.SendChatMessage, REQUEST .. (key and (" " .. key) or ""), "CHANNEL", nil, id)
	end
	DR:Print(L["Asking for routes ..."])
end

local function answer(player, key, ownOnly)
	local now = time()
	if lastAnswer[player] and now - lastAnswer[player] < QUIET then return end
	lastAnswer[player] = now
	local texts = offerable(key, ownOnly)
	if #texts > 0 then
		C_Timer.After(math.random() * ANSWER_DELAY, function() send("WHISPER", texts, player) end)
	end
end

local function learn(sender, f)
	local key, hash, stops = f[2], f[3], tonumber(f[4])
	if not DR:GetDungeon(key) or type(hash) ~= "string" or #hash ~= 16 or hash:find("[^%x]")
		or not stops or stops < 1 or stops > 500 then
		return
	end
	local e = DR.db.list[hash]
	if not e then
		e = { holders = {} }
		DR.db.list[hash] = e
	end
	e.key, e.stops, e.seen = key, math.floor(stops), time()
	e.author = clean(f[5] ~= nil and f[5] ~= "" and f[5] or sender, 48)
	e.name = clean(f[6] ~= nil and f[6] ~= "" and f[6] or "?", 50)
	-- the author's own count is right; a count handed on by others only fills a gap
	local likes = tonumber(f[7])
	if likes and likes >= 0 and likes < 100000 and (sender == e.author or not e.likes) then
		e.likes = math.floor(likes)
	end
	-- a recommendation the author has not confirmed yet: once more, now that the author is here
	if sender == e.author and DR.db.liked[hash] == "sent" then
		send("WHISPER", { "V\t" .. hash }, sender)
	end
	for i = #e.holders, 1, -1 do
		if e.holders[i] == sender then table.remove(e.holders, i) end
	end
	table.insert(e.holders, 1, sender)
	while #e.holders > MAX_HOLDERS do table.remove(e.holders) end
	trim()
	DR:Fire("ROUTE_LIST_CHANGED", key)
end

-- Sends a route this addon has (own in the list, or taken over from the list) to whoever asked.
local function serve(player, hash)
	local now = time()
	local id = player .. hash
	if lastServe[id] and now - lastServe[id] < QUIET then return end
	local text
	for _, p in ipairs(published()) do
		if p.hash == hash then text = p.text end
	end
	if not text and DR.db.list[hash] then text = DR.db.list[hash].text end
	if not text then return end
	local parts = math.ceil(#text / PIECE)
	if parts > MAX_PARTS then return end
	lastServe[id] = now
	local texts = {}
	for i = 1, parts do
		texts[i] = table.concat({ "T", hash, tostring(i), tostring(parts), text:sub((i - 1) * PIECE + 1, i * PIECE) }, "\t")
	end
	send("WHISPER", texts, player)
end

-- Taking over -------------------------------------------------------------------------------------

local function takeOver(hash, text, from)
	local e = DR.db.list[hash]
	local key, route = DR:ImportRoute(text)
	if not key or not e or key ~= e.key then
		DR:Print(L["%s sent a route that could not be read."], DR.Share.SenderName(from or "?"))
		return
	end
	e.text = text -- so this addon can hand it on as well
	local existing = DR.Share.SameRoute(key, text)
	if existing then
		existing.listHash, existing.listAuthor = hash, e.author
		DR:SetActiveRoute(key, existing.id)
		DR:Print(L["You already have this route; it is now active."])
	else
		route.listHash, route.listAuthor = hash, e.author
		DR:AddImportedRoute(key, route)
		DR:Print(L["Route from %s taken over: %s"], DR.Share.SenderName(e.author or from or "?"), DR:GetRouteName(route))
	end
	DR:Fire("ROUTE_LIST_CHANGED", key)
end

local function askNext()
	if not fetch then return end
	local holder = fetch.holders[fetch.next]
	if not holder then
		DR:Print(L["Nobody who has this route answered. Try again later."])
		fetch = nil
		return
	end
	fetch.next = fetch.next + 1
	fetch.from, fetch.pieces, fetch.got, fetch.parts, fetch.last = holder, {}, 0, nil, time()
	DR:Print(L["Fetching the route from %s ..."], DR.Share.SenderName(holder))
	send("WHISPER", { "G\t" .. fetch.hash }, holder)
	local current = fetch
	local function watch()
		if fetch ~= current or fetch.from ~= holder then return end
		if time() - fetch.last >= FETCH_TIMEOUT then
			askNext()
		else
			C_Timer.After(2, watch)
		end
	end
	C_Timer.After(2, watch)
end

-- Takes a route of the list over: at once when this addon has its text, else from a player who has it.
function List:Fetch(hash)
	local e = DR.db.list[hash]
	if not e then return end
	if e.text then
		takeOver(hash, e.text, e.author)
		return
	end
	local holders = {}
	for _, h in ipairs(e.holders) do holders[#holders + 1] = h end
	fetch = { hash = hash, holders = holders, next = 1 }
	askNext()
end

local function piece(sender, f)
	local hash, index, parts = f[2], tonumber(f[3]), tonumber(f[4])
	if not fetch or fetch.hash ~= hash or fetch.from ~= sender or not index or not parts
		or parts < 1 or parts > MAX_PARTS or index < 1 or index > parts or index ~= math.floor(index) then
		return
	end
	if fetch.parts and fetch.parts ~= parts then return end
	fetch.parts = parts
	if fetch.pieces[index] then return end
	fetch.pieces[index] = f[5] or ""
	fetch.got = fetch.got + 1
	fetch.last = time()
	if fetch.got == parts then
		local text = table.concat(fetch.pieces)
		local done = fetch
		fetch = nil
		if List.Hash(text) ~= done.hash then
			DR:Print(L["%s sent a route that could not be read."], DR.Share.SenderName(sender))
			return
		end
		takeOver(done.hash, text, sender)
	end
end

-- Recommending -------------------------------------------------------------------------------------

-- Recommends a route taken over from the list, once: the author's addon counts it.
function List:Recommend(route)
	local hash, author = route and route.listHash, route and route.listAuthor
	if not hash or not author or DR.db.liked[hash] then return end
	DR.db.liked[hash] = "sent"
	local e = DR.db.list[hash]
	if e then e.likes = (e.likes or 0) + 1 end
	send("WHISPER", { "V\t" .. hash }, author)
	DR:Print(L["Recommended. %s gets it when online."], DR.Share.SenderName(author))
	DR:Fire("ROUTE_LIST_CHANGED", e and e.key)
end

local function recommended(sender, hash)
	for _, p in ipairs(published()) do
		if p.hash == hash then
			p.route.likes = p.route.likes or {}
			p.route.likes[sender] = true
			send("WHISPER", { "A\t" .. hash }, sender)
			return
		end
	end
end

-- Messages ----------------------------------------------------------------------------------------

function List:OnMessage(prefix, text, channel, sender)
	prefix, text, channel, sender = DR.Safe(prefix), DR.Safe(text), DR.Safe(channel), DR.Safe(sender)
	if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or DR.Share.IsMe(sender) then
		return
	end
	local f = {}
	for field in (text .. "\t"):gmatch("([^\t]*)\t") do
		f[#f + 1] = field
	end
	if f[1] == "L" then
		learn(sender, f)
	elseif f[1] == "Q" then
		answer(sender, f[2] ~= "" and DR:GetDungeon(f[2] or "") and f[2] or nil)
	elseif f[1] == "G" and channel == "WHISPER" then
		serve(sender, f[2] or "")
	elseif f[1] == "T" and channel == "WHISPER" then
		piece(sender, f)
	elseif f[1] == "V" and channel == "WHISPER" then
		recommended(sender, f[2] or "")
	elseif f[1] == "A" and channel == "WHISPER" and DR.db.liked[f[2] or ""] then
		DR.db.liked[f[2]] = "done"
	end
end

function List:OnChannelLine(text, player, channelName, baseName)
	text, player = DR.Safe(text), DR.Safe(player)
	if type(text) ~= "string" or type(player) ~= "string" or not isOurChannel(channelName, baseName)
		or DR.Share.IsMe(player) then
		return
	end
	if text == REQUEST then
		answer(player, nil, true)
	else
		local key = text:match("^" .. REQUEST:gsub("%p", "%%%0") .. " (%S+)$")
		if key and DR:GetDungeon(key) then answer(player, key, true) end
	end
end

-- Asks the others in a party (not a raid: 40 answers each) once it has someone new.
local lastGroupAsk, lastSize = 0, 0
local function groupChanged()
	local channel = DR.Share:Channel()
	local size = GetNumGroupMembers and DR.Safe(GetNumGroupMembers()) or 0
	if channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then
		lastSize = 0
		return
	end
	if size > lastSize and time() - lastGroupAsk >= GROUP_ASK then
		lastGroupAsk = time()
		C_Timer.After(5, function()
			local now = DR.Share:Channel()
			if now then send(now, { "Q\t" }) end
		end)
	end
	lastSize = size
end

-- On login: join the channel, tell the guild the own routes in the list.
local function loggedIn()
	joinChannel()
	if DR.Share:InGuild() then
		local texts = {}
		for _, p in ipairs(published()) do
			if #texts >= ANSWER_ENTRIES then break end
			texts[#texts + 1] = entryMessage(p.key, p.hash, #p.route.stops, me(), DR:GetRouteName(p.route), likesOf(p.route))
		end
		if #texts > 0 then send("GUILD", texts) end
	end
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("CHAT_MSG_CHANNEL")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
local started = false
events:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		List:OnMessage(...)
	elseif event == "CHAT_MSG_CHANNEL" then
		local text, player, _, channelName, _, _, _, _, baseName = ...
		List:OnChannelLine(text, player, channelName, baseName)
	elseif event == "GROUP_ROSTER_UPDATE" then
		groupChanged()
	elseif event == "PLAYER_ENTERING_WORLD" and not started and DR.db then
		started = true
		C_Timer.After(15, loggedIn)
	end
end)
