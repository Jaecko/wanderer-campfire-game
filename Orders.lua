local _, ns = ...
local L = ns.L

-- The quartermaster's orders: goods of the real world (by your professions, and some for anyone), how many
-- he asks, how many you have (bags and bank), what honoring brings. Honored, the goods stay yours.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view = {}

local function Draw()
	local list = view.orders
	local all = ns.State().orders
	local offset = list:Clamp(#all)
	for index, row in ipairs(list.rows) do
		local order = all[index + offset]
		local entry, values, action
		if order then
			local name, link, quality = U.ItemInfo(order.item)
			entry = { name = name or U.ItemName(order.item) or ("#" .. order.item), link = link, quality = quality or 1,
				icon = U.ItemIcon(order.item) }
			local have = ns.Carried(order.item)
			local state
			if order.done then
				state = U.Colorize(L.ORDER_DONE:format(ns.Left(order.done + ns.ORDER_AGAIN - time())), 0.56, 0.88, 0.64)
			else
				state = L.ORDER_REWARD:format(order.supplies, order.renown) .. "  "
					.. U.Colorize(L.ORDER_LEFT:format(ns.Left(order.at + ns.ORDER_LIFE - time())), 0.56, 0.53, 0.46)
			end
			values = { asked = order.count, have = order.done and "" or U.HaveNeed(have, order.count), reward = state }
			if ns.CanHonor(order) then action = function() if ns.Honor(order) then ns.Redraw() end end end
		end
		row:Fill(entry, false, values, order and L["SOURCE_" .. order.source:upper()], "blue", action and L.HONOR, action)
	end
	list.empty:SetShown(#all == 0)
end

local function Build(page)
	local intro = Skin.Text(page, "GameTooltipText", "soft")
	intro:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	intro:SetWidth(page.width)
	intro:SetJustifyH("LEFT")
	intro:SetText(L.ORDERS_INTRO)
	view.orders = Skin.Table(page, {
		width = page.width, rows = 5, rowHeight = 46, action = 100,
		columns = {
			{ key = "asked", title = L.COL_ASKED, width = 70 },
			{ key = "have", title = L.COL_HAVE, width = 90 },
			{ key = "reward", title = L.COL_REWARD, width = 340, justify = "LEFT" },
		},
		onClick = function() end, onDraw = Draw,
	})
	view.orders:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
	view.orders:Fit(18 + 5 * 46)
	view.orders.empty:SetText(L.ORDERS_EMPTY)
end

-- (the names and icons the game sends a moment later: drawn again)
local names = CreateFrame("Frame")
names:SetScript("OnEvent", U and U.Debounce and U.Debounce(0.5, function() if view.orders and view.orders:IsVisible() then Draw() end end) or nil)
function ns.HearNames(on)
	if on then names:RegisterEvent("GET_ITEM_INFO_RECEIVED") else names:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

ns.AddPage("orders", L.TAB_ORDERS, Build, Draw)
