local _, DR = ...
local L = DR.L

-- Route panel in the top right corner of the world map: dungeon, route choice, stops in order
-- with their progress, and the buttons for editing and sharing.

local WIDTH = 228
local ROW_HEIGHT = 18
local PAD = 10

local panel
local rows = {}

local function floorIsDungeon(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info ~= nil and info.mapType == Enum.UIMapType.Dungeon
end

local function levelText(key)
	local dungeon = DR:GetDungeon(key)
	if dungeon and dungeon.levels then
		return L["Level"] .. " " .. dungeon.levels[1] .. "-" .. dungeon.levels[2]
	end
	return nil
end

local function makeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:GetFontString():SetFontObject(GameFontNormalSmall)
	return b
end

local function makeRow(index)
	local row = CreateFrame("Button", nil, panel.Body)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetAllPoints()
	row.Highlight:SetColorTexture(1, 0.85, 0.5, 0.12)

	row.Badge = row:CreateTexture(nil, "ARTWORK")
	row.Badge:SetTexture("Interface\\AddOns\\ForeverDungeonRoutes\\media\\ring")
	row.Badge:SetSize(16, 16)
	row.Badge:SetPoint("LEFT", 2, 0)
	row.BadgeFill = row:CreateTexture(nil, "BACKGROUND")
	row.BadgeFill:SetTexture("Interface\\AddOns\\ForeverDungeonRoutes\\media\\circle")
	row.BadgeFill:SetVertexColor(0.06, 0.05, 0.04, 0.95)
	row.BadgeFill:SetAllPoints(row.Badge)
	row.Number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Number:SetPoint("CENTER", row.Badge, "CENTER", 0, 0)

	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetTexture("Interface\\AddOns\\ForeverDungeonRoutes\\media\\check")
	row.Check:SetSize(14, 14)
	row.Check:SetPoint("RIGHT", -2, 0)

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Badge, "RIGHT", 6, 0)
	row.Name:SetPoint("RIGHT", row.Check, "LEFT", -4, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		DR:Fire("HIGHLIGHT_STOP", self.index)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.stopName, 1, 0.82, 0)
		if self.note and self.note ~= "" then
			GameTooltip:AddLine(self.note, 1, 1, 1, true)
		end
		if self.otherFloor then
			GameTooltip:AddLine(L["On another map level"], 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(L["Click: mark as done  |  Shift-click: show on map"], 0.4, 0.8, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		DR:Fire("HIGHLIGHT_STOP", nil)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if IsShiftKeyDown() or button == "RightButton" then
			DR:ShowStopOnMap(panel.route, self.index)
		else
			DR:ToggleStopDone(panel.key, panel.route, self.index)
		end
	end)
	rows[index] = row
	return row
end

-- Route menu ------------------------------------------------------------------------------

local function exportRoute()
	local text = DR:ExportRoute(panel.key, panel.route)
	DR.Dialog.ShowText(L["Export route"], L["Copy the text with Ctrl+C and share it. Others can paste it via Import."], text)
end

local function importRoute()
	DR.Dialog.AskText(L["Import route"], L["Paste a route text with Ctrl+V."], function(text)
		local key, route = DR:ImportRoute(text)
		if not key then
			return route
		end
		DR:AddImportedRoute(key, route)
		DR:Print(L["Route imported: %s"], DR:GetRouteName(route))
		if WorldMapFrame:IsShown() then
			local first = route.paths[1] or route.stops[1]
			if first and first.floor ~= WorldMapFrame:GetMapID() and DR.MapHasArt(first.floor) then
				WorldMapFrame:SetMapID(first.floor)
			end
		end
	end, L["Import"])
end

local function renameRoute()
	local key, route = panel.key, panel.route
	DR.Dialog.AskLine(L["Rename route"], nil, DR:GetRouteName(route), function(name)
		if name == "" then return L["Please enter a name."] end
		DR:RenameRoute(key, route, name)
	end)
end

local function deleteRoute()
	local key, route = panel.key, panel.route
	DR.Dialog.Confirm(L["Delete route"], L["Delete the route \"%s\"? This cannot be undone."]:format(DR:GetRouteName(route)),
		function()
			if DR.Editor:IsEditing(key, route) then
				DR.Editor:Stop()
			end
			DR:DeleteRoute(key, route)
		end, DELETE or L["Delete"])
end

local function newRoute(key)
	DR.Dialog.AskLine(L["New route"], L["Name of the new route:"], L["My route"], function(name)
		if name == "" then return L["Please enter a name."] end
		local route = DR:NewRoute(key, name)
		DR.Editor:Start(key, route)
	end)
end

local function openRouteMenu(owner)
	local key, current = panel.key, panel.route
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Routes"])
		for _, route in ipairs(DR:GetRoutes(key)) do
			root:CreateRadio(DR:GetRouteName(route), function() return route == DR:GetActiveRoute(key) end,
				function() DR:SetActiveRoute(key, route.id) end)
		end
		root:CreateDivider()
		root:CreateButton(L["New route"], function() newRoute(key) end)
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
			root:CreateButton(L["Export route"], exportRoute)
		else
			root:CreateDivider()
		end
		root:CreateButton(L["Import route"], importRoute)
	end)
end

-- Layout ----------------------------------------------------------------------------------

local function build()
	local container = WorldMapFrame:GetCanvasContainer()
	panel = CreateFrame("Frame", "ForeverDungeonRoutesPanel", WorldMapFrame, "BackdropTemplate")
	DR.StyleBox(panel, 0.86)
	panel:SetWidth(WIDTH)
	panel:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -8)
	panel:EnableMouse(true)
	panel:Hide()
	-- Map pins use frame levels up to 9000, so the panel sits one frame strata above the map.
	panel:SetScript("OnShow", function(self)
		local order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
		local mapStrata = WorldMapFrame:GetFrameStrata()
		for i, strata in ipairs(order) do
			if strata == mapStrata then
				self:SetFrameStrata(order[math.min(i + 1, #order)])
				break
			end
		end
	end)

	local header = CreateFrame("Button", nil, panel)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(24)
	header:SetScript("OnClick", function()
		DR.db.panelCollapsed = not DR.db.panelCollapsed
		DR:RefreshPanel()
	end)
	panel.Header = header
	panel.Toggle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.Toggle:SetPoint("RIGHT", -8, 0)
	panel.Title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.Title:SetPoint("LEFT", PAD, 0)
	panel.Title:SetPoint("RIGHT", panel.Toggle, "LEFT", -6, 0)
	panel.Title:SetJustifyH("LEFT")
	panel.Title:SetWordWrap(false)

	panel.Body = CreateFrame("Frame", nil, panel)
	panel.Body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, 0)
	panel.Body:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)

	panel.Sub = panel.Body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Sub:SetPoint("TOPLEFT", 0, 0)
	panel.Sub:SetPoint("TOPRIGHT", 0, 0)
	panel.Sub:SetJustifyH("LEFT")

	local routeButton = CreateFrame("Button", nil, panel.Body, "BackdropTemplate")
	DR.StyleBox(routeButton, 1)
	routeButton:SetBackdropColor(0.12, 0.11, 0.1, 1)
	routeButton:SetHeight(22)
	routeButton.Text = routeButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	routeButton.Text:SetPoint("LEFT", 8, 0)
	routeButton.Text:SetPoint("RIGHT", -18, 0)
	routeButton.Text:SetJustifyH("LEFT")
	routeButton.Text:SetWordWrap(false)
	routeButton.Arrow = routeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	routeButton.Arrow:SetPoint("RIGHT", -6, 0)
	routeButton.Arrow:SetText("v")
	routeButton:SetScript("OnClick", function(self) openRouteMenu(self) end)
	routeButton:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(1, 0.9, 0.6, 1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Choose, copy, share or import routes"], 1, 1, 1)
		if panel.route and panel.route.source then
			GameTooltip:AddLine(L["Source"] .. ": " .. panel.route.source, 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end)
	routeButton:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0.76, 0.66, 0.47, 0.9)
		GameTooltip:Hide()
	end)
	panel.RouteButton = routeButton

	panel.Empty = panel.Body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Empty:SetJustifyH("LEFT")
	panel.Empty:SetSpacing(2)

	panel.EditButton = makeButton(panel.Body, L["Edit"], 100)
	panel.EditButton:SetScript("OnClick", function()
		if DR.Editor:IsEditing(panel.key, panel.route) then
			DR.Editor:Stop()
		elseif DR:IsBuiltIn(panel.route) then
			local copy = DR:CopyRoute(panel.key, panel.route)
			DR:Print(L["The standard route stays unchanged. You are editing a copy: %s"], DR:GetRouteName(copy))
			DR.Editor:Start(panel.key, copy)
		else
			DR.Editor:Start(panel.key, panel.route)
		end
	end)
	panel.ResetButton = makeButton(panel.Body, L["New run"], 100)
	panel.ResetButton:SetScript("OnClick", function()
		DR:ResetProgress(panel.key)
	end)
	panel.ResetButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Clears all checkmarks of this dungeon."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	panel.ResetButton:SetScript("OnLeave", GameTooltip_Hide)
	panel.NewButton = makeButton(panel.Body, L["New route"], 100)
	panel.NewButton:SetScript("OnClick", function()
		newRoute(DR:GetOrCreateKeyForMap(WorldMapFrame:GetMapID()))
	end)
	panel.ImportButton = makeButton(panel.Body, L["Import"], 100)
	panel.ImportButton:SetScript("OnClick", importRoute)

	DR.EditorToolbar = DR.Editor:BuildToolbar(panel.Body)
end

function DR:RefreshPanel()
	if not panel then return end
	local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	local key = mapID and DR:GetKeyForMap(mapID)
	local route = key and DR:GetActiveRoute(key)
	local editing = DR.Editor:IsEditing(key, route)
	local wanted = DR.db.showPanel and mapID and (route or key or floorIsDungeon(mapID) or editing)
	if not wanted then
		panel:Hide()
		return
	end
	panel.key, panel.route = key, route
	panel:Show()

	local title = key and DR:GetKeyName(key) or L["Forever Dungeon Routes"]
	panel.Title:SetText(title)
	panel.Toggle:SetText(DR.db.panelCollapsed and "+" or "-")
	if DR.db.panelCollapsed and not editing then
		panel.Body:Hide()
		panel:SetHeight(24)
		return
	end
	panel.Body:Show()

	local y = 0
	local sub = levelText(key)
	panel.Sub:SetText(sub or "")
	if sub then
		y = y - 14
	end

	for _, row in ipairs(rows) do
		row:Hide()
	end
	panel.Empty:Hide()
	panel.EditButton:Hide()
	panel.ResetButton:Hide()
	panel.NewButton:Hide()
	panel.ImportButton:Hide()
	DR.EditorToolbar:Hide()

	if not route then
		panel.RouteButton:Hide()
		panel.Empty:ClearAllPoints()
		panel.Empty:SetPoint("TOPLEFT", 0, y - 2)
		panel.Empty:SetPoint("RIGHT", 0, 0)
		panel.Empty:SetText(L["No route for this map yet. Create one or import a route text."])
		panel.Empty:Show()
		y = y - panel.Empty:GetStringHeight() - 10
		panel.NewButton:ClearAllPoints()
		panel.NewButton:SetPoint("TOPLEFT", 0, y)
		panel.NewButton:Show()
		panel.ImportButton:ClearAllPoints()
		panel.ImportButton:SetPoint("LEFT", panel.NewButton, "RIGHT", 8, 0)
		panel.ImportButton:Show()
		y = y - 26
		panel.Body:SetHeight(-y)
		panel:SetHeight(24 + -y + 6)
		return
	end

	panel.RouteButton:ClearAllPoints()
	panel.RouteButton:SetPoint("TOPLEFT", 0, y - 2)
	panel.RouteButton:SetPoint("RIGHT", 0, 0)
	panel.RouteButton.Text:SetText(DR:GetRouteName(route))
	panel.RouteButton:Show()
	y = y - 30

	local labels = DR:GetStopLabels(route)
	local nextIndex = DR:GetNextStopIndex(key, route)
	for i, stop in ipairs(route.stops) do
		local row = rows[i] or makeRow(i)
		row.index = i
		row.stopName = (stop.name ~= "" and stop.name) or L["Boss"]
		row.note = DR.LocText(stop, "note")
		row.otherFloor = not DR.OnFloor(stop, mapID)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		row:SetPoint("RIGHT", 0, 0)
		row.Number:SetText(labels[i])
		row.Name:SetText(row.stopName)
		local done = DR:IsStopDone(key, route, i)
		row.Check:SetShown(done)
		local r, g, b = 0.95, 0.76, 0.31
		if stop.kind == "rare" then
			r, g, b = 0.89, 0.87, 0.82
		elseif stop.kind == "optional" then
			r, g, b = 0.62, 0.78, 0.95
		end
		row.Badge:SetVertexColor(r, g, b)
		row.Number:SetTextColor(r, g, b)
		if done then
			row.Name:SetTextColor(0.5, 0.5, 0.5)
		elseif i == nextIndex then
			row.Name:SetTextColor(1, 0.92, 0.6)
		elseif row.otherFloor then
			row.Name:SetTextColor(0.72, 0.72, 0.72)
		else
			row.Name:SetTextColor(1, 1, 1)
		end
		row:Show()
		y = y - ROW_HEIGHT
	end
	if #route.stops == 0 then
		panel.Empty:ClearAllPoints()
		panel.Empty:SetPoint("TOPLEFT", 0, y)
		panel.Empty:SetPoint("RIGHT", 0, 0)
		panel.Empty:SetText(L["This route has no stops yet."])
		panel.Empty:Show()
		y = y - panel.Empty:GetStringHeight() - 4
	end
	y = y - 8

	if editing then
		DR.EditorToolbar:ClearAllPoints()
		DR.EditorToolbar:SetPoint("TOPLEFT", 0, y)
		DR.EditorToolbar:SetPoint("RIGHT", 0, 0)
		DR.EditorToolbar:Refresh()
		DR.EditorToolbar:Show()
		y = y - DR.EditorToolbar:GetHeight() - 4
	else
		panel.EditButton:ClearAllPoints()
		panel.EditButton:SetPoint("TOPLEFT", 0, y)
		panel.EditButton:SetText(L["Edit"])
		panel.EditButton:Show()
		panel.ResetButton:ClearAllPoints()
		panel.ResetButton:SetPoint("LEFT", panel.EditButton, "RIGHT", 8, 0)
		panel.ResetButton:Show()
		y = y - 26
	end
	panel.Body:SetHeight(-y)
	panel:SetHeight(24 + -y + 6)
end

function DR:InitPanel()
	build()
	self:On("MAP_SHOWN", function() DR:RefreshPanel() end)
	self:On("ROUTE_CHANGED", function() DR:RefreshPanel() end)
	self:On("PROGRESS_CHANGED", function() DR:RefreshPanel() end)
	self:On("EDITOR_CHANGED", function() DR:RefreshPanel() end)
	WorldMapFrame:HookScript("OnHide", function()
		panel:Hide()
	end)
end
