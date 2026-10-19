local _, ns = ...
local L = ns.L

-- On the road: the expeditions away (where, who, back in how long), then the last ones back (won or lost,
-- what they brought; hovered: who was wounded, the levels gained, a trophy found).

local W = Wanderer

local view = {}

local function Names(ids)
	local names = {}
	for _, id in ipairs(ids) do
		local companion = ns.Companion(id)
		if companion then names[#names + 1] = companion.name end
	end
	return table.concat(names, ", ")
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	local all = {}
	for index, expedition in ipairs(s.expeditions) do all[index] = expedition end
	table.sort(all, function(a, b) return a.finish < b.finish end)
	list:Caption(L.RUNNING, L.ROAD_COUNT:format(#all, ns.Tier().slots))
	if #all == 0 then list:Text(L.RUNNING_EMPTY, "muted") end
	for _, expedition in ipairs(all) do
		local left = expedition.finish - time()
		local length = math.max(1, expedition.finish - (expedition.start or expedition.finish))
		list:Row({ icon = ns.KindIcon(expedition.kind), title = ns.PlaceName(expedition.area), sub = Names(expedition.members) .. "\n"
			.. (left > 0 and L.BACK_IN:format(ns.Left(left)) or L.BACK_NOW), wrap = true,
			chip = ns.KindName(expedition.kind), tone = "grey", bar = expedition.start and (1 - math.max(0, left) / length) or nil,
			tip = { ns.PlaceName(expedition.area), Names(expedition.members), L.CHANCE:format(math.floor(expedition.chance * 100 + 0.5)) } })
	end
	list:Caption(L.LOG)
	if #s.log == 0 then list:Text(L.LOG_EMPTY, "muted") end
	for _, told in ipairs(s.log) do
		local gains = { ns.Gains({ renown = told.renown, embers = told.embers, supplies = told.supplies }, true) }
		if told.trophy then gains[#gains + 1] = L["TROPHY_" .. told.trophy] end
		local tip = { ns.PlaceName(told.area), told.won and L.WON or L.LOST }
		if told.up then tip[#tip + 1] = L.LOG_UP:format(told.up) end
		if told.hurt and told.hurt[1] then tip[#tip + 1] = L.LOG_HURT:format(table.concat(told.hurt, ", ")) end
		list:Row({ title = ns.PlaceName(told.area) .. "   " .. W.Util.Colorize(date("%H:%M", told.at), 0.56, 0.53, 0.46),
			icon = ns.KindIcon(told.kind or "zone"), sub = table.concat(gains, "   "), wrap = true, chip = told.won and L.WON or L.LOST, tone = told.won and "green" or "red", tip = tip })
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("road", L.TAB_ROAD, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Misc_Map_01", desc = L.ROAD_DESC,
	summary = function()
		local count = #ns.State().expeditions
		if count > 0 then return L.ROAD_COUNT:format(count, ns.Tier().slots), "gold" end
	end })
