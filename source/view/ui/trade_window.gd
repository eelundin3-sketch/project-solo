extends Control
## Trading and talking with someone, as a frontier ledger: a portrait medallion with their name,
## trade, town and mood; what they last said to you in a speech bubble; their goods and yours in
## two ruled columns with item pictures, stock, prices and Buy / Sell buttons; and along the foot
## both purses, the terms you have haggled, and the things you can say to them.
## Everything shown is read from the simulation; every button submits a command.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Market = preload("res://sim/economy/market.gd")
const ItemIcons = preload("res://view/ui/item_icons.gd")
const Dialogue = preload("res://sim/player/dialogue.gd")
const TABS := 32.0   # the Trade / Talk tab row
const TALK_ROW := 36.0   # a line on the Talk tab (seven fit where five trade rows do)
const TALK_MAX := 7

signal close_requested
signal minimize_requested

const WIDTH := 800.0
const ROW := 52.0
const BAR := 34.0
const RADIUS := 12
# Palette: dark wood, parchment and ink.
const WOOD := Color("231a12")
const WOOD_EDGE := Color("5b4429")
const PAPER := Color("efe2c2")
const PAPER_SHADE := Color("e2d1aa")
const RULE := Color(0.42, 0.31, 0.18, 0.28)
const INK := Color("33251a")
const INK_SOFT := Color("6e5a42")
const BRASS := Color("c9a25a")
const BUY := Color("4f7a4a")
const SELL := Color("9a5a2c")
const DISABLED := Color(0.45, 0.4, 0.33, 0.45)
const NAMES := {"log": "Logs", "plank": "Planks", "food": "Bread", "rye": "Rye", "bandage": "Bandages", "antiseptic": "Antiseptic",
	"ore": "Iron ore", "tool": "Iron tools", "shell": "Shells", "shotgun": "Shotgun", "rifle": "Rifle", "cartridge": "Cartridges"}

var simulation: RefCounted
var target: int = 0
var tab: String = "trade"         # "trade" or "talk": view state only (the panels set it on opening)
var buttons: Array = []          # [{rect, kind, payload, enabled}]
var hover: int = -1
var dragging := false
var drag_offset := Vector2.ZERO
var _serif: Font
var _sans: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit(2)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Baskerville", "Georgia", "Times New Roman", "serif"])
	serif.font_weight = 600
	_serif = serif
	_sans = ThemeDB.fallback_font

func home_position() -> Vector2:
	return ((get_viewport_rect().size - size) * 0.5).floor()

## The window fits its longest column (two to five rows).
func _fit(rows: int) -> void:
	var wanted := Vector2(WIDTH, BAR + 6 + 16 + 96 + 30 + TABS + rows * ROW + 78)
	if size != wanted:
		size = wanted
		custom_minimum_size = wanted

func show_for(id: int) -> void:
	target = id
	queue_redraw()

func refresh(s: Dictionary) -> void:
	if s.get("entities", {}).has(str(target)):
		var tabs: Array = Dialogue.tabs(s, target)
		if not tab in tabs: tab = tabs[0]
		if tab == "talk":
			_fit(clampi(ceili(Dialogue.options(s, target).size() * TALK_ROW / ROW), 2, 5))
		else:
			var goods: Array = _goods(s)
			_fit(clampi(maxi(goods[0].size(), goods[1].size()), 2, 5))
	queue_redraw()

# --- what is shown -------------------------------------------------------------------------------

func _state() -> Dictionary:
	return simulation.state if simulation != null else {}

func _counterpart(s: Dictionary) -> Dictionary:
	return load("res://sim/economy/stall_service.gd").counterpart(s, target)

func _price(s: Dictionary, item: String, buying: bool) -> int:
	var e: Dictionary = s.entities.get(str(target), {})
	return load("res://sim/economy/stall_service.gd").price(s, int(e.get("settlement", 1)), item, buying, target)

## What they sell (their stock) and what they would buy from you.
func _goods(s: Dictionary) -> Array:
	var e: Dictionary = s.entities.get(str(target), {})
	var deals: Array = e.get("sale_items", []) if e.get("kind", "") == "market_stall" else Market.BASE.keys()
	var theirs: Array = []
	var yours: Array = []
	for item in deals:
		if Inventory.amount(s, target, item) > 0: theirs.append(item)
		if Inventory.amount(s, s.player, item) > 0: yours.append(item)
	if e.get("kind", "") == "market_stall":
		for item in deals:
			if not item in theirs: theirs.append(item)   # a stall shows its whole line, even sold out
	return [theirs, yours]

# --- drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	buttons.clear()
	var s: Dictionary = _state()
	var e: Dictionary = s.get("entities", {}).get(str(target), {})
	if e.is_empty(): return
	var npc: Dictionary = _counterpart(s)
	var person: Dictionary = s.entities.get(str(npc.get("id", 0)), {})
	# Frame: a dark wooden board with a parchment sheet set into it.
	var frame := StyleBoxFlat.new()
	frame.bg_color = WOOD
	frame.set_corner_radius_all(RADIUS)
	frame.border_color = WOOD_EDGE
	frame.set_border_width_all(2)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 22
	frame.shadow_offset = Vector2(0, 8)
	frame.anti_aliasing = true
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	var stall_name: String = String(e.name)
	var tabs: Array = Dialogue.tabs(s, target)
	if not tab in tabs: tab = tabs[0]
	var title: String = ("Trading at %s" % stall_name if "'s " in stall_name else "Trading at the %s" % stall_name) if e.kind == "market_stall" else "Trading with %s" % e.name
	if tab == "talk": title = "Talking with %s" % String(person.get("name", e.name))
	draw_string(_serif, Vector2(0, BAR * 0.5 + 6.0), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color("e9dcbc"))
	_window_buttons()
	var sheet := Rect2(Vector2(12, BAR + 6), size - Vector2(24, BAR + 18))
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(8)
	paper.anti_aliasing = true
	draw_style_box(paper, sheet)
	draw_rect(sheet.grow(-6), Color(0.45, 0.32, 0.17, 0.18), false, 1.0)
	# Header: portrait, name and trade, mood; and what they said.
	var top := sheet.position + Vector2(18, 16)
	_portrait(top + Vector2(38, 38), person, npc)
	var first: String = String(person.get("name", "")).split(" ")[0] if not person.is_empty() else ""
	var name_line: String = String(person.get("name", "Nobody at the counter")) if not person.is_empty() else "Nobody at the counter"
	draw_string(_serif, top + Vector2(92, 26), name_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	var town: String = str(s.get("settlements", {}).get(str(e.get("settlement", 0)), {}).get("name", ""))
	var sub: String = "%s  ·  %s" % [String(npc.get("occupation", "Villager")), town] if not npc.is_empty() else town
	draw_string(_sans, top + Vector2(93, 47), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_SOFT)
	_mood_chip(top + Vector2(93, 56), npc)
	if e.kind == "market_stall" and not npc.is_empty():
		draw_string(_sans, top + Vector2(146, 69), "at the counter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
	var said: String = _last_words(s, first)
	_speech(Rect2(top + Vector2(400, 0), Vector2(sheet.size.x - 436, 78)), said)
	# Tabs: Trade and Talk.
	var tab_x: float = sheet.position.x + 18
	for name in tabs:
		var label: String = "Trade" if name == "trade" else "Talk"
		var w: float = _sans.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
		_tab(Rect2(Vector2(tab_x, top.y + 90), Vector2(w, 26)), label, name)
		tab_x += w + 6
	draw_line(Vector2(sheet.position.x + 18, top.y + 116), Vector2(sheet.end.x - 18, top.y + 116), RULE, 1.0)
	var columns_top: float = top.y + 96 + TABS
	if tab == "talk":
		_talk(Rect2(Vector2(sheet.position.x + 18, columns_top), Vector2(sheet.size.x - 36, sheet.end.y - columns_top - 64)), s, npc)
		var talk_foot: float = sheet.end.y - 52
		draw_line(Vector2(sheet.position.x + 18, talk_foot - 10), Vector2(sheet.end.x - 18, talk_foot - 10), RULE, 1.0)
		draw_string(_serif, Vector2(sheet.position.x + 22, talk_foot + 22), Dialogue.standing_line(s, npc), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK_SOFT)
		return
	# The two ledgers.
	var goods: Array = _goods(s)
	var column_width: float = (sheet.size.x - 54) * 0.5
	_ledger(Rect2(Vector2(sheet.position.x + 18, columns_top), Vector2(column_width, 300)), "FOR SALE", goods[0], true, s)
	_ledger(Rect2(Vector2(sheet.position.x + 36 + column_width, columns_top), Vector2(column_width, 300)), "YOU CAN SELL", goods[1], false, s)
	# Foot: purses, terms and talk.
	var foot_y: float = sheet.end.y - 52
	draw_line(Vector2(sheet.position.x + 18, foot_y - 10), Vector2(sheet.end.x - 18, foot_y - 10), RULE, 1.0)
	_coin(Vector2(sheet.position.x + 30, foot_y + 16))
	draw_string(_sans, Vector2(sheet.position.x + 44, foot_y + 12), "Your purse", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
	draw_string(_serif, Vector2(sheet.position.x + 44, foot_y + 30), "%d coins" % int(s.accounts.get(str(s.player), 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	_coin(Vector2(sheet.position.x + 170, foot_y + 16))
	draw_string(_sans, Vector2(sheet.position.x + 184, foot_y + 12), "Their till", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
	draw_string(_serif, Vector2(sheet.position.x + 184, foot_y + 30), "%d coins" % int(s.accounts.get(str(target), 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	_terms_chip(Vector2(sheet.position.x + 300, foot_y + 6), s)
	var talk_to: int = int(npc.get("id", 0))
	var x: float = sheet.end.x - 18
	for spec in [["Haggle", "haggle"]]:   # asking questions lives on the Talk tab
		var w: float = _sans.get_string_size(spec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 26
		x -= w
		var kind: String = spec[1]
		var payload: Dictionary = {"target": target} if kind == "haggle" else {"target": talk_to, "action": kind}
		_button(Rect2(Vector2(x, foot_y + 4), Vector2(w, 30)), spec[0], kind, payload, talk_to != 0, Color("5b4429"))
		x -= 8

func _window_buttons() -> void:
	var colors := [Color("ff5f57"), Color("febc2e")]
	for index in range(2):
		var c := Vector2(20.0 + index * 20.0, BAR * 0.5)
		draw_circle(c, 6.2, colors[index])
		draw_arc(c, 6.2, 0.0, TAU, 20, colors[index].darkened(0.25), 0.8, true)
	buttons.append({"rect": Rect2(Vector2(12, 9), Vector2(16, 16)), "kind": "close", "payload": {}, "enabled": true})
	buttons.append({"rect": Rect2(Vector2(32, 9), Vector2(16, 16)), "kind": "minimize", "payload": {}, "enabled": true})

## A round medallion: their clothes' colour, their initials, a brass rim.
func _portrait(c: Vector2, person: Dictionary, npc: Dictionary) -> void:
	draw_circle(c + Vector2(0, 3), 37, Color(0, 0, 0, 0.18))
	draw_circle(c, 36, BRASS)
	draw_circle(c, 32, Color("4b3a28"))
	var tone: Color = Color.from_hsv(fmod(float(npc.get("id", 1)) * 0.137, 1.0), 0.35, 0.62)
	draw_circle(c, 30, tone)
	draw_circle(c + Vector2(0, -6), 13, Color("e3c29b"))           # a face
	draw_colored_polygon(PackedVector2Array([c + Vector2(-22, 26), c + Vector2(-16, 8), c + Vector2(16, 8), c + Vector2(22, 26)]), tone.darkened(0.3))   # shoulders
	draw_colored_polygon(PackedVector2Array([c + Vector2(-19, -14), c + Vector2(19, -14), c + Vector2(13, -22), c + Vector2(-13, -22)]), Color("5a4330"))   # a hat
	draw_line(c + Vector2(-24, -14), c + Vector2(24, -14), Color("4a3626"), 3.0)
	var parts: PackedStringArray = String(person.get("name", "?")).split(" ")
	var initials: String = (parts[0].left(1) + (parts[-1].left(1) if parts.size() > 1 else "")).to_upper()
	draw_circle(c + Vector2(24, 24), 12, PAPER)
	draw_arc(c + Vector2(24, 24), 12, 0, TAU, 24, BRASS, 1.5, true)
	draw_string(_serif, c + Vector2(13, 29), initials, HORIZONTAL_ALIGNMENT_CENTER, 22, 11, INK)

func _mood_chip(at: Vector2, npc: Dictionary) -> void:
	if npc.is_empty(): return
	var feeling: Array = Dialogue.feeling(_state(), npc)   # what they remember of you (society.gd opinion)
	var tints := {"angry": Color("a2382c"), "wary": Color("b0812f"), "friendly": Color("4f7a4a"), "calm": Color("6b7f8c")}
	var mood: Array = [feeling[0], tints.get(feeling[1], Color("6b7f8c"))]
	var w: float = _sans.get_string_size(mood[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(mood[1], 0.16)
	chip.border_color = mood[1]
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(9)
	draw_style_box(chip, Rect2(at, Vector2(w, 18)))
	draw_string(_sans, at + Vector2(9, 13), mood[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mood[1].darkened(0.2))

## What they last said to the player (the notice, when it is their line), else a greeting.
func _last_words(s: Dictionary, first: String) -> String:
	var notice: String = str(s.get("player_control", {}).get("notice", ""))
	if not first.is_empty() and notice.begins_with(first + ":"): return notice.substr(first.length() + 1).strip_edges()
	if first.is_empty(): return "There is nobody behind the counter. Wait for them, or come back later."
	return "Good day to you. Have a look."

func _speech(box: Rect2, text: String) -> void:
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color("fbf4e2")
	bubble.border_color = Color(0.42, 0.31, 0.18, 0.55)
	bubble.set_border_width_all(1)
	bubble.set_corner_radius_all(12)
	bubble.anti_aliasing = true
	draw_style_box(bubble, box)
	draw_colored_polygon(PackedVector2Array([box.position + Vector2(-12, 30), box.position + Vector2(1, 22), box.position + Vector2(1, 40)]), Color("fbf4e2"))
	draw_line(box.position + Vector2(-12, 30), box.position + Vector2(0, 22), Color(0.42, 0.31, 0.18, 0.55), 1.0)
	draw_line(box.position + Vector2(-12, 30), box.position + Vector2(0, 40), Color(0.42, 0.31, 0.18, 0.55), 1.0)
	draw_multiline_string(_serif, box.position + Vector2(14, 24), "“%s”" % text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 14, 3, INK)

## A ruled column of goods: picture, name, stock, price, buttons.
func _ledger(area: Rect2, heading: String, items: Array, theirs: bool, s: Dictionary) -> void:
	draw_string(_serif, area.position + Vector2(0, 14), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_SOFT)
	draw_line(area.position + Vector2(0, 22), area.position + Vector2(area.size.x, 22), INK_SOFT, 1.2)
	if items.is_empty():
		draw_string(_serif, area.position + Vector2(0, 52), "Nothing they deal in." if not theirs else "Nothing for sale just now.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_SOFT)
		return
	var row_h := ROW
	for index in range(mini(items.size(), 5)):
		var item: String = items[index]
		var y: float = area.position.y + 28 + index * row_h
		var row := Rect2(Vector2(area.position.x, y), Vector2(area.size.x, row_h - 4))
		if index % 2 == 0: draw_rect(row, Color(PAPER_SHADE, 0.55))
		draw_circle(row.position + Vector2(24, row_h * 0.5 - 2), 19, Color("fbf4e2"))
		draw_arc(row.position + Vector2(24, row_h * 0.5 - 2), 19, 0, TAU, 28, Color(0.42, 0.31, 0.18, 0.35), 1.0, true)
		ItemIcons.draw(self, item, row.position + Vector2(24, row_h * 0.5 - 2), 1.0)
		var stock: int = Inventory.amount(s, target if theirs else s.player, item)
		var unit: int = _price(s, item, theirs)
		draw_string(_serif, row.position + Vector2(52, 20), NAMES.get(item, item.capitalize()), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
		var stock_text: String = ("%d in stock" % stock) if theirs else ("you have %d" % stock)
		draw_string(_sans, row.position + Vector2(52, 38), stock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
		var town: int = int(s.entities.get(str(target), {}).get("settlement", 1))
		var elsewhere: Dictionary = Market.better_elsewhere(s, town, item, theirs, unit)
		if not elsewhere.is_empty():
			var hint: String = "· %s %d c" % [elsewhere.name, int(elsewhere.price)]   # cheaper there (buying) or dearer there (selling)
			var x: float = 56.0 + _sans.get_string_size(stock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(_sans, row.position + Vector2(x, 38), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK_SOFT, 0.45) if elsewhere.stale else Color("6b4a1e"))
		var price_text := "%d c" % unit
		draw_string(_serif, row.position + Vector2(row.size.x - 156, 30), price_text, HORIZONTAL_ALIGNMENT_RIGHT, 52, 16, INK)
		var price_width: float = _serif.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_trend_arrow(row.position + Vector2(row.size.x - 112 - price_width, 25), Market.trend(s, town, item))
		var purse: int = int(s.accounts.get(str(s.player if theirs else target), 0))
		var can_one: bool = stock >= 1 and purse >= unit
		var color: Color = BUY if theirs else SELL
		if theirs:
			_button(Rect2(row.position + Vector2(row.size.x - 98, 9), Vector2(44, 28)), "Buy 1", "trade", {"target": target, "item": item, "buy": true, "quantity": 1}, can_one, color)
			_button(Rect2(row.position + Vector2(row.size.x - 50, 9), Vector2(48, 28)), "Buy 5", "trade", {"target": target, "item": item, "buy": true, "quantity": 5}, stock >= 1 and purse >= unit, color)
		else:
			_button(Rect2(row.position + Vector2(row.size.x - 98, 9), Vector2(44, 28)), "Sell 1", "trade", {"target": target, "item": item, "buy": false, "quantity": 1}, can_one, color)
			_button(Rect2(row.position + Vector2(row.size.x - 50, 9), Vector2(48, 28)), "All", "trade", {"target": target, "item": item, "buy": false, "quantity": -1}, can_one, color)

## A small arrow beside a price: up (dearer than yesterday) or down (cheaper); nothing if the same.
func _trend_arrow(at: Vector2, direction: int) -> void:
	if direction == 0: return
	var up: bool = direction > 0
	var tip := at + Vector2(0, -4 if up else 4)
	var points := PackedVector2Array([tip, at + Vector2(-4, 3 if up else -3), at + Vector2(4, 3 if up else -3)])
	draw_colored_polygon(points, Color("9b3a2a") if up else Color("3f6b34"))

func _button(rect: Rect2, text: String, kind: String, payload: Dictionary, enabled: bool, color: Color) -> void:
	var index: int = buttons.size()
	buttons.append({"rect": rect, "kind": kind, "payload": payload, "enabled": enabled})
	var box := StyleBoxFlat.new()
	var hot: bool = enabled and index == hover
	box.bg_color = (color.lightened(0.12) if hot else color) if enabled else DISABLED
	box.set_corner_radius_all(6)
	box.border_color = color.darkened(0.35) if enabled else Color(0, 0, 0, 0.1)
	box.set_border_width_all(1)
	box.shadow_color = Color(0, 0, 0, 0.18 if enabled else 0.0)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 1)
	box.anti_aliasing = true
	draw_style_box(box, rect)
	draw_string(_sans, rect.position + Vector2(0, rect.size.y * 0.5 + 4.5), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color("fbf4e2") if enabled else Color(1, 1, 1, 0.6))

## A tab at the top of the sheet; the open one looks like part of the page.
func _tab(rect: Rect2, label: String, name: String) -> void:
	var open: bool = name == tab
	buttons.append({"rect": rect, "kind": "tab", "payload": {"tab": name}, "enabled": true})
	var box := StyleBoxFlat.new()
	box.bg_color = Color("fbf4e2") if open else Color(PAPER_SHADE, 0.9 if buttons.size() - 1 == hover else 0.6)
	box.border_color = Color(0.42, 0.31, 0.18, 0.55 if open else 0.3)
	box.set_border_width_all(1)
	box.border_width_bottom = 0 if open else 1
	box.corner_radius_top_left = 7
	box.corner_radius_top_right = 7
	box.anti_aliasing = true
	draw_style_box(box, rect)
	draw_string(_serif if open else _sans, rect.position + Vector2(0, 18), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14 if open else 13, INK if open else INK_SOFT)

## The Talk tab: what you can say, one ruled row each (dialogue.gd decides the list).
func _talk(area: Rect2, s: Dictionary, npc: Dictionary) -> void:
	var talk_options: Array = Dialogue.options(s, target)
	if talk_options.is_empty():
		draw_string(_serif, area.position + Vector2(0, 30), "There's nobody here to talk to.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK_SOFT)
		return
	for index in range(mini(talk_options.size(), TALK_MAX)):
		var option: Dictionary = talk_options[index]
		var y: float = area.position.y + index * TALK_ROW
		var row := Rect2(Vector2(area.position.x, y), Vector2(area.size.x, TALK_ROW - 4))
		if index % 2 == 0: draw_rect(row, Color(PAPER_SHADE, 0.55))
		draw_string(_serif, row.position + Vector2(16, 21), "“%s”" % str(option.label), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 260, 15, INK if bool(option.enabled) else INK_SOFT)
		if not str(option.get("reason", "")).is_empty() and not bool(option.enabled):
			draw_string(_sans, row.position + Vector2(row.size.x - 250, 29), str(option.reason), HORIZONTAL_ALIGNMENT_RIGHT, 120, 11, INK_SOFT)
		_button(Rect2(row.position + Vector2(row.size.x - 100, 4), Vector2(92, 24)), "Say it", "context",
			{"target": int(npc.get("id", 0)), "action": str(option.id)}, bool(option.enabled), Color("5b4429"))

func _coin(c: Vector2) -> void:
	draw_circle(c, 8, Color("d9b45a"))
	draw_arc(c, 8, 0, TAU, 20, Color("8a6a2a"), 1.2, true)
	draw_arc(c, 5, 0, TAU, 16, Color("b08a3a"), 1.0, true)

func _terms_chip(at: Vector2, s: Dictionary) -> void:
	var terms: Dictionary = s.get("player_control", {}).get("trade_terms", {})
	var pct: int = int(terms.get("pct", 0)) if int(terms.get("target", 0)) == target else 0
	var text: String = "Usual prices" if pct == 0 else ("%d%% off" % -pct if pct < 0 else "%d%% dearer" % pct)
	var tint: Color = INK_SOFT if pct == 0 else (BUY if pct < 0 else Color("a2382c"))
	draw_string(_sans, at + Vector2(0, 6), "Terms", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
	draw_string(_serif, at + Vector2(0, 24), text, HORIZONTAL_ALIGNMENT_LEFT, 128, 13, tint)

# --- input ---------------------------------------------------------------------------------------

func _button_at(point: Vector2) -> int:
	for index in range(buttons.size()):
		if buttons[index].rect.has_point(point): return index
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var index: int = _button_at(event.position)
			if index >= 0:
				var button: Dictionary = buttons[index]
				if bool(button.enabled): _press(button)
			elif event.position.y <= BAR:
				dragging = true
				drag_offset = event.position
			accept_event()
		else:
			dragging = false
	elif event is InputEventMouseMotion:
		if dragging:
			var view := get_viewport_rect().size
			var wanted: Vector2 = get_global_mouse_position() - drag_offset
			position = Vector2(clampf(wanted.x, -size.x + 80.0, view.x - 80.0), clampf(wanted.y, 0.0, view.y - BAR))
			accept_event()
		var over: int = _button_at(event.position)
		if over != hover:
			hover = over
			queue_redraw()

func _press(button: Dictionary) -> void:
	match str(button.kind):
		"close": close_requested.emit()
		"minimize": minimize_requested.emit()
		"trade": simulation.submit("person_trade", button.payload)
		"haggle": simulation.submit("haggle", button.payload)
		"tab":
			tab = str(button.payload.tab)
			refresh(_state())
		_: simulation.submit("context_action", button.payload)
	queue_redraw()
