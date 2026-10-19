local _, ns = ...
local L = ns.L

-- The trophies: three in every place (a keepsake, a relic, a treasure), the ones found in gold, how many in
-- all and what they bring.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view = {}

local function Draw()
	local rows = ns.PlaceRows(function(place) return place end)
	local total = 0
	for _, place in ipairs(rows) do if place.area then total = total + 3 end end
	local count = ns.TrophyCount()
	local trophies = ns.State().trophies
	local list = view.list
	list:Begin()
	list:Text(L.TROPHIES_COUNT:format(count, total) .. (count >= 10
		and ("   " .. L.PROF_REWARDS:format(math.floor(math.floor(count / 10) * ns.TROPHY_BONUS * 100 + 0.5))) or ""), "gold", "GameTooltipText")
	list:Text(L.TROPHIES_INTRO, "soft")
	for _, place in ipairs(rows) do
		if place.header then
			list:Caption(place.header)
		else
			local found, have = trophies[place.area] or {}, 0
			local parts = {}
			for tier = 1, 3 do
				if found[tier] then have = have + 1 end
				parts[tier] = found[tier] and U.Colorize(L["TROPHY_" .. tier], 1, 0.82, 0) or U.Colorize(L["TROPHY_" .. tier], unpack(Skin.COLORS.muted))
			end
			list:Row({ icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", grey = have == 0, title = ns.PlaceName(place.area), color = have == 3 and Skin.COLORS.gold or Skin.COLORS.text, sub = table.concat(parts, "  ·  "),
				chip = have .. " / 3", tone = have == 3 and "gold" or "grey", height = 46 })
		end
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("trophies", L.TAB_TROPHIES, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", desc = L.TROPHIES_DESC,
	summary = function() return tostring(ns.TrophyCount()), "gold" end })
