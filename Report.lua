local _, ns = ...
local L = ns.L

-- The expeditions' reports: when you come back to the camp (or while you look at it), each expedition back and
-- not yet told shows over the window, one after the other. The place's picture and its name; won or lost, in
-- large letters; who went (their faces, their experience filling up to the levels gained, the wounded); how
-- the road went (who countered which threat, why it was lost); what
-- they brought (renown, embers, supplies, a trophy, gear: put on, or taken apart at the forge); a choice the
-- road brought back. "The same road" sends the same party there again; the last ones told can be read again
-- from the road's page.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local UI = ns.UI

local BANNER = 150
local CELL, FACE = 74, 46
local GOLD = Skin.COLORS.gold
local card, dimmer
local queue, shown = {}, nil
local drawn = 0 -- (each report drawn: a filling of the one before, not begun yet, never begins on its faces)

local function Count(value) return ns.Short(math.floor(value + 0.5)) end

-- A companion's place in the report: their face, name, levels, experience.
local function NewCell(parent)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetSize(CELL, 100)
	cell.portrait = ns.Portrait(cell, FACE, true)
	cell.portrait:SetPoint("TOP", cell, "TOP", 0, -4)
	cell.name = Skin.CreateText(cell, "GameFontHighlightSmall")
	cell.name:SetPoint("TOP", cell.portrait, "BOTTOM", 0, -6)
	cell.name:SetWidth(CELL - 4)
	if cell.name.SetWordWrap then cell.name:SetWordWrap(false) end
	cell.level = Skin.Text(cell, "GameTooltipTextSmall", "muted")
	cell.level:SetPoint("TOP", cell.name, "BOTTOM", 0, -3)
	cell.bar = UI.Bar(cell, 3)
	cell.bar:SetSize(CELL - 16, 3)
	cell.bar:SetPoint("TOP", cell.level, "BOTTOM", 0, -5)
	cell:EnableMouse(true)
	Skin.Tooltip(cell, function(self) return self.tip end)
	return cell
end

-- The experience filling: from where they were to where they are now, a glint at each level gained.
local function Fill(cell, gone, delay)
	local total = (gone.to - gone.from) + (gone.after or 0) - (gone.share or 0)
	local function Show(value)
		local level = gone.from + math.floor(value + 1e-6)
		local part = value - math.floor(value + 1e-6)
		if level >= gone.to then
			level = gone.to
			if gone.top then part = 1 end
		end
		cell.bar:Set(part)
		if level ~= cell.shownLevel then
			if cell.shownLevel and level > cell.shownLevel and cell:IsVisible() then -- (none with the window closed)
				UI.Flash(cell, 0.35)
				U.PlaySound("IG_QUEST_LIST_SELECT")
			end
			cell.shownLevel = level
			cell.portrait.seal.text:SetText(level)
		end
	end
	cell.shownLevel = nil
	Show(gone.share or 0)
	local mine = drawn
	C_Timer.After(delay, function()
		if mine ~= drawn then return end
		-- (the window closed meanwhile: filled at once, as it will be seen)
		if not card:IsVisible() then return Show((gone.share or 0) + total) end
		UI.Tween(cell, 0.6 + 0.35 * math.min(4, gone.to - gone.from), function(t) Show((gone.share or 0) + total * t) end)
	end)
end

-- The fillings of the faces ended where they are.
local function StopFills()
	for _, cell in ipairs(card.cells) do UI.Stop(cell) end
end

local function FillCell(cell, gone)
	local color = ns.ClassColor(gone.class)
	local companion = ns.Companion(gone.id) or gone
	cell.portrait:Set({ class = gone.class, look = gone.look, level = gone.from, rarity = gone.rarity }, { hurt = gone.hurt, level = gone.from })
	cell.name:SetText(gone.name)
	cell.name:SetTextColor(color[1], color[2], color[3])
	if gone.hurt then
		cell.level:SetText(Skin.Colorize(L.REPORT_HURT, "bad"))
	elseif gone.to > gone.from then
		cell.level:SetText(Skin.Colorize(L.REPORT_UP:format(gone.to - gone.from), "gold"))
	else
		cell.level:SetText(L.LEVEL_SHORT:format(gone.to))
	end
	cell.tip = { gone.name, ns.CompanionKind(companion), L.REPORT_XP:format(ns.Number(gone.xp or 0)) }
	cell:Show()
end

-- A piece found, said: put on (by whom, in what slot, how much better; what it replaced taken apart: its
-- supplies), kept in the armory, or taken apart.
function ns.GearLine(found)
	if found.salvage then return L.REPORT_SALVAGE:format(found.name, found.salvage) end
	if found.kept then return L.REPORT_KEPT:format(found.name) end
	local line = L.REPORT_GEAR:format(found.name, ns.SlotName(found.slot), found.gain)
	return found.oldSalvage and (line .. "   " .. ns.Amount("supplies", found.oldSalvage, "+")) or line
end

-- Why a standing order ended, in words.
local function Ended(why)
	if why == "hurt" then return L.AGAIN_HURT end
	if why == "away" then return L.AGAIN_AWAY end
	return ns.CantText(why)
end

-- The road told: each threat met (who countered it, with what; or left open), why it was lost, the camp's rest,
-- a standing order (gone again, or why it ended). Short lines, the spells' own icons.
local function Story(list, told)
	local lines = {}
	for _, met in ipairs(told.threats or {}) do
		local threat = ns.THREAT[met.key]
		if threat then
			local name = L["THREAT_" .. met.key:upper()]
			if met.by then
				local c = ns.ClassColor(met.class)
				lines[#lines + 1] = ns.InlineIcon(ns.SpellIcon(met.spell), 14) .. " " .. L.STORY_COUNTERED:format(U.Colorize(met.by, c[1], c[2], c[3]),
					name, ns.SpellName(met.spell))
			else
				lines[#lines + 1] = ns.InlineIcon(threat.icon, 14) .. " " .. Skin.Colorize(L.STORY_OPEN:format(name), "bad")
			end
		end
	end
	for _, why in ipairs(told.why or {}) do lines[#lines + 1] = Skin.Colorize(L["STORY_LOST_" .. why:upper()], "bad") end
	if told.rested then lines[#lines + 1] = Skin.Colorize(L.REST_REPORT, "blue") end
	if told.again == "left" then
		lines[#lines + 1] = Skin.Colorize(L.AGAIN_LEFT, "gold")
	elseif told.again then
		lines[#lines + 1] = Skin.Colorize(L.AGAIN_ENDED:format(Ended(told.again)), "muted")
	end
	if not lines[1] then return end
	list:Caption(L.REPORT_STORY)
	list:Text(table.concat(lines, "\n"), "soft", "GameTooltipText")
end

-- What they brought: the road told first, the resources side by side (counting up, unless drawn again), then the
-- trophies, the gear found, a recruit, a choice the road brought back; the standing order to take with the same
-- road.
local function Brought(list, told, again)
	Story(list, told)
	local lines = {}
	for _, key in ipairs({ "renown", "embers", "supplies" }) do
		if (told[key] or 0) > 0 then lines[#lines + 1] = { key = key, value = told[key] } end
	end
	if lines[1] then
		list:Caption(L.REPORT_GAINS)
		local amounts = card.amounts
		for index, box in ipairs(amounts.cells) do
			local line = lines[index]
			box:SetShown(line ~= nil)
			if line then
				box.icon:SetTexture(ns.IconFile(line.key))
				box.word:SetText(L[line.key:upper()])
				local value = line.value
				if again then
					UI.Stop(box)
					box.value:SetText("+" .. Count(value))
				else
					box.value:SetText("+0")
					UI.Tween(box, 0.9, function(t) box.value:SetText("+" .. Count(value * t)) end)
				end
			end
		end
		list:Put(amounts, 48, 6)
	end
	for _, trophy in ipairs({ told.trophy or false, told.trophy2 or false }) do
		if trophy then
			list:Row({ icon = ns.TrophyIcon(trophy), quality = trophy + 1, title = L["TROPHY_" .. trophy],
				color = GOLD, sub = L.REPORT_TROPHY:format(ns.PlaceName(told.area)), height = 50 })
		end
	end
	for _, found in ipairs(told.gear or {}) do
		local piece = ns.GEAR_ITEM[found.item] or {}
		list:Row({ icon = ns.PieceIcon(found.item), quality = piece.quality, title = ns.PieceText(found.item), sub = ns.GearLine(found), wrap = true,
			chip = L.ITEM_LEVEL:format(piece.level or 0), tone = (found.salvage or found.kept) and "grey" or "green" })
	end
	if told.recruit then
		list:Row({ icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", quality = told.recruitRarity or 3, title = told.recruit, color = GOLD, sub = L.REPORT_RECRUIT, wrap = true })
	end
	if told.road then list:Text(L.REPORT_ROAD, "gold") end
	if not (lines[1] or told.trophy or told.gear or told.recruit) then list:Text(L.REPORT_NOTHING, "muted") end
	-- (beside the same road: whether it is a standing order; not when it set out again already)
	if told.party and told.again ~= "left" and not told.contract then
		card.standing:Refresh()
		list:Put(card.standing, 20, 8, true)
	end
end

-- The ways on: the next report (how many wait) or back to the camp, the same road again, the others skipped.
local function Ways()
	local left = #queue
	card.next:SetText(left > 0 and L.REPORT_NEXT:format(left) or L.REPORT_CLOSE)
	card.next:Fit()
	card.again:SetShown(shown.party ~= nil)
	card.again:SetEnabled(ns.CanAgain(shown) and true or false)
	card.skip:SetShown(left > 0)
end

local function Draw()
	local told = shown
	if not told then return end
	drawn = drawn + 1
	-- (the fillings of the report before ended where they were)
	StopFills()
	ns.ReportRead(told)
	card.banner:Set(told.area)
	card.kind:Set(told.contract and (L.CONTRACT .. ": " .. ns.ContractName(told.contract)) or ns.KindOne(told.kind or "zone"),
		told.contract and "gold" or "grey")
	card.place:SetText(ns.PlaceName(told.area))
	local facts = {}
	if told.minutes then facts[#facts + 1] = ns.Minutes(told.minutes) end
	if told.chance then facts[#facts + 1] = L.REPORT_CHANCE:format(math.floor(told.chance * 100 + 0.5)) end
	facts[#facts + 1] = L.REPORT_AT:format(date("%H:%M", told.at))
	card.facts:SetText(table.concat(facts, ns.DOT))
	-- Won or lost.
	card.result:SetText(U.Upper(told.won and L.REPORT_WON or L.REPORT_LOST))
	local c = told.won and ns.WARM or Skin.COLORS.bad
	card.result:SetTextColor(c[1], c[2], c[3])
	card.left:SetColorTexture(c[1], c[2], c[3], 0.35)
	card.right:SetColorTexture(c[1], c[2], c[3], 0.35)
	-- Who went.
	local party = told.party or {}
	local perRow = math.min(5, math.max(1, #party))
	local rows = math.max(1, math.ceil(#party / 5))
	local faces = #party > 0 and rows * 104 or 40
	card.party:SetHeight(faces)
	-- (what they brought: in the room left, the two rows of faces of a raid taking more of it)
	local room = card.room - faces
	card.list.scroll:SetHeight(room)
	card.list.view = room
	local width = card:GetWidth() - 32
	for index, gone in ipairs(party) do
		local cell = card.cells[index]
		if not cell then
			cell = NewCell(card.party)
			card.cells[index] = cell
		end
		local column, row = (index - 1) % 5, math.floor((index - 1) / 5)
		local inRow = math.min(perRow, #party - row * 5)
		local start = (width - inRow * CELL) / 2
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", card.party, "TOPLEFT", start + column * CELL, -row * 104)
		FillCell(cell, gone)
		Fill(cell, gone, 0.35 + index * 0.08)
	end
	for index = #party + 1, #card.cells do card.cells[index]:Hide() end
	-- (an older tale, before the reports: the levels and the wounded said in words)
	card.older:SetShown(#party == 0)
	if #party == 0 then
		local lines = {}
		if told.up then lines[#lines + 1] = L.LOG_UP:format(told.up) end
		if told.hurt and told.hurt[1] then lines[#lines + 1] = L.LOG_HURT:format(table.concat(told.hurt, ", ")) end
		card.older:SetText(table.concat(lines, "\n"))
	end
	-- What they brought.
	local list = card.list
	list:Begin()
	Brought(list, told)
	list:Done()
	list:Top()
	Ways()
end

-- (quiet: from one of the card's buttons, which sound already)
local function Next(quiet)
	shown = table.remove(queue, 1)
	if not shown then
		StopFills()
		UI.Tween(card, 0.18, function(t) card:SetAlpha(1 - t) dimmer:SetAlpha(1 - t) end, function()
			card:Hide()
			dimmer:Hide()
		end)
		ns.Redraw()
		return
	end
	-- (a report come while the last one faded: the fading ended there)
	UI.Stop(card)
	Draw()
	card:SetAlpha(1)
	UI.Tween(card.inner, 0.3, function(t)
		card.inner:SetAlpha(t)
		card.inner:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -14 * (1 - t))
		card.inner:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, -14 * (1 - t))
	end)
	if not quiet then U.PlaySound(shown.won and "IG_QUEST_LIST_COMPLETE" or "IG_QUEST_FAILED") end
end

local function Build()
	local window = ns.WindowFrame()
	-- (under the heading: the window can still be moved and closed)
	dimmer = CreateFrame("Frame", nil, window)
	dimmer:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -ns.WindowTop())
	dimmer:SetPoint("BOTTOMRIGHT")
	dimmer:SetFrameLevel(window:GetFrameLevel() + 30)
	dimmer:EnableMouse(true)
	local shade = dimmer:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.72)
	card = CreateFrame("Frame", nil, dimmer)
	card:SetPoint("TOPLEFT", dimmer, "TOPLEFT", 14, -6)
	card:SetPoint("BOTTOMRIGHT", dimmer, "BOTTOMRIGHT", -14, 18)
	card:SetFrameLevel(dimmer:GetFrameLevel() + 2)
	local ground = card:CreateTexture(nil, "BACKGROUND", nil, -3)
	ground:SetAllPoints()
	ground:SetColorTexture(0.045, 0.038, 0.032, 0.98)
	Skin.Edges(card, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.3)
	local inner = CreateFrame("Frame", nil, card)
	inner:SetPoint("TOPLEFT")
	inner:SetPoint("BOTTOMRIGHT")
	card.inner = inner
	local width = window:GetWidth() - 28
	-- The place.
	card.banner = ns.Banner(inner, width, BANNER)
	card.banner:SetPoint("TOPLEFT")
	card.kind = Skin.Chip(card.banner)
	card.kind:SetPoint("TOPLEFT", card.banner, "TOPLEFT", 12, -12)
	card.place = Skin.CreateText(card.banner, "GameFontNormalLarge")
	card.place:SetPoint("BOTTOMLEFT", card.banner, "BOTTOMLEFT", 16, 30)
	card.place:SetPoint("RIGHT", card.banner, "RIGHT", -16, 0)
	card.place:SetJustifyH("LEFT")
	card.place:SetTextColor(1, 0.92, 0.75)
	card.facts = Skin.Text(card.banner, "GameTooltipTextSmall", "soft")
	card.facts:SetPoint("TOPLEFT", card.place, "BOTTOMLEFT", 0, -5)
	-- Won or lost, between two thin rules.
	card.result = Skin.CreateText(inner, "GameFontNormalHuge")
	card.result:SetPoint("TOP", card.banner, "BOTTOM", 0, -16)
	card.left = inner:CreateTexture(nil, "ARTWORK")
	card.left:SetHeight(1)
	card.left:SetPoint("LEFT", inner, "LEFT", 24, 0)
	card.left:SetPoint("RIGHT", card.result, "LEFT", -14, 0)
	card.left:SetPoint("TOP", card.result, "CENTER", 0, 0)
	card.right = inner:CreateTexture(nil, "ARTWORK")
	card.right:SetHeight(1)
	card.right:SetPoint("LEFT", card.result, "RIGHT", 14, 0)
	card.right:SetPoint("RIGHT", inner, "RIGHT", -24, 0)
	card.right:SetPoint("TOP", card.result, "CENTER", 0, 0)
	-- Who went.
	card.party = CreateFrame("Frame", nil, inner)
	card.party:SetPoint("TOPLEFT", inner, "TOPLEFT", 16, -(BANNER + 62))
	card.party:SetPoint("RIGHT", inner, "RIGHT", -16, 0)
	card.party:SetHeight(104)
	card.cells = {}
	card.older = Skin.Text(inner, "GameTooltipText", "soft")
	card.older:SetPoint("TOPLEFT", card.party, "TOPLEFT", 0, -6)
	card.older:SetPoint("RIGHT", card.party, "RIGHT")
	card.older:SetJustifyH("CENTER")
	-- The ways on, at the foot.
	card.next = Skin.Button(inner, L.REPORT_CLOSE, function() Next(true) end, "main", 150)
	card.next:SetHeight(36)
	card.next:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -16, 16)
	-- (its key over it: Space, while the mouse is over the window)
	card.key = Skin.Text(inner, "GameTooltipTextSmall", "muted")
	card.key:SetPoint("BOTTOMRIGHT", card.next, "TOPRIGHT", 0, 4)
	card.key:SetText(_G.KEY_SPACE or "Space")
	card.again = Skin.Button(inner, L.REPORT_AGAIN, function()
		if shown and ns.Again(shown, ns.State().goAgain) then Next(true) end
	end, nil, 130)
	card.again:SetHeight(36)
	card.again:SetMotionScriptsWhileDisabled(true) -- (hovered while it cannot go: why)
	card.again:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 16, 16)
	Skin.Tooltip(card.again, function()
		local can, why = ns.CanAgain(shown)
		return can and L.REPORT_AGAIN_DESC or ns.CantText(why)
	end)
	card.skip = Skin.CreateLink(inner, L.REPORT_SKIP, function()
		Skin.Play("click") -- (a link: no sound of its own)
		ns.ReportsRead()
		wipe(queue)
		Next(true)
	end)
	card.skip:SetPoint("BOTTOM", inner, "BOTTOM", 0, 64)
	-- What they brought (a list: a raid may bring much).
	local holder = CreateFrame("Frame", nil, inner)
	holder:SetPoint("TOPLEFT", card.party, "BOTTOMLEFT", 0, -10)
	holder:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -16, 84)
	holder.width = width - 32
	card.room = window:GetHeight() - ns.WindowTop() - 24 - (BANNER + 62) - 10 - 84
	holder.height = card.room - 104
	card.list = UI.List(holder, holder.width, holder.height)
	-- The resources brought, side by side.
	local amounts = CreateFrame("Frame", nil, card.list)
	amounts.cells = {}
	local each = (card.list.width - 12) / 3
	for index = 1, 3 do
		local cell = CreateFrame("Frame", nil, amounts)
		cell:SetSize(each, 44)
		cell:SetPoint("TOPLEFT", amounts, "TOPLEFT", (index - 1) * (each + 6), 0)
		cell.ground = cell:CreateTexture(nil, "BACKGROUND")
		cell.ground:SetAllPoints()
		cell.ground:SetColorTexture(1, 1, 1, 0.04)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(26, 26)
		cell.icon:SetPoint("LEFT", cell, "LEFT", 8, 0)
		ns.Crop(cell.icon)
		cell.value = Skin.Text(cell, "GameFontNormal", "gold")
		cell.value:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", 8, 0)
		cell.word = Skin.Text(cell, "GameTooltipTextSmall", "muted")
		cell.word:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", 8, 0)
		amounts.cells[index] = cell
	end
	card.amounts = amounts
	-- The standing order, taken with the same road (this character's choice, as on a place's page).
	card.standing = Skin.Check(card.list, L.GO_AGAIN, function() return ns.State().goAgain end,
		function(on) ns.State().goAgain = on or nil end, L.GO_AGAIN_DESC)
	card.standing:Hide()
	dimmer:Hide()
end

-- The reports to show: those given (one read again), else every one not told yet (quiet: asked by a click,
-- which sounded already).
function ns.ShowReports(list, quiet)
	local window = ns.WindowFrame()
	if not (window and window:IsShown()) then return end
	if not card then Build() end
	local fresh = list or ns.Reports()
	if not (fresh[1] or queue[1]) then return end
	-- (those already waiting kept, none twice)
	local known = {}
	if shown then known[shown] = true end
	for _, told in ipairs(queue) do known[told] = true end
	for _, told in ipairs(fresh) do
		if not known[told] then queue[#queue + 1] = told end
	end
	-- (one open already: only its ways on told again, what waits after it)
	if dimmer:IsShown() and shown then return Ways() end
	dimmer:Show()
	dimmer:SetAlpha(0)
	card:Show()
	UI.Tween(dimmer, 0.25, function(t) dimmer:SetAlpha(t) end)
	Next(quiet)
end

-- The report open put aside (your absence is read first): it comes back first next time.
function ns.HideReport()
	if not (dimmer and dimmer:IsShown()) then return end
	UI.Stop(card)
	StopFills()
	if shown then table.insert(queue, 1, shown) end
	shown = nil
	card:Hide()
	dimmer:Hide()
end
local function Open() return dimmer ~= nil and dimmer:IsShown() end
ns.ReportShown = Open

-- Every report waiting forgotten (all collected at once from the return card).
function ns.ClearReports()
	wipe(queue)
	if Open() then
		StopFills()
		shown = nil
		card:Hide()
		dimmer:Hide()
	end
end

-- Space: the report's main button (the next one, or back to the camp).
function ns.ReportMain()
	if not (Open() and shown) then return false end
	Skin.Play("click")
	Next(true)
	return true
end

-- What it brought drawn again (the names of the pieces found, come from the game a moment later).
function ns.RefreshReport()
	if not (Open() and shown) then return end
	card.list:Begin()
	Brought(card.list, shown, true)
	card.list:Done()
end

-- The return ------------------------------------------------------------------------------------------------
-- Back at the camp: one card over the window for everything that came meanwhile. Under the time away, what the
-- camp made; each expedition back in a row (won or lost, what it brought; a click: its whole report); what waits
-- (an order, an event by the fire, the week's chest, a talent: a click, its page). "Collect all" takes it all at
-- once (Space while the mouse is over the window); the reports one by one stay a click away. After a long
-- absence with nothing new, a word says so a moment. Also what waits at the camp, for the fire's page and the
-- launcher's word.

local board, recap, quiet -- (the return card)

-- What waits ------------------------------------------------------------------------------------------------

-- Each thing waiting at the camp, with the page where it is done: { icon, text, page }.
function ns.Waiting()
	local list = {}
	if not ns.Lit() then return list end
	if ns.OrderReady() then list[#list + 1] = { icon = "Interface\\Icons\\INV_Misc_Note_01", text = L.WAITING_ORDER, page = "orders" } end
	if ns.State().event then list[#list + 1] = { icon = "Interface\\Icons\\Spell_Fire_Fire", text = L.WAITING_EVENT, page = "camp" } end
	if ns.WeekReady() then list[#list + 1] = { icon = "Interface\\Icons\\INV_Box_02", text = L.WAITING_WEEK, page = "week" } end
	if ns.TalentWaiting() then list[#list + 1] = { icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", text = L.WAITING_TALENT, page = "companions" } end
	return list
end

-- What a report brought, in one line (its resources, its trophies).
function ns.ToldGains(told)
	local gains = { ns.Gains({ renown = told.renown, embers = told.embers, supplies = told.supplies }, true) }
	for _, trophy in ipairs({ told.trophy or false, told.trophy2 or false }) do
		if trophy then gains[#gains + 1] = L["TROPHY_" .. trophy] end
	end
	return table.concat(gains, "   ")
end

-- Under the launcher's word: the expeditions back to read, those on the road (the first back in how long),
-- what waits. Lines { text, role } (also .text, .role).
local function Line(lines, text, role) lines[#lines + 1] = { text, role, text = text, role = role } end
function ns.Summary()
	if not ns.Lit() then return nil end
	local now, lines = time(), {}
	local back, away, soonest = #ns.Reports(), 0, nil
	for _, expedition in ipairs(ns.State().expeditions) do
		if expedition.finish <= now then
			back = back + 1
		else
			away = away + 1
			soonest = math.min(soonest or expedition.finish, expedition.finish)
		end
	end
	if back > 0 then Line(lines, L.SUMMARY_BACK:format(back), "good") end
	if away > 0 then Line(lines, L.SUMMARY_AWAY:format(away, ns.Left(soonest - now)), "text") end
	local texts = {}
	for _, item in ipairs(ns.Waiting()) do texts[#texts + 1] = item.text end
	if texts[1] then Line(lines, table.concat(texts, ns.DOT), "soft") end
	if not lines[1] then Line(lines, L.SUMMARY_QUIET, "muted") end
	return lines
end

-- The card --------------------------------------------------------------------------------------------------

local function Hide()
	if board then board:Hide() end
	recap = nil
end

-- Everything taken: the reports read (their gains are in your camp already, the gear put on or taken apart).
local function Collect()
	U.PlaySound("IG_QUEST_LIST_COMPLETE")
	ns.ReportsRead()
	ns.ClearReports()
	Hide()
	ns.ShowPage("fire")
end

local function DrawBoard()
	local fresh, waiting = ns.Reports(), ns.Waiting()
	-- (nothing left to show: every report read from it, no absence to tell)
	if not recap and not fresh[1] then return Hide() end
	board.title:SetText(recap and L.AWAY_TITLE or L.RETURN_TITLE)
	board.since:SetText(recap and L.AWAY_FOR:format(U.Ago(recap.away)) or "")
	local list = board.list
	list:Begin()
	-- What the camp made.
	if recap then
		local lines = {}
		for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
			if (recap[key] or 0) > 0 then lines[#lines + 1] = ns.Amount(key, recap[key], "+") .. "  " .. L[key:upper()] end
		end
		if (recap.trophies or 0) > 0 then lines[#lines + 1] = L.AWAY_TROPHIES:format(recap.trophies) end
		if (recap.levels or 0) > 0 then lines[#lines + 1] = L.AWAY_LEVELS:format(recap.levels) end
		-- (the camp rested, discreetly: the roads that leave now teach more)
		if (recap.rest or 0) > 0 then
			lines[#lines + 1] = Skin.Colorize(L.REST_LINE:format(math.floor(ns.REST_XP * 100 + 0.5), ns.Minutes(recap.rest)), "blue")
		end
		if lines[1] then
			list:Caption(L.RETURN_MADE)
			board.text = list:Text(table.concat(lines, "\n"), "text", "GameFontHighlight")
		end
	end
	-- The expeditions back, one row each (a click: its whole report).
	if fresh[1] then
		list:Caption(L.RETURN_BACK, tostring(#fresh))
		for _, told in ipairs(fresh) do
			list:Row({ icon = ns.KindIcon(told.kind or "zone"), title = ns.PlaceName(told.area), sub = ns.ToldGains(told), height = 46,
				chip = told.won and L.WON or L.LOST, tone = told.won and "green" or "red",
				tip = { ns.PlaceName(told.area), L.RETURN_ROW_DESC }, onClick = function() ns.ShowReports({ told }, true) end })
		end
	end
	-- What waits (a click: its page, everything taken first).
	if waiting[1] then
		list:Caption(L.WAITING_TITLE)
		for _, item in ipairs(waiting) do
			list:Row({ icon = item.icon, title = item.text, color = Skin.COLORS.gold, height = 40, onClick = function()
				Collect()
				ns.ShowPage(item.page)
			end })
		end
	end
	list:Done()
	board.each:SetShown(fresh[2] ~= nil)
end

local function BuildBoard()
	local window = ns.WindowFrame()
	-- (under the heading: the window can still be moved and closed; a report opened from it comes over it)
	board = CreateFrame("Frame", nil, window)
	board:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -(ns.WindowTop() + 6))
	board:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 18)
	board:SetFrameLevel(window:GetFrameLevel() + 20)
	board:EnableMouse(true)
	local ground = board:CreateTexture(nil, "BACKGROUND", nil, -3)
	ground:SetAllPoints()
	ground:SetColorTexture(0.045, 0.038, 0.032, 0.98)
	Skin.Edges(board, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.3)
	board.title = Skin.Text(board, "GameFontNormalLarge", "gold")
	board.title:SetPoint("TOP", board, "TOP", 0, -20)
	board.since = Skin.Text(board, "GameTooltipTextSmall", "muted")
	board.since:SetPoint("TOP", board.title, "BOTTOM", 0, -6)
	-- At the foot: the key hint, the reports one by one, the main button.
	board.keys = Skin.Text(board, "GameTooltipTextSmall", "muted")
	board.keys:SetPoint("BOTTOM", board, "BOTTOM", 0, 12)
	board.keys:SetText(L.KEYS_HINT)
	board.collect = Skin.Button(board, L.COLLECT_ALL .. "   " .. Skin.Colorize(_G.KEY_SPACE or "Space", "muted"), Collect, "main", 220)
	board.collect:SetHeight(38)
	board.collect:SetPoint("BOTTOM", board.keys, "TOP", 0, 12)
	Skin.Tooltip(board.collect, L.COLLECT_ALL_DESC)
	board.each = Skin.SmallButton(board, L.REPORTS_EACH, function()
		local fresh = ns.Reports()
		Hide()
		ns.ShowPage("fire")
		ns.ShowReports(fresh, true)
	end, L.REPORTS_EACH_DESC, 24)
	board.each:SetPoint("BOTTOM", board.collect, "TOP", 0, 10)
	-- What came, in a list between the heading and the buttons.
	local holder = CreateFrame("Frame", nil, board)
	holder:SetPoint("TOPLEFT", board, "TOPLEFT", 16, -64)
	holder:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -16, 118)
	holder.width = window:GetWidth() - 28 - 32
	holder.height = window:GetHeight() - ns.WindowTop() - 24 - 64 - 118
	board.list = UI.List(holder, holder.width, holder.height)
	board:Hide()
end

-- The card shown (given: what changed while you were away, or nil: only the expeditions back).
function ns.ShowReturn(given)
	if not board then BuildBoard() end
	recap = given
	board:Show()
	DrawBoard()
	if board:IsShown() then UI.Appear(board, 0.35) end
end
function ns.ReturnShown() return board ~= nil and board:IsShown() end
function ns.DrawReturn() if ns.ReturnShown() then DrawBoard() end end
function ns.HideReturn() Hide() end
-- (Space: its main button)
function ns.ReturnMain()
	if not ns.ReturnShown() then return false end
	Collect()
	return true
end

-- Back after a long absence, nothing new: said a moment, over the fire.
function ns.NothingNew()
	local window = ns.WindowFrame()
	if not quiet then
		-- (over the pages: its own layer)
		quiet = CreateFrame("Frame", nil, window)
		quiet:SetAllPoints()
		quiet:SetFrameLevel(window:GetFrameLevel() + 25)
		local text = Skin.Text(quiet, "GameFontHighlight", "soft")
		text:SetPoint("TOP", window, "TOP", 0, -(ns.WindowTop() + 52))
		text:SetText(L.NOTHING_NEW)
	end
	quiet:Show()
	UI.Tween(quiet, 0.3, function(t) quiet:SetAlpha(t) end)
	C_Timer.After(2, function() UI.Tween(quiet, 0.6, function(t) quiet:SetAlpha(1 - t) end, function() quiet:Hide() end) end)
end
