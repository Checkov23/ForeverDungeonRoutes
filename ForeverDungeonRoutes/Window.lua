local _, DR = ...
local L = DR.L

-- The route window, in the spirit of MDT: the dungeon map with the route on the left, the stops
-- of the route on the right. Dungeon and floor are chosen in the header. Inside a dungeon the map
-- follows the run until a floor is chosen by hand: the game gives addons no position there, so
-- the map shows the floor of the next boss that is still open.

local HEADER_H = 36
local SIDEBAR_W = 240
local PAD = 10
local ROW_HEIGHT = 18
local MIN_W, MIN_H = 520, 320
local ROUTE_Y, LIST_Y = -30, -60 -- route choice and stop list below the level, time and entrance lines
local DEFAULT_W, DEFAULT_H = 900, 480
local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- style "Gilded" (Theme.lua, ornate): a taller header with the title and the floor tabs, a footer,
-- the route choice on top of the sidebar and a head line over the stops
local ORNATE_HEADER_H, FOOTER_H = 92, 26
local ORNATE_ROUTE_Y, ORNATE_LIST_Y = 0, -52

local Window = {}
DR.Window = Window

local frame, view, sidebar
local shown = {}       -- key, floor
local following = true
local rows = {}

-- Small helpers ---------------------------------------------------------------------------

local function makeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:GetFontString():SetFontObject(GameFontNormalSmall)
	return b
end

local function makeDropButton(parent, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	DR.StyleBox(b, 1, "field")
	b:SetSize(width, 22)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 8, 0)
	b.Text:SetPoint("RIGHT", -18, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	DR.ThemeText(b.Text, "fieldText")
	b.Arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Arrow:SetPoint("RIGHT", -6, 0)
	b.Arrow:SetText("v")
	DR.ThemeText(b.Arrow, "arrow")
	b:SetScript("OnEnter", function(self)
		DR.HoverBox(self, true)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
			if self.tooltipExtra then
				GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
			end
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		DR.HoverBox(self, false)
		GameTooltip:Hide()
	end)
	return b
end

local function makeIconButton(parent, texture, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetTexture(MEDIA .. texture)
	b.Icon:SetAllPoints()
	DR.ThemeIcon(b.Icon, "icon")
	b:SetScript("OnEnter", function(self)
		local c = DR.Theme().iconHover
		self.Icon:SetVertexColor(c[1], c[2], c[3])
	end)
	b:SetScript("OnLeave", function(self)
		local c = DR.Theme().icon
		self.Icon:SetVertexColor(c[1], c[2], c[3])
	end)
	return b
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
	return nil
end

-- The decoration of the chosen style (Theme.lua: ornate), or nil.
local function ornate()
	return DR.Theme().ornate
end

local function rowHeight()
	return ornate() and 20 or ROW_HEIGHT
end

local styleOrnate

-- Geometry ----------------------------------------------------------------------------------

local function saveGeometry()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local g = DR.db.window
	g.point, g.relativePoint, g.x, g.y = point, relativePoint, x, y
	g.width, g.height = frame:GetWidth(), frame:GetHeight()
end

local function restoreGeometry()
	local g = DR.db.window
	frame:ClearAllPoints()
	if g.point then
		frame:SetPoint(g.point, UIParent, g.relativePoint or g.point, g.x or 0, g.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	frame:SetSize(math.max(MIN_W, g.width or DEFAULT_W), math.max(MIN_H, g.height or DEFAULT_H))
end

local function layout()
	local o = ornate()
	local top, bottom = o and ORNATE_HEADER_H or HEADER_H, o and (PAD + FOOTER_H) or PAD
	frame.Header:SetHeight(top)
	local map = view.frame
	map:ClearAllPoints()
	map:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
	sidebar:ClearAllPoints()
	sidebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -top)
	sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, o and bottom or (PAD + 10))
	sidebar:SetWidth(SIDEBAR_W - PAD)
	sidebar.Scroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, o and ORNATE_LIST_Y or LIST_Y)
	frame.RouteButton:ClearAllPoints()
	if DR.db.showStops then
		sidebar:Show()
		map:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(SIDEBAR_W + PAD), bottom)
		frame.RouteButton:SetParent(sidebar)
		frame.RouteButton:SetFrameLevel(sidebar:GetFrameLevel() + 2)
		local y = o and ORNATE_ROUTE_Y or ROUTE_Y
		frame.RouteButton:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, y)
		frame.RouteButton:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, y)
	else
		sidebar:Hide()
		map:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, bottom)
		-- without the stop list the route choice sits on the map
		frame.RouteButton:SetParent(map)
		frame.RouteButton:SetFrameLevel(map:GetFrameLevel() + 40)
		frame.RouteButton:SetPoint("TOPRIGHT", map, "TOPRIGHT", -6, -6)
		frame.RouteButton:SetWidth(210)
	end
	styleOrnate()
end

-- Menus -------------------------------------------------------------------------------------

local function exportRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	if not route then return end
	DR.Dialog.ShowText(L["Export route"], L["Copy the text with Ctrl+C and share it. Others can paste it via Import."],
		DR:ExportRoute(key, route))
end

local function importRoute()
	DR.Dialog.AskText(L["Import route"], L["Paste a route text with Ctrl+V."], function(text)
		local key, route = DR:ImportRoute(text)
		if not key then
			return route
		end
		DR:AddImportedRoute(key, route)
		DR:Print(L["Route imported: %s"], DR:GetRouteName(route))
		Window:Open(key, DR:GetRouteStartFloor(route))
	end, L["Import"])
end

local function renameRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	DR.Dialog.AskLine(L["Rename route"], nil, DR:GetRouteName(route), function(name)
		if name == "" then return L["Please enter a name."] end
		DR:RenameRoute(key, route, name)
	end)
end

local function deleteRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	DR.Dialog.Confirm(L["Delete route"], L["Delete the route \"%s\"? This cannot be undone."]:format(DR:GetRouteName(route)),
		function()
			if DR.Editor:IsEditing(key, route) then
				DR.Editor:Stop()
			end
			DR:DeleteRoute(key, route)
		end, DELETE or L["Delete"])
end

local function newRoute()
	local key = shown.key
	DR.Dialog.AskLine(L["New route"], L["Name of the new route:"], L["My route"], function(name)
		if name == "" then return L["Please enter a name."] end
		local route = DR:NewRoute(key, name)
		DR.Editor:Start(key, route)
	end)
end

local function openRouteMenu(owner)
	local key = shown.key
	local current = DR:GetActiveRoute(key)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Routes"])
		for _, route in ipairs(DR:GetRoutes(key)) do
			root:CreateRadio(DR:GetRouteName(route), function() return route == DR:GetActiveRoute(key) end,
				function() DR:SetActiveRoute(key, route.id) end)
		end
		root:CreateDivider()
		root:CreateButton(L["New route"], newRoute)
		local recorded = root:CreateButton(L["Route from the last run"], function()
			local route = DR.Recorder:Build(key)
			if route then DR.Window:Open(key, DR:GetRouteStartFloor(route)) end
		end)
		recorded:SetEnabled(DR.Recorder:CanBuild(key))
		if current then
			root:CreateButton(L["Copy route"], function()
				local copy = DR:CopyRoute(key, current)
				DR:Print(L["Copied. The copy can be edited: %s"], DR:GetRouteName(copy))
			end)
			if not DR:IsBuiltIn(current) then
				root:CreateButton(L["Rename route"], renameRoute)
				root:CreateButton(L["Delete route"], deleteRoute)
			end
			root:CreateDivider()
			local share = root:CreateButton(L["Share"])
			local send = share:CreateButton(L["Send to group"], function() DR.Share:SendRoute(key, current) end)
			send:SetEnabled(DR.Share:Channel() ~= nil)
			local guild = share:CreateButton(L["Send to guild"], function() DR.Share:SendRoute(key, current, "GUILD") end)
			guild:SetEnabled(DR.Share:InGuild())
			share:CreateButton(L["Post the boss order in the group chat"], function() DR.Share:PostOrder(key, current) end)
			share:CreateButton(L["Export route"], exportRoute)
			if not DR:IsBuiltIn(current) then
				share:CreateCheckbox(L["In the route list"], function() return DR.RouteList:IsPublished(key, current) end,
					function() DR.RouteList:Publish(key, current, not DR.RouteList:IsPublished(key, current)) end)
			end
			if current.listHash then
				-- taken over from the route list: one recommendation for its author
				local liked = DR.db.liked[current.listHash]
				local recommend = root:CreateButton(liked and L["Recommended"] or L["Recommend this route"],
					function() DR.RouteList:Recommend(current) end)
				recommend:SetEnabled(not liked)
			end
		else
			root:CreateDivider()
		end
		root:CreateButton(L["Import route"], importRoute)
		-- routes other players put in the route list, to take over with one click
		local list = root:CreateButton(L["Route list"])
		list:CreateButton(L["Refresh the list"], function() DR.RouteList:Refresh(key) end)
		local entries = DR.RouteList:Entries(key)
		if #entries == 0 then
			local none = list:CreateButton(L["No routes from other players yet."])
			none:SetEnabled(false)
		else
			list:CreateDivider()
			for _, item in ipairs(entries) do
				local e = item.entry
				local label = (e.likes or 0) > 0
					and L["%s by %s, %d stops, recommendations: %d"]:format(e.name, DR.Share.SenderName(e.author), e.stops, e.likes)
					or L["%s by %s, %d stops"]:format(e.name, DR.Share.SenderName(e.author), e.stops)
				list:CreateButton(label, function() DR.RouteList:Fetch(item.hash) end)
			end
		end
	end)
end

local function openDungeonMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local level = DR.PlayerLevel()
		root:CreateTitle(level and L["Dungeons (level %d)"]:format(level) or L["Dungeons"])
		local raids -- the raids in a submenu at the end, so the list stays short
		for _, dungeon in ipairs(DR.Dungeons) do
			local key = dungeon.key
			local text = DR:GetKeyName(key)
			local color = DR:GetLevelColor(key, level)
			if color then
				text = "|cff" .. color .. text .. "|r"
			end
			if dungeon.levels then
				text = text .. "  |cff8c8c8c" .. DR:GetLevelRange(key) .. "|r"
			end
			if key == DR.currentKey then
				text = text .. "  |cffffd75c" .. L["(you are here)"] .. "|r"
			end
			local parent = root
			if dungeon.raid then
				if not raids then
					root:CreateDivider()
					raids = root:CreateButton(L["Raids"])
				end
				parent = raids
			end
			parent:CreateRadio(text, function() return shown.key == key end, function()
				following = key == DR.currentKey
				Window:ShowDungeon(key)
			end)
		end
	end)
end

local function openFloorMenu(owner)
	local dungeon = DR:GetDungeon(shown.key)
	if not dungeon then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Map level"])
		for i, floor in ipairs(dungeon.floors) do
			root:CreateRadio(i .. ". " .. DR:GetFloorName(floor), function() return shown.floor == floor end,
				function() Window:SelectFloor(floor, true) end)
		end
	end)
end

local function setting(key, value)
	DR.db[key] = value
	DR:Fire("SETTINGS_CHANGED", key)
end

local function openSettingsMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Settings"])
		root:CreateCheckbox(L["Stop list beside the map"], function() return DR.db.showStops end,
			function() setting("showStops", not DR.db.showStops) end)
		root:CreateCheckbox(L["Arrows on the route"], function() return DR.db.showArrows end,
			function() setting("showArrows", not DR.db.showArrows) end)
		root:CreateCheckbox(L["Map from the game's minimap"], function() return DR.db.gameMinimap end,
			function() setting("gameMinimap", not DR.db.gameMinimap) end)
		root:CreateCheckbox(L["Tick off bosses automatically"], function() return DR.db.autoCheck end,
			function() setting("autoCheck", not DR.db.autoCheck) end)
		root:CreateCheckbox(L["Open automatically in dungeons"], function() return DR.db.autoOpen end,
			function() setting("autoOpen", not DR.db.autoOpen) end)
		root:CreateCheckbox(L["Button at the minimap"], function() return DR.db.minimapButton end,
			function() setting("minimapButton", not DR.db.minimapButton) end)
		root:CreateCheckbox(L["Small display in dungeons"], function() return DR.db.showTracker end,
			function() setting("showTracker", not DR.db.showTracker) end)
		root:CreateCheckbox(L["Route list over the server channel"], function() return DR.db.listChannel end,
			function()
				setting("listChannel", not DR.db.listChannel)
				DR.RouteList:SetChannel(DR.db.listChannel)
			end)
		local width = root:CreateButton(L["Line width"])
		for _, w in ipairs({ 3, 4, 5, 6 }) do
			width:CreateRadio(tostring(w), function() return DR.db.lineWidth == w end, function() setting("lineWidth", w) end)
		end
		local size = root:CreateButton(L["Text size of the stop list"])
		for _, scale in ipairs({ 0.9, 1, 1.15, 1.3 }) do
			size:CreateRadio(math.floor(scale * 100 + 0.5) .. "%", function() return DR.db.listScale == scale end,
				function() setting("listScale", scale) end)
		end
		local style = root:CreateButton(L["Window style"])
		for _, theme in ipairs(DR.THEMES) do
			style:CreateRadio(DR.ThemeName(theme), function() return DR.Theme() == theme end,
				function() DR:SetTheme(theme.key) end)
		end
		local opacity = root:CreateButton(L["Opacity"])
		for _, a in ipairs({ 1, 0.85, 0.7, 0.55 }) do
			opacity:CreateRadio(math.floor(a * 100 + 0.5) .. "%", function() return DR.db.alpha == a end,
				function() setting("alpha", a) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Reset window size and position"], function()
			DR.db.window = {}
			restoreGeometry()
		end)
		root:CreateDivider()
		root:CreateTitle(("Forever Dungeon Routes %s, \194\169 2026 Checkov23"):format(DR.version))
	end)
end

-- Stop list -----------------------------------------------------------------------------------

local function makeRow(index)
	local row = CreateFrame("Button", nil, sidebar.List)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetAllPoints()
	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints()
	row.Hover:Hide()
	-- style "Gilded": every other row darker, the next stop filled with a gold edge on the left
	row.Band = row:CreateTexture(nil, "BACKGROUND", nil, -2)
	row.Band:SetAllPoints()
	row.Band:Hide()
	row.NextFill = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.NextFill:SetAllPoints()
	row.NextFill:Hide()
	row.NextBar = row:CreateTexture(nil, "ARTWORK")
	row.NextBar:SetPoint("TOPLEFT")
	row.NextBar:SetPoint("BOTTOMLEFT")
	row.NextBar:SetWidth(2)
	row.NextBar:Hide()

	row.Badge = row:CreateTexture(nil, "ARTWORK")
	row.Badge:SetTexture(MEDIA .. "ring")
	row.Badge:SetSize(16, 16)
	row.Badge:SetPoint("LEFT", 5, 0)
	row.BadgeFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.BadgeFill:SetTexture(MEDIA .. "circle")
	row.BadgeFill:SetAllPoints(row.Badge)
	row.Number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Number:SetPoint("CENTER", row.Badge, "CENTER", 0, 0)
	DR.ThemeText(row.Number)

	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetTexture(MEDIA .. "check")
	row.Check:SetSize(14, 14)
	row.Check:SetPoint("RIGHT", -2, 0)

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Badge, "RIGHT", 6, 0)
	row.Name:SetPoint("RIGHT", row.Check, "LEFT", -4, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	DR.ThemeText(row.Name)

	row:SetScript("OnEnter", function(self)
		DR:Fire("HIGHLIGHT_STOP", self.index)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.stopName, 1, 0.82, 0)
		if self.note and self.note ~= "" then
			GameTooltip:AddLine(self.note, 1, 1, 1, true)
		end
		if self.otherFloor then
			GameTooltip:AddLine(L["On another map level"] .. ": " .. DR:GetFloorName(self.floor), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(L["Click: mark as done\nShift-click: show on map\nAlt-click: show to the group"], 0.4, 0.8, 1, true)
		if self.auto and DR.db.autoCheck then
			GameTooltip:AddLine(L["Ticks itself off when the boss dies."], 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		DR:Fire("HIGHLIGHT_STOP", nil)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if IsAltKeyDown() and button == "LeftButton" then
			DR.Group:ShowStop(shown.key, DR:GetActiveRoute(shown.key), self.index)
		elseif IsShiftKeyDown() or button == "RightButton" then
			Window:FocusStop(self.index)
		else
			DR:ToggleStopDone(shown.key, DR:GetActiveRoute(shown.key), self.index)
		end
	end)
	rows[index] = row
	return row
end

-- The last runs of the shown dungeon in a tooltip (mouse on the run time).
local function showLastRuns(self)
	local runs = shown.key and DR.db.runs[shown.key]
	if not runs or #runs == 0 then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText(L["Last runs"], 1, 1, 1)
	for _, run in ipairs(runs) do
		GameTooltip:AddDoubleLine(date("%Y-%m-%d", run.date) .. "  " .. (run.route or ""), DR.FormatDuration(run.time),
			0.8, 0.8, 0.8, 1, 0.82, 0)
	end
	GameTooltip:Show()
end

local function entranceEnter(self)
	local c = DR.Theme().linkHover
	self.Text:SetTextColor(c[1], c[2], c[3])
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Click: set a waypoint to the entrance"], 1, 1, 1, 1, true)
	GameTooltip:Show()
end

local function entranceLeave(self)
	local c = DR.Theme().link
	self.Text:SetTextColor(c[1], c[2], c[3])
	GameTooltip:Hide()
end

local function buildSidebar()
	sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -HEADER_H)
	sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 10)
	sidebar:SetWidth(SIDEBAR_W - PAD)

	sidebar.Level = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sidebar.Level:SetPoint("TOPLEFT", 2, 0)
	sidebar.Level:SetJustifyH("LEFT")
	DR.ThemeText(sidebar.Level, "muted")
	-- run time and best time on the level line
	sidebar.Time = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sidebar.Time:SetPoint("TOPRIGHT", 0, 0)
	sidebar.Time:SetJustifyH("RIGHT")
	DR.ThemeText(sidebar.Time, "muted")
	sidebar.Level:SetPoint("TOPRIGHT", sidebar.Time, "TOPLEFT", -6, 0)
	-- the last runs of the dungeon when the mouse rests on the times
	local timeHover = CreateFrame("Frame", nil, sidebar)
	timeHover:SetPoint("TOPLEFT", sidebar.Time, "TOPLEFT", -2, 2)
	timeHover:SetPoint("BOTTOMRIGHT", sidebar.Time, "BOTTOMRIGHT", 2, -2)
	timeHover:SetMouseMotionEnabled(true) -- the tooltip only, clicks go through
	timeHover:SetScript("OnEnter", showLastRuns)
	timeHover:SetScript("OnLeave", GameTooltip_Hide)
	sidebar.TimeHover = timeHover
	-- the way to the entrance, outside the dungeon
	local entrance = CreateFrame("Button", nil, sidebar)
	entrance:SetPoint("TOPLEFT", 2, -14)
	entrance:SetHeight(14)
	entrance.Text = entrance:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	entrance.Text:SetPoint("LEFT")
	DR.ThemeText(entrance.Text, "link")
	entrance:SetScript("OnClick", function() DR:SetEntranceWaypoint(shown.key) end)
	entrance:SetScript("OnEnter", entranceEnter)
	entrance:SetScript("OnLeave", entranceLeave)
	sidebar.Entrance = entrance

	-- the stops scroll when the window is too small for all of them
	local scroll = CreateFrame("ScrollFrame", nil, sidebar)
	scroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, LIST_Y)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(DR.Clamp(self:GetVerticalScroll() - delta * rowHeight() * 2, 0, range))
	end)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(SIDEBAR_W - PAD, 10)
	list:SetScale(DR.db.listScale or 1)
	scroll:SetScrollChild(list)
	scroll:SetScript("OnSizeChanged", function(_, width) list:SetWidth(width / list:GetScale()) end)
	sidebar.Scroll, sidebar.List = scroll, list

	sidebar.Empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sidebar.Empty:SetPoint("TOPLEFT", 0, -2)
	sidebar.Empty:SetPoint("TOPRIGHT", 0, -2)
	sidebar.Empty:SetJustifyH("LEFT")
	DR.ThemeText(sidebar.Empty, "muted")
	sidebar.Empty:SetSpacing(2)

	-- buttons under the list
	local bottom = CreateFrame("Frame", nil, sidebar)
	bottom:SetPoint("BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(24)
	sidebar.Bottom = bottom
	scroll:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 6)

	sidebar.EditButton = makeButton(bottom, L["Edit"], 108)
	sidebar.EditButton:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.EditButton:SetScript("OnClick", function()
		local key = shown.key
		local route = DR:GetActiveRoute(key)
		if DR:IsBuiltIn(route) then
			local copy = DR:CopyRoute(key, route)
			DR:Print(L["The standard route stays unchanged. You are editing a copy: %s"], DR:GetRouteName(copy))
			DR.Editor:Start(key, copy)
		else
			DR.Editor:Start(key, route)
		end
	end)
	sidebar.ResetButton = makeButton(bottom, L["New run"], 108)
	sidebar.ResetButton:SetPoint("LEFT", sidebar.EditButton, "RIGHT", 6, 0)
	sidebar.ResetButton:SetScript("OnClick", function() DR:ResetProgress(shown.key) end)
	sidebar.ResetButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Clears all checkmarks of this dungeon."], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sidebar.ResetButton:SetScript("OnLeave", GameTooltip_Hide)
	sidebar.NewButton = makeButton(bottom, L["New route"], 108)
	sidebar.NewButton:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.NewButton:SetScript("OnClick", newRoute)
	sidebar.ImportButton = makeButton(bottom, L["Import"], 108)
	sidebar.ImportButton:SetPoint("LEFT", sidebar.NewButton, "RIGHT", 6, 0)
	sidebar.ImportButton:SetScript("OnClick", importRoute)

	sidebar.Toolbar = DR.Editor:BuildToolbar(bottom)
	sidebar.Toolbar:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.Toolbar:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function refreshSidebar()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	local editing = DR.Editor:IsEditing(key, route)
	local levelText = DR:GetLevelText(key) or ""
	local color = DR:GetLevelColor(key, DR.PlayerLevel())
	sidebar.Level:SetText(color and ("|cff" .. color .. levelText .. "|r") or levelText)
	local zone = DR:GetEntranceZone(key)
	local inside = key == DR.currentKey
	local orn = ornate()
	sidebar.Entrance.Text:SetText(zone and L["Entrance: %s"]:format(zone) or "")
	sidebar.Entrance:SetWidth(sidebar.Entrance.Text:GetStringWidth() + 4)
	sidebar.Entrance:SetShown(zone ~= nil and not inside and not orn)
	if orn then
		-- style "Gilded": level and entrance under the title
		local o = frame.Ornate
		o.Level:SetText(color and ("|cff" .. color .. levelText .. "|r") or levelText)
		o.Entrance.Text:SetText(zone and ("   \194\183   " .. L["Entrance: %s"]:format(zone)) or "")
		o.Entrance:SetWidth(o.Entrance.Text:GetStringWidth() + 4)
		o.Entrance:SetShown(zone ~= nil and not inside)
	end
	Window:UpdateTime()
	for _, row in ipairs(rows) do
		row:Hide()
	end
	sidebar.Empty:Hide()
	sidebar.EditButton:Hide()
	sidebar.ResetButton:Hide()
	sidebar.NewButton:Hide()
	sidebar.ImportButton:Hide()
	sidebar.Toolbar:Hide()

	local y = 0
	frame.Ornate.StopsCount:SetText("")
	if not route then
		sidebar.Empty:SetText(L["No route for this dungeon yet. Create one or import a route text."])
		sidebar.Empty:Show()
		y = -sidebar.Empty:GetStringHeight() - 4
		sidebar.NewButton:Show()
		sidebar.ImportButton:Show()
		sidebar.Bottom:SetHeight(24)
	else
		local labels = DR:GetStopLabels(route)
		local nextIndex = DR:GetNextStopIndex(key, route)
		local theme = DR.Theme()
		local height, doneCount = rowHeight(), 0
		for i, stop in ipairs(route.stops) do
			local row = rows[i] or makeRow(i)
			row:SetHeight(height)
			row.index = i
			row.floor = stop.floor
			row.stopName = DR:GetStopName(stop)
			row.auto = stop.encounters ~= nil
			row.note = DR.LocText(stop, "note")
			row.otherFloor = not DR.OnFloor(stop, shown.floor)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", 0, y)
			row.Number:SetText(labels[i])
			row.Name:SetText(row.stopName)
			local done = DR:IsStopDone(key, route, i)
			row.Check:SetShown(done)
			if done then doneCount = doneCount + 1 end
			if orn then
				local b, f, e, c = orn.band, orn.nextFill, orn.nextBar, orn.check
				row.Band:SetColorTexture(b[1], b[2], b[3], b[4])
				row.NextFill:SetColorTexture(f[1], f[2], f[3], f[4])
				row.NextBar:SetColorTexture(e[1], e[2], e[3], e[4])
				row.Check:SetVertexColor(c[1], c[2], c[3])
			else
				row.Check:SetVertexColor(1, 1, 1)
			end
			row.Band:SetShown(orn ~= nil and i % 2 == 0 and i ~= nextIndex)
			row.NextFill:SetShown(orn ~= nil and i == nextIndex)
			row.NextBar:SetShown(orn ~= nil and i == nextIndex)
			local k = theme.kinds[stop.kind] or theme.kinds.boss
			row.Badge:SetVertexColor(k[1], k[2], k[3])
			row.Number:SetTextColor(k[1], k[2], k[3])
			local c = done and theme.done or i == nextIndex and theme.next or row.otherFloor and theme.dim or theme.text
			row.Name:SetTextColor(c[1], c[2], c[3])
			local f, h = theme.badgeFill, theme.highlight
			row.BadgeFill:SetVertexColor(f[1], f[2], f[3], f[4])
			row.Highlight:SetColorTexture(h[1], h[2], h[3], h[4])
			row.Hover:SetColorTexture(h[1], h[2], h[3], h[4])
			row:Show()
			y = y - height
		end
		frame.Ornate.StopsCount:SetText(#route.stops > 0 and (doneCount .. "/" .. #route.stops) or "")
		if #route.stops == 0 then
			sidebar.Empty:SetText(L["This route has no stops yet."])
			sidebar.Empty:Show()
			y = -sidebar.Empty:GetStringHeight() - 4
		end
		if editing then
			sidebar.Toolbar:Refresh()
			sidebar.Toolbar:Show()
			sidebar.Bottom:SetHeight(sidebar.Toolbar:GetHeight())
		else
			sidebar.EditButton:Show()
			sidebar.ResetButton:Show()
			sidebar.Bottom:SetHeight(24)
		end
	end
	sidebar.List:SetHeight(math.max(10, -y))
end

-- Style "Gilded" ----------------------------------------------------------------------------------
-- A frame of brick and gold: an inner trim, gems at the corners, a title plate on the top edge, the
-- logo with the dungeon as title (click: choose a dungeon) and below its level and entrance, the
-- floors as tabs, a frame around the map, a head line over the stops and a footer with the run time.
-- Hidden in the other styles, where the header holds the dungeon and floor choice and the sidebar the
-- level, the times and the entrance.

local function makeLine(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	return line
end

local function tabColors(tab)
	local t = DR.Theme()
	local orn = t.ornate
	if tab.selected then
		tab:SetBackdropColor(orn.plate[1], orn.plate[2], orn.plate[3], orn.plate[4])
		tab:SetBackdropBorderColor(orn.trim[1], orn.trim[2], orn.trim[3], orn.trim[4])
		tab.Text:SetTextColor(t.title[1], t.title[2], t.title[3])
	else
		tab:SetBackdropColor(0, 0, 0, 0)
		tab:SetBackdropBorderColor(0, 0, 0, 0)
		local c = tab.hover and t.title or t.accent
		tab.Text:SetTextColor(c[1], c[2], c[3])
	end
end

local function makeTab(index)
	local tab = CreateFrame("Button", nil, frame.Ornate, "BackdropTemplate")
	tab:SetHeight(22)
	tab:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	tab.Text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.Text:SetPoint("LEFT", 10, 0)
	tab.Text:SetPoint("RIGHT", -10, 0)
	tab.Text:SetWordWrap(false)
	DR.ThemeText(tab.Text)
	tab:SetScript("OnClick", function(self) Window:SelectFloor(self.floor, true) end)
	tab:SetScript("OnEnter", function(self)
		self.hover = true
		tabColors(self)
	end)
	tab:SetScript("OnLeave", function(self)
		self.hover = false
		tabColors(self)
	end)
	frame.Ornate.Tabs[index] = tab
	return tab
end

local function buildOrnate()
	local o = CreateFrame("Frame", nil, frame)
	o:SetAllPoints()
	o:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.Ornate = o
	o.Trim = CreateFrame("Frame", nil, o, "BackdropTemplate")
	o.Trim:SetPoint("TOPLEFT", 3, -3)
	o.Trim:SetPoint("BOTTOMRIGHT", -3, 3)
	o.Trim:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	o.Gems = {}
	for i, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		local gem = o:CreateTexture(nil, "OVERLAY")
		gem:SetTexture(MEDIA .. "diamond")
		gem:SetSize(14, 14)
		gem:SetPoint("CENTER", frame, point, 0, 0)
		o.Gems[i] = gem
	end
	-- the title plate on the top edge
	local plate = CreateFrame("Frame", nil, o, "BackdropTemplate")
	plate:SetPoint("CENTER", frame, "TOP", 0, 0)
	plate:SetHeight(24)
	plate:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	plate.Text = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	plate.Text:SetPoint("CENTER")
	plate.Text:SetText(L["Forever Dungeon Routes"]:upper())
	DR.ThemeText(plate.Text, "title")
	plate:SetWidth(plate.Text:GetStringWidth() + 84)
	plate.Gems = {}
	for i, side in ipairs({ "LEFT", "RIGHT" }) do
		local gem = plate:CreateTexture(nil, "OVERLAY")
		gem:SetTexture(MEDIA .. "diamond")
		gem:SetSize(8, 8)
		gem:SetPoint("CENTER", plate, side, i == 1 and 16 or -16, 0)
		plate.Gems[i] = gem
	end
	o.Plate = plate
	-- the logo, the dungeon as title and below its level and the way to the entrance
	o.Logo = o:CreateTexture(nil, "ARTWORK")
	o.Logo:SetTexture(MEDIA .. "icon")
	o.Logo:SetSize(34, 34)
	o.Logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 6, -20)
	local title = CreateFrame("Button", nil, o)
	title:SetPoint("TOPLEFT", o.Logo, "TOPRIGHT", 10, 3)
	title:SetHeight(24)
	title.Text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title.Text:SetPoint("LEFT")
	title.Text:SetWordWrap(false)
	DR.ThemeText(title.Text, "title")
	title.Arrow = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title.Arrow:SetPoint("LEFT", title.Text, "RIGHT", 8, -1)
	title.Arrow:SetText("v")
	DR.ThemeText(title.Arrow, "arrow")
	title:SetScript("OnClick", openDungeonMenu)
	title:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Choose a dungeon"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	title:SetScript("OnLeave", GameTooltip_Hide)
	o.Title = title
	o.Level = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	o.Level:SetPoint("TOPLEFT", o.Logo, "TOPRIGHT", 10, -24)
	DR.ThemeText(o.Level, "text")
	local entrance = CreateFrame("Button", nil, o)
	entrance:SetPoint("LEFT", o.Level, "RIGHT", 0, 0)
	entrance:SetHeight(14)
	entrance.Text = entrance:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	entrance.Text:SetPoint("LEFT")
	DR.ThemeText(entrance.Text, "link")
	entrance:SetScript("OnClick", function() DR:SetEntranceWaypoint(shown.key) end)
	entrance:SetScript("OnEnter", entranceEnter)
	entrance:SetScript("OnLeave", entranceLeave)
	o.Entrance = entrance
	-- the floors as tabs on a line
	o.Tabs = {}
	o.TabLine = makeLine(o)
	o.TabLine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(ORNATE_HEADER_H - 6))
	o.TabLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(ORNATE_HEADER_H - 6))
	-- a frame around the map
	o.MapFrame = CreateFrame("Frame", nil, o, "BackdropTemplate")
	o.MapFrame:SetPoint("TOPLEFT", view.frame, "TOPLEFT", -1, 1)
	o.MapFrame:SetPoint("BOTTOMRIGHT", view.frame, "BOTTOMRIGHT", 1, -1)
	o.MapFrame:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	-- the head line over the stops: how many are done
	o.StopsHead = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	o.StopsHead:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 2, -32)
	o.StopsHead:SetText(L["Stops"]:upper())
	DR.ThemeText(o.StopsHead, "title")
	o.StopsCount = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	o.StopsCount:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -2, -32)
	DR.ThemeText(o.StopsCount, "muted")
	o.StopsLine = makeLine(sidebar)
	o.StopsLine:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -46)
	o.StopsLine:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -46)
	-- the footer: the addon, the run time and the best time
	o.FootLine = makeLine(o)
	o.FootLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, FOOTER_H)
	o.FootLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOTER_H)
	o.FootIcon = o:CreateTexture(nil, "ARTWORK")
	o.FootIcon:SetTexture(MEDIA .. "icon")
	o.FootIcon:SetSize(16, 16)
	o.FootIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, 6)
	o.FootName = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	o.FootName:SetPoint("LEFT", o.FootIcon, "RIGHT", 6, 0)
	o.FootName:SetText(L["Forever Dungeon Routes"])
	DR.ThemeText(o.FootName, "accent")
	o.FootTime = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	o.FootTime:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + 14), 10)
	DR.ThemeText(o.FootTime, "muted")
	local timeHover = CreateFrame("Frame", nil, o)
	timeHover:SetPoint("TOPLEFT", o.FootTime, "TOPLEFT", -2, 2)
	timeHover:SetPoint("BOTTOMRIGHT", o.FootTime, "BOTTOMRIGHT", 2, -2)
	timeHover:SetMouseMotionEnabled(true)
	timeHover:SetScript("OnEnter", showLastRuns)
	timeHover:SetScript("OnLeave", GameTooltip_Hide)
	o.TimeHover = timeHover
end

-- Shows or hides the decoration for the chosen style and colours it.
styleOrnate = function()
	local o, t = frame.Ornate, DR.Theme()
	local orn = t.ornate
	o:SetShown(orn ~= nil)
	for _, region in ipairs({ o.StopsHead, o.StopsCount, o.StopsLine }) do
		region:SetShown(orn ~= nil)
	end
	frame.DungeonButton:SetShown(orn == nil)
	sidebar.Level:SetShown(orn == nil)
	sidebar.Time:SetShown(orn == nil)
	sidebar.TimeHover:SetShown(orn == nil)
	frame.Close:ClearAllPoints()
	if orn then
		frame.Close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + 6), -22)
	else
		frame.Close:SetPoint("RIGHT", frame.Header, "RIGHT", -PAD, -1)
	end
	if not orn then return end
	local gold, trim = t.border, orn.trim
	o.Trim:SetBackdropBorderColor(trim[1], trim[2], trim[3], trim[4])
	o.MapFrame:SetBackdropBorderColor(trim[1], trim[2], trim[3], trim[4])
	for _, line in ipairs({ o.TabLine, o.FootLine, o.StopsLine }) do
		line:SetColorTexture(trim[1], trim[2], trim[3], trim[4])
	end
	for _, gem in ipairs(o.Gems) do gem:SetVertexColor(gold[1], gold[2], gold[3]) end
	o.Plate:SetBackdropColor(orn.plate[1], orn.plate[2], orn.plate[3], orn.plate[4])
	o.Plate:SetBackdropBorderColor(gold[1], gold[2], gold[3], gold[4])
	for _, gem in ipairs(o.Plate.Gems) do gem:SetVertexColor(gold[1], gold[2], gold[3]) end
	for _, tab in ipairs(o.Tabs) do tabColors(tab) end
end

-- Title and floor tabs of the style "Gilded"; true where the tabs replace the floor choice (several
-- floors whose tabs fit in a row).
local function refreshOrnate(dungeon, index)
	local o = frame.Ornate
	if not ornate() then return false end
	o.Title.Text:SetText(DR:GetKeyName(shown.key))
	o.Title:SetWidth(o.Title.Text:GetStringWidth() + 22)
	local floors = dungeon.floors
	local several = #floors > 1
	local x = PAD
	for i = 1, math.max(#floors, #o.Tabs) do
		local tab = o.Tabs[i]
		if several and i <= #floors then
			tab = tab or makeTab(i)
			tab.floor = floors[i]
			tab.selected = i == index
			tab.Text:SetText(i .. ". " .. DR:GetFloorName(floors[i]))
			local w = math.min(tab.Text:GetStringWidth() + 22, 230)
			tab:SetWidth(w)
			tab:ClearAllPoints()
			tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, -(ORNATE_HEADER_H - 6))
			x = x + w + 4
			tabColors(tab)
			tab:Show()
		elseif tab then
			tab:Hide()
		end
	end
	local fits = several and x - 4 <= frame:GetWidth() - PAD
	if several and not fits then
		for i = 1, #floors do o.Tabs[i]:Hide() end
	end
	return fits
end

-- Building --------------------------------------------------------------------------------------

local function build()
	frame = CreateFrame("Frame", "ForeverDungeonRoutesFrame", UIParent, "BackdropTemplate")
	DR.StyleBox(frame, 0.96)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_W, MIN_H)
	frame:SetDontSavePosition(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, "ForeverDungeonRoutesFrame")
	restoreGeometry()
	frame:SetAlpha(DR.db.alpha or 1)
	frame:SetScript("OnHide", function()
		DR:Fire("WINDOW_HIDDEN")
	end)
	-- the run time goes on while the window is open
	local ticker = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		ticker = ticker + elapsed
		if ticker >= 1 then
			ticker = 0
			Window:UpdateTime()
		end
	end)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		saveGeometry()
	end)
	frame.Header = header

	frame.DungeonButton = makeDropButton(header, 200)
	frame.DungeonButton:SetPoint("LEFT", PAD, -1)
	frame.DungeonButton.tooltip = L["Choose a dungeon"]
	frame.DungeonButton:SetScript("OnClick", openDungeonMenu)

	frame.FloorPrev = makeButton(header, "<", 22)
	frame.FloorPrev:SetHeight(22)
	frame.FloorPrev:SetPoint("LEFT", frame.DungeonButton, "RIGHT", 8, 0)
	frame.FloorPrev:SetScript("OnClick", function() Window:StepFloor(-1) end)
	frame.FloorButton = makeDropButton(header, 180)
	frame.FloorButton:SetPoint("LEFT", frame.FloorPrev, "RIGHT", 2, 0)
	frame.FloorButton.tooltip = L["Choose the map level"]
	frame.FloorButton:SetScript("OnClick", openFloorMenu)
	frame.FloorNext = makeButton(header, ">", 22)
	frame.FloorNext:SetHeight(22)
	frame.FloorNext:SetPoint("LEFT", frame.FloorButton, "RIGHT", 2, 0)
	frame.FloorNext:SetScript("OnClick", function() Window:StepFloor(1) end)

	frame.Close = makeButton(header, "X", 22)
	frame.Close:SetHeight(22)
	frame.Close:SetPoint("RIGHT", -PAD, -1)
	frame.Close:SetScript("OnClick", function() frame:Hide() end)
	frame.Gear = makeIconButton(header, "gear", 20)
	frame.Gear:SetPoint("RIGHT", frame.Close, "LEFT", -8, 0)
	frame.Gear:SetScript("OnClick", openSettingsMenu)

	view = DR.MapView
	view:Create(frame)
	buildSidebar()
	frame.Sidebar = sidebar

	frame.RouteButton = makeDropButton(sidebar, 210)
	frame.RouteButton.tooltip = L["Choose, copy, share or import routes"]
	frame.RouteButton:SetScript("OnClick", openRouteMenu)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 50)
	grip.Icon = grip:CreateTexture(nil, "OVERLAY")
	grip.Icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip.Icon:SetAllPoints()
	grip.Highlight = grip:CreateTexture(nil, "HIGHLIGHT")
	grip.Highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip.Highlight:SetAllPoints()
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		saveGeometry()
	end)
	frame.Grip = grip

	buildOrnate()
	layout()
end

-- State -----------------------------------------------------------------------------------------

function Window:IsShown()
	return frame ~= nil and frame:IsShown()
end

function Window:GetShown()
	return shown.key, shown.floor
end

function Window:GetShownKey()
	return shown.key
end

function Window:IsFollowing()
	return following
end

function Window:GetFrame()
	return frame
end

function Window:Refresh()
	if not frame or not shown.key then return end
	local dungeon = DR:GetDungeon(shown.key)
	frame.DungeonButton.Text:SetText(DR:GetKeyName(shown.key))
	local floors = dungeon.floors
	local index = indexOf(floors, shown.floor) or 1
	local several = #floors > 1
	-- in the style "Gilded" the floors are tabs; where they do not fit, the choice sits in the tab row
	local tabs = refreshOrnate(dungeon, index)
	frame.FloorPrev:ClearAllPoints()
	if ornate() then
		frame.FloorPrev:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", PAD, -(ORNATE_HEADER_H - 8))
	else
		frame.FloorPrev:SetPoint("LEFT", frame.DungeonButton, "RIGHT", 8, 0)
	end
	frame.FloorPrev:SetShown(several and not tabs)
	frame.FloorNext:SetShown(several and not tabs)
	frame.FloorButton:SetShown(several and not tabs)
	if several then
		frame.FloorButton.Text:SetText(index .. "/" .. #floors .. "  " .. DR:GetFloorName(shown.floor))
		frame.FloorPrev:SetEnabled(index > 1)
		frame.FloorNext:SetEnabled(index < #floors)
	end
	local route = DR:GetActiveRoute(shown.key)
	frame.RouteButton.Text:SetText(route and DR:GetRouteName(route) or L["No route yet"])
	frame.RouteButton.tooltipExtra = route and route.source and (L["Source"] .. ": " .. route.source) or nil
	view:SetFloor(shown.key, shown.floor)
	if DR.db.showStops then
		refreshSidebar()
	end
end

-- Run time while a run is on (or how long it took), and the best time of the shown dungeon.
function Window:UpdateTime()
	if not sidebar or not frame:IsVisible() then return end
	local started, finished, best = DR:GetRunTimes(shown.key)
	local parts = {}
	if started then
		parts[#parts + 1] = L["Run %s"]:format(DR.FormatDuration((finished or time()) - started))
	end
	if best then
		parts[#parts + 1] = L["Best %s"]:format(DR.FormatDuration(best))
	end
	sidebar.Time:SetText(table.concat(parts, "  "))
	frame.Ornate.FootTime:SetText(table.concat(parts, "   \194\183   "))
end

-- The floor of the next boss still open in the route of a dungeon.
local function nextBossFloor(key)
	local route = DR:GetActiveRoute(key)
	local index = DR:GetNextStopIndex(key, route)
	return index and route.stops[index].floor
end

-- The floor of the room the game names as the player's place (the shown one if it has the room).
local function roomFloor(key)
	local room = key == DR.currentKey and DR.Room:Get()
	if not room then return nil end
	if shown.key == key and shown.floor and DR.Room:OnFloor(room, shown.floor) then
		return shown.floor
	end
	return DR.Room:MainFloor(room)
end

-- Shows a dungeon; without a floor inside the dungeon the player's floor where the game reveals
-- it, else the floor of the room the player is in, else of the next open boss, else where the
-- route starts.
function Window:ShowDungeon(key, floor)
	local dungeon = DR:GetDungeon(key)
	if not dungeon then return end
	local newKey = key ~= shown.key
	if not floor and key == DR.currentKey then
		local located, playerFloor = DR:LocatePlayer(not newKey and shown.floor or nil)
		if located and located ~= key then
			-- the position showed another wing of the instance
			return self:ShowDungeon(located)
		end
		floor = playerFloor or roomFloor(key) or nextBossFloor(key)
	end
	if not floor and not newKey then
		floor = shown.floor
	end
	if not floor or DR:GetDungeonForFloor(floor) ~= dungeon then
		floor = DR:GetRouteStartFloor(DR:GetActiveRoute(key))
		if DR:GetDungeonForFloor(floor) ~= dungeon then
			floor = dungeon.floors[1]
		end
	end
	shown.key, shown.floor = key, floor
	if newKey then
		DR:Fire("SHOWN_CHANGED", key)
	end
	self:Refresh()
end

function Window:SelectFloor(floor, byHand)
	local dungeon = DR:GetDungeon(shown.key)
	if not floor or not dungeon or DR:GetDungeonForFloor(floor) ~= dungeon then return end
	if byHand then
		following = false
	end
	if floor == shown.floor then return end
	shown.floor = floor
	self:Refresh()
end

function Window:StepFloor(delta)
	local dungeon = DR:GetDungeon(shown.key)
	if not dungeon then return end
	local index = indexOf(dungeon.floors, shown.floor) or 1
	local floor = dungeon.floors[index + delta]
	if floor then
		self:SelectFloor(floor, true)
	end
end

-- Back to where the player is: the current dungeon on the player's floor where the game reveals
-- it, else the floor of the room the player is in, else of the next open boss; centered on it
-- when zoomed in. The map follows again.
function Window:FollowPlayer()
	following = true
	if not DR.currentKey then return end
	self:ShowDungeon(DR.currentKey)
	if view.zoom <= 1 then return end
	local u, v = view:GetPlayerUV()
	local room = DR.Room:Get()
	if not u and room then
		u, v = DR.Room:Center(room, shown.floor)
	end
	if not u then
		local route = DR:GetActiveRoute(shown.key)
		local index = DR:GetNextStopIndex(shown.key, route)
		local stop = index and route.stops[index]
		if stop and DR.OnFloor(stop, shown.floor) then
			u, v = stop.x, stop.y
		end
	end
	if u then
		view:CenterOn(u, v)
	end
end

function Window:FocusStop(index)
	local route = DR:GetActiveRoute(shown.key)
	local stop = route and route.stops[index]
	if not stop then return end
	if not DR.OnFloor(stop, shown.floor) then
		self:SelectFloor(stop.floor, true)
	end
	view:CenterOn(stop.x, stop.y, 2)
end

function Window:Open(key, floor)
	if not frame then
		build()
	end
	key = key or DR.currentKey or shown.key or DR.Dungeons[1].key
	if key == DR.currentKey and not floor then
		following = true
	end
	self:ShowDungeon(key, floor)
	frame:Show()
	frame:Raise()
	view:Layout()
	-- the sidebar is visible only now, so the run time can be filled in
	self:UpdateTime()
end

function Window:Toggle()
	if self:IsShown() then
		frame:Hide()
	else
		self:Open(DR.currentKey or shown.key)
	end
end

local function refreshIfShown(key)
	if Window:IsShown() and (key == nil or key == shown.key) then
		Window:Refresh()
	end
end

DR:On("ROUTE_CHANGED", refreshIfShown)
DR:On("PROGRESS_CHANGED", refreshIfShown)
-- A boss was ticked off (by the kill or by hand): while the map follows the run it moves on to
-- the floor of the next open boss, unless the game reveals the player's own floor.
DR:On("PROGRESS_CHANGED", function(key)
	if not Window:IsShown() or not following or key ~= DR.currentKey or shown.key ~= key then return end
	if DR:GetUnitWorldPosition("player") or DR.Room:Get() then return end
	local floor = nextBossFloor(key)
	if floor then
		Window:SelectFloor(floor)
	end
end)
DR:On("EDITOR_CHANGED", function() refreshIfShown() end)
DR:On("SETTINGS_CHANGED", function(key)
	if not frame then return end
	if key == "alpha" then
		frame:SetAlpha(DR.db.alpha)
	elseif key == "showStops" then
		layout()
	elseif key == "gameMinimap" then
		view:UpdateArt()
	elseif key == "theme" then
		layout()
	elseif key == "listScale" then
		sidebar.List:SetScale(DR.db.listScale)
		sidebar.List:SetWidth(sidebar.Scroll:GetWidth() / DR.db.listScale)
	end
	refreshIfShown()
end)
DR:On("DUNGEON_CHANGED", function(key)
	if not Window:IsShown() then return end
	if key and following then
		Window:ShowDungeon(key)
	else
		view:UpdateGroup()
		view:UpdateRoom()
	end
end)
-- The player walked into another named room: while the map follows, it shows the room's floor.
DR:On("ROOM_CHANGED", function(room)
	if not Window:IsShown() then return end
	if room and following and shown.key == DR.currentKey and not DR.Room:OnFloor(room, shown.floor) then
		Window:SelectFloor(DR.Room:MainFloor(room))
	else
		view:UpdateRoom()
	end
end)
DR:On("STOP_HOVER", function(index)
	for _, row in ipairs(rows) do
		row.Hover:SetShown(row:IsShown() and row.index == index)
	end
end)
