extends Control
## The map screen's markings, drawn over the zoomed-out world: a badge for every building that
## matters (sheriff, lodge, storehouse, sawmill, bakery, forge, market, farm, ore, well), a name
## pill for each town kept clear of the bottom bar, a legend, a compass, and a waypoint you set by
## clicking. The waypoint also shows in normal play, as a distance and bearing readout and an arrow
## at the edge of the screen. Everything is read from the simulation; nothing here changes it.
const CELL := 24.0
const BOTTOM_MARGIN := 150.0          # keeps labels clear of the hotbar and buttons
const KINDS := {
	"office": {"label": "Sheriff", "color": Color("d9b44a"), "glyph": "S"},
	"saloon": {"label": "Saloon", "color": Color("c46a4a"), "glyph": "B"},
	"town_hall": {"label": "Town house", "color": Color("d8c27a"), "glyph": "T"},
	"home_lodge": {"label": "Lodge", "color": Color("9cc4d9"), "glyph": "L"},
	"warehouse": {"label": "Storehouse", "color": Color("c98b4a"), "glyph": "G"},
	"sawmill": {"label": "Sawmill", "color": Color("b6845a"), "glyph": "W"},
	"bakery": {"label": "Bakery", "color": Color("e3c08a"), "glyph": "B"},
	"forge": {"label": "Forge", "color": Color("c8604a"), "glyph": "F"},
	"market": {"label": "Market", "color": Color("8fc38a"), "glyph": "M"},
	"farm": {"label": "Farm", "color": Color("b7d65f"), "glyph": "R"},
	"ore": {"label": "Ore", "color": Color("9aa0a8"), "glyph": "O"},
	"well": {"label": "Well", "color": Color("6fa6d8"), "glyph": "~"}}
var active: bool = false
var state: Dictionary = {}
var waypoint: Vector2 = Vector2.INF     # world pixels; INF when none
var player_world: Vector2 = Vector2.ZERO
var zoom: float = 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## What is on the map, as {"kind", "world" (cell), "label", "town"}: every building of interest and each town's well.
static func markers(s: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = s.entities.keys()
	ids.sort()
	for key in ids:
		var entity: Dictionary = s.entities[key]
		var kind: String = str(entity.get("kind", ""))
		var town: int = int(entity.get("settlement", 0))
		if kind == "home":
			if "lodge" in str(entity.name).to_lower(): kind = "home_lodge"
			else: continue
		if not KINDS.has(kind) or kind == "well" or not entity.has("cell"): continue
		result.append({"kind": kind, "world": entity.cell.duplicate(), "label": str(entity.name), "town": town})
	for town in s.get("settlements", {}).values():
		var store: Array = s.entities[str(town.warehouse)].cell
		result.append({"kind": "well", "world": [store[0], store[1] + 9], "label": "%s well" % town.name, "town": int(town.id)})
	return result

## The kinds actually present, for the legend.
static func legend_kinds(list: Array) -> Array:
	var seen: Dictionary = {}
	for marker in list: seen[marker.kind] = true
	var order: Array = KINDS.keys().filter(func(k: String) -> bool: return seen.has(k))
	return order

## A label rectangle of `size` wanted at `at` (screen), kept inside the screen and above the hotbar.
static func clamp_label(at: Vector2, size: Vector2, screen: Vector2) -> Rect2:
	var position := Vector2(clampf(at.x - size.x * 0.5, 8.0, screen.x - size.x - 8.0), clampf(at.y - size.y * 0.5, 8.0, screen.y - BOTTOM_MARGIN - size.y))
	return Rect2(position, size)

func set_waypoint(world: Vector2) -> void:
	waypoint = world
	queue_redraw()

func clear_waypoint() -> void:
	waypoint = Vector2.INF
	queue_redraw()

## "230 m NE": cells are metres.
static func bearing_text(from_world: Vector2, to_world: Vector2) -> String:
	var delta := (to_world - from_world) / CELL
	var names := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var index: int = posmod(roundi(delta.angle() / (PI / 4.0)), 8)
	return "%d m %s" % [roundi(delta.length()), names[index]]

func _draw() -> void:
	if state.is_empty(): return
	var transform: Transform2D = get_viewport().get_canvas_transform()
	var screen: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	if active:
		var list: Array = markers(state)
		# Badges for buildings once there is room for them; always the town names.
		var show_icons: bool = zoom >= 0.1
		for marker in list:
			if not show_icons and marker.kind != "warehouse": continue
			var p: Vector2 = transform * (Vector2(marker.world[0], marker.world[1]) * CELL)
			if p.x < -20 or p.y < -20 or p.x > screen.x + 20 or p.y > screen.y + 20: continue
			var data: Dictionary = KINDS[marker.kind]
			var radius: float = 9.0
			draw_circle(p, radius + 1.5, Color("25291f"))
			draw_circle(p, radius, data.color)
			draw_string(font, p + Vector2(-4.5, 5.0), data.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("25291f"))
		for town in state.get("settlements", {}).values():
			var store: Array = state.entities[str(town.warehouse)].cell
			var p: Vector2 = transform * (Vector2(store[0], store[1] - 12) * CELL)
			var text: String = str(town.name)
			var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18) + Vector2(22, 12)
			var rect := clamp_label(p, size, screen)
			draw_rect(rect, Color(0.08, 0.07, 0.05, 0.88))
			draw_rect(rect, Color("e2b55a"), false, 1.5)
			draw_string(font, rect.position + Vector2(11, size.y - 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f3e7cc"))
		_draw_legend(font, list)
		_draw_compass(font, screen)
	# The waypoint: a pin on the map, an arrow and a readout in play.
	if waypoint != Vector2.INF:
		var pin: Vector2 = transform * waypoint
		var on_screen: bool = Rect2(Vector2.ZERO, screen).grow(-6).has_point(pin)
		var info: String = bearing_text(player_world, waypoint)
		if on_screen:
			draw_line(pin, pin + Vector2(0, -26), Color("25291f"), 4.0)
			draw_line(pin, pin + Vector2(0, -26), Color("e8573f"), 2.0)
			draw_circle(pin + Vector2(0, -28), 7.0, Color("25291f"))
			draw_circle(pin + Vector2(0, -28), 5.4, Color("e8573f"))
			if active: draw_string(font, pin + Vector2(12, -26), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f3e7cc"))
		else:
			# An arrow on the screen edge pointing the way.
			var centre: Vector2 = screen * 0.5
			var toward: Vector2 = (pin - centre).normalized()
			var edge: Vector2 = centre + toward * minf((screen.x * 0.5 - 40.0) / maxf(absf(toward.x), 0.001), (screen.y * 0.5 - BOTTOM_MARGIN * 0.5) / maxf(absf(toward.y), 0.001))
			var side := Vector2(-toward.y, toward.x)
			draw_colored_polygon(PackedVector2Array([edge + toward * 14.0, edge - toward * 8.0 + side * 9.0, edge - toward * 8.0 - side * 9.0]), Color("e8573f"))
		if not active:
			var text: String = "Waypoint · " + info
			var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(20, 8)
			var rect := Rect2(Vector2((screen.x - size.x) * 0.5, screen.y - 178.0), size)
			draw_rect(rect, Color(0.08, 0.07, 0.05, 0.8))
			draw_string(font, rect.position + Vector2(10, size.y - 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f3e7cc"))

	# Travelling to a town by yourself: say where, and how to take over.
	var travelling: int = int(state.get("player_control", {}).get("travelling", 0))
	if travelling != 0 and not active:
		var name: String = str(state.get("settlements", {}).get(str(travelling), {}).get("name", "town"))
		var text: String = "Travelling to %s  ·  move or press Esc to stop" % name
		var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15) + Vector2(24, 10)
		var rect := Rect2(Vector2((screen.x - size.x) * 0.5, 18.0), size)
		draw_rect(rect, Color(0.08, 0.07, 0.05, 0.82))
		draw_rect(rect, Color("e2b55a", 0.7), false, 1.2)
		draw_string(font, rect.position + Vector2(12, size.y - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f3e7cc"))

func _draw_legend(font: Font, list: Array) -> void:
	var kinds: Array = legend_kinds(list)
	var rows: int = kinds.size()
	var panel := Rect2(Vector2(14, 14), Vector2(214, 30 + rows * 22 + 24))
	draw_rect(panel, Color(0.08, 0.07, 0.05, 0.86))
	draw_rect(panel, Color("e2b55a", 0.6), false, 1.0)
	draw_string(font, panel.position + Vector2(12, 21), "Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f3e7cc"))
	for index in range(rows):
		var data: Dictionary = KINDS[kinds[index]]
		var y: float = panel.position.y + 42.0 + index * 22.0
		draw_circle(Vector2(panel.position.x + 20, y - 4), 8.0, data.color)
		draw_string(font, Vector2(panel.position.x + 16, y), data.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("25291f"))
		draw_string(font, Vector2(panel.position.x + 36, y), data.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e6dcc0"))
	draw_string(font, panel.position + Vector2(12, panel.size.y - 8), "Click: set waypoint · Esc/M: back", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a99c7e"))

func _draw_compass(font: Font, screen: Vector2) -> void:
	var c := Vector2(screen.x - 54, 190)
	draw_circle(c, 26.0, Color(0.08, 0.07, 0.05, 0.8))
	draw_arc(c, 26.0, 0, TAU, 32, Color("e2b55a", 0.7), 1.2)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -20), c + Vector2(6, 4), c + Vector2(-6, 4)]), Color("e8573f"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 20), c + Vector2(6, -4), c + Vector2(-6, -4)]), Color("a99c7e"))
	draw_string(font, c + Vector2(-5, -29), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f3e7cc"))
