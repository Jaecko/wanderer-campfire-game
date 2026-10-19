local _, ns = ...
local L = ns.L

-- The quartermaster's orders: goods of the real world (by your professions, and some for anyone), how many
-- he asks, how many you have (bags and bank), what honoring brings. Honored, the goods stay yours.

local W = Wanderer
local U = W and W.Util

local view = {}

local function Draw()
	local list = view.list
	if not list then return end
	list:Begin()
	list:Text(L.ORDERS_INTRO, "soft")
	local all = ns.State().orders
	if #all == 0 then list:Text(L.ORDERS_EMPTY, "muted") end
	for _, order in ipairs(all) do
		local name, link, quality = U.ItemInfo(order.item)
		local have = ns.Carried(order.item)
		local state
		if order.done then
			state = U.Colorize(L.ORDER_DONE:format(ns.Left(order.done + ns.ORDER_AGAIN - time())), 0.56, 0.88, 0.64)
		else
			state = U.HaveNeed(have, order.count) .. "   " .. ns.Gains({ supplies = order.supplies, renown = order.renown }, true) .. "\n"
				.. U.Colorize(L.ORDER_LEFT:format(ns.Left(order.at + ns.ORDER_LIFE - time())), 0.56, 0.53, 0.46)
		end
		local can = ns.CanHonor(order)
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

-- (the names and icons the game sends a moment later: drawn again)
local names = CreateFrame("Frame")
names:SetScript("OnEvent", U and U.Debounce and U.Debounce(0.5, function() if view.list and view.list:IsVisible() then Draw() end end) or nil)
function ns.HearNames(on)
	if on then names:RegisterEvent("GET_ITEM_INFO_RECEIVED") else names:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

ns.AddPage("orders", L.TAB_ORDERS, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Misc_Note_01", desc = L.ORDERS_DESC,
	summary = function()
		local ready = 0
		for _, order in ipairs(ns.State().orders) do if ns.CanHonor(order) then ready = ready + 1 end end
		if ready > 0 then return L.ORDERS_READY:format(ready), "green" end
	end })
