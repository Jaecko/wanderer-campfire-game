local ADDON, ns = ...
local L = ns.L

-- The camp's window: its heading, its tabs (each page is a file of its own: ns.AddPage), your resources
-- along the top; before the fire is lit, an invitation to light it, then what your journey brings. While it
-- is shown the camp is looked at every few seconds; closed, nothing runs. And the notices of the
-- expeditions back (an option, on).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH, HEIGHT = 980, 640
local TOP = 96 -- the heading, the tabs, the resources
local LOOK_EVERY = 5 -- seconds between two looks while the window is shown

local window, light, current
local pages, links = {}, {}

local function Settings() return W and W.Settings and W.Settings("campfire") or nil end

-- Numbers and times, said the same way everywhere.
function ns.Number(value) return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(value)) or tostring(math.floor(value)) end
function ns.Minutes(minutes)
	if minutes < 60 then return L.MINUTES:format(minutes) end
	return L.HOURS:format(math.floor(minutes / 60))
end
function ns.Left(seconds) return U.Ago(math.max(60, seconds)) end

-- A page: its key, its tab's label, build(frame) once, draw() each time it is shown or the camp changes.
function ns.AddPage(key, label, build, draw)
	pages[#pages + 1] = { key = key, label = label, build = build, draw = draw }
end

local function Draw()
	if not (window and window:IsShown()) then return end
	local lit = ns.Lit()
	light:SetShown(not lit or light.heritage ~= nil)
	for _, page in ipairs(pages) do
		local shown = lit and light.heritage == nil and page == current
		page.frame:SetShown(shown)
		local link = links[page.key]
		link:SetShown(lit)
		link:SetLabel(page == current and U.Colorize(page.label, 1, 0.82, 0) or page.label)
	end
	if not lit then return end
	-- Your resources, along the top.
	local s, rates = ns.State(), ns.Rates()
	window.resources:SetText(("%s  %s     %s  %s     %s  %s     %s  %s"):format(
		U.Colorize(L.EMBERS, 0.85, 0.75, 0.5), L.AMOUNT_CAP:format(ns.Number(s.embers), ns.Number(rates.embersCap)),
		U.Colorize(L.PROVISIONS, 0.85, 0.75, 0.5), L.AMOUNT_CAP:format(ns.Number(s.provisions), ns.Number(rates.provisionsCap)),
		U.Colorize(L.RENOWN, 0.85, 0.75, 0.5), ns.Number(s.renown),
		U.Colorize(L.SUPPLIES, 0.85, 0.75, 0.5), ns.Number(s.supplies)))
	if current and light.heritage == nil then current.draw() end
end
ns.Redraw = Draw

local function Show(key)
	for _, page in ipairs(pages) do
		if page.key == key then current = page end
	end
	Draw()
end
ns.ShowPage = Show

-- Before the fire: an invitation; after it is lit, what your journey brought (once).
local function BuildLight()
	light = Skin.Panel(window)
	light:SetSize(560, 300)
	light:SetPoint("CENTER", window, "CENTER", 0, -20)
	light.title = Skin.Text(light, "GameFontNormalLarge", "gold")
	light.title:SetPoint("TOP", light, "TOP", 0, -24)
	light.text = Skin.Text(light, "GameTooltipText", "soft")
	light.text:SetPoint("TOPLEFT", light, "TOPLEFT", 28, -60)
	light.text:SetPoint("RIGHT", light, "RIGHT", -28, 0)
	light.text:SetJustifyH("LEFT")
	light.text:SetSpacing(3)
	light.button = Skin.Button(light, L.LIGHT_BUTTON, function()
		if light.heritage then
			light.heritage = nil
			Show("camp")
			return
		end
		local heritage = ns.Light()
		if not heritage then return Draw() end
		local lines = { L.HERITAGE_TEXT, "" }
		for _, key in ipairs({ "embers", "provisions", "renown", "supplies" }) do
			if (heritage[key] or 0) > 0 then lines[#lines + 1] = "  " .. ns.Number(heritage[key]) .. " " .. L[key:upper()] end
		end
		if heritage.veteran then lines[#lines + 1] = "  " .. L.HERITAGE_VETERAN:format(heritage.veteran) end
		lines[#lines + 1] = "  " .. L.HERITAGE_ZONES:format(heritage.zones)
		light.heritage = table.concat(lines, "\n")
		light.title:SetText(L.HERITAGE_TITLE)
		light.text:SetText(light.heritage)
		light.button:SetText(OKAY or "OK")
		light.button:Fit()
		Draw()
	end, "main", 160)
	light.button:SetHeight(32)
	light.button:SetPoint("BOTTOM", light, "BOTTOM", 0, 22)
	light.title:SetText(L.LIGHT_TITLE)
	light.text:SetText(L.LIGHT_TEXT)
end

local function Create()
	window = Skin.CreateWindow("WandererCampfireGame", "MEDIUM")
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 30 }, "campfirePos")
	window:SetSize(WIDTH, HEIGHT)
	local _, title, margin = Skin.Header(window, "Wanderer", L.TITLE)
	-- The tabs, under the title.
	local previous
	for _, page in ipairs(pages) do
		local link = Skin.CreateLink(window, page.label, function()
			if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
			Show(page.key)
		end)
		if previous then link:SetPoint("LEFT", previous, "RIGHT", 4, 0) else link:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -5, -4) end
		links[page.key] = link
		previous = link
	end
	window.resources = Skin.Text(window, "GameTooltipText", "text")
	window.resources:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)
	local rule = Skin.Rule(window, false, 0.2)
	rule:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP - 8))
	rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin, -(margin + TOP - 8))
	for _, page in ipairs(pages) do
		page.frame = CreateFrame("Frame", nil, window)
		page.frame:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
		page.frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
		page.frame.width, page.frame.height = WIDTH - margin * 2, HEIGHT - margin * 2 - TOP
		page.build(page.frame)
		page.frame:Hide()
	end
	current = pages[1]
	BuildLight()
	-- Shown: the camp looked at; then every few seconds while it stays shown.
	local since = 0
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.Scale())
		if ns.HearNames then ns.HearNames(true) end
		ns.Update()
		Draw()
	end)
	window:HookScript("OnHide", function() if ns.HearNames then ns.HearNames(false) end end)
	window:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < LOOK_EVERY then return end
		since = 0
		ns.Update()
		if ns.SaySaid then ns.SaySaid() end
		Draw()
	end)
	Skin.Get(window):Layout()
end

function ns.Toggle()
	if not window then Create() end
	window:SetShown(not window:IsShown())
end

function ns.Open(key)
	if not window then Create() end
	window:Show()
	if key then Show(key) end
end

-- Notices -------------------------------------------------------------------------------------------------

local function PlaceOf(told) return ns.PlaceName(told.area) end

-- Expeditions back while you play: a short notice (an option, on), the window drawn again.
function ns.Back(back)
	Draw()
	local settings = Settings()
	if not (back and back[1] and settings and settings.notify and W.Toast) then return end
	if #back == 1 then
		local told = back[1]
		W.Toast(L.BACK_TITLE, L.BACK_ONE:format(PlaceOf(told), told.won and L.WON or L.LOST), { duration = 5, corner = true })
	else
		W.Toast(L.BACK_TITLE, L.BACK_MANY:format(#back), { duration = 5, corner = true })
	end
end

function ns.SaySaid()
	for _, said in ipairs(ns.TakeSaid()) do
		if not W.Print then return end
		if said[1] == "champion" then W.Print(L.CHAMPION_JOINED:format(said[2])) end
		if said[1] == "lived" then W.Print(L.LIVED_SAID:format(ns.PlaceName(said[2]))) end
		if said[1] == "feat" then W.Print(L.FEAT_SAID:format(L["FEAT_" .. said[2]:upper()])) end
	end
end

-- Init ----------------------------------------------------------------------------------------------------

BINDING_HEADER_WANDERERCAMPFIREGAME = "Wanderer Campfire Game"
BINDING_NAME_WANDERERCAMPFIREGAME_TOGGLE = L.TITLE
function WandererCampfireGame_Toggle() ns.Toggle() end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	if (W.API or 1) < 5 then return W.Print(L.NEEDS_WANDERER) end
	W.RegisterExtension({
		key = "campfire",
		addon = ADDON,
		title = L.ADDON,
		news = L.NEWS_LINES,
		defaults = { notify = true },
		launcher = { label = L.TITLE, open = function() ns.Toggle() end },
		options = function(o)
			o.Header(L.ADDON)
			o.Button(L.TITLE, L.OPEN, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end)
			o.Checkbox("campfire", "notify", L.NOTIFY, L.NOTIFY_DESC)
		end,
	})
	SLASH_WANDERERCAMPFIREGAME1 = "/wcampfire"
	SLASH_WANDERERCAMPFIREGAME2 = "/wcamp"
	SlashCmdList.WANDERERCAMPFIREGAME = function() ns.Toggle() end
	ns.ListenReal()
	-- At login: what came back while you were away, said once; the zones you enter, noted.
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	events:SetScript("OnEvent", function(_, event)
		if event == "ZONE_CHANGED_NEW_AREA" then return ns.NoteVisit() end
		C_Timer.After(5, function()
			ns.Back(ns.Update())
			ns.SaySaid()
		end)
	end)
end

if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
