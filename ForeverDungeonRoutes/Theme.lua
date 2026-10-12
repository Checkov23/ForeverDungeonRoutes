local _, DR = ...
local L = DR.L

-- Window styles: frames and colours of the addon's own windows (map window, small display, dialog).
-- The map art stays as it is. A style is chosen behind the gear button and applies at once: every
-- styled box and text registers here and is styled again when the style changes.

local SOLID = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
-- dark brick walls (the addon's own texture, tiled) with a thin gold edge
local BRICK = {
	bgFile = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\brick", edgeFile = "Interface\\Buttons\\WHITE8X8",
	tile = true, tileSize = 128, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
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
	{
		-- brick walls framed in gold, with a title plate, the dungeon as title, the floors as tabs and a
		-- footer (Window.lua draws these where a style has "ornate")
		key = "gilded", name = "Gilded",
		window = BRICK, bg = { 1, 1, 1 }, border = { 0.79, 0.64, 0.15, 1 },
		field = SOLID, fieldBg = { 0.07, 0.05, 0.03, 1 }, fieldBorder = { 0.43, 0.31, 0.13, 1 },
		hover = { 1, 0.82, 0.25, 1 }, fieldText = { 0.93, 0.89, 0.8 }, arrow = { 0.79, 0.64, 0.15 },
		icon = { 0.79, 0.64, 0.15 }, iconHover = { 1, 0.86, 0.35 },
		text = { 0.93, 0.89, 0.8 }, next = { 1, 0.82, 0 }, dim = { 0.72, 0.65, 0.53 }, done = { 0.59, 0.52, 0.41 },
		muted = { 0.59, 0.52, 0.41 }, title = { 1, 0.82, 0 }, accent = { 0.84, 0.7, 0.27 },
		link = { 0.45, 0.78, 1 }, linkHover = { 0.7, 0.9, 1 }, hint = { 0.75, 0.85, 1 },
		highlight = { 1, 0.82, 0.3, 0.12 }, badgeFill = { 0.06, 0.04, 0.02, 0.95 },
		kinds = { boss = { 0.84, 0.69, 0.24 }, rare = { 0.89, 0.87, 0.82 }, optional = { 0.62, 0.78, 0.95 } },
		shadow = true,
		ornate = {
			trim = { 0.43, 0.31, 0.13, 1 },        -- inner line of the frame, lines and the map frame
			plate = { 0.07, 0.05, 0.03, 0.97 },    -- title plate and the chosen tab
			band = { 0, 0, 0, 0.28 },              -- every other stop
			nextFill = { 0.21, 0.15, 0.08, 0.9 },  -- the next stop
			nextBar = { 1, 0.82, 0, 1 },
			check = { 0.84, 0.69, 0.24 },
		},
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
		frame:SetBackdrop(t.window)
		frame:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], alpha)
		frame:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], t.border[4])
	end
end

-- A box of the addon: a window (role nil), a choice field ("field") or an input ("input").
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

-- An icon tinted in the colour of the style ("icon").
function DR.ThemeIcon(tex, role)
	icons[#icons + 1] = { tex = tex, role = role }
	local c = DR.Theme()[role]
	tex:SetVertexColor(c[1], c[2], c[3])
end

function DR:SetTheme(key)
	if not byKey[key] then return end
	DR.db.theme = key
	for _, b in ipairs(boxes) do styleBox(b.frame, b.alpha, b.role) end
	for _, x in ipairs(texts) do styleText(x.fs, x.role) end
	for _, i in ipairs(icons) do
		local c = DR.Theme()[i.role]
		i.tex:SetVertexColor(c[1], c[2], c[3])
	end
	DR:Fire("SETTINGS_CHANGED", "theme")
end
