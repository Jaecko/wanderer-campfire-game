local _, ns = ...
local L = ns.L

-- The expeditions' map: a continent of the game (the Eastern Kingdoms or Kalimdor, the one you are on first),
-- the places open to the expeditions on it (a small mark; a key for a dungeon, a dragon for a raid: clicked,
-- their page), and the expeditions on the road: their party's face going along a dotted road from your camp
-- (where your character stands) to the place, as far as they have come. Under it, those on the road.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local CONTINENTS = { 1415, 1414 } -- the Eastern Kingdoms, Kalimdor
local DOTS = 12 -- a road's dots
local view = {}
local shown -- the continent shown

-- A map's rectangle on a continent (0 to 1), nil when it is not on it.
local function Rect(map, continent)
	if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
	local left, right, top, bottom = Safe(C_Map.GetMapRectOnMap, map, continent)
	left, right, top, bottom = Clean(left), Clean(right), Clean(top), Clean(bottom)
	if not (left and right and top and bottom) or right <= left or bottom <= top then return nil end
	return left, right, top, bottom
end

-- Its middle.
local function Middle(map, continent)
	local left, right, top, bottom = Rect(map, continent)
	if not left then return nil end
	return (left + right) / 2, (top + bottom) / 2
end

-- A place's map: its zone's (a dungeon's or raid's: the zone of its door).
local function PlaceMap(area)
	local art = ns.PLACE_ART and ns.PLACE_ART[area]
	if art and art.map then return art.map end
	local zone = ns.ENTRANCES[area]
	art = zone and ns.PLACE_ART[zone]
	return art and art.map or nil
end

-- Where a place is on a continent; a dungeon or raid a little aside from its zone's middle.
local function Where(area, kind, continent)
	local map = PlaceMap(area)
	if not map then return nil end
	local x, y = Middle(map, continent)
	if not x then return nil end
	if kind == "dungeon" then x, y = x + 0.012, y + 0.01 elseif kind == "raid" then x, y = x - 0.012, y + 0.012 end
	return x, y
end

-- Your camp: where your character stands, on a continent.
local function Camp(continent)
	local map, px, py = U.HereOnMap()
	if not map then return nil end
	local left, right, top, bottom = Rect(map, continent)
	if not left then return nil end
	return left + px * (right - left), top + py * (bottom - top)
end

local function Continent()
	for _, continent in ipairs(CONTINENTS) do
		if Camp(continent) then return continent end
	end
	return CONTINENTS[1]
end

local function Pin(index)
	local pin = view.pins[index]
	if pin then return pin end
	pin = CreateFrame("Button", nil, view.map)
	pin:SetSize(16, 16)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin:SetFrameLevel(view.map:GetFrameLevel() + 2)
	pin:SetScript("OnClick", function(self)
		Skin.Play("click")
		ns.ShowPage("expedition", self.key)
	end)
	Skin.Tooltip(pin, function(self) return self.tip end)
	view.pins[index] = pin
	return pin
end

local function Dot(index)
	local dot = view.dots[index]
	if dot then return dot end
	dot = view.map:CreateTexture(nil, "OVERLAY")
	dot:SetSize(3, 3)
	dot:SetColorTexture(ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.85)
	view.dots[index] = dot
	return dot
end

local function Marker(index)
	local marker = view.markers[index]
	if marker then return marker end
	marker = CreateFrame("Frame", nil, view.map)
	marker:SetSize(26, 26)
	marker:SetFrameLevel(view.map:GetFrameLevel() + 4)
	marker.portrait = ns.Portrait(marker, 24, false)
	marker.portrait:SetPoint("CENTER")
	marker:EnableMouse(true)
	Skin.Tooltip(marker, function(self) return self.tip end)
	view.markers[index] = marker
	return marker
end

local function Draw()
	local s = ns.State()
	shown = shown or Continent()
	view.switch:Select(shown)
	local map = view.map
	map:SetMap(shown)
	local width, height = map:GetWidth(), map:GetHeight()
	-- Your camp.
	local cx, cy = Camp(shown)
	view.camp:SetShown(cx ~= nil)
	if cx then
		view.camp:ClearAllPoints()
		view.camp:SetPoint("CENTER", map, "TOPLEFT", cx * width, -cy * height)
	end
	-- The places open.
	local used = 0
	for _, place in ipairs(ns.Places()) do
		if place.open then
			local x, y = Where(place.area, place.kind, shown)
			if x then
				used = used + 1
				local pin = Pin(used)
				pin.key = ns.PlaceKey(place)
				pin.tip = { ns.PlaceName(place.area), L.LEVELS:format(place.low, place.high), ns.ThreatIcons(place, 16) }
				local size = place.kind == "zone" and 10 or 16
				pin:SetSize(size, size)
				if place.kind == "zone" then
					pin.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
					pin.icon:SetTexCoord(0, 1, 0, 1)
				else
					pin.icon:SetTexture(ns.KindIcon(place.kind))
					ns.Crop(pin.icon)
				end
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", map, "TOPLEFT", x * width, -y * height)
				pin:Show()
			end
		end
	end
	for index = used + 1, #view.pins do view.pins[index]:Hide() end
	-- The expeditions on the road: their face along the way, the road dotted from the camp.
	local dots, marks = 0, 0
	for _, expedition in ipairs(s.expeditions) do
		local done = ns.Progress(expedition)
		local leader = ns.Companion(expedition.members[1])
		local x, y = Where(expedition.area, expedition.kind, shown)
		if x and leader then
			local fromX, fromY = cx or x, cy or y
			if cx then
				for step = 1, DOTS - 1 do
					local t = step / DOTS
					dots = dots + 1
					local dot = Dot(dots)
					dot:ClearAllPoints()
					dot:SetPoint("CENTER", map, "TOPLEFT", (fromX + (x - fromX) * t) * width, -(fromY + (y - fromY) * t) * height)
					dot:SetAlpha(t <= done and 0.9 or 0.35)
					dot:Show()
				end
			end
			marks = marks + 1
			local marker = Marker(marks)
			marker.portrait:Set(leader)
			marker.tip = { ns.PlaceName(expedition.area), ns.MemberNames(expedition.members), ns.BackWhen(expedition) }
			marker:ClearAllPoints()
			marker:SetPoint("CENTER", map, "TOPLEFT", (fromX + (x - fromX) * done) * width, -(fromY + (y - fromY) * done) * height)
			marker:Show()
		end
	end
	for index = dots + 1, #view.dots do view.dots[index]:Hide() end
	for index = marks + 1, #view.markers do view.markers[index]:Hide() end
	-- Under it, those on the road.
	local list = view.list
	list:Begin()
	ns.RunningRows(list)
	list:Done()
end

local function Build(page)
	view.pins, view.dots, view.markers = {}, {}, {}
	-- The continents to choose from (their names, the game's).
	local choices = {}
	for index, continent in ipairs(CONTINENTS) do
		local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, continent)
		choices[index] = { continent, type(info) == "table" and Clean(info.name) or tostring(continent) }
	end
	view.switch = Skin.Choices(page, choices, function(continent)
		shown = continent
		ns.Redraw()
	end, 28)
	view.switch:SetPoint("TOPLEFT")
	ns.UI.Fill(view.switch, page.width)
	-- The map, as wide as the page.
	local height = math.floor(page.width * 668 / 1002)
	view.map = ns.Banner(page, page.width, height)
	view.map:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -34)
	view.map.shade:Hide()
	view.map.top:Hide()
	view.camp = view.map:CreateTexture(nil, "OVERLAY")
	view.camp:SetSize(22, 22)
	view.camp:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
	ns.Crop(view.camp)
	Skin.RoundMask(view.map, view.camp)
	-- Those on the road, under it.
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(34 + height + 8))
	holder.width, holder.height = page.width, page.height - 34 - height - 8
	holder:SetSize(holder.width, holder.height)
	view.list = ns.UI.List(holder)
	page.list = view.list
	-- (the window opened again: the continent you are on, until another is chosen)
	ns.WindowFrame():HookScript("OnHide", function() shown = nil end)
end

ns.AddPage("map", L.MAP_TITLE, Build, Draw, { parent = "expeditions", icon = "Interface\\Icons\\INV_Misc_Map02" })
