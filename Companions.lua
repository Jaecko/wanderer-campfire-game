local _, ns = ...
local L = ns.L

-- The companions' page: those of the camp as cards, two by two (their face ringed in their class's color and
-- their level on its seal, their name, race and class, their role, what they do now, their strength, how far
-- to their next level), each opening their sheet; then the candidates around the fire, to recruit.
-- A companion's sheet: standing in 3D (turned by dragging) between the seven pieces they wear (real gear of
-- the game, found on the roads), their strength and item level, their experience; below, three leaves: their
-- statistics (and the forge, which reinforces their gear), their talents, their journey (and the way to part).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local ROLE_TONES = { tank = "blue", heal = "green", dps = "red" }
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local GOLD, MUTED = Skin.COLORS.gold, Skin.COLORS.muted
local DOT = ns.DOT
local view, profile = {}, {}

-- A companion's class icon (a part of the game's sheet of them).
function ns.ClassIcon(class)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	local inset = 0.012
	return CLASS_ICONS, { coords[1] + inset, coords[2] - inset, coords[3] + inset, coords[4] - inset }
end

-- Their class and race in the game's words (a woman's class said as such when the game says it).
function ns.CompanionClass(companion)
	local names = companion.sex == 1 and LOCALIZED_CLASS_NAMES_FEMALE or nil
	return names and names[companion.class] or ns.ClassName(companion.class)
end
function ns.RaceName(race)
	local info = race and C_CreatureInfo and C_CreatureInfo.GetRaceInfo and U.Safe(C_CreatureInfo.GetRaceInfo, race)
	return type(info) == "table" and U.Clean(info.raceName) or nil
end
-- "Dwarf · Paladin": who they are, in a few words.
function ns.CompanionKind(companion)
	local race = ns.RaceName(companion.race)
	return (race and (race .. DOT) or "") .. ns.CompanionClass(companion)
end

-- A rarity's word (the game's: uncommon, rare, epic), in its color.
function ns.RarityName(rarity, plain)
	local word = _G["ITEM_QUALITY" .. (rarity or 2) .. "_DESC"] or L.RARITY
	if plain then return word end
	local r, g, b = U.QualityColor(rarity or 2)
	return U.Colorize(word, r or 1, g or 1, b or 1)
end

-- A companion's name, said with their title.
function ns.CompanionName(companion)
	if companion.champion then return L.CHAMPION_OF:format(companion.name) end
	if companion.veteran then return companion.name .. "  " .. Skin.Colorize("(" .. L.VETERAN .. ")", "muted") end
	return companion.name
end

-- What a companion is: their class, level and trait.
function ns.CompanionLine(companion)
	return ns.CompanionClass(companion) .. ", " .. L.LEVEL_SHORT:format(companion.level) .. ", " .. L["TRAIT_" .. companion.trait:upper()]
end

-- A companion as a row of a list (for this page and the expeditions'): their round portrait.
function ns.CompanionRow(companion, extra)
	local spec = { companion = companion, title = ns.CompanionName(companion), color = ns.ClassColor(companion.class),
		sub = ns.CompanionLine(companion), chip = L["ROLE_" .. companion.role:upper()], tone = ROLE_TONES[companion.role] }
	for key, value in pairs(extra or {}) do spec[key] = value end
	return spec
end

local function Expedition(companion)
	for _, expedition in ipairs(ns.State().expeditions) do
		if expedition.id == companion.busy then return expedition end
	end
end

-- What they do now: words, a color, how far along (an expedition's road), where.
local function Doing(companion)
	if ns.Busy(companion) then
		local expedition = Expedition(companion)
		if expedition then
			return L.STATE_BUSY:format(ns.Left(expedition.finish - time())), Skin.COLORS.blue, ns.Progress(expedition), ns.PlaceName(expedition.area)
		end
	end
	if ns.Hurt(companion) then return L.STATE_HURT:format(ns.Left(companion.hurt - time())), Skin.COLORS.bad end
	return L.STATE_FREE, Skin.COLORS.good
end

local function State(companion)
	local words, color = Doing(companion)
	local text = U.Colorize(words, color[1], color[2], color[3])
	if not ns.Busy(companion) and not ns.Hurt(companion) and ns.TalentDue(companion) then
		text = text .. ", " .. Skin.Colorize(L.TALENT_READY, "gold")
	end
	return text
end

-- The cards ------------------------------------------------------------------------------------------------------

local CARD_HEIGHT = 132

local function NewCard(parent)
	local card = CreateFrame("Button", nil, parent)
	card:SetHeight(CARD_HEIGHT)
	card.ground = card:CreateTexture(nil, "BACKGROUND")
	card.ground:SetAllPoints()
	card.ground:SetColorTexture(1, 1, 1, 0.035)
	card.glow = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.glow:SetPoint("TOPLEFT")
	card.glow:SetPoint("TOPRIGHT")
	card.glow:SetHeight(70)
	card.accent = card:CreateTexture(nil, "BORDER")
	card.accent:SetPoint("TOPLEFT")
	card.accent:SetPoint("TOPRIGHT")
	card.accent:SetHeight(2)
	card.edges = Skin.Edges(card, 1, 1, 1, 0.07)
	card.hover = card:CreateTexture(nil, "HIGHLIGHT")
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, 0.05)
	card.portrait = ns.Portrait(card, 54, true)
	card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -14)
	card.name = Skin.CreateText(card, "GameFontNormal")
	card.name:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 12, -2)
	card.name:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	card.name:SetJustifyH("LEFT")
	if card.name.SetWordWrap then card.name:SetWordWrap(false) end
	card.kind = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card.kind:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.kind:SetPoint("RIGHT", card, "RIGHT", -8, 0)
	card.kind:SetJustifyH("LEFT")
	if card.kind.SetWordWrap then card.kind:SetWordWrap(false) end
	card.role = card:CreateTexture(nil, "ARTWORK")
	card.role:SetSize(16, 16)
	card.role:SetPoint("TOPLEFT", card.kind, "BOTTOMLEFT", -1, -5)
	card.roleText = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.roleText:SetPoint("LEFT", card.role, "RIGHT", 4, 0)
	card.roleText:SetJustifyH("LEFT")
	if card.roleText.SetWordWrap then card.roleText:SetWordWrap(false) end
	card.mark = card:CreateTexture(nil, "OVERLAY")
	card.mark:SetSize(14, 14)
	card.mark:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
	card.dot = card:CreateTexture(nil, "OVERLAY")
	card.dot:SetSize(12, 12)
	card.dot:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -7)
	card.dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	-- (their abilities, small, at the right of their role)
	card.skills = {}
	for index = 1, 3 do
		local skill = card:CreateTexture(nil, "ARTWORK")
		skill:SetSize(15, 15)
		ns.Crop(skill)
		skill:SetPoint("RIGHT", card, "TOPRIGHT", -10 - (index - 1) * 18, -57)
		card.skills[index] = skill
	end
	card.roleText:SetPoint("RIGHT", card.skills[3], "LEFT", -4, 0)
	-- At its foot: what they do now, their strength; the road's progress; their experience.
	card.rule = Skin.Rule(card, false, 0.1)
	card.rule:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 34)
	card.rule:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 34)
	card.state = Skin.Text(card, "GameTooltipTextSmall", "good")
	card.state:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 13)
	card.state:SetPoint("RIGHT", card, "RIGHT", -62, 0)
	card.state:SetJustifyH("LEFT")
	if card.state.SetWordWrap then card.state:SetWordWrap(false) end
	card.power = Skin.Text(card, "GameFontNormal", "gold")
	card.power:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 12)
	card.powerIcon = card:CreateTexture(nil, "ARTWORK")
	card.powerIcon:SetSize(13, 13)
	card.powerIcon:SetPoint("RIGHT", card.power, "LEFT", -3, 0)
	card.powerIcon:SetTexture("Interface\\Icons\\Ability_Warrior_BattleShout")
	ns.Crop(card.powerIcon)
	card.road = card:CreateTexture(nil, "ARTWORK")
	card.road:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 30)
	card.road:SetHeight(3)
	card.road:SetColorTexture(Skin.COLORS.blue[1], Skin.COLORS.blue[2], Skin.COLORS.blue[3], 0.8)
	card.xp = ns.UI.Bar(card, 3, 1, 1, 1)
	card:SetScript("OnClick", function(self)
		Skin.Play("click")
		if self.companion then ns.ShowPage("companion", self.companion.id) end
	end)
	Skin.Tooltip(card, function(self)
		local companion = self.companion
		if not companion then return nil end
		local lines = { ns.CompanionName(companion), ns.CompanionKind(companion) .. "  " .. ns.RarityName(companion.rarity) }
		for _, ability in ipairs(ns.AbilitiesOf(companion)) do
			lines[#lines + 1] = ns.InlineIcon(ns.SpellIcon(ability.spell)) .. " " .. ns.SpellName(ability.spell) .. "  "
				.. Skin.Colorize(L.COUNTERS:format(L["THREAT_" .. ability.counters:upper()]), "muted")
		end
		local _, _, _, where = Doing(companion)
		if where then lines[#lines + 1] = Skin.Colorize(where, "blue") end
		lines[#lines + 1] = Skin.Colorize(L.SHEET_OPEN, "muted")
		return lines
	end)
	return card
end

local function FillCard(card, companion, width)
	card.companion = companion
	card:SetWidth(width)
	local color = ns.ClassColor(companion.class)
	ns.Gradient(card.glow, true, color[1], color[2], color[3], 0, color[1], color[2], color[3], 0.16)
	card.accent:SetColorTexture(color[1], color[2], color[3], 0.8)
	local busy, hurt = ns.Busy(companion), ns.Hurt(companion)
	card.portrait:Set(companion, { hurt = hurt })
	card.name:SetText(companion.name)
	card.name:SetTextColor(color[1], color[2], color[3])
	card.kind:SetText(ns.CompanionKind(companion))
	ns.RoleSign(card.role, companion.role)
	card.roleText:SetText(L["ROLE_" .. companion.role:upper()])
	local abilities = ns.AbilitiesOf(companion)
	for index, skill in ipairs(card.skills) do
		local ability = abilities[#abilities - index + 1]
		skill:SetShown(ability ~= nil)
		if ability then skill:SetTexture(ns.SpellIcon(ability.spell)) end
	end
	local words, tone, road = Doing(companion)
	card.state:SetText(words)
	card.state:SetTextColor(tone[1], tone[2], tone[3])
	card.power:SetText(math.floor(ns.Power(companion) + 0.5))
	card.road:SetShown(busy and road ~= nil)
	if road then card.road:SetWidth(math.max(1, (width - 20) * math.max(0, math.min(1, road)))) end
	local top = companion.level >= ns.LevelCap()
	card.xp:Set(not top and (companion.xp or 0) / math.max(1, ns.XPNeed(companion.level)) or nil)
	-- (a champion's crown, a veteran's mark; a talent waiting: a dot)
	local due = ns.TalentDue(companion) ~= nil
	card.dot:SetShown(due)
	card.mark:SetShown(not due and (companion.champion or companion.veteran) and true or false)
	card.mark:SetTexture(companion.champion and "Interface\\GroupFrame\\UI-Group-LeaderIcon" or "Interface\\GroupFrame\\UI-Group-AssistantIcon")
	card:SetAlpha(busy and 0.82 or 1)
end

-- Two cards side by side, in the list.
local function NewPair(list)
	local pair = CreateFrame("Frame", nil, list)
	pair.cards = { NewCard(pair), NewCard(pair) }
	pair.cards[1]:SetPoint("TOPLEFT")
	pair.cards[2]:SetPoint("TOPRIGHT")
	return pair
end

local function Breathe()
	local glow = ns.UI.Glow()
	for _, pair in ipairs(view.pairs) do
		for _, card in ipairs(pair.cards) do if card.dot:IsShown() then card.dot:SetAlpha(glow) end end
	end
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	-- Who is where: by the fire, away, wounded.
	local free, away, hurt = 0, 0, 0
	for _, companion in ipairs(s.companions) do
		if ns.Busy(companion) then away = away + 1 elseif ns.Hurt(companion) then hurt = hurt + 1 else free = free + 1 end
	end
	ns.Tip(list, "companions")
	list:Caption(L.TAB_COMPANIONS, L.COMPANIONS_COUNT:format(ns.CompanionCount(), ns.MaxCompanions()))
	if #s.companions == 0 then
		list:Text(L.COMPANIONS_EMPTY, "muted")
	else
		list:Text(L.ROSTER_LINE:format(free, away, hurt), "muted")
	end
	local width = (list.width - 8) / 2
	local index, due = 0, false
	for at = 1, #s.companions, 2 do
		index = index + 1
		local pair = view.pairs[index]
		if not pair then
			pair = NewPair(list)
			view.pairs[index] = pair
		end
		for side = 1, 2 do
			local companion = s.companions[at + side - 1]
			pair.cards[side]:SetShown(companion ~= nil)
			if companion then
				FillCard(pair.cards[side], companion, width)
				due = due or ns.TalentDue(companion) ~= nil
			end
		end
		list:Put(pair, CARD_HEIGHT, 8)
	end
	view.frame:SetScript("OnUpdate", due and Breathe or nil)
	-- The candidates.
	list:Caption(L.CANDIDATES)
	local can, why = ns.CanRecruit()
	local candidates = ns.Candidates() -- (first: a new draw sets the next one's time)
	local nextDraw = s.candidatesAt and (s.candidatesAt + ns.CANDIDATES_EVERY - time()) or 0
	list:Text((why == "full" and L.RECRUIT_FULL or L.RECRUIT_COST:format(ns.Number(ns.RecruitCost()))) .. "\n" .. L.CANDIDATES_NEW:format(ns.Left(nextDraw)), "muted")
	for _, candidate in ipairs(candidates) do
		-- (one may be kept through the next draws: a click on its row; a contract's recruit stays anyway)
		local held = candidate.held == true
		local spec = ns.CompanionRow(candidate, { sub = (held and (Skin.Colorize(L.CANDIDATE_KEPT, "gold") .. ", ") or "") .. ns.CompanionKind(candidate) .. "\n"
			.. ns.RoleText(candidate.role, 13) .. " "
			.. L["ROLE_" .. candidate.role:upper()] .. ", " .. L.LEVEL_SHORT:format(candidate.level) .. ", " .. L["TRAIT_" .. candidate.trait:upper()]
			.. "\n" .. ns.AbilityWords(candidate), wrap = true, chosen = held, plain = true,
			chip = ns.RarityName(candidate.rarity, true), tone = ({ [3] = "blue", [4] = "gold" })[candidate.rarity or 2] or "green",
			tip = { candidate.name, L["TRAIT_" .. candidate.trait:upper()] .. ": " .. L["TRAIT_" .. candidate.trait:upper() .. "_DESC"],
				not candidate.kept and (held and L.CANDIDATE_LET_GO or L.CANDIDATE_KEEP) or nil },
			onClick = not candidate.kept and function()
				ns.HoldCandidate(candidate)
				ns.Redraw()
			end or nil,
			action = { text = L.RECRUIT, enabled = can and true or false, fn = function()
				if ns.Recruit(candidate) then ns.Redraw() end
			end } })
		list:Row(spec)
	end
	list:Done()
end

local function Build(page)
	view.frame = page
	view.list = ns.UI.List(page)
	view.pairs = {}
	page:HookScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
end

ns.AddPage("companions", L.TAB_COMPANIONS, Build, Draw, { tab = 3, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
	badge = function()
		return ns.TalentWaiting()
	end })

-- A companion's sheet ---------------------------------------------------------------------------------------------

local HERO = 300
local SLOT_SIZE = 38
local EMPTY = {
	head = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", shoulder = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
	chest = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", hands = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
	legs = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs", feet = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
	weapon = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
}
-- (the slots' names: the game's own words)
local SLOT_WORDS = { head = "INVTYPE_HEAD", shoulder = "INVTYPE_SHOULDER", chest = "INVTYPE_CHEST", hands = "INVTYPE_HAND",
	legs = "INVTYPE_LEGS", feet = "INVTYPE_FEET", weapon = "INVTYPE_WEAPONMAINHAND" }
function ns.SlotName(slot) return _G[SLOT_WORDS[slot]] end
local LEFT_SLOTS, RIGHT_SLOTS = { "head", "shoulder", "chest", "weapon" }, { "hands", "legs", "feet" }
local leaf = "stats"

local function Percent(value)
	local whole = math.floor(value * 100 + 0.5)
	return (whole > 0 and "+" or "") .. whole .. " %"
end

-- A piece's square: its icon in its quality's edge (empty: the game's empty slot); hovered, what it is.
local function NewSlot(parent, slot)
	local square = Skin.Icon(parent, SLOT_SIZE)
	square.slot = slot
	square:EnableMouse(true)
	square:SetScript("OnEnter", function(self)
		local companion = ns.Companion(ns.CurrentArg())
		local item = companion and companion.items and companion.items[slot]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not item then
			GameTooltip:AddLine(ns.SlotName(slot), GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine(L.SLOT_EMPTY, 1, 1, 1, true)
		else
			local piece = ns.GEAR_ITEM[item] or {}
			local r, g, b = U.QualityColor(piece.quality or 1)
			GameTooltip:AddLine(ns.PieceName(item) or "...", r or 1, g or 1, b or 1)
			GameTooltip:AddLine(L.ITEM_LEVEL:format(piece.level or 0), GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine(ns.SlotName(slot), 1, 1, 1)
			local from = companion.found and companion.found[slot]
			if from ~= false then
				GameTooltip:AddLine(from == "week" and L.FROM_WEEK or from and L.FOUND_AT:format(ns.PlaceName(from)) or L.FIRST_GEAR, MUTED[1], MUTED[2], MUTED[3], true)
			end
		end
		GameTooltip:AddLine(L.SLOT_ARMORY, MUTED[1], MUTED[2], MUTED[3], true)
		GameTooltip:Show()
	end)
	square:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- (clicked: what the armory holds for this slot)
	square:SetScript("OnMouseUp", function(self, button)
		if button ~= "LeftButton" or not self:IsMouseOver() then return end
		Skin.Play("click")
		ns.ShowPage("armory", { id = ns.CurrentArg(), slot = slot })
	end)
	return square
end

local function FillSlot(square, companion)
	local item = companion.items and companion.items[square.slot]
	if item then
		local piece = ns.GEAR_ITEM[item] or {}
		square:Set(ns.PieceIcon(item), piece.quality)
		ns.Crop(square.texture)
		square.texture:SetAlpha(1)
		ns.PieceName(item) -- (asked now: its name ready when hovered)
	else
		square:Set(EMPTY[square.slot])
		square.texture:SetTexCoord(0, 1, 0, 1)
		square.texture:SetAlpha(0.6)
	end
end

-- A statistic's tile: its icon, its name, its value (muted when nothing).
local function NewTile(parent)
	local tile = CreateFrame("Frame", nil, parent)
	tile.ground = tile:CreateTexture(nil, "BACKGROUND")
	tile.ground:SetAllPoints()
	tile.ground:SetColorTexture(1, 1, 1, 0.03)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetSize(18, 18)
	tile.icon:SetPoint("LEFT", tile, "LEFT", 8, 0)
	ns.Crop(tile.icon)
	tile.label = Skin.Text(tile, "GameTooltipTextSmall", "soft")
	tile.label:SetPoint("LEFT", tile.icon, "RIGHT", 8, 0)
	tile.value = Skin.Text(tile, "GameFontHighlight", "text")
	tile.value:SetPoint("RIGHT", tile, "RIGHT", -10, 0)
	tile.label:SetPoint("RIGHT", tile.value, "LEFT", -6, 0)
	tile.label:SetJustifyH("LEFT")
	if tile.label.SetWordWrap then tile.label:SetWordWrap(false) end
	tile:EnableMouse(true)
	Skin.Tooltip(tile, function(self) return self.tip end)
	return tile
end

-- What a companion brings to an expedition, beyond their strength (their trait and talents).
local STATS = {
	{ key = "success", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
	{ key = "rewards", icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ key = "trophy", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04" },
	{ key = "duration", icon = "Interface\\Icons\\Spell_Nature_Swiftness" },
	{ key = "injury", icon = "Interface\\Icons\\Spell_Holy_Heal" },
	{ key = "provisions", icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ key = "xp", icon = "Interface\\Icons\\INV_Misc_Book_11" },
	{ key = "party", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
}

local function DrawStats(companion, list)
	-- Their strength and gear, then the rest, as tiles two by two.
	local grid = profile.grid
	local width = (list.width - 6) / 2
	local values = {
		{ "Interface\\Icons\\Ability_Warrior_BattleShout", L.STAT_POWER, tostring(math.floor(ns.Power(companion) + 0.5)), L.STAT_POWER_DESC:format(companion.level,
			Percent(ns.GearFactor(companion) - 1), Percent(ns.GEAR_POWER * (companion.gear or 0)), Percent(ns.Effect(companion, "power"))) },
		{ "Interface\\Icons\\INV_Chest_Chain_05", L.STAT_ILVL, tostring(math.floor(ns.ItemLevel(companion) + 0.5)), L.STAT_ILVL_DESC },
	}
	for _, stat in ipairs(STATS) do
		local value
		if stat.key == "party" then
			value = ns.Effect(companion, "partyXp") + ns.Effect(companion, "partyInjury")
		else
			value = ns.Effect(companion, stat.key)
		end
		values[#values + 1] = { stat.icon, L["STAT_" .. stat.key:upper()], value ~= 0 and Percent(value) or nil, L["STAT_" .. stat.key:upper() .. "_DESC"] }
	end
	for index, entry in ipairs(values) do
		local tile = grid.tiles[index]
		if not tile then
			tile = NewTile(grid)
			grid.tiles[index] = tile
		end
		local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", grid, "TOPLEFT", column * (width + 6), -row * 36)
		tile:SetSize(width, 32)
		tile.icon:SetTexture(entry[1])
		tile.label:SetText(entry[2])
		tile.value:SetText(entry[3] or "0 %")
		local c = entry[3] and (index <= 2 and Skin.COLORS.gold or Skin.COLORS.good) or Skin.COLORS.muted
		tile.value:SetTextColor(c[1], c[2], c[3])
		tile.icon:SetDesaturated(entry[3] == nil)
		tile.tip = { entry[2], entry[4] }
		tile:Show()
	end
	for index = #values + 1, #grid.tiles do grid.tiles[index]:Hide() end
	list:Put(grid, math.ceil(#values / 2) * 36, 6)
	-- Their abilities: what each counters.
	list:Caption(L.ABILITIES, ns.RarityName(companion.rarity))
	for _, ability in ipairs(ns.AbilitiesOf(companion)) do
		local threat = ns.THREAT[ability.counters]
		list:Row({ icon = ns.SpellIcon(ability.spell), title = ns.SpellName(ability.spell), color = Skin.COLORS.text,
			sub = ns.InlineIcon(threat.icon) .. " " .. L.COUNTERS:format(L["THREAT_" .. ability.counters:upper()]),
			tip = ns.ThreatTip(ability.counters), height = 46 })
	end
	-- Their promotion: the next rarity, what it asks.
	local rank = ns.NextRarity(companion)
	if rank then
		local rule = ns.PROMOTE[rank]
		local can, why = ns.CanPromote(companion)
		local needs = L.PROMOTE_NEEDS:format(rule.level, rule.roads) .. "\n" .. ns.Amount("renown", rule.renown) .. "   " .. ns.Amount("supplies", rule.supplies)
		list:Row({ icon = "Interface\\Icons\\Spell_Holy_ChampionsBond", quality = rank, title = L.PROMOTE:format(ns.RarityName(rank, true)),
			color = Skin.COLORS.gold, sub = needs, wrap = true,
			tip = { L.PROMOTE:format(ns.RarityName(rank, true)), L.PROMOTE_DESC, why and why ~= "top" and L["PROMOTE_WHY_" .. why:upper()] or nil },
			action = { text = L.PROMOTE_BUTTON, enabled = can and true or false, fn = function()
				if ns.Promote(companion) then
					ns.UI.Flash(profile.hero, 0.25)
					ns.Redraw()
				end
			end } })
	end
	-- Their trait.
	local trait = companion.trait:upper()
	list:Caption(L.TRAIT)
	list:Row({ icon = "Interface\\Icons\\INV_Misc_Note_01", title = L["TRAIT_" .. trait], color = GOLD, sub = L["TRAIT_" .. trait .. "_DESC"], wrap = true })
	-- The forge: their gear reinforced.
	list:Caption(L.FORGE_REINFORCE, L.REINFORCE_LEVEL:format(companion.gear or 0, ns.GEAR_MAX))
	local can, why = ns.CanForge(companion)
	local embers, supplies = ns.GearCost(companion)
	list:Row({ icon = "Interface\\Icons\\Trade_BlackSmithing", title = why == "top" and L.FORGE_TOP or L.REINFORCE_NEXT:format((companion.gear or 0) + 1),
		sub = why ~= "top" and (why == "forge" and L.FORGE_NEEDS or ns.Amount("embers", embers) .. "   " .. ns.Amount("supplies", supplies)) or nil, wrap = true,
		action = why ~= "top" and { text = L.FORGE_BUTTON, enabled = can and true or false,
			fn = function()
				if ns.Forge(companion) then ns.Redraw() end
			end } or nil })
end

local function DrawTalents(companion, list)
	list:Caption(L.TALENTS)
	if companion.talents and companion.talents[1] then
		for at, key in ipairs(companion.talents) do
			list:Row({ icon = "Interface\\Icons\\Ability_Marksmanship", title = L["TALENT_" .. key:upper()], color = GOLD,
				sub = L["TALENT_" .. key:upper() .. "_DESC"], wrap = true, chip = L.LEVEL_SHORT:format(ns.TALENT_LEVELS[at]), tone = "gold" })
		end
	end
	local tier = ns.TalentDue(companion)
	if tier then
		list:Text(L.TALENT_CHOOSE, "gold")
		for _, talent in ipairs(ns.TALENTS[companion.role][tier]) do
			list:Row({ icon = "Interface\\Icons\\INV_Misc_Book_09", title = L["TALENT_" .. talent.key:upper()], sub = L["TALENT_" .. talent.key:upper() .. "_DESC"], wrap = true,
				action = { text = L.CHOOSE, fn = function()
					if ns.ChooseTalent(companion, talent.key) then ns.Redraw() end
				end } })
		end
	else
		local coming = ns.TALENT_LEVELS[#(companion.talents or {}) + 1]
		if coming then list:Text(L.TALENT_NEXT:format(coming), "muted") end
	end
end

local function DrawJourney(companion, list)
	local record = companion.record or {}
	list:Caption(L.JOURNEY)
	local done, won = record.expeditions or 0, record.won or 0
	local lines = {
		{ "Interface\\Icons\\INV_Misc_Map_01", L.JOURNEY_ROADS, done > 0 and L.JOURNEY_ROADS_LINE:format(done, won, math.floor(won / done * 100 + 0.5)) or L.JOURNEY_NONE },
		{ "Interface\\Icons\\Spell_Holy_SurgeOfLight", L.JOURNEY_LEVELS, tostring(record.levels or 0) },
		{ "Interface\\Icons\\INV_Chest_Chain_05", L.JOURNEY_ITEMS, tostring(record.items or 0) },
	}
	if record.since then lines[#lines + 1] = { "Interface\\Icons\\Spell_Fire_Fire", L.JOURNEY_SINCE, date("%x", record.since) } end
	-- (the one they went with most)
	local bonds, best, shared = ns.State().bonds, nil, 0
	for _, other in ipairs(ns.State().companions) do
		if other.id ~= companion.id then
			local count = bonds[ns.BondKey(other.id, companion.id)] or 0
			if count > shared then best, shared = other, count end
		end
	end
	if best then lines[#lines + 1] = { "Interface\\Icons\\INV_ValentinesCard02", L.JOURNEY_BOND, L.JOURNEY_BOND_LINE:format(best.name, shared) } end
	for _, line in ipairs(lines) do list:Row({ icon = line[1], title = line[2], sub = line[3], height = 46 }) end
	-- Parted with (free, and not a champion).
	if not ns.Busy(companion) and not companion.champion then
		list:Gap(10)
		list:Put(profile.dismiss, 30, 0)
	end
end

local function DrawProfile(id)
	local companion = ns.Companion(id)
	if not companion then return ns.GoBack() end
	local hero = profile.hero
	local color = ns.ClassColor(companion.class)
	ns.Gradient(hero.glow, true, color[1], color[2], color[3], 0.2, color[1], color[2], color[3], 0)
	hero.name:SetText(ns.CompanionName(companion))
	hero.name:SetTextColor(color[1], color[2], color[3])
	hero.kind:SetText(L.LEVEL_SHORT:format(companion.level) .. DOT .. ns.RarityName(companion.rarity) .. " " .. ns.CompanionKind(companion) .. DOT
		.. ns.RoleText(companion.role, 13) .. " " .. L["ROLE_" .. companion.role:upper()])
	hero.state:SetText(State(companion))
	hero.power:SetText(math.floor(ns.Power(companion) + 0.5))
	-- Standing between their gear (a portrait when the game cannot stand them up).
	local standing = false
	if hero.figure then
		if hero.figure.shown3D == companion.look and hero.figure:IsShown() then standing = true else standing = hero.figure:Show3D(companion) end
	end
	hero.portrait:SetShown(not standing)
	if not standing then hero.portrait:Set(companion) end
	for _, square in ipairs(hero.slots) do FillSlot(square, companion) end
	-- Their experience.
	local top = companion.level >= ns.LevelCap()
	local need = ns.XPNeed(companion.level)
	hero.bar:Set(top and 1 or (companion.xp or 0) / math.max(1, need))
	hero.xp:SetText(top and L.XP_TOP or L.XP_LINE:format(companion.xp or 0, need))
	hero.ilvl:SetText(L.ITEM_LEVEL:format(math.floor(ns.ItemLevel(companion) + 0.5)))
	-- The leaves.
	profile.leaves:Select(leaf)
	local list = profile.list
	list:Begin()
	ns.Tip(list, "sheet")
	if leaf == "talents" then DrawTalents(companion, list) elseif leaf == "journey" then DrawJourney(companion, list) else DrawStats(companion, list) end
	list:Done()
end

local function BuildHero(page)
	local hero = CreateFrame("Frame", nil, page)
	hero:SetPoint("TOPLEFT")
	hero:SetSize(page.width, HERO)
	hero.ground = hero:CreateTexture(nil, "BACKGROUND")
	hero.ground:SetAllPoints()
	hero.ground:SetColorTexture(0.03, 0.025, 0.02, 0.6)
	hero.glow = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
	hero.glow:SetPoint("BOTTOMLEFT")
	hero.glow:SetPoint("BOTTOMRIGHT")
	hero.glow:SetHeight(HERO * 0.7)
	Skin.Edges(hero, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.12)
	hero.name = Skin.CreateText(hero, "GameFontNormalLarge")
	hero.name:SetPoint("TOPLEFT", hero, "TOPLEFT", 14, -12)
	hero.name:SetPoint("RIGHT", hero, "RIGHT", -90, 0)
	hero.name:SetJustifyH("LEFT")
	if hero.name.SetWordWrap then hero.name:SetWordWrap(false) end
	hero.kind = Skin.Text(hero, "GameTooltipTextSmall", "soft")
	hero.kind:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -5)
	hero.kind:SetPoint("RIGHT", hero, "RIGHT", -12, 0)
	hero.kind:SetJustifyH("LEFT")
	if hero.kind.SetWordWrap then hero.kind:SetWordWrap(false) end
	hero.state = Skin.Text(hero, "GameTooltipTextSmall", "muted")
	hero.state:SetPoint("TOPLEFT", hero.kind, "BOTTOMLEFT", 0, -4)
	hero.state:SetPoint("RIGHT", hero, "RIGHT", -12, 0)
	hero.state:SetJustifyH("LEFT")
	if hero.state.SetWordWrap then hero.state:SetWordWrap(false) end
	-- Their strength, at the top right.
	hero.power = Skin.Text(hero, "GameFontNormalHuge", "gold")
	hero.power:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -14, -12)
	hero.powerWord = Skin.Caps(hero, L.STAT_POWER)
	hero.powerWord:SetPoint("TOPRIGHT", hero.power, "BOTTOMRIGHT", 0, -3)
	-- The gear: four pieces on the left, three on the right.
	hero.slots = {}
	for index, slot in ipairs(LEFT_SLOTS) do
		local square = NewSlot(hero, slot)
		square:SetPoint("TOPLEFT", hero, "TOPLEFT", 12, -70 - (index - 1) * (SLOT_SIZE + 8))
		hero.slots[#hero.slots + 1] = square
	end
	for index, slot in ipairs(RIGHT_SLOTS) do
		local square = NewSlot(hero, slot)
		square:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -12, -70 - (index - 1) * (SLOT_SIZE + 8))
		hero.slots[#hero.slots + 1] = square
	end
	-- Standing in the middle.
	hero.figure = ns.Figure(hero)
	if hero.figure then
		hero.figure:SetPoint("TOPLEFT", hero, "TOPLEFT", SLOT_SIZE + 22, -64)
		hero.figure:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -(SLOT_SIZE + 22), 44)
		Skin.Tooltip(hero.figure, L.FIGURE_TIP)
	end
	hero.portrait = ns.Portrait(hero, 120, false)
	hero.portrait:SetPoint("CENTER", hero, "CENTER", 0, -6)
	hero.portrait:Hide()
	-- Their experience, at the foot.
	hero.xp = Skin.Text(hero, "GameTooltipTextSmall", "soft")
	hero.xp:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 14, 22)
	hero.ilvl = Skin.Text(hero, "GameTooltipTextSmall", "gold")
	hero.ilvl:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -14, 22)
	hero.bar = ns.UI.Bar(hero, 5, 14, 14, 12)
	ns.Gradient(hero.bar.fill, false, 0.85, 0.45, 0.1, 0.95, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.95)
	return hero
end

local function BuildProfile(page)
	profile.width = page.width
	profile.hero = BuildHero(page)
	-- The leaves: statistics, talents, journey (as wide as the page).
	profile.leaves = Skin.Choices(page, { { "stats", L.LEAF_STATS }, { "talents", L.TALENTS }, { "journey", L.JOURNEY } }, function(key)
		leaf = key
		if profile.list then profile.list:Top() end
		ns.Redraw()
	end, 30)
	profile.leaves:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(HERO + 8))
	ns.UI.Fill(profile.leaves, page.width)
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(HERO + 46))
	holder.width, holder.height = page.width, page.height - HERO - 46
	holder:SetSize(holder.width, holder.height)
	profile.list = ns.UI.List(holder)
	page.list = profile.list
	profile.grid = CreateFrame("Frame", nil, profile.list)
	profile.grid.tiles = {}
	profile.dismiss = CreateFrame("Frame", nil, profile.list)
	profile.dismiss.button = Skin.Button(profile.dismiss, L.DISMISS, function()
		local companion = ns.Companion(ns.CurrentArg())
		if not companion then return end
		ns.Ask(L.DISMISS_ASK:format(companion.name), function()
			if ns.Dismiss(companion.id) then ns.Redraw() end -- (its sheet, still open, goes back by itself)
		end)
	end, nil, 140)
	profile.dismiss.button:SetPoint("CENTER")
	profile.dismiss:Hide()
end

ns.AddPage("companion", L.TAB_COMPANIONS, BuildProfile, DrawProfile, { parent = "companions",
	title = function(id)
		local companion = ns.Companion(id)
		return companion and companion.name or L.TAB_COMPANIONS
	end })
