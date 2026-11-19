local _, DR = ...
local L = DR.L

-- The dungeon map inside the window: the game's own map art, the route on top, stops, notes,
-- floor links, and the own position and group where the game reveals them (not inside
-- dungeons). The art comes in twelve tiles of 256 pixels
-- (4 across, 3 down) of which the map uses the top left 1002 by 668 pixels; route coordinates
-- are 0..1 across that part. Mouse wheel zooms, dragging pans.

local MAP_W, MAP_H = 1002, 668
local TILE = 256
local MAX_ZOOM = 4
local ZOOM_STEP = 1.25
local DRAG_START = 5        -- pixels the mouse moves before a press becomes a pan
local UPDATE_INTERVAL = 0.1 -- seconds between position updates
local ROOM_ALPHA = 0.45     -- the room the player is in: lowest opacity of its pulsing glow
local ROOM_PULSE = 0.3      -- ... and how much brighter it gets
local ROOM_COLOR = { 1.00, 0.80, 0.30 }
local ROOM_GLOW = 1.35      -- the soft glow over a part of a room is this much larger, its edge fades out
-- A room whose glow covers more of the map than this (Chapel Gardens in the Cathedral, Ironclad Cove, Shadowforge
-- City, the Spiral of Thorns ...) glows faint and still: pulsing it would pulse the whole map (Oliver, 14.11.2026).
local BIG_ROOM, BIG_ROOM_ALPHA = 0.3, 0.2
local HELP_MIN_W = 240      -- the "?" of the key to the signs only on a map at least this wide (since 1.3.0)
local ART_TOGGLE_MIN_W = 280 -- the switch to the minimap pictures beside them only from this width (since 1.3.4), so the
                             -- room's name in the lower left keeps its room on the small map
local ADDON_PATH = "Interface\\AddOns\\ForeverDungeonRoutes\\"
-- The classic maps' tiles, shipped with the addon since 1.3.3 (tiles\<file ID>.blp, Blizzard's files unchanged): the
-- Russian, Spanish (Mexico) and Italian clients of WoW: Forever lack the game's own and drew the maps green (found by
-- OpenMap, 07.11.2026, build 1.60.1.70862). On those clients a tile of the addon the game does not know yet (an update
-- with /reload only) asks for a restart; elsewhere the game's own tile stands in until then.
local TILE_PATH = ADDON_PATH .. "tiles\\"
local WITHOUT_GAME_TILES = { ruRU = true, esMX = true, itIT = true }
local MEDIA = ADDON_PATH .. "media\\"

DR.MAP_W, DR.MAP_H = MAP_W, MAP_H
DR.ROOM_GLOW = ROOM_GLOW

-- Color of the main path runs from the first to the last stop.
local GRADIENT = {
	{ 0.00, 0.37, 0.84, 0.82 },
	{ 0.55, 1.00, 0.84, 0.36 },
	{ 1.00, 1.00, 0.50, 0.25 },
}
local SIDE_COLOR = { 0.89, 0.87, 0.82 }
local CASING_COLOR = { 0.05, 0.04, 0.03, 0.78 }
local ARROW_COLOR = { 0.06, 0.05, 0.03, 0.92 }
local EDIT_DOT_COLOR = { 1.00, 1.00, 1.00, 0.95 }
local EDGE_COLOR = { 0.85, 0.85, 0.85, 0.6 } -- the edge of the drawn map while editing on the map turned north up

local MEMBER_COLOR = { 0.45, 0.78, 1.00 } -- rooms of the others in the group
local MEMBER_ALPHA = 0.45
local OWN_COLOR = { 0.40, 0.95, 0.55 }    -- the own marker (since 1.3.2), a colour no other sign on the map has
local LOCK_COLOR = { 1.00, 0.84, 0.36 }   -- the padlock, gold like the "?" and the crosshair

local KIND_STYLE = {
	boss = { ring = { 0.95, 0.76, 0.31 }, text = { 1.00, 0.91, 0.66 } },
	rare = { ring = { 0.89, 0.87, 0.82 }, text = { 0.89, 0.87, 0.82 } },
	optional = { ring = { 0.62, 0.78, 0.95 }, text = { 0.80, 0.89, 1.00 } },
}

local function gradient(t)
	for i = 1, #GRADIENT - 1 do
		local a, b = GRADIENT[i], GRADIENT[i + 1]
		if t <= b[1] then
			local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 0
			return a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u
		end
	end
	local last = GRADIENT[#GRADIENT]
	return last[2], last[3], last[4]
end
DR.GradientColor = gradient

-- One colour for the whole route instead of the gradient (setting lineColor, since 1.3.0; a wish on CurseForge: the
-- route should stand out more). Main path and side paths take it, the side paths stay dashed. Colours that neither
-- the map art (brown and beige parchment, grey and green minimap pictures, orange lava, blue water) nor the addon's
-- own signs use (gold bosses and rooms, blue floor boxes and group, whitish grey rares), bright on the dark minimap
-- pictures and set off on the light parchment by the dark edge every line has.
local LINE_COLORS = {
	white = { 1.00, 1.00, 1.00 },
	magenta = { 1.00, 0.30, 0.85 },
	cyan = { 0.30, 0.90, 1.00 },
}

-- The fixed colour the player chose for the route line, or nil for the gradient (also for a value it does not know).
function DR.LineColor()
	local key = DR.db and DR.db.lineColor
	return key and LINE_COLORS[key] or nil
end

function DR.LineColorKey()
	return DR.LineColor() and DR.db.lineColor or "gradient"
end

local View = {}
DR.MapView = View

-- Pins ------------------------------------------------------------------------------------

local function editing(pin)
	return DR.Editor:IsEditing(View.key, View.route) and pin.route == View.route
end

local function pinMouseDown(pin, button)
	pin.dragged = nil
	if button == "LeftButton" and editing(pin) and not IsShiftKeyDown() then
		DR.Editor:StartDrag(pin)
	end
end

local function pinMouseUp(pin)
	if pin.dragging then
		DR.Editor:StopDrag(pin)
	end
end

local function stopOnEnter(pin)
	local stop = pin.stop
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local kindText = stop.kind == "rare" and L["Rare"] or stop.kind == "optional" and L["Optional"] or L["Boss"]
	local name = DR.LocText(stop, "name") or ""
	GameTooltip:SetText(name ~= "" and name or kindText, 1, 0.82, 0)
	if name ~= "" then
		GameTooltip:AddLine(kindText, 0.7, 0.7, 0.7)
	end
	local note = DR.LocText(stop, "note")
	if note and note ~= "" then
		GameTooltip:AddLine(note, 1, 1, 1, true)
	end
	if editing(pin) then
		GameTooltip:AddLine(L["Drag: move\nClick: options\nRight-click: delete"], 0.4, 0.8, 1, true)
	else
		GameTooltip:AddLine(L["Click: mark as done\nAlt-click: show to the group"], 0.4, 0.8, 1, true)
		if stop.encounters and DR.db.autoCheck then
			GameTooltip:AddLine(L["Ticks itself off when the boss dies."], 0.6, 0.6, 0.6, true)
		end
	end
	GameTooltip:Show()
	DR:Fire("STOP_HOVER", pin.index)
end

local function stopOnLeave()
	GameTooltip:Hide()
	DR:Fire("STOP_HOVER", nil)
end

local function stopOnClick(pin, button)
	if pin.dragged then
		pin.dragged = nil
		return
	end
	if editing(pin) then
		DR.Editor:OnStopClicked(pin, button)
	elseif button == "LeftButton" and IsAltKeyDown() then
		DR.Group:ShowStop(View.key, pin.route, pin.index)
	elseif button == "LeftButton" then
		DR:ToggleStopDone(View.key, pin.route, pin.index)
	end
end

local function createStopPin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(24, 24)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 12)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.Glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.Glow:SetTexture(MEDIA .. "glow")
	pin.Glow:SetBlendMode("ADD")
	pin.Glow:SetSize(46, 46)
	pin.Glow:SetPoint("CENTER")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "circle")
	pin.Fill:SetAllPoints()
	pin.Ring = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	pin.Ring:SetTexture(MEDIA .. "ring")
	pin.Ring:SetAllPoints()
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pin.Label:SetDrawLayer("OVERLAY", 2)
	pin.Label:SetPoint("CENTER", 0, 0)
	pin.Check = pin:CreateTexture(nil, "OVERLAY", nil, 3)
	pin.Check:SetTexture(MEDIA .. "check")
	pin.Check:SetSize(18, 18)
	pin.Check:SetPoint("CENTER", 8, -8)
	pin:SetScript("OnEnter", stopOnEnter)
	pin:SetScript("OnLeave", stopOnLeave)
	pin:SetScript("OnMouseDown", pinMouseDown)
	pin:SetScript("OnMouseUp", pinMouseUp)
	pin:SetScript("OnClick", stopOnClick)
	return pin
end

local function noteOnEnter(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Note"], 1, 0.82, 0)
	GameTooltip:AddLine(DR.LocText(pin.note, "text") or "", 1, 1, 1, true)
	if editing(pin) then
		GameTooltip:AddLine(L["Drag: move\nClick: edit text\nRight-click: delete"], 0.4, 0.8, 1, true)
	end
	GameTooltip:Show()
end

local function noteOnClick(pin, button)
	if pin.dragged then
		pin.dragged = nil
		return
	end
	if editing(pin) then
		DR.Editor:OnNoteClicked(pin, button)
	end
end

local function createNotePin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(20, 20)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 10)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "diamond")
	pin.Fill:SetAllPoints()
	pin.Fill:SetVertexColor(0.55, 0.16, 0.14, 0.95)
	pin.Edge = pin:CreateTexture(nil, "OVERLAY")
	pin.Edge:SetTexture(MEDIA .. "diamondring")
	pin.Edge:SetAllPoints()
	pin.Edge:SetVertexColor(1, 0.78, 0.7, 1)
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pin.Label:SetPoint("CENTER", 0, 0)
	pin.Label:SetText("!")
	pin:SetScript("OnEnter", noteOnEnter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnMouseDown", pinMouseDown)
	pin:SetScript("OnMouseUp", pinMouseUp)
	pin:SetScript("OnClick", noteOnClick)
	return pin
end

local function linkOnEnter(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(pin.link.forward and L["Route continues on"] or L["Route comes from"], 1, 0.82, 0)
	GameTooltip:AddLine(DR:GetFloorName(pin.link.to), 1, 1, 1)
	GameTooltip:AddLine(L["Click: show this map level"], 0.4, 0.8, 1)
	GameTooltip:Show()
end

local function linkOnClick(pin, button)
	if button == "LeftButton" then
		DR.Window:SelectFloor(pin.link.to, true)
	end
end

local function createLinkPin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(20, 20)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 10)
	pin:RegisterForClicks("LeftButtonUp")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "square")
	pin.Fill:SetAllPoints()
	pin.Fill:SetVertexColor(0.12, 0.24, 0.36, 0.95)
	pin.Edge = pin:CreateTexture(nil, "OVERLAY")
	pin.Edge:SetTexture(MEDIA .. "squarering")
	pin.Edge:SetAllPoints()
	pin.Edge:SetVertexColor(0.67, 0.82, 1, 1)
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pin.Label:SetPoint("CENTER", 0, 0)
	pin:SetScript("OnEnter", linkOnEnter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", linkOnClick)
	return pin
end

-- The key to the signs on the map (the "?" beside the crosshair, since 1.3.0); the line as it is drawn: the gradient,
-- or the one colour the player chose (setting lineColor).
local function legendOnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Signs on the map"], 1, 1, 1)
	for _, text in ipairs({
		L["1 2 3: bosses in route order (click to tick off)"],
		L["R: rare   +: optional   !: note"],
		L["Blue box: another map level (same letters belong together, click to switch)"],
		DR.LineColor() and L["Solid line: the route, dashed: side path"]
			or L["Line from turquoise (start) to orange (end), dashed: side path"],
	}) do
		GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true)
	end
	GameTooltip:AddLine(L["Hover over a stop for its tips"], 0.4, 0.8, 1, true)
	GameTooltip:AddLine(L["Shift-click on the map: your own marker (drag it along, right-click removes it)"], 0.4, 0.8, 1, true)
	GameTooltip:Show()
end

local function ownOnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Your marker"], 1, 1, 1)
	GameTooltip:AddLine(L["Drag it along as you go; right-click removes it."], 0.9, 0.9, 0.9, true)
	GameTooltip:Show()
end

local function lockOnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	if DR.db.lockWindow then
		GameTooltip:SetText(L["Window locked"], 1, 1, 1)
		GameTooltip:AddLine(L["Click to move and resize them again; Escape then closes the window again."], 0.9, 0.9, 0.9, true)
	else
		GameTooltip:SetText(L["Lock the window"], 1, 1, 1)
		GameTooltip:AddLine(L["The window and the small map stay where they are and keep their size, and Escape no longer closes the window."], 0.9, 0.9, 0.9, true)
	end
	GameTooltip:Show()
end

-- The switch between the drawn map and the game's minimap pictures (since 1.3.4, Oliver: a button on the map rather
-- than the box behind the gear button; a player on CurseForge found it hard to tell where he is on the route).
local function artToggleOnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	-- what the map shows, not only the setting (UpdateArtToggle)
	if View.artSource == "minimap" then
		GameTooltip:SetText(L["Map from the game's minimap"], 1, 1, 1)
		GameTooltip:AddLine(L["Click to show the drawn map again."], 0.9, 0.9, 0.9, true)
	else
		GameTooltip:SetText(L["Show the map from the game's minimap"], 1, 1, 1)
		GameTooltip:AddLine(L["It looks like the minimap in your game, which makes it easier to see where you are."],
			0.9, 0.9, 0.9, true)
	end
	GameTooltip:Show()
end

local function createMarker(view, size, level)
	local marker = CreateFrame("Frame", nil, view.canvas)
	marker:SetSize(size, size)
	marker:SetFrameLevel(view.canvas:GetFrameLevel() + level)
	marker:EnableMouse(false)
	marker.Dot = marker:CreateTexture(nil, "ARTWORK")
	marker.Dot:SetTexture(MEDIA .. "circle")
	marker.Dot:SetSize(size * 0.6, size * 0.6)
	marker.Dot:SetPoint("CENTER")
	marker.Ring = marker:CreateTexture(nil, "OVERLAY")
	marker.Ring:SetTexture(MEDIA .. "ring")
	marker.Ring:SetVertexColor(0.05, 0.04, 0.03, 1)
	marker.Ring:SetSize(size * 0.6, size * 0.6)
	marker.Ring:SetPoint("CENTER")
	marker:Hide()
	return marker
end

-- Floor changes along the main path get a link pin at both ends, so the next floor is one
-- click away. Explicit links stored in the route are shown as well; where one of them already
-- marks that change (a stair "v", a portal "P"), no second pin goes on top of it, and the one at
-- the end of a piece says "Route continues on" in its tooltip (both since 1.3.0).
local NEAR_LINK = 0.03

local function explicitNear(route, floor, x, y, to)
	for _, link in ipairs(route.links or {}) do
		if link.floor == floor and link.to == to and math.abs(link.x - x) <= NEAR_LINK and math.abs(link.y - y) <= NEAR_LINK then
			return link
		end
	end
end

local function collectLinks(route)
	-- copies, so the flag for the tooltip never ends up in the route itself (saved routes)
	local links, shown = {}, {}
	for _, link in ipairs(route.links or {}) do
		local copy = {}
		for k, v in pairs(link) do
			copy[k] = v
		end
		shown[link] = copy
		table.insert(links, copy)
	end
	local previous
	for _, path in ipairs(route.paths) do
		if path.kind == "main" and #path.pts >= 4 then
			-- a copy of the route for a twin floor restarts the gradient; that is no floor change
			local continues = not previous or not path.t0 or not previous.t1 or path.t0 >= previous.t1 - 0.01
			if previous and previous.floor ~= path.floor and continues then
				local pts = previous.pts
				local x, y = pts[#pts - 1], pts[#pts]
				local own = explicitNear(route, previous.floor, x, y, path.floor)
				if own then
					shown[own].forward = true
				else
					table.insert(links, { floor = previous.floor, x = x, y = y, to = path.floor, forward = true })
				end
				if not explicitNear(route, path.floor, path.pts[1], path.pts[2], previous.floor) then
					table.insert(links, { floor = path.floor, x = path.pts[1], y = path.pts[2], to = previous.floor })
				end
			end
			previous = path
		end
	end
	return links
end
DR.CollectLinks = collectLinks -- for the checks in tools/szenario.lua

-- Setup -------------------------------------------------------------------------------------

function View:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetClipsChildren(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	self.frame = frame
	local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:SetAllPoints()
	DR.ThemeFill(background, "mapBg") -- black, in the style "Gilded" a warm dark
	self.background = background

	local canvas = CreateFrame("Frame", nil, frame)
	canvas:SetSize(MAP_W, MAP_H)
	canvas:SetPoint("TOPLEFT")
	self.canvas = canvas
	self.tiles = {}
	for i = 1, 12 do
		local row, col = math.floor((i - 1) / 4), (i - 1) % 4
		local w = math.min(TILE, MAP_W - col * TILE)
		local h = math.min(TILE, MAP_H - row * TILE)
		local tile = canvas:CreateTexture(nil, "BACKGROUND")
		tile:SetSize(w, h)
		tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * TILE, -row * TILE)
		tile:SetTexCoord(0, w / TILE, 0, h / TILE)
		self.tiles[i] = tile
	end
	-- a picture of the whole floor where the game has no map art (floor.image)
	self.picture = canvas:CreateTexture(nil, "BACKGROUND")
	self.picture:SetAllPoints(canvas)
	self.picture:Hide()
	-- or, where the player chose so, the game's own minimap pictures of the floor (Data/Minimaps.lua)
	self.minimapTiles = {}

	self.layer = CreateFrame("Frame", nil, canvas)
	self.layer:SetAllPoints(canvas)
	self.layer:SetFrameLevel(canvas:GetFrameLevel() + 1)
	self.lines, self.numLines = {}, 0
	self.dots, self.numDots = {}, 0
	self.stopPins, self.notePins, self.linkPins = {}, {}, {}
	self.numStops, self.numNotes, self.numLinks = 0, 0, 0

	self.player = createMarker(self, 28, 20)
	self.player.Dot:SetVertexColor(1, 0.84, 0.36, 1)
	self.player.Arrow = self.player:CreateTexture(nil, "OVERLAY", nil, 1)
	self.player.Arrow:SetTexture(MEDIA .. "player")
	self.player.Arrow:SetAllPoints()
	self.party = {}
	-- the own marker (since 1.3.2): Shift-click puts it on the map (OnMouseUp), the mouse drags it (OnUpdate), a
	-- right-click takes it away; green dot with the arrow of the player's own position outside
	local own = CreateFrame("Button", nil, canvas)
	own:SetSize(26, 26)
	own:SetFrameLevel(canvas:GetFrameLevel() + 22)
	own:RegisterForClicks("RightButtonUp")
	own.Dot = own:CreateTexture(nil, "ARTWORK")
	own.Dot:SetTexture(MEDIA .. "circle")
	own.Dot:SetSize(22, 22)
	own.Dot:SetPoint("CENTER")
	own.Dot:SetVertexColor(OWN_COLOR[1], OWN_COLOR[2], OWN_COLOR[3], 1)
	own.Ring = own:CreateTexture(nil, "OVERLAY")
	own.Ring:SetTexture(MEDIA .. "ring")
	own.Ring:SetVertexColor(0.05, 0.04, 0.03, 1)
	own.Ring:SetSize(22, 22)
	own.Ring:SetPoint("CENTER")
	own.Arrow = own:CreateTexture(nil, "OVERLAY", nil, 1)
	own.Arrow:SetTexture(MEDIA .. "player")
	own.Arrow:SetAllPoints()
	own:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then View.dragOwn = {} end
	end)
	own:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then View:DropOwnMarker() end
	end)
	own:SetScript("OnClick", function(_, button)
		if button == "RightButton" then DR:ClearMarker(View.key) end
	end)
	own:SetScript("OnEnter", ownOnEnter)
	own:SetScript("OnLeave", GameTooltip_Hide)
	own:Hide()
	self.own = own

	self.message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.message:SetPoint("CENTER")
	self.message:SetText(L["The game has no map art for this floor."])
	self.message:Hide()
	-- room name in the lower left corner, above the map
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 40)
	self.status = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.status:SetPoint("BOTTOMLEFT", 14, 13)
	self.status:SetWordWrap(false)
	self.status:SetTextColor(1, 0.86, 0.5)
	self.status:Hide()
	self.statusBack = overlay:CreateTexture(nil, "BACKGROUND")
	self.statusBack:SetPoint("TOPLEFT", self.status, "TOPLEFT", -7, 5)
	self.statusBack:SetPoint("BOTTOMRIGHT", self.status, "BOTTOMRIGHT", 7, -5)
	self.statusBack:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	self.statusBack:Hide()
	-- the legend of the group (since 1.2.4): lower left, above the room name
	self.overlay = overlay
	self.legend = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.legend:SetJustifyH("LEFT")
	self.legend:SetTextColor(MEMBER_COLOR[1], MEMBER_COLOR[2], MEMBER_COLOR[3])
	self.legend:Hide()
	self.legendBack = overlay:CreateTexture(nil, "BACKGROUND")
	self.legendBack:SetPoint("TOPLEFT", self.legend, "TOPLEFT", -7, 5)
	self.legendBack:SetPoint("BOTTOMRIGHT", self.legend, "BOTTOMRIGHT", 7, -5)
	self.legendBack:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	self.legendBack:Hide()
	self.roomLines, self.numRoomLines = {}, 0
	-- rooms of the others in the group (their numbers of the legend), and a stop someone shows to the group
	self.memberLines, self.numMemberLines, self.memberLabels = {}, 0, {}
	self.ping = createMarker(self, 44, 21)
	self.ping.Dot:Hide()
	self.ping.Ring:SetVertexColor(MEMBER_COLOR[1], MEMBER_COLOR[2], MEMBER_COLOR[3], 1)
	-- who drew a picture floor, in the upper right corner
	self.credit = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.credit:SetPoint("TOPRIGHT", -14, -13)
	self.credit:SetWordWrap(false)
	self.credit:SetTextColor(0.85, 0.85, 0.85)
	self.credit:Hide()
	self.creditBack = overlay:CreateTexture(nil, "BACKGROUND")
	self.creditBack:SetPoint("TOPLEFT", self.credit, "TOPLEFT", -7, 5)
	self.creditBack:SetPoint("BOTTOMRIGHT", self.credit, "BOTTOMRIGHT", 7, -5)
	self.creditBack:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	self.creditBack:Hide()
	-- a map picture of the addon the game does not know yet (since 1.3.0, UpdateArt): a hint across the top of the
	-- map (Layout), wrapped where the map is narrow (the small map)
	self.newMap = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.newMap:SetPoint("TOPLEFT", 20, -13)
	self.newMap:SetPoint("TOPRIGHT", -20, -13)
	self.newMap:SetJustifyH("CENTER")
	self.newMap:SetWordWrap(true)
	self.newMap:SetTextColor(1, 0.86, 0.5)
	self.newMap:SetText(L["This map is new: quit and restart the game once (/reload is not enough)."])
	self.newMap:Hide()
	self.newMapBack = overlay:CreateTexture(nil, "BACKGROUND")
	self.newMapBack:SetPoint("TOPLEFT", self.newMap, "TOPLEFT", -7, 5)
	self.newMapBack:SetPoint("BOTTOMRIGHT", self.newMap, "BOTTOMRIGHT", 7, -5)
	self.newMapBack:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	self.newMapBack:Hide()

	local locate = CreateFrame("Button", nil, frame)
	locate:SetSize(26, 26)
	locate:SetPoint("BOTTOMRIGHT", -6, 6)
	locate:SetFrameLevel(frame:GetFrameLevel() + 40)
	locate.Back = locate:CreateTexture(nil, "BACKGROUND")
	locate.Back:SetTexture(MEDIA .. "circle")
	locate.Back:SetAllPoints()
	locate.Back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
	locate.Icon = locate:CreateTexture(nil, "ARTWORK")
	locate.Icon:SetTexture(MEDIA .. "locate")
	locate.Icon:SetSize(18, 18)
	locate.Icon:SetPoint("CENTER")
	locate.Icon:SetVertexColor(1, 0.84, 0.36)
	locate.Highlight = locate:CreateTexture(nil, "HIGHLIGHT")
	locate.Highlight:SetTexture(MEDIA .. "glow")
	locate.Highlight:SetBlendMode("ADD")
	locate.Highlight:SetAllPoints()
	-- finds the dungeon and its wing once more (as on entering) and shows where the player is
	locate:SetScript("OnClick", function() DR:Redetect() end)
	locate:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Show where you are"], 1, 1, 1)
		GameTooltip:AddLine(L["The room you are in, else the next open boss. The map follows you again."], 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	locate:SetScript("OnLeave", GameTooltip_Hide)
	locate:Hide()
	self.locate = locate
	-- the signs on the map explained (since 1.3.0): a round "?" beside the crosshair, in its look and in every style,
	-- the mouse on it shows the key (legendOnEnter); in the corner where the crosshair is hidden (PlaceHelp), only
	-- where the map is wide enough for it (Layout: the small map can be narrower)
	local help = CreateFrame("Button", nil, frame)
	help:SetSize(26, 26)
	help:SetPoint("BOTTOMRIGHT", -6, 6)
	help:SetFrameLevel(frame:GetFrameLevel() + 40)
	help.Back = help:CreateTexture(nil, "BACKGROUND")
	help.Back:SetTexture(MEDIA .. "circle")
	help.Back:SetAllPoints()
	help.Back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
	help.Text = help:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	help.Text:SetPoint("CENTER", 0, 0)
	help.Text:SetText("?")
	help.Text:SetTextColor(1, 0.84, 0.36)
	help.Highlight = help:CreateTexture(nil, "HIGHLIGHT")
	help.Highlight:SetTexture(MEDIA .. "glow")
	help.Highlight:SetBlendMode("ADD")
	help.Highlight:SetAllPoints()
	help:SetScript("OnEnter", legendOnEnter)
	help:SetScript("OnLeave", GameTooltip_Hide)
	self.help = help
	-- the padlock (since 1.3.2, a wish on CurseForge): left of the "?" and in its look, it keeps the window and the small
	-- map where they are (Window.lua, applyLock); drawn from the shapes the addon has (no new file, no restart needed):
	-- the upper half of a ring as the shackle on a small square, lifted while open
	local lock = CreateFrame("Button", nil, frame)
	lock:SetSize(26, 26)
	lock:SetPoint("RIGHT", help, "LEFT", -4, 0)
	lock:SetFrameLevel(frame:GetFrameLevel() + 40)
	lock.Back = lock:CreateTexture(nil, "BACKGROUND")
	lock.Back:SetTexture(MEDIA .. "circle")
	lock.Back:SetAllPoints()
	lock.Back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
	lock.Body = lock:CreateTexture(nil, "ARTWORK", nil, 1)
	lock.Body:SetTexture(MEDIA .. "square")
	lock.Body:SetSize(12, 9)
	lock.Body:SetPoint("CENTER", 0, -3)
	lock.Shackle = lock:CreateTexture(nil, "ARTWORK")
	lock.Shackle:SetTexture(MEDIA .. "ring")
	lock.Shackle:SetTexCoord(0, 1, 0, 0.5)
	lock.Shackle:SetSize(10, 6)
	lock.Highlight = lock:CreateTexture(nil, "HIGHLIGHT")
	lock.Highlight:SetTexture(MEDIA .. "glow")
	lock.Highlight:SetBlendMode("ADD")
	lock.Highlight:SetAllPoints()
	lock:SetScript("OnClick", function()
		DR:SetLocked(not DR.db.lockWindow)
		if lock:IsMouseOver() then lockOnEnter(lock) end
	end)
	lock:SetScript("OnEnter", lockOnEnter)
	lock:SetScript("OnLeave", GameTooltip_Hide)
	self.lock = lock
	self:UpdateLock()
	-- the switch to the game's minimap pictures (since 1.3.4): left of the padlock and in its look, a small round map
	-- with the player's arrow, bright while the minimap pictures show (as the padlock while locked); the same setting
	-- as the box behind the gear button, drawn from the shapes the addon has (no new file)
	local art = CreateFrame("Button", nil, frame)
	art:SetSize(26, 26)
	art:SetPoint("RIGHT", lock, "LEFT", -4, 0)
	art:SetFrameLevel(frame:GetFrameLevel() + 40)
	art.Back = art:CreateTexture(nil, "BACKGROUND")
	art.Back:SetTexture(MEDIA .. "circle")
	art.Back:SetAllPoints()
	art.Back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
	art.Ring = art:CreateTexture(nil, "ARTWORK")
	art.Ring:SetTexture(MEDIA .. "ring")
	art.Ring:SetSize(16, 16)
	art.Ring:SetPoint("CENTER")
	art.Arrow = art:CreateTexture(nil, "ARTWORK", nil, 1)
	art.Arrow:SetTexture(MEDIA .. "player")
	art.Arrow:SetSize(9, 9)
	art.Arrow:SetPoint("CENTER")
	art.Highlight = art:CreateTexture(nil, "HIGHLIGHT")
	art.Highlight:SetTexture(MEDIA .. "glow")
	art.Highlight:SetBlendMode("ADD")
	art.Highlight:SetAllPoints()
	art:SetScript("OnClick", function()
		DR:SetGameMinimap(not DR.db.gameMinimap)
		if art:IsMouseOver() then artToggleOnEnter(art) end
	end)
	art:SetScript("OnEnter", artToggleOnEnter)
	art:SetScript("OnLeave", GameTooltip_Hide)
	art:Hide()
	self.artToggle = art
	-- the tip for the own marker (since 1.3.2, Oliver: the keys belong on the map, not hidden in the options): a band
	-- at the top of the map in the dungeon the player is in, until the first marker is set or a click hides it for good
	local tip = CreateFrame("Button", nil, frame)
	tip:SetFrameLevel(frame:GetFrameLevel() + 41)
	tip.Text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tip.Text:SetPoint("TOPLEFT", 8, -5)
	tip.Text:SetPoint("TOPRIGHT", -8, -5)
	tip.Text:SetJustifyH("CENTER")
	tip.Text:SetWordWrap(true)
	tip.Text:SetTextColor(OWN_COLOR[1], OWN_COLOR[2], OWN_COLOR[3])
	tip.Text:SetText(L["Tip: Shift-click on the map sets your own marker"])
	tip.Back = tip:CreateTexture(nil, "BACKGROUND")
	tip.Back:SetAllPoints()
	tip.Back:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	tip:SetScript("OnClick", function()
		DR.db.markerHint = "done"
		GameTooltip_Hide()
		View:UpdateMarkerHint()
	end)
	tip:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Click to hide this tip"], 1, 1, 1)
		GameTooltip:Show()
	end)
	tip:SetScript("OnLeave", GameTooltip_Hide)
	tip:Hide()
	self.markerTip = tip

	frame:SetScript("OnSizeChanged", function() View:Layout() end)
	frame:SetScript("OnMouseWheel", function(_, delta) View:OnMouseWheel(delta) end)
	frame:SetScript("OnMouseDown", function(_, button) View:OnMouseDown(button) end)
	frame:SetScript("OnMouseUp", function(_, button) View:OnMouseUp(button) end)
	frame:SetScript("OnUpdate", function(_, elapsed) View:OnUpdate(elapsed) end)
	frame:SetScript("OnHide", function() View.press = nil end)

	self.zoom, self.ox, self.oy, self.fit, self.scale = 1, 0, 0, 1, 1
	self.elapsed = 0

	DR:On("HIGHLIGHT_STOP", function(index) View:HighlightStop(index) end)
	DR:On("MARKER_CHANGED", function(key) if key == View.key then View:UpdateOwnMarker() end end)
	DR:On("GROUP_ROOMS_CHANGED", function() View:UpdateMembers() end)
	DR:On("GROUP_STOP_SHOWN", function() View:UpdatePing() end)
	return frame
end

-- Geometry ----------------------------------------------------------------------------------

-- North up (since 1.3.5): on nine levels of the new dungeons Santiago's map is turned against north (Data/Pictures.lua,
-- frame: Alcaz Prison by 89 degrees, the Depths of Forbidden Magic by 167), and so were the minimap pictures laid on it.
-- Where Data/Minimaps.lua has them north up as well (DR.MinimapArtNorth, over a rectangle of the world around the
-- building, the route and the rooms), the view with the minimap pictures shows them so, like the minimap in the game
-- (Oliver, 19.11.2026), and turns everything on the map with them. Routes, rooms, markers and the group keep the drawn
-- map's coordinates (saved routes, export strings and group messages stay as they are); only the drawing converts
-- them (View:ToCanvas, View:FromCanvas).
local turns = {} -- [floor] = the turn of northTurn, worked out once
local CANVAS = { 0, 0, MAP_W, MAP_H } -- what the map shows where nothing reaches beyond the canvas (View:UpdateExtent)
local EXTENT_MARGIN = 24 -- canvas pixels kept around a route point or the marker beyond the north-up rectangle

-- The turn of a floor from the drawn map's coordinates to the north-up rectangle: shown u = t[1] u + t[2] v + t[3],
-- shown v = t[4] u + t[5] v + t[6]; back over the world (t.frame, t.world). Nil where the floor has none.
local function northTurn(floor)
	local north = DR.MinimapArtNorth and DR.MinimapArtNorth[floor]
	local info = DR.Floors[floor]
	local f, r = info and info.frame, north and north.world
	if not f or not r then return nil end
	local turn = turns[floor]
	if turn and turn.frame == f and turn.world == r then return turn end
	-- frame: u = a north + b west + c, v = d north + e west + g; the rectangle { north min, west min, north max,
	-- west max }: shown u = (west max - west) / its width, shown v = (north max - north) / its height
	local a, b, c, d, e, g = f[1], f[2], f[3], f[4], f[5], f[6]
	local det = a * e - b * d
	local sn, sw = r[3] - r[1], r[4] - r[2]
	if det == 0 or not (sn > 0) or not (sw > 0) then return nil end
	turn = {
		d / (det * sw), -a / (det * sw), r[4] / sw + (a * g - d * c) / (det * sw),
		-e / (det * sn), b / (det * sn), r[3] / sn + (e * c - b * g) / (det * sn),
		frame = f, world = r,
	}
	turns[floor] = turn
	return turn
end

-- The linear part of a turn in canvas pixels: a direction or length on the drawn map to the one shown.
local function turnPixels(t)
	return t[1], t[2] * MAP_W / MAP_H, t[4] * MAP_H / MAP_W, t[5]
end

-- Where a point in the drawn map's coordinates (u, v, 0..1) lies on the canvas, in its pixels (1002 by 668).
function View:ToCanvas(u, v)
	local t = self.turn
	if t then
		return (t[1] * u + t[2] * v + t[3]) * MAP_W, (t[4] * u + t[5] * v + t[6]) * MAP_H
	end
	return u * MAP_W, v * MAP_H
end

-- And back: the drawn map's coordinates of a point on the canvas.
function View:FromCanvas(x, y)
	local t = self.turn
	if not t then
		return x / MAP_W, y / MAP_H
	end
	local f, r = t.frame, t.world
	local west = r[4] - x / MAP_W * (r[4] - r[2])
	local north = r[3] - y / MAP_H * (r[3] - r[1])
	return f[1] * north + f[2] * west + f[3], f[4] * north + f[5] * west + f[6]
end

-- What the map shows, in canvas pixels { left, top, right, bottom }: the canvas, and on the map turned north up also
-- whatever of the shown route on this floor or of the own marker lies beyond it. The north-up rectangle frames the
-- building, the standard route and the rooms (werkzeug/minikarten_export.py); an own route or a marker set on the
-- drawn map can reach further on Santiago's map and would otherwise be cut off (the review of 1.3.5). Layout fits and
-- ApplyTransform keeps this in view. Returns whether it changed.
function View:UpdateExtent()
	local x0, y0, x1, y1 = 0, 0, MAP_W, MAP_H
	local floor, route = self.floor, self.route
	if self.turn and floor then
		local function add(u, v)
			local x, y = self:ToCanvas(u, v)
			x0, x1 = math.min(x0, x - EXTENT_MARGIN), math.max(x1, x + EXTENT_MARGIN)
			y0, y1 = math.min(y0, y - EXTENT_MARGIN), math.max(y1, y + EXTENT_MARGIN)
		end
		if route then
			for _, path in ipairs(route.paths) do
				if path.floor == floor then
					for i = 1, #path.pts - 1, 2 do add(path.pts[i], path.pts[i + 1]) end
				end
			end
			for _, list in ipairs({ route.stops, route.notes or {}, route.links or {} }) do
				for _, entry in ipairs(list) do
					if DR.OnFloor(entry, floor) then add(entry.x, entry.y) end
				end
			end
		end
		local marker = self.key and DR:GetMarker(self.key)
		if marker and marker.floor == floor then add(marker.x, marker.y) end
	end
	local e = self.extent
	if e and e[1] == x0 and e[2] == y0 and e[3] == x1 and e[4] == y1 then return false end
	self.extent = (x0 == 0 and y0 == 0 and x1 == MAP_W and y1 == MAP_H) and CANVAS or { x0, y0, x1, y1 }
	return true
end

-- Turns the drawing north up or back (UpdateArt). Zoomed in, the spot of the dungeon in the middle of the map stays in
-- the middle; pins, lines and glowing rooms move to their new places.
function View:SetTurn(turn)
	if turn == self.turn then return end
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	local s = self.scale
	local u, v
	if self.zoom > 1 and s and s > 0 and w and w > 0 and h and h > 0 then
		u, v = self:FromCanvas((w / 2 - self.ox) / s, (h / 2 - self.oy) / s)
	end
	self.turn = turn
	self:UpdateExtent()
	self:Layout() -- the fit for what the map shows now; places pins and lines anew
	if u then
		s = self.fit * self.zoom
		local x, y = self:ToCanvas(u, v)
		self.ox, self.oy = w / 2 - x * s, h / 2 - y * s
		self:ApplyTransform(true)
	end
	self:UpdateRoom()
	self:UpdateMembers()
end

function View:Layout()
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	local e = self.extent or CANVAS -- the canvas, or more where the map is turned north up (UpdateExtent, since 1.3.5)
	self.fit = math.min(w / (e[3] - e[1]), h / (e[4] - e[2]))
	-- the "?" where the map has room for it beside the crosshair and the room's name (the window's map is always wide
	-- enough, the small map only at about its first size)
	self.help:SetShown(w >= HELP_MIN_W)
	self.lock:SetShown(w >= HELP_MIN_W) -- the padlock with it (since 1.3.2)
	self.width = w
	self:UpdateArtToggle() -- the switch to the minimap pictures (since 1.3.4)
	-- the hint on a new map at the top, below the route choice where that sits on the map (stop list hidden)
	local y = (not DR.db.showStops and self.frame:GetParent() == DR.Window:GetFrame()) and -36 or -13
	self.newMap:ClearAllPoints()
	self.newMap:SetPoint("TOPLEFT", 20, y)
	self.newMap:SetPoint("TOPRIGHT", -20, y)
	-- the tip for the own marker in the same place (the two never show together)
	if self.markerTip then
		self.markerTip:ClearAllPoints()
		self.markerTip:SetPoint("TOP", 0, y + 5)
		self:UpdateMarkerHint()
	end
	self:ApplyTransform(true)
end

-- The tip for the own marker (since 1.3.2): in the dungeon the player is in, no marker yet, never set one before and
-- not clicked away (db.markerHint), not while a route is drawn or the band about a new map shows. Fits narrow maps.
function View:UpdateMarkerHint()
	local tip = self.markerTip
	if not tip then return end
	local show = DR.db.markerHint ~= "done" and self.key ~= nil and self.key == DR.currentKey
		and not DR:GetMarker(self.key) and not self.newMap:IsShown()
		and not (self.route and DR.Editor:IsEditing(self.key, self.route))
	if show then
		-- as wide as the text, at most the map less a margin; the text (anchored left and right) wraps inside
		local width = math.min(tip.Text:GetStringWidth(), math.max(120, (self.frame:GetWidth() or 300) - 60))
		tip:SetWidth(width + 16)
		tip:SetHeight(tip.Text:GetStringHeight() + 10)
	end
	tip:SetShown(show)
end

-- The "?" beside the crosshair, or in its corner where the crosshair is hidden (outside the dungeons).
function View:PlaceHelp()
	local beside = self.locate:IsShown()
	if self.helpBeside == beside then return end
	self.helpBeside = beside
	self.help:ClearAllPoints()
	if beside then
		self.help:SetPoint("RIGHT", self.locate, "LEFT", -4, 0)
	else
		self.help:SetPoint("BOTTOMRIGHT", -6, 6)
	end
end

-- Places the canvas for the current zoom and pan; the map stays inside the view where it can.
function View:ApplyTransform(redraw)
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	local s = self.fit * self.zoom
	if s <= 0 then return end
	-- what the map shows: the canvas, or more on the map turned north up (UpdateExtent, since 1.3.5)
	local e = self.extent or CANVAS
	local cw, ch = (e[3] - e[1]) * s, (e[4] - e[2]) * s
	if cw <= w then
		self.ox = (w - cw) / 2 - e[1] * s
	else
		self.ox = DR.Clamp(self.ox, w - e[3] * s, -e[1] * s)
	end
	if ch <= h then
		self.oy = (h - ch) / 2 - e[2] * s
	else
		self.oy = DR.Clamp(self.oy, h - e[4] * s, -e[2] * s)
	end
	local rescaled = s ~= self.scale
	self.scale = s
	self.canvas:SetScale(s)
	self.canvas:ClearAllPoints()
	self.canvas:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.ox / s, -self.oy / s)
	if rescaled or redraw then
		self:PlaceAllPins()
		self:RequestRedraw()
	end
end

function View:CursorInFrame()
	local x, y = GetCursorPosition()
	local scale = self.frame:GetEffectiveScale()
	local left, top = self.frame:GetLeft(), self.frame:GetTop()
	if not left or not top or not scale or scale <= 0 then return nil end
	return x / scale - left, top - y / scale
end

-- The point under the mouse in the drawn map's coordinates (also where the map is turned north up).
function View:GetCursorUV()
	local fx, fy = self:CursorInFrame()
	if not fx then return nil end
	local s = self.scale
	return self:FromCanvas((fx - self.ox) / s, (fy - self.oy) / s)
end

-- The same, kept on what the map shows (for the own marker): on the drawn map its area, as before; on the map turned
-- north up the whole north-up rectangle, which can reach beyond the drawn map (since 1.3.5: there the marker stays
-- under the mouse instead of jumping to the drawn map's edge; DR:SetMarker keeps such a point).
function View:CursorOnShownMap()
	local fx, fy = self:CursorInFrame()
	if not fx then return nil end
	local s, e = self.scale, self.extent or CANVAS
	return self:FromCanvas(DR.Clamp((fx - self.ox) / s, e[1], e[3]), DR.Clamp((fy - self.oy) / s, e[2], e[4]))
end

function View:ZoomAt(fx, fy, factor)
	local zoom = DR.Clamp(self.zoom * factor, 1, MAX_ZOOM)
	if zoom == self.zoom then return end
	local s = self.scale
	local px, py = (fx - self.ox) / s, (fy - self.oy) / s
	local s2 = self.fit * zoom
	self.zoom = zoom
	self.ox, self.oy = fx - px * s2, fy - py * s2
	self:ApplyTransform()
end

-- Centers the map on a point, zooming in to at least the given zoom.
function View:CenterOn(u, v, zoom)
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 then return end
	self.zoom = DR.Clamp(math.max(self.zoom, zoom or 1), 1, MAX_ZOOM)
	local s = self.fit * self.zoom
	local x, y = self:ToCanvas(u, v)
	self.ox, self.oy = w / 2 - x * s, h / 2 - y * s
	self:ApplyTransform()
end

function View:ResetZoom()
	self.zoom = 1
	self:ApplyTransform()
end

-- Mouse ---------------------------------------------------------------------------------------

function View:OnMouseWheel(delta)
	local fx, fy = self:CursorInFrame()
	if not fx then return end
	self:ZoomAt(fx, fy, delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
end

function View:OnMouseDown(button)
	local fx, fy = self:CursorInFrame()
	if not fx then return end
	-- While editing the left button places points, so only the other buttons pan.
	local canPan = button ~= "LeftButton" or not DR.Editor:IsEditing(self.key, self.route)
	self.press = { button = button, fx = fx, fy = fy, ox = self.ox, oy = self.oy, canPan = canPan }
end

function View:OnMouseUp(button)
	local press = self.press
	self.press = nil
	if not press or press.button ~= button or press.moved then return end
	local u, v = self:GetCursorUV()
	if not u then return end
	if DR.Editor:OnMapClick(button, u, v) then return end
	-- Shift-click puts the own marker here (since 1.3.2); while editing the click belongs to the editor (above)
	if button == "LeftButton" and IsShiftKeyDown() and self.key and self.floor then
		DR:SetMarker(self.key, self.floor, self:CursorOnShownMap())
		return
	end
	if button == "RightButton" then
		self:ResetZoom()
	end
end

function View:OnUpdate(elapsed)
	-- the own marker follows the mouse while it is dragged (DropOwnMarker keeps it where it is let go)
	if self.dragOwn then
		local u, v = self:CursorOnShownMap()
		if u then
			self.dragOwn.u, self.dragOwn.v = u, v
			self:PlacePin(self.own, u, v)
		end
	end
	local press = self.press
	if press and press.canPan then
		local fx, fy = self:CursorInFrame()
		if fx then
			local dx, dy = fx - press.fx, fy - press.fy
			if not press.moved and math.abs(dx) + math.abs(dy) >= DRAG_START then
				press.moved = true
			end
			if press.moved then
				self.ox, self.oy = press.ox + dx, press.oy + dy
				self:ApplyTransform()
			end
		end
	end
	self.elapsed = self.elapsed + elapsed
	if self.elapsed >= UPDATE_INTERVAL then
		self.elapsed = 0
		self:UpdateGroup()
	end
	if self.ping:IsShown() then
		self.pingPulse = (self.pingPulse or 0) + elapsed
		local k = 0.5 + 0.5 * math.sin(self.pingPulse * 5)
		self.ping.Ring:SetSize(26 + 16 * k, 26 + 16 * k)
		self.ping.Ring:SetAlpha(0.55 + 0.45 * k)
		if not DR.Group:GetShownStop() then
			self.ping:Hide()
		end
	end
	if self.numRoomLines > 0 and not self.roomStill then
		self.pulse = (self.pulse or 0) + elapsed
		local alpha = ROOM_ALPHA + ROOM_PULSE * (0.5 + 0.5 * math.sin(self.pulse * 3))
		for i = 1, self.numRoomLines do
			local line = self.roomLines[i]
			if line then line:SetAlpha(alpha) end
		end
	end
end

-- The room the player is in --------------------------------------------------------------------
-- The game names the room (Room.lua): its name stands in the lower left corner of the map (since 1.3.0 always, before
-- only with the glow), and where the player wants it (setting showRoom, off at first) its parts glow softly on the
-- map. The map follows the rooms either way.

-- A soft glow over one part of a room: a soft rectangle (full inside, rounded corners, fading edge) stretched
-- along a line through the middle of the part (width along the line, height as thickness), a little larger so
-- the part lies in its full inside and the edge fades out around it.
local function placeGlow(view, line, box)
	local cx, cy = view:ToCanvas(box[2], box[3])
	local half = box[4] * ROOM_GLOW / 2
	local thickness = box[5] * ROOM_GLOW
	local dx, dy = math.cos(box[6]) * half, math.sin(box[6]) * half
	local t = view.turn
	if t then
		-- turned north up with the map (since 1.3.5): the line turns and stretches with it, the thickness keeps the
		-- area of the part (a rectangle the turn would skew a little becomes the nearest rectangle)
		local p, q, r, s = turnPixels(t)
		dx, dy = p * dx + q * dy, r * dx + s * dy
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0 then
			thickness = thickness * math.abs(p * s - q * r) * half / len
		end
	end
	line:SetStartPoint("TOPLEFT", view.canvas, cx - dx, -(cy - dy))
	line:SetEndPoint("TOPLEFT", view.canvas, cx + dx, -(cy + dy))
	line:SetThickness(thickness)
end

local function createGlow(view, color)
	local line = view.canvas:CreateLine(nil, "BORDER")
	line:SetTexture(MEDIA .. "roomglow")
	line:SetVertexColor(color[1], color[2], color[3], 1)
	return line
end

-- Hides everything of a list ever created (pairs: a list of labels may have gaps), so nothing stays behind
-- even when an earlier update stopped halfway.
local function hideAll(list)
	for _, region in pairs(list) do
		region:Hide()
	end
end

-- The soft glow over the parts of a room on the shown floor, from the list of lines (created as needed, stored
-- before use); returns how many lines of the list are in use, whether the room is big (then its glow is
-- faint and does not pulse) and the share of the map its glow covers.
local function glowRoom(view, lines, used, room, color, alpha)
	local area = 0
	for _, box in ipairs(room.boxes or {}) do
		if box[1] == view.floor then area = area + box[4] * box[5] * ROOM_GLOW * ROOM_GLOW end
	end
	if view.turn then
		-- as large as it shows on the map turned north up (since 1.3.5)
		local p, q, r, s = turnPixels(view.turn)
		area = area * math.abs(p * s - q * r)
	end
	local big = area > BIG_ROOM * MAP_W * MAP_H
	if big then alpha = math.min(alpha, BIG_ROOM_ALPHA) end
	for _, box in ipairs(room.boxes or {}) do
		if box[1] == view.floor then
			local line = lines[used + 1]
			if not line then
				line = createGlow(view, color)
				lines[used + 1] = line
			end
			used = used + 1
			placeGlow(view, line, box)
			line:SetAlpha(alpha)
			line:Show()
		end
	end
	return used, big, area / (MAP_W * MAP_H)
end

function View:UpdateRoom()
	self.numRoomLines, self.roomShare = 0, nil
	hideAll(self.roomLines)
	self.status:Hide()
	self.statusBack:Hide()
	local room = self.key ~= nil and self.key == DR.currentKey and DR.Room:Get()
	if room then
		self.status:SetText(L["You are in: %s"]:format(DR.LocText(room, "name")))
		self.status:Show()
		self.statusBack:Show()
		self:FitStatus()
		if DR.db.showRoom then
			self.numRoomLines, self.roomStill, self.roomShare = glowRoom(self, self.roomLines, 0, room, ROOM_COLOR,
				ROOM_ALPHA)
		end
	end
	self:PlaceLegend()
end

-- Content -------------------------------------------------------------------------------------

function View:SetFloor(key, floor)
	if key ~= self.key or floor ~= self.floor then
		self.key, self.floor = key, floor
		self.zoom = 1
		self:UpdateArt()
	end
	self:Refresh()
end

-- The art of the shown floor: the map tiles of the classic maps (since 1.3.3 from the addon folder) or a drawn
-- picture (floor.image), or, where the player chose so, the game's minimap pictures of the floor instead.
function View:UpdateArt()
	local floor = self.floor
	local info = DR.Floors[floor]
	local hasArt = floor ~= nil and DR.FloorHasArt(floor)
	local minimapArt = floor ~= nil and DR.MinimapArt and DR.MinimapArt[floor]
	local minimap = DR.db.gameMinimap and minimapArt
	local picture = hasArt and not minimap and info.image
	local tiles = hasArt and not minimap and not info.image
	-- What the game answers for each file the map draws (since 1.3.3, for the report in the gear menu, after green
	-- maps on Russian clients): true, false or nothing, counted as they come; own = the addon's tiles, game = the
	-- game's files (its tiles where the addon's are not known yet, its minimap pictures).
	local own, game = { yes = 0, no = 0, none = 0 }, { yes = 0, no = 0, none = 0 }
	local function tally(answers, answer)
		if answer == true then
			answers.yes = answers.yes + 1
		elseif answer == false then
			answers.no = answers.no + 1
		else
			answers.none = answers.none + 1
		end
		return answer
	end
	for i, tile in ipairs(self.tiles) do
		if tiles then
			local id = info.tiles[i]
			if tally(own, tile:SetTexture(TILE_PATH .. id, nil, nil, "TRILINEAR")) == false then
				tally(game, tile:SetTexture(id, nil, nil, "TRILINEAR"))
			end
			tile:Show()
		else
			tile:Hide()
		end
	end
	-- the addon's tiles new since the last start of the game: where the game has its own tiles they stand in unnoticed;
	-- on the clients without them (or where the game says so) the hint to restart, as for a new picture below
	local tilesNew = own.no > 0 and (WITHOUT_GAME_TILES[GetLocale()] or game.no > 0) and true or false
	-- A picture in the addon folder that is new since the last start of the game (an update with /reload only) is
	-- unknown to the game until it starts again and shows bright green. SetTexture tells (since 1.3.0, as
	-- DR.MediaReady for the window's pictures): then a hint instead, over the game's minimap pictures of the floor
	-- where there are some.
	local missing = false
	if picture then
		missing = self.picture:SetTexture(ADDON_PATH .. picture.file, nil, nil, "TRILINEAR") == false
		self.picture:SetTexCoord(0, picture.right or 1, 0, picture.bottom or 1)
		if missing then
			picture, minimap = nil, minimapArt
		end
	end
	-- the minimap pictures north up where the drawn map is turned against north (since 1.3.5): the same pictures from
	-- DR.MinimapArtNorth, and the route and everything else on the map turned with them (SetTurn)
	local turn = minimap and northTurn(floor) or nil
	if turn then
		minimap = DR.MinimapArtNorth[floor]
	end
	self:SetTurn(turn)
	self.artMissing = missing
	self.newMap:SetShown(missing or tilesNew)
	self.newMapBack:SetShown(missing or tilesNew)
	self.picture:SetShown(picture and true or false)
	-- { file, x, y, width, height, 8 texture coordinates, sublevel }: in pixels of the map, turned by the
	-- texture coordinates (a building at an angle leaves the rest of its box clear), higher building
	-- parts drawn over lower ones
	local count = minimap and #minimap or 0
	for i = 1, count do
		local part, tile = minimap[i], self.minimapTiles[i]
		if not tile then
			tile = self.canvas:CreateTexture(nil, "BACKGROUND")
			self.minimapTiles[i] = tile
		end
		tally(game, tile:SetTexture(part[1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR"))
		tile:SetTexCoord(part[6], part[7], part[8], part[9], part[10], part[11], part[12], part[13])
		tile:SetDrawLayer("BACKGROUND", part[14])
		tile:SetSize(part[4], part[5])
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", part[2], -part[3])
		tile:Show()
	end
	for i = count + 1, #self.minimapTiles do
		self.minimapTiles[i]:Hide()
	end
	local credit = hasArt and not minimap and not missing and info.credit
	if credit then
		self.credit:SetText(L["Map: %s"]:format(credit))
	end
	self.credit:SetShown(credit and true or false)
	self.creditBack:SetShown(credit and true or false)
	self.message:SetShown(floor ~= nil and not hasArt and not minimap)
	-- for the report (since 1.3.3): which art the floor shows and the game's answers for its files; "gametiles" where
	-- tiles of the addon were not known yet and the game's stood in. No floor stays unknown (nil), not "none".
	if floor == nil then
		self.artSource = nil
	elseif count > 0 then
		self.artSource = "minimap"
	elseif picture then
		self.artSource = "picture"
	elseif tiles then
		self.artSource = own.no > 0 and "gametiles" or "tiles"
	else
		self.artSource = "none"
	end
	self.artAnswers = (self.artSource == "tiles" and own)
		or ((self.artSource == "gametiles" or self.artSource == "minimap") and game) or nil
	self.ownTilesRefused = tiles and own.no or nil
	self.tilesNew = tilesNew
	self:UpdateArtToggle()
end

function View:Refresh()
	self.route = self.key and DR:GetActiveRoute(self.key)
	self:ReleasePins()
	if self.route and self.floor then
		self:AddPins()
	end
	if self.floor then
		self:AddMapNotes()
	end
	self:UpdateExtent() -- what the map shows, before Layout fits it (since 1.3.5)
	self:Layout()
	self:UpdateRoom()
	self:UpdateMembers()
	self:UpdateGroup()
	self:UpdatePing()
	self:UpdateOwnMarker()
end

-- The own marker on its floor (since 1.3.2), not while it hangs on the mouse.
function View:UpdateOwnMarker()
	if self.dragOwn then return end
	local marker = DR:GetMarker(self.key)
	if marker and marker.floor == self.floor then
		self:PlacePin(self.own, marker.x, marker.y)
		self.own:Show()
	else
		self.own:Hide()
	end
	-- on the map turned north up a marker beyond its rectangle widens what the map shows (since 1.3.5)
	if self.turn and self:UpdateExtent() then
		self:Layout()
	end
	self:UpdateMarkerHint()
end

-- The own marker let go after dragging: it stays where the mouse is (a click without moving keeps it in place).
function View:DropOwnMarker()
	local drag = self.dragOwn
	self.dragOwn = nil
	if drag and drag.u and self.key and self.floor then
		DR:SetMarker(self.key, self.floor, drag.u, drag.v)
	else
		self:UpdateOwnMarker()
	end
end

-- The padlock shut (shackle down, full gold) or open (shackle lifted, faint), since 1.3.2.
function View:UpdateLock()
	local lock = self.lock
	if not lock then return end
	local locked = DR.db.lockWindow == true
	local alpha = locked and 1 or 0.55
	lock.Shackle:ClearAllPoints()
	lock.Shackle:SetPoint("BOTTOM", lock.Body, "TOP", locked and 0 or 2, locked and -1 or 2)
	lock.Shackle:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], alpha)
	lock.Body:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], alpha)
end

-- The switch to the minimap pictures (since 1.3.4): only where the floor has minimap pictures and the map is wide enough,
-- bright while the map shows them. Not while they only stand in for a drawn picture the game does not know yet
-- (artMissing): a click would change nothing there before the restart.
function View:UpdateArtToggle()
	local art = self.artToggle
	if not art then return end
	local floor = self.floor
	local available = floor ~= nil and DR.MinimapArt ~= nil and DR.MinimapArt[floor] ~= nil and not self.artMissing
	art:SetShown(available and (self.width or 0) >= ART_TOGGLE_MIN_W)
	local alpha = self.artSource == "minimap" and 1 or 0.55
	art.Ring:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], alpha)
	art.Arrow:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], alpha)
	self:FitStatus()
end

-- The room's name in the lower left ends before the buttons in the lower right (since 1.3.4: with the switch to the
-- minimap pictures that row grew by one button, and on the small map a long name ran under it). A name that does not
-- fit is cut by the game with "...".
local STATUS_LEFT, STATUS_PAD, BUTTON_GAP, BUTTON_MARGIN = 14, 7, 4, 6

function View:FitStatus()
	local status, frame = self.status, self.frame
	if not status or not frame then return end
	local right = BUTTON_MARGIN
	for _, button in ipairs({ self.locate, self.help, self.lock, self.artToggle }) do
		if button and button:IsShown() then
			right = right + button:GetWidth() + BUTTON_GAP
		end
	end
	local room = (frame:GetWidth() or 0) - STATUS_LEFT - STATUS_PAD - right
	status:SetWidth(0)
	if room > 0 and (status:GetStringWidth() or 0) > room then
		status:SetWidth(room)
	end
end

-- The others in the group ----------------------------------------------------------------------
-- Every addon in the group tells the room its player is in (Group.lua). Since 1.2.4 a setting of its own (showGroup,
-- on at first), and nothing over the map but a small number in each room someone is in (as far as the game names
-- rooms there), with a legend in the lower left corner: number, name, room (Oliver, 14.11.2026: nothing over the
-- map, rather a legend). Where the rooms glow (showRoom) their rooms glow blue as well.

local LEGEND_LINES = 5              -- players in the legend, the others count as "+n"
local LEGEND_ELSEWHERE = "ff9aa3ad" -- a player on another floor or in a room the game does not name: no number here

local function createLabel(view)
	local label = CreateFrame("Frame", nil, view.canvas)
	label:SetSize(10, 10)
	label:SetFrameLevel(view.canvas:GetFrameLevel() + 18)
	label:EnableMouse(false)
	label.Text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label.Text:SetPoint("CENTER")
	label.Text:SetTextColor(MEMBER_COLOR[1], MEMBER_COLOR[2], MEMBER_COLOR[3])
	label.Back = label:CreateTexture(nil, "BACKGROUND")
	label.Back:SetPoint("TOPLEFT", label.Text, "TOPLEFT", -5, 3)
	label.Back:SetPoint("BOTTOMRIGHT", label.Text, "BOTTOMRIGHT", 5, -3)
	label.Back:SetColorTexture(0.05, 0.05, 0.06, 0.82)
	label:Hide()
	return label
end

-- Places the legend in the lower left corner, above the name of the player's room where that stands.
function View:PlaceLegend()
	local legend = self.legend
	if not legend then return end
	legend:ClearAllPoints()
	if self.status:IsShown() then
		legend:SetPoint("BOTTOMLEFT", self.status, "TOPLEFT", 0, 11)
	else
		legend:SetPoint("BOTTOMLEFT", self.overlay, "BOTTOMLEFT", 14, 13)
	end
end

-- The legend: one line per player of the group in the shown dungeon, numbered as on the map; grey where this floor
-- shows no number for them.
function View:UpdateLegend(list)
	if #list == 0 then
		self.legend:Hide()
		self.legendBack:Hide()
		return
	end
	local lines = {}
	for i, m in ipairs(list) do
		if i > LEGEND_LINES then
			lines[#lines + 1] = "+" .. (#list - LEGEND_LINES)
			break
		end
		local line = L["%d %s: %s"]:format(i, m.name, m.room and DR.LocText(m.room, "name") or L["room unknown"])
		if not (m.room and self.floor and DR.Room:OnFloor(m.room, self.floor)) then
			line = "|c" .. LEGEND_ELSEWHERE .. line .. "|r"
		end
		lines[#lines + 1] = line
	end
	self.legend:SetText(table.concat(lines, "\n"))
	self.legend:Show()
	self.legendBack:Show()
	self:PlaceLegend()
end

function View:UpdateMembers()
	if not self.memberLines then return end
	self.numMemberLines = 0
	hideAll(self.memberLines)
	hideAll(self.memberLabels)
	local list = self.key and DR.db.showGroup and DR.Group:InDungeon(self.key) or {}
	self:UpdateLegend(list)
	if not self.floor then return end
	-- the numbers of the legend by room, on the shown floor
	local rooms, byRoom = {}, {}
	for i, m in ipairs(list) do
		if m.room and DR.Room:OnFloor(m.room, self.floor) then
			local entry = byRoom[m.room]
			if not entry then
				entry = { room = m.room, numbers = {} }
				byRoom[m.room] = entry
				rooms[#rooms + 1] = entry
			end
			table.insert(entry.numbers, i)
		end
	end
	for i, entry in ipairs(rooms) do
		if DR.db.showRoom then
			self.numMemberLines = glowRoom(self, self.memberLines, self.numMemberLines, entry.room, MEMBER_COLOR,
				MEMBER_ALPHA)
		end
		local u, v = DR.Room:Center(entry.room, self.floor)
		if u then
			local label = self.memberLabels[i]
			if not label then
				label = createLabel(self)
				self.memberLabels[i] = label
			end
			label.Text:SetText(table.concat(entry.numbers, ","))
			label:Show()
			self:PlacePin(label, u, v)
		end
	end
end

-- A stop someone showed to the group: a pulsing ring while it lasts.
function View:UpdatePing()
	if not self.ping then return end
	local shownStop = DR.Group:GetShownStop()
	if shownStop and shownStop.key == self.key and shownStop.floor == self.floor then
		self.ping:Show()
		self:PlacePin(self.ping, shownStop.x, shownStop.y)
	else
		self.ping:Hide()
	end
end

function View:RequestRedraw()
	if self.redrawPending then return end
	self.redrawPending = true
	C_Timer.After(0, function()
		View.redrawPending = nil
		View:DrawLines()
	end)
end

-- Lines ---------------------------------------------------------------------------------------

function View:ReleaseLines()
	for i = 1, self.numLines do
		self.lines[i]:Hide()
	end
	self.numLines = 0
	for i = 1, self.numDots do
		self.dots[i]:Hide()
	end
	self.numDots = 0
end

function View:Segment(subLevel, x1, y1, x2, y2, thickness, r, g, b, a)
	self.numLines = self.numLines + 1
	local line = self.lines[self.numLines]
	if not line then
		line = self.layer:CreateLine(nil, "ARTWORK")
		self.lines[self.numLines] = line
	end
	line:SetDrawLayer("ARTWORK", subLevel)
	line:SetStartPoint("TOPLEFT", self.layer, x1, -y1)
	line:SetEndPoint("TOPLEFT", self.layer, x2, -y2)
	line:SetThickness(thickness)
	line:SetColorTexture(r, g, b, a or 1)
	line:Show()
	return line
end

function View:Dot(x, y, size, r, g, b, a)
	self.numDots = self.numDots + 1
	local dot = self.dots[self.numDots]
	if not dot then
		dot = self.layer:CreateTexture(nil, "OVERLAY")
		dot:SetTexture(MEDIA .. "circle")
		self.dots[self.numDots] = dot
	end
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", self.layer, "TOPLEFT", x, -y)
	dot:SetSize(size, size)
	dot:SetVertexColor(r, g, b, a or 1)
	dot:Show()
	return dot
end

local function toCanvas(view, pts)
	local xs, ys = {}, {}
	for i = 1, #pts / 2 do
		xs[i], ys[i] = view:ToCanvas(pts[2 * i - 1], pts[2 * i])
	end
	return xs, ys
end

-- k is the canvas scale: widths are given in screen units and divided by it, so lines keep their
-- width on screen while zooming.
function View:DrawMainPath(path, k)
	local xs, ys = toCanvas(self, path.pts)
	local n = #xs
	if n < 2 then return end
	local width = (DR.db.lineWidth or 4) / k
	local casing = width + 3 / k
	local cum = { 0 }
	for i = 2, n do
		local dx, dy = xs[i] - xs[i - 1], ys[i] - ys[i - 1]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
	end
	local total = cum[n] > 0 and cum[n] or 1
	local t0, t1 = path.t0 or 0, path.t1 or 1
	for i = 2, n do
		self:Segment(-6, xs[i - 1], ys[i - 1], xs[i], ys[i], casing, unpack(CASING_COLOR))
	end
	local fixed = DR.LineColor()
	for i = 2, n do
		local r, g, b
		if fixed then
			r, g, b = fixed[1], fixed[2], fixed[3]
		else
			r, g, b = gradient(t0 + (t1 - t0) * ((cum[i - 1] + cum[i]) * 0.5 / total))
		end
		self:Segment(0, xs[i - 1], ys[i - 1], xs[i], ys[i], width, r, g, b, 1)
	end
	if DR.db.showArrows then
		local spacing, size = 64 / k, 5 / k
		local s = spacing * 0.6
		local i = 2
		while s < cum[n] - 8 / k do
			while cum[i] < s do
				i = i + 1
			end
			local seg = cum[i] - cum[i - 1]
			local u = seg > 0 and (s - cum[i - 1]) / seg or 0
			local mx = xs[i - 1] + (xs[i] - xs[i - 1]) * u
			local my = ys[i - 1] + (ys[i] - ys[i - 1]) * u
			local angle = math.atan2(ys[i] - ys[i - 1], xs[i] - xs[i - 1])
			local ax1 = mx - size * math.cos(angle - 0.75)
			local ay1 = my - size * math.sin(angle - 0.75)
			local ax2 = mx - size * math.cos(angle + 0.75)
			local ay2 = my - size * math.sin(angle + 0.75)
			local thick = 2 / k
			self:Segment(4, ax1, ay1, mx, my, thick, unpack(ARROW_COLOR))
			self:Segment(4, ax2, ay2, mx, my, thick, unpack(ARROW_COLOR))
			s = s + spacing
		end
	end
	return xs, ys
end

function View:DrawSidePath(path, k)
	local xs, ys = toCanvas(self, path.pts)
	local n = #xs
	if n < 2 then return end
	local width = math.max(2, (DR.db.lineWidth or 4) - 1) / k
	local casing = width + 3 / k
	local dash, gap = 7 / k, 5 / k
	-- whitish grey beside the gradient, in the colour of the main path where the player chose one (since 1.3.0)
	local color = DR.LineColor() or SIDE_COLOR
	for i = 2, n do
		self:Segment(-6, xs[i - 1], ys[i - 1], xs[i], ys[i], casing, CASING_COLOR[1], CASING_COLOR[2], CASING_COLOR[3], 0.55)
	end
	local phase, drawing = dash, true
	for i = 2, n do
		local x1, y1, x2, y2 = xs[i - 1], ys[i - 1], xs[i], ys[i]
		local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local pos = 0
		while pos < len do
			local step = math.min(phase, len - pos)
			if drawing then
				local a, b = pos / len, (pos + step) / len
				self:Segment(0, x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b,
					width, color[1], color[2], color[3], 1)
			end
			pos = pos + step
			phase = phase - step
			if phase <= 0 then
				drawing = not drawing
				phase = drawing and dash or gap
			end
		end
	end
	return xs, ys
end

function View:DrawLines()
	self:ReleaseLines()
	local route, floor = self.route, self.floor
	if not route or not floor then return end
	local k = self.scale
	if not k or k <= 0 then return end
	local editingRoute = DR.Editor:IsEditing(self.key, route)
	for index, path in ipairs(route.paths) do
		if path.floor == floor then
			local xs, ys
			if path.kind == "main" then
				xs, ys = self:DrawMainPath(path, k)
			else
				xs, ys = self:DrawSidePath(path, k)
			end
			if editingRoute and xs then
				local active = DR.Editor:IsActivePath(index)
				for i = 1, #xs do
					local size = (active and i == #xs) and 9 / k or 5 / k
					self:Dot(xs[i], ys[i], size, unpack(EDIT_DOT_COLOR))
				end
			end
		end
	end
	-- editing on the map turned north up (since 1.3.5): a thin line along the edge of the drawn map. Route points go
	-- only inside it (they are kept in the drawn map's coordinates), while the north-up map can show more around it.
	if editingRoute and self.turn then
		local xs, ys = {}, {}
		for i, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }) do
			xs[i], ys[i] = self:ToCanvas(corner[1], corner[2])
		end
		for i = 1, 4 do
			local j = i % 4 + 1
			self:Segment(-2, xs[i], ys[i], xs[j], ys[j], 1.5 / k, unpack(EDGE_COLOR))
		end
	end
end

-- Pins ----------------------------------------------------------------------------------------

-- A pin at a point in the drawn map's coordinates (kept in pin.u, pin.v; drawn turned where the map is north up).
function View:PlacePin(pin, u, v)
	pin.u, pin.v = u, v
	local s = self.scale
	local x, y = self:ToCanvas(u, v)
	pin:SetScale(1 / s)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", self.canvas, "TOPLEFT", x * s, -y * s)
end

local function eachPin(view, fn)
	for i = 1, view.numStops do fn(view.stopPins[i]) end
	for i = 1, view.numNotes do fn(view.notePins[i]) end
	for i = 1, view.numLinks do fn(view.linkPins[i]) end
end

function View:PlaceAllPins()
	eachPin(self, function(pin) self:PlacePin(pin, pin.u, pin.v) end)
	if self.player:IsShown() and self.player.u then
		self:PlacePin(self.player, self.player.u, self.player.v)
	end
	for _, dot in ipairs(self.party) do
		if dot:IsShown() and dot.u then
			self:PlacePin(dot, dot.u, dot.v)
		end
	end
	for _, label in ipairs(self.memberLabels or {}) do
		if label:IsShown() and label.u then
			self:PlacePin(label, label.u, label.v)
		end
	end
	if self.ping and self.ping:IsShown() and self.ping.u then
		self:PlacePin(self.ping, self.ping.u, self.ping.v)
	end
	if self.own and self.own:IsShown() and self.own.u then
		self:PlacePin(self.own, self.own.u, self.own.v)
	end
end

function View:ReleasePins()
	-- "dragged" stays: the click that ends a drag arrives after the pins were drawn again
	eachPin(self, function(pin)
		pin:Hide()
		pin:SetScript("OnUpdate", nil)
		pin.dragging = nil
	end)
	self.numStops, self.numNotes, self.numLinks = 0, 0, 0
end

local function acquire(view, list, countKey, create)
	view[countKey] = view[countKey] + 1
	local pin = list[view[countKey]]
	if not pin then
		pin = create(view)
		list[view[countKey]] = pin
	end
	pin:Show()
	return pin
end

function View:AddPins()
	local key, route, floor = self.key, self.route, self.floor
	local labels = DR:GetStopLabels(route)
	local nextIndex = DR:GetNextStopIndex(key, route)
	for i, stop in ipairs(route.stops) do
		if DR.OnFloor(stop, floor) then
			local pin = acquire(self, self.stopPins, "numStops", createStopPin)
			pin.route, pin.index, pin.stop = route, i, stop
			local style = KIND_STYLE[stop.kind] or KIND_STYLE.boss
			local done = DR:IsStopDone(key, route, i)
			pin.Label:SetText(labels[i])
			pin.Label:SetTextColor(style.text[1], style.text[2], style.text[3])
			pin.Ring:SetVertexColor(style.ring[1], style.ring[2], style.ring[3])
			pin.Fill:SetVertexColor(0.06, 0.05, 0.04, 0.92)
			pin.Check:SetShown(done)
			pin:SetAlpha(done and 0.55 or 1)
			pin.isNext = i == nextIndex and not done
			pin.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
			pin.Glow:SetShown(pin.isNext)
			self:PlacePin(pin, stop.x, stop.y)
		end
	end
	for i, note in ipairs(route.notes) do
		if DR.OnFloor(note, floor) then
			local pin = acquire(self, self.notePins, "numNotes", createNotePin)
			pin.route, pin.index, pin.note = route, i, note
			self:PlacePin(pin, note.x, note.y)
		end
	end
	for _, link in ipairs(collectLinks(route)) do
		if link.floor == floor and DR:GetDungeonForFloor(link.to) == DR:GetDungeon(key) then
			local pin = acquire(self, self.linkPins, "numLinks", createLinkPin)
			pin.link = link
			if link.label and link.label ~= "" then
				pin.Label:SetText(link.label)
			else
				pin.Label:SetText(link.forward and ">" or "<")
			end
			self:PlacePin(pin, link.x, link.y)
		end
	end
end

-- Remarks on the drawn map art (DR.MapNotes in Data/DefaultRoutes.lua), the same for every route: a
-- skull of a later version of the dungeon where WoW: Forever has no boss, a part of a cave the art
-- leaves out. The game's minimap pictures have neither, so the remarks stay off there. Not part of a
-- route, so the editor leaves them alone.
function View:AddMapNotes()
	local floor = self.floor
	-- nor where the drawn picture is missing (since 1.3.0, UpdateArt)
	if self.artMissing or (DR.db.gameMinimap and DR.MinimapArt and DR.MinimapArt[floor]) then
		return
	end
	for _, note in ipairs(DR.MapNotes and DR.MapNotes[floor] or {}) do
		local pin = acquire(self, self.notePins, "numNotes", createNotePin)
		pin.route, pin.index, pin.note = nil, nil, note
		self:PlacePin(pin, note.x, note.y)
	end
end

function View:HighlightStop(index)
	for i = 1, self.numStops do
		local pin = self.stopPins[i]
		if pin.index == index then
			pin.Glow:SetVertexColor(1, 1, 1, 0.8)
			pin.Glow:Show()
		else
			pin.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
			pin.Glow:SetShown(pin.isNext)
		end
	end
end

-- Own position and group ----------------------------------------------------------------------
-- Inside dungeons the game gives addons no positions (since patch 7.1), so this usually shows
-- nothing there; it stays for places where the game does reveal them.

function View:HideGroup()
	self.player:Hide()
	for _, dot in ipairs(self.party) do
		dot:Hide()
	end
end

function View:UpdateGroup()
	local inside = self.key ~= nil and self.key == DR.currentKey
	-- the crosshair inside every dungeon the addon knows, also while the map shows another one: a click finds
	-- the dungeon again (for a player who loaded the addon inside and sees the wrong one)
	self.locate:SetShown(inside or DR:InKnownInstance())
	self:PlaceHelp()
	self:FitStatus() -- the crosshair takes room from the room's name (since 1.3.4)
	self:UpdateMarkerHint()
	if not inside or not DR.db.showPlayer then
		self:HideGroup()
		return
	end
	local _, floor, u, v = DR:LocatePlayer(self.floor)
	if not floor then
		self:HideGroup()
		return
	end
	if floor ~= self.floor then
		if DR.Window:IsFollowing() then
			DR.Window:SelectFloor(floor)
			return
		end
		self.player:Hide()
	else
		local player = self.player
		local facing = DR:GetPlayerFacing()
		player.Arrow:SetShown(facing ~= nil)
		player.Dot:SetShown(facing == nil)
		player.Ring:SetShown(facing == nil)
		if facing then
			player.Arrow:SetRotation(facing)
		end
		player:Show()
		self:PlacePin(player, u, v)
	end
	local members = DR:GroupOnFloor(self.floor)
	for i, member in ipairs(members) do
		local dot = self.party[i]
		if not dot then
			dot = createMarker(self, 18, 19)
			self.party[i] = dot
		end
		dot.Dot:SetVertexColor(member.r, member.g, member.b, 1)
		dot:Show()
		self:PlacePin(dot, member.u, member.v)
	end
	for i = #members + 1, #self.party do
		self.party[i]:Hide()
	end
end

-- Where the player stands on the shown floor, if known.
function View:GetPlayerUV()
	if self.player:IsShown() then
		return self.player.u, self.player.v
	end
	return nil
end
