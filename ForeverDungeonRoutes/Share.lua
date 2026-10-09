local _, DR = ...
local L = DR.L

-- Sharing routes with the group in game, in the spirit of MDT. Own routes travel as their export
-- text, cut into addon messages of at most 255 characters; for a standard route a short hint is
-- enough, every group member with the addon has it. Nothing is taken over without asking.
--
-- Messages (fields separated by tabs):
--   S <key> <routeId>                     use this standard route
--   R <transfer> <parts> <key> <name>     an own route follows in <parts> pieces
--   C <transfer> <index> <piece>          one piece of the export text

local PREFIX = "FDRoutes"
local PIECE = 240            -- characters of export text per message (with the header under 255)
local MAX_PARTS = 300        -- 72 000 characters, far above the largest route
local TRANSFER_TIMEOUT = 120 -- seconds without a new piece before a transfer is dropped
local SEND_INTERVAL = 0.2
local RETRY_THROTTLE = 1
local RETRY_LOCKDOWN = 2

-- Enum.SendAddonMessageResult in the Forever client (ChatConstantsDocumentation)
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = RESULT.Success or 0
local THROTTLE = { [RESULT.AddonMessageThrottle or 3] = true, [RESULT.ChannelThrottle or 8] = true }
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

local Share = {}
DR.Share = Share

local queue = {}
local sending = false
local transfers = {} -- [sender .. transfer] = { sender, key, name, parts, pieces, got, time }
local offers = {}    -- offers waiting for the dialog

-- The group channel to use, or nil when not in a group.
function Share:Channel()
	if LE_PARTY_CATEGORY_INSTANCE and DR.Safe(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
		return "INSTANCE_CHAT"
	end
	if DR.Safe(IsInRaid()) then return "RAID" end
	if DR.Safe(IsInGroup()) then return "PARTY" end
	return nil
end

local function inLockdown()
	return C_ChatInfo.InChatMessagingLockdown ~= nil and DR.Safe(C_ChatInfo.InChatMessagingLockdown()) == true
end

local function pump()
	local item = queue[1]
	if not item then
		sending = false
		return
	end
	if inLockdown() then
		C_Timer.After(RETRY_LOCKDOWN, pump)
		return
	end
	local result = DR.Safe(C_ChatInfo.SendAddonMessage(PREFIX, item.text, item.channel))
	if result == SUCCESS or result == true then
		table.remove(queue, 1)
		if item.done then
			DR:Print(item.done)
		end
		C_Timer.After(SEND_INTERVAL, pump)
	elseif THROTTLE[result] or result == LOCKDOWN then
		C_Timer.After(result == LOCKDOWN and RETRY_LOCKDOWN or RETRY_THROTTLE, pump)
	else
		queue = {}
		sending = false
		DR:Print(L["Sending failed."])
	end
end

local function enqueue(channel, texts, done)
	for i, text in ipairs(texts) do
		queue[#queue + 1] = { channel = channel, text = text, done = i == #texts and done or nil }
	end
	if not sending then
		sending = true
		pump()
	end
end

-- Sends a route to the group. Returns true when sending started.
function Share:SendRoute(key, route)
	if not key or not route then return false end
	local channel = self:Channel()
	if not channel then
		DR:Print(L["You are not in a group."])
		return false
	end
	if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and DR.Safe(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()) then
		DR:Print(L["Sending failed."])
		return false
	end
	if inLockdown() then
		DR:Print(L["Sending has to wait until the fight is over."])
	end
	if DR:IsBuiltIn(route) then
		enqueue(channel, { table.concat({ "S", key, route.id }, "\t") }, L["Route sent to your group."])
		return true
	end
	local text = DR:ExportRoute(key, route)
	local parts = math.ceil(#text / PIECE)
	local transfer = string.format("%04x", math.random(0, 65535))
	local name = DR:GetRouteName(route):gsub("[\t|]", " "):sub(1, 60)
	local texts = { table.concat({ "R", transfer, tostring(parts), key, name }, "\t") }
	for i = 1, parts do
		texts[#texts + 1] = table.concat({ "C", transfer, tostring(i), text:sub((i - 1) * PIECE + 1, i * PIECE) }, "\t")
	end
	DR:Print(L["Sending the route to your group (%d parts)."], parts)
	enqueue(channel, texts, L["Route sent to your group."])
	return true
end

function Share:IsSending()
	return sending
end

-- Receiving -------------------------------------------------------------------------------------

local function senderName(sender)
	if Ambiguate then
		return Ambiguate(sender, "none")
	end
	return (sender:gsub("%-.*$", ""))
end

local function isMe(sender)
	local me = DR.Safe(UnitName("player"))
	return me ~= nil and senderName(sender) == me
end

local function showNextOffer()
	if DR.Dialog.IsShown() then return end
	local offer = table.remove(offers, 1)
	if not offer then return end
	DR.Dialog.Confirm(offer.title, offer.text, offer.accept, offer.acceptText)
end

local function offer(o)
	table.insert(offers, o)
	showNextOffer()
end

local function openOn(key, route)
	DR.Window:Open(key, DR:GetRouteStartFloor(route))
end

local function receivedStandard(sender, key, routeId)
	local route = DR:GetRoute(key, routeId)
	if not route or not DR:IsBuiltIn(route) then return end
	offer({
		title = L["Route received"],
		text = L["%s recommends the standard route \"%s\" for %s. Use it?"]:format(senderName(sender),
			DR:GetRouteName(route), DR:GetKeyName(key)),
		acceptText = L["Use"],
		accept = function()
			DR:SetActiveRoute(key, routeId)
			openOn(key, route)
		end,
	})
end

-- An own route of the same dungeon with the same content: taking it over again would only make a twin.
local function sameRoute(key, text)
	for _, route in ipairs(DR:GetRoutes(key)) do
		if not DR:IsBuiltIn(route) and DR:ExportRoute(key, route) == text then
			return route
		end
	end
	return nil
end

local function receivedRoute(sender, t)
	local text = table.concat(t.pieces)
	local key, route = DR:ImportRoute(text)
	if not key or key ~= t.key then
		DR:Print(L["%s sent a route that could not be read."], senderName(sender))
		return
	end
	offer({
		title = L["Route received"],
		text = L["%s sends you the route \"%s\" for %s. Take it over?"]:format(senderName(sender),
			DR:GetRouteName(route), DR:GetKeyName(key)),
		acceptText = L["Take over"],
		accept = function()
			local existing = sameRoute(key, text)
			if existing then
				DR:SetActiveRoute(key, existing.id)
				DR:Print(L["You already have this route; it is now active."])
				openOn(key, existing)
				return
			end
			DR:AddImportedRoute(key, route)
			DR:Print(L["Route from %s taken over: %s"], senderName(sender), DR:GetRouteName(route))
			openOn(key, route)
		end,
	})
end

local function dropOld(now)
	for id, t in pairs(transfers) do
		if now - t.time > TRANSFER_TIMEOUT then
			transfers[id] = nil
		end
	end
end

function Share:OnMessage(prefix, text, channel, sender)
	prefix, text, sender = DR.Safe(prefix), DR.Safe(text), DR.Safe(sender)
	if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or isMe(sender) then
		return
	end
	local f = {}
	for field in (text .. "\t"):gmatch("([^\t]*)\t") do
		f[#f + 1] = field
	end
	local now = time()
	dropOld(now)
	if f[1] == "S" and DR:GetDungeon(f[2]) then
		receivedStandard(sender, f[2], f[3])
	elseif f[1] == "R" then
		local parts = tonumber(f[3])
		if not parts or parts < 1 or parts > MAX_PARTS or not DR:GetDungeon(f[4]) then return end
		-- one transfer per sender at a time; a new one replaces an unfinished one
		for id, t in pairs(transfers) do
			if t.sender == sender then transfers[id] = nil end
		end
		transfers[sender .. f[2]] = { sender = sender, key = f[4], parts = parts, pieces = {}, got = 0, time = now }
	elseif f[1] == "C" then
		local t = transfers[sender .. (f[2] or "")]
		local index = tonumber(f[3])
		if not t or not index or index < 1 or index > t.parts or index ~= math.floor(index) or t.pieces[index] then return end
		t.pieces[index] = f[4] or ""
		t.got = t.got + 1
		t.time = now
		if t.got == t.parts then
			transfers[sender .. f[2]] = nil
			receivedRoute(sender, t)
		end
	end
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	Share:OnMessage(prefix, text, channel, sender)
end)
DR.Dialog.onHidden = function()
	C_Timer.After(0, showNextOffer)
end
