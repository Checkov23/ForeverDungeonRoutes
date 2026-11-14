local _, DR = ...
local L = DR.L

-- Window styles: frames and colours of the addon's own windows (map window, small display, dialog).
-- The map art stays as it is. A style is chosen behind the gear button and applies at once: every
-- styled box and text registers here and is styled again when the style changes.

local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"
local SOLID = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
-- the addon's own gold frame (media\frame: a beveled gold band lit from the top, a thin inner line
-- curving in at the corners; werkzeug/stil_vergoldet.py) on a dark ground with a faint diamond
-- pattern; the ground reaches 1 under the gold band, so no seam can open between them
local GILDED_FRAME = {
	bgFile = MEDIA .. "panel", edgeFile = MEDIA .. "frame",
	tile = true, tileSize = 128, tileEdge = true, edgeSize = 16,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
-- a narrower gold band without the inner line, for the small display and the small map
local GILDED_SMALL = {
	bgFile = MEDIA .. "panel", edgeFile = MEDIA .. "frame-small",
	tile = true, tileSize = 128, tileEdge = true, edgeSize = 16,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
-- the game's own dialog and tooltip frames (Forever client: Blizzard_SharedXML/Backdrop.lua)
local GOLD_DIALOG = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tile = true, tileEdge = true, tileSize = 32, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local TOOLTIP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileEdge = true, tileSize = 16, edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

DR.THEMES = {
	{
		-- a beveled gold frame on a dark ground, the title plate on the top edge, gold stones at the
		-- corners, the dungeon as title, the floors as tabs, the map set in, gold-framed buttons and a
		-- footer (Window.lua draws these where a style has "ornate"; since 1.2.0, before brick walls)
		key = "gilded", name = "Gilded",
		window = GILDED_FRAME, small = GILDED_SMALL, bg = { 1, 1, 1 }, border = { 1, 1, 1, 1 }, -- the frame's own colours
		field = SOLID, fieldBg = { 0.05, 0.037, 0.025, 1 }, fieldBorder = { 0.62, 0.48, 0.21, 1 },
		hover = { 0.98, 0.82, 0.44, 1 }, fieldText = { 0.95, 0.91, 0.82 }, arrow = { 0.88, 0.72, 0.38 },
		icon = { 0.88, 0.72, 0.38 }, iconHover = { 1, 0.9, 0.6 },
		text = { 0.93, 0.89, 0.8 }, next = { 1, 0.82, 0.3 }, dim = { 0.7, 0.64, 0.53 }, done = { 0.56, 0.5, 0.41 },
		muted = { 0.62, 0.55, 0.43 }, title = { 0.99, 0.83, 0.41 }, accent = { 0.86, 0.71, 0.38 },
		link = { 0.5, 0.78, 1 }, linkHover = { 0.72, 0.9, 1 }, hint = { 0.82, 0.76, 0.62 },
		highlight = { 1, 0.82, 0.4, 0.14 }, badgeFill = { 0.05, 0.035, 0.02, 0.95 },
		kinds = { boss = { 0.9, 0.74, 0.33 }, rare = { 0.89, 0.87, 0.82 }, optional = { 0.62, 0.78, 0.95 } },
		shadow = true,
		mapBg = { 0, 0, 0, 0.15 },             -- beside the map art: the ground shows through, set in
		grip = { 1, 0.9, 0.62 },               -- the corner grip
		-- gold-framed dark buttons instead of the game's red ones, lit from the top (Theme: StyleButton)
		button = {
			fill = { 0.1, 0.073, 0.045, 1 }, shine = { 1, 0.86, 0.52, 0.14 }, outline = { 0, 0, 0, 0.7 },
			borderTop = { 0.86, 0.69, 0.36, 1 }, borderSide = { 0.62, 0.48, 0.21, 1 }, borderBottom = { 0.34, 0.25, 0.11, 1 },
			hover = { 1, 0.84, 0.45, 0.12 }, hoverBorder = { 0.98, 0.82, 0.44, 1 }, pressed = { 0.04, 0.03, 0.02, 1 },
			disabledFill = { 0.05, 0.04, 0.03, 0.7 }, disabledBorder = { 0.3, 0.25, 0.17, 1 },
			primaryFill = { 0.19, 0.135, 0.065, 1 }, primaryTop = { 1, 0.88, 0.5, 1 }, primarySide = { 0.86, 0.7, 0.36, 1 },
			primaryBottom = { 0.5, 0.38, 0.17, 1 },
			text = { 0.99, 0.83, 0.41 }, textHover = { 1, 0.93, 0.72 }, textDisabled = { 0.5, 0.45, 0.37 },
			textPlain = { 0.93, 0.89, 0.8 },
		},
		ornate = {
			gold = { 0.88, 0.72, 0.38, 1 },        -- small stones beside the title
			trim = { 0.6, 0.46, 0.2, 1 },          -- dividers, the frame of the map
			band = { 0, 0, 0, 0.22 },              -- every other stop
			nextBase = { 0.2, 0.15, 0.07, 0.85 },  -- the next stop: a warm row
			nextFill = { 1, 0.8, 0.36, 0.2 },      -- and on it a gold light fading to the right
			nextBar = { 1, 0.84, 0.42, 1 },
			check = { 1, 1, 1 },                   -- the green tick as in the other styles
			glow = { 1, 0.78, 0.4, 0.07 },         -- light from the top of the window
			vignette = { 0, 0, 0, 0.55 },          -- darker towards the edges
			tabLine = { 1, 0.84, 0.42, 1 },        -- under the chosen tab
			tabGlow = { 1, 0.8, 0.36, 0.24 },
			shade = { 0, 0, 0, 0.5 },              -- the map's inner shadow
			dropShadow = { 0, 0, 0, 0.6 },         -- around the window
		},
		gripHover = { 1, 0.9, 0.6 },
	},
	{
		key = "dark", name = "Dark",
		window = SOLID, bg = { 0.07, 0.07, 0.08 }, border = { 0.76, 0.66, 0.47, 0.9 },
		field = SOLID, fieldBg = { 0.12, 0.11, 0.1, 1 }, fieldBorder = { 0.76, 0.66, 0.47, 0.9 },
		hover = { 1, 0.9, 0.6, 1 }, fieldText = { 1, 1, 1 }, arrow = { 1, 0.82, 0 },
		icon = { 0.76, 0.66, 0.47 }, iconHover = { 1, 0.9, 0.6 },
		text = { 1, 1, 1 }, next = { 1, 0.92, 0.6 }, dim = { 0.72, 0.72, 0.72 }, done = { 0.5, 0.5, 0.5 },
		muted = { 0.5, 0.5, 0.5 }, title = { 1, 0.82, 0 }, accent = { 1, 0.86, 0.5 },
		link = { 0.45, 0.78, 1 }, linkHover = { 0.7, 0.9, 1 }, hint = { 0.75, 0.85, 1 },
		highlight = { 1, 0.85, 0.5, 0.12 }, badgeFill = { 0.06, 0.05, 0.04, 0.95 },
		kinds = { boss = { 0.95, 0.76, 0.31 }, rare = { 0.89, 0.87, 0.82 }, optional = { 0.62, 0.78, 0.95 } },
		shadow = true,
	},
	{
		-- light like the map art, dark text without shadow
		key = "parchment", name = "Parchment",
		window = SOLID, bg = { 0.86, 0.79, 0.64 }, border = { 0.42, 0.31, 0.17, 1 },
		field = SOLID, fieldBg = { 0.93, 0.88, 0.77, 1 }, fieldBorder = { 0.42, 0.31, 0.17, 1 },
		hover = { 0.2, 0.12, 0.04, 1 }, fieldText = { 0.18, 0.12, 0.05 }, arrow = { 0.42, 0.31, 0.17 },
		icon = { 0.42, 0.31, 0.17 }, iconHover = { 0.18, 0.12, 0.05 },
		text = { 0.18, 0.12, 0.05 }, next = { 0.62, 0.22, 0.02 }, dim = { 0.42, 0.36, 0.28 }, done = { 0.58, 0.53, 0.45 },
		muted = { 0.38, 0.32, 0.24 }, title = { 0.45, 0.25, 0.05 }, accent = { 0.55, 0.3, 0.05 },
		link = { 0.08, 0.3, 0.62 }, linkHover = { 0.15, 0.42, 0.85 }, hint = { 0.15, 0.3, 0.55 },
		highlight = { 0.45, 0.3, 0.1, 0.15 }, badgeFill = { 0.95, 0.91, 0.8, 1 },
		kinds = { boss = { 0.72, 0.45, 0.04 }, rare = { 0.4, 0.37, 0.33 }, optional = { 0.18, 0.4, 0.72 } },
		shadow = false,
	},
	{
		-- the game's gold dialog frame, fields like its tooltips
		key = "classic", name = "Classic",
		window = GOLD_DIALOG, bg = { 1, 1, 1 }, border = { 1, 1, 1, 1 },
		field = TOOLTIP, fieldBg = { 0.09, 0.09, 0.19, 1 }, fieldBorder = { 0.8, 0.8, 0.8, 1 },
		hover = { 1, 0.82, 0, 1 }, fieldText = { 1, 1, 1 }, arrow = { 1, 0.82, 0 },
		icon = { 1, 0.82, 0 }, iconHover = { 1, 1, 1 },
		text = { 1, 1, 1 }, next = { 1, 0.82, 0 }, dim = { 0.75, 0.75, 0.75 }, done = { 0.5, 0.5, 0.5 },
		muted = { 0.6, 0.6, 0.6 }, title = { 1, 0.82, 0 }, accent = { 1, 0.82, 0 },
		link = { 0.25, 0.78, 0.92 }, linkHover = { 0.6, 0.9, 1 }, hint = { 0.75, 0.85, 1 },
		highlight = { 0.35, 0.55, 1, 0.18 }, badgeFill = { 0.04, 0.04, 0.08, 0.95 },
		kinds = { boss = { 1, 0.82, 0 }, rare = { 0.85, 0.85, 0.85 }, optional = { 0.4, 0.75, 1 } },
		shadow = true,
	},
}

local byKey = {}
for _, theme in ipairs(DR.THEMES) do byKey[theme.key] = theme end

function DR.Theme()
	return byKey[DR.db and DR.db.theme] or DR.THEMES[1]
end

function DR.ThemeName(theme)
	return L[theme.name]
end

local boxes, texts, icons = {}, {}, {}

local function styleBox(frame, alpha, role)
	local t = DR.Theme()
	if role == "field" or role == "input" then
		frame:SetBackdrop(t.field)
		if role == "input" then
			frame:SetBackdropColor(0, 0, 0, 0.6) -- input fields stay dark, their text is white
		else
			local c = t.fieldBg
			frame:SetBackdropColor(c[1], c[2], c[3], c[4])
		end
		local b = t.fieldBorder
		frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
	else
		frame:SetBackdrop(role == "small" and t.small or t.window)
		frame:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], alpha)
		frame:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], t.border[4])
	end
end

-- A box of the addon: a window (role nil), a small window ("small": the small display and map; a
-- style may frame them more plainly), a choice field ("field") or an input ("input").
function DR.StyleBox(frame, alpha, role)
	frame.themeRole = role
	boxes[#boxes + 1] = { frame = frame, alpha = alpha or 0.96, role = role }
	styleBox(frame, alpha or 0.96, role)
end

-- The hover colour of a box's border and back to normal.
function DR.HoverBox(frame, on)
	local t = DR.Theme()
	local c = on and t.hover or (frame.themeRole == "field" and t.fieldBorder or t.border)
	frame:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

local function shadow(fs, t)
	if t.shadow then
		fs:SetShadowColor(0, 0, 0, 1)
	else
		fs:SetShadowColor(0, 0, 0, 0)
	end
end

local function styleText(fs, role)
	local t = DR.Theme()
	shadow(fs, t)
	local c = role and t[role]
	if c then fs:SetTextColor(c[1], c[2], c[3]) end
end

-- A text of the addon in a colour of the style (role: "text", "title", "muted", ...). Without a
-- role only the shadow follows the style; its colour is set where it is shown.
function DR.ThemeText(fs, role)
	texts[#texts + 1] = { fs = fs, role = role }
	styleText(fs, role)
end

local WHITE = { 1, 1, 1, 1 }
local BLACK = { 0, 0, 0, 1 }

local function tintIcon(tex, role)
	local c = DR.Theme()[role] or WHITE
	tex:SetVertexColor(c[1], c[2], c[3])
end

-- An icon tinted in the colour of the style ("icon"; a style without the role leaves it white).
function DR.ThemeIcon(tex, role)
	icons[#icons + 1] = { tex = tex, role = role }
	tintIcon(tex, role)
end

-- A plain colour of the style on a texture ("mapBg"; black where a style has none).
local fills = {}
local function fill(tex, role)
	local c = DR.Theme()[role] or BLACK
	tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

function DR.ThemeFill(tex, role)
	fills[#fills + 1] = { tex = tex, role = role }
	fill(tex, role)
end

-- Buttons of the game's template (UIPanelButtonTemplate). Styles with "button" hide its red parts
-- (Left, Middle, Right and its highlight) and show a dark box with a gold edge lit from the top
-- instead; with an icon ("close", "minus", "plus") only the icon in the style's colour, like the gear.
-- The mouse-over look sits in the HIGHLIGHT layer. The text takes the button's three font objects
-- (normal, mouse over, disabled; the game switches between them), so it keeps its size and the
-- style's gold in every state. Disabled and pressed buttons show so (hooked: the template's own
-- scripts stay).
local buttons = {}
local fontSets = {}

-- The button's fonts: normal, mouse over, disabled, and "plain" (a tool that is not chosen). The
-- game's own in styles without "button", else copies in the style's colours.
local function buttonFonts(small, s)
	if not s then
		if small then
			return GameFontNormalSmall, GameFontHighlightSmall, GameFontDisableSmall, GameFontHighlightSmall
		end
		return GameFontNormal, GameFontHighlight, GameFontDisable, GameFontHighlight
	end
	local key = small and "Small" or ""
	if not fontSets[key] then
		local set = {}
		for i, c in ipairs({ s.text, s.textHover, s.textDisabled, s.textPlain }) do
			local font = CreateFont("ForeverDungeonRoutesButton" .. key .. i)
			font:SetFontObject(small and GameFontNormalSmall or GameFontNormal)
			font:SetTextColor(c[1], c[2], c[3])
			set[i] = font
		end
		fontSets[key] = set
	end
	return unpack(fontSets[key])
end

-- Four lines around a button (inset < 0: outside it).
local function edges(b, layer, inset)
	local lines = {}
	for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = b:CreateTexture(nil, layer, nil, 3)
		if i <= 2 then
			line:SetPoint(side .. "LEFT", inset, i == 1 and -inset or inset)
			line:SetPoint(side .. "RIGHT", -inset, i == 1 and -inset or inset)
			line:SetHeight(1)
		else
			line:SetPoint("TOP" .. side, i == 3 and inset or -inset, -inset)
			line:SetPoint("BOTTOM" .. side, i == 3 and inset or -inset, inset)
			line:SetWidth(1)
		end
		lines[i] = line
	end
	return lines
end

local function buildSkin(b)
	local k = {}
	if b.skinIcon then
		local size = b.skinIconSize
		k.HoverBg = b:CreateTexture(nil, "HIGHLIGHT", nil, -1)
		k.HoverBg:SetAllPoints()
		k.Icon = b:CreateTexture(nil, "ARTWORK")
		k.Icon:SetTexture(MEDIA .. b.skinIcon)
		k.Icon:SetSize(size, size)
		k.Icon:SetPoint("CENTER")
		k.IconHover = b:CreateTexture(nil, "HIGHLIGHT")
		k.IconHover:SetTexture(MEDIA .. b.skinIcon)
		k.IconHover:SetAllPoints(k.Icon)
	else
		k.Outline = edges(b, "BACKGROUND", -1)
		k.Fill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
		k.Fill:SetAllPoints()
		k.Shine = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		k.Shine:SetTexture(MEDIA .. "fade-top")
		k.Shine:SetPoint("TOPLEFT", 1, -1)
		k.Shine:SetPoint("BOTTOMRIGHT", b, "RIGHT", -1, 0)
		k.Edges = edges(b, "BORDER", 0)
		k.Hover = b:CreateTexture(nil, "HIGHLIGHT")
		k.Hover:SetPoint("TOPLEFT", 1, -1)
		k.Hover:SetPoint("BOTTOMRIGHT", -1, 1)
		k.HoverEdges = edges(b, "HIGHLIGHT", 0)
	end
	b.fdrSkin = k
end

local function color(tex, c, asTexture)
	if asTexture then
		tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	else
		tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end
end

local function styleButton(b)
	local s = DR.Theme().button
	for _, part in ipairs({ "Left", "Middle", "Right" }) do
		if b[part] then b[part]:SetShown(s == nil) end
	end
	local highlight = b:GetHighlightTexture()
	if highlight then highlight:SetAlpha(s and 0 or 1) end
	local normal, over, disabled, plain = buttonFonts(b.skinSmall, s)
	b:SetNormalFontObject(b.skinSelected == false and plain or normal)
	b:SetHighlightFontObject(over)
	b:SetDisabledFontObject(disabled)
	local text = b:GetFontString()
	if text then text:SetShown(s == nil or b.skinIcon == nil) end
	if s and not b.fdrSkin then buildSkin(b) end
	local k = b.fdrSkin
	if not k then return end
	if k.Icon then
		for _, r in ipairs({ k.Icon, k.IconHover, k.HoverBg }) do r:SetShown(s ~= nil) end
		if s then
			tintIcon(k.Icon, "icon")
			tintIcon(k.IconHover, "iconHover")
			color(k.HoverBg, s.hover, true)
		end
		return
	end
	for _, r in ipairs({ k.Fill, k.Shine, k.Hover }) do r:SetShown(s ~= nil) end
	for i = 1, 4 do
		k.Outline[i]:SetShown(s ~= nil)
		k.Edges[i]:SetShown(s ~= nil)
		k.HoverEdges[i]:SetShown(s ~= nil)
	end
	if not s then return end
	local on, primary = b:IsEnabled(), b.skinPrimary
	local edge = not on and { s.disabledBorder, s.disabledBorder, s.disabledBorder, s.disabledBorder }
		or primary and { s.primaryTop, s.primaryBottom, s.primarySide, s.primarySide }
		or { s.borderTop, s.borderBottom, s.borderSide, s.borderSide }
	color(k.Fill, not on and s.disabledFill or b.skinPressed and s.pressed or primary and s.primaryFill or s.fill, true)
	color(k.Shine, s.shine)
	k.Shine:SetShown(on and not b.skinPressed)
	color(k.Hover, s.hover, true)
	for i = 1, 4 do
		color(k.Outline[i], s.outline, true)
		color(k.Edges[i], edge[i], true)
		color(k.HoverEdges[i], s.hoverBorder, true)
	end
end

-- A button of the game's template in the style. opts: icon (file in media that replaces the text in
-- styles with "button") and size of the icon, small (the small fonts), primary (the main button of a
-- dialog, a little brighter).
function DR.StyleButton(b, opts)
	opts = opts or {}
	b.skinIcon, b.skinIconSize, b.skinSmall, b.skinPrimary = opts.icon, opts.size or 12, opts.small, opts.primary
	buttons[#buttons + 1] = b
	b:HookScript("OnEnable", styleButton)
	b:HookScript("OnDisable", styleButton)
	b:HookScript("OnMouseDown", function(self)
		self.skinPressed = self:IsEnabled()
		styleButton(self)
	end)
	b:HookScript("OnMouseUp", function(self)
		self.skinPressed = false
		styleButton(self)
	end)
	b:HookScript("OnHide", function(self) self.skinPressed = false end)
	styleButton(b)
end

-- A tool button that is chosen or not (Editor): chosen in the normal gold, else in the plain colour.
function DR.ButtonSelected(b, chosen)
	b.skinSelected = chosen
	styleButton(b)
end

function DR:SetTheme(key)
	if not byKey[key] then return end
	DR.db.theme = key
	for _, b in ipairs(boxes) do styleBox(b.frame, b.alpha, b.role) end
	for _, x in ipairs(texts) do styleText(x.fs, x.role) end
	for _, i in ipairs(icons) do tintIcon(i.tex, i.role) end
	for _, f in ipairs(fills) do fill(f.tex, f.role) end
	for _, b in ipairs(buttons) do styleButton(b) end
	DR:Fire("SETTINGS_CHANGED", "theme")
end
