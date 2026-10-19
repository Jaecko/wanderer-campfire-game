local _, ns = ...
local L = ns.L

-- The companions' page, in a list that scrolls: those of the camp (their class's icon, their name in its
-- color, their role, level and trait, what they do now), each opening their own page; then the candidates
-- around the fire, to recruit. A companion's page: their trait, experience, gear and talents, better gear
-- from the forge, a talent to choose when one is due, and the way to dismiss them.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local ROLE_TONES = { tank = "blue", heal = "green", dps = "red" }
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local view, profile = {}, {}

-- A companion's class icon (a part of the game's sheet of them).
function ns.ClassIcon(file)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
	if not coords then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	local inset = 0.012
	return CLASS_ICONS, { coords[1] + inset, coords[2] - inset, coords[3] + inset, coords[4] - inset }
end

-- A companion's name, said with their title.
function ns.CompanionName(companion)
	if companion.champion then return L.CHAMPION_OF:format(companion.name) end
	if companion.veteran then return companion.name .. "  " .. U.Colorize("(" .. L.VETERAN .. ")", 0.56, 0.53, 0.46) end
	return companion.name
end

-- What a companion is: their class, level and trait.
function ns.CompanionLine(companion)
	return ns.ClassName(companion.class) .. ", " .. L.LEVEL_SHORT:format(companion.level) .. ", " .. L["TRAIT_" .. companion.trait:upper()]
end

-- A companion as a row of a list (for this page and the expeditions').
function ns.CompanionRow(companion, extra)
	local icon, coords = ns.ClassIcon(companion.class)
	local spec = { icon = icon, coords = coords, title = ns.CompanionName(companion), color = ns.ClassColor(companion.class),
		sub = ns.CompanionLine(companion), chip = L["ROLE_" .. companion.role:upper()], tone = ROLE_TONES[companion.role] }
	for key, value in pairs(extra or {}) do spec[key] = value end
	return spec
end

local function State(companion)
	if ns.Busy(companion) then
		for _, expedition in ipairs(ns.State().expeditions) do
			if expedition.id == companion.busy then return L.STATE_BUSY:format(ns.Left(expedition.finish - time())) end
		end
	end
	if ns.Hurt(companion) then return U.Colorize(L.STATE_HURT:format(ns.Left(companion.hurt - time())), 0.95, 0.54, 0.49) end
	local free = U.Colorize(L.STATE_FREE, 0.56, 0.88, 0.64)
	if ns.TalentDue(companion) then free = free .. ", " .. U.Colorize(L.TALENT_READY, 1, 0.82, 0) end
	return free
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	list:Caption(L.TAB_COMPANIONS, L.COMPANIONS_COUNT:format(ns.CompanionCount(), ns.MaxCompanions()))
	if #s.companions == 0 then list:Text(L.COMPANIONS_EMPTY, "muted") end
	for _, companion in ipairs(s.companions) do
		list:Row(ns.CompanionRow(companion, { sub = ns.CompanionLine(companion) .. "\n" .. State(companion), wrap = true,
			onClick = function() ns.ShowPage("companion", companion.id) end }))
	end
	-- The candidates.
	list:Caption(L.CANDIDATES)
	local can, why = ns.CanRecruit()
	local candidates = ns.Candidates() -- (first: a new draw sets the next one's time)
	local next = s.candidatesAt and (s.candidatesAt + ns.CANDIDATES_EVERY - time()) or 0
	list:Text((why == "full" and L.RECRUIT_FULL or L.RECRUIT_COST:format(ns.Number(ns.RecruitCost()))) .. "\n" .. L.CANDIDATES_NEW:format(ns.Left(next)), "muted")
	for index, candidate in ipairs(candidates) do
		local spec = ns.CompanionRow(candidate, { sub = ns.CompanionLine(candidate) .. ", " .. L["ROLE_" .. candidate.role:upper()],
			tip = { candidate.name, L["TRAIT_" .. candidate.trait:upper()] .. ": " .. L["TRAIT_" .. candidate.trait:upper() .. "_DESC"] },
			action = { text = L.RECRUIT, enabled = can and true or false, fn = function() if ns.Recruit(index) then ns.Redraw() end end } })
		spec.chip = nil -- (the role said in its line)
		list:Row(spec)
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("companions", L.TAB_COMPANIONS, Build, Draw, { tab = 3, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
	badge = function()
		for _, companion in ipairs(ns.State().companions) do if ns.TalentDue(companion) then return true end end
		return false
	end })

-- A companion's own page ------------------------------------------------------------------------------------

local function DrawProfile(id)
	local companion = ns.Companion(id)
	if not companion then return ns.GoBack() end
	local list = profile.list
	list:Begin()
	list:Row(ns.CompanionRow(companion, { sub = ns.CompanionLine(companion) .. "\n" .. State(companion), wrap = true, height = 62 }))
	-- What they are.
	local trait = companion.trait:upper()
	list:Text(U.Colorize(L["TRAIT_" .. trait], 1, 0.82, 0) .. "\n" .. L["TRAIT_" .. trait .. "_DESC"], "soft", "GameTooltipText")
	if companion.level < ns.LevelCap() then
		local need = ns.XPNeed(companion.level)
		list:Row({ title = L.XP_LINE:format(companion.xp or 0, need), height = 34, bar = (companion.xp or 0) / math.max(1, need) })
	end
	-- Their gear, from the forge.
	list:Caption(L.GEAR_LINE:format(companion.gear or 0))
	local can, why = ns.CanForge(companion)
	local embers, supplies = ns.GearCost(companion)
	list:Row({ icon = "Interface\\Icons\\Trade_BlackSmithing", title = why == "top" and L.FORGE_TOP or L.GEAR_LINE:format((companion.gear or 0) + 1),
		sub = why == "top" and nil or why == "forge" and L.FORGE_NEEDS or ns.Amount("embers", embers) .. "   " .. ns.Amount("supplies", supplies), wrap = true,
		action = why ~= "top" and { text = L.FORGE_BUTTON, enabled = can and true or false,
			fn = function() if ns.Forge(companion) then ns.Redraw() end end } or nil })
	-- Their talents: those chosen, the one due.
	list:Caption(L.TALENTS)
	if companion.talents and companion.talents[1] then
		for _, key in ipairs(companion.talents) do
			list:Row({ title = L["TALENT_" .. key:upper()], color = Skin.COLORS.gold, sub = L["TALENT_" .. key:upper() .. "_DESC"], wrap = true })
		end
	end
	local tier = ns.TalentDue(companion)
	if tier then
		list:Text(L.TALENT_CHOOSE, "gold")
		for _, talent in ipairs(ns.TALENTS[companion.role][tier]) do
			list:Row({ title = L["TALENT_" .. talent.key:upper()], sub = L["TALENT_" .. talent.key:upper() .. "_DESC"], wrap = true,
				action = { text = L.CHOOSE, fn = function() if ns.ChooseTalent(companion, talent.key) then ns.Redraw() end end } })
		end
	elseif not (companion.talents and companion.talents[1]) then
		list:Text(L.TALENTS_NONE, "muted")
	end
	-- Dismissed (free, and not a champion).
	if not ns.Busy(companion) and not companion.champion then
		list:Gap(10)
		list:Put(profile.dismiss, 30, 0)
	end
	list:Done()
end

local function BuildProfile(page)
	profile.list = ns.UI.List(page)
	profile.dismiss = CreateFrame("Frame", nil, profile.list)
	profile.dismiss.button = Skin.Button(profile.dismiss, L.DISMISS, function()
		local companion = ns.Companion(ns.CurrentArg())
		if not companion then return end
		Skin.Ask(L.DISMISS_ASK:format(companion.name), function()
			if ns.Dismiss(companion.id) then ns.GoBack() end
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
