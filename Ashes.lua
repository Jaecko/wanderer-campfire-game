local _, ns = ...
local L = ns.L

-- Between two fires, and only then: the old fire is out, its ashes gathered. The whole window: what the ashes
-- do, how many there are to spend, the ashes' tree (each node, its level, what it does, its price, a button),
-- and at the foot the button that lights the new fire. The ashes not spent wait for the next time.

local W = Wanderer
local Skin = W and W.Skin

local view = {}

local function Percent(ashes) return math.floor(ashes * ns.ASH_BONUS * 100 + 0.5) end

-- What a node does at a level, in a few signs: the producers a new fire starts with, a share more or less, hours.
local function Effect(key, level)
	local function Share(value) return math.floor(value * 100 + 0.5) .. " %" end
	if key == "kindling" then
		local parts = {}
		for _, generator in ipairs(ns.GENERATORS) do
			local count = ns.KINDLING[generator.key]
			if count then parts[#parts + 1] = "|T" .. generator.icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. count * level end
		end
		return table.concat(parts, "  ")
	end
	if key == "breath" then return "+" .. Share(ns.BREATH * level) end
	if key == "fervor" then return "+" .. Share(ns.FERVOR * level) end
	if key == "memory" then return "-" .. Share(1 - (1 - ns.MEMORY) ^ level) end
	if key == "peddler" then return "-" .. Share(1 - (1 - ns.PEDDLER) ^ level) end
	if key == "slumber" then return L.HOURS:format(math.floor(ns.Offline() / 3600 - ns.SLUMBER / 3600 * (ns.AshLevel("slumber") - level))) end
	return tostring(level)
end

local function Draw()
	local s = ns.State()
	local list = view.list
	list:Begin()
	list:Text(L.ASH_OUT_TEXT, "soft", "GameTooltipText")
	list:Text(ns.Icon("ashes", 16) .. " " .. L.ASH_STATE:format(ns.Number(s.ashesTotal), Percent(s.ashesTotal), ns.Number(s.ashes)), "good", "GameTooltipText")
	list:Caption(L.ASH_TREE, ns.Amount("ashes", s.ashes))
	for _, node in ipairs(ns.ASH_TREE) do
		local key = node.key:upper()
		local level, cost = ns.AshLevel(node.key), ns.AshCost(node.key)
		local spec = { icon = node.icon, quality = 1, title = L["ASH_" .. key] .. "   " .. W.Util.Colorize(node.max and (level .. " / " .. node.max) or L.LEVEL_SHORT:format(level), 0.56, 0.53, 0.46),
			color = level > 0 and Skin.COLORS.gold or Skin.COLORS.text, sub = L["ASH_" .. key .. "_DESC"] .. "\n" .. (cost and L.ASH_NOW_NEXT:format(Effect(node.key, level), Effect(node.key, level + 1))
				or L.ASH_NOW:format(Effect(node.key, level))), wrap = true, bar = node.max and level / node.max or nil }
		if cost then
			local can = ns.CanBuyAsh(node.key)
			spec.chip, spec.tone = ns.Amount("ashes", cost), can and "gold" or "grey"
			spec.action = { text = L.ASH_BUY, enabled = can, fn = function() if ns.BuyAsh(node.key) then ns.Redraw() end end }
		else
			spec.chip, spec.tone = L.ASH_TOP, "green"
		end
		list:Row(spec)
	end
	list:Done()
end

local function Build(page)
	-- At the foot, the new fire.
	view.kindle = Skin.Button(page, L.ASH_KINDLE, function()
		ns.Kindle()
		ns.ShowPage("fire")
	end, "main", 240)
	view.kindle:SetHeight(42)
	view.kindle:SetPoint("BOTTOM", page, "BOTTOM", 0, 6)
	view.list = ns.UI.List(page, page.width, page.height - 62)
end

ns.AddPage("ashes", L.TAB_ASHES, Build, Draw, { screen = true, title = function() return L.ASH_OUT end })
