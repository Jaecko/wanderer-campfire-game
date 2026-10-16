local _, ns = ...
local L = ns.L

-- The companions' page: those of the camp (their class in its color, their role, level, trait and what they
-- do now; hovered: their trait and experience), then the candidates around the fire, to recruit.

local W = Wanderer
local Skin = W and W.Skin

local ROLE_TONES = { tank = "blue", heal = "green", dps = "red" }
local ROWS = 10
local view = {}

-- A companion as a row: its name in its class's color, its role's chip.
function ns.CompanionEntry(companion)
	local tip = { companion.name, ns.ClassName(companion.class) .. ", " .. L["ROLE_" .. companion.role:upper()],
		L["TRAIT_" .. companion.trait:upper()] .. ": " .. L["TRAIT_" .. companion.trait:upper() .. "_DESC"] }
	if companion.level < ns.LevelCap() then tip[#tip + 1] = L.XP_LINE:format(companion.xp or 0, ns.XPNeed(companion.level)) end
	if (companion.gear or 0) > 0 then tip[#tip + 1] = L.GEAR_LINE:format(companion.gear) end
	if companion.talents and companion.talents[1] then
		local names = {}
		for _, key in ipairs(companion.talents) do names[#names + 1] = L["TALENT_" .. key:upper()] end
		tip[#tip + 1] = L.TALENTS_LINE:format(table.concat(names, ", "))
	end
	local name = companion.name
	if companion.champion then
		name = L.CHAMPION_OF:format(companion.name)
	elseif companion.veteran then
		name = name .. "  " .. W.Util.Colorize("(" .. L.VETERAN .. ")", 0.56, 0.53, 0.46)
	end
	return { id = companion.id, companion = companion, name = name, color = ns.ClassColor(companion.class), tip = tip }
end

-- A companion's menu: better gear from the forge, a talent to choose, dismissed.
function ns.CompanionMenu(owner, companion)
	W.Util.Menu(owner, function(_, root)
		root:CreateTitle(companion.name)
		local can, why = ns.CanForge(companion)
		local label = why == "top" and L.FORGE_TOP or why == "forge" and L.FORGE_NEEDS
			or L.FORGE:format(ns.Number((ns.GearCost(companion))), ns.Number(select(2, ns.GearCost(companion))))
		local forge = root:CreateButton(label, function() if ns.Forge(companion) then ns.Redraw() end end)
		if not can and forge.SetEnabled then forge:SetEnabled(false) end
		local tier = ns.TalentDue(companion)
		if tier then
			local talents = root:CreateButton(L.TALENT_CHOOSE)
			for _, talent in ipairs(ns.TALENTS[companion.role][tier]) do
				talents:CreateButton(L["TALENT_" .. talent.key:upper()] .. ": " .. L["TALENT_" .. talent.key:upper() .. "_DESC"], function()
					if ns.ChooseTalent(companion, talent.key) then ns.Redraw() end
				end)
			end
		end
		if not ns.Busy(companion) and not companion.champion then
			root:CreateDivider()
			root:CreateButton(L.DISMISS, function()
				Skin.Ask(L.DISMISS_ASK:format(companion.name), function()
					if ns.Dismiss(companion.id) then ns.Redraw() end
				end)
			end)
		end
	end)
end

local function State(companion)
	if ns.Busy(companion) then
		for _, expedition in ipairs(ns.State().expeditions) do
			if expedition.id == companion.busy then return L.STATE_BUSY:format(ns.Left(expedition.finish - time())) end
		end
	end
	if ns.Hurt(companion) then return W.Util.Colorize(L.STATE_HURT:format(ns.Left(companion.hurt - time())), 0.95, 0.54, 0.49) end
	local free = W.Util.Colorize(L.STATE_FREE, 0.56, 0.88, 0.64)
	if ns.TalentDue(companion) then free = free .. ", " .. W.Util.Colorize(L.TALENT_READY, 1, 0.82, 0) end
	return free
end

local function DrawCompanions()
	local list = view.companions
	local all = ns.State().companions
	local offset = list:Clamp(#all)
	for index, row in ipairs(list.rows) do
		local companion = all[index + offset]
		local entry, values, action
		if companion then
			entry = ns.CompanionEntry(companion)
			values = { class = ns.ClassName(companion.class), level = companion.level, trait = L["TRAIT_" .. companion.trait:upper()],
				state = State(companion) }
			action = function() ns.CompanionMenu(row.action, companion) end
		end
		row:Fill(entry, false, values, companion and L["ROLE_" .. companion.role:upper()], companion and ROLE_TONES[companion.role],
			action and L.MANAGE, action)
	end
	list.empty:SetShown(#all == 0)
end

local function DrawCandidates()
	local list = view.candidates
	local candidates = ns.Candidates()
	list:Clamp(#candidates)
	local can = ns.CanRecruit()
	for index, row in ipairs(list.rows) do
		local candidate = candidates[index]
		local entry, values
		if candidate then
			entry = ns.CompanionEntry(candidate)
			values = { class = ns.ClassName(candidate.class), level = candidate.level, trait = L["TRAIT_" .. candidate.trait:upper()] }
		end
		row:Fill(entry, false, values, candidate and L["ROLE_" .. candidate.role:upper()], candidate and ROLE_TONES[candidate.role],
			can and candidate and L.RECRUIT, function() if ns.Recruit(index) then ns.Redraw() end end)
	end
end

local function Draw()
	view.count:SetText(L.COMPANIONS_COUNT:format(ns.CompanionCount(), ns.MaxCompanions()))
	DrawCompanions()
	local _, why = ns.CanRecruit()
	local next = ns.State().candidatesAt and (ns.State().candidatesAt + ns.CANDIDATES_EVERY - time()) or 0
	view.recruit:SetText((why == "full" and L.RECRUIT_FULL or L.RECRUIT_COST:format(ns.Number(ns.RecruitCost())))
		.. "   " .. L.CANDIDATES_NEW:format(ns.Left(next)))
	DrawCandidates()
end

local function Build(page)
	view.count = Skin.Text(page, "GameTooltipText", "label")
	view.count:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	local columns = {
		{ key = "class", title = L.CLASS, width = 120, justify = "LEFT" },
		{ key = "level", title = L.COL_LEVEL, width = 60 },
		{ key = "trait", title = L.COL_TRAIT, width = 120, justify = "LEFT" },
		{ key = "state", title = L.COL_STATE, width = 220, justify = "LEFT" },
	}
	view.companions = Skin.Table(page, {
		width = page.width, rows = ROWS, rowHeight = 30, icon = false, action = 100, columns = columns,
		onClick = function() end, onDraw = DrawCompanions,
	})
	view.companions:SetPoint("TOPLEFT", view.count, "BOTTOMLEFT", 0, -8)
	view.companions:Fit(18 + ROWS * 30)
	view.companions.empty:SetText(L.COMPANIONS_EMPTY)
	local caption = Skin.Caps(page, L.CANDIDATES, "gold")
	caption:SetPoint("TOPLEFT", view.companions, "BOTTOMLEFT", 0, -14)
	view.recruit = Skin.Text(page, "GameTooltipTextSmall", "muted")
	view.recruit:SetPoint("LEFT", caption, "RIGHT", 12, 0)
	view.candidates = Skin.Table(page, {
		width = page.width, rows = 3, rowHeight = 30, icon = false, titles = false, action = 100,
		columns = { columns[1], columns[2], columns[3], { key = "state", width = 220 } },
		onClick = function() end, onDraw = DrawCandidates,
	})
	view.candidates:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
	view.candidates:Fit(3 * 30)
end

ns.AddPage("companions", L.TAB_COMPANIONS, Build, Draw)
