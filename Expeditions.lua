local _, ns = ...
local L = ns.L

-- The expeditions' page, in a list that scrolls: those on the road (opening the road's page), then every
-- place, zones then dungeons then raids (a closed one faded, with what opens it), each opening its own page.
-- A place's page: how long, who goes (a click takes a companion along or leaves them), the odds, the
-- provisions, what it should bring, and the way out.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view, setup = {}, {}
local minutes -- the duration chosen
local party = {} -- companion id -> true

local function Key(place) return place.kind .. ":" .. place.area end

-- A kind of place, by its icon: a zone (a map), a dungeon (a key), a raid (a dragon's head).
local KIND_ICONS = { zone = "Interface\\Icons\\INV_Misc_Map_01", dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01" }
function ns.KindIcon(kind) return KIND_ICONS[kind] or KIND_ICONS.zone end
local function Find(key)
	for _, place in ipairs(ns.Places()) do if Key(place) == key then return place end end
end

local function Members()
	local list = {}
	for _, companion in ipairs(ns.State().companions) do
		if party[companion.id] then list[#list + 1] = companion end
	end
	return list
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	-- On the road.
	local running = #s.expeditions
	list:Row({ icon = "Interface\\Icons\\INV_Misc_Map_01", title = L.TAB_ROAD, color = Skin.COLORS.gold,
		sub = running > 0 and L.ROAD_COUNT:format(running, ns.Tier().slots) or L.RUNNING_EMPTY, onClick = function() ns.ShowPage("road") end })
	-- Every place.
	local rows = ns.PlaceRows(function(place) return place end)
	for _, place in ipairs(rows) do
		if place.header then
			list:Caption(place.header)
		else
			local lived = (s.lived[place.area] or 0) > 0
			local why = not place.open and (place.why == "level" and L.WHY_LEVEL:format(place.kind == "raid" and 60 or place.low)
				or place.why and L["WHY_" .. place.why:upper()]) or nil
			list:Row({ icon = ns.KindIcon(place.kind), grey = not place.open, title = ns.PlaceName(place.area) .. (lived and ("  " .. U.Colorize(L.LIVED_MARK, 1, 0.82, 0)) or ""),
				color = place.open and Skin.COLORS.text or Skin.COLORS.muted, height = 44,
				sub = why or L.LEVELS:format(place.low, place.high), dim = not place.open,
				tip = { ns.PlaceName(place.area), L.LEVELS:format(place.low, place.high), why or (lived and L.LIVED:format()) or nil },
				onClick = function() ns.ShowPage("expedition", Key(place)) end })
		end
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("expeditions", L.TAB_EXPEDITIONS, Build, Draw, { tab = 4, icon = "Interface\\Icons\\INV_Misc_Map_01",
	badge = function()
		for _, expedition in ipairs(ns.State().expeditions) do if expedition.finish <= time() then return true end end
		return false
	end })

-- A place's own page --------------------------------------------------------------------------------------

local function DrawSetup(key)
	local place = Find(key)
	if not place then return ns.GoBack() end
	local s = ns.State()
	local list = setup.list
	list:Begin()
	list:Row({ icon = ns.KindIcon(place.kind), title = ns.PlaceName(place.area), color = Skin.COLORS.gold, sub = L.LEVELS:format(place.low, place.high),
		chip = ns.KindName(place.kind), tone = "grey", height = 48 })
	if not place.open then
		list:Text(place.why == "level" and L.WHY_LEVEL:format(place.kind == "raid" and 60 or place.low) or place.why and L["WHY_" .. place.why:upper()] or "", "bad")
	end
	-- How long.
	local lengths = ns.DURATIONS[place.kind]
	local known = false
	for _, length in ipairs(lengths) do if length == minutes then known = true end end
	if not known then minutes = lengths[1] end
	list:Caption(L.DURATION)
	local bar = setup.choices[place.kind]
	bar:Select(minutes)
	list:Put(bar, 30, 4, true)
	-- Who goes.
	local free = {}
	for _, companion in ipairs(s.companions) do
		if ns.Free(companion) then free[#free + 1] = companion else party[companion.id] = nil end
	end
	local members = Members()
	list:Caption(L.PARTY, L.PARTY_COUNT:format(#members, ns.Tier().party))
	if #free == 0 then list:Text(L.PARTY_NONE, "muted") end
	for _, companion in ipairs(free) do
		local taken = party[companion.id] == true
		local function Toggle()
			party[companion.id] = not party[companion.id] or nil
			ns.Redraw()
		end
		list:Row(ns.CompanionRow(companion, { chosen = taken, plain = true, onClick = Toggle,
			action = { text = taken and L.LEAVE or L.TAKE, fn = Toggle } }))
	end
	list:Text(L.PARTY_TIP, "muted")
	-- What it should bring.
	local cost = ns.Provisions(place, minutes, members)
	local rewards = ns.Rewards(place, minutes, members)
	local lines = { U.Colorize(L.CHANCE:format(math.floor(ns.Chance(place, minutes, members) * 100 + 0.5)), 0.56, 0.88, 0.64),
		ns.Icon("provisions") .. " " .. L.COST:format(ns.Number(cost), ns.Number(s.provisions)),
		ns.Gains({ renown = rewards.renown, embers = rewards.embers, supplies = rewards.supplies }, true) }
	local bonds = ns.BondBonus(members)
	if bonds > 0 then lines[#lines + 1] = L.BONDS:format(math.floor(bonds * 100 + 0.5)) end
	if (s.lived[place.area] or 0) > 0 then lines[#lines + 1] = L.LIVED:format() end
	list:Caption(L.OUTLOOK)
	list:Text(table.concat(lines, "\n"), "soft", "GameTooltipText")
	-- The way out.
	local can, why = ns.CanStart(place, minutes, members)
	setup.start:SetEnabled(can)
	setup.why:SetText(not can and (why == "party" and L.CANT_PARTY:format(ns.Tier().party) or L["CANT_" .. why:upper()]) or "")
	list:Done()
end

local function BuildSetup(page)
	-- At the foot, the way out (always in sight).
	setup.start = Skin.Button(page, L.START, function()
		local place = Find(ns.CurrentArg())
		if place and ns.Start(place, minutes, Members()) then
			wipe(party)
			ns.ShowPage("road")
		end
	end, "main", 200)
	setup.start:SetHeight(38)
	setup.start:SetPoint("BOTTOM", page, "BOTTOM", 0, 2)
	setup.why = Skin.Text(page, "GameTooltipTextSmall", "bad")
	setup.why:SetPoint("BOTTOM", setup.start, "TOP", 0, 6)
	setup.why:SetWidth(page.width)
	setup.why:SetJustifyH("CENTER")
	setup.list = ns.UI.List(page, page.width, page.height - 70)
	-- One row of durations for each kind of place.
	setup.choices = {}
	for kind, lengths in pairs(ns.DURATIONS) do
		local choices = {}
		for index, length in ipairs(lengths) do choices[index] = { length, ns.Minutes(length) } end
		local bar = Skin.Choices(setup.list, choices, function(length)
			minutes = length
			ns.Redraw()
		end, 30)
		bar:Hide()
		setup.choices[kind] = bar
	end
end

ns.AddPage("expedition", L.TAB_EXPEDITIONS, BuildSetup, DrawSetup, { parent = "expeditions",
	title = function(key)
		local place = Find(key)
		return place and ns.PlaceName(place.area) or L.TAB_EXPEDITIONS
	end })
