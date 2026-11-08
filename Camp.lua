local _, ns = ...
local L = ns.L

-- The camp's page, in a list that scrolls: the fire's tier and what it gives, the fireside event (a choice,
-- and what came of it), the trades (a supply at the peddler, renown for a feast), then the ways to the
-- buildings and to what your professions bring (pages of their own), and the week's goals.

local W = Wanderer
local Skin = W and W.Skin

local view = {}
local said -- what the last choice brought, until the next event

-- What came of a choice, in words.
local function Result(told)
	local parts = {}
	local gains = ns.Gains(told, true)
	if gains ~= "" then parts[1] = gains end
	if told.who then parts[#parts + 1] = L.RESULT_XP:format(told.who) end
	if told.xpAll then parts[#parts + 1] = L.RESULT_XP_ALL end
	if told.hurt then parts[#parts + 1] = L.RESULT_HURT:format(told.hurt) end
	if told.joined then parts[#parts + 1] = L.RESULT_JOINED:format(told.joined) end
	if told.healed then parts[#parts + 1] = L.RESULT_HEALED end
	if told.trophy then parts[#parts + 1] = L.RESULT_TROPHY:format(L["TROPHY_" .. told.trophy] .. ", " .. ns.PlaceName(told.area)) end
	return L.RESULT:format(#parts > 0 and table.concat(parts, ", ") or L.RESULT_NOTHING)
end

-- The fireside event: its words, its two answers one above the other; its height.
local function DrawEvent(width)
	local event = view.event
	local key = ns.State().event
	-- (an incident of the road says where it happened)
	local text = key and L["EVENT_" .. key:upper()]
	if text and key:find("^road_") then text = text:format(ns.PlaceName(ns.State().eventArea or 0)) end
	event.text:SetWidth(width - 28)
	event.text:SetText(text or (said or L.EVENT_NONE))
	local height = 14 + math.ceil(event.text:GetStringHeight() or 14) + 12
	event.a:SetShown(key ~= nil)
	event.b:SetShown(key ~= nil)
	if key then
		for _, choice in ipairs({ "a", "b" }) do
			local button = event[choice]
			button:SetText(L["EVENT_" .. key:upper() .. "_" .. choice:upper()])
			button:SetEnabled(ns.CanAnswer(choice))
			button:SetWidth(width - 28)
		end
		event.a:ClearAllPoints()
		event.a:SetPoint("TOPLEFT", event, "TOPLEFT", 14, -height)
		height = height + 34 + 6 + 30 + 14
	end
	return height
end

local function Draw()
	local s, tier = ns.State(), ns.Tier()
	local list = view.list
	list:Begin()
	-- The fire's tier, and what it gives.
	local gives = L.TIER_GIVES:format(ns.MaxCompanions(), tier.slots, tier.party)
	if s.prestige > 0 then gives = gives .. "\n" .. L.PRESTIGE_LINE:format(s.prestige, math.floor(s.prestige * ns.PRESTIGE_BONUS * 100 + 0.5)) end
	if s.ashesTotal > 0 then gives = gives .. "\n" .. ns.Icon("ashes") .. " " .. L.ASH_LINE:format(ns.Number(s.ashesTotal), ns.AshPercent(s.ashesTotal)) end
	list:Row({ icon = "Interface\\Icons\\Spell_Fire_Fire", quality = 1, title = ns.TierName(s.tier), color = Skin.COLORS.gold, sub = gives, wrap = true,
		chip = L.TIER_NUMBER:format(s.tier), tone = "gold" })
	-- The fireside event.
	list:Caption(L.EVENT_TITLE, nil, s.event and "gold" or "muted")
	-- (what the last choice brought: said until the next event)
	if s.event and view.shownEvent ~= s.event then said = nil end
	list:Put(view.event, DrawEvent(list.width))
	if s.event and view.shownEvent ~= s.event then ns.UI.Appear(view.event, 0.4) end
	view.shownEvent = s.event
	-- The trades.
	list:Caption(L.TRADES)
	for _, trade in ipairs({ { "supplies", "Interface\\Icons\\INV_Misc_Coin_02", L.TRADE_PEDDLER }, { "renown", "Interface\\Icons\\INV_Misc_Food_15", L.TRADE_FEAST } }) do
		local kind = trade[1]
		local price, count = ns.TradeCost(kind)
		local can = s.embers >= price
		list:Row({ icon = trade[2], title = trade[3], sub = ns.Gains({ [kind] = count }, true) .. "\n" .. L["TRADE_" .. kind:upper() .. "_DESC"], wrap = true,
			chip = ns.Amount("embers", price), tone = can and "gold" or "red",
			action = { text = L.TRADE, enabled = can, fn = function() if ns.Trade(kind) then ns.Redraw() end end } })
	end
	-- The buildings and your professions: pages of their own.
	list:Caption(L.CAMP_MORE)
	local ready = 0
	for _, building in ipairs(ns.BUILDINGS) do if ns.CanBuild(building.key) then ready = ready + 1 end end
	list:Row({ icon = "Interface\\Icons\\Trade_Engineering", title = L.BUILDINGS, color = Skin.COLORS.gold, sub = L.BUILDINGS_DESC, wrap = true,
		chip = ready > 0 and L.BUILD_READY:format(ready) or nil, tone = "green", onClick = function() ns.ShowPage("buildings") end })
	list:Row({ icon = "Interface\\Icons\\INV_Pick_02", title = L.PROFESSIONS_TITLE, color = Skin.COLORS.gold, sub = L.PROFESSIONS_DESC, wrap = true,
		onClick = function() ns.ShowPage("professions") end })
	-- The week's goals.
	local chip, tone = ns.WeekSummary()
	list:Row({ icon = "Interface\\Icons\\INV_Box_02", title = L.WEEK, color = Skin.COLORS.gold, sub = L.WEEK_DESC, wrap = true,
		chip = chip, tone = tone, onClick = function() ns.ShowPage("week") end })
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
	-- The fireside event, a card of its own.
	local event = Skin.Panel(view.list)
	event.text = Skin.Text(event, "GameTooltipText", "soft")
	event.text:SetPoint("TOPLEFT", event, "TOPLEFT", 14, -14)
	event.text:SetJustifyH("LEFT")
	event.text:SetSpacing(2)
	local function Answer(choice, button)
		local told = ns.Answer(choice)
		if told then said = Result(told) end
		ns.UI.Flash(button)
		ns.Redraw()
	end
	event.a = Skin.Button(event, "", function(self) Answer("a", self) end, "main")
	event.a:SetHeight(34)
	event.b = Skin.Button(event, "", function(self) Answer("b", self) end)
	event.b:SetPoint("TOPLEFT", event.a, "BOTTOMLEFT", 0, -6)
	view.event = event
	event:Hide()
end

ns.AddPage("camp", L.TAB_CAMP, Build, Draw, { tab = 2, icon = "Interface\\Icons\\INV_Misc_Bag_10", live = true,
	badge = function() return ns.State().event ~= nil end })

-- The buildings ----------------------------------------------------------------------------------------------

-- The buildings, as cards two by two: each its icon, name and levels (lit pips), what it does, and what its next
-- level costs (built from there), or why it waits.

local buildings = {}
local CARD = 172

local function NewCard(parent)
	local card = Skin.Panel(parent)
	card:SetHeight(CARD)
	card.glow = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.glow:SetPoint("TOPLEFT")
	card.glow:SetPoint("TOPRIGHT")
	card.glow:SetHeight(64)
	ns.Gradient(card.glow, true, 1, 0.6, 0.2, 0, 1, 0.6, 0.2, 0.1)
	card.icon = Skin.Icon(card, 40)
	card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
	card.name = Skin.CreateText(card, "GameFontNormal")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
	card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
	card.name:SetJustifyH("LEFT")
	if card.name.SetWordWrap then card.name:SetWordWrap(false) end
	card.pips = {}
	for index = 1, ns.BUILDING_MAX do
		local pip = card:CreateTexture(nil, "ARTWORK")
		pip:SetSize(12, 5)
		pip:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", (index - 1) * 15, -7)
		card.pips[index] = pip
	end
	card.desc = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.desc:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -60)
	card.desc:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	card.desc:SetJustifyH("LEFT")
	card.desc:SetSpacing(2)
	card.cost = Skin.Text(card, "GameTooltipTextSmall", "text")
	card.cost:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 46)
	card.cost:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	card.cost:SetJustifyH("LEFT")
	card.button = Skin.Button(card, L.BUILD, function(self)
		if self.key and ns.Build(self.key) then
			ns.UI.Flash(card, 0.3)
			ns.Redraw()
		end
	end, "main", 100)
	card.button:SetHeight(28)
	card.button:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
	card.button:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 10)
	return card
end

local function DrawBuildings()
	local list = buildings.list
	list:Begin()
	list:Text(L.BUILDINGS_DESC, "soft")
	local width = (list.width - 8) / 2
	for at = 1, #ns.BUILDINGS, 2 do
		local index = (at + 1) / 2
		local row = buildings.rows[index]
		if not row then
			row = CreateFrame("Frame", nil, list)
			row.cards = { NewCard(row), NewCard(row) }
			row.cards[1]:SetPoint("TOPLEFT")
			row.cards[2]:SetPoint("TOPRIGHT")
			buildings.rows[index] = row
		end
		for side = 1, 2 do
			local building, card = ns.BUILDINGS[at + side - 1], row.cards[side]
			card:SetShown(building ~= nil)
			if building then
				local key = building.key:upper()
				local level = ns.Level(building.key)
				card:SetWidth(width)
				card.icon:Set(building.icon, level > 0 and 1 or nil)
				card.icon.texture:SetDesaturated(level == 0)
				card.name:SetText(L["BUILDING_" .. key])
				local c = level > 0 and Skin.COLORS.gold or Skin.COLORS.text
				card.name:SetTextColor(c[1], c[2], c[3])
				for step, pip in ipairs(card.pips) do
					if step <= level then pip:SetColorTexture(ns.EMBER[1], ns.EMBER[2], ns.EMBER[3], 0.95) else pip:SetColorTexture(1, 1, 1, 0.1) end
				end
				card.desc:SetText(L["BUILDING_" .. key .. "_DESC"])
				local can, why = ns.CanBuild(building.key)
				card.button.key = building.key
				if why == "top" then
					card.cost:SetText(Skin.Colorize(L.BUILD_TOP, "good"))
					card.button:Hide()
				elseif why == "tier" then
					card.cost:SetText(Skin.Colorize(L.BUILD_TIER, "muted"))
					card.button:Hide()
				else
					local embers, supplies = ns.BuildingCost(building.key)
					card.cost:SetText(ns.Amount("embers", embers) .. "   " .. ns.Amount("supplies", supplies))
					card.button:Show()
					card.button:SetEnabled(can and true or false)
				end
			end
		end
		list:Put(row, CARD, 8)
	end
	list:Done()
end

ns.AddPage("buildings", L.BUILDINGS, function(page)
	buildings.list = ns.UI.List(page)
	buildings.rows = {}
end, DrawBuildings, { parent = "camp", live = true })

-- What your professions bring --------------------------------------------------------------------------------

local professions = {}
local PROFESSION_BONUSES = {
	{ "provisions", "Interface\\Icons\\INV_Misc_Food_15" }, { "power", "Interface\\Icons\\Trade_BlackSmithing" },
	{ "success", "Interface\\Icons\\INV_Misc_Spyglass_03" }, { "injury", "Interface\\Icons\\Trade_Alchemy" },
	{ "recruit", "Interface\\Icons\\INV_Misc_GroupNeedMore" }, { "rewards", "Interface\\Icons\\INV_Misc_Coin_02" },
	{ "duration", "Interface\\Icons\\INV_Misc_Map_01" }, { "trophy", "Interface\\Icons\\INV_Misc_Gem_Pearl_04" },
}

local function DrawProfessions()
	local list = professions.list
	list:Begin()
	list:Text(L.PROFESSIONS_DESC, "soft")
	local any = false
	for _, pair in ipairs(PROFESSION_BONUSES) do
		local kind = pair[1]
		local bonus = ns.ProfessionBonus(kind)
		if bonus > 0 then
			any = true
			list:Row({ icon = pair[2], title = L["PROF_" .. kind:upper()]:format(math.floor(bonus * 100 + 0.5)), height = 44 })
		end
	end
	if not any then list:Text(L.PROFESSIONS_NONE, "muted") end
	list:Caption(L.REAL_TITLE)
	list:Text(L.REAL_INFO, "soft")
	list:Done()
end

ns.AddPage("professions", L.PROFESSIONS_TITLE, function(page) professions.list = ns.UI.List(page) end, DrawProfessions, { parent = "camp" })
