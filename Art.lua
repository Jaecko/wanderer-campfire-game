local _, ns = ...

-- The camp's pictures, all the game's own: a companion's round portrait (the face of an NPC, ringed in their
-- class's color, their level on a small seal), a place's banner (a zone's map, a dungeon's loading screen,
-- cropped to fill it, darkened at its foot for the words over it), the roles' signs, a companion standing in 3D
-- (turned by dragging). When the game cannot draw a face, the class's icon takes its place.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The camp's own warm gold (a fire's, a little softer than the kit's gold): seals, banners, cards.
ns.WARM = { 1, 0.82, 0.3 }
local WARM = ns.WARM
-- (its embers: the bars of how far along, a building's steps)
ns.EMBER = { 1, 0.72, 0.25 }

-- A texture shaded from one color (at its bottom, or left) to another (its top, or right).
function ns.Gradient(texture, vertical, r1, g1, b1, a1, r2, g2, b2, a2)
	texture:SetTexture(WHITE)
	texture:SetGradient(vertical and "VERTICAL" or "HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

-- The roles' signs (the group finder's round ones).
local ROLES = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { tank = { 0, 19 / 64, 22 / 64, 41 / 64 }, heal = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	dps = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }
function ns.RoleSign(texture, role)
	local coords = ROLE_COORDS[role] or ROLE_COORDS.dps
	texture:SetTexture(ROLES)
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end
function ns.RoleText(role, size)
	local coords = ROLE_COORDS[role] or ROLE_COORDS.dps
	size = size or 14
	return ("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t"):format(ROLES, size, size, coords[1] * 64, coords[2] * 64, coords[3] * 64, coords[4] * 64)
end

-- Portraits ---------------------------------------------------------------------------------------------------

-- The few words of a line apart: "Dwarf · Paladin".
ns.DOT = "  \194\183  "

-- An icon's edges cut away.
ns.CROP = { 0.08, 0.92, 0.08, 0.92 }
function ns.Crop(texture) texture:SetTexCoord(ns.CROP[1], ns.CROP[2], ns.CROP[3], ns.CROP[4]) end

-- A face drawn on a texture: the NPC's portrait, else the class's icon.
local function Face(texture, companion)
	if companion.look and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, texture, companion.look) then
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end
	local icon, coords = ns.ClassIcon(companion.class)
	texture:SetTexture(icon)
	if coords then texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else ns.Crop(texture) end
end

-- A round portrait: portrait:Set(companion, { level = shown, dim = faded, hurt = tinted }).
function ns.Portrait(parent, size, withLevel)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	-- (the kit's round portrait and its ring, on a dark ground; a red tint for the wounded)
	holder.face = Skin.RoundPortrait(holder, size)
	holder.face:SetPoint("CENTER")
	holder.ring = holder.face.ring
	holder.ring:SetShown(holder.face.ringShown)
	holder.ground = holder:CreateTexture(nil, "BACKGROUND")
	holder.ground:SetAllPoints()
	holder.ground:SetColorTexture(0.06, 0.05, 0.045, 1)
	Skin.RoundMask(holder, holder.ground)
	holder.tint = holder:CreateTexture(nil, "OVERLAY")
	holder.tint:SetAllPoints()
	holder.tint:SetColorTexture(0.7, 0.08, 0.05, 0.35)
	Skin.RoundMask(holder, holder.tint)
	holder.tint:Hide()
	if withLevel then
		local seal = CreateFrame("Frame", nil, holder)
		local seat = math.max(16, math.floor(size * 0.36))
		seal:SetSize(seat, seat)
		seal:SetPoint("CENTER", holder, "BOTTOMRIGHT", -seat * 0.28, seat * 0.28)
		seal.edge = seal:CreateTexture(nil, "BORDER")
		seal.edge:SetPoint("TOPLEFT", -1, 1)
		seal.edge:SetPoint("BOTTOMRIGHT", 1, -1)
		seal.edge:SetColorTexture(WARM[1], WARM[2], WARM[3], 0.9)
		Skin.RoundMask(seal, seal.edge)
		seal.ground = seal:CreateTexture(nil, "ARTWORK")
		seal.ground:SetAllPoints()
		seal.ground:SetColorTexture(0.08, 0.065, 0.05, 1)
		Skin.RoundMask(seal, seal.ground)
		seal.text = Skin.Text(seal, size >= 60 and "GameFontHighlight" or "GameFontHighlightSmall", "text")
		seal.text:SetPoint("CENTER", 0, 0)
		holder.seal = seal
	end
	function holder:Set(companion, opts)
		opts = opts or {}
		local color = ns.ClassColor(companion.class)
		self.ring:SetVertexColor(color[1], color[2], color[3], opts.dim and 0.4 or 0.95)
		Face(self.face, companion)
		self.face:SetDesaturated(opts.dim and true or false)
		self.face:SetAlpha(opts.dim and 0.7 or 1)
		self.tint:SetShown(opts.hurt and true or false)
		if self.seal then
			-- (its seal in the color of its rarity)
			local r, g, b = U.QualityColor(companion.rarity or 2)
			self.seal.edge:SetColorTexture(r or 1, g or 0.82, b or 0.3, 0.95)
			local level = opts.level or companion.level
			self.seal:SetShown(level ~= nil)
			self.seal.text:SetText(level or "")
		end
	end
	return holder
end

-- A 3D companion standing, turned by dragging it.
function ns.Figure(parent)
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
	if not (ok and model) then return nil end
	model:EnableMouse(true)
	model.facing = 0.35
	local lastX
	-- (turned while the button is held; let go anywhere, even with the window closed meanwhile, it stops)
	local function Stop(self) self:SetScript("OnUpdate", nil) end
	model:SetScript("OnMouseDown", function(self)
		lastX = GetCursorPosition()
		self:SetScript("OnUpdate", function()
			if not IsMouseButtonDown("LeftButton") then return Stop(self) end
			local x = GetCursorPosition()
			self.facing = self.facing + (x - lastX) * 0.012
			lastX = x
			pcall(self.SetFacing, self, self.facing)
		end)
	end)
	model:SetScript("OnMouseUp", Stop)
	model:SetScript("OnHide", Stop)
	function model:Show3D(companion)
		self.shown3D = companion.look
		if not companion.look or not pcall(self.SetDisplayInfo, self, companion.look) then
			self:Hide()
			return false
		end
		pcall(self.SetPortraitZoom, self, 0)
		pcall(self.SetCamDistanceScale, self, 1.15)
		pcall(self.SetPosition, self, 0, 0, -0.05)
		pcall(self.SetFacing, self, self.facing)
		self:Show()
		return true
	end
	return model
end

-- Banners -----------------------------------------------------------------------------------------------------

-- The picture of a place laid over a frame: cropped so it fills it, centered (pieces: the textures to show).
local function Cover(banner, pieces, width, height)
	local boxWidth, boxHeight = banner:GetWidth(), banner:GetHeight()
	local scale = math.max(boxWidth / width, boxHeight / height)
	local left, top = (width * scale - boxWidth) / 2, (height * scale - boxHeight) * 0.45
	for index, piece in ipairs(pieces) do
		local tile = banner.tiles[index]
		if not tile then
			tile = banner:CreateTexture(nil, "BACKGROUND")
			banner.tiles[index] = tile
		end
		-- (the piece in the picture's pixels; what of it falls within the frame)
		local x1, y1 = piece.x * scale - left, piece.y * scale - top
		local x2, y2 = x1 + piece.width * scale, y1 + piece.height * scale
		local cx1, cy1, cx2, cy2 = math.max(0, x1), math.max(0, y1), math.min(boxWidth, x2), math.min(boxHeight, y2)
		if cx2 - cx1 < 0.5 or cy2 - cy1 < 0.5 then
			tile:Hide()
		else
			local u1, v1 = piece.u1 + (cx1 - x1) / (x2 - x1) * (piece.u2 - piece.u1), piece.v1 + (cy1 - y1) / (y2 - y1) * (piece.v2 - piece.v1)
			local u2, v2 = piece.u1 + (cx2 - x1) / (x2 - x1) * (piece.u2 - piece.u1), piece.v1 + (cy2 - y1) / (y2 - y1) * (piece.v2 - piece.v1)
			tile:SetTexture(piece.file)
			tile:SetTexCoord(u1, u2, v1, v2)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", banner, "TOPLEFT", cx1, -cy1)
			tile:SetSize(cx2 - cx1, cy2 - cy1)
			tile:Show()
		end
	end
	for index = #pieces + 1, #banner.tiles do banner.tiles[index]:Hide() end
end

-- A map's picture as pieces (its tiles), with its size; nil when the game has none.
local function MapPieces(map)
	local layers = C_Map and C_Map.GetMapArtLayers and Safe(C_Map.GetMapArtLayers, map)
	local layer = type(layers) == "table" and layers[1]
	local textures = layer and C_Map.GetMapArtLayerTextures and Safe(C_Map.GetMapArtLayerTextures, map, 1)
	if not (layer and type(textures) == "table" and textures[1]) then return nil end
	local width, height = Clean(layer.layerWidth) or 1002, Clean(layer.layerHeight) or 668
	local tileWidth, tileHeight = Clean(layer.tileWidth) or 256, Clean(layer.tileHeight) or 256
	local columns = math.ceil(width / tileWidth)
	local pieces = {}
	for index, file in ipairs(textures) do
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		local w, h = math.min(tileWidth, width - column * tileWidth), math.min(tileHeight, height - row * tileHeight)
		if w > 0 and h > 0 then
			pieces[#pieces + 1] = { file = file, x = column * tileWidth, y = row * tileHeight, width = w, height = h,
				u1 = 0, u2 = w / tileWidth, v1 = 0, v2 = h / tileHeight }
		end
	end
	return pieces, width, height
end

-- A place's picture as pieces (its zone's map, or its loading screen), with its size; nil when it has none.
local function Pieces(area)
	local art = ns.PLACE_ART and ns.PLACE_ART[area]
	if not art then return nil end
	if art.file then
		local height = 1000
		return { { file = art.file, x = 0, y = 0, width = height * art.aspect, height = height, u1 = 0, u2 = 1, v1 = 0, v2 = 1 } },
			height * art.aspect, height
	end
	return MapPieces(art.map)
end

-- A banner: banner:Set(area) draws the place (or a warm dusk when the game has no picture of it).
function ns.Banner(parent, width, height)
	local banner = CreateFrame("Frame", nil, parent)
	banner:SetSize(width, height)
	banner.tiles = {}
	banner.dusk = banner:CreateTexture(nil, "BACKGROUND", nil, -2)
	banner.dusk:SetAllPoints()
	ns.Gradient(banner.dusk, true, 0.05, 0.04, 0.035, 1, 0.22, 0.13, 0.07, 1)
	banner.shade = banner:CreateTexture(nil, "BORDER")
	banner.shade:SetPoint("BOTTOMLEFT")
	banner.shade:SetPoint("BOTTOMRIGHT")
	banner.shade:SetHeight(height * 0.75)
	ns.Gradient(banner.shade, true, 0.03, 0.025, 0.02, 0.95, 0.03, 0.025, 0.02, 0)
	banner.top = banner:CreateTexture(nil, "BORDER")
	banner.top:SetPoint("TOPLEFT")
	banner.top:SetPoint("TOPRIGHT")
	banner.top:SetHeight(height * 0.3)
	ns.Gradient(banner.top, true, 0.03, 0.025, 0.02, 0, 0.03, 0.025, 0.02, 0.5)
	banner.edges = Skin.Edges(banner, WARM[1], WARM[2], WARM[3], 0.18)
	function banner:Set(area)
		if self.area == area and self.drawn then return end
		self.area = area
		local pieces, w, h = Pieces(area)
		self.drawn = pieces ~= nil
		Cover(self, pieces or {}, w or 1, h or 1)
	end
	-- (a whole map instead: a continent, for the expeditions' map)
	function banner:SetMap(map)
		if self.map == map and self.drawn then return end
		self.map, self.area = map, nil
		local pieces, w, h = MapPieces(map)
		self.drawn = pieces ~= nil
		Cover(self, pieces or {}, w or 1, h or 1)
	end
	return banner
end
