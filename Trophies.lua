local _, ns = ...
local L = ns.L

-- The trophies, as a cabinet: how many in all and what they bring, then each place on a shelf of its own (its
-- name, lived or not), its three trophies side by side (a keepsake, a relic, a treasure): found, in their
-- colors; not yet, dark shapes.

local W = Wanderer
local Skin = W and W.Skin

local view = {}
local SHELF = 46
local TROPHY_ICONS = { "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", "Interface\\Icons\\INV_Misc_Idol_03",
	"Interface\\Icons\\INV_Misc_Gem_Diamond_02" }
function ns.TrophyIcon(tier) return TROPHY_ICONS[tier] or TROPHY_ICONS[1] end

local function NewShelf(list)
	local shelf = CreateFrame("Frame", nil, list)
	shelf.ground = shelf:CreateTexture(nil, "BACKGROUND")
	shelf.ground:SetAllPoints()
	shelf.ground:SetColorTexture(1, 1, 1, 0.03)
	shelf.board = shelf:CreateTexture(nil, "BORDER")
	shelf.board:SetPoint("BOTTOMLEFT", 0, 0)
	shelf.board:SetPoint("BOTTOMRIGHT", 0, 0)
	shelf.board:SetHeight(3)
	ns.Gradient(shelf.board, false, 0.35, 0.22, 0.1, 0.9, 0.5, 0.33, 0.15, 0.6)
	shelf.name = Skin.CreateText(shelf, "GameFontNormal")
	shelf.name:SetPoint("LEFT", shelf, "LEFT", 12, 4)
	shelf.name:SetPoint("RIGHT", shelf, "RIGHT", -120, 0)
	shelf.name:SetJustifyH("LEFT")
	if shelf.name.SetWordWrap then shelf.name:SetWordWrap(false) end
	shelf.note = Skin.Text(shelf, "GameTooltipTextSmall", "muted")
	shelf.note:SetPoint("TOPLEFT", shelf.name, "BOTTOMLEFT", 0, -2)
	shelf.items = {}
	for tier = 3, 1, -1 do
		local square = Skin.Icon(shelf, 30)
		square:SetPoint("RIGHT", shelf, "RIGHT", -10 - (3 - tier) * 36, 2)
		square:EnableMouse(true)
		Skin.Tooltip(square, function(self) return self.tip end)
		shelf.items[tier] = square
	end
	return shelf
end

local function Draw()
	local rows = ns.PlaceRows()
	local total = 0
	for _, place in ipairs(rows) do if place.area then total = total + 3 end end
	local count = ns.TrophyCount()
	local s = ns.State()
	local list = view.list
	list:Begin()
	list:Text(L.TROPHIES_COUNT:format(count, total) .. (count >= 10
		and ("   " .. L.PROF_REWARDS:format(math.floor(ns.TrophyBonus() * 100 + 0.5))) or ""), "gold", "GameTooltipText")
	list:Text(L.TROPHIES_INTRO, "soft")
	local used = 0
	for _, place in ipairs(rows) do
		if place.header then
			list:Caption(place.header)
		else
			used = used + 1
			local shelf = view.shelves[used]
			if not shelf then
				shelf = NewShelf(list)
				view.shelves[used] = shelf
			end
			local found, have = s.trophies[place.area] or {}, 0
			for tier = 1, 3 do
				local square = shelf.items[tier]
				local got = found[tier] and true or false
				if got then have = have + 1 end
				square:Set(ns.TrophyIcon(tier), got and (tier + 1) or nil)
				square.texture:SetVertexColor(got and 1 or 0.12, got and 1 or 0.11, got and 1 or 0.1)
				square.tip = { L["TROPHY_" .. tier], got and L.TROPHY_FOUND:format(ns.PlaceName(place.area)) or L.TROPHY_MISSING }
			end
			shelf.name:SetText(ns.PlaceName(place.area))
			local c = have == 3 and Skin.COLORS.gold or have > 0 and Skin.COLORS.text or Skin.COLORS.muted
			shelf.name:SetTextColor(c[1], c[2], c[3])
			shelf.note:SetText(have .. " / 3" .. ns.LivedMark(place.area))
			list:Put(shelf, SHELF, 4)
		end
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
	view.shelves = {}
end

ns.AddPage("trophies", L.TAB_TROPHIES, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", desc = L.TROPHIES_DESC,
	summary = function() return tostring(ns.TrophyCount()), "gold" end })
