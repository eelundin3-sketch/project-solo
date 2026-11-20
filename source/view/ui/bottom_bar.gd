extends Control
const ItemIcons = preload("res://view/ui/item_icons.gd")
## Bottom-of-screen controls: the stamina bar and four-slot hotbar with the inventory
## and health buttons (bottom centre), and the clock with time-lapse controls (bottom right).
signal action(kind: String)
signal slot_pressed(index: int)
const SLOT := 56.0
const GAP := 4.0
const GOLD := Color("c79a3e")
const PANEL := Color("8a6a3c")
const PANEL_DARK := Color("6d5230")
const SPEEDS: Array[int] = [1, 2, 3, 5]
var simulation: RefCounted
var clock: RefCounted
var hover: String = ""
## Set by the owner while a modal panel covers the bar.
var blocked: bool = false

## An invisible target over one hotbar slot that accepts items dragged out of the inventory.
class SlotDrop extends Control:
	var bar: Control
	var index: int = 0
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "solo_item" and data.get("from", "") == "grid" and not str(data.item).contains(":")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		bar.simulation.submit("hotbar_assign", {"slot": index, "item": data.item})

var drop_zones: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Full-screen and see-through: clicks are picked out in _input so everything underneath keeps working.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(4):
		var zone := SlotDrop.new()
		zone.bar = self
		zone.index = index
		zone.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(zone)
		drop_zones.append(zone)
	resized.connect(_place_drop_zones)
	_place_drop_zones()

func _place_drop_zones() -> void:
	var rects := _layout()
	for index in range(drop_zones.size()):
		drop_zones[index].position = rects["slot%d" % index].position
		drop_zones[index].size = rects["slot%d" % index].size

var drawn_signature: int = 0
## Repaints only when something it shows has changed: stamina, the hotbar and its counts, the
## shotgun's load, the day and hour, the speed, or the hover. It used to repaint every tick.
func refresh() -> void:
	if simulation == null: return
	var s: Dictionary = simulation.state
	var hotbar: Dictionary = s.get("hotbar", {})
	var signature: int = [s.get("player_health", {}).get("stamina", 100), s.get("player_health", {}).get("stamina_max", 100),
		hotbar.hash(), s.get("inventories", {}).get(str(s.get("player", 0)), {}).get("items", {}).hash(),
		s.get("shotgun", {}).get("equipped", false), s.get("shotgun", {}).get("loaded", 0),
		int(s.tick) / 600, clock.paused if clock != null else false, clock.speed if clock != null else 1, hover, blocked, size].hash()
	if signature == drawn_signature: return
	drawn_signature = signature
	queue_redraw()

func _layout() -> Dictionary:
	var rects: Dictionary = {}
	var total := SLOT * 7 + GAP * 6 + 18.0
	var left := (size.x - total) * 0.5
	var top := size.y - SLOT - 18.0
	for index in range(4):
		rects["slot%d" % index] = Rect2(left + index * (SLOT + GAP), top, SLOT, SLOT)
	var after := left + 4 * (SLOT + GAP) + 18.0
	rects["inventory"] = Rect2(after, top, SLOT, SLOT)
	rects["health"] = Rect2(after + SLOT + GAP, top, SLOT, SLOT)
	rects["map"] = Rect2(after + 2 * (SLOT + GAP), top, SLOT, SLOT)
	rects["stamina"] = Rect2(left, top - 30.0, total - 0.0, 8.0)
	var clock_left := size.x - 214.0
	rects["slower"] = Rect2(clock_left, size.y - 46.0, 44, 30)
	rects["speed"] = Rect2(clock_left + 48, size.y - 46.0, 56, 30)
	rects["pause"] = Rect2(clock_left + 108, size.y - 46.0, 30, 30)
	rects["faster"] = Rect2(clock_left + 142, size.y - 46.0, 44, 30)
	return rects

func _input(event: InputEvent) -> void:
	if blocked:
		if hover != "":
			hover = ""
			queue_redraw()
		return
	var rects := _layout()
	if event is InputEventMouseMotion:
		var found := ""
		for key in rects:
			if key != "stamina" and rects[key].has_point(event.position): found = key
		if found != hover:
			hover = found
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for key in rects:
			if key == "stamina" or not rects[key].has_point(event.position): continue
			get_viewport().set_input_as_handled()
			if key.begins_with("slot"): slot_pressed.emit(int(key.substr(4)))
			else: action.emit(key)
			return

func _frame(rect: Rect2, active: bool = false, lit: bool = false) -> void:
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, PANEL.lightened(0.12) if lit else PANEL)
	draw_rect(rect.grow(-3), PANEL_DARK.lerp(PANEL, 0.4), false, 1.0)
	draw_rect(rect, GOLD if active else Color("3b2a1d"), false, 2.5 if active else 1.5)

func _draw() -> void:
	if simulation == null: return
	var s: Dictionary = simulation.state
	var font: Font = ThemeDB.fallback_font
	var rects := _layout()
	# Stamina: a thin blue bar above the hotbar, like the reference.
	var health: Dictionary = s.get("player_health", {})
	var fill: float = clampf(float(health.get("stamina", 100)) / maxf(1.0, float(health.get("stamina_max", 100))), 0.0, 1.0)
	var bar: Rect2 = rects.stamina
	draw_rect(bar, Color(0.05, 0.08, 0.1, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color("4aa3c4") if fill > 0.2 else Color("c4694a"))
	draw_rect(bar, Color("1c2a30"), false, 1.0)
	var hotbar: Dictionary = s.get("hotbar", {"slots": ["", "", "", ""], "active": 0})
	for index in range(4):
		var rect: Rect2 = rects["slot%d" % index]
		var item: String = hotbar.slots[index]
		var active: bool = hotbar.active == index
		_frame(rect, active, hover == "slot%d" % index)
		draw_string(font, rect.position + Vector2(rect.size.x * 0.5 - 4, -6), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f0e4c8"))
		if item != "":
			var have: int = int(s.get("inventories", {}).get(str(s.player), {}).get("items", {}).get(item, 0))
			_icon(item, rect.get_center() + Vector2(0, -2), 1.0 if have > 0 else 0.35)
			if have > 1 or item in ["cartridge", "shell", "food", "rye", "log", "plank", "bandage", "antiseptic", "ore", "tool"]:
				draw_string(font, rect.position + Vector2(rect.size.x - 20, rect.size.y - 5), str(have), HORIZONTAL_ALIGNMENT_RIGHT, 16, 12, Color("f0e4c8"))
		if item in ["rifle", "shotgun"] and s.get("shotgun", {}).get("equipped", false) and str(s.shotgun.get("kind", item)) == item:
			draw_string(font, rect.position + Vector2(5, 14), "%d" % s.shotgun.loaded, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd98a"))
	for entry in [["inventory", "I"], ["health", "H"], ["map", "M"]]:
		var rect: Rect2 = rects[entry[0]]
		_frame(rect, false, hover == entry[0])
		draw_string(font, rect.position + Vector2(rect.size.x * 0.5 - 4, -6), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f0e4c8"))
		if entry[0] == "inventory": _backpack(rect.get_center())
		elif entry[0] == "map": _map_icon(rect.get_center())
		else: _heart(rect.get_center())
	# Clock and time-lapse controls.
	var tick: int = int(s.tick)
	var days: int = tick / 14400 + 1
	var hours: int = (tick / 10) % 1440 / 60
	var clock_right: float = size.x - 24.0
	draw_string(font, Vector2(clock_right - 120, size.y - 86), "%d d." % days, HORIZONTAL_ALIGNMENT_RIGHT, 120, 24, Color("f4ecd6"))
	draw_string(font, Vector2(clock_right - 120, size.y - 60), "%d h." % hours, HORIZONTAL_ALIGNMENT_RIGHT, 120, 24, Color("f4ecd6"))
	# The season and the part of the day (morning, day, evening, night) above the clock.
	var Weather = load("res://sim/world/weather.gd")
	var when: String = "%s · %s" % [String(Weather.SEASON_NAMES[Weather.season(s)]).capitalize(), load("res://sim/world/day_clock.gd").phase_name(s)]
	draw_string(font, Vector2(clock_right - 200, size.y - 112), when, HORIZONTAL_ALIGNMENT_RIGHT, 200, 15, Color("d9ccb0"))
	var paused: bool = clock != null and clock.paused
	var speed: int = clock.speed if clock != null else 1
	for key in ["slower", "speed", "pause", "faster"]:
		var rect: Rect2 = rects[key]
		_frame(rect, key == "pause" and paused, hover == key)
		var c := rect.get_center()
		match key:
			"slower":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-2, -7), c + Vector2(-12, 0), c + Vector2(-2, 7)]), Color("f4ecd6"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(9, -7), c + Vector2(-1, 0), c + Vector2(9, 7)]), Color("f4ecd6"))
			"faster":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -7), c + Vector2(1, 0), c + Vector2(-9, 7)]), Color("f4ecd6"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(2, -7), c + Vector2(12, 0), c + Vector2(2, 7)]), Color("f4ecd6"))
			"pause":
				if paused: draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -7), c + Vector2(6, 0), c + Vector2(-4, 7)]), Color("ffd98a"))
				else:
					draw_rect(Rect2(c + Vector2(-5, -7), Vector2(3.5, 14)), Color("f4ecd6"))
					draw_rect(Rect2(c + Vector2(1.5, -7), Vector2(3.5, 14)), Color("f4ecd6"))
			"speed":
				draw_string(font, rect.position + Vector2(0, 21), "x%.1f" % float(speed), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color("f4ecd6"))

## Small vector pictograms for hotbar items, drawn around `c`.
func _icon(item: String, c: Vector2, alpha: float) -> void:
	ItemIcons.draw(self, item, c, alpha)

func _backpack(c: Vector2) -> void:
	var tone := Color("e1b94c")
	draw_rect(Rect2(c + Vector2(-13, -8), Vector2(26, 21)), tone, false, 3.0)
	draw_arc(c + Vector2(0, -8), 9, PI, TAU, 14, tone, 3.0)
	draw_rect(Rect2(c + Vector2(-7, 2), Vector2(14, 8)), tone, false, 2.5)

func _heart(c: Vector2) -> void:
	var tone := Color("e1b94c")
	draw_arc(c + Vector2(-6, -4), 7, PI * 0.95, TAU * 1.0 + 0.4, 12, tone, 3.0)
	draw_arc(c + Vector2(6, -4), 7, PI - 0.4, TAU + PI * 0.05, 12, tone, 3.0)
	draw_polyline(PackedVector2Array([c + Vector2(-12, -2), c + Vector2(0, 11), c + Vector2(12, -2)]), tone, 3.0, true)
	draw_polyline(PackedVector2Array([c + Vector2(-9, 2), c + Vector2(-4, 2), c + Vector2(-1, -5), c + Vector2(3, 7), c + Vector2(6, 2), c + Vector2(9, 2)]), tone, 2.0, true)

func _map_icon(c: Vector2) -> void:
	var tone := Color("e1b94c")
	# A folded map: three panels with a route and a marker.
	draw_polyline(PackedVector2Array([c + Vector2(-14, -9), c + Vector2(-5, -12), c + Vector2(5, -9), c + Vector2(14, -12), c + Vector2(14, 9), c + Vector2(5, 12), c + Vector2(-5, 9), c + Vector2(-14, 12), c + Vector2(-14, -9)]), tone, 2.5, true)
	draw_line(c + Vector2(-5, -12), c + Vector2(-5, 9), tone, 2.0)
	draw_line(c + Vector2(5, -9), c + Vector2(5, 12), tone, 2.0)
	draw_circle(c + Vector2(9, -1), 2.5, Color("d6573d"))
