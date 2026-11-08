local _, ns = ...

-- What the game says of your character, read only, never changed: its level, the zones it has explored (the
-- game's exploration achievement; else the zones it has been to since the addon came), its professions
-- and their skill, its exalted factions, what it carries (bags and bank), the classes' names and colors.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

function ns.PlayerLevel() return Clean(Safe(UnitLevel, "player")) or 1 end

-- An achievement done: true or false; nil when the game does not know it (then the zone is opened by going
-- there). Read again once a minute at most (the window asks often).
local achievements, achievementsAt = {}, 0
local function AchievementDone(id)
	if not (id and GetAchievementInfo) then return nil end
	if time() - achievementsAt > 60 then achievements, achievementsAt = {}, time() end
	if achievements[id] == nil then
		local found, _, _, done = Safe(GetAchievementInfo, id)
		achievements[id] = not Clean(found) and "unknown" or (Clean(done) and true or false)
	end
	local done = achievements[id]
	if done == "unknown" then return nil end
	return done
end

-- A zone open to expeditions, and why not when it is not ("explore": its achievement; "visit": go there).
function ns.ZoneOpen(zone)
	local done = AchievementDone(zone.achievement)
	if done then return true end
	-- (gone to: only a zone the game has no achievement for)
	if done == nil and ns.State().visited[zone.area] then return true end
	return false, done == nil and "visit" or "explore"
end

-- A place's name in your language (from the game), its number until the game has it.
function ns.PlaceName(area) return U.AreaName(area) or ("#" .. tostring(area)) end

-- Where you stand, kept: a zone of the list entered is a zone visited.
function ns.NoteVisit()
	local state = ns.State()
	local here = U.PlainName(Clean(Safe(GetRealZoneText)))
	if not here then return end
	for _, zone in ipairs(ns.ZONES) do
		if not state.visited[zone.area] and U.PlainName(U.AreaName(zone.area)) == here then state.visited[zone.area] = true end
	end
end

-- A kind of place's name (raids and dungeons: words every addon shares).
function ns.KindName(kind) return kind == "raid" and ns.L.RAIDS or kind == "dungeon" and ns.L.DUNGEONS or ns.L["KIND_" .. kind:upper()] end
-- One place's kind (a zone, a dungeon, a raid); a contract's reward, in words.
function ns.KindOne(kind) return ns.L["PLACE_" .. kind:upper()] end
function ns.ContractName(reward, desc) return ns.L["CONTRACT_" .. reward:upper() .. (desc and "_DESC" or "")] end

-- A place's key ("zone:12"); a place by its kind and area (open or not).
function ns.PlaceKey(place) return place.kind .. ":" .. place.area end
function ns.Place(kind, area)
	for _, place in ipairs(ns.Places()) do if place.kind == kind and place.area == area then return place end end
end

-- Every place as table rows, under its kind's title (zones, dungeons, raids).
function ns.PlaceRows()
	local rows, kind = {}, nil
	for _, place in ipairs(ns.Places()) do
		if place.kind ~= kind then
			kind = place.kind
			rows[#rows + 1] = { header = ns.KindName(kind) }
		end
		rows[#rows + 1] = place
	end
	return rows
end

-- Your professions: { key = skill } (the keys of Data.lua's PROFESSIONS).
function ns.Professions()
	local found = {}
	for _, known in ipairs(U.Professions()) do
		local profession = ns.PROFESSIONS[known.line or 0]
		if profession then found[profession.key] = known.rank end
	end
	return found
end

-- A faction: its name, and whether your character is exalted with it.
function ns.Faction(id)
	local name, standing = U.Faction(id)
	return name, standing == 8
end

-- How many of an item you have, bags and bank.
function ns.Carried(id) return U.ItemCount(id, true) end

-- A class's name and color (the game's).
function ns.ClassName(file)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return names and names[file] or file
end
function ns.ClassColor(file)
	local r, g, b = U.ClassColor(file)
	if not r then return W.Skin.COLORS.text end
	return { r, g, b }
end

-- Your real journey, heard: a quest handed in, fish caught, a dish cooked (only while a profession's window is
-- open), a boss killed in a dungeon or a raid. Each gives the camp its share (Game.lua: ns.Real).
function ns.ListenReal()
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_TURNED_IN", "LOOT_OPENED", "ENCOUNTER_END", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "QUEST_TURNED_IN" then
			ns.Real("quest")
		elseif event == "LOOT_OPENED" then
			if IsFishingLoot and Clean(Safe(IsFishingLoot)) then ns.Real("fish", Clean(Safe(GetNumLootItems)) or 1) end
		elseif event == "ENCOUNTER_END" then
			local _, _, _, _, success = ...
			if Clean(success) == 1 then
				local name, kind = Safe(GetInstanceInfo)
				kind = Clean(kind)
				if kind == "party" or kind == "raid" then ns.Real("boss", Clean(name)) end
			end
		elseif event == "TRADE_SKILL_SHOW" then
			pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
		elseif event == "TRADE_SKILL_CLOSE" then
			frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- (a recipe made at the cooking fire)
			local _, _, spell = ...
			local ui = C_TradeSkillUI
			local recipe = ui and ui.GetRecipeInfo and Safe(ui.GetRecipeInfo, Clean(spell))
			local profession = ui and ui.GetBaseProfessionInfo and Safe(ui.GetBaseProfessionInfo)
			if type(recipe) == "table" and type(profession) == "table" and Clean(profession.professionID) == 185 then
				ns.Real("cook")
			end
		end
		ns.SaySaid() -- (a place lived: said at once)
	end)
end
