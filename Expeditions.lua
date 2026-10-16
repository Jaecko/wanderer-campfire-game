local _, ns = ...
local L = ns.L

-- The expeditions' page. On the left every place, zones then dungeons then raids (a closed one faded,
-- hovered: what opens it). On the right the place chosen: how long, who goes (a click takes a companion
-- along or leaves them), the odds, the provisions, what it should bring, and the way out.

local W = Wanderer
local Skin = W and W.Skin

local LEFT = 330
local ROWS = 15
local view = {}
local rows = {}
local chosen -- the place chosen
local minutes -- its duration chosen
local party = {} -- companion id -> true

local function Members()
	local list = {}
	for _, companion in ipairs(ns.State().companions) do
		if party[companion.id] then list[#list + 1] = companion end
	end
	return list
end

-- Every place, by kind (a closed one faded; hovered: what opens it).
local function Gather()
	rows = ns.PlaceRows(function(place)
		local why = place.why == "level" and L.WHY_LEVEL:format(place.kind == "raid" and 60 or place.low)
			or place.why and L["WHY_" .. place.why:upper()] or nil
		local lived = (ns.State().lived[place.area] or 0) > 0
		local name = ns.PlaceName(place.area) .. (lived and ("  " .. W.Util.Colorize(L.LIVED_MARK, 1, 0.82, 0)) or "")
		return { place = place, name = name, color = not place.open and Skin.COLORS.muted or nil,
			tip = { ns.PlaceName(place.area), L.LEVELS:format(place.low, place.high), why, lived and L.LIVED or nil } }
	end)
end

local function DrawPlaces()
	local list = view.places
	local offset = list:Clamp(#rows)
	for index, row in ipairs(list.rows) do
		local entry = rows[index + offset]
		local values = entry and entry.place and { levels = entry.place.low .. "-" .. entry.place.high } or nil
		row:Fill(entry, entry ~= nil and chosen ~= nil and entry.place ~= nil and entry.place.area == chosen.area, values)
	end
end

local function DrawParty()
	local list = view.party
	local all = {}
	for _, companion in ipairs(ns.State().companions) do
		if ns.Free(companion) then all[#all + 1] = companion else party[companion.id] = nil end
	end
	local offset = list:Clamp(#all)
	for index, row in ipairs(list.rows) do
		local companion = all[index + offset]
		local entry, values
		if companion then
			entry = ns.CompanionEntry(companion)
			values = { level = companion.level, role = L["ROLE_" .. companion.role:upper()] }
		end
		row:Fill(entry, companion ~= nil and party[companion.id] == true, values, nil, nil,
			companion and (party[companion.id] and L.LEAVE or L.TAKE),
			companion and function()
				party[companion.id] = not party[companion.id] or nil
				ns.Redraw()
			end)
	end
end

local function DrawDetail()
	local shown = chosen ~= nil
	view.detail:SetShown(shown)
	view.pick:SetShown(not shown)
	if not shown then return end
	view.name:SetText(ns.PlaceName(chosen.area))
	view.levels:SetText(L.LEVELS:format(chosen.low, chosen.high))
	local members = Members()
	view.count:SetText(L.PARTY_COUNT:format(#members, ns.Tier().party))
	DrawParty()
	local cost = ns.Provisions(chosen, minutes, members)
	view.chance:SetText(L.CHANCE:format(math.floor(ns.Chance(chosen, minutes, members) * 100 + 0.5)))
	view.cost:SetText(L.COST:format(ns.Number(cost), ns.Number(ns.State().provisions)))
	local rewards = ns.Rewards(chosen, minutes, members)
	local extra = {}
	local bonds = ns.BondBonus(members)
	if bonds > 0 then extra[#extra + 1] = L.BONDS:format(math.floor(bonds * 100 + 0.5)) end
	if (ns.State().lived[chosen.area] or 0) > 0 then extra[#extra + 1] = L.LIVED end
	view.rewards:SetText(L.EXPECTED:format(ns.Number(rewards.renown), ns.Number(rewards.embers))
		.. (extra[1] and ("\n" .. table.concat(extra, "\n")) or ""))
	local can, why = ns.CanStart(chosen, minutes, members)
	view.start:SetEnabled(can)
	view.why:SetText(not can and (why == "party" and L.CANT_PARTY:format(ns.Tier().party) or L["CANT_" .. why:upper()]) or "")
end

local function Choose(entry)
	if not (entry and entry.place) then return end
	chosen = entry.place
	local lengths = ns.DURATIONS[chosen.kind]
	view.durations:Hide()
	view.durations = view.choices[chosen.kind]
	view.durations:Show()
	local known = false
	for _, length in ipairs(lengths) do if length == minutes then known = true end end
	if not known then minutes = lengths[1] end
	view.durations:Select(minutes)
	ns.Redraw()
end

local function Draw()
	Gather()
	-- (the place chosen read again: it may have opened)
	if chosen then
		for _, entry in ipairs(rows) do
			if entry.place and entry.place.area == chosen.area and entry.place.kind == chosen.kind then chosen = entry.place end
		end
	end
	DrawPlaces()
	DrawDetail()
end

local function Build(page)
	view.places = Skin.Table(page, {
		width = LEFT, rows = ROWS + 5, rowHeight = 24, icon = false, titles = false,
		columns = { { key = "levels", width = 56 } }, onClick = Choose, onDraw = DrawPlaces,
	})
	view.places:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	view.places:Fit(page.height)
	local rule = Skin.Rule(page, true, 0.2)
	rule:SetPoint("TOPLEFT", view.places, "TOPRIGHT", 12, 0)
	rule:SetPoint("BOTTOM", page, "BOTTOM", 0, 0)
	local right = LEFT + 26
	local width = page.width - right
	view.pick = Skin.Text(page, "GameTooltipText", "muted")
	view.pick:SetPoint("TOP", page, "TOPLEFT", right + width / 2, -80)
	view.pick:SetText(L.PICK_PLACE)
	local detail = CreateFrame("Frame", nil, page)
	detail:SetPoint("TOPLEFT", page, "TOPLEFT", right, 0)
	detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	view.detail = detail
	view.name = Skin.Text(detail, "GameTooltipHeaderText", "gold")
	view.name:SetPoint("TOPLEFT")
	view.levels = Skin.Text(detail, "GameTooltipTextSmall", "label")
	view.levels:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -4)
	local caption = Skin.Caps(detail, L.DURATION)
	caption:SetPoint("TOPLEFT", view.levels, "BOTTOMLEFT", 0, -14)
	-- One row of durations for each kind of place.
	view.choices = {}
	for kind, lengths in pairs(ns.DURATIONS) do
		local list = {}
		for index, length in ipairs(lengths) do list[index] = { length, ns.Minutes(length) } end
		local bar = Skin.Choices(detail, list, function(length)
			minutes = length
			ns.Redraw()
		end, 28)
		bar:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
		bar:Hide()
		view.choices[kind] = bar
	end
	view.durations = view.choices.zone
	local who = Skin.Caps(detail, L.PARTY)
	who:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -46)
	Skin.Tooltip(who, L.PARTY_TIP)
	view.count = Skin.Text(detail, "GameTooltipTextSmall", "muted")
	view.count:SetPoint("LEFT", who, "RIGHT", 10, 0)
	view.party = Skin.Table(detail, {
		width = width, rows = 8, rowHeight = 26, icon = false, titles = false, action = 90,
		columns = { { key = "level", width = 50 }, { key = "role", width = 110, justify = "LEFT" } },
		onClick = function(entry)
			party[entry.id] = not party[entry.id] or nil
			ns.Redraw()
		end,
		onDraw = DrawParty,
	})
	view.party:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -6)
	view.party:Fit(8 * 26)
	view.chance = Skin.Text(detail, "GameTooltipText", "good")
	view.chance:SetPoint("TOPLEFT", view.party, "BOTTOMLEFT", 0, -12)
	view.cost = Skin.Text(detail, "GameTooltipTextSmall", "soft")
	view.cost:SetPoint("TOPLEFT", view.chance, "BOTTOMLEFT", 0, -6)
	view.rewards = Skin.Text(detail, "GameTooltipTextSmall", "soft")
	view.rewards:SetPoint("TOPLEFT", view.cost, "BOTTOMLEFT", 0, -4)
	view.start = Skin.Button(detail, L.START, function()
		if ns.Start(chosen, minutes, Members()) then
			wipe(party)
			ns.Redraw()
		end
	end, "main", 140)
	view.start:SetHeight(30)
	view.start:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
	view.why = Skin.Text(detail, "GameTooltipTextSmall", "bad")
	view.why:SetPoint("RIGHT", view.start, "LEFT", -12, 0)
	detail:Hide()
end

ns.AddPage("expeditions", L.TAB_EXPEDITIONS, Build, Draw)
