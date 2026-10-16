local _, ns = ...
local L = ns.L

-- The camp's feats (done in gold, the others with how far they are), then a new start, from the outpost.

local W = Wanderer
local Skin = W and W.Skin

local view = {}

local function Draw()
	local list = view.feats
	local feats, done = ns.FEATS, ns.State().feats
	local offset = list:Clamp(#feats)
	for index, row in ipairs(list.rows) do
		local feat = feats[index + offset]
		local entry, values, chip, tone
		if feat then
			local finished = done[feat.key] ~= nil
			local have, need = ns.FeatProgress(feat)
			entry = { name = L["FEAT_" .. feat.key:upper()], color = finished and Skin.COLORS.gold or Skin.COLORS.soft }
			values = { progress = math.min(have, need) .. " / " .. need, reward = L.FEAT_REWARD:format(ns.Number(feat.renown)) }
			chip, tone = finished and L.FEAT_DONE or L.FEAT_TODO, finished and "green" or "grey"
		end
		row:Fill(entry, false, values, chip, tone)
	end
	local s = ns.State()
	view.restart:SetEnabled(ns.CanRestart())
	view.needs:SetText(ns.CanRestart() and "" or L.RESTART_NEEDS)
	view.prestige:SetText(s.prestige > 0 and L.PRESTIGE_LINE:format(s.prestige, math.floor(s.prestige * ns.PRESTIGE_BONUS * 100 + 0.5)) or "")
end

local function Build(page)
	local intro = Skin.Text(page, "GameTooltipTextSmall", "soft")
	intro:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	intro:SetText(L.FEATS_INTRO)
	view.feats = Skin.Table(page, {
		width = page.width, rows = 11, rowHeight = 30, icon = false, titles = false,
		columns = { { key = "progress", width = 90 }, { key = "reward", width = 150, justify = "LEFT" } },
		onClick = function() end, onDraw = Draw,
	})
	view.feats:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)
	view.feats:Fit(11 * 30)
	-- A new start.
	local panel = Skin.Panel(page)
	panel:SetPoint("TOPLEFT", view.feats, "BOTTOMLEFT", 0, -12)
	panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	local title = Skin.Caps(panel, L.RESTART_TITLE, "gold")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
	view.prestige = Skin.Text(panel, "GameTooltipTextSmall", "good")
	view.prestige:SetPoint("LEFT", title, "RIGHT", 14, 0)
	local text = Skin.Text(panel, "GameTooltipTextSmall", "soft")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	text:SetPoint("RIGHT", panel, "RIGHT", -180, 0)
	text:SetJustifyH("LEFT")
	text:SetText(L.RESTART_TEXT)
	view.restart = Skin.Button(panel, L.RESTART, function()
		Skin.Ask(L.RESTART_ASK, function() if ns.Restart() then ns.Redraw() end end)
	end, "main", 150)
	view.restart:SetPoint("RIGHT", panel, "RIGHT", -14, 4)
	view.needs = Skin.Text(panel, "GameTooltipTextSmall", "muted")
	view.needs:SetPoint("TOPRIGHT", view.restart, "BOTTOMRIGHT", 0, -4)
	view.needs:SetWidth(160)
	view.needs:SetJustifyH("RIGHT")
end

ns.AddPage("feats", L.TAB_FEATS, Build, Draw)
