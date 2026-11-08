local _, ns = ...
local L = ns.L

-- On the road: the expeditions away (where, who, back in how long), then the last ones back (won or lost,
-- what they brought, a trophy found; hovered: who was wounded, the levels gained; clicked: its report again).

local W = Wanderer
local Skin = W and W.Skin

local view = {}

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	ns.RunningRows(list)
	list:Caption(L.LOG)
	if #s.log == 0 then list:Text(L.LOG_EMPTY, "muted") end
	for _, told in ipairs(s.log) do
		local tip = { ns.PlaceName(told.area), told.won and L.WON or L.LOST }
		if told.up then tip[#tip + 1] = L.LOG_UP:format(told.up) end
		if told.hurt and told.hurt[1] then tip[#tip + 1] = L.LOG_HURT:format(table.concat(told.hurt, ", ")) end
		tip[#tip + 1] = L.REPORT_READ
		list:Row({ title = ns.PlaceName(told.area) .. "   " .. Skin.Colorize(date("%H:%M", told.at), "muted"),
			icon = ns.KindIcon(told.kind or "zone"), sub = ns.ToldGains(told), wrap = true, chip = told.won and L.WON or L.LOST, tone = told.won and "green" or "red", tip = tip,
			plain = true, onClick = function() ns.ShowReports({ told }, true) end })
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
