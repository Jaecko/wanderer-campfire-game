local ADDON, ns = ...
local L = ns.L

-- The camp's window: tall and narrow, read at a glance. At the top its heading (the page's name; in a page
-- opened from another, a button back), then your resources; at the bottom the tabs (the fire, the camp, the
-- companions, the expeditions, the rest). A page opened from another (a companion, an expedition, the
-- road...) takes the window's place with its way back, as a menu would. Before the fire is lit, an invitation
-- to light it, then what your journey brings. While it is shown the camp is looked at every few seconds;
-- closed, nothing runs. And the notices of the expeditions back (an option, on).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH, HEIGHT = 420, 720
local HEAD, STRIP, TABS = 50, 38, 56 -- the heading, the resources' strip, the tabs
local LOOK_EVERY = 5 -- seconds between two looks while the window is shown
local RESOURCES = {
	{ key = "embers", icon = "Interface\\Icons\\Spell_Fire_Incinerate" },
	{ key = "provisions", icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ key = "renown", icon = "Interface\\Icons\\INV_Banner_02" },
	{ key = "supplies", icon = "Interface\\Icons\\INV_Crate_01" },
}
local ICONS = { ashes = "Interface\\Icons\\INV_Misc_Powder_Black" }
for _, resource in ipairs(RESOURCES) do ICONS[resource.key] = resource.icon end
ns.ICONS = ICONS

-- A resource's icon within a text (its edges cut away), and amounts said with their icons: "[icon] 12,4 k".
function ns.Icon(key, size)
	size = size or 14
	return "|T" .. ICONS[key] .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t"
end
function ns.Amount(key, value, sign) return ns.Icon(key) .. " " .. (sign or "") .. ns.Short(value) end
function ns.Gains(gains, sign)
	local parts = {}
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies", "ashes" }) do
		local value = gains[key]
		if value and value ~= 0 then parts[#parts + 1] = ns.Amount(key, math.abs(value), sign and (value > 0 and "+" or "-") or nil) end
	end
	return table.concat(parts, "   ")
end

local window, light, away, current
local pages, order = {}, {} -- every page by key; in the order they were added

local function Settings() return W and W.Settings and W.Settings("campfire") or nil end
local function Sound() if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end end

-- Numbers and times, said the same way everywhere.
function ns.Number(value)
	value = tonumber(value) or 0
	-- (very large: abbreviated, the game writes them badly)
	if value >= 1e9 then return ns.Short(value) end
	return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(value)) or tostring(math.floor(value))
end
-- A number as a player reads it: "1 234", "12,4 k", "3,25 M"; small ones with a decimal ("0,1").
local UNITS = { { 1e15, "NUMBER_Q" }, { 1e12, "NUMBER_T" }, { 1e9, "NUMBER_B" }, { 1e6, "NUMBER_M" }, { 1e4, "NUMBER_K", 1e3 } }
local POINT = DECIMAL_SEPERATOR or "."
function ns.Decimal(value, places)
	local text = ("%." .. places .. "f"):format(value)
	return (text:gsub("%.", POINT))
end
function ns.Short(value)
	value = tonumber(value) or 0
	if value ~= value then return "0" end -- (not a number)
	-- Past Q, as idle games say them: AA, AB... AZ, BA... each a thousand times the last.
	if value >= 9.995e17 then
		if value >= math.huge then return "\226\136\158" end -- (the infinity sign)
		local group = math.floor(math.log(value) / math.log(1000) + 1e-9)
		local scaled = value / 1000 ^ group
		-- (rounded up to a thousand of its unit: the next one, never "1000 AA")
		if scaled >= 999.5 then scaled, group = scaled / 1000, group + 1 end
		local index = group - 6 -- (1e18: AA)
		local name = string.char(65 + math.floor(index / 26) % 26, 65 + index % 26)
		return ns.Decimal(scaled, scaled < 10 and 2 or scaled < 100 and 1 or 0) .. " " .. name
	end
	for index, unit in ipairs(UNITS) do
		if value >= unit[1] then
			local scaled = value / (unit[3] or unit[1])
			-- (rounded up to a thousand of its unit: the next unit, never "1000 k")
			local bigger = UNITS[index - 1]
			if scaled >= 999.5 and bigger then
				scaled = value / bigger[1]
				unit = bigger
			end
			return ns.Decimal(scaled, scaled < 10 and 2 or scaled < 100 and 1 or 0) .. " " .. L[unit[2]]
		end
	end
	if value < 100 and value ~= math.floor(value) then return ns.Decimal(value, value < 1 and 2 or value < 10 and 1 or 0) end
	return ns.Number(value)
end

function ns.Minutes(minutes)
	if minutes < 60 then return L.MINUTES:format(minutes) end
	return L.HOURS:format(math.floor(minutes / 60))
end
function ns.Left(seconds) return U.Ago(math.max(60, seconds)) end

-- A number in Roman figures (the levels of the eternal blaze, the living embers): II, III, IV...
local ROMAN = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" },
	{ 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
function ns.Roman(value)
	local text = ""
	for _, pair in ipairs(ROMAN) do
		while value >= pair[1] do
			text = text .. pair[2]
			value = value - pair[1]
		end
	end
	return text
end

-- A tier's name: past the seventh, the eternal blaze and its level (II, III...).
function ns.TierName(index)
	if index <= 7 then return L["TIER_" .. index] end
	return L.TIER_7 .. " " .. ns.Roman(index - 6)
end

-- The pieces of the pages ---------------------------------------------------------------------------------
-- A list that scrolls (UI.List), drawn from the top down each time its page is drawn: list:Begin(), then
-- its pieces (a caption, a text, a row, a frame of the page's own), list:Done(). Its scroll bar beside it,
-- shown when there is more than it holds: the wheel, the thumb dragged or the rail clicked scroll it.
-- A row: spec { icon, quality, coords (a part of its texture), grey (its icon faded), shape (its icon dark: not known yet), title, color,
-- sub, wrap (its sub on several lines), right (a big number), chip, tone, bar (0 to 1), action = { text, fn,
-- enabled, tip }, onClick (a chevron: it opens something; plain: no chevron), tip (lines, the first in gold), dim, chosen }.

local UI = {}
ns.UI = UI

-- Movement, kept light: a tween runs fn(progress) from 0 to 1 over its seconds (eased), then done(); one
-- frame drives them all, and only while one runs. A tween of the same key takes the place of the last.
local tweens = {}
local animator = CreateFrame("Frame")
-- (a step that fails ends its tween, never the others; what ends is told once the round is over)
local function Animate(_, elapsed)
	local finished
	for key, tween in pairs(tweens) do
		tween.age = tween.age + elapsed
		local t = math.min(1, tween.age / tween.duration)
		if not pcall(tween.fn, 1 - (1 - t) * (1 - t)) then t = 1 end
		if t >= 1 then
			tweens[key] = nil
			finished = finished or {}
			finished[#finished + 1] = tween.done
		end
	end
	for _, done in ipairs(finished or {}) do pcall(done) end
	if not next(tweens) then animator:SetScript("OnUpdate", nil) end
end
function UI.Tween(key, duration, fn, done)
	tweens[key] = { age = 0, duration = duration, fn = fn, done = done }
	if not pcall(fn, 0) then tweens[key] = nil return end
	animator:SetScript("OnUpdate", Animate)
end

-- A soft golden glint over a frame (a purchase, a choice): there, then gone in a moment.
function UI.Flash(frame, strength)
	if not frame.wandererFlash then
		frame.wandererFlash = frame:CreateTexture(nil, "OVERLAY")
		frame.wandererFlash:SetAllPoints()
		frame.wandererFlash:SetColorTexture(1, 0.78, 0.3, 1)
		frame.wandererFlash:SetBlendMode("ADD")
		frame.wandererFlash:SetAlpha(0)
	end
	local glint = frame.wandererFlash
	UI.Tween(glint, 0.6, function(t) glint:SetAlpha((strength or 0.28) * (1 - t)) end)
end

-- A page, a card come into sight: from clear to seen.
function UI.Appear(frame, duration)
	UI.Tween(frame, duration or 0.2, function(t) frame:SetAlpha(t) end)
end
local RAIL = 12 -- the scroll bar's room
local THUMB_MIN = 24
local ROW = 54 -- a row's height
local GOLD = { 1, 0.82, 0 }
local CROP = { 0.08, 0.92, 0.08, 0.92 } -- (an icon's edges cut away)

local function NewRow(list)
	local row = CreateFrame("Button", nil, list)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.ground = row:CreateTexture(nil, "BACKGROUND")
	row.ground:SetAllPoints()
	row.edges = Skin.Edges(row, 1, 1, 1, 0.07)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.icon = Skin.Icon(row, 36)
	row.icon:SetPoint("LEFT", row, "LEFT", 9, 0)
	row.title = Skin.CreateText(row, "GameFontNormal")
	if row.title.SetWordWrap then row.title:SetWordWrap(false) end
	row.sub = Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.sub:SetJustifyH("LEFT")
	row.sub:SetSpacing(2)
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.right:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.right:SetTextColor(0.88, 0.85, 0.77, 0.9)
	row.chip = Skin.Chip(row)
	row.action = Skin.SmallButton(row, "", function(self)
		if self.run then self.run(self) end
		UI.Flash(row)
	end, nil, 26)
	Skin.Tooltip(row.action, function(self) return self.tip end)
	row.more = row:CreateTexture(nil, "ARTWORK")
	row.more:SetSize(14, 14)
	row.more:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.more:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	row.track = row:CreateTexture(nil, "BORDER")
	row.track:SetPoint("BOTTOMLEFT", 1, 1)
	row.track:SetPoint("BOTTOMRIGHT", -1, 1)
	row.track:SetHeight(2)
	row.track:SetColorTexture(1, 1, 1, 0.06)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("BOTTOMLEFT", 1, 1)
	row.bar:SetHeight(2)
	row.bar:SetColorTexture(1, 0.7, 0.25, 0.85)
	row:SetScript("OnClick", function(self, mouse)
		local spec = self.spec
		if spec and spec.onClick then
			Sound()
			spec.onClick(self, mouse)
			if spec.plain then UI.Flash(self, 0.2) end
		end
	end)
	row:SetScript("OnEnter", function(self)
		local spec = self.spec
		local tip = spec and spec.tip
		-- (no words of its own: its whole title, when it was cut)
		if not tip and spec and self.title.IsTruncated and self.title:IsTruncated() then tip = { self.title:GetText() } end
		if not tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if spec.link then
			GameTooltip:SetHyperlink(spec.link)
		else
			for index, line in ipairs(type(tip) == "table" and tip or { tip }) do
				if index == 1 then GameTooltip:AddLine(line, GOLD[1], GOLD[2], GOLD[3]) else GameTooltip:AddLine(line, 1, 1, 1, true) end
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

-- A row filled from its spec; its height (taller when its sub runs on several lines).
local function FillRow(row, spec, width)
	row.spec = spec
	row.hover:SetShown(spec.onClick ~= nil)
	local left = 12
	row.icon:SetShown(spec.icon ~= nil)
	if spec.icon then
		row.icon:Set(spec.icon, spec.quality)
		local coords = spec.coords or CROP
		row.icon.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		local shade = spec.shape and 0 or 1
		row.icon.texture:SetVertexColor(shade, shade, shade)
		row.icon.texture:SetDesaturated(spec.grey and true or false)
		left = 56
	end
	-- On the right: a button and a chip (one above the other), or a big number, or a chevron.
	local right = 12
	row.action:SetShown(spec.action ~= nil)
	row.chip:Set(spec.chip, spec.tone)
	row.action:ClearAllPoints()
	row.chip:ClearAllPoints()
	if spec.action then
		row.action:SetLabel(spec.action.text)
		row.action:SetEnabled(spec.action.enabled ~= false)
		row.action.run, row.action.tip = spec.action.fn, spec.action.tip
		right = math.max(right, row.action:GetWidth() + 20)
	end
	if spec.chip then right = math.max(right, row.chip:GetWidth() + 20) end
	if spec.action and spec.chip then
		row.chip:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
		row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 7)
	elseif spec.action then
		row.action:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	elseif spec.chip then
		row.chip:SetPoint("RIGHT", row, "RIGHT", (spec.onClick and not spec.plain) and -30 or -10, 0)
		if spec.onClick and not spec.plain then right = right + 20 end
	end
	row.right:SetText(spec.right or "")
	row.right:SetShown(spec.right ~= nil)
	if spec.right then right = math.max(right, U.Measure(row.right, "GetStringWidth", 30) + 24) end
	row.more:SetShown(spec.onClick ~= nil and not spec.plain and spec.action == nil and spec.right == nil)
	if row.more:IsShown() and not spec.chip then right = math.max(right, 30) end
	-- The words.
	local room = width - left - right
	row.title:ClearAllPoints()
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -10)
	row.title:SetWidth(room)
	row.title:SetText(spec.title or "")
	local color = spec.color or Skin.COLORS.text
	row.title:SetTextColor(color[1], color[2], color[3])
	row.sub:ClearAllPoints()
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
	row.sub:SetWidth(room)
	if row.sub.SetWordWrap then row.sub:SetWordWrap(spec.wrap and true or false) end
	row.sub:SetText(spec.sub or "")
	row.sub:SetShown(spec.sub ~= nil)
	local height = spec.height or ROW
	if spec.wrap and spec.sub then height = math.max(height, 10 + 15 + 4 + math.ceil(row.sub:GetStringHeight() or 14) + 11) end
	-- (a chip above a button: room for both)
	if spec.action and spec.chip then height = math.max(height, 62) end
	if not spec.sub then
		row.title:ClearAllPoints()
		row.title:SetPoint("LEFT", row, "LEFT", left, 0)
	end
	-- How far along (the next one, a level).
	row.track:SetShown(spec.bar ~= nil)
	row.bar:SetShown(spec.bar ~= nil)
	if spec.bar then row.bar:SetWidth(math.max(1, (width - 2) * math.max(0, math.min(1, spec.bar)))) end
	if spec.chosen then row.ground:SetColorTexture(1, 0.82, 0, 0.08) else row.ground:SetColorTexture(1, 1, 1, 0.035) end
	row.edges.Color(1, spec.chosen and 0.82 or 1, spec.chosen and 0 or 1, spec.chosen and 0.35 or 0.07)
	row:SetAlpha(spec.dim and 0.55 or 1)
	return height
end

function UI.List(parent, width, shown)
	width, shown = width or parent.width, shown or parent.height
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetSize(width, shown)
	scroll:SetPoint("TOPLEFT")
	local list = CreateFrame("Frame", nil, scroll)
	list.width, list.view, list.total = width - RAIL, shown, 0
	list:SetSize(list.width, 1)
	scroll:SetScrollChild(list)
	list.scroll = scroll
	parent.list = parent.list or list -- (a page's list: back to its top when the page is opened again)
	list.pools, list.used, list.placed = { row = {}, caption = {}, text = {} }, {}, {}
	-- The scroll bar: a thin rail, a thumb as long as the part shown (dragged; the rail clicked: a page).
	local bar = CreateFrame("Button", nil, scroll)
	bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
	bar:SetWidth(RAIL - 2)
	local rail = bar:CreateTexture(nil, "BACKGROUND")
	rail:SetColorTexture(1, 0.82, 0, 0.18)
	rail:SetWidth(2)
	rail:SetPoint("TOP")
	rail:SetPoint("BOTTOM")
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(6)
	thumb.fill = thumb:CreateTexture(nil, "ARTWORK")
	thumb.fill:SetAllPoints()
	thumb.fill:SetColorTexture(1, 0.82, 0, 0.45)
	bar:Hide()
	local function Range() return math.max(0, list.total - list.view) end
	local function DrawBar()
		local range = Range()
		bar:SetShown(range > 0)
		if range <= 0 then return end
		local size = math.max(THUMB_MIN, math.floor(list.view * list.view / list.total))
		local position = math.floor((list.view - size) * scroll:GetVerticalScroll() / range + 0.5)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -position)
	end
	function list:ScrollTo(y)
		scroll:SetVerticalScroll(math.max(0, math.min(Range(), y)))
		DrawBar()
	end
	function list:Top() self:ScrollTo(0) end
	local function CursorTop()
		local _, y = GetCursorPosition()
		return (bar:GetTop() or 0) - y / bar:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self)
		self.grab = CursorTop() - (scroll:GetVerticalScroll() / math.max(1, Range())) * (list.view - self:GetHeight())
		self:SetScript("OnUpdate", function(own)
			-- Let go anywhere: the drag ends.
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return own:SetScript("OnUpdate", nil) end
			local free = list.view - own:GetHeight()
			if free > 0 then list:ScrollTo((CursorTop() - own.grab) / free * Range()) end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function(self) self.fill:SetColorTexture(1, 0.82, 0, 0.8) end)
	thumb:SetScript("OnLeave", function(self) self.fill:SetColorTexture(1, 0.82, 0, 0.45) end)
	bar:SetScript("OnClick", function()
		local position = (scroll:GetVerticalScroll() / math.max(1, Range())) * (list.view - thumb:GetHeight())
		local below = CursorTop() > position + thumb:GetHeight()
		list:ScrollTo(scroll:GetVerticalScroll() + (below and 1 or -1) * (list.view - 40))
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta) list:ScrollTo(scroll:GetVerticalScroll() - delta * 60) end)

	local y = 0
	local function Take(kind, make)
		list.used[kind] = (list.used[kind] or 0) + 1
		local pool = list.pools[kind]
		local piece = pool[list.used[kind]]
		if not piece then
			piece = make()
			pool[#pool + 1] = piece
		end
		piece:ClearAllPoints()
		piece:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
		piece:Show()
		return piece
	end
	function list:Begin()
		y = 0
		wipe(self.used)
		wipe(self.placed)
	end
	function list:Gap(height) y = y + height end
	-- A section's caption (aside: a few words at its right).
	function list:Caption(text, aside, role)
		if y > 0 then y = y + 10 end
		local caption = Take("caption", function()
			local frame = CreateFrame("Frame", nil, list)
			frame:SetHeight(16)
			frame.caps = Skin.Caps(frame, "")
			frame.caps:SetPoint("LEFT")
			frame.aside = Skin.Text(frame, "GameTooltipTextSmall", "muted")
			frame.aside:SetPoint("RIGHT")
			return frame
		end)
		caption:SetWidth(self.width)
		caption.caps:SetText(U.Upper(text or ""))
		local c = Skin.COLORS[role or "gold"] or Skin.COLORS.gold
		caption.caps:SetTextColor(c[1], c[2], c[3])
		caption.aside:SetText(aside or "")
		y = y + 16 + 6
		return caption
	end
	-- A text across the list, on as many lines as it needs.
	function list:Text(text, role, template)
		local holder = Take("text", function()
			local frame = CreateFrame("Frame", nil, list)
			frame.text = Skin.Text(frame, "GameTooltipTextSmall", "soft")
			frame.text:SetPoint("TOPLEFT")
			frame.text:SetJustifyH("LEFT")
			frame.text:SetSpacing(2)
			return frame
		end)
		holder.text:SetFontObject(template or "GameTooltipTextSmall")
		local c = Skin.COLORS[role or "soft"] or Skin.COLORS.soft
		holder.text:SetTextColor(c[1], c[2], c[3])
		holder.text:SetWidth(self.width)
		holder.text:SetText(text or "")
		local height = math.ceil(holder.text:GetStringHeight() or 14)
		holder:SetSize(self.width, height)
		y = y + height + 8
		return holder.text
	end
	function list:Row(spec)
		local row = Take("row", function() return NewRow(list) end)
		row:SetWidth(self.width)
		local height = FillRow(row, spec, self.width)
		row:SetHeight(height)
		y = y + height + 4
		return row
	end
	-- A frame of the page's own (hidden when a drawing leaves it out).
	function list:Put(frame, height, gap, keepWidth)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
		if not keepWidth then frame:SetWidth(self.width) end
		frame:SetHeight(height)
		frame:Show()
		self.placed[frame] = true
		self.own = self.own or {}
		self.own[frame] = true
		y = y + height + (gap or 8)
	end
	function list:Done()
		for kind, pool in pairs(self.pools) do
			for index = (self.used[kind] or 0) + 1, #pool do pool[index]:Hide() end
		end
		for frame in pairs(self.own or {}) do
			if not self.placed[frame] then frame:Hide() end
		end
		self.total = y
		self:SetHeight(math.max(1, y))
		self:ScrollTo(scroll:GetVerticalScroll())
	end
	return list, scroll
end

-- A card: a soft panel with a caption and words, placed by its page.
function UI.Card(parent)
	local card = Skin.Panel(parent)
	card.caption = Skin.Caps(card, "", "gold")
	card.caption:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
	card.text = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.text:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -6)
	card.text:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.text:SetJustifyH("LEFT")
	card.text:SetSpacing(2)
	return card
end

-- Pages -----------------------------------------------------------------------------------------------------

-- A page: its key, its name, build(frame) once, draw(arg) each time it is shown or the camp changes.
-- opts: { tab (its place among the tabs), icon, parent (a page opened from that one: a way back),
-- screen (the whole window, no tabs), title(arg) (its heading), desc (a menu's line), badge() (something to
-- do there: a dot on its tab), summary() (a chip in a menu: text, tone) }.
function ns.AddPage(key, label, build, draw, opts)
	opts = opts or {}
	local page = { key = key, label = label, build = build, draw = draw }
	for name, value in pairs(opts) do page[name] = value end
	pages[key] = page
	order[#order + 1] = page
end

-- Your resources, on a strip: each with its icon; hovered, what it is for.
local function Write(region, text)
	if region.wandererText ~= text then
		region.wandererText = text
		region:SetText(text)
	end
end
local function Resources()
	local s = ns.State()
	local cells = window.strip.cells
	Write(cells.embers.value, ns.Short(s.embers))
	Write(cells.provisions.value, ns.Short(s.provisions) .. U.Colorize(" / " .. ns.Short(ns.Rates().provisionsCap), 0.56, 0.53, 0.46))
	Write(cells.renown.value, ns.Short(s.renown))
	Write(cells.supplies.value, ns.Short(s.supplies))
end

local function Heading(welcome, page)
	local back = not welcome and page and page.parent ~= nil
	window.back:SetShown(back)
	window.kicker:ClearAllPoints()
	window.kicker:SetPoint("TOPLEFT", window, "TOPLEFT", window.margin + (back and 38 or 0), -window.margin)
	if welcome or not page then
		window.kicker:SetText(U.Upper("Wanderer"))
		window.title:SetText(L.TITLE)
	elseif back then
		local from = pages[page.back or page.parent]
		window.kicker:SetText(U.Upper(from and from.label or L.TITLE))
		window.title:SetText(page.title and page.title(page.arg) or page.label)
	else
		window.kicker:SetText(U.Upper(L.TITLE))
		window.title:SetText(page.title and page.title(page.arg) or page.label)
	end
end

-- (the dots of the tabs breathe while something waits)
local function Breathe()
	local glow = 0.55 + 0.45 * math.sin(GetTime() * 3)
	for _, button in ipairs(window.tabs.buttons) do button.dot:SetAlpha(glow) end
end

local function Tabs(page)
	local any = false
	local tab, steps = page, 0
	while tab.parent and steps < 5 do
		tab = pages[tab.back or tab.parent] or pages[tab.parent]
		steps = steps + 1
	end
	for _, button in ipairs(window.tabs.buttons) do
		local on = button.page == tab
		button.mark:SetShown(on)
		button.icon:SetDesaturated(not on)
		button.icon:SetAlpha(on and 1 or 0.6)
		local c = on and Skin.COLORS.gold or Skin.COLORS.muted
		button.label:SetTextColor(c[1], c[2], c[3])
		button.dot:SetShown(button.page.badge ~= nil and button.page.badge() and true or false)
		any = any or button.dot:IsShown()
	end
	window.tabs:SetScript("OnUpdate", any and Breathe or nil)
end

local function Draw()
	if not (window and window:IsShown()) then return end
	local lit = ns.Lit()
	-- (between two fires: the ashes, nothing else)
	if lit and ns.State().choosing and pages.ashes then
		current = pages.ashes
	elseif current == pages.ashes and not ns.State().choosing then
		current = pages.fire or current
	end
	local welcome = not lit or light.heritage ~= nil
	light:SetShown(welcome)
	local page = current
	window.strip:SetShown(not welcome and not page.screen)
	window.tabs:SetShown(not welcome and not page.screen)
	for _, each in ipairs(order) do
		if each.frame then each.frame:SetShown(not welcome and each == page) end
	end
	Heading(welcome, page)
	if welcome then return end
	Resources()
	Tabs(page)
	page.draw(page.arg)
end
ns.Redraw = Draw

-- A page shown (arg: what it shows, a companion, a place...). Opened from another, its way back leads there.
local function Show(key, arg, returning)
	local page = pages[key]
	if not page then return end
	if not returning and page.parent and current and current ~= page then page.back = current.screen and page.parent or current.key end
	if not returning and (current ~= page or (arg ~= nil and arg ~= page.arg)) and page.frame and page.frame.list then page.frame.list:Top() end
	if arg ~= nil then page.arg = arg end
	local new = current ~= page
	current = page
	Draw()
	if new and page.frame and page.frame:IsShown() then UI.Appear(page.frame) end
end
ns.ShowPage = Show

local function GoBack()
	if current and current.parent then Show(current.back or current.parent, nil, true) end
end
ns.GoBack = GoBack
function ns.CurrentArg() return current and current.arg end

-- The rest: a menu of the pages opened from it (their icon, a line, what waits there).
local function BuildMore(page) UI.List(page) end
local function DrawMore()
	local list = pages.more.frame.list
	list:Begin()
	for _, each in ipairs(order) do
		if each.parent == "more" then
			local chip, tone
			if each.summary then chip, tone = each.summary() end
			list:Row({ icon = each.icon, title = each.label, color = Skin.COLORS.gold, sub = each.desc, wrap = true, chip = chip, tone = tone,
				height = 62, onClick = function() Show(each.key) end })
		end
	end
	list:Done()
end
ns.AddPage("more", L.TAB_MORE, BuildMore, DrawMore, { tab = 5, icon = "Interface\\Icons\\INV_Misc_Book_09",
	badge = function()
		for _, wanted in ipairs(ns.State().orders) do if ns.CanHonor(wanted) then return true end end
		return false
	end })

-- Before the fire: an invitation; after it is lit, what your journey brought (once).
local function BuildLight()
	light = Skin.Panel(window)
	light:SetPoint("TOPLEFT", window, "TOPLEFT", window.margin, -(window.margin + HEAD + 20))
	light:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -window.margin, window.margin + 20)
	light.icon = Skin.Icon(light, 56)
	light.icon:SetPoint("TOP", light, "TOP", 0, -34)
	light.icon:Set("Interface\\Icons\\Spell_Fire_Fire", 1)
	light.title = Skin.Text(light, "GameFontNormalLarge", "gold")
	light.title:SetPoint("TOP", light.icon, "BOTTOM", 0, -18)
	light.text = Skin.Text(light, "GameTooltipText", "soft")
	light.text:SetPoint("TOPLEFT", light, "TOPLEFT", 26, -150)
	light.text:SetPoint("RIGHT", light, "RIGHT", -26, 0)
	light.text:SetJustifyH("LEFT")
	light.text:SetSpacing(4)
	light.button = Skin.Button(light, L.LIGHT_BUTTON, function()
		if light.heritage then
			light.heritage = nil
			Show("fire")
			return
		end
		local heritage = ns.Light()
		if not heritage then return Draw() end
		local lines = { L.HERITAGE_TEXT, "" }
		for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
			if (heritage[key] or 0) > 0 then lines[#lines + 1] = "  " .. ns.Amount(key, heritage[key]) .. "  " .. L[key:upper()] end
		end
		if heritage.veteran then lines[#lines + 1] = "  " .. L.HERITAGE_VETERAN:format(heritage.veteran) end
		lines[#lines + 1] = "  " .. L.HERITAGE_ZONES:format(heritage.zones)
		light.heritage = table.concat(lines, "\n")
		light.title:SetText(L.HERITAGE_TITLE)
		light.text:SetText(light.heritage)
		light.button:SetText(OKAY or "OK")
		light.button:Fit()
		Draw()
		UI.Appear(light, 0.4)
	end, "main", 200)
	light.button:SetHeight(40)
	light.button:SetPoint("BOTTOM", light, "BOTTOM", 0, 30)
	light.title:SetText(L.LIGHT_TITLE)
	light.text:SetText(L.LIGHT_TEXT)
end

-- While you were away: a card over the camp, what changed since you last saw it; a button back to the fire.
local function ShowAway(recap)
	if not away then
		away = Skin.Panel(window)
		away:SetPoint("LEFT", window, "LEFT", window.margin + 10, 0)
		away:SetPoint("RIGHT", window, "RIGHT", -(window.margin + 10), 0)
		away:SetHeight(300)
		away:SetPoint("CENTER", window, "CENTER", 0, 0)
		away:SetFrameLevel(window:GetFrameLevel() + 20)
		away:EnableMouse(true)
		local ground = away:CreateTexture(nil, "BACKGROUND", nil, -1)
		ground:SetAllPoints()
		ground:SetColorTexture(0.04, 0.035, 0.03, 0.97)
		away.title = Skin.Text(away, "GameFontNormalLarge", "gold")
		away.title:SetPoint("TOP", away, "TOP", 0, -24)
		away.title:SetText(L.AWAY_TITLE)
		away.since = Skin.Text(away, "GameTooltipTextSmall", "muted")
		away.since:SetPoint("TOP", away.title, "BOTTOM", 0, -6)
		away.text = Skin.Text(away, "GameTooltipText", "soft")
		away.text:SetPoint("TOPLEFT", away, "TOPLEFT", 30, -78)
		away.text:SetPoint("RIGHT", away, "RIGHT", -30, 0)
		away.text:SetJustifyH("LEFT")
		away.text:SetSpacing(5)
		away.button = Skin.Button(away, L.AWAY_BUTTON, function()
			away:Hide()
			Show("fire")
		end, "main", 200)
		away.button:SetHeight(38)
		away.button:SetPoint("BOTTOM", away, "BOTTOM", 0, 22)
	end
	away.since:SetText(L.AWAY_FOR:format(U.Ago(recap.away)))
	local lines = {}
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		if recap[key] > 0 then lines[#lines + 1] = ns.Amount(key, recap[key], "+") .. "  " .. L[key:upper()] end
	end
	if recap.back > 0 then lines[#lines + 1] = L.AWAY_BACK:format(recap.back, recap.won) end
	if recap.trophies > 0 then lines[#lines + 1] = L.AWAY_TROPHIES:format(recap.trophies) end
	if recap.levels > 0 then lines[#lines + 1] = L.AWAY_LEVELS:format(recap.levels) end
	away.text:SetText(table.concat(lines, "\n"))
	away:Show()
	UI.Appear(away, 0.35)
end

local function BuildStrip(margin)
	local strip = Skin.Panel(window)
	strip:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + HEAD))
	strip:SetSize(WIDTH - margin * 2, STRIP - 8)
	strip.cells = {}
	local width = (WIDTH - margin * 2) / #RESOURCES
	for index, resource in ipairs(RESOURCES) do
		local cell = CreateFrame("Frame", nil, strip)
		cell:SetPoint("TOPLEFT", strip, "TOPLEFT", (index - 1) * width, 0)
		cell:SetSize(width, STRIP - 8)
		cell:EnableMouse(true)
		cell.icon = Skin.Icon(cell, 20)
		cell.icon:SetPoint("LEFT", cell, "LEFT", 8, 0)
		cell.icon:Set(resource.icon)
		cell.value = Skin.Text(cell, "GameFontHighlightSmall", "text")
		cell.value:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
		cell.value:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
		if cell.value.SetWordWrap then cell.value:SetWordWrap(false) end
		local key = resource.key
		cell:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddDoubleLine(L[key:upper()], ns.Number(ns.State()[key]), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
			GameTooltip:AddLine(L[key:upper() .. "_DESC"], 1, 1, 1, true)
			if key == "embers" then GameTooltip:AddLine(L.PER_SECOND:format(ns.Short(ns.PerSecond())), 0.56, 0.88, 0.64) end
			if key == "provisions" then GameTooltip:AddLine(L.PER_HOUR:format(ns.Number(ns.Rates().provisions)), 0.56, 0.88, 0.64) end
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		strip.cells[key] = cell
	end
	window.strip = strip
end

local function BuildTabs(margin)
	local bar = CreateFrame("Frame", nil, window)
	bar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	bar:SetSize(WIDTH - margin * 2, TABS - 6)
	local rule = Skin.Rule(bar, false, 0.22)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	local tabs = {}
	for _, page in ipairs(order) do if page.tab then tabs[#tabs + 1] = page end end
	table.sort(tabs, function(a, b) return a.tab < b.tab end)
	bar.buttons = {}
	local width = (WIDTH - margin * 2) / #tabs
	for index, page in ipairs(tabs) do
		local button = CreateFrame("Button", nil, bar)
		button:SetPoint("TOPLEFT", bar, "TOPLEFT", (index - 1) * width, 0)
		button:SetSize(width, TABS - 6)
		button.page = page
		local hover = button:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.04)
		button.mark = button:CreateTexture(nil, "ARTWORK")
		button.mark:SetPoint("TOPLEFT", button, "TOPLEFT", 10, 0)
		button.mark:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, 0)
		button.mark:SetHeight(2)
		button.mark:SetColorTexture(1, 0.82, 0, 0.9)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetSize(24, 24)
		button.icon:SetPoint("TOP", button, "TOP", 0, -7)
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.icon:SetTexture(page.icon)
		button.label = Skin.Text(button, "GameFontHighlightSmall", "muted")
		button.label:SetPoint("TOP", button.icon, "BOTTOM", 0, -3)
		button.label:SetJustifyH("CENTER")
		button.label:SetWidth(width - 4)
		if button.label.SetWordWrap then button.label:SetWordWrap(false) end
		button.label:SetText(page.label)
		button.dot = button:CreateTexture(nil, "OVERLAY")
		button.dot:SetSize(10, 10)
		button.dot:SetPoint("CENTER", button.icon, "TOPRIGHT", 0, 0)
		button.dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
		button.dot:Hide()
		button:SetScript("OnClick", function()
			Sound()
			Show(page.key)
		end)
		bar.buttons[index] = button
	end
	window.tabs = bar
end

local function Create()
	window = Skin.CreateWindow("WandererCampfireGame", "MEDIUM")
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 30 }, "campfirePos")
	window:SetSize(WIDTH, HEIGHT)
	local kicker, title, margin = Skin.Header(window, "Wanderer", L.TITLE)
	window.kicker, window.title, window.margin = kicker, title, margin
	-- (a page opened from another: the way back, before its name)
	window.back = Skin.SmallButton(window, "", GoBack, function()
		local from = current and pages[current.back or current.parent or ""]
		return from and from.label or nil
	end, 30)
	window.back:SetWidth(30)
	window.back:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin + 1)
	local arrow = window.back:CreateTexture(nil, "ARTWORK")
	arrow:SetSize(22, 22)
	arrow:SetPoint("CENTER")
	arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	window.back:Hide()
	BuildStrip(margin)
	-- The pages, between the strip and the tabs (a screen: the whole window under the heading).
	for _, page in ipairs(order) do
		local top = margin + HEAD + (page.screen and 0 or STRIP)
		local bottom = margin + (page.screen and 0 or TABS)
		page.frame = CreateFrame("Frame", nil, window)
		page.frame:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -top)
		page.frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, bottom)
		page.frame.width, page.frame.height = WIDTH - margin * 2, HEIGHT - top - bottom
		page.build(page.frame)
		page.frame:Hide()
	end
	BuildTabs(margin)
	current = pages.fire or order[1]
	BuildLight()
	-- Shown: the camp looked at; then every few seconds while it stays shown.
	local since = 0
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.Scale())
		ns.State().unseen = nil
		if ns.HearNames then ns.HearNames(true) end
		ns.Update()
		Draw()
		-- (back after a while: what the camp did meanwhile)
		local recap = ns.WhileAway()
		if recap then ShowAway(recap) elseif away then away:Hide() end
	end)
	window:HookScript("OnHide", function()
		if ns.State().choosing then ns.Kindle() end
		if ns.HearNames then ns.HearNames(false) end
		ns.Snapshot()
	end)
	-- (the fire makes its embers every moment while you look; the counters drawn ten times a second)
	local live = 0
	window:SetScript("OnUpdate", function(_, elapsed)
		live = live + elapsed
		if live >= 0.1 then
			if ns.Lit() then ns.Tick(live) end
			live = 0
			if current and current.key == "fire" and ns.FireLive and ns.Lit() and not light:IsShown() then ns.FireLive() end
			if ns.Lit() and window.strip:IsShown() then Resources() end
		end
		since = since + elapsed
		if since < LOOK_EVERY then return end
		since = 0
		ns.Back(ns.Update()) -- (drawn again there)
		if ns.SaySaid then ns.SaySaid() end
	end)
	Skin.Get(window):Layout()
end

function ns.Toggle()
	if not window then Create() end
	window:SetShown(not window:IsShown())
end

function ns.Open(key, arg)
	if not window then Create() end
	window:Show()
	if key then Show(key, arg) end
end

-- Notices -------------------------------------------------------------------------------------------------

local function PlaceOf(told) return ns.PlaceName(told.area) end

-- Expeditions back while you play: a short notice (an option, on), the window drawn again; its window closed,
-- news waiting (the bar's word pulses until it is opened).
function ns.Back(back)
	if back and back[1] and not (window and window:IsShown()) then ns.State().unseen = true end
	Draw()
	local settings = Settings()
	if not (back and back[1] and settings and settings.notify and W.Toast) then return end
	if #back == 1 then
		local told = back[1]
		W.Toast(L.BACK_TITLE, L.BACK_ONE:format(PlaceOf(told), told.won and L.WON or L.LOST), { duration = 5, corner = true })
	else
		W.Toast(L.BACK_TITLE, L.BACK_MANY:format(#back), { duration = 5, corner = true })
	end
end

function ns.SaySaid()
	for _, said in ipairs(ns.TakeSaid()) do
		if not W.Print then return end
		if said[1] == "champion" then W.Print(L.CHAMPION_JOINED:format(said[2])) end
		if said[1] == "lived" then W.Print(L.LIVED_SAID:format(ns.PlaceName(said[2]))) end
		if said[1] == "feat" then W.Print(L.FEAT_SAID:format(L["FEAT_" .. said[2]:upper()])) end
	end
end

-- Init ----------------------------------------------------------------------------------------------------

BINDING_HEADER_WANDERERCAMPFIREGAME = "Wanderer Campfire Game"
BINDING_NAME_WANDERERCAMPFIREGAME_TOGGLE = L.TITLE
function WandererCampfireGame_Toggle() ns.Toggle() end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	if (W.API or 1) < 6 then return W.Print(L.NEEDS_WANDERER) end
	W.RegisterExtension({
		key = "campfire",
		addon = ADDON,
		title = L.ADDON,
		news = L.NEWS_LINES,
		defaults = { notify = true },
		launcher = { label = L.TITLE, open = function() ns.Toggle() end, attention = function() return ns.Attention() end },
		options = function(o)
			o.Header(L.ADDON)
			o.Button(L.TITLE, L.OPEN, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end)
			o.Checkbox("campfire", "notify", L.NOTIFY, L.NOTIFY_DESC)
		end,
	})
	SLASH_WANDERERCAMPFIREGAME1 = "/wcampfire"
	SLASH_WANDERERCAMPFIREGAME2 = "/wcamp"
	SlashCmdList.WANDERERCAMPFIREGAME = function() ns.Toggle() end
	ns.ListenReal()
	-- At login: what came back while you were away, said once; the zones you enter, noted.
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	events:RegisterEvent("PLAYER_LOGOUT")
	events:SetScript("OnEvent", function(_, event)
		if event == "ZONE_CHANGED_NEW_AREA" then return ns.NoteVisit() end
		-- (leaving: the camp as you leave it, for the next "while you were away")
		if event == "PLAYER_LOGOUT" then
			if ns.State().choosing then ns.Kindle() end
			return ns.Snapshot()
		end
		C_Timer.After(5, function()
			ns.Back(ns.Update())
			ns.SaySaid()
		end)
	end)
end

if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
