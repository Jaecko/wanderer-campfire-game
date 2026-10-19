local _, ns = ...

-- The rules. Nothing runs between two looks: each time the camp is looked at (the window, a returning
-- expedition, the login), the time gone by is counted at once: what the fire made (12 hours at most while you
-- were away, more with the ashes' slumbering embers), the expeditions back, the hurt healed, a fireside event,
-- the orders, new candidates. One timer only, for the next expedition to come back (its notice).

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
	state.tier = math.max(1, math.floor(tonumber(state.tier) or 1))
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
	state.ashes = tonumber(state.ashes) or 0 -- the ashes not spent
	state.ashesTotal = tonumber(state.ashesTotal) or 0 -- every ash ever gathered (its bonus)
	state.rekindles = tonumber(state.rekindles) or 0
	state.choosing = state.choosing == true or nil -- (between two fires: the ashes to spend)
	state.ashTree = type(state.ashTree) == "table" and state.ashTree or {} -- node -> level
	state.gens = type(state.gens) == "table" and state.gens or {} -- producer -> how many owned
	state.upgrades = type(state.upgrades) == "table" and state.upgrades or {} -- upgrade id -> bought
	state.total = tonumber(state.total) or 0 -- every ember the fire ever made
	state.clicks = tonumber(state.clicks) or 0
	return state
end

function ns.Lit() return ns.State().lit ~= nil end
function ns.AshLevel(key) return ns.State().ashTree[key] or 0 end
-- A tier of the fire: one of the list, or past the seventh one of its endless levels (each dearer).
local eternal = {}
function ns.TierAt(index)
	local last = #ns.TIERS
	if index <= last then return ns.TIERS[index] end
	if eternal[index] then return eternal[index] end
	local base, past = ns.TIERS[last], index - last
	local tier = {}
	for key, value in pairs(base) do tier[key] = value end
	tier.embers = base.embers * ns.ETERNAL_GROWTH ^ past
	tier.renown = floor(ns.ETERNAL_RENOWN_BASE * ns.ETERNAL_RENOWN ^ (past - 1))
	eternal[index] = tier
	return tier
end
function ns.Tier() return ns.TierAt(ns.State().tier) end
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

-- What the fire makes an hour.
function ns.Rates(away)
	local tier = min(ns.State().tier, #ns.TIERS)
	local store = 1 + 0.5 * ns.Level("store")
	local again = 1 + ns.PRESTIGE_BONUS * ns.State().prestige
	local embers = ns.PerSecond(away) * HOUR
	local provisions = ns.PROVISIONS_RATE * tier * (1 + 0.3 * ns.Level("kitchen")) * (1 + ns.ProfessionBonus("provisions")) * again
		* (away and 1 or ns.HearthFactor())
	return {
		embers = embers, provisions = provisions,
		embersCap = math.huge, provisionsCap = floor(ns.PROVISIONS_CAP * tier * store), -- (embers: no cap any more)
	}
end

-- The clicker ---------------------------------------------------------------------------------------------

local function Earn(amount)
	if amount ~= amount or amount <= 0 or amount >= math.huge then return end
	local s = ns.State()
	s.embers = s.embers + amount
	s.total = s.total + amount
	s.run = (s.run or s.total - amount) + amount -- (this start's, since the last new start)
end

function ns.Owned(key) return ns.State().gens[key] or 0 end

-- What count more of a producer costs (its price grows with each one).
function ns.GenPrice(key, count)
	local generator, owned, total = ns.GENERATOR[key], ns.Owned(key), 0
	local cheaper = (1 - ns.MEMORY) ^ ns.AshLevel("memory")
	for index = 0, (count or 1) - 1 do total = total + ceil(generator.cost * cheaper * ns.GENERATOR_GROWTH ^ (owned + index)) end
	return total
end

-- Your character by a real campfire of the game (its "Cozy Fire"), its furniture around: what the camp makes
-- grows while you stay there (read once a second).
local hearth, hearthAt = 1, -1
function ns.HearthFactor()
	local now = GetTime and GetTime() or 0
	if now - hearthAt < 1 then return hearth end
	hearthAt = now
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	local fire, furniture = false, 0
	if get then
		for _, id in ipairs(ns.HEARTH_AURAS) do if U.Clean(U.Safe(get, id)) then fire = true end end
		for _, id in ipairs(ns.FURNITURE_AURAS) do if U.Clean(U.Safe(get, id)) then furniture = furniture + 1 end end
	end
	hearth = fire and (1 + ns.HEARTH_BONUS + ns.FURNITURE_BONUS * min(ns.FURNITURE_MAX, furniture)) or 1
	return hearth
end

-- What everything is multiplied by: the companions at the fire, its tier, your new starts, your trophies, a
-- real campfire of the game (away: not counted, the warmth is for the moments you are there).
-- The companions at the fire: as many as its tents hold
function ns.Multiplier(away)
	local s = ns.State()
	return (away and 1 or ns.HearthFactor()) * (1 + ns.COMPANION_BONUS * min(#s.companions, ns.MaxCompanions())) * (1 + ns.TIER_BONUS * (s.tier - 1)) * (1 + ns.PRESTIGE_BONUS * s.prestige)
		* (1 + ns.TROPHY_BONUS * floor(ns.TrophyCount() / 10))
		* (1 + ns.ASH_BONUS * s.ashesTotal) * (1 + ns.FERVOR * ns.AshLevel("fervor"))
end

-- (each producer's ranks, counted when one is bought; the rest counted again a few times a second at most)
local ranksOf
local function Ranks(key)
	if not ranksOf then
		ranksOf = {}
		for id in pairs(ns.State().upgrades) do
			local which = id:match("^rank:([^:]+):")
			if which then ranksOf[which] = (ranksOf[which] or 0) + 1 end
		end
	end
	return ranksOf[key] or 0
end
local perSecond, perSecondAt
local function Forget() ranksOf, perSecondAt = nil, nil end
ns.ForgetRates = Forget

-- What one producer of a kind makes a second, and all of them.
function ns.GenEach(key, away) return ns.GENERATOR[key].rate * 2 ^ Ranks(key) * ns.Multiplier(away) end
function ns.GenTotal(key, away) return ns.GenEach(key, away) * ns.Owned(key) end

-- What the fire makes a second: its own small flame, then every producer (away: without a real campfire's
-- warmth). Counted once a tenth of a second at most.
function ns.PerSecond(away)
	local now = GetTime and GetTime() or 0
	if not away and perSecondAt and now - perSecondAt < 0.1 then return perSecond end
	local multiplier = ns.Multiplier(away)
	local total = ns.Tier().rate / HOUR * multiplier
	for _, generator in ipairs(ns.GENERATORS) do
		total = total + generator.rate * 2 ^ Ranks(generator.key) * multiplier * ns.Owned(generator.key)
	end
	if away then return total end
	perSecond, perSecondAt = total, now
	return total
end

-- What a click on the fire brings.
function ns.ClickPower()
	local s = ns.State()
	local power, share = 1, 0
	for _, upgrade in ipairs(ns.CLICK_UPGRADES) do
		if s.upgrades["click:" .. upgrade.key] then
			if upgrade.double then power = power * 2 end
			share = share + (upgrade.share or 0)
		end
	end
	share = share + ns.CLICK_EMBER.share * ns.Embers()
	-- (breath: the whole click stronger, its share of what the fire makes a second too)
	return (power * (1 + ns.TIER_BONUS * (s.tier - 1)) * ns.HearthFactor() + share * ns.PerSecond()) * (1 + ns.BREATH * ns.AshLevel("breath"))
end

function ns.Click()
	if not ns.Lit() or ns.State().choosing then return 0 end
	local gain = ns.ClickPower()
	Earn(gain)
	local s = ns.State()
	s.clicks = s.clicks + 1
	return gain
end

-- A producer shown (once you have held a share of its price, or own one).
function ns.Revealed(key)
	local s = ns.State()
	return ns.Owned(key) > 0 or (s.run or s.total) >= ns.GENERATOR[key].cost * ns.REVEAL
end

function ns.BuyGenerator(key, count)
	count = count or 1
	local s, price = ns.State(), ns.GenPrice(key, count)
	if not ns.Lit() or s.choosing or s.embers < price then return false end
	s.embers = s.embers - price
	s.gens[key] = ns.Owned(key) + count
	Forget()
	return true
end

-- A producer's rank (its index): when it comes (so many owned), its price (times the producer's first price);
-- past the list, without end.
function ns.RankAt(index)
	local last = #ns.RANKS
	if index <= last then return ns.RANKS[index] end
	local base, past = ns.RANKS[last], index - last
	return { at = base.at + ns.RANK_EVERY * past, price = base.price * ns.RANK_PRICE ^ past }
end

-- The living embers bought (the click's upgrades without end, after the list).
function ns.Embers()
	local s, count = ns.State(), 0
	while s.upgrades["click:ember:" .. (count + 1)] do count = count + 1 end
	return count
end

-- The upgrades within reach, the cheapest first: { id, kind ("rank" or "click"), key, rank, price, icon }.
function ns.Upgrades()
	local s, list = ns.State(), {}
	for _, upgrade in ipairs(ns.CLICK_UPGRADES) do
		local id = "click:" .. upgrade.key
		if not s.upgrades[id] and (s.run or s.total) >= upgrade.price * ns.CLICK_REVEAL then
			list[#list + 1] = { id = id, kind = "click", key = upgrade.key, price = upgrade.price, icon = upgrade.icon, upgrade = upgrade }
		end
	end
	-- (the click's last upgrade bought: a living ember, then another...)
	local last = ns.CLICK_UPGRADES[#ns.CLICK_UPGRADES]
	if s.upgrades["click:" .. last.key] then
		local count = ns.Embers() + 1
		local price = last.price * ns.CLICK_PRICE ^ count
		if (s.run or s.total) >= price * ns.CLICK_REVEAL then
			list[#list + 1] = { id = "click:ember:" .. count, kind = "click", key = "ember", rank = count, price = price,
				icon = ns.CLICK_EMBER.icon, upgrade = ns.CLICK_EMBER }
		end
	end
	for _, generator in ipairs(ns.GENERATORS) do
		-- (its next rank only, in order)
		local index = 1
		while s.upgrades["rank:" .. generator.key .. ":" .. index] do index = index + 1 end
		local rank = ns.RankAt(index)
		if ns.Owned(generator.key) >= rank.at then
			list[#list + 1] = { id = "rank:" .. generator.key .. ":" .. index, kind = "rank", key = generator.key, rank = index + 1,
				price = generator.cost * rank.price, icon = generator.icon }
		end
	end
	table.sort(list, function(a, b) return a.price < b.price end)
	return list
end

function ns.BuyUpgrade(id)
	local s = ns.State()
	if not ns.Lit() or s.choosing then return false end
	for _, upgrade in ipairs(ns.Upgrades()) do
		if upgrade.id == id and s.embers >= upgrade.price then
			s.embers = s.embers - upgrade.price
			s.upgrades[id] = true
			Forget()
			return true
		end
	end
	return false
end

-- Provisions added, up to the larder's cap (what is above it already, from an event or an older cap, kept).
local function Stock(amount, cap)
	local s = ns.State()
	s.provisions = max(s.provisions, min(cap, s.provisions + amount))
end

-- While the window is open: what the fire made since the last frame (the provisions too).
local Relevel -- (below: an older save's companions on the gentler levels)

function ns.Tick(elapsed)
	if not ns.Lit() or elapsed <= 0 then return end
	-- (a long freeze of the game: counted by Produce, from the last moment seen)
	if elapsed > 1 then
		local back = ns.Update()
		if ns.Back then ns.Back(back) end
		return
	end
	Relevel()
	if not ns.State().choosing then Earn(ns.PerSecond() * elapsed) end
	local rates = ns.Rates()
	Stock(rates.provisions * elapsed / HOUR, rates.provisionsCap)
	ns.State().last = Now()
end

-- Embers given by a choice or an incident, in proportion to what the fire makes (never less than written).
local function EmberScale() return max(1, ns.PerSecond() / 5) end

-- Time going by -------------------------------------------------------------------------------------------

-- How long the fire burns while you are away (longer with the ashes' slumber).
function ns.Offline() return ns.OFFLINE + ns.SLUMBER * ns.AshLevel("slumber") end

local function Produce(now)
	local s = ns.State()
	local from = s.last or now
	local seconds = min(max(0, now - from), ns.Offline())
	s.last = now
	-- (a second or less: the window's own moments, already counted by Tick)
	if seconds <= 1 then return end
	local rates = ns.Rates(true)
	if not s.choosing then Earn(ns.PerSecond(true) * seconds) end
	Stock(rates.provisions * seconds / HOUR, rates.provisionsCap)
end

-- Companions ---------------------------------------------------------------------------------------------

function ns.LevelCap() return min(60, max(10, ns.PlayerLevel() + 5)) end
-- (gentle enough for the companions to follow your own level through the tiers)
function ns.XPNeed(level) return floor(40 * level ^ 1.3) end

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
	return floor(5000 * level ^ 2.2), level * level -- (embers, supplies: the forge, where supplies go)
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
	amount = amount or 0
	companion.xp = (companion.xp or 0) + floor(amount * (1 + Trait(companion, "xp")))
	while companion.level < ns.LevelCap() and companion.xp >= ns.XPNeed(companion.level) do
		companion.xp = companion.xp - ns.XPNeed(companion.level)
		companion.level = companion.level + 1
	end
end

-- (a save made before the gentler levels: its companions' experience counted again, once)
function Relevel()
	local s = ns.State()
	if s.levelCurve == 2 then return end
	s.levelCurve = 2
	for _, companion in ipairs(s.companions or {}) do GainXP(companion, 0) end
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

function ns.NextTier() return ns.TierAt(ns.State().tier + 1) end

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
	Forget()
	s.renown, s.embers = s.renown - nextTier.renown, s.embers - nextTier.embers
	s.tier = s.tier + 1
	return true
end

-- Trades at the camp (the peddler's supplies, a feast's renown): how many were made lately (forgotten by half
-- every TRADE_HALF_LIFE), what the next costs in embers, what it gives.
local function Traded(kind)
	local s = ns.State()
	s.trades = s.trades or {}
	local trade = s.trades[kind] or { count = 0, at = Now() }
	return trade.count * 0.5 ^ ((Now() - trade.at) / ns.TRADE_HALF_LIFE), trade
end

function ns.TradeCost(kind)
	local trade = ns.TRADES[kind]
	local recent = Traded(kind)
	local price = max(trade.least, ns.PerSecond(true) * trade.seconds) * ns.TRADE_GROWTH ^ recent
		* (1 - ns.PEDDLER) ^ ns.AshLevel("peddler")
	return floor(price), trade.gives + (trade.perTier or 0) * (min(ns.State().tier, #ns.TIERS) - 1)
end

function ns.CanTrade(kind)
	return ns.State().embers >= ns.TradeCost(kind)
end

function ns.Trade(kind)
	if not ns.CanTrade(kind) then return false end
	local s = ns.State()
	local price, gives = ns.TradeCost(kind)
	s.embers = s.embers - price
	s[kind] = s[kind] + gives
	local recent = Traded(kind)
	s.trades[kind] = { count = recent + 1, at = Now() }
	return gives
end

function ns.BuildingCost(key)
	local building, level = ns.BUILDING[key], ns.Level(key)
	return floor(building.embers * ns.BUILDING_SCALE * ns.BUILDING_GROWTH ^ level), building.supplies * (level + 1)
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
	local places, level = {}, ns.PlayerLevel()
	for _, zone in ipairs(ns.ZONES) do
		local open, why = ns.ZoneOpen(zone)
		places[#places + 1] = { kind = "zone", area = zone.area, low = zone.low, high = zone.high, open = open, why = why }
	end
	for _, dungeon in ipairs(ns.DUNGEONS) do
		local open = level >= dungeon.low and ns.Tier().party >= ns.PARTY.dungeon
		places[#places + 1] = { kind = "dungeon", area = dungeon.area, low = dungeon.low, high = dungeon.high, open = open,
			why = not open and (level < dungeon.low and "level" or "tier") or nil }
	end
	for _, raid in ipairs(ns.RAIDS) do
		local open = level >= 60 and ns.Tier().party >= ns.PARTY.raid
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
	-- (never more than a full larder: the longest expedition can always leave once it is full)
	return min(ns.Rates().provisionsCap, ceil(#members * minutes / per * (1 - frugal / max(1, #members))))
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
	return { renown = floor(base * (0.5 + 0.25 * #members) * bonus * ns.RENOWN_SCALE),
		embers = floor(base * 4 * bonus + ns.PerSecond(true) * minutes * ns.EXPEDITION_SHARE),
		supplies = max(1, floor(Difficulty(place) / ns.SUPPLIES_PER * ns.REWARD_SCALE[place.kind] * hours ^ 0.8
			* (0.75 + 0.25 * #members) * bonus)) }
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
	Earn(told.embers)
	-- Supplies: always when won, a share of them when lost.
	local supplies = won and rewards.supplies or floor(rewards.supplies * ns.SUPPLIES_LOST)
	if supplies > 0 then
		told.supplies = supplies
		s.supplies = s.supplies + supplies
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
	local index = 1
	while s.expeditions[index] do
		if s.expeditions[index].finish <= now then
			back[#back + 1] = Resolve(table.remove(s.expeditions, index))
		else
			index = index + 1
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

-- A choice you can pay for (what it costs, you have).
function ns.CanAnswer(choice)
	local s = ns.State()
	local event = s.event and ns.EVENT[s.event]
	local effect = event and event[choice]
	if not effect then return false end
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		local amount = effect[key]
		if amount and amount < 0 then
			if key == "embers" then amount = floor(amount * EmberScale()) end
			if s[key] < -amount then return false end
		end
	end
	return true
end

-- A choice made: what it brings, said back ({ key = amount, ... }, the companion concerned).
function ns.Answer(choice)
	local s = ns.State()
	local event = s.event and ns.EVENT[s.event]
	if not event or (choice ~= "a" and choice ~= "b") then return nil end
	local effect, told = event[choice], {}
	if not ns.CanAnswer(choice) then return nil end
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		if effect[key] then
			local amount = key == "embers" and floor(effect[key] * EmberScale()) or effect[key]
			if key == "embers" and amount > 0 then Earn(amount) else s[key] = max(0, s[key] + amount) end
			told[key] = amount
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
		Earn(floor(50 + ns.PerSecond(true) * ns.QUEST_SHARE))
	elseif kind == "fish" then
		Stock(ns.REAL.fishProvisions * (value or 1), rates.provisionsCap)
	elseif kind == "cook" then
		Stock(ns.REAL.cookProvisions, rates.provisionsCap)
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
	if feat.prestige then return s.prestige + s.rekindles, feat.prestige end
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

-- A new fire (rekindled) -------------------------------------------------------------------------------
-- Only the clicker begins again: the embers, the producers, their ranks, the click's upgrades. The tier, the
-- buildings, the companions, the expeditions and the other resources stay. It leaves ashes.

-- The ashes this fire would leave now: the cube root of what it made, counted in ASH_UNIT.
function ns.AshesFor()
	local s = ns.State()
	return floor(((s.run or 0) / ns.ASH_UNIT) ^ (1 / 3) + 1e-9) -- (1000 gives 9.999...: a hair added)
end

function ns.CanRekindle() return ns.Lit() and not ns.State().choosing and ns.AshesFor() >= 1 end

function ns.Rekindle()
	if not ns.CanRekindle() then return nil end
	local s = ns.State()
	local gained = ns.AshesFor()
	s.ashes, s.ashesTotal, s.rekindles = s.ashes + gained, s.ashesTotal + gained, s.rekindles + 1
	s.embers, s.gens, s.upgrades, s.run = 0, {}, {}, 0
	-- (the old fire out: its ashes spent before the new one is lit)
	s.choosing = true
	Forget()
	return gained
end

-- The new fire lit: kindling, it starts with a few producers.
function ns.Kindle()
	local s = ns.State()
	if not s.choosing then return false end
	s.choosing = nil
	local kindling = ns.AshLevel("kindling")
	for key, count in pairs(ns.KINDLING) do
		if kindling > 0 then s.gens[key] = (s.gens[key] or 0) + count * kindling end
	end
	Forget()
	return true
end

-- The ashes' tree: a node's next level, its price (nil at its top).
function ns.AshCost(key)
	local node = ns.ASH[key]
	local level = ns.AshLevel(key)
	if not node or (node.max and level >= node.max) then return nil end
	return ceil(node.cost * node.growth ^ level)
end

function ns.CanBuyAsh(key)
	local cost = ns.AshCost(key)
	return cost ~= nil and ns.State().choosing == true and ns.State().ashes >= cost
end

function ns.BuyAsh(key)
	if not ns.CanBuyAsh(key) then return false end
	local s = ns.State()
	s.ashes = s.ashes - ns.AshCost(key)
	s.ashTree[key] = ns.AshLevel(key) + 1
	Forget()
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
	s.provisions = 30 + heritage.provisions -- (all of it, as said: above the cap until spent)
	s.renown, s.supplies = heritage.renown, heritage.supplies
	-- Two to start, and the veteran.
	Join(NewCompanion(1))
	Join(NewCompanion(1))
	if heritage.veteran then Join(NewCompanion(heritage.veteran)).veteran = true end
	ns.Update()
	return heritage
end

-- While you were away -------------------------------------------------------------------------------------
-- The camp as you last saw it (its window closed, or the logout); on the next look after half an hour or more,
-- what changed meanwhile, said once.

local AWAY = 30 * 60

local function Levels()
	local total = 0
	for _, companion in ipairs(ns.State().companions) do total = total + (companion.level or 1) end
	return total
end

function ns.Snapshot()
	local s = ns.State()
	if not s.lit then return end
	s.seen = { time = Now(), embers = s.embers, provisions = s.provisions, renown = s.renown, supplies = s.supplies,
		expeditions = s.stats.expeditions, won = s.stats.won, trophies = ns.TrophyCount(), levels = Levels() }
end

-- What changed since you last saw the camp: { away (seconds), embers, provisions, renown, supplies, back, won,
-- trophies, levels }, or nil (not away long enough, nothing new, or the fire never seen). Said once.
function ns.WhileAway()
	local s = ns.State()
	local seen = s.seen
	if not (s.lit and type(seen) == "table" and seen.time) then return nil end
	local away = Now() - seen.time
	if away < AWAY then return nil end
	local recap = { away = away }
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
		recap[key] = max(0, floor((s[key] or 0) - (seen[key] or 0)))
	end
	recap.back = max(0, s.stats.expeditions - (seen.expeditions or 0))
	recap.won = max(0, s.stats.won - (seen.won or 0))
	recap.trophies = max(0, ns.TrophyCount() - (seen.trophies or 0))
	recap.levels = max(0, Levels() - (seen.levels or 0))
	ns.Snapshot()
	for _, key in ipairs({ "embers", "provisions", "renown", "supplies", "back", "trophies", "levels" }) do
		if recap[key] > 0 then return recap end
	end
	return nil
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

-- Something waits at the camp (Wanderer's bar then pulses its word): news come while its window was closed,
-- an expedition back, a choice by the fire, a talent to choose, the fire ready to grow, an order your bags
-- can honor.
function ns.Attention()
	if not ns.Lit() then return false end
	local s, now = ns.State(), Now()
	if s.choosing then return true end
	if s.unseen or s.event then return true end
	for _, expedition in ipairs(s.expeditions) do if expedition.finish <= now then return true end end
	for _, companion in ipairs(s.companions) do if ns.TalentDue(companion) then return true end end
	if ns.CanRaise() and s.raiseSeen ~= s.tier then return true end
	for _, order in ipairs(s.orders) do if ns.CanHonor(order) then return true end end
	return false
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
