local _, ns = ...
local L = ns.L

-- The fire's page. On the left the fire: its tier, what it makes and holds, what raising it asks, what your
-- professions bring. On the right the fireside event (a choice, and what came of it), then the buildings.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local LEFT = 360
local view = {}
local said -- what the last choice brought, until the next event

local function Amount(value, cap) return L.AMOUNT_CAP:format(ns.Number(value), ns.Number(cap)) end

-- What came of a choice, in words.
local function Result(told)
	local parts = {}
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		local value = told[key]
		if value and value ~= 0 then parts[#parts + 1] = (value > 0 and "+" or "") .. value .. " " .. L[key:upper()] end
	end
	if told.who then parts[#parts + 1] = L.RESULT_XP:format(told.who) end
	if told.hurt then parts[#parts + 1] = L.RESULT_HURT:format(told.hurt) end
	if told.joined then parts[#parts + 1] = L.RESULT_JOINED:format(told.joined) end
	if told.healed then parts[#parts + 1] = L.RESULT_HEALED end
	if told.trophy then parts[#parts + 1] = L.RESULT_TROPHY:format(L["TROPHY_" .. told.trophy] .. ", " .. ns.PlaceName(told.area)) end
	return L.RESULT:format(#parts > 0 and table.concat(parts, ", ") or L.RESULT_NOTHING)
end

local function DrawBuildings()
	local list = view.buildings
	list:Clamp(#ns.BUILDINGS)
	for index, row in ipairs(list.rows) do
		local building = ns.BUILDINGS[index]
		local entry, values, chip, tone, action
		if building then
			local level = ns.Level(building.key)
			entry = { key = building.key, name = L["BUILDING_" .. building.key:upper()], icon = building.icon, quality = 1,
				tip = { L["BUILDING_" .. building.key:upper()], L["BUILDING_" .. building.key:upper() .. "_DESC"] } }
			values = { level = level .. " / " .. ns.BUILDING_MAX, effect = L["BUILDING_" .. building.key:upper() .. "_DESC"] }
			local can, why = ns.CanBuild(building.key)
			if why == "top" then
				chip, tone = L.BUILD_TOP, "green"
			elseif why == "tier" then
				chip, tone = L.BUILD_TIER, "grey"
			else
				local embers, supplies = ns.BuildingCost(building.key)
				chip, tone = L.BUILD_COST:format(ns.Number(embers), ns.Number(supplies)), can and "gold" or "red"
			end
			if can then action = function() if ns.Build(building.key) then ns.Redraw() end end end
		end
		row:Fill(entry, false, values, chip, tone, action and L.BUILD, action)
	end
end

local function DrawEvent()
	local key = ns.State().event
	-- (an incident of the road says where it happened)
	local text = key and L["EVENT_" .. key:upper()]
	if text and key:find("^road_") then text = text:format(ns.PlaceName(ns.State().eventArea or 0)) end
	view.event.text:SetText(text or (said or L.EVENT_NONE))
	view.event.a:SetShown(key ~= nil)
	view.event.b:SetShown(key ~= nil)
	if key then
		view.event.a:SetText(L["EVENT_" .. key:upper() .. "_A"])
		view.event.a:Fit()
		view.event.b:SetText(L["EVENT_" .. key:upper() .. "_B"])
		view.event.b:Fit()
		view.event.said:SetText(said or "")
	else
		view.event.said:SetText("")
	end
end

local function Draw()
	local s, tier, rates = ns.State(), ns.Tier(), ns.Rates()
	view.name:SetText(L["TIER_" .. s.tier])
	view.tierOf:SetText(L.TIER_OF:format(s.tier, #ns.TIERS))
	view.embers.value:SetText(Amount(s.embers, rates.embersCap) .. "  " .. U.Colorize(L.PER_HOUR:format(ns.Number(rates.embers)), 0.56, 0.53, 0.46))
	view.provisions.value:SetText(Amount(s.provisions, rates.provisionsCap) .. "  " .. U.Colorize(L.PER_HOUR:format(ns.Number(rates.provisions)), 0.56, 0.53, 0.46))
	view.renown.value:SetText(ns.Number(s.renown))
	view.supplies.value:SetText(ns.Number(s.supplies))
	view.gives:SetText(L.TIER_GIVES:format(ns.MaxCompanions(), tier.slots, tier.party)
		.. (s.prestige > 0 and ("\n" .. L.PRESTIGE_LINE:format(s.prestige, math.floor(s.prestige * ns.PRESTIGE_BONUS * 100 + 0.5))) or ""))
	local nextTier = ns.NextTier()
	local can, why = ns.CanRaise()
	if nextTier then
		view.next:SetText(L.NEXT_TIER:format(L["TIER_" .. (s.tier + 1)]) .. "\n" ..
			L.NEXT_NEEDS:format(nextTier.level, ns.Number(nextTier.renown), ns.Number(nextTier.embers)))
		view.why:SetText(not can and (why == "level" and L.WHY_LEVEL:format(nextTier.level) or why == "renown" and L.WHY_RENOWN
			or why == "embers" and L.WHY_EMBERS) or "")
	else
		view.next:SetText(L.TOP_TIER)
		view.why:SetText("")
	end
	view.raise:SetShown(nextTier ~= nil)
	view.raise:SetEnabled(can)
	-- What your professions bring.
	local lines = {}
	for _, kind in ipairs({ "provisions", "power", "success", "injury", "recruit", "rewards", "duration", "trophy" }) do
		local bonus = ns.ProfessionBonus(kind)
		if bonus > 0 then lines[#lines + 1] = L["PROF_" .. kind:upper()]:format(math.floor(bonus * 100 + 0.5)) end
	end
	view.professions:SetText((#lines > 0 and table.concat(lines, "\n") or L.PROFESSIONS_NONE) .. "\n\n" .. L.REAL_INFO)
	DrawEvent()
	DrawBuildings()
end

local function Build(page)
	view.icon = Skin.Icon(page, 44)
	view.icon:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)
	view.icon:Set("Interface\\Icons\\Spell_Fire_Fire", 1)
	view.name = Skin.Text(page, "GameFontNormalLarge", "gold")
	view.name:SetPoint("TOPLEFT", view.icon, "TOPRIGHT", 12, -4)
	view.tierOf = Skin.Text(page, "GameTooltipTextSmall", "muted")
	view.tierOf:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -4)
	-- What the fire makes and holds (hovered: what each is for).
	local anchor = view.icon
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		local line = Skin.SummaryLine(page, anchor, L[key:upper()])
		-- (the left column only)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, key == "embers" and -14 or -8)
		line:SetWidth(LEFT)
		Skin.Tooltip(line, L[key:upper() .. "_DESC"])
		view[key] = line
		anchor = line
	end
	view.gives = Skin.Text(page, "GameTooltipTextSmall", "soft")
	view.gives:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	view.gives:SetWidth(LEFT)
	view.gives:SetJustifyH("LEFT")
	view.next = Skin.Text(page, "GameTooltipText", "label")
	view.next:SetPoint("TOPLEFT", view.gives, "BOTTOMLEFT", 0, -14)
	view.next:SetWidth(LEFT)
	view.next:SetJustifyH("LEFT")
	view.raise = Skin.Button(page, L.RAISE, function() if ns.Raise() then ns.Redraw() end end, "main", 150)
	view.raise:SetHeight(30)
	view.raise:SetPoint("TOPLEFT", view.next, "BOTTOMLEFT", 0, -8)
	view.why = Skin.Text(page, "GameTooltipTextSmall", "bad")
	view.why:SetPoint("LEFT", view.raise, "RIGHT", 10, 0)
	view.why:SetWidth(LEFT - 170)
	view.why:SetJustifyH("LEFT")
	local caption = Skin.Caps(page, L.PROFESSIONS_TITLE)
	caption:SetPoint("TOPLEFT", view.raise, "BOTTOMLEFT", 0, -18)
	view.professions = Skin.Text(page, "GameTooltipTextSmall", "soft")
	view.professions:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
	view.professions:SetWidth(LEFT)
	view.professions:SetJustifyH("LEFT")
	-- On the right: the fireside event.
	local right = LEFT + 30
	local width = page.width - right
	local event = Skin.Panel(page)
	event:SetPoint("TOPLEFT", page, "TOPLEFT", right, 0)
	event:SetSize(width, 150)
	event.caption = Skin.Caps(event, L.EVENT_TITLE, "gold")
	event.caption:SetPoint("TOPLEFT", event, "TOPLEFT", 14, -12)
	event.text = Skin.Text(event, "GameTooltipText", "soft")
	event.text:SetPoint("TOPLEFT", event.caption, "BOTTOMLEFT", 0, -8)
	event.text:SetWidth(width - 28)
	event.text:SetJustifyH("LEFT")
	local function Answer(choice)
		local told = ns.Answer(choice)
		if told then said = Result(told) end
		ns.Redraw()
	end
	event.a = Skin.Button(event, "", function() Answer("a") end, "main")
	event.a:SetPoint("BOTTOMLEFT", event, "BOTTOMLEFT", 14, 12)
	event.b = Skin.Button(event, "", function() Answer("b") end)
	event.b:SetPoint("LEFT", event.a, "RIGHT", 8, 0)
	event.said = Skin.Text(event, "GameTooltipTextSmall", "muted")
	event.said:SetPoint("BOTTOMLEFT", event.a, "TOPLEFT", 0, 6)
	event.said:SetWidth(width - 28)
	event.said:SetJustifyH("LEFT")
	view.event = event
	-- Then the buildings.
	local caption2 = Skin.Caps(page, L.BUILDINGS)
	caption2:SetPoint("TOPLEFT", event, "BOTTOMLEFT", 0, -16)
	view.buildings = Skin.Table(page, {
		width = width, rows = #ns.BUILDINGS, rowHeight = 42, titles = false, action = 90,
		onClick = function() end, onDraw = DrawBuildings,
		columns = { { key = "level", width = 60 }, { key = "effect", width = 190, justify = "LEFT" } },
	})
	view.buildings:SetPoint("TOPLEFT", caption2, "BOTTOMLEFT", 0, -6)
	view.buildings:Fit(#ns.BUILDINGS * 42)
end

ns.AddPage("camp", L.TAB_CAMP, Build, Draw)
