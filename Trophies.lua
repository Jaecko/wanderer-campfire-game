local _, ns = ...
local L = ns.L

-- The trophies: three in every place (a keepsake, a relic, a treasure), the ones found in gold, how many in
-- all and what they bring.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local view = {}
local rows = {}

local function Gather()
	rows = ns.PlaceRows(function(place) return { area = place.area, name = ns.PlaceName(place.area), color = Skin.COLORS.soft } end)
end

local function Draw()
	Gather()
	local total = 0
	for _, entry in ipairs(rows) do if entry.area then total = total + 3 end end
	local count = ns.TrophyCount()
	view.count:SetText(L.TROPHIES_COUNT:format(count, total) .. (count >= 10
		and ("   " .. L.PROF_REWARDS:format(math.floor(count / 10) * ns.TROPHY_BONUS * 100)) or ""))
	local list = view.trophies
	local offset = list:Clamp(#rows)
	local trophies = ns.State().trophies
	for index, row in ipairs(list.rows) do
		local entry = rows[index + offset]
		local values
		if entry and entry.area then
			values = {}
			local found = trophies[entry.area] or {}
			for tier = 1, 3 do
				values["t" .. tier] = found[tier] and U.Colorize(L["TROPHY_" .. tier], 1, 0.82, 0)
					or U.Colorize(L.TROPHY_MISSING, unpack(Skin.COLORS.muted))
			end
		end
		row:Fill(entry, false, values)
	end
end

local function Build(page)
	view.count = Skin.Text(page, "GameTooltipText", "gold")
	view.count:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	local intro = Skin.Text(page, "GameTooltipTextSmall", "soft")
	intro:SetPoint("TOPLEFT", view.count, "BOTTOMLEFT", 0, -6)
	intro:SetWidth(page.width)
	intro:SetJustifyH("LEFT")
	intro:SetText(L.TROPHIES_INTRO)
	view.trophies = Skin.Table(page, {
		width = page.width, rows = 16, rowHeight = 24, icon = false,
		columns = {
			{ key = "t1", title = L.TROPHY_1, width = 150, justify = "LEFT" },
			{ key = "t2", title = L.TROPHY_2, width = 150, justify = "LEFT" },
			{ key = "t3", title = L.TROPHY_3, width = 150, justify = "LEFT" },
		},
		onClick = function() end, onDraw = Draw,
	})
	view.trophies:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
	view.trophies:Fit(page.height - 60)
end

ns.AddPage("trophies", L.TAB_TROPHIES, Build, Draw)
