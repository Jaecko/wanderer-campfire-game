local _, ns = ...
local L = ns.L

-- The camp's feats: done in gold, the others with how far they are.

local W = Wanderer
local Skin = W and W.Skin

local view = {}

local function Draw()
	local done = ns.State().feats
	local list = view.list
	list:Begin()
	list:Text(L.FEATS_INTRO, "soft")
	for _, feat in ipairs(ns.FEATS) do
		local finished = done[feat.key] ~= nil
		local have, need = ns.FeatProgress(feat)
		list:Row({ title = L["FEAT_" .. feat.key:upper()], color = finished and Skin.COLORS.gold or Skin.COLORS.text,
			icon = finished and "Interface\\Icons\\Ability_Warrior_BattleShout" or "Interface\\Icons\\INV_Misc_Note_01", grey = not finished,
			sub = ns.Number(math.min(have, need)) .. " / " .. ns.Number(need) .. "   " .. ns.Gains({ renown = feat.renown }, true),
			chip = finished and L.FEAT_DONE or nil, tone = "green", bar = not finished and math.min(1, have / math.max(1, need)) or nil, height = 46 })
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("feats", L.TAB_FEATS, Build, Draw, { parent = "more", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", desc = L.FEATS_DESC,
	summary = function()
		local count = 0
		for _ in pairs(ns.State().feats) do count = count + 1 end
		return count .. " / " .. #ns.FEATS, "grey"
	end })
