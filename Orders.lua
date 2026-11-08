local _, ns = ...
local L = ns.L

-- The quartermaster's orders: goods of the real world (by your professions, and some for anyone), how many
-- he asks, how many you have (bags and bank), what honoring brings. Honored, the goods stay yours.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view = {}

local function Draw()
	local list = view.list
	list:Begin()
	list:Text(L.ORDERS_INTRO, "soft")
	local all = ns.State().orders
	if #all == 0 then list:Text(L.ORDERS_EMPTY, "muted") end
	for _, order in ipairs(all) do
		local name, link, quality = U.ItemInfo(order.item)
		local have = ns.Carried(order.item)
		local state
		if order.done then
			state = Skin.Colorize(L.ORDER_DONE:format(ns.Left(order.done + ns.ORDER_AGAIN - time())), "good")
		else
			state = U.HaveNeed(have, order.count) .. "   " .. ns.Gains({ supplies = order.supplies, renown = order.renown }, true) .. "\n"
				.. Skin.Colorize(L.ORDER_LEFT:format(ns.Left(order.at + ns.ORDER_LIFE - time())), "muted")
		end
		local can = not order.done and have >= order.count
		list:Row({ icon = U.ItemIcon(order.item), quality = quality or 1, link = link, tip = link and true or nil,
			title = (order.count > 1 and (order.count .. " x ") or "") .. (name or U.ItemName(order.item) or ("#" .. order.item)),
			color = { U.QualityColor(quality or 1) }, sub = state, wrap = true, chip = L["SOURCE_" .. order.source:upper()], tone = "blue",
			action = not order.done and { text = L.HONOR, enabled = can and true or false, fn = function() if ns.Honor(order) then ns.Redraw() end end } or nil,
			dim = order.done ~= nil })
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("orders", L.TAB_ORDERS, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Misc_Note_01", desc = L.ORDERS_DESC,
	summary = function()
		local ready = 0
		for _, order in ipairs(ns.State().orders) do if ns.CanHonor(order) then ready = ready + 1 end end
		if ready > 0 then return L.ORDERS_READY:format(ready), "green" end
	end })
