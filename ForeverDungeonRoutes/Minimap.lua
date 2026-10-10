local _, DR = ...
local L = DR.L

-- Round button at the edge of the minimap: a click shows or hides the map, dragging moves it
-- around the minimap. It can be switched off behind the gear button. Ring, background and
-- highlight are the game's own minimap button art (file IDs, present in the Forever client).

local ICON = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\icon"
local RING, BACKGROUND, HIGHLIGHT = 136430, 136467, 136477
local OUTSIDE = 5 -- pixels the button center sits outside the minimap edge

local button

local function place()
	local angle = math.rad(DR.db.minimapAngle)
	local radius = Minimap:GetWidth() / 2 + OUTSIDE
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function followCursor()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	DR.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	place()
end

local function build()
	button = CreateFrame("Button", "ForeverDungeonRoutesMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(HIGHLIGHT)
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetTexture(BACKGROUND)
	back:SetSize(24, 24)
	back:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	local ring = button:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(RING)
	ring:SetSize(50, 50)
	ring:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function() DR.Window:Toggle() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", followCursor)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Forever Dungeon Routes"], 1, 1, 1)
		GameTooltip:AddLine(L["Click: show or hide the map\nDrag: move the button"], 0.4, 0.8, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	DR.MinimapButton = button
end

-- Shows or hides the button as set; called after loading and when the setting changes.
function DR:UpdateMinimapButton()
	if not Minimap then return end
	if not DR.db.minimapButton then
		if button then button:Hide() end
		return
	end
	if not button then build() end
	place()
	button:Show()
end

DR:On("SETTINGS_CHANGED", function(key)
	if key == "minimapButton" then
		DR:UpdateMinimapButton()
	end
end)
