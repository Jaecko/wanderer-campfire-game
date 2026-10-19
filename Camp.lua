local _, ns = ...
local L = ns.L

-- The camp's page, in a list that scrolls: the fire's tier and what it gives, the fireside event (a choice,
-- and what came of it), the trades (a supply at the peddler, renown for a feast), then the ways to the
-- buildings and to what your professions bring (pages of their own).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view = {}
local said -- what the last choice brought, until the next event

-- What came of a choice, in words.
local function Result(told)
	local parts = {}
	local gains = ns.Gains(told, true)
	if gains ~= "" then parts[1] = gains end
	if told.who then parts[#parts + 1] = L.RESULT_XP:format(told.who) end
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
	event.said:SetShown(key ~= nil and said ~= nil)
	if key then
		event.said:SetWidth(width - 28)
		event.said:SetText(said or "")
		if said then height = height + math.ceil(event.said:GetStringHeight() or 14) + 8 end
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
	if s.ashesTotal > 0 then gives = gives .. "\n" .. ns.Icon("ashes") .. " " .. L.ASH_LINE:format(ns.Number(s.ashesTotal), math.floor(s.ashesTotal * ns.ASH_BONUS * 100 + 0.5)) end
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
		list:Row({ icon = trade[2], title = trade[3], sub = ns.Gains({ [kind] = count }, true) .. "\n" .. L["TRADE_" .. kind:upper() .. "_DESC"], wrap = true,
			chip = ns.Amount("embers", price), tone = ns.CanTrade(kind) and "gold" or "red",
			action = { text = L.TRADE, enabled = ns.CanTrade(kind), fn = function() if ns.Trade(kind) then ns.Redraw() end end } })
	end
	-- The buildings and your professions: pages of their own.
	list:Caption(L.CAMP_MORE)
	local ready = 0
	for _, building in ipairs(ns.BUILDINGS) do if ns.CanBuild(building.key) then ready = ready + 1 end end
	list:Row({ icon = "Interface\\Icons\\Trade_Engineering", title = L.BUILDINGS, color = Skin.COLORS.gold, sub = L.BUILDINGS_DESC, wrap = true,
		chip = ready > 0 and L.BUILD_READY:format(ready) or nil, tone = "green", onClick = function() ns.ShowPage("buildings") end })
	list:Row({ icon = "Interface\\Icons\\INV_Pick_02", title = L.PROFESSIONS_TITLE, color = Skin.COLORS.gold, sub = L.PROFESSIONS_DESC, wrap = true,
		onClick = function() ns.ShowPage("professions") end })
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
	event.said = Skin.Text(event, "GameTooltipTextSmall", "muted")
	event.said:SetPoint("TOPLEFT", event.text, "BOTTOMLEFT", 0, -8)
	event.said:SetJustifyH("LEFT")
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

ns.AddPage("camp", L.TAB_CAMP, Build, Draw, { tab = 2, icon = "Interface\\Icons\\INV_Misc_Bag_10",
	badge = function() return ns.State().event ~= nil end })

-- The buildings ----------------------------------------------------------------------------------------------

local buildings = {}

local function DrawBuildings()
	local list = buildings.list
	list:Begin()
	list:Text(L.BUILDINGS_DESC, "soft")
	for _, building in ipairs(ns.BUILDINGS) do
		local key = building.key:upper()
		local level = ns.Level(building.key)
		local spec = { icon = building.icon, quality = 1, title = L["BUILDING_" .. key] .. "   " .. U.Colorize(level .. " / " .. ns.BUILDING_MAX, 0.56, 0.53, 0.46),
			color = level > 0 and Skin.COLORS.gold or Skin.COLORS.text, sub = L["BUILDING_" .. key .. "_DESC"], wrap = true, bar = level / ns.BUILDING_MAX }
		local can, why = ns.CanBuild(building.key)
		if why == "top" then
			spec.chip, spec.tone = L.BUILD_TOP, "green"
		elseif why == "tier" then
			spec.chip, spec.tone = L.BUILD_TIER, "grey"
		else
			local embers, supplies = ns.BuildingCost(building.key)
			spec.chip, spec.tone = ns.Amount("embers", embers) .. "  " .. ns.Amount("supplies", supplies), can and "gold" or "red"
			spec.action = { text = L.BUILD, enabled = can, fn = function() if ns.Build(building.key) then ns.Redraw() end end }
		end
		list:Row(spec)
	end
	list:Done()
end

ns.AddPage("buildings", L.BUILDINGS, function(page) buildings.list = ns.UI.List(page) end, DrawBuildings, { parent = "camp" })

-- What your professions bring --------------------------------------------------------------------------------

local professions = {}
local PROFESSION_ICONS = {
	provisions = "Interface\\Icons\\INV_Misc_Food_15", power = "Interface\\Icons\\Trade_BlackSmithing",
	success = "Interface\\Icons\\INV_Misc_Spyglass_03", injury = "Interface\\Icons\\Trade_Alchemy",
	recruit = "Interface\\Icons\\INV_Misc_GroupNeedMore", rewards = "Interface\\Icons\\INV_Misc_Coin_02",
	duration = "Interface\\Icons\\INV_Misc_Map_01", trophy = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
}

local function DrawProfessions()
	local list = professions.list
	list:Begin()
	list:Text(L.PROFESSIONS_DESC, "soft")
	local any = false
	for _, kind in ipairs({ "provisions", "power", "success", "injury", "recruit", "rewards", "duration", "trophy" }) do
		local bonus = ns.ProfessionBonus(kind)
		if bonus > 0 then
			any = true
			list:Row({ icon = PROFESSION_ICONS[kind], title = L["PROF_" .. kind:upper()]:format(math.floor(bonus * 100 + 0.5)), height = 44 })
		end
	end
	if not any then list:Text(L.PROFESSIONS_NONE, "muted") end
	list:Caption(L.REAL_TITLE)
	list:Text(L.REAL_INFO, "soft")
	list:Done()
end

ns.AddPage("professions", L.PROFESSIONS_TITLE, function(page) professions.list = ns.UI.List(page) end, DrawProfessions, { parent = "camp" })
