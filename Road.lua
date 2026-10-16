local _, ns = ...
local L = ns.L

-- On the road: the expeditions away (where, who, back in how long), then the last ones back (won or lost,
-- what they brought; hovered: who was wounded, the levels gained, a trophy found).

local W = Wanderer
local Skin = W and W.Skin

local view = {}

local function Names(ids)
	local names = {}
	for _, id in ipairs(ids) do
		local companion = ns.Companion(id)
		if companion then names[#names + 1] = companion.name end
	end
	return table.concat(names, ", ")
end

local function DrawRunning()
	local list = view.running
	local all = ns.State().expeditions
	table.sort(all, function(a, b) return a.finish < b.finish end)
	local offset = list:Clamp(#all)
	for index, row in ipairs(list.rows) do
		local expedition = all[index + offset]
		local entry, values
		if expedition then
			entry = { name = ns.PlaceName(expedition.area), color = W.Skin.COLORS.soft,
				tip = { ns.PlaceName(expedition.area), Names(expedition.members), L.CHANCE:format(math.floor(expedition.chance * 100 + 0.5)) } }
			values = { who = Names(expedition.members), back = L.BACK_IN:format(ns.Left(expedition.finish - time())) }
		end
		row:Fill(entry, false, values, expedition and ns.KindName(expedition.kind), "grey")
	end
	list.empty:SetShown(#all == 0)
end

local function DrawLog()
	local list = view.log
	local all = ns.State().log
	local offset = list:Clamp(#all)
	for index, row in ipairs(list.rows) do
		local told = all[index + offset]
		local entry, values
		if told then
			local gains = { L.LOG_GAINS:format(ns.Number(told.renown or 0), ns.Number(told.embers or 0)) }
			if told.supplies then gains[#gains + 1] = L.LOG_SUPPLIES:format(ns.Number(told.supplies)) end
			if told.trophy then gains[#gains + 1] = L["TROPHY_" .. told.trophy] end
			local tip = { ns.PlaceName(told.area), told.won and L.WON or L.LOST }
			if told.up then tip[#tip + 1] = L.LOG_UP:format(told.up) end
			if told.hurt and told.hurt[1] then tip[#tip + 1] = L.LOG_HURT:format(table.concat(told.hurt, ", ")) end
			entry = { name = ns.PlaceName(told.area), color = W.Skin.COLORS.soft, tip = tip }
			values = { gains = table.concat(gains, ", "), when = date("%H:%M", told.at) }
		end
		row:Fill(entry, false, values, told and (told.won and L.WON or L.LOST), told and (told.won and "green" or "red"))
	end
	list.empty:SetShown(#all == 0)
end

local function Draw()
	DrawRunning()
	DrawLog()
end

local function Build(page)
	local caption = Skin.Caps(page, L.RUNNING, "gold")
	caption:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	view.running = Skin.Table(page, {
		width = page.width, rows = 5, rowHeight = 32, icon = false, titles = false,
		columns = { { key = "who", width = 380, justify = "LEFT" }, { key = "back", width = 180, justify = "LEFT" } },
		onClick = function() end, onDraw = DrawRunning,
	})
	view.running:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
	view.running:Fit(5 * 32)
	view.running.empty:SetText(L.RUNNING_EMPTY)
	local caption2 = Skin.Caps(page, L.LOG, "gold")
	caption2:SetPoint("TOPLEFT", view.running, "BOTTOMLEFT", 0, -16)
	view.log = Skin.Table(page, {
		width = page.width, rows = 8, rowHeight = 30, icon = false, titles = false,
		columns = { { key = "gains", width = 420, justify = "LEFT" }, { key = "when", width = 70 } },
		onClick = function() end, onDraw = DrawLog,
	})
	view.log:SetPoint("TOPLEFT", caption2, "BOTTOMLEFT", 0, -6)
	view.log:Fit(8 * 30)
	view.log.empty:SetText(L.LOG_EMPTY)
end

ns.AddPage("road", L.TAB_ROAD, Build, Draw)
