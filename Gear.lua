local _, ns = ...

-- The companions as people: each one a race of your faction their class may be, a face (an NPC of the game
-- dressed in the armor of their class), and seven pieces of real gear (their names, icons and colors come from
-- the game). Gear is found on won expeditions (uncommon in zones, rare in dungeons, epic in raids) and put on at
-- once when it is better (what it replaces, like a piece that is not better, goes to the armory when it keeps
-- them, else to the forge for supplies). The older companions are given all this the first time they are seen.

local W = Wanderer
local U = W and W.Util

local floor, max, min = math.floor, math.max, math.min

-- Every piece by its id: its family, item level, level needed, quality.
ns.GEAR_ITEM = {}
for family, list in pairs(ns.GEAR_DATA or {}) do
	for i = 1, #list, 4 do
		ns.GEAR_ITEM[list[i]] = { family = family, level = list[i + 1], need = list[i + 2], quality = list[i + 3] }
	end
end

local FEMALE = {}
for _, name in ipairs(ns.NAMES_FEMALE) do FEMALE[name] = true end

local function Faction()
	local faction = U.Clean(U.Safe(UnitFactionGroup, "player"))
	return ns.FACTION_RACES[faction] and faction or "Alliance"
end

-- A number drawn from a text (the same each time: a companion keeps the face and race it was given).
local function Seed(text)
	local seed = 7
	for index = 1, #text do seed = (seed * 31 + text:byte(index)) % 2147483647 end
	return seed
end
ns.Seed = Seed

local function Within(list, wanted)
	local out = {}
	for _, value in ipairs(list) do
		for _, other in ipairs(wanted) do if value == other then out[#out + 1] = value end end
	end
	return out
end

-- The races of your faction a class may be (none: a class your faction cannot be).
local function Races(class) return Within(ns.CLASS_RACES[class] or { 1 }, ns.FACTION_RACES[Faction()]) end
function ns.OfFaction(class) return Races(class)[1] ~= nil end

-- The armor a companion wears now (the best its level allows).
function ns.ArmorOf(companion)
	for _, pair in ipairs(ns.CLASS_ARMOR[companion.class] or { { "cloth", 1 } }) do
		if (companion.level or 1) >= pair[2] then return pair[1] end
	end
	return "cloth"
end

-- The families of pieces a companion may wear in a slot, the best first.
local function Families(companion, slot)
	local list = {}
	if slot == "weapon" then
		for _, kind in ipairs(ns.CLASS_WEAPONS[companion.class] or { "staff" }) do list[#list + 1] = "weapon_" .. kind end
		return list
	end
	for _, pair in ipairs(ns.CLASS_ARMOR[companion.class] or { { "cloth", 1 } }) do
		if (companion.level or 1) >= pair[2] then list[#list + 1] = pair[1] .. "_" .. slot end
	end
	return list
end
ns.Families = Families

-- A piece for a slot: of a family the companion wears, needing a level from low to top, of a quality (else of
-- that quality from lower levels, else of a lesser one, else the nearest below); nil when the game has none.
-- (each pass: the quality exactly or below, the levels from low or any)
local PASSES = { { true, true }, { true, false }, { false, true }, { false, false } }
function ns.PickPiece(companion, slot, top, quality, low)
	top = max(1, top)
	low = min(top, low or (top - 6))
	for _, rule in ipairs(PASSES) do
		local exact, near = rule[1], rule[2]
		local found = {}
		for _, family in ipairs(Families(companion, slot)) do
			local list = ns.GEAR_DATA and ns.GEAR_DATA[family] or {}
			for i = 1, #list, 4 do
				local need, worth = list[i + 2], list[i + 3]
				local fits = need <= top and (not near or need >= low) and (exact and worth == quality or not exact and worth <= quality)
				if fits then found[#found + 1] = list[i] end
			end
			-- (armor: the best kind first; weapons: any kind of the class)
			if found[1] and slot ~= "weapon" then break end
		end
		if found[1] then
			-- (from any level: the nearest below, the highest levels kept)
			if not near then
				table.sort(found, function(a, b) return ns.GEAR_ITEM[a].need > ns.GEAR_ITEM[b].need end)
				return found[math.random(min(3, #found))]
			end
			return found[math.random(#found)]
		end
	end
end

-- A companion's identity and gear, given once (an older one, a new recruit, a champion).
function ns.Outfit(companion)
	local seed = Seed((companion.name or "") .. (companion.class or ""))
	-- (its rarity and abilities: an older companion uncommon, a champion epic)
	if not companion.rarity then companion.rarity = companion.champion and 4 or 2 end
	if not companion.abilities then ns.GiveAbilities(companion) end
	if companion.sex == nil then companion.sex = FEMALE[companion.name] and 1 or (companion.champion and floor(seed / 3) % 2 or 0) end
	if not companion.race then
		-- (a champion of a class your faction cannot be: one of its own races)
		local races = Races(companion.class)
		if not races[1] then races = ns.CLASS_RACES[companion.class] or { 1 } end
		companion.race = races[seed % #races + 1]
	end
	if not companion.look then
		local faces = ns.LOOKS and ns.LOOKS[companion.race] and ns.LOOKS[companion.race][companion.sex + 1]
		local list
		if faces then
			list = faces[ns.ArmorOf(companion)]
			for _, pair in ipairs(ns.CLASS_ARMOR[companion.class] or {}) do list = list or faces[pair[1]] end
			list = list or faces.cloth or faces.leather or faces.mail or faces.plate
		end
		if list and list[1] then companion.look = list[floor(seed / 7) % #list + 1] end
	end
	if not companion.items then
		companion.items, companion.found = {}, {}
		for _, slot in ipairs(ns.SLOTS) do
			companion.items[slot] = ns.PickPiece(companion, slot, (companion.level or 1) - 1, 2, (companion.level or 1) - 8)
		end
	end
	companion.record = companion.record or {}
	return companion
end

-- Their gear's strength: its mean item level (an empty slot ten levels below them), what it adds or takes away.
function ns.ItemLevel(companion)
	local total = 0
	for _, slot in ipairs(ns.SLOTS) do
		local piece = companion.items and ns.GEAR_ITEM[companion.items[slot]]
		total = total + (piece and piece.level or max(1, (companion.level or 1) - 10))
	end
	return total / #ns.SLOTS
end

function ns.GearFactor(companion)
	return 1 + max(ns.GEAR_LOW, min(ns.GEAR_HIGH, ns.GEAR_ILVL * (ns.ItemLevel(companion) - (companion.level or 1) - 5)))
end

-- A piece found on a won expedition (a place, its length, the party): for the one it suits best, put on when
-- better, else kept in the armory (when it keeps them) or taken apart at the forge. boost: { quality, sure,
-- strict } (a contract's, the week's chest; strict: of that quality only, every slot tried). Returns what was
-- found, for the expedition's tale.
function ns.FindGear(place, minutes, members, boost)
	local rule = ns.FIND[place.kind]
	if not (rule and members[1]) then return nil end
	local luck = 1 + 0.05 * ns.Level("watch") + ns.ProfessionBonus("trophy") * 0.5
	local chance = (boost and boost.sure) and 1 or min(0.95, rule.chance * (minutes / 60) ^ 0.5 * luck)
	local quality = boost and boost.quality or rule.quality
	local found = {}
	for _ = 1, boost and 1 or (rule.pieces or 1) do
		if math.random() < chance then
			-- (each member a slot drawn, or every slot when strict: the piece goes to the one it raises most)
			local best
			for _, companion in ipairs(members) do
				local top = min(companion.level, place.high)
				for _, slot in ipairs(boost and boost.strict and ns.SLOTS or { ns.SLOTS[math.random(#ns.SLOTS)] }) do
					local item = ns.PickPiece(companion, slot, top, quality, max(place.low, top - 6))
					local piece = item and ns.GEAR_ITEM[item]
					if piece and not (boost and boost.strict and piece.quality ~= quality) then
						local gain = ns.WearGain(companion, item)
						if not best or gain > best.gain then best = { companion = companion, slot = slot, item = item, gain = gain } end
					end
				end
			end
			if best then
				local companion = best.companion
				local tale = { name = companion.name, slot = best.slot, item = best.item, gain = best.gain }
				if best.gain > 0 then
					-- (what it wore there: kept in the armory, else taken apart at the forge)
					local old, oldFrom = ns.PutOn(companion, best.slot, best.item, place.area)
					if old and not ns.Keep(old, oldFrom) then
						tale.oldSalvage = ns.SalvageOf(old)
						ns.State().supplies = ns.State().supplies + tale.oldSalvage
					end
					companion.record = companion.record or {}
					companion.record.items = (companion.record.items or 0) + 1
					ns.WeekAdd("gear")
				elseif ns.Keep(best.item, place.area) then
					tale.kept = true
				else
					-- (no better: the forge takes it apart)
					tale.salvage = ns.SalvageOf(best.item)
					ns.State().supplies = ns.State().supplies + tale.salvage
				end
				found[#found + 1] = tale
			end
		end
	end
	return found[1] and found or nil
end

-- A piece put on in a slot (where it was found; false: not known, a piece of the armory that was worn first by
-- another); what was worn there, and where it had been found, given back.
function ns.PutOn(companion, slot, item, area)
	companion.items = companion.items or {}
	companion.found = companion.found or {}
	local old, oldFrom = companion.items[slot], companion.found[slot]
	companion.items[slot], companion.found[slot] = item, area or false
	return old, oldFrom
end

-- What the forge gives for a piece taken apart.
function ns.SalvageOf(item) return 1 + floor(((ns.GEAR_ITEM[item] or {}).level or 0) / 15) end

-- A piece as the game knows it: its name (when the game has it already: else asked once, nil meanwhile), icon, color.
local asked = {}
function ns.PieceName(item)
	local name = U.ItemName(item)
	if not name and not asked[item] then
		asked[item] = true
		U.LoadItem(item)
	end
	return name
end
function ns.PieceIcon(item) return U.ItemIcon(item) or "Interface\\Icons\\INV_Misc_QuestionMark" end
function ns.PieceText(item)
	local piece = ns.GEAR_ITEM[item]
	local name = ns.PieceName(item) or "..."
	if not piece then return name end
	local r, g, b = U.QualityColor(piece.quality)
	return U.Colorize(name, r or 1, g or 1, b or 1)
end
