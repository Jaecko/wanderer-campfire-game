local _, ns = ...

-- The rules. Nothing runs between two looks: each time the camp is looked at (the window, a returning
-- expedition, the login), the time gone by is counted at once: what the fire made (12 hours at most while you
-- were away), the expeditions back, the hurt healed, a fireside event, the orders, new candidates. One timer
-- only, for the next expedition to come back (its notice).

local W = Wanderer
local U = W and W.Util

local HOUR = 3600
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local function Now() return time() end
local function Pick(list) return list[math.random(#list)] end

-- The camp of this character -----------------------------------------------------------------------------

local state
function ns.State()
	if state then return state end
	WandererCampfireGameDB = type(WandererCampfireGameDB) == "table" and WandererCampfireGameDB or {}
	state = WandererCampfireGameDB
	state.tier = math.max(1, math.min(#ns.TIERS, math.floor(tonumber(state.tier) or 1)))
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		state[key] = math.max(0, tonumber(state[key]) or 0)
	end
	state.buildings = state.buildings or {}
	state.companions = state.companions or {}
	state.nextId = state.nextId or 1
	state.expeditions = state.expeditions or {}
	state.log = state.log or {}
	state.orders = state.orders or {}
	state.trophies = state.trophies or {}
	state.visited = state.visited or {}
	state.champions = state.champions or {}
	state.stats = state.stats or {}
	for _, key in ipairs({ "expeditions", "won", "orders", "dungeons", "raids" }) do state.stats[key] = state.stats[key] or 0 end
	state.bonds = state.bonds or {} -- "id:id" -> expeditions shared
	state.lived = state.lived or {} -- area -> bosses your character killed there
	state.feats = state.feats or {}
	state.prestige = state.prestige or 0
	return state
end

function ns.Lit() return ns.State().lit ~= nil end
function ns.Tier() return ns.TIERS[ns.State().tier] end
function ns.Level(key) return ns.State().buildings[key] or 0 end

-- Bonuses -------------------------------------------------------------------------------------------------

-- What your professions bring (Data.lua's PROFESSIONS), each at its share of its full skill.
local professions, professionsAt = {}, 0
local function Professions()
	if Now() - professionsAt > 60 then professions, professionsAt = ns.Professions(), Now() end
	return professions
end
function ns.ProfessionBonus(kind)
	local total = 0
	for _, profession in pairs(ns.PROFESSIONS) do
		local skill = Professions()[profession.key]
		if skill and profession[kind] then total = total + profession[kind] * min(skill, 300) / 300 end
	end
	return total
end

function ns.TrophyCount()
	local count = 0
	for _, found in pairs(ns.State().trophies) do
		for index = 1, 3 do if found[index] then count = count + 1 end end
	end
	return count
end

-- What the fire makes an hour, what it holds.
function ns.Rates()
	local tier = ns.State().tier
	local store = 1 + 0.5 * ns.Level("store")
	local again = 1 + ns.PRESTIGE_BONUS * ns.State().prestige
	local embers = ns.TIERS[tier].rate * again
	local provisions = ns.PROVISIONS_RATE * tier * (1 + 0.3 * ns.Level("kitchen")) * (1 + ns.ProfessionBonus("provisions")) * again
	return {
		embers = embers, provisions = provisions,
		embersCap = floor(ns.TIERS[tier].cap * store), provisionsCap = floor(ns.PROVISIONS_CAP * tier * store),
	}
end

-- Time going by -------------------------------------------------------------------------------------------

local function Produce(now)
	local s = ns.State()
	local from = s.last or now
	local seconds = min(max(0, now - from), ns.OFFLINE)
	s.last = now
	if seconds <= 0 then return end
	local rates = ns.Rates()
	s.embers = min(rates.embersCap, s.embers + rates.embers * seconds / HOUR)
	s.provisions = min(rates.provisionsCap, s.provisions + rates.provisions * seconds / HOUR)
end

-- Companions ---------------------------------------------------------------------------------------------

function ns.LevelCap() return min(60, max(10, ns.PlayerLevel() + 5)) end
function ns.XPNeed(level) return floor(60 * level ^ 1.6) end

function ns.Companion(id)
	for _, companion in ipairs(ns.State().companions) do
		if companion.id == id then return companion end
	end
end

function ns.MaxCompanions() return ns.Tier().companions + ns.Level("tents") end
local function Count()
	local count = 0
	for _, companion in ipairs(ns.State().companions) do if not companion.champion then count = count + 1 end end
	return count
end
function ns.CompanionCount() return Count() end

function ns.Busy(companion) return companion.busy ~= nil end
function ns.Hurt(companion) return (companion.hurt or 0) > Now() end
function ns.Free(companion) return not ns.Busy(companion) and not ns.Hurt(companion) end

-- What a companion brings for a key: its trait and its talents together.
local function Effect(companion, key)
	local total = (ns.TRAITS[companion.trait] or {})[key] or 0
	for _, talent in ipairs(companion.talents or {}) do total = total + ((ns.TALENT[talent] or {})[key] or 0) end
	return total
end
ns.Effect = Effect
local Trait = Effect

-- What a whole party brings for a key.
local function PartyEffect(members, key)
	local total = 0
	for _, companion in ipairs(members) do total = total + Effect(companion, key) end
	return total
end

-- A companion's strength: its level, the forge, your smiths and miners, its gear, its trait and talents, a
-- champion more.
function ns.Power(companion, place, minutes)
	local power = companion.level * (1 + 0.06 * ns.Level("forge") + ns.ProfessionBonus("power")
		+ ns.GEAR_POWER * (companion.gear or 0) + Effect(companion, "power"))
	if minutes and minutes >= 240 then power = power * (1 + Effect(companion, "longPower")) end
	if place and place.high >= 45 then power = power * (1 + Effect(companion, "hardPower")) end
	if companion.champion then power = power * 1.2 end
	return power
end

-- Talents: the next one a companion may choose (its tier), nil when none waits.
function ns.TalentDue(companion)
	local chosen = #(companion.talents or {})
	local level = ns.TALENT_LEVELS[chosen + 1]
	if level and companion.level >= level and ns.TALENTS[companion.role] then return chosen + 1 end
end

function ns.ChooseTalent(companion, key)
	local tier = ns.TalentDue(companion)
	if not tier then return false end
	for _, talent in ipairs(ns.TALENTS[companion.role][tier]) do
		if talent.key == key then
			companion.talents = companion.talents or {}
			companion.talents[#companion.talents + 1] = key
			return true
		end
	end
	return false
end

-- Forged gear: what the next level costs, whether the forge allows it.
function ns.GearCost(companion)
	local level = (companion.gear or 0) + 1
	return floor(100 * level ^ 1.6), level
end

function ns.CanForge(companion)
	local gear = companion.gear or 0
	if gear >= ns.GEAR_MAX then return false, "top" end
	if gear >= 2 * ns.Level("forge") then return false, "forge" end
	local embers, supplies = ns.GearCost(companion)
	local s = ns.State()
	if s.embers < embers then return false, "embers" end
	if s.supplies < supplies then return false, "supplies" end
	return true
end

function ns.Forge(companion)
	if not ns.CanForge(companion) then return false end
	local s = ns.State()
	local embers, supplies = ns.GearCost(companion)
	s.embers, s.supplies = s.embers - embers, s.supplies - supplies
	companion.gear = (companion.gear or 0) + 1
	return true
end

-- Bonds: what the companions who went together before add to the odds.
local function BondKey(a, b) return a < b and (a .. ":" .. b) or (b .. ":" .. a) end
function ns.BondBonus(members)
	local bonds, total = ns.State().bonds, 0
	for i = 1, #members do
		for j = i + 1, #members do
			local shared = bonds[BondKey(members[i].id, members[j].id)] or 0
			total = total + min(ns.BOND_PAIR, floor(shared / ns.BOND_EVERY) * 0.01)
		end
	end
	return min(ns.BOND_PARTY, total)
end

local function GainXP(companion, amount)
	if companion.level >= ns.LevelCap() then return end
	companion.xp = (companion.xp or 0) + floor(amount * (1 + Trait(companion, "xp")))
	while companion.level < ns.LevelCap() and companion.xp >= ns.XPNeed(companion.level) do
		companion.xp = companion.xp - ns.XPNeed(companion.level)
		companion.level = companion.level + 1
	end
end

local function UsedNames()
	local used = {}
	for _, companion in ipairs(ns.State().companions) do used[companion.name] = true end
	return used
end

local function NewCompanion(level)
	local used = UsedNames()
	local names = {}
	for _, name in ipairs(ns.NAMES) do if not used[name] then names[#names + 1] = name end end
	local class = Pick(ns.CLASSES)
	return { name = Pick(#names > 0 and names or ns.NAMES), class = class.file, role = Pick(class.roles),
		trait = Pick(ns.TRAIT_KEYS), level = max(1, level), xp = 0 }
end

local function Join(companion)
	local s = ns.State()
	companion.id = s.nextId
	s.nextId = s.nextId + 1
	s.companions[#s.companions + 1] = companion
	return companion
end

-- The candidates around the fire: three, new ones every few hours.
function ns.Candidates()
	local s = ns.State()
	if not s.candidates or Now() - (s.candidatesAt or 0) >= ns.CANDIDATES_EVERY then
		local top = max(1, min(ns.PlayerLevel(), s.tier * 10))
		s.candidates = {}
		for index = 1, 3 do
			s.candidates[index] = NewCompanion(math.random(max(1, floor(top * 0.3)), max(1, floor(top * 0.6))))
		end
		s.candidatesAt = Now()
	end
	return s.candidates
end

function ns.RecruitCost()
	return floor(10 * (Count() + 1) ^ 1.5 * (1 - min(0.5, ns.ProfessionBonus("recruit"))))
end

function ns.CanRecruit()
	if Count() >= ns.MaxCompanions() then return false, "full" end
	if ns.State().renown < ns.RecruitCost() then return false, "renown" end
	return true
end

function ns.Recruit(index)
	local s = ns.State()
	local candidate = ns.Candidates()[index]
	if not candidate or not ns.CanRecruit() then return false end
	s.renown = s.renown - ns.RecruitCost()
	table.remove(s.candidates, index)
	Join(candidate)
	return candidate
end

function ns.Dismiss(id)
	local s = ns.State()
	for index, companion in ipairs(s.companions) do
		if companion.id == id and not ns.Busy(companion) and not companion.champion then
			table.remove(s.companions, index)
			return true
		end
	end
	return false
end

-- A champion for each faction your character is exalted with (beyond the tents' room).
local function Champions()
	local s = ns.State()
	for _, champion in ipairs(ns.CHAMPIONS) do
		if not s.champions[champion.faction] then
			local name, exalted = ns.Faction(champion.faction)
			if exalted and name then
				s.champions[champion.faction] = true
				Join({ name = name, class = champion.class, role = champion.role, trait = "valiant",
					level = min(60, ns.PlayerLevel()), xp = 0, champion = champion.faction })
				ns.Said("champion", name)
			end
		end
	end
end

-- The fire's tiers and the buildings ----------------------------------------------------------------------

function ns.NextTier()
	local s = ns.State()
	return ns.TIERS[s.tier + 1]
end

function ns.CanRaise()
	local s, nextTier = ns.State(), ns.NextTier()
	if not nextTier then return false, "top" end
	if ns.PlayerLevel() < nextTier.level then return false, "level" end
	if s.renown < nextTier.renown then return false, "renown" end
	if s.embers < nextTier.embers then return false, "embers" end
	return true
end

function ns.Raise()
	if not ns.CanRaise() then return false end
	local s, nextTier = ns.State(), ns.NextTier()
	s.renown, s.embers = s.renown - nextTier.renown, s.embers - nextTier.embers
	s.tier = s.tier + 1
	return true
end

function ns.BuildingCost(key)
	local building, level = ns.BUILDING[key], ns.Level(key)
	return floor(building.embers * ns.BUILDING_GROWTH ^ level), building.supplies * (level + 1)
end

function ns.CanBuild(key)
	local s, level = ns.State(), ns.Level(key)
	if level >= ns.BUILDING_MAX then return false, "top" end
	if level >= s.tier then return false, "tier" end
	local embers, supplies = ns.BuildingCost(key)
	if s.embers < embers then return false, "embers" end
	if s.supplies < supplies then return false, "supplies" end
	return true
end

function ns.Build(key)
	if not ns.CanBuild(key) then return false end
	local s = ns.State()
	local embers, supplies = ns.BuildingCost(key)
	s.embers, s.supplies = s.embers - embers, s.supplies - supplies
	s.buildings[key] = ns.Level(key) + 1
	return true
end

-- The places of the expeditions ---------------------------------------------------------------------------

-- Every place: { kind, area, low, high, open, why (when closed) }.
function ns.Places()
	local places, level, s = {}, ns.PlayerLevel(), ns.State()
	for _, zone in ipairs(ns.ZONES) do
		local open, why = ns.ZoneOpen(zone)
		places[#places + 1] = { kind = "zone", area = zone.area, low = zone.low, high = zone.high, open = open, why = why }
	end
	for _, dungeon in ipairs(ns.DUNGEONS) do
		local open = level >= dungeon.low and ns.TIERS[s.tier].party >= ns.PARTY.dungeon
		places[#places + 1] = { kind = "dungeon", area = dungeon.area, low = dungeon.low, high = dungeon.high, open = open,
			why = not open and (level < dungeon.low and "level" or "tier") or nil }
	end
	for _, raid in ipairs(ns.RAIDS) do
		local open = level >= 60 and ns.TIERS[s.tier].party >= ns.PARTY.raid
		places[#places + 1] = { kind = "raid", area = raid.area, low = raid.low, high = raid.high, open = open,
			why = not open and (level < 60 and "level" or "tier") or nil }
	end
	return places
end

local function Difficulty(place)
	if place.kind == "zone" then return (place.low + place.high) / 2 end
	return place.high
end

-- An expedition's odds (0.05 to 0.95), as said before it leaves.
function ns.Chance(place, minutes, members)
	local count = #members
	if count == 0 then return 0 end
	local total, tank, heal = 0, false, false
	for _, companion in ipairs(members) do
		total = total + ns.Power(companion, place, minutes)
		if companion.role == "tank" then tank = true end
		if companion.role == "heal" then heal = true end
	end
	local chance = 0.45 + (total / count - Difficulty(place)) * 0.04 + (count - 1) * 0.04
	if place.kind == "zone" then
		chance = chance + (tank and 0.05 or 0) + (heal and 0.05 or 0)
	else
		chance = chance + (tank and 0.1 or -0.15) + (heal and 0.1 or -0.15) - 0.15 * max(0, ns.PARTY[place.kind] - count)
	end
	local steps = 0
	for index, length in ipairs(ns.DURATIONS[place.kind]) do if length == minutes then steps = index - 1 end end
	chance = chance - 0.04 * steps + 0.03 * ns.Level("apothecary") + ns.ProfessionBonus("success")
		+ PartyEffect(members, "success") + ns.BondBonus(members)
	return max(0.05, min(0.95, chance))
end

function ns.Provisions(place, minutes, members)
	local frugal = 0
	for _, companion in ipairs(members) do frugal = frugal + Effect(companion, "provisions") end
	local per = place.kind == "raid" and 24 or 12
	return ceil(#members * minutes / per * (1 - frugal / max(1, #members)))
end

function ns.Length(minutes, members)
	local swift = 0
	for _, companion in ipairs(members) do swift = max(swift, Effect(companion, "duration")) end
	return floor(minutes * 60 * (1 - swift - ns.ProfessionBonus("duration")))
end

function ns.Running()
	local running = 0
	for _ in pairs(ns.State().expeditions) do running = running + 1 end
	return running
end

-- Whether it can leave, and why not.
function ns.CanStart(place, minutes, members)
	local s, tier = ns.State(), ns.Tier()
	if not place.open then return false, "closed" end
	if #members == 0 then return false, "none" end
	if #members > tier.party then return false, "party" end
	if ns.Running() >= tier.slots then return false, "slots" end
	if s.provisions < ns.Provisions(place, minutes, members) then return false, "provisions" end
	for _, companion in ipairs(members) do
		if not ns.Free(companion) then return false, "busy" end
	end
	return true
end

function ns.Start(place, minutes, members)
	if not ns.CanStart(place, minutes, members) then return false end
	local s = ns.State()
	local ids = {}
	for index, companion in ipairs(members) do ids[index] = companion.id end
	local expedition = { id = s.nextId, kind = place.kind, area = place.area, low = place.low, high = place.high,
		minutes = minutes, members = ids, start = Now(), finish = Now() + ns.Length(minutes, members),
		chance = ns.Chance(place, minutes, members) }
	s.nextId = s.nextId + 1
	s.provisions = s.provisions - ns.Provisions(place, minutes, members)
	for _, companion in ipairs(members) do companion.busy = expedition.id end
	s.expeditions[#s.expeditions + 1] = expedition
	ns.Schedule()
	return expedition
end

-- What a won expedition brings, before luck.
function ns.Rewards(place, minutes, members)
	local hours = minutes / 60
	local base = Difficulty(place) * hours ^ 0.85 * ns.REWARD_SCALE[place.kind]
	local s = ns.State()
	local bonus = 1 + 0.08 * ns.Level("watch") + ns.ProfessionBonus("rewards") + ns.TROPHY_BONUS * floor(ns.TrophyCount() / 10)
		+ ns.PRESTIGE_BONUS * s.prestige + ((s.lived[place.area] or 0) > 0 and ns.LIVED_BONUS or 0)
	for _, companion in ipairs(members) do bonus = bonus + Effect(companion, "rewards") / max(1, #members) end
	return { renown = floor(base * (0.5 + 0.25 * #members) * bonus), embers = floor(base * 4 * bonus) }
end

local function FindTrophy(area, hours, members)
	local s = ns.State()
	s.trophies[area] = s.trophies[area] or {}
	local found = s.trophies[area]
	local luck = 1 + ns.ProfessionBonus("trophy") + 0.1 * ns.Level("watch")
	for _, companion in ipairs(members) do luck = luck + Trait(companion, "trophy") end
	for index = 3, 1, -1 do
		if not found[index] and math.random() < ns.TROPHY_CHANCES[index] * hours ^ 0.5 * luck then
			found[index] = true
			return index
		end
	end
end

local function Resolve(expedition)
	local s = ns.State()
	local members = {}
	for _, id in ipairs(expedition.members) do
		local companion = ns.Companion(id)
		if companion then members[#members + 1] = companion end
	end
	local place = { kind = expedition.kind, area = expedition.area, low = expedition.low, high = expedition.high }
	local won = math.random() < expedition.chance
	local told = { kind = expedition.kind, area = expedition.area, won = won, at = expedition.finish, hurt = {} }
	local rewards = ns.Rewards(place, expedition.minutes, members)
	local share = won and 1 or 0.2
	told.renown, told.embers = floor(rewards.renown * share), won and rewards.embers or 0
	s.renown = s.renown + told.renown
	s.embers = min(ns.Rates().embersCap, s.embers + told.embers)
	if won and math.random() < 0.25 + 0.1 * expedition.minutes / 60 then
		told.supplies = ceil(Difficulty(place) / 12 * ns.REWARD_SCALE[place.kind])
		s.supplies = s.supplies + told.supplies
	end
	if won then told.trophy = FindTrophy(expedition.area, expedition.minutes / 60, members) end
	local xp = expedition.minutes * 1.5 * ns.REWARD_SCALE[place.kind] * (won and 1 or 0.4)
	local heal = 1 - 0.15 * ns.Level("apothecary") - ns.ProfessionBonus("injury") - min(0.6, PartyEffect(members, "partyInjury"))
	local learn = 1 + min(0.6, PartyEffect(members, "partyXp"))
	for _, companion in ipairs(members) do
		companion.busy = nil
		local before = companion.level
		GainXP(companion, xp * learn * (Difficulty(place) / max(1, companion.level)) ^ 0.5)
		if companion.level > before then told.up = (told.up or 0) + 1 end
		if not won and math.random() < 0.5 then
			local minutes = max(30, expedition.minutes * 0.5) * max(0.1, heal) * (1 - Trait(companion, "injury"))
			companion.hurt = expedition.finish + floor(minutes * 60)
			told.hurt[#told.hurt + 1] = companion.name
		end
	end
	s.stats.expeditions = s.stats.expeditions + 1
	if won then
		s.stats.won = s.stats.won + 1
		if place.kind == "dungeon" then s.stats.dungeons = s.stats.dungeons + 1 end
		if place.kind == "raid" then s.stats.raids = s.stats.raids + 1 end
	end
	for i = 1, #members do
		for j = i + 1, #members do
			local key = BondKey(members[i].id, members[j].id)
			s.bonds[key] = (s.bonds[key] or 0) + 1
		end
	end
	-- (now and then, a choice the road brings back with it)
	if not s.event and math.random() < ns.ROAD_CHANCE then
		s.event, s.eventArea = Pick(ns.ROAD_EVENTS).key, expedition.area
	end
	table.insert(s.log, 1, told)
	while #s.log > ns.LOG_KEPT do table.remove(s.log) end
	return told
end

-- The expeditions back: resolved, in the order they came back.
local function Returns(now)
	local s = ns.State()
	local back = {}
	table.sort(s.expeditions, function(a, b) return a.finish < b.finish end)
	for index = #s.expeditions, 1, -1 do
		local expedition = s.expeditions[index]
		if expedition.finish <= now then
			table.remove(s.expeditions, index)
			table.insert(back, 1, Resolve(expedition))
		end
	end
	return back
end

-- The quartermaster's orders -----------------------------------------------------------------------------

function ns.OrderSlots()
	local tier = ns.State().tier
	return 3 + (tier >= 3 and 1 or 0) + (tier >= 5 and 1 or 0)
end

-- The goods an order may ask of a source (a profession's key or "general"), near a level of items.
local function Goods(source, target)
	local reagents, bits = W.Reagents()
	local rule = ns.ORDER_SOURCES[source]
	local bitsOf = {} -- the bits of the source's professions
	for _, name in ipairs(rule.bits) do if bits[name] then bitsOf[#bitsOf + 1] = bits[name] end end
	local subclasses = type(rule.subclass) == "table" and rule.subclass or (rule.subclass and { rule.subclass }) or nil
	local near, any = {}, {}
	for id, used in pairs(reagents) do
		local shared = false
		for _, bit in ipairs(bitsOf) do
			if floor(used / bit) % 2 == 1 then shared = true end
		end
		if shared then
			local _, _, _, _, _, class, subclass = U.ItemInstant(id)
			local kind = not subclasses
			for _, wanted in ipairs(subclasses or {}) do if class == 7 and subclass == wanted then kind = true end end
			if kind and U.ItemMaxStack(id) > 1 then
				local level = U.ItemLevels(id)
				if level then
					any[#any + 1] = id
					if math.abs(level - target) <= 10 then near[#near + 1] = id end
				else
					U.LoadItem(id) -- (known next time)
				end
			end
		end
	end
	return #near > 0 and near or any
end

local function NewOrder(taken)
	local list = { "general" }
	-- (your professions three times as often as the goods anyone may bring)
	for key in pairs(Professions()) do
		if ns.ORDER_SOURCES[key] then list[#list + 1] = key list[#list + 1] = key list[#list + 1] = key end
	end
	local source = Pick(list)
	local target = source == "general" and ns.PlayerLevel() or (5 + (Professions()[source] or 1) / 5)
	local goods = {}
	for _, id in ipairs(Goods(source, target)) do if not taken[id] then goods[#goods + 1] = id end end
	if #goods == 0 then return nil end
	local id = Pick(goods)
	local level = U.ItemLevels(id) or target
	local count = U.ItemMaxStack(id) >= 20 and (10 + 5 * math.random(0, 2)) or 5
	return { item = id, count = count, source = source, at = Now(),
		supplies = 1 + floor(level / 12) + (count >= 15 and 1 or 0), renown = floor(level * count / 8) + 5 }
end

local function Orders(now)
	local s = ns.State()
	for index = #s.orders, 1, -1 do
		local order = s.orders[index]
		if not order.done and now - order.at >= ns.ORDER_LIFE then table.remove(s.orders, index) end
		if order.done and now - order.done >= ns.ORDER_AGAIN then table.remove(s.orders, index) end
	end
	local taken = {}
	for _, order in ipairs(s.orders) do taken[order.item] = true end
	local tries = 0
	while #s.orders < ns.OrderSlots() and tries < 6 do
		tries = tries + 1
		local order = NewOrder(taken)
		if order then
			s.orders[#s.orders + 1] = order
			taken[order.item] = true
		end
	end
end

function ns.CanHonor(order)
	return not order.done and ns.Carried(order.item) >= order.count
end

-- Honored: the goods stay yours (they are only shown), the camp gets its due.
function ns.Honor(order)
	if not ns.CanHonor(order) then return false end
	local s = ns.State()
	order.done = Now()
	s.supplies, s.renown = s.supplies + order.supplies, s.renown + order.renown
	s.stats.orders = s.stats.orders + 1
	return true
end

-- Fireside events -----------------------------------------------------------------------------------------

local function Events(now)
	local s = ns.State()
	if s.event or now - (s.eventAt or 0) < ns.EVENT_EVERY then return end
	if s.nextEvent then
		s.event, s.eventAt, s.nextEvent = s.nextEvent, now, nil
		return
	end
	local list = {}
	for _, event in ipairs(ns.EVENTS) do if event.key ~= s.lastEvent then list[#list + 1] = event.key end end
	s.event, s.eventAt = Pick(list), now
end

local function AnyCompanion(free)
	local list = {}
	for _, companion in ipairs(ns.State().companions) do
		if not free or ns.Free(companion) then list[#list + 1] = companion end
	end
	return #list > 0 and Pick(list) or nil
end

-- A choice made: what it brings, said back ({ key = amount, ... }, the companion concerned).
function ns.Answer(choice)
	local s = ns.State()
	local event = s.event and ns.EVENT[s.event]
	if not event or (choice ~= "a" and choice ~= "b") then return nil end
	local effect, told = event[choice], {}
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		if effect[key] then
			s[key] = max(0, s[key] + effect[key])
			told[key] = effect[key]
		end
	end
	local companion = AnyCompanion(true)
	if effect.xp and companion then GainXP(companion, effect.xp) told.who = companion.name end
	if effect.next then s.nextEvent = effect.next end
	if effect.xpAll then for _, each in ipairs(s.companions) do GainXP(each, effect.xpAll) end end
	if effect.injury and companion and math.random() < 0.5 then
		companion.hurt = Now() + HOUR
		told.hurt = companion.name
	end
	if effect.heal then for _, each in ipairs(s.companions) do each.hurt = nil end told.healed = true end
	if effect.recruit and Count() < ns.MaxCompanions() then
		local joined = Join(NewCompanion(max(1, floor(ns.PlayerLevel() * 0.4))))
		told.joined = joined.name
	end
	if effect.trophy and math.random() < effect.trophy then
		local zone = Pick(ns.ZONES)
		local found = FindTrophy(zone.area, 100, {})
		if found then told.trophy, told.area = found, zone.area end
	end
	s.lastEvent, s.event, s.eventAt, s.eventArea = s.event, nil, Now(), nil
	return told
end

-- Your real journey ---------------------------------------------------------------------------------------

-- A quest handed in, fish caught, a dish cooked, a boss killed in a dungeon or a raid: the camp gets its share.
function ns.Real(kind, value)
	local s = ns.State()
	if not s.lit then return end
	local rates = ns.Rates()
	if kind == "quest" then
		s.renown = s.renown + ns.REAL.questRenown
	elseif kind == "fish" then
		s.provisions = min(rates.provisionsCap, s.provisions + ns.REAL.fishProvisions * (value or 1))
	elseif kind == "cook" then
		s.provisions = min(rates.provisionsCap, s.provisions + ns.REAL.cookProvisions)
	elseif kind == "boss" then
		local here = U.PlainName(value)
		for _, list in ipairs({ ns.DUNGEONS, ns.RAIDS }) do
			for _, place in ipairs(list) do
				if here and U.PlainName(U.AreaName(place.area)) == here then
					s.lived[place.area] = (s.lived[place.area] or 0) + 1
					if s.lived[place.area] == 1 then ns.Said("lived", place.area) end
				end
			end
		end
	end
end

-- Feats -----------------------------------------------------------------------------------------------------

-- How far a feat is: what you have, what it asks.
function ns.FeatProgress(feat)
	local s = ns.State()
	if feat.stat then return s.stats[feat.stat] or 0, feat.count end
	if feat.trophies then return ns.TrophyCount(), feat.trophies end
	if feat.tier then return s.tier, feat.tier end
	if feat.prestige then return s.prestige, feat.prestige end
	if feat.companions then return #s.companions, feat.companions end
	if feat.lived then
		local count = 0
		for _ in pairs(s.lived) do count = count + 1 end
		return count, feat.lived
	end
	if feat.companionLevel then
		local best = 0
		for _, companion in ipairs(s.companions) do best = max(best, companion.level) end
		return best, feat.companionLevel
	end
	if feat.champion then return next(s.champions) and 1 or 0, 1 end
	if feat.fullPlace then
		for _, found in pairs(s.trophies) do if found[1] and found[2] and found[3] then return 1, 1 end end
		return 0, 1
	end
	return s.lit and 1 or 0, 1
end

local function Feats()
	local s = ns.State()
	for _, feat in ipairs(ns.FEATS) do
		if not s.feats[feat.key] then
			local have, need = ns.FeatProgress(feat)
			if have >= need then
				s.feats[feat.key] = Now()
				s.renown = s.renown + feat.renown
				ns.Said("feat", feat.key)
			end
		end
	end
end

-- A new start (from the outpost): the camp begins again; its trophies, feats, champions and the places you
-- lived stay; each new start makes the fire and the roads give more.
function ns.CanRestart()
	local s = ns.State()
	return s.tier >= #ns.TIERS and ns.Running() == 0
end

function ns.Restart()
	if not ns.CanRestart() then return false end
	local s = ns.State()
	s.prestige = s.prestige + 1
	s.tier, s.embers, s.provisions, s.renown, s.supplies = 1, 0, 60, 30, 0
	s.buildings, s.orders, s.log, s.bonds, s.candidates = {}, {}, {}, {}, nil
	s.event, s.nextEvent, s.eventArea = nil, nil, nil
	local kept = {}
	for _, companion in ipairs(s.companions) do
		if companion.champion then
			companion.hurt, companion.busy = nil, nil
			kept[#kept + 1] = companion
		end
	end
	s.companions = kept
	Join(NewCompanion(1))
	Join(NewCompanion(1))
	return true
end

-- Lighting the fire: the traveler's heritage -------------------------------------------------------------

-- What your journey so far brings to a new camp (said once): reserves, and a veteran from level 10.
function ns.Heritage()
	local level, zones, skill = ns.PlayerLevel(), 0, 0
	for _, zone in ipairs(ns.ZONES) do if ns.ZoneOpen(zone) then zones = zones + 1 end end
	for _, value in pairs(ns.Professions()) do skill = skill + value end
	return { embers = 50 * level, provisions = 10 * level, renown = 3 * level + 10 * zones, supplies = floor(skill / 20),
		veteran = level >= 10 and (floor(level * 0.6) + 1) or nil, zones = zones }
end

function ns.Light()
	local s = ns.State()
	if s.lit then return nil end
	local heritage = ns.Heritage()
	s.lit, s.last, s.eventAt = Now(), Now(), Now()
	local rates = ns.Rates()
	s.embers = min(rates.embersCap, heritage.embers)
	s.provisions = min(rates.provisionsCap, 30 + heritage.provisions)
	s.renown, s.supplies = heritage.renown, heritage.supplies
	-- Two to start, and the veteran.
	Join(NewCompanion(1))
	Join(NewCompanion(1))
	if heritage.veteran then Join(NewCompanion(heritage.veteran)).veteran = true end
	ns.Update()
	return heritage
end

-- One look at the camp ------------------------------------------------------------------------------------

local said = {}
function ns.Said(kind, ...) said[#said + 1] = { kind, ... } end
function ns.TakeSaid()
	local list = said
	said = {}
	return list
end

-- Everything since the last look; the expeditions back are returned (for their notice).
function ns.Update()
	local s = ns.State()
	if not s.lit then return {} end
	local now = Now()
	ns.NoteVisit()
	Produce(now)
	local back = Returns(now)
	for _, companion in ipairs(s.companions) do
		if companion.hurt and companion.hurt <= now then companion.hurt = nil end
	end
	Champions()
	Feats()
	Events(now)
	-- (the orders looked at twice a minute at most: their goods are read from a long list)
	if now - (s.ordersAt or 0) >= 30 then
		s.ordersAt = now
		Orders(now)
	end
	ns.Schedule()
	return back
end

-- The next expedition back: one timer, its notice.
local token = 0
function ns.Schedule()
	token = token + 1
	local mine, soonest = token, nil
	for _, expedition in ipairs(ns.State().expeditions) do
		if not soonest or expedition.finish < soonest then soonest = expedition.finish end
	end
	if not soonest then return end
	C_Timer.After(max(1, soonest - Now() + 1), function()
		if mine ~= token then return end
		local back = ns.Update()
		if ns.Back then ns.Back(back) end
	end)
end
