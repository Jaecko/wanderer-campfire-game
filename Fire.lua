local _, ns = ...
local L = ns.L

-- The fire's page, the heart of the game: a clicker. At the top, always in sight, the camp at night (the
-- game's art): the embers counting up, what the fire makes a second and what a click brings; a click on the
-- fire stokes it, the gain rising from it; at its foot the fire's tier and the way to the next. Under it, in
-- a list that scrolls, the upgrades within reach (a producer doubled, the click made stronger) and the
-- producers: what each makes, how many you own, what the next one costs, lit when you can buy it. And when
-- this fire has grown enough, the way to a new one (its ashes). Drawn live while the window is shown.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local ART = "Interface\\AddOns\\WandererCampfireGame\\Media\\Camp"
local GLOW = "Interface\\AddOns\\Wanderer\\Media\\MinimapFade"
local SCENE = 256 -- the fire's scene, always shown
local FOOT = 48 -- its foot: the tier
local TILE, TILE_GAP = 40, 6 -- an upgrade's tile
-- The seats around the fire (from its middle: right, up), two by two; all beside the fire one clicks.
local SEATS = { { -118, -14 }, { 118, -14 }, { -148, -32 }, { 148, -32 }, { -104, -40 }, { 104, -40 }, { -160, -4 }, { 160, -4 },
	{ -136, 14 }, { 136, 14 }, { -156, 38 }, { 156, 38 } }
local GOLD, SOFT, GOOD, BAD = Skin.COLORS.gold, Skin.COLORS.soft, Skin.COLORS.good, Skin.COLORS.bad

local view = {}
local Pulse -- (below: a purchase makes the counter swell)

-- (a text, a color, a width, a state given to the game only when it changes: each change makes it draw again)
local Text = ns.Write
local function Tint(region, color)
	if region.wandererTint ~= color then
		region.wandererTint = color
		region:SetTextColor(color[1], color[2], color[3])
	end
end
local function Grey(texture, grey)
	if texture.wandererGrey ~= grey then
		texture.wandererGrey = grey
		texture:SetDesaturated(grey)
	end
end
local tiles, pops, rows = {}, {}, {}

local function Affordable(price) return ns.State().embers >= price end

-- The upgrades --------------------------------------------------------------------------------------------

local function UpgradeName(upgrade)
	if upgrade.key == "ember" then return L.UP_CLICK_EMBER .. (upgrade.rank > 1 and (" " .. ns.Roman(upgrade.rank)) or "") end
	if upgrade.kind == "click" then return L["UP_CLICK_" .. upgrade.key:upper()] end
	return L.UP_RANK:format(L["GEN_" .. upgrade.key:upper()], upgrade.rank)
end

local function UpgradeText(upgrade)
	if upgrade.kind == "rank" then return L.UP_RANK_DESC:format(L["GEN_" .. upgrade.key:upper()]) end
	if upgrade.upgrade.double then return L.UP_CLICK_DOUBLE end
	return L.UP_CLICK_SHARE:format(math.floor(upgrade.upgrade.share * 100 + 0.5))
end

local function Tile(index)
	if tiles[index] then return tiles[index] end
	local tile = CreateFrame("Button", nil, view.tiles)
	tile:SetSize(TILE, TILE)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetPoint("TOPLEFT", 2, -2)
	tile.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	ns.Crop(tile.icon)
	tile.edges = Skin.Edges(tile, GOLD[1], GOLD[2], GOLD[3], 0.8)
	tile:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tile:SetScript("OnClick", function(self)
		if self.upgrade and ns.BuyUpgrade(self.upgrade.id) then
			Skin.Play("click")
			Pulse()
			ns.Redraw()
		end
	end)
	Skin.Tooltip(tile, function(self)
		local upgrade = self.upgrade
		if not upgrade then return nil end
		local can = Affordable(upgrade.price)
		return { UpgradeName(upgrade), { UpgradeText(upgrade), 1, 1, 1 },
			{ L.COST_EMBERS:format(ns.Short(upgrade.price)), (can and GOOD or BAD)[1], (can and GOOD or BAD)[2], (can and GOOD or BAD)[3] } }
	end, "ANCHOR_LEFT")
	tiles[index] = tile
	return tile
end

-- A producer bought (Shift: up to ten, as many as you can pay).
local function Buy(key)
	if not ns.Revealed(key) then return end
	local count = 1
	if IsShiftKeyDown() then
		count = 10
		while count > 1 and ns.GenPrice(key, count) > ns.State().embers do count = count - 1 end
	end
	if ns.BuyGenerator(key, count) then
		Pulse()
		ns.Redraw()
	end
end

-- Drawing -------------------------------------------------------------------------------------------------

local function Why(why, nextTier)
	return why == "level" and L.WHY_LEVEL:format(nextTier.level) or why and L["WHY_" .. why:upper()] or nil
end

-- What may come within reach as the embers grow (an upgrade, the next producer seen, a new fire): drawn again.
local function Reach()
	local s = ns.State()
	return #ns.Upgrades() .. ":" .. tostring((s.run or s.total) >= (view.nextReveal or math.huge)) .. ":" .. tostring(ns.CanRekindle())
end

-- What changes every moment: the counters, what can be bought, how close the next one is.
local function Live()
	if not view.count then return end
	local s = ns.State()
	Text(view.count, ns.Short(s.embers))
	Text(view.rate, L.PER_SECOND:format(ns.Short(ns.PerSecond())))
	-- By a real campfire of the game: everything grows, said in gold.
	local hearth = ns.HearthFactor()
	Text(view.click, L.PER_CLICK:format(ns.Short(ns.ClickPower())) .. (hearth > 1 and ("   " .. Skin.Colorize(L.HEARTH_ON:format(ns.Decimal(hearth, 2)), "gold")) or ""))
	-- (what came within reach as the embers grew: drawn again, once a second)
	if GetTime() - (view.drawn or 0) >= 1 then
		view.drawn = GetTime()
		if view.reach ~= Reach() then return ns.Redraw() end
	end
	for _, row in ipairs(rows) do
		local key = row:IsShown() and row.generator
		if key and ns.Revealed(key) then
			local price = ns.GenPrice(key)
			local can = s.embers >= price
			local chip = ns.Amount("embers", price)
			if row.wandererChip ~= chip .. tostring(can) then
				row.wandererChip = chip .. tostring(can)
				row.chip:Set(chip, can and "gold" or "red")
			end
			Tint(row.title, can and GOLD or SOFT)
			if row.wandererCan ~= can then
				row.wandererCan = can
				row.action:SetEnabled(can)
			end
			Grey(row.icon.texture, not can)
			row.bar:Set(math.min(1, s.embers / price))
		end
	end
	for _, tile in ipairs(tiles) do
		if tile:IsShown() and tile.upgrade then
			local can = s.embers >= tile.upgrade.price
			Grey(tile.icon, not can)
			if tile.wandererCan ~= can then
				tile.wandererCan = can
				tile:SetAlpha(can and 1 or 0.55)
			end
		end
	end
	-- The fire's tier: how close the next is (the eternal blaze has always a next).
	local nextTier = ns.NextTier()
	view.tierLine:Set(math.min(1, s.embers / math.max(1, nextTier.embers)))
	local can, why = ns.CanRaise()
	can = can and true or false
	if view.raise.wandererCan ~= can then
		view.raise.wandererCan = can
		view.raise:SetEnabled(can)
	end
	Text(view.why, not can and (Why(why, nextTier) or "") or "")
end
ns.FireLive = Live

local function DrawList()
	local s = ns.State()
	local list = view.list
	list:Begin()
	wipe(rows)
	-- What waits for a while only (an order, an event by the fire, the week's chest, a talent): one click away.
	local waiting = ns.Waiting()
	if waiting[1] then
		list:Caption(L.WAITING_TITLE)
		for _, item in ipairs(waiting) do
			list:Row({ icon = item.icon, title = item.text, color = Skin.COLORS.gold, height = 40, onClick = function() ns.ShowPage(item.page) end })
		end
	end
	-- A new fire, first when this one can leave ashes.
	local gain = ns.AshesFor()
	local rekindle = { icon = "Interface\\Icons\\Spell_Fire_SelfDestruct", title = L.ASH_TITLE, color = Skin.COLORS.gold, wrap = true,
		sub = gain >= 1 and L.ASH_GAIN:format(ns.Number(gain), ns.AshPercent(gain)) or L.ASH_NOT_YET:format(ns.Short(ns.ASH_UNIT)),
		tip = { L.ASH_TITLE, L.ASH_TEXT, L.ASH_HINT },
		action = { text = L.ASH_REKINDLE, enabled = gain >= 1, fn = function()
			ns.Ask(L.ASH_ASK:format(ns.Number(ns.AshesFor())), function()
				if ns.Rekindle() then ns.ShowPage("ashes") end
			end)
		end } }
	if gain >= 1 then list:Row(rekindle) end
	-- The upgrades within reach.
	local upgrades = ns.Upgrades()
	list:Caption(L.UPGRADES_TITLE, #upgrades > 0 and tostring(#upgrades) or nil)
	if #upgrades == 0 then
		list:Text(L.UPGRADES_NONE, "muted")
	else
		local perRow = math.max(1, math.floor((list.width + TILE_GAP) / (TILE + TILE_GAP)))
		for index, upgrade in ipairs(upgrades) do
			local tile = Tile(index)
			tile.upgrade = upgrade
			tile.icon:SetTexture(upgrade.icon)
			tile:ClearAllPoints()
			local column, line = (index - 1) % perRow, math.floor((index - 1) / perRow)
			tile:SetPoint("TOPLEFT", view.tiles, "TOPLEFT", column * (TILE + TILE_GAP), -line * (TILE + TILE_GAP))
			tile:Show()
		end
		for index = #upgrades + 1, #tiles do tiles[index]:Hide() end
		list:Put(view.tiles, math.ceil(#upgrades / perRow) * (TILE + TILE_GAP) - TILE_GAP, 6)
	end
	-- The producers: the ones you can see, and the next one as a shape.
	list:Caption(L.PRODUCERS_TITLE)
	view.nextReveal = nil
	for _, generator in ipairs(ns.GENERATORS) do
		local key = generator.key
		local revealed = ns.Revealed(key)
		local owned = ns.Owned(key)
		local spec = { icon = generator.icon, shape = not revealed, plain = true, dim = not revealed }
		if revealed then
			spec.title = L["GEN_" .. key:upper()] .. (owned > 0 and ("   " .. U.Colorize("x" .. ns.Number(owned), 0.88, 0.85, 0.77)) or "")
			spec.sub = owned > 0 and L.GEN_TOTAL:format(ns.Short(ns.GenTotal(key)),
				math.floor(ns.GenTotal(key) / math.max(0.0001, ns.PerSecond()) * 100 + 0.5)) or L.GEN_EACH:format(ns.Short(ns.GenEach(key)))
			local price = ns.GenPrice(key)
			local can = Affordable(price)
			spec.chip, spec.tone = ns.Amount("embers", price), can and "gold" or "red"
			spec.bar = math.min(1, s.embers / price)
			spec.tip = { L["GEN_" .. key:upper()], L["GEN_" .. key:upper() .. "_DESC"], L.GEN_EACH:format(ns.Short(ns.GenEach(key))), L.GEN_BUY_HINT }
			spec.action = { text = L.BUY, enabled = can, tip = L.GEN_BUY_HINT, fn = function() Buy(key) end }
		else
			spec.title = UNKNOWN or "?"
		end
		local row = list:Row(spec)
		row.generator = revealed and key or nil
		row.wandererChip, row.wandererCan = nil, nil
		row.title.wandererTint, row.icon.texture.wandererGrey = nil, nil
		rows[#rows + 1] = row
		if not revealed then
			view.nextReveal = generator.cost * ns.REVEAL
			break
		end
	end
	if gain < 1 and (s.ashesTotal > 0 or s.tier >= 3) then list:Row(rekindle) end
	list:Done()
end

local function Draw()
	if not view.count then return end
	local s = ns.State()
	if ns.CanRaise() then s.raiseSeen = s.tier end
	-- The fire's tier.
	view.tier:SetText(U.Upper(ns.TierName(s.tier)) .. "  " .. Skin.Colorize(L.TIER_NUMBER:format(s.tier), "muted"))
	DrawList()
	view.reach = Reach()
	Live()
	-- Those at the camp, around the fire (a new face appears softly; more than the seats: the last says how many).
	local seat, more = 0, 0
	for _, companion in ipairs(s.companions) do
		if not ns.Busy(companion) and seat >= #view.sitters then more = more + 1 end
		if not ns.Busy(companion) and seat < #view.sitters then
			seat = seat + 1
			local sitter = view.sitters[seat]
			local fresh = sitter.companion ~= companion or not sitter:IsShown()
			sitter.companion = companion
			sitter.portrait:Set(companion, { hurt = ns.Hurt(companion) })
			sitter:Show()
			if fresh then ns.UI.Appear(sitter, 0.5) end
		end
	end
	for index = seat + 1, #view.sitters do
		view.sitters[index].companion = nil
		view.sitters[index]:Hide()
	end
	view.sitters[#view.sitters].more = more
end

-- A gain rising from the fire where it was clicked.
local function Rise(x, y, text)
	local pop, oldest
	for _, each in ipairs(pops) do
		if not each.live then pop = each end
		if not oldest or each.age > oldest.age then oldest = each end
	end
	if not pop and #pops >= 12 then pop = oldest end
	if not pop then
		pop = view.fire:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		pop:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		pops[#pops + 1] = pop
	end
	pop.live, pop.age, pop.x, pop.y = true, 0, x, y
	pop:SetText("+" .. text)
	pop:ClearAllPoints()
	pop:SetPoint("CENTER", view.fire, "BOTTOMLEFT", x, y)
	pop:SetAlpha(1)
	pop:Show()
end

-- The scene, while it is seen: the fire breathes slowly (its glow), brighter under the mouse, flaring at
-- each click; the gains rise from it.
local function Animate(_, elapsed)
	view.clock = (view.clock or 0) + elapsed
	for _, pop in ipairs(pops) do
		if pop.live then
			pop.age = pop.age + elapsed
			local t = pop.age / 0.9
			if t >= 1 then
				pop.live = false
				pop:Hide()
			else
				pop:SetPoint("CENTER", view.fire, "BOTTOMLEFT", pop.x, pop.y + 50 * t)
				pop:SetAlpha(1 - t * t)
			end
		end
	end
	view.flare = math.max(0, view.flare - elapsed * 2.2)
	local breath = 0.1 + 0.06 * math.sin(view.clock * 1.4)
	view.glow:SetAlpha(math.min(1, breath + (view.fire:IsMouseOver() and 0.14 or 0) + view.flare * 0.45))
end

-- A purchase: the counter swells a moment.
function Pulse()
	ns.UI.Tween(view.count, 0.35, function(t) view.count:SetScale(1 + 0.12 * (1 - t)) end)
end

-- A new tier: the fire flares, its name rises over the scene and fades.
local function Celebrate()
	view.flare = 1.8
	local burst = view.burst
	burst:SetText(U.Upper(ns.TierName(ns.State().tier)))
	burst:Show()
	ns.UI.Flash(view.art, 0.18)
	ns.UI.Tween(burst, 2.4, function(t)
		burst:SetAlpha(t < 0.2 and t / 0.2 or 1 - (t - 0.2) / 0.8)
		if burst.SetScale then burst:SetScale(0.9 + 0.15 * t) end
	end, function() burst:Hide() end)
end

local function Build(page)
	local width = page.width
	-- The camp at night, the fire in its middle (the picture is square: a band of it, the fire kept).
	local art = CreateFrame("Frame", nil, page)
	art:SetPoint("TOPLEFT")
	art:SetSize(width, SCENE)
	local picture = art:CreateTexture(nil, "BACKGROUND")
	picture:SetAllPoints()
	picture:SetTexture(ART)
	local band = SCENE / width
	local top = math.max(0, 0.58 - band * 0.6)
	picture:SetTexCoord(0, 1, top, math.min(1, top + band))
	for _, side in ipairs({ "TOP", "BOTTOM" }) do
		local shade = art:CreateTexture(nil, "BORDER")
		shade:SetPoint(side .. "LEFT")
		shade:SetPoint(side .. "RIGHT")
		shade:SetHeight(side == "TOP" and 110 or 70)
		local dark = side == "TOP" and 0 or 0.85
		ns.Gradient(shade, true, 0.01, 0.01, 0.03, dark, 0.01, 0.01, 0.03, 0.85 - dark)
	end
	Skin.Edges(art, GOLD[1], GOLD[2], GOLD[3], 0.25)
	-- The counters, over the night sky.
	view.count = art:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	local font = view.count:GetFont()
	view.count:SetFont(font, 34, "OUTLINE")
	view.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	view.count:SetPoint("TOP", art, "TOP", 0, -14)
	view.rate = Skin.Text(art, "GameFontHighlight", "soft")
	view.rate:SetPoint("TOP", view.count, "BOTTOM", 0, -4)
	view.click = Skin.Text(art, "GameTooltipTextSmall", "muted")
	view.click:SetPoint("TOP", view.rate, "BOTTOM", 0, -3)
	-- The fire to stoke: a glow under the mouse, brighter at each click, the gain rising.
	view.fire = CreateFrame("Button", nil, art)
	view.fire:SetSize(180, 120)
	view.fire:SetPoint("CENTER", art, "TOPLEFT", width * 0.47, -(SCENE * 0.6))
	view.fire:RegisterForClicks("LeftButtonDown")
	view.glow = view.fire:CreateTexture(nil, "ARTWORK")
	view.glow:SetPoint("CENTER")
	view.glow:SetSize(240, 200)
	view.glow:SetTexture(GLOW)
	view.glow:SetBlendMode("ADD")
	view.glow:SetVertexColor(1, 0.55, 0.15)
	view.glow:SetAlpha(0)
	view.flare = 0
	Skin.Tooltip(view.fire, L.CLICK_HINT)
	view.fire:SetScript("OnClick", function(self)
		local gain = ns.Click()
		if gain <= 0 then return end
		local x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		Rise(x / scale - (self:GetLeft() or 0), y / scale - (self:GetBottom() or 0), ns.Short(gain))
		view.flare = 1
		Text(view.count, ns.Short(ns.State().embers))
	end)
	art:SetScript("OnUpdate", Animate)
	view.art = art
	-- Those at the camp, sitting around the fire (their faces; hovered, who; clicked, their sheet).
	view.fireX, view.fireY = width * 0.47, SCENE * 0.6
	view.sitters = {}
	for index = 1, #SEATS do
		local seat = CreateFrame("Button", nil, art)
		seat:SetSize(28, 28)
		seat:SetFrameLevel(view.fire:GetFrameLevel() + 2)
		seat.portrait = ns.Portrait(seat, 26, false)
		seat.portrait:SetPoint("CENTER")
		seat:SetPoint("CENTER", art, "TOPLEFT", view.fireX + SEATS[index][1], -(view.fireY - SEATS[index][2]))
		seat:SetScript("OnClick", function(self)
			Skin.Play("click")
			if self.companion then ns.ShowPage("companion", self.companion.id) end
		end)
		Skin.Tooltip(seat, function(self)
			local companion = self.companion
			if not companion then return nil end
			return { companion.name, ns.CompanionKind(companion) .. ", " .. L.LEVEL_SHORT:format(companion.level), ns.Hurt(companion)
				and L.STATE_HURT:format(ns.Left(companion.hurt - time())) or L.STATE_FREE, (self.more or 0) > 0 and L.SEATS_MORE:format(self.more) or nil }
		end)
		seat:Hide()
		view.sitters[index] = seat
	end
	-- (a new tier's name, over the scene)
	view.burst = art:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	view.burst:SetFont(view.count:GetFont(), 26, "OUTLINE")
	view.burst:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	view.burst:SetPoint("CENTER", art, "CENTER", 0, 30)
	view.burst:Hide()
	-- The fire's tier, at its foot: how close the next is, the button to raise it.
	local foot = CreateFrame("Frame", nil, art)
	foot:SetPoint("BOTTOMLEFT")
	foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(FOOT)
	view.raise = Skin.Button(foot, L.RAISE, function()
		if ns.Raise() then
			ns.Redraw()
			Celebrate()
		end
	end, "main", 120)
	view.raise:SetHeight(32)
	view.raise:SetPoint("RIGHT", foot, "RIGHT", -10, 0)
	-- (hovered: what the next tier asks)
	view.raise:SetMotionScriptsWhileDisabled(true)
	Skin.Tooltip(view.raise, function()
		local s, nextTier = ns.State(), ns.NextTier()
		return L.NEXT_TIER:format(ns.TierName(s.tier + 1)) .. "\n" .. L.NEXT_NEEDS:format(nextTier.level, ns.Number(nextTier.renown), ns.Short(nextTier.embers))
	end)
	view.tier = Skin.Text(foot, "GameTooltipTextSmall", "gold")
	view.tier:SetPoint("TOPLEFT", foot, "TOPLEFT", 12, -6)
	view.tier:SetWidth(width - 170)
	view.tier:SetJustifyH("LEFT")
	if view.tier.SetWordWrap then view.tier:SetWordWrap(false) end
	view.tierLine = ns.UI.Bar(foot, 5)
	view.tierLine:SetPoint("TOPLEFT", view.tier, "BOTTOMLEFT", 0, -5)
	view.tierLine:SetWidth(width - 170)
	view.why = Skin.Text(foot, "GameTooltipTextSmall", "bad")
	view.why:SetPoint("TOPLEFT", view.tierLine, "BOTTOMLEFT", 0, -4)
	view.why:SetWidth(width - 170)
	if view.why.SetWordWrap then view.why:SetWordWrap(false) end
	-- (hovered: the reason whole, when it is long)
	local hover = CreateFrame("Frame", nil, foot)
	hover:SetAllPoints(view.why)
	hover:EnableMouse(true)
	Skin.Tooltip(hover, function() local text = view.why:GetText() return text ~= "" and text or nil end)
	-- Under it, what can be bought, in a list that scrolls.
	view.list = ns.UI.List(page, width, page.height - SCENE - 8)
	view.list.scroll:ClearAllPoints()
	view.list.scroll:SetPoint("TOPLEFT", art, "BOTTOMLEFT", 0, -8)
	view.tiles = CreateFrame("Frame", nil, view.list)
end

ns.AddPage("fire", L.TAB_FIRE, Build, Draw, { tab = 1, icon = "Interface\\Icons\\Spell_Fire_Fire",
	badge = function() return ns.CanRaise() and true or false end })
