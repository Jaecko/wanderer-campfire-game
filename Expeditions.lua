local _, ns = ...
local L = ns.L

-- The expeditions' page, in a list that scrolls: the map of the roads, those on the road (the road's page), the
-- contracts on the board (their reward, how long they stay), then every place, zones then dungeons then raids
-- (its threats in small; a closed one faded, with what opens it), each opening its own page.
-- A place's page: its picture with its threats (lit when countered), how long (a contract's length is fixed),
-- who goes (the best party in one click; each one's abilities, what they would learn), the odds, the
-- provisions, what it should bring, and the way out.

local W = Wanderer
local Skin = W and W.Skin

local view, setup = {}, {}
local minutes -- the duration chosen
local party = {} -- companion id -> true
local GOLD = Skin.COLORS.gold

local Key = ns.PlaceKey

-- Those on a road: their names; how far they have come (0 to 1); when they come back.
function ns.MemberNames(ids)
	local names = {}
	for _, id in ipairs(ids) do
		local companion = ns.Companion(id)
		if companion then names[#names + 1] = companion.name end
	end
	return table.concat(names, ", ")
end
function ns.Progress(expedition)
	local length = math.max(1, expedition.finish - (expedition.start or expedition.finish))
	return math.min(1, 1 - math.max(0, expedition.finish - time()) / length)
end
function ns.BackWhen(expedition)
	local left = expedition.finish - time()
	return left > 0 and L.BACK_IN:format(ns.Left(left)) or L.BACK_NOW
end

-- The expeditions on the road, the soonest back first, as rows (the face of the one who leads each).
function ns.RunningRows(list)
	local all = {}
	for index, expedition in ipairs(ns.State().expeditions) do all[index] = expedition end
	table.sort(all, function(a, b) return a.finish < b.finish end)
	list:Caption(L.RUNNING, L.ROAD_COUNT:format(#all, ns.Tier().slots))
	if not all[1] then list:Text(L.RUNNING_EMPTY, "muted") end
	for _, expedition in ipairs(all) do
		local leader = ns.Companion(expedition.members[1])
		local names = ns.MemberNames(expedition.members)
		-- (a standing order: said by its chip, set or ended by its button; a contract's road goes once)
		local again = expedition.again == true
		list:Row({ companion = leader, icon = not leader and ns.KindIcon(expedition.kind) or nil, title = ns.PlaceName(expedition.area),
			color = Skin.COLORS.gold, sub = names .. "\n" .. ns.BackWhen(expedition), wrap = true,
			chip = again and L.AGAIN_ON or ns.KindOne(expedition.kind), tone = again and "gold" or "grey",
			bar = ns.Progress(expedition), tip = { ns.PlaceName(expedition.area), names, L.CHANCE:format(math.floor((expedition.chance or 0.5) * 100 + 0.5)) },
			action = not expedition.contract and { text = again and L.AGAIN_STOP or L.AGAIN_SET, tip = again and L.AGAIN_STOP_DESC or L.GO_AGAIN_DESC,
				fn = function()
					ns.SetAgain(expedition, not again)
					ns.Redraw()
				end } or nil })
	end
end

-- A kind of place, by its icon: a zone (a map), a dungeon (a key), a raid (a dragon's head).
local KIND_ICONS = { zone = "Interface\\Icons\\INV_Misc_Map_01", dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01" }
function ns.KindIcon(kind) return KIND_ICONS[kind] or KIND_ICONS.zone end

-- A place by its key ("zone:12"), or a contract's ("contract:id": the place and the contract).
local function Find(key)
	local id = type(key) == "string" and tonumber(key:match("^contract:(%d+)$"))
	local contract = id and ns.Contract(id)
	if id and not contract then return nil end
	if contract then return ns.Place(contract.kind, contract.area), contract end
	for _, place in ipairs(ns.Places()) do if Key(place) == key then return place end end
end
local function ContractKey(contract) return "contract:" .. contract.id end

-- Why a place is closed (its level, the fire's tier, a zone to explore or go to); the mark of a place lived.
local function ClosedWhy(place)
	if place.open then return nil end
	if place.why == "level" then return L.WHY_LEVEL:format(place.kind == "raid" and 60 or place.low) end
	return place.why and L["WHY_" .. place.why:upper()] or nil
end
-- Why a road cannot leave, in words (closed: what opens the place, when it is known).
function ns.CantText(why, place)
	if why == "party" then return L.CANT_PARTY:format(ns.Tier().party) end
	if why == "closed" and place then return ClosedWhy(place) or L.CANT_CLOSED end
	return L["CANT_" .. (why or "closed"):upper()]
end
function ns.LivedMark(area)
	return (ns.State().lived[area] or 0) > 0 and ("  " .. Skin.Colorize(L.LIVED_MARK, "gold")) or ""
end

local function Members()
	local list = {}
	for _, companion in ipairs(ns.State().companions) do
		if party[companion.id] then list[#list + 1] = companion end
	end
	return list
end

-- A threat's words: its name, what it is, who counters it in a party (false: no one).
function ns.ThreatTip(threat, covered)
	local key = threat:upper()
	local tip = { L["THREAT_" .. key], L["THREAT_" .. key .. "_DESC"] }
	if covered then
		tip[#tip + 1] = Skin.Colorize(L.THREAT_COUNTERED:format(covered.companion.name, ns.SpellName(covered.ability.spell)), "good")
	elseif covered == false then
		tip[#tip + 1] = Skin.Colorize(L.THREAT_OPEN, "bad")
	end
	return tip
end
-- A place's threats as small icons within a text.
function ns.ThreatIcons(place, size)
	local parts = {}
	for _, threat in ipairs(ns.Threats(place)) do parts[#parts + 1] = ns.InlineIcon(ns.THREAT[threat].icon, size) end
	return table.concat(parts, " ")
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	ns.Tip(list, "expeditions")
	-- The map, and those on the road.
	local running = #s.expeditions
	list:Row({ icon = "Interface\\Icons\\INV_Misc_Map02", title = L.MAP_TITLE, color = GOLD, sub = L.MAP_DESC, wrap = true,
		onClick = function() ns.ShowPage("map") end })
	list:Row({ icon = "Interface\\Icons\\INV_Misc_Map_01", title = L.TAB_ROAD, color = GOLD,
		sub = running > 0 and L.ROAD_COUNT:format(running, ns.Tier().slots) or L.RUNNING_EMPTY, onClick = function() ns.ShowPage("road") end })
	-- The contracts on the board.
	local contracts = ns.Contracts()
	-- (when new ones come: once a place is open)
	local left = ns.ContractsLeft()
	list:Caption(L.CONTRACTS, left > 0 and L.CONTRACTS_NEW:format(ns.Left(left)) or nil)
	if not contracts[1] and left == 0 then list:Text(L.CONTRACTS_NONE, "muted") end
	for _, contract in ipairs(contracts) do
		local reward = ns.CONTRACT_REWARD[contract.reward]
		local place = ns.Place(contract.kind, contract.area)
		list:Row({ icon = reward.icon, quality = 4, title = ns.PlaceName(contract.area), color = GOLD,
			sub = ns.ContractName(contract.reward) .. "\n" .. ns.KindOne(contract.kind) .. ", " .. ns.Minutes(contract.minutes)
				.. (place and ("   " .. ns.ThreatIcons(place)) or ""), wrap = true,
			tip = { ns.ContractName(contract.reward), ns.ContractName(contract.reward, true), L.CONTRACT_STAYS },
			onClick = function() ns.ShowPage("expedition", ContractKey(contract)) end })
	end
	-- (seen now: they stay on the board until taken)
	ns.SeeContracts()
	-- Every place.
	local rows = ns.PlaceRows()
	for _, place in ipairs(rows) do
		if place.header then
			list:Caption(place.header)
		else
			local lived = (s.lived[place.area] or 0) > 0
			local why = ClosedWhy(place)
			list:Row({ icon = ns.KindIcon(place.kind), grey = not place.open, title = ns.PlaceName(place.area) .. ns.LivedMark(place.area),
				color = place.open and Skin.COLORS.text or Skin.COLORS.muted, height = 44,
				sub = why or (L.LEVELS:format(place.low, place.high) .. "   " .. ns.ThreatIcons(place, 13)), dim = not place.open,
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
		return ns.BackWaiting()
	end })

-- A place's own page --------------------------------------------------------------------------------------

-- The threats over the picture: lit when someone of the party counters them.
local function DrawThreats(place, members)
	local covered = ns.Coverage(place, members)
	local threats = ns.Threats(place)
	for index, threat in ipairs(threats) do
		local square = setup.threats[index]
		if not square then
			square = Skin.Icon(setup.banner, 28)
			square:EnableMouse(true)
			Skin.Tooltip(square, function(self) return self.tip end)
			setup.threats[index] = square
		end
		square:ClearAllPoints()
		square:SetPoint("TOPRIGHT", setup.banner, "TOPRIGHT", -10 - (#threats - index) * 32, -10)
		square:Set(ns.THREAT[threat].icon)
		local by = covered[threat]
		square.texture:SetDesaturated(not by)
		square.texture:SetAlpha(by and 1 or 0.7)
		if by then square.edges.Color(0.31, 0.78, 0.43, 0.95) else square.edges.Color(Skin.COLORS.bad[1], Skin.COLORS.bad[2], Skin.COLORS.bad[3], 0.7) end
		square.tip = ns.ThreatTip(threat, by or false)
		square:Show()
	end
	for index = #threats + 1, #setup.threats do setup.threats[index]:Hide() end
end

-- A companion's abilities as words, those countering a threat of the place in green.
function ns.AbilityWords(companion, place)
	local wanted = {}
	for _, threat in ipairs(place and ns.Threats(place) or {}) do wanted[threat] = true end
	local parts = {}
	for _, ability in ipairs(ns.AbilitiesOf(companion)) do
		parts[#parts + 1] = Skin.Colorize(ns.InlineIcon(ns.SpellIcon(ability.spell), 13) .. " " .. ns.SpellName(ability.spell),
			wanted[ability.counters] and "good" or "muted")
	end
	return table.concat(parts, "   ")
end

local function DrawSetup(key)
	local place, contract = Find(key)
	if not place then return ns.GoBack() end
	local s = ns.State()
	local list = setup.list
	-- Who goes (those no longer free left out).
	local free = {}
	for _, companion in ipairs(s.companions) do
		if ns.Free(companion) then free[#free + 1] = companion else party[companion.id] = nil end
	end
	local members = Members()
	-- The place, in its picture, its threats over it.
	setup.banner:Set(place.area)
	setup.kind:Set(contract and L.CONTRACT or ns.KindOne(place.kind), contract and "gold" or "grey")
	setup.place:SetText(ns.PlaceName(place.area) .. ns.LivedMark(place.area))
	setup.levels:SetText(L.LEVELS:format(place.low, place.high))
	DrawThreats(place, members)
	list:Begin()
	ns.Tip(list, "threats")
	-- A contract: its reward.
	if contract then
		local reward = ns.CONTRACT_REWARD[contract.reward]
		list:Row({ icon = reward.icon, quality = 4, title = ns.ContractName(contract.reward), color = GOLD,
			sub = ns.ContractName(contract.reward, true), wrap = true })
	end
	-- How long (a contract's: fixed).
	list:Caption(L.DURATION, contract and ns.Minutes(contract.minutes) or nil)
	if contract then
		minutes = contract.minutes
	else
		local lengths = ns.DURATIONS[place.kind]
		local known = false
		for _, length in ipairs(lengths) do if length == minutes then known = true end end
		if not known then minutes = lengths[1] end
		local bar = setup.choices[place.kind]
		bar:Select(minutes)
		list:Put(bar, 30, 4, true)
	end
	-- Who goes: the best party in one click, then each one.
	list:Caption(L.PARTY, L.PARTY_COUNT:format(#members, ns.Tier().party))
	if #free == 0 then
		list:Text(L.PARTY_NONE, "muted")
	else
		list:Put(setup.best, 28, 8)
	end
	local double = contract and contract.reward == "xp" and 2 or 1
	for _, companion in ipairs(free) do
		local taken = party[companion.id] == true
		local function Toggle()
			party[companion.id] = not party[companion.id] or nil
			ns.Redraw()
		end
		-- (what they would learn there, won: the levels, else a share of the next one)
		local with = members
		if not taken then
			with = { companion }
			for _, member in ipairs(members) do with[#with + 1] = member end
		end
		local level, xp = ns.LevelAfter(companion, ns.ExpeditionXP(companion, place, minutes, with, true) * double)
		local preview
		if companion.level >= ns.LevelCap() then
			preview = L.XP_PREVIEW_TOP
		elseif level > companion.level then
			preview = L.XP_PREVIEW_LEVELS:format(level - companion.level)
		else
			preview = L.XP_PREVIEW_SHARE:format(math.floor((xp - (companion.xp or 0)) / math.max(1, ns.XPNeed(companion.level)) * 100 + 0.5))
		end
		list:Row(ns.CompanionRow(companion, { chosen = taken, plain = true, onClick = Toggle, chip = preview, tone = "gold", wrap = true,
			sub = ns.RoleText(companion.role, 13) .. " " .. L["ROLE_" .. companion.role:upper()] .. ", " .. L.LEVEL_SHORT:format(companion.level)
				.. ", " .. L.POWER_SHORT:format(math.floor(ns.Power(companion, place, minutes) + 0.5)) .. "\n" .. ns.AbilityWords(companion, place),
			tip = { companion.name, L.XP_PREVIEW_DESC },
			action = { text = taken and L.LEAVE or L.TAKE, fn = Toggle } }))
	end
	list:Text(L.PARTY_TIP, "muted")
	-- What it should bring.
	local cost = ns.Provisions(place, minutes, members)
	local rewards = ns.Rewards(place, minutes, members)
	local lines = { Skin.Colorize(L.CHANCE:format(math.floor(ns.Chance(place, minutes, members) * 100 + 0.5)), "good"),
		ns.Icon("provisions") .. " " .. L.COST:format(ns.Number(cost), ns.Number(s.provisions)),
		ns.Gains({ renown = rewards.renown, embers = rewards.embers, supplies = rewards.supplies }, true) }
	local _, countered, open = ns.Coverage(place, members)
	lines[#lines + 1] = L.THREATS_LINE:format(countered, countered + open)
	local _, leader = ns.PartyPower(place, minutes, members)
	if leader then lines[#lines + 1] = Skin.Colorize(L.LEADER:format(leader.name), "gold") end
	local bonds = ns.BondBonus(members)
	if bonds > 0 then lines[#lines + 1] = L.BONDS:format(math.floor(bonds * 100 + 0.5)) end
	if (s.lived[place.area] or 0) > 0 then lines[#lines + 1] = L.LIVED:format() end
	if ns.Rest() > 0 then lines[#lines + 1] = Skin.Colorize(L.REST_LINE:format(math.floor(ns.REST_XP * 100 + 0.5), ns.Minutes(ns.Rest())), "blue") end
	list:Caption(L.OUTLOOK)
	list:Text(table.concat(lines, "\n"), "soft", "GameTooltipText")
	-- (a standing order: the party sets out again on each return; a contract's road goes once)
	if not contract then
		setup.again:Refresh()
		list:Put(setup.again, 20, 8, true)
	end
	-- The way out.
	local can, why = ns.CanStart(place, minutes, members)
	setup.start:SetEnabled(can)
	setup.why:SetText(not can and ns.CantText(why, place) or "")
	list:Done()
end

local function BuildSetup(page)
	-- At the foot, the way out (always in sight).
	setup.start = Skin.Button(page, L.START, function()
		local place, contract = Find(ns.CurrentArg())
		if place and ns.Start(place, minutes, Members(), contract, not contract and ns.State().goAgain) then
			wipe(party)
			-- (the road's way back leads to the page this road was chosen from, not to this road gone)
			ns.GoBack()
			ns.ShowPage("road")
		end
	end, "main", 200)
	setup.start:SetHeight(38)
	setup.start:SetPoint("BOTTOM", page, "BOTTOM", 0, 2)
	setup.why = Skin.Text(page, "GameTooltipTextSmall", "bad")
	setup.why:SetPoint("BOTTOM", setup.start, "TOP", 0, 6)
	setup.why:SetWidth(page.width)
	setup.why:SetJustifyH("CENTER")
	-- At the top, the place in its picture.
	setup.banner = ns.Banner(page, page.width, 112)
	setup.banner:SetPoint("TOPLEFT")
	setup.kind = Skin.Chip(setup.banner)
	setup.kind:SetPoint("TOPLEFT", setup.banner, "TOPLEFT", 10, -10)
	setup.place = Skin.CreateText(setup.banner, "GameFontNormalLarge")
	setup.place:SetPoint("BOTTOMLEFT", setup.banner, "BOTTOMLEFT", 14, 28)
	setup.place:SetPoint("RIGHT", setup.banner, "RIGHT", -14, 0)
	setup.place:SetJustifyH("LEFT")
	setup.place:SetTextColor(1, 0.92, 0.75)
	setup.levels = Skin.Text(setup.banner, "GameTooltipTextSmall", "soft")
	setup.levels:SetPoint("TOPLEFT", setup.place, "BOTTOMLEFT", 0, -4)
	setup.threats = {}
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -120)
	holder.width, holder.height = page.width, page.height - 70 - 120
	holder:SetSize(holder.width, holder.height)
	setup.list = ns.UI.List(holder)
	page.list = setup.list
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
	-- The best party: for the odds, for the experience; or no one.
	local best = CreateFrame("Frame", nil, setup.list)
	local function Choose(goal)
		local place = Find(ns.CurrentArg())
		if not place then return end
		wipe(party)
		for _, companion in ipairs(ns.BestParty(place, minutes, goal)) do party[companion.id] = true end
		ns.Redraw()
	end
	best.odds = Skin.SmallButton(best, L.BEST_ODDS, function() Choose("odds") end, L.BEST_ODDS_DESC, 26)
	best.odds:SetPoint("LEFT")
	best.xp = Skin.SmallButton(best, L.BEST_XP, function() Choose("xp") end, L.BEST_XP_DESC, 26)
	best.xp:SetPoint("LEFT", best.odds, "RIGHT", 8, 0)
	best.clear = Skin.SmallButton(best, L.PARTY_CLEAR, function()
		wipe(party)
		ns.Redraw()
	end, nil, 26)
	best.clear:SetPoint("RIGHT")
	setup.best = best
	best:Hide()
	-- The standing order, remembered for the next roads (this character's).
	setup.again = Skin.Check(setup.list, L.GO_AGAIN, function() return ns.State().goAgain end,
		function(on) ns.State().goAgain = on or nil end, L.GO_AGAIN_DESC)
	setup.again:Hide()
end

ns.AddPage("expedition", L.TAB_EXPEDITIONS, BuildSetup, DrawSetup, { parent = "expeditions",
	title = function(key)
		local place = Find(key)
		return place and ns.PlaceName(place.area) or L.TAB_EXPEDITIONS
	end })
