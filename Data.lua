local _, ns = ...

-- What the game is made of: the fire's tiers, the buildings, the classes and traits of the companions, the
-- places of the expeditions (zones, dungeons, raids, by the game's own area ids: their names come from the
-- game, in your language), the factions that send a champion, the fireside events. Numbers only: the
-- words are in Locales.lua, the rules in Game.lua.

local HOUR = 3600

-- The fire, tier by tier: the level your character needs, what it costs to build (renown, embers), the
-- embers its own small flame makes an hour (rate; cap: read no more), the
-- companions it shelters, the expeditions at once, the most companions on one expedition.
-- (balanced by simulated playthroughs of 30 days: the clicker makes billions by the second day, so the
-- embers of the later tiers are counted in trillions; renown grows with the expeditions of each tier)
ns.TIERS = {
	{ level = 1, renown = 0, embers = 0, rate = 60, cap = 600, companions = 4, slots = 1, party = 2 },
	{ level = 10, renown = 60, embers = 2000, rate = 120, cap = 2500, companions = 5, slots = 2, party = 3 },
	{ level = 20, renown = 400, embers = 5e11, rate = 240, cap = 7500, companions = 6, slots = 2, party = 5 },
	{ level = 30, renown = 5000, embers = 1e14, rate = 420, cap = 20000, companions = 8, slots = 3, party = 5 },
	{ level = 45, renown = 25000, embers = 2e15, rate = 660, cap = 50000, companions = 10, slots = 4, party = 5 },
	{ level = 55, renown = 45000, embers = 1.5e16, rate = 960, cap = 60000, companions = 12, slots = 5, party = 10 },
	{ level = 60, renown = 80000, embers = 3e16, rate = 1300, cap = 70000, companions = 12, slots = 5, party = 10 },
}
-- The seventh tier, the eternal blaze, never ends: each of its levels (II, III...) asks so many times the
-- embers and the renown of the one before; it shelters no more companions, it makes more (TIER_BONUS).
ns.ETERNAL_GROWTH = 1.3
ns.ETERNAL_RENOWN = 1.08
ns.ETERNAL_RENOWN_BASE = 25000 -- (the eternal levels ask less renown than the seventh, the gate: a renown of their own)

ns.OFFLINE = 12 * HOUR -- the fire burns this long while you are away, no more
ns.PROVISIONS_RATE = 6 -- provisions an hour, for each tier of the fire (a full larder pays any expedition)
ns.PROVISIONS_CAP = 60 -- provisions held, for each tier
ns.EVENT_EVERY = 3 * HOUR -- a fireside event, at most this often
ns.ORDER_LIFE = 24 * HOUR -- an order not honored leaves the board after this
ns.ORDER_AGAIN = 2 * HOUR -- an honored order's place takes a new one after this
ns.CANDIDATES_EVERY = 4 * HOUR -- new candidates around the fire
ns.LOG_KEPT = 30 -- the last expeditions told

-- The buildings: each up to the fire's tier; what a level costs (embers, supplies, both growing) and does.
ns.BUILDINGS = {
	{ key = "kitchen", embers = 150, supplies = 2, icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ key = "forge", embers = 250, supplies = 3, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ key = "apothecary", embers = 200, supplies = 3, icon = "Interface\\Icons\\Trade_Alchemy" },
	{ key = "tents", embers = 300, supplies = 4, icon = "Interface\\Icons\\INV_Misc_Bag_10" },
	{ key = "store", embers = 180, supplies = 2, icon = "Interface\\Icons\\INV_Crate_01" },
	{ key = "watch", embers = 350, supplies = 5, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
}
ns.BUILDING_GROWTH = 120 -- each level costs this much more embers than the one before (the clicker grows that fast)
ns.BUILDING_SCALE = 40 -- (the clicker's scale: the embers of a level, so many times its base)

-- The clicker ---------------------------------------------------------------------------------------------
-- What keeps the fire burning, bought with embers: each makes so many embers a second; its price grows with
-- each one bought (GENERATOR_GROWTH). A producer shows once you have held a share of its price (REVEAL).
ns.GENERATORS = {
	{ key = "twigs", cost = 15, rate = 0.1, icon = "Interface\\Icons\\Spell_Fire_Fire" },
	{ key = "woodcutter", cost = 100, rate = 1, icon = "Interface\\Icons\\INV_Axe_02" },
	{ key = "charcoal", cost = 1100, rate = 8, icon = "Interface\\Icons\\INV_Ore_Iron_01" },
	{ key = "bellows", cost = 12000, rate = 47, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ key = "firestone", cost = 130000, rate = 260, icon = "Interface\\Icons\\Spell_Fire_SelfDestruct" },
	{ key = "brazier", cost = 1400000, rate = 1400, icon = "Interface\\Icons\\Spell_Fire_Incinerate" },
	{ key = "elemental", cost = 20000000, rate = 7800, icon = "Interface\\Icons\\Spell_Fire_Volcano" },
	{ key = "heart", cost = 330000000, rate = 44000, icon = "Interface\\Icons\\Spell_Fire_LavaSpawn" },
}
ns.GENERATOR_GROWTH = 1.15
ns.REVEAL = 0.4
ns.GENERATOR = {}
for index, generator in ipairs(ns.GENERATORS) do generator.index = index ns.GENERATOR[generator.key] = generator end
-- A producer's ranks: once so many are owned, a rank doubles what each makes (bought for so many times the
-- producer's first price).
-- (then, past the last, one more every RANK_EVERY owned, RANK_PRICE times dearer each)
ns.RANKS = { { at = 1, price = 10 }, { at = 5, price = 50 }, { at = 25, price = 500 }, { at = 50, price = 50000 },
	{ at = 100, price = 5000000 } }
ns.RANK_EVERY, ns.RANK_PRICE = 50, 1000
-- The click's own upgrades: the click twice as strong, or a share of what the fire makes each second added.
ns.CLICK_UPGRADES = {
	{ key = "poker", price = 100, double = true, icon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
	{ key = "bellows", price = 500, double = true, icon = "Interface\\Icons\\Spell_Fire_Fireball02" },
	{ key = "glove", price = 10000, double = true, icon = "Interface\\Icons\\Spell_Fire_SealOfFire" },
	{ key = "spark", price = 100000, share = 0.05, icon = "Interface\\Icons\\Spell_Fire_SoulBurn" },
	{ key = "blaze", price = 10000000, share = 0.05, icon = "Interface\\Icons\\Spell_Fire_FlameShock" },
	{ key = "inferno", price = 1000000000, share = 0.1, icon = "Interface\\Icons\\Spell_Fire_Immolation" },
}
-- (then, without end, a living ember: a share more of what the fire makes, CLICK_PRICE times dearer each)
ns.CLICK_EMBER = { share = 0.05, icon = "Interface\\Icons\\Spell_Fire_Fire" }
ns.CLICK_PRICE = 1000
-- A real campfire of the game: its warmth (the "Cozy Fire" aura) makes the camp give more, and each piece of
-- furniture set around it (by the auras it gives) more still.
ns.HEARTH_AURAS = { 7353 } -- Cozy Fire
ns.FURNITURE_AURAS = {} -- (filled as they are known)
ns.HEARTH_BONUS = 0.5
ns.FURNITURE_BONUS = 0.15
ns.FURNITURE_MAX = 4
ns.CLICK_REVEAL = 0.3 -- a click's upgrade shows once you have held this share of its price
ns.COMPANION_BONUS = 0.05 -- each companion at the fire: so much more made
ns.TIER_BONUS = 0.25 -- each tier of the fire beyond the first: so much more made, and the click as much
ns.EXPEDITION_SHARE = 15 -- an expedition won brings what the fire makes in so many seconds, for each of its minutes
ns.RENOWN_SCALE = 0.6 -- the renown an expedition brings, so many times its base (the fire's tiers and recruits ask a lot)
ns.SUPPLIES_PER = 30 -- an expedition won brings a supply for so many levels of its place (more when long, with more)
ns.SUPPLIES_LOST = 0.25 -- an expedition lost still brings back this share of them
-- The embers the clicker makes, traded at the camp: a supply at the peddler, renown for a feast. The price is
-- what the fire makes in so many seconds (a floor below it), growing with each trade (GROWTH), the growth
-- forgotten by half every HALF_LIFE seconds.
ns.TRADES = {
	supplies = { seconds = 120, least = 500, gives = 1 },
	renown = { seconds = 300, least = 1500, gives = 10, perTier = 5 },
}
ns.TRADE_GROWTH = 1.2
ns.TRADE_HALF_LIFE = 6 * 3600
ns.QUEST_SHARE = 30 -- a quest handed in: what the fire makes in so many seconds
ns.BUILDING_MAX = 5
ns.BUILDING = {} -- by key
for index, building in ipairs(ns.BUILDINGS) do building.index = index ns.BUILDING[building.key] = building end

-- The game's classes (their file names: their colors and icons come from the game) and the roles each may hold.
ns.CLASSES = {
	{ file = "WARRIOR", roles = { "tank", "dps" } },
	{ file = "PALADIN", roles = { "tank", "heal", "dps" } },
	{ file = "HUNTER", roles = { "dps" } },
	{ file = "ROGUE", roles = { "dps" } },
	{ file = "PRIEST", roles = { "heal", "dps" } },
	{ file = "SHAMAN", roles = { "heal", "dps" } },
	{ file = "MAGE", roles = { "dps" } },
	{ file = "WARLOCK", roles = { "dps" } },
	{ file = "DRUID", roles = { "tank", "heal", "dps" } },
}
ns.CLASS = {}
for _, class in ipairs(ns.CLASSES) do ns.CLASS[class.file] = class end

-- The traits a companion may have, each with what it changes (Game.lua reads them).
ns.TRAITS = {
	careful = { injury = 0.5 }, -- hurt half as long
	tracker = { trophy = 0.5 }, -- trophies found more often
	sturdy = { longPower = 0.15 }, -- stronger on long expeditions
	lucky = { rewards = 0.12 }, -- more brought back
	swift = { duration = 0.1 }, -- the expedition a little shorter
	frugal = { provisions = 0.3 }, -- eats less
	valiant = { hardPower = 0.15 }, -- stronger where it is hard
	learned = { xp = 0.25 }, -- learns faster
}
ns.TRAIT_KEYS = { "careful", "tracker", "sturdy", "lucky", "swift", "frugal", "valiant", "learned" }

-- Companions' names (the same in every language).
ns.NAMES = {
	"Aldric", "Brenna", "Caelan", "Dorna", "Edric", "Fenna", "Garrick", "Hilde", "Ivor", "Jessa", "Kael", "Lira",
	"Marek", "Nessa", "Orrin", "Perra", "Quill", "Rhosyn", "Soren", "Talia", "Ulric", "Vessa", "Wren", "Yorrick",
	"Zara", "Bram", "Cora", "Dalen", "Elowen", "Fargus", "Grenna", "Halvar", "Isolde", "Joren", "Kestra", "Lothar",
	"Mira", "Norwin", "Odessa", "Pellam", "Runa", "Sigrid", "Tobin", "Una", "Varek", "Willa", "Brannoc", "Eira",
	"Thorn", "Maelis", "Corwin", "Saela", "Grom", "Ysolde", "Durgan", "Liesl", "Hakon", "Nym", "Rowan", "Tamsin",
}

-- The expeditions' durations, in minutes (zones; dungeons; raids).
ns.DURATIONS = { zone = { 15, 60, 240, 480, 720 }, dungeon = { 120, 360, 720 }, raid = { 720, 1440 } } -- (12 h: a night)

-- The zones: their area (its name), the exploration achievement that opens them, their levels.
ns.ZONES = {
	{ area = 12, achievement = 776, low = 1, high = 10 }, -- Elwynn Forest
	{ area = 1, achievement = 627, low = 1, high = 10 }, -- Dun Morogh
	{ area = 141, achievement = 842, low = 1, high = 10 }, -- Teldrassil
	{ area = 14, achievement = 728, low = 1, high = 10 }, -- Durotar
	{ area = 215, achievement = 736, low = 1, high = 10 }, -- Mulgore
	{ area = 85, achievement = 768, low = 1, high = 10 }, -- Tirisfal Glades
	{ area = 40, achievement = 802, low = 10, high = 20 }, -- Westfall
	{ area = 38, achievement = 779, low = 10, high = 20 }, -- Loch Modan
	{ area = 148, achievement = 844, low = 10, high = 20 }, -- Darkshore
	{ area = 130, achievement = 769, low = 10, high = 20 }, -- Silverpine Forest
	{ area = 17, achievement = 750, low = 10, high = 25 }, -- The Barrens
	{ area = 44, achievement = 780, low = 15, high = 25 }, -- Redridge Mountains
	{ area = 406, achievement = 847, low = 15, high = 27 }, -- Stonetalon Mountains
	{ area = 10, achievement = 778, low = 18, high = 30 }, -- Duskwood
	{ area = 331, achievement = 845, low = 18, high = 30 }, -- Ashenvale
	{ area = 11, achievement = 841, low = 20, high = 30 }, -- Wetlands
	{ area = 267, achievement = 772, low = 20, high = 30 }, -- Hillsbrad Foothills
	{ area = 400, achievement = 846, low = 25, high = 35 }, -- Thousand Needles
	{ area = 36, achievement = 760, low = 30, high = 40 }, -- Alterac Mountains
	{ area = 45, achievement = 761, low = 30, high = 40 }, -- Arathi Highlands
	{ area = 405, achievement = 848, low = 30, high = 40 }, -- Desolace
	{ area = 33, achievement = 781, low = 30, high = 45 }, -- Stranglethorn Vale
	{ area = 15, achievement = 850, low = 35, high = 45 }, -- Dustwallow Marsh
	{ area = 3, achievement = 765, low = 35, high = 45 }, -- Badlands
	{ area = 8, achievement = 782, low = 35, high = 45 }, -- Swamp of Sorrows
	{ area = 357, achievement = 849, low = 40, high = 50 }, -- Feralas
	{ area = 47, achievement = 773, low = 40, high = 50 }, -- The Hinterlands
	{ area = 440, achievement = 851, low = 40, high = 50 }, -- Tanaris
	{ area = 51, achievement = 774, low = 43, high = 50 }, -- Searing Gorge
	{ area = 16, achievement = 852, low = 45, high = 55 }, -- Azshara
	{ area = 4, achievement = 766, low = 45, high = 55 }, -- Blasted Lands
	{ area = 490, achievement = 854, low = 48, high = 55 }, -- Un'Goro Crater
	{ area = 361, achievement = 853, low = 48, high = 55 }, -- Felwood
	{ area = 46, achievement = 775, low = 50, high = 58 }, -- Burning Steppes
	{ area = 28, achievement = 770, low = 51, high = 58 }, -- Western Plaguelands
	{ area = 139, achievement = 771, low = 53, high = 60 }, -- Eastern Plaguelands
	{ area = 618, achievement = 857, low = 55, high = 60 }, -- Winterspring
	{ area = 41, achievement = 777, low = 55, high = 60 }, -- Deadwind Pass
	{ area = 493, achievement = 855, low = 55, high = 60 }, -- Moonglade
	{ area = 1377, achievement = 856, low = 55, high = 60 }, -- Silithus
}

-- The dungeons (opened by your level) and the raids (your level 60 and a fire whose expeditions take ten).
ns.DUNGEONS = {
	{ area = 2437, low = 13, high = 18 }, -- Ragefire Chasm
	{ area = 718, low = 17, high = 24 }, -- Wailing Caverns
	{ area = 1581, low = 17, high = 26 }, -- The Deadmines
	{ area = 209, low = 22, high = 30 }, -- Shadowfang Keep
	{ area = 719, low = 24, high = 32 }, -- Blackfathom Deeps
	{ area = 717, low = 24, high = 32 }, -- The Stockade
	{ area = 133, low = 29, high = 38 }, -- Gnomeregan
	{ area = 1717, low = 30, high = 40 }, -- Razorfen Kraul
	{ area = 796, low = 34, high = 45 }, -- Scarlet Monastery
	{ area = 722, low = 40, high = 50 }, -- Razorfen Downs
	{ area = 1517, low = 41, high = 51 }, -- Uldaman
	{ area = 978, low = 44, high = 54 }, -- Zul'Farrak
	{ area = 2100, low = 46, high = 55 }, -- Maraudon
	{ area = 1417, low = 50, high = 56 }, -- The Temple of Atal'Hakkar
	{ area = 1584, low = 52, high = 60 }, -- Blackrock Depths
	{ area = 1583, low = 55, high = 60 }, -- Blackrock Spire
	{ area = 2557, low = 56, high = 60 }, -- Dire Maul
	{ area = 2017, low = 58, high = 60 }, -- Stratholme
	{ area = 2057, low = 58, high = 60 }, -- Scholomance
}
ns.RAIDS = {
	{ area = 1977, low = 60, high = 62 }, -- Zul'Gurub
	{ area = 3429, low = 60, high = 62 }, -- Ruins of Ahn'Qiraj
	{ area = 2717, low = 60, high = 63 }, -- Molten Core
	{ area = 2159, low = 60, high = 63 }, -- Onyxia's Lair
	{ area = 2677, low = 60, high = 65 }, -- Blackwing Lair
	{ area = 3428, low = 60, high = 67 }, -- Temple of Ahn'Qiraj
	{ area = 3456, low = 60, high = 70 }, -- Naxxramas
}
ns.PARTY = { dungeon = 5, raid = 10 }
ns.REWARD_SCALE = { zone = 1, dungeon = 2.5, raid = 6 }

-- The professions (the game's skill lines) and what each brings to the camp, at its full skill (300).
ns.PROFESSIONS = {
	[185] = { key = "cooking", provisions = 0.5 }, -- Cooking
	[356] = { key = "fishing", provisions = 0.25 }, -- Fishing
	[164] = { key = "blacksmithing", power = 0.15 }, -- Blacksmithing
	[186] = { key = "mining", power = 0.1 }, -- Mining
	[171] = { key = "alchemy", success = 0.05, injury = 0.3 }, -- Alchemy
	[182] = { key = "herbalism", success = 0.03, injury = 0.2 }, -- Herbalism
	[129] = { key = "firstaid", injury = 0.3 }, -- First Aid
	[197] = { key = "tailoring", recruit = 0.2 }, -- Tailoring
	[165] = { key = "leatherworking", recruit = 0.15 }, -- Leatherworking
	[393] = { key = "skinning", rewards = 0.1 }, -- Skinning
	[202] = { key = "engineering", duration = 0.1 }, -- Engineering
	[333] = { key = "enchanting", trophy = 0.5 }, -- Enchanting
}
-- The orders of each profession: the reagents its own recipes use (Wanderer.Reagents' bits), and for the
-- gatherers, the kind of goods they bring (the game's item class 7, its subclass).
ns.ORDER_SOURCES = {
	cooking = { bits = { "Cooking" } },
	fishing = { bits = { "Cooking" } },
	blacksmithing = { bits = { "Blacksmithing" } },
	mining = { bits = { "Blacksmithing", "Engineering", "Mining" }, subclass = 7 }, -- metal and stone
	alchemy = { bits = { "Alchemy" } },
	herbalism = { bits = { "Alchemy" }, subclass = 9 }, -- herbs
	firstaid = { bits = { "FirstAid" } },
	tailoring = { bits = { "Tailoring" } },
	leatherworking = { bits = { "Leatherworking" } },
	skinning = { bits = { "Leatherworking" }, subclass = 6 }, -- leather
	engineering = { bits = { "Engineering" } },
	enchanting = { bits = { "Enchanting" } },
	general = { bits = { "Tailoring", "Cooking", "FirstAid" }, subclass = { 5, 8 } }, -- cloth, meat
}

-- The factions whose champion joins an exalted character: their id, the champion's class and role.
ns.CHAMPIONS = {
	{ faction = 72, class = "PALADIN", role = "tank" }, -- Stormwind
	{ faction = 47, class = "WARRIOR", role = "tank" }, -- Ironforge
	{ faction = 69, class = "DRUID", role = "heal" }, -- Darnassus
	{ faction = 54, class = "MAGE", role = "dps" }, -- Gnomeregan
	{ faction = 76, class = "WARRIOR", role = "tank" }, -- Orgrimmar
	{ faction = 81, class = "DRUID", role = "heal" }, -- Thunder Bluff
	{ faction = 68, class = "WARLOCK", role = "dps" }, -- Undercity
	{ faction = 530, class = "SHAMAN", role = "heal" }, -- Darkspear Trolls
	{ faction = 529, class = "PRIEST", role = "heal" }, -- Argent Dawn
	{ faction = 609, class = "DRUID", role = "dps" }, -- Cenarion Circle
	{ faction = 59, class = "WARRIOR", role = "dps" }, -- Thorium Brotherhood
	{ faction = 576, class = "HUNTER", role = "dps" }, -- Timbermaw Hold
	{ faction = 749, class = "SHAMAN", role = "dps" }, -- Hydraxian Waterlords
	{ faction = 270, class = "PRIEST", role = "dps" }, -- Zandalar Tribe
	{ faction = 910, class = "MAGE", role = "dps" }, -- Brood of Nozdormu
}

-- The fireside events: two choices each, and what each brings (resources, a companion's experience or
-- hurt, a trophy). Their words: EVENT_<key>, EVENT_<key>_A/_B (the choices), EVENT_<key>_A_DONE/_B_DONE.
ns.EVENTS = {
	{ key = "peddler", a = { embers = -150, supplies = 3 }, b = { renown = 5 } },
	{ key = "wounded", a = { provisions = -40, renown = 25 }, b = { embers = 60 } },
	{ key = "rumor", a = { trophy = 0.6, injury = true }, b = { xp = 120 } },
	{ key = "storm", a = { embers = -100, provisions = 30 }, b = { provisions = -50 } },
	{ key = "bard", a = { embers = -50, renown = 20 }, b = { xp = 80 } },
	{ key = "wolves", a = { injury = true, provisions = 60 }, b = { provisions = -30 } },
	{ key = "pilgrim", a = { provisions = -30, renown = 30 }, b = { embers = 40 } },
	{ key = "cache", a = { supplies = 4, injury = true }, b = { embers = 120 } },
	{ key = "stars", a = { xp = 150 }, b = { embers = 150 } },
	{ key = "rival", a = { renown = 40, injury = true }, b = { renown = -10, supplies = 2 } },
	{ key = "feast", a = { provisions = -60, xpAll = 60 }, b = { provisions = 20 } },
	{ key = "lost", a = { provisions = -20, recruit = true }, b = { renown = 5 } },
	{ key = "relic", a = { embers = -200, trophy = 1 }, b = { supplies = 2 } },
	{ key = "spring", a = { heal = true }, b = { provisions = 40 } },
}
ns.EVENT = {}
for _, event in ipairs(ns.EVENTS) do ns.EVENT[event.key] = event end

-- Trophies: three of each place (a keepsake, a relic, a treasure), how often each is found on a won
-- expedition of an hour, and the camp's bonus for every ten trophies found.
ns.TROPHY_CHANCES = { 0.15, 0.05, 0.012 }
ns.TROPHY_BONUS = 0.02 -- more brought back, for every ten trophies

-- Talents: at levels 20, 40 and 60 a companion chooses one of two, by its role. What each changes: power (its
-- strength), success (the expedition's odds), injury (its wounds shorter), partyInjury (everyone's), rewards
-- (more brought back), trophy, duration (shorter), provisions (eaten less), partyXp (everyone learns faster).
ns.TALENT_LEVELS = { 20, 40, 60 }
ns.TALENTS = {
	tank = {
		{ { key = "bulwark", power = 0.1 }, { key = "shieldwall", partyInjury = 0.3 } },
		{ { key = "vanguard", success = 0.04 }, { key = "sentinel", hardPower = 0.2 } },
		{ { key = "champion", power = 0.2 }, { key = "warden", success = 0.06 } },
	},
	heal = {
		{ { key = "mender", partyInjury = 0.4 }, { key = "blessed", partyXp = 0.2 } },
		{ { key = "lifeline", success = 0.05 }, { key = "herbal", provisions = 0.3 } },
		{ { key = "saint", success = 0.08 }, { key = "sage", partyXp = 0.3 } },
	},
	dps = {
		{ { key = "hunter", trophy = 0.4 }, { key = "striker", power = 0.1 } },
		{ { key = "raider", rewards = 0.1 }, { key = "pathfinder", duration = 0.1 } },
		{ { key = "slayer", power = 0.2 }, { key = "plunderer", rewards = 0.2 } },
	},
}
ns.TALENT = {}
for _, tiers in pairs(ns.TALENTS) do
	for _, pair in ipairs(tiers) do for _, talent in ipairs(pair) do ns.TALENT[talent.key] = talent end end
end

-- Forged gear: each level makes a companion 4 % stronger; the forge allows two levels for each of its own.
ns.GEAR_POWER = 0.04
ns.GEAR_MAX = 10

-- Bonds: two companions who often go together work better (for every 5 expeditions shared, 1 % more chance,
-- 5 % at most for a pair, 10 % for a party).
ns.BOND_EVERY, ns.BOND_PAIR, ns.BOND_PARTY = 5, 0.05, 0.1

-- Your real victories: a dungeon or raid where your character killed a boss is "lived": its expeditions bring
-- a quarter more, for good.
ns.LIVED_BONUS = 0.25

-- What your real journey brings to the camp as you play.
ns.REAL = { questRenown = 4, fishProvisions = 4, cookProvisions = 6 }

-- Incidents on the road: one expedition in five comes back with a choice to make (its place in the words).
ns.ROAD_CHANCE = 0.2
ns.ROAD_EVENTS = {
	{ key = "road_chest", a = { supplies = 3, injury = true }, b = { xp = 60 } },
	{ key = "road_refugees", a = { provisions = -40, renown = 35 }, b = { renown = 5 } },
	{ key = "road_ambush", a = { renown = 30, injury = true }, b = { embers = -120 } },
	{ key = "road_shrine", a = { xpAll = 50 }, b = { supplies = 2, renown = -10 } },
	{ key = "road_map", a = { embers = -150, trophy = 0.8 }, b = { embers = 100 } },
	{ key = "road_storm", a = { provisions = -30 }, b = { injury = true, renown = 10 } },
}
-- Stories told over three nights: the first choice "a" leads to the next one.
ns.CHAIN_EVENTS = {
	{ key = "bard2", a = { renown = 30, next = "bard3" }, b = { embers = 60 } },
	{ key = "bard3", a = { renown = 80, xpAll = 80 }, b = { supplies = 4 } },
	{ key = "lost2", a = { provisions = -30, next = "lost3" }, b = { renown = 10 } },
	{ key = "lost3", a = { recruit = true, renown = 40 }, b = { supplies = 3 } },
}
ns.EVENT.bard.a.next, ns.EVENT.lost.a.next = "bard2", "lost2"
for _, list in ipairs({ ns.ROAD_EVENTS, ns.CHAIN_EVENTS }) do
	for _, event in ipairs(list) do ns.EVENT[event.key] = event end
end

-- The camp's feats: what each asks (Game.lua reads it) and the renown it gives once.
ns.FEATS = {
	{ key = "light", renown = 10 },
	{ key = "road10", stat = "expeditions", count = 10, renown = 40 },
	{ key = "road100", stat = "expeditions", count = 100, renown = 200 },
	{ key = "road500", stat = "expeditions", count = 500, renown = 800 },
	{ key = "dungeon", stat = "dungeons", count = 1, renown = 60 },
	{ key = "raid", stat = "raids", count = 1, renown = 300 },
	{ key = "orders10", stat = "orders", count = 10, renown = 60 },
	{ key = "orders50", stat = "orders", count = 50, renown = 250 },
	{ key = "trophies10", trophies = 10, renown = 80 },
	{ key = "trophies50", trophies = 50, renown = 400 },
	{ key = "place", fullPlace = true, renown = 120 },
	{ key = "tier3", tier = 3, renown = 100 },
	{ key = "tier6", tier = 6, renown = 600 },
	{ key = "tier7", tier = 7, renown = 1000 },
	{ key = "veteran", companionLevel = 60, renown = 300 },
	{ key = "champion", champion = true, renown = 150 },
	{ key = "lived5", lived = 5, renown = 200 },
	{ key = "band", companions = 10, renown = 150 },
	{ key = "again", prestige = 1, renown = 500 },
}

-- A new start, from the outpost: the camp begins again, its trophies, feats and champions kept, and each new
-- start makes the fire burn and the roads give 10 % more for good.
ns.PRESTIGE_BONUS = 0.1 -- (the new starts of older versions, the whole camp begun again: their bonus kept)

-- A new fire (rekindled, the Ashes' page): only the clicker begins again (embers, producers, their ranks, the
-- click's upgrades); the tier, the buildings, the companions, the expeditions and every other resource stay.
-- It leaves ashes: the cube root of what this fire made, counted in ASH_UNIT (eight times more embers, twice
-- the ashes). Each ash ever gathered makes every fire ASH_BONUS more, for good; the ashes are also spent in
-- the tree below (a level's price: cost * growth ^ level; a node has no end, but slumber: 48 hours at most).
ns.ASH_UNIT = 1e10
ns.ASH_BONUS = 0.1
ns.ASH_TREE = {
	{ key = "kindling", cost = 1, growth = 2, icon = "Interface\\Icons\\INV_TradeskillItem_03" }, -- a new fire starts with producers
	{ key = "breath", cost = 2, growth = 2, icon = "Interface\\Icons\\Spell_Nature_Cyclone" }, -- a click half as strong again
	{ key = "memory", cost = 3, growth = 2, icon = "Interface\\Icons\\INV_Misc_Book_09" }, -- producers 8 % cheaper (of what is left)
	{ key = "fervor", cost = 5, growth = 1.5, icon = "Interface\\Icons\\Spell_Fire_SealOfFire" }, -- everything 15 % more
	{ key = "slumber", max = 18, cost = 4, growth = 1.8, icon = "Interface\\Icons\\Spell_Nature_Sleep" }, -- 2 h more while away
	{ key = "peddler", cost = 3, growth = 2, icon = "Interface\\Icons\\INV_Misc_Coin_02" }, -- trades 8 % cheaper (of what is left)
}
ns.ASH = {}
for index, node in ipairs(ns.ASH_TREE) do node.index = index ns.ASH[node.key] = node end
ns.KINDLING = { twigs = 10, woodcutter = 5, charcoal = 2 } -- a new fire's producers, for each level of kindling
ns.FERVOR, ns.MEMORY, ns.SLUMBER, ns.PEDDLER, ns.BREATH = 0.15, 0.08, 2 * HOUR, 0.08, 0.5
