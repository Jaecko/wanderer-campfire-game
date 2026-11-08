local _, ns = ...
local L = ns.L

-- The armory: whether it keeps the pieces no better than those worn (else the forge takes them apart), then
-- the pieces it holds, each with the companion it suits best (given in one click; right click or "...": its
-- card, given or taken apart, asked first for an epic one). Opened from a companion's slot, it shows first what fits that slot for them.

local W = Wanderer
local Skin = W and W.Skin

local view = {}
local GOLD = Skin.COLORS.gold

-- (taken apart: an epic piece asked first)
local function Salvage(kept)
	local function Go() if ns.Salvage(kept) > 0 then ns.Redraw() end end
	if ((ns.GEAR_ITEM[kept.item] or {}).quality or 0) >= 4 then
		return ns.Ask(L.ARMORY_SALVAGE_ASK:format(ns.PieceText(kept.item)), Go)
	end
	Go()
end

-- A piece's card (its right click, its "..."): given to the one it suits, or taken apart at the forge.
local function PieceCard(owner, kept, who, wearing)
	local rows = {}
	if who then
		rows[#rows + 1] = { text = wearing and L.ARMORY_WEAR or L.ARMORY_GIVE, glyph = "check",
			onClick = function() if ns.Equip(kept, who) then ns.Redraw() end end }
	end
	rows[#rows + 1] = { text = L.ARMORY_SALVAGE, glyph = "close", role = "bad", hint = L.ARMORY_SALVAGE_HINT,
		onClick = function() Salvage(kept) end }
	Skin.ActionCard(owner, { title = ns.PieceText(kept.item), rows = rows, atCursor = true })
end

-- (who: the companion it is shown for, else the one it suits best, and what it adds)
local function PieceRow(list, kept, who, gain, wearing)
	local piece = ns.GEAR_ITEM[kept.item] or {}
	local slot = ns.PieceSlot(kept.item)
	local sub = ns.SlotName(slot or "chest") .. ", " .. L.ITEM_LEVEL:format(piece.level or 0) .. "\n"
		.. (who and L.ARMORY_FOR:format(who.name, (gain >= 0 and "+" or "") .. gain) or Skin.Colorize(L.ARMORY_NOONE, "muted"))
	local tip = { ns.PieceName(kept.item) or "..." }
	if kept.area then tip[#tip + 1] = kept.area == "week" and L.FROM_WEEK or L.FOUND_AT:format(ns.PlaceName(kept.area)) end
	tip[#tip + 1] = L.ARMORY_SALVAGE_TIP
	list:Row({ icon = ns.PieceIcon(kept.item), quality = piece.quality, title = ns.PieceText(kept.item), sub = sub, wrap = true, tip = tip,
		onRight = function(row) PieceCard(row, kept, who, wearing) end,
		action = who and { text = wearing and L.ARMORY_WEAR or L.ARMORY_GIVE, fn = function()
			if ns.Equip(kept, who) then ns.Redraw() end
		end } or nil })
end

local function Draw(arg)
	local s = ns.State()
	local armory = ns.Armory()
	local list = view.list
	list:Begin()
	ns.Tip(list, "armory")
	-- Kept, or taken apart.
	list:Row({ icon = "Interface\\Icons\\INV_Box_01", title = L.ARMORY_KEEP, color = GOLD, sub = L.ARMORY_KEEP_DESC, wrap = true,
		chip = s.keepGear and L.ARMORY_ON or L.ARMORY_OFF, tone = s.keepGear and "green" or "grey",
		action = { text = s.keepGear and L.ARMORY_TURN_OFF or L.ARMORY_TURN_ON, fn = function()
			s.keepGear = not s.keepGear or nil
			ns.Redraw()
		end } })
	-- For a companion's slot first.
	local companion = type(arg) == "table" and ns.Companion(arg.id)
	if companion then
		list:Caption(L.ARMORY_SLOT:format(companion.name, ns.SlotName(arg.slot)))
		local any = false
		for _, kept in ipairs(armory) do
			if ns.PieceSlot(kept.item) == arg.slot and ns.CanWear(companion, kept.item) then
				any = true
				PieceRow(list, kept, companion, ns.WearGain(companion, kept.item), true)
			end
		end
		if not any then list:Text(L.ARMORY_SLOT_NONE, "muted") end
	end
	-- Everything it holds.
	list:Caption(L.ARMORY_ALL, #armory .. " / " .. ns.ARMORY_MAX)
	if not armory[1] then list:Text(L.ARMORY_EMPTY, "muted") end
	local useless = {}
	for _, kept in ipairs(armory) do
		local who, gain = ns.BestWearer(kept.item)
		if not gain or gain <= 0 then useless[#useless + 1] = kept end
		PieceRow(list, kept, who, gain)
	end
	-- Those no one needs, taken apart at once (asked first).
	if useless[1] then
		list:Gap(6)
		list:Row({ icon = "Interface\\Icons\\Trade_BlackSmithing", title = L.ARMORY_CLEAR, sub = L.ARMORY_CLEAR_DESC:format(#useless), wrap = true,
			action = { text = L.ARMORY_CLEAR_BUTTON, fn = function()
				ns.Ask(L.ARMORY_CLEAR_ASK:format(#useless), function()
					for _, kept in ipairs(useless) do ns.Salvage(kept) end
					ns.Redraw()
				end)
			end } })
	end
	list:Done()
end

local function Build(page)
	view.list = ns.UI.List(page)
end

ns.AddPage("armory", L.ARMORY, Build, Draw, { parent = "more", icon = "Interface\\Icons\\INV_Box_01", desc = L.ARMORY_DESC,
	summary = function()
		local count = #ns.Armory()
		if count > 0 then return tostring(count), "grey" end
	end })
