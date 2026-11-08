local _, ns = ...
local L = ns.L

-- The week's goals: three of them (the same all week), each with how far it is; once all are done, a chest to
-- open (renown, supplies, a rare piece for the one it suits best). Renewed each Monday; a chest earned and not
-- opened stays, to open the week after.

local W = Wanderer
local Skin = W and W.Skin

local view = {}
local held -- what the chest held, said until the page is left
local ICONS = {
	won = ns.KindIcon("zone"), dungeons = ns.KindIcon("dungeon"), raids = ns.KindIcon("raid"),
	levels = "Interface\\Icons\\Spell_Holy_SurgeOfLight", gear = "Interface\\Icons\\INV_Chest_Chain_05",
	contracts = "Interface\\Icons\\INV_Misc_Note_02", orders = "Interface\\Icons\\INV_Crate_01", trophies = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
}

local function Draw()
	local week = ns.Week()
	local list = view.list
	list:Begin()
	list:Caption(L.WEEK, L.WEEK_LEFT:format(ns.Left(ns.WeekLeft())))
	list:Text(L.WEEK_INTRO, "soft")
	for _, goal in ipairs(week.goals) do
		local done = goal.done >= goal.count
		list:Row({ icon = ICONS[goal.key], title = L["WEEK_" .. goal.key:upper()]:format(goal.count), color = done and Skin.COLORS.gold or Skin.COLORS.text,
			sub = done and L.WEEK_DONE or nil, bar = math.min(1, goal.done / goal.count),
			chip = goal.done .. " / " .. goal.count, tone = done and "green" or "grey", height = 50 })
	end
	-- The chest.
	list:Gap(8)
	local chest = ns.WeekChest()
	-- (a chest earned last week and not opened: kept, to open when you like)
	if ns.WeekKept() then
		list:Row({ icon = "Interface\\Icons\\INV_Box_02", quality = 3, title = L.WEEK_KEPT, color = Skin.COLORS.gold,
			sub = ns.Gains({ renown = chest.renown, supplies = chest.supplies }, true) .. "\n" .. L.WEEK_KEPT_DESC, wrap = true,
			action = { text = L.OPEN, fn = function()
				held = ns.ClaimWeek(true)
				if held then ns.Redraw() end
			end } })
	end
	list:Row({ icon = "Interface\\Icons\\INV_Box_02", quality = 3, title = L.WEEK_CHEST, color = Skin.COLORS.gold,
		sub = ns.Gains({ renown = chest.renown, supplies = chest.supplies }, true) .. "\n" .. L.WEEK_CHEST_GEAR, wrap = true,
		chip = week.claimed and L.WEEK_OPENED or nil, tone = "green",
		action = not week.claimed and { text = L.OPEN, enabled = ns.WeekNowReady(), fn = function()
			held = ns.ClaimWeek(false)
			if held then ns.Redraw() end
		end } or nil })
	-- (what it held: the pieces' names as soon as the game has them)
	if held then
		local lines = { ns.Gains({ renown = held.renown, supplies = held.supplies }, true) }
		for _, found in ipairs(held.gear or {}) do lines[#lines + 1] = ns.PieceText(found.item) .. "  " .. ns.GearLine(found) end
		list:Text(table.concat(lines, "\n"), "good")
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
	page:HookScript("OnHide", function() held = nil end)
end

ns.AddPage("week", L.WEEK, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Box_02", desc = L.WEEK_DESC,
	summary = function() return ns.WeekSummary() end })
