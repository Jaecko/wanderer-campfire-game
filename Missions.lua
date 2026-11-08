local _, ns = ...

-- The rules of the missions, as those of the followers: the threats of each place and the abilities that counter
-- them, the companions' rarity and their promotion, the best party for a road, the contracts on the board, the
-- week's goals and their chest, the armory where the pieces no better than those worn (and those replaced) wait.

local W = Wanderer
local L = ns.L
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local floor, min, max = math.floor, math.min, math.max
local WEEK = 7 * 86400
local Now = ns.Now

-- A draw that is the same each time for a seed: one of a pool, taken out of it (the seed carried on).
local function Draw(seed, pool)
	seed = seed * 16807 % 2147483647
	return seed, table.remove(pool, seed % #pool + 1)
end

-- Spells (the abilities): their names and icons, the game's own.
function ns.SpellName(id)
	local api = C_Spell and C_Spell.GetSpellName
	local name = api and Clean(Safe(api, id))
	if not name and GetSpellInfo then name = Clean((Safe(GetSpellInfo, id))) end
	return name or ("#" .. id)
end
function ns.SpellIcon(id)
	local api = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
	return api and Clean(Safe(api, id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Rarity --------------------------------------------------------------------------------------------------------

function ns.Rarity(companion) return ns.RARITY[companion.rarity or 2] or ns.RARITY[2] end

-- A recruit's rarity: mostly uncommon; your tailors and leatherworkers make rarer ones come.
function ns.RollRarity()
	local luck = 1 + ns.ProfessionBonus("recruit") * 2
	local roll = math.random()
	if roll < ns.RARITY_ODDS.epic * luck then return 4 end
	if roll < (ns.RARITY_ODDS.epic + ns.RARITY_ODDS.rare) * luck then return 3 end
	return 2
end

-- Its abilities: as many of its class's as its rarity allows (drawn once).
function ns.GiveAbilities(companion)
	local list = ns.ABILITIES[companion.class] or {}
	local count = min(#list, ns.Rarity(companion).abilities)
	local order = {}
	for index = 1, #list do order[index] = index end
	for index = #order, 2, -1 do
		local other = math.random(index)
		order[index], order[other] = order[other], order[index]
	end
	companion.abilities = {}
	for index = 1, count do companion.abilities[index] = order[index] end
	table.sort(companion.abilities)
end

function ns.AbilitiesOf(companion)
	local list, out = ns.ABILITIES[companion.class] or {}, {}
	for _, index in ipairs(companion.abilities or {}) do
		if list[index] then out[#out + 1] = list[index] end
	end
	return out
end

-- Promotion: the next rarity, whether its time has come (and why not).
function ns.NextRarity(companion)
	local rank = (companion.rarity or 2) + 1
	return ns.PROMOTE[rank] and rank or nil
end
function ns.CanPromote(companion)
	local rank = ns.NextRarity(companion)
	if not rank then return false, "top" end
	local rule = ns.PROMOTE[rank]
	if companion.level < rule.level then return false, "level" end
	if ((companion.record or {}).expeditions or 0) < rule.roads then return false, "roads" end
	local s = ns.State()
	if s.renown < rule.renown then return false, "renown" end
	if s.supplies < rule.supplies then return false, "supplies" end
	return true
end
function ns.Promote(companion)
	if not ns.CanPromote(companion) then return false end
	local rank = ns.NextRarity(companion)
	local rule, s = ns.PROMOTE[rank], ns.State()
	s.renown, s.supplies = s.renown - rule.renown, s.supplies - rule.supplies
	companion.rarity = rank
	-- (one more ability, the others kept)
	local list = ns.ABILITIES[companion.class] or {}
	local known = {}
	for _, index in ipairs(companion.abilities or {}) do known[index] = true end
	for index = 1, #list do
		if not known[index] and #companion.abilities < ns.Rarity(companion).abilities then
			companion.abilities[#companion.abilities + 1] = index
			known[index] = true
		end
	end
	table.sort(companion.abilities)
	return true
end

-- Threats ---------------------------------------------------------------------------------------------------------

-- A place's threats: always the same for it (drawn from its area).
local threatsOf = {}
function ns.Threats(place)
	local key = ns.PlaceKey(place)
	if threatsOf[key] then return threatsOf[key] end
	local seed = ns.Seed(key)
	local pool = {}
	for index, threat in ipairs(ns.THREATS) do pool[index] = threat.key end
	local list = {}
	for index = 1, min(#pool, ns.THREAT_COUNT[place.kind] or 2) do seed, list[index] = Draw(seed, pool) end
	threatsOf[key] = list
	return list
end

-- Who counters each threat of a place in a party: threat -> { companion, ability }; how many are countered.
function ns.Coverage(place, members)
	local covered, count = {}, 0
	local threats = ns.Threats(place)
	for _, threat in ipairs(threats) do
		for _, companion in ipairs(members) do
			if not covered[threat] then
				for _, ability in ipairs(ns.AbilitiesOf(companion)) do
					if ability.counters == threat and not covered[threat] then
						covered[threat] = { companion = companion, ability = ability }
						count = count + 1
					end
				end
			end
		end
	end
	return covered, count, #threats - count
end

function ns.ThreatBonus(place, members)
	local _, covered, open = ns.Coverage(place, members)
	return covered * ns.THREAT_COVERED - open * ns.THREAT_OPEN
end

-- The best party ------------------------------------------------------------------------------------------------

-- The free companions who make the best party for a road: the best odds, or the most experience (each one's share
-- of their next level, as likely as the road is won). Built one by one, the one who adds most each time.
function ns.BestParty(place, minutes, goal)
	local free = {}
	for _, companion in ipairs(ns.State().companions) do
		if ns.Free(companion) then free[#free + 1] = companion end
	end
	local room = ns.Tier().party
	local wanted = ns.PARTY[place.kind] and min(room, ns.PARTY[place.kind]) or 1
	local provisions = ns.State().provisions
	local function Score(members)
		if provisions < ns.Provisions(place, minutes, members) then return nil end
		local chance = ns.Chance(place, minutes, members)
		if goal ~= "xp" then return chance - #members * 0.001 end
		local learned = 0
		for _, companion in ipairs(members) do
			if companion.level < ns.LevelCap() then
				learned = learned + ns.ExpeditionXP(companion, place, minutes, members, true) / max(1, ns.XPNeed(companion.level))
			end
		end
		return learned * chance
	end
	local chosen, best = {}, -math.huge
	while #chosen < room do
		local pick, score
		for index, companion in ipairs(free) do
			chosen[#chosen + 1] = companion
			local value = Score(chosen)
			chosen[#chosen] = nil
			if value and (not score or value > score) then pick, score = index, value end
		end
		if not pick then break end
		-- (more only while it helps, but a dungeon or a raid filled first)
		if score <= best and #chosen >= wanted then break end
		chosen[#chosen + 1] = table.remove(free, pick)
		best = max(best, score)
	end
	return chosen
end

-- Contracts -------------------------------------------------------------------------------------------------------

-- The contracts' recruits waiting among the candidates.
local function KeptWaiting()
	local waiting = 0
	for _, each in ipairs(ns.State().candidates or {}) do if each.kept then waiting = waiting + 1 end end
	return waiting
end

-- A new contract at one of the places open not on the board yet (nil: none left).
local function NewContract(open)
	local s = ns.State()
	local on, free = {}, {}
	for _, contract in ipairs(s.contracts) do on[contract.kind .. ":" .. contract.area] = true end
	for _, place in ipairs(open) do if not on[ns.PlaceKey(place)] then free[#free + 1] = place end end
	if not free[1] then return nil end
	local place = free[math.random(#free)]
	local reward = ns.CONTRACT_REWARDS[math.random(#ns.CONTRACT_REWARDS)].key
	-- (a place whose trophies are all found, recruits enough waiting: its renown instead)
	local found = s.trophies[place.area] or {}
	if reward == "trophy" and found[1] and found[2] and found[3] then reward = "renown" end
	if reward == "recruit" and KeptWaiting() >= 2 then reward = "renown" end
	-- (an epic piece: only where epics are found, the places of level 55 and more)
	if reward == "epic" and place.high < 55 then reward = "renown" end
	local contract = { id = s.nextId, kind = place.kind, area = place.area, reward = reward, minutes = ns.CONTRACT_MINUTES[place.kind] or 240 }
	s.nextId = s.nextId + 1
	return contract
end

-- The oldest contract not seen yet on the board (its index), nil when every one has been seen.
local function Unseen()
	for index, contract in ipairs(ns.State().contracts) do if not contract.seen then return index end end
end

-- The board: a few roads among the places open, each with its reward. Full at first; then one more every few
-- hours, in a free seat or in the place of the oldest one not seen yet. A contract seen stays until it is taken.
function ns.Contracts()
	local s = ns.State()
	s.contracts = type(s.contracts) == "table" and s.contracts or {}
	local open = {}
	for _, place in ipairs(ns.Places()) do if place.open then open[#open + 1] = place end end
	-- (no place open yet: the board waits for the first, not six hours)
	if not open[1] then return s.contracts end
	local steps
	if not s.contractsAt then
		steps, s.contractsAt = ns.CONTRACTS, Now()
	else
		steps = floor((Now() - s.contractsAt) / ns.CONTRACT_EVERY)
		-- (a long absence: a few steps, never a whole board of them waiting)
		s.contractsAt = steps > ns.CONTRACTS and Now() or s.contractsAt + steps * ns.CONTRACT_EVERY
		steps = min(ns.CONTRACTS, steps)
	end
	for _ = 1, steps do
		if #s.contracts >= ns.CONTRACTS then
			local index = Unseen()
			if not index then break end
			table.remove(s.contracts, index)
		end
		local contract = NewContract(open)
		if not contract then break end
		s.contracts[#s.contracts + 1] = contract
	end
	return s.contracts
end

-- Until the next contract comes: 0 when it would change nothing (a full board, every contract seen).
function ns.ContractsLeft()
	local s = ns.State()
	if #(s.contracts or {}) >= ns.CONTRACTS and not Unseen() then return 0 end
	return max(0, (s.contractsAt or 0) + ns.CONTRACT_EVERY - Now())
end

-- The contracts on the board marked seen (they stay until taken).
function ns.SeeContracts()
	for _, contract in ipairs(ns.State().contracts or {}) do contract.seen = true end
end

function ns.Contract(id)
	for _, contract in ipairs(ns.Contracts()) do if contract.id == id then return contract end end
end
function ns.DropContract(contract)
	for index, each in ipairs(ns.State().contracts or {}) do
		if each == contract then return table.remove(ns.State().contracts, index) end
	end
end

-- A contract's reward, once its road is won (told: the expedition's tale, given what it brought).
function ns.ContractReward(reward, place, minutes, members, told)
	local s = ns.State()
	if reward == "renown" then
		local more = told.renown * 2
		s.renown = s.renown + more
		told.renown = told.renown + more
	elseif reward == "epic" then
		-- (an epic piece the party can wear, else its renown)
		local found = ns.FindGear(place, minutes, members, { quality = 4, sure = true, strict = true })
		if not found then return ns.ContractReward("renown", place, minutes, members, told) end
		told.gear = told.gear or {}
		for _, piece in ipairs(found) do told.gear[#told.gear + 1] = piece end
	elseif reward == "trophy" then
		-- (one more than the road's own find; the place's trophies all found: its renown instead)
		local trophy = ns.GiveTrophy(place.area)
		if trophy and told.trophy then
			told.trophy2 = trophy
			ns.WeekAdd("trophies")
		elseif trophy then
			told.trophy = trophy
		else
			return ns.ContractReward("renown", place, minutes, members, told)
		end
	elseif reward == "recruit" then
		-- (among the candidates until recruited, through their new draws; two wait at most, then renown instead)
		if KeptWaiting() >= 2 then return ns.ContractReward("renown", place, minutes, members, told) end
		local level = 1
		for _, companion in ipairs(members) do level = max(level, companion.level - 5) end
		local candidate = ns.NewRecruit(level, math.random() < 0.25 and 4 or 3)
		candidate.kept = true
		s.candidates = s.candidates or {}
		table.insert(s.candidates, 1, candidate)
		told.recruit, told.recruitRarity = candidate.name, candidate.rarity
	end
	ns.WeekAdd("contracts")
end

-- The week's goals ------------------------------------------------------------------------------------------------

local function WeekNumber() return floor((Now() - ns.WEEK_START) / WEEK) end
function ns.WeekLeft() return (WeekNumber() + 1) * WEEK + ns.WEEK_START - Now() end

-- Every goal of a week done.
local function Complete(week)
	if type(week) ~= "table" or type(week.goals) ~= "table" then return false end
	for _, goal in ipairs(week.goals) do if (goal.done or 0) < (goal.count or 1) then return false end end
	return true
end

-- This week's: three drawn (the same all week, among those the camp can reach), each with how far it is. A
-- week's chest earned and not opened stays, to open the week after.
function ns.Week()
	local s = ns.State()
	local number = WeekNumber()
	if type(s.week) ~= "table" or s.week.number ~= number then
		if Complete(s.week) and not s.week.claimed then s.weekKept = true end
		-- (only goals the camp can reach: dungeons or raids once one is open to it)
		local open = {}
		for _, place in ipairs(ns.Places()) do if place.open then open[place.kind] = true end end
		local pool = {}
		for _, goal in ipairs(ns.WEEK_GOALS) do
			local reachable = (goal.key ~= "dungeons" or open.dungeon) and (goal.key ~= "raids" or open.raid)
			if reachable then pool[#pool + 1] = goal end
		end
		local seed = ns.Seed("week" .. number)
		local goals = {}
		for index = 1, min(ns.WEEK_PICK, #pool) do
			local goal
			seed, goal = Draw(seed, pool)
			goals[index] = { key = goal.key, count = goal.count, done = 0 }
		end
		s.week = { number = number, goals = goals }
	end
	return s.week
end

function ns.WeekAdd(key, count)
	if not ns.Lit() then return end
	for _, goal in ipairs(ns.Week().goals) do
		if goal.key == key then goal.done = min(goal.count, goal.done + (count or 1)) end
	end
end

-- Its word in a menu: the chest ready, or how many goals are done.
function ns.WeekSummary()
	if ns.WeekReady() then return L.WEEK_READY, "gold" end
	local week, done = ns.Week(), 0
	for _, goal in ipairs(week.goals) do if goal.done >= goal.count then done = done + 1 end end
	return done .. " / " .. #week.goals, week.claimed and "green" or "grey"
end

-- This week's chest to open; a chest to open at all (this week's, or one kept from the week before).
function ns.WeekNowReady()
	local week = ns.Week()
	return not week.claimed and Complete(week)
end
function ns.WeekKept() return ns.State().weekKept == true end
function ns.WeekReady() return ns.WeekNowReady() or ns.WeekKept() end

-- The chest: renown and supplies by the fire's tier, a rare piece for the one it suits best.
function ns.WeekChest()
	local tier = ns.State().tier
	return { renown = 60 * tier, supplies = 5 * tier }
end
-- (kept: the one kept from the week before; not said: this week's when it is ready, else the kept one)
function ns.ClaimWeek(kept)
	local s = ns.State()
	if kept == nil then kept = not ns.WeekNowReady() end
	if kept and not ns.WeekKept() then return nil end
	if not kept and not ns.WeekNowReady() then return nil end
	local chest = ns.WeekChest()
	s.renown, s.supplies = s.renown + chest.renown, s.supplies + chest.supplies
	if kept then s.weekKept = nil else ns.Week().claimed = true end
	local members, level = {}, 1
	for _, companion in ipairs(s.companions) do
		members[#members + 1] = companion
		level = max(level, companion.level)
	end
	chest.gear = members[1] and ns.FindGear({ kind = "dungeon", area = "week", low = max(1, level - 6), high = level }, 60, members, { quality = 3, sure = true })
	return chest
end

-- The armory -------------------------------------------------------------------------------------------------------

function ns.Armory()
	local s = ns.State()
	s.armory = type(s.armory) == "table" and s.armory or {}
	return s.armory
end

-- A piece kept (when the armory keeps them and has room): true.
function ns.Keep(item, area)
	local s = ns.State()
	if not s.keepGear or #ns.Armory() >= ns.ARMORY_MAX then return false end
	table.insert(ns.Armory(), 1, { item = item, area = area })
	return true
end

-- The slot a piece goes in; whether a companion may wear it (its family, its level); what it would add.
function ns.PieceSlot(item)
	local piece = ns.GEAR_ITEM[item]
	if not piece then return nil end
	if piece.family:find("^weapon_") then return "weapon" end
	return piece.family:match("_(%a+)$")
end
function ns.CanWear(companion, item)
	local piece, slot = ns.GEAR_ITEM[item], ns.PieceSlot(item)
	if not (piece and slot) or piece.need > companion.level then return false end
	for _, family in ipairs(ns.Families(companion, slot)) do
		if family == piece.family then return true end
	end
	return false
end
function ns.WearGain(companion, item)
	local worn = ns.GEAR_ITEM[(companion.items or {})[ns.PieceSlot(item)]]
	return ns.GEAR_ITEM[item].level - (worn and worn.level or 0)
end

-- The one a piece suits best (and what it adds), nil when none may wear it.
function ns.BestWearer(item)
	local best, gain
	for _, companion in ipairs(ns.State().companions) do
		if ns.CanWear(companion, item) then
			local value = ns.WearGain(companion, item)
			if not gain or value > gain then best, gain = companion, value end
		end
	end
	return best, gain
end

-- A piece of the armory (as kept there) put on, what was worn going there in its place; one taken apart, for
-- supplies. (The piece itself, not its place: the armory may have changed since it was shown.)
local function IndexOf(kept)
	for index, each in ipairs(ns.Armory()) do if each == kept then return index end end
end
function ns.Equip(kept, companion)
	local index = IndexOf(kept)
	if not (index and ns.CanWear(companion, kept.item)) then return false end
	local old, oldFrom = ns.PutOn(companion, ns.PieceSlot(kept.item), kept.item, kept.area)
	table.remove(ns.Armory(), index)
	if old then table.insert(ns.Armory(), 1, { item = old, area = oldFrom }) end
	return true
end
function ns.Salvage(kept)
	local index = IndexOf(kept)
	if not index then return 0 end
	table.remove(ns.Armory(), index)
	local supplies = ns.SalvageOf(kept.item)
	ns.State().supplies = ns.State().supplies + supplies
	return supplies
end
