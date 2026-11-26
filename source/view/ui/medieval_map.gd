extends Control
## The map screen: a hand-drawn map of the frontier on old parchment. Woods are little inked
## trees, rocks are hills, roads are brown tracks with dashed centre lines, every building is a
## small roofed block, and each town's name is lettered across it. Click a town's name to travel
## there; click anywhere else to set a waypoint.
##
## The picture is painted once each time the map opens (into a SubViewport, UPDATE_ONCE) and then
## only moved and scaled, so the map costs next to nothing per frame and the living world behind
## it is not drawn at all. Only the player's mark, the waypoint and the route are drawn live.
const World = preload("res://sim/world/world_db.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const MapOverlay = preload("res://view/ui/map_overlay.gd")
const CELL := 24.0
const PX := 3.0               # picture pixels per world cell
const MARGIN := 60.0          # picture pixels of parchment and frame around the land
const BOTTOM_MARGIN := 150.0  # keeps the town names clear of the hotbar
# Palette: parchment, inks and washes.
const PARCHMENT := Color("eadbb4")
const PARCHMENT_SHADE := Color("cfb684")
const INK := Color("3a2918")
const INK_FAINT := Color(0.23, 0.16, 0.09, 0.45)
const WOOD := Color("8b9a5c")
const WOOD_SHADE := Color("66743f")
const ROAD := Color("a98152")
const ROOF := Color("a5523a")
const ROOF_HOUSE := Color("b97a49")
const FIELD := Color("d9c27b")
const HILL := Color("a39478")
const MARK := Color("b8322a")

class Painter extends Node2D:
	var map
	func _draw() -> void:
		map._paint(self)

var state: Dictionary = {}
var builds: int = 0               # how many times the picture has been painted (for tests)
var viewport: SubViewport
var picture_size := Vector2.ZERO  # picture pixels
var origin := Vector2.ZERO        # the world cell at the picture's land corner
var view_offset := Vector2.ZERO   # where the picture's corner is on screen
var view_scale: float = 1.0       # screen pixels per picture pixel
var fit_scale: float = 1.0
var town_rects: Array = []        # [{"town", "rect"}] where the names were lettered, for clicks
var waypoint: Vector2 = Vector2.INF   # world pixels
var _live_key: String = ""
var _serif: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Baskerville", "Georgia", "Times New Roman", "serif"])
	serif.font_weight = 600
	_serif = serif

## Paints a fresh picture of the world as it is now and shows it, fitted to the screen.
func open(s: Dictionary) -> void:
	state = s
	var bounds: Array = s.world.get("bounds", [0, 0, World.WIDTH, World.HEIGHT])
	origin = Vector2(bounds[0], bounds[1])
	picture_size = (Vector2(bounds[2] - bounds[0], bounds[3] - bounds[1]) * PX + Vector2.ONE * MARGIN * 2.0).ceil()
	if viewport != null: viewport.queue_free()
	viewport = SubViewport.new()
	viewport.size = Vector2i(picture_size)
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Painter.new()
	painter.map = self
	viewport.add_child(painter)
	add_child(viewport)
	builds += 1
	var screen: Vector2 = get_viewport_rect().size
	fit_scale = minf(screen.x / picture_size.x, (screen.y - 40.0) / picture_size.y)
	view_scale = fit_scale
	view_offset = (screen - picture_size * view_scale) * 0.5
	visible = true
	_live_key = ""
	queue_redraw()

func close() -> void:
	visible = false
	if viewport != null:
		viewport.queue_free()
		viewport = null

# --- moving the map ---------------------------------------------------------------------------

func pan(screen_delta: Vector2) -> void:
	view_offset -= screen_delta
	_clamp_view()
	queue_redraw()

func zoom_at(screen_point: Vector2, factor: float) -> void:
	var wanted: float = clampf(view_scale * factor, fit_scale * 0.85, fit_scale * 4.0)
	view_offset = screen_point - (screen_point - view_offset) * (wanted / view_scale)
	view_scale = wanted
	_clamp_view()
	queue_redraw()

func _clamp_view() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var shown: Vector2 = picture_size * view_scale
	view_offset.x = clampf(view_offset.x, minf(screen.x - shown.x, 0.0) - 120.0, maxf(0.0, screen.x - shown.x) + 120.0)
	view_offset.y = clampf(view_offset.y, minf(screen.y - shown.y, 0.0) - 120.0, maxf(0.0, screen.y - shown.y) + 120.0)

## Picture pixels for a world cell, and the screen point for world pixels (and back).
func _picture(cell: Vector2) -> Vector2:
	return (cell - origin) * PX + Vector2.ONE * MARGIN

func screen_of(world_px: Vector2) -> Vector2:
	return view_offset + _picture(world_px / CELL) * view_scale

func world_of(screen_point: Vector2) -> Vector2:
	return ((screen_point - view_offset) / view_scale - Vector2.ONE * MARGIN) / PX * CELL + origin * CELL

## The town whose name is under this screen point, or 0.
func town_at(screen_point: Vector2) -> int:
	for entry in town_rects:
		if entry.rect.grow(6).has_point(screen_point): return int(entry.town)
	return 0

## Called every frame while open: redraws only when something drawn live has changed.
func refresh_live(s: Dictionary) -> void:
	state = s
	var cell: Array = s.entities[str(s.player)].cell
	var key := "%d,%d:%d:%s" % [cell[0], cell[1], s.get("player_path", []).size(), str(waypoint)]
	if key != _live_key:
		_live_key = key
		queue_redraw()

# --- the live layer ---------------------------------------------------------------------------

func _draw() -> void:
	if state.is_empty() or viewport == null: return
	var screen: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color("2a2118"))
	draw_texture_rect(viewport.get_texture(), Rect2(view_offset, picture_size * view_scale), false)
	# The route being walked, in red ink.
	var path: Array = state.get("player_path", [])
	if path.size() > 1:
		var line := PackedVector2Array()
		for index in range(0, path.size(), 3):
			line.append(screen_of(Vector2(path[index][0], path[index][1]) * CELL))
		line.append(screen_of(Vector2(path[-1][0], path[-1][1]) * CELL))
		for index in range(0, line.size() - 1, 2):
			draw_line(line[index], line[index + 1], MARK, 2.0, true)
	# Town names, lettered large, clear of the bottom of the screen.
	town_rects.clear()
	for town in state.get("settlements", {}).values():
		var store: Array = state.entities[str(town.warehouse)].cell
		var at: Vector2 = screen_of(Vector2(store[0], store[1] - 16) * CELL)
		var text: String = str(town.name)
		# A town off the screen is named small at the edge, with an arrow pointing the way.
		var away: bool = not Rect2(Vector2.ZERO, screen - Vector2(0, BOTTOM_MARGIN)).grow(-10).has_point(at)
		var size: int = 17 if away else clampi(roundi(26.0 * sqrt(view_scale / fit_scale)), 22, 40)
		var extent: Vector2 = _serif.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var rect := Rect2(Vector2(clampf(at.x - extent.x * 0.5, 30.0, screen.x - extent.x - 30.0), clampf(at.y - extent.y * 0.5, 50.0, screen.y - BOTTOM_MARGIN - extent.y)), extent)
		if away:
			var toward: Vector2 = (at - rect.get_center()).normalized()
			var tip: Vector2 = rect.get_center() + toward * (extent.length() * 0.5 + 14.0)
			var side := Vector2(-toward.y, toward.x) * 6.0
			draw_colored_polygon(PackedVector2Array([tip, tip - toward * 11.0 + side, tip - toward * 11.0 - side]), INK)
		var baseline: Vector2 = rect.position + Vector2(0, extent.y * 0.78)
		draw_string_outline(_serif, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(PARCHMENT, 0.85))
		draw_string(_serif, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)
		draw_line(rect.position + Vector2(0, extent.y + 2), rect.position + Vector2(extent.x, extent.y + 2), INK_FAINT, 1.0)
		if not away:
			# How the town sees you, in small italic-ish lettering under its name (reputation.gd).
			var Reputation = load("res://sim/factions/reputation.gd")
			var standing: String = "You are %s here" % Reputation.label(Reputation.value(state, int(town.id)))
			var note_size: int = maxi(12, size / 2)
			var note_extent: Vector2 = _serif.get_string_size(standing, HORIZONTAL_ALIGNMENT_LEFT, -1, note_size)
			var note_at: Vector2 = Vector2(rect.get_center().x - note_extent.x * 0.5, rect.end.y + note_extent.y + 2)
			draw_string_outline(_serif, note_at, standing, HORIZONTAL_ALIGNMENT_LEFT, -1, note_size, 4, Color(PARCHMENT, 0.85))
			draw_string(_serif, note_at, standing, HORIZONTAL_ALIGNMENT_LEFT, -1, note_size, INK_FAINT.darkened(0.3))
		town_rects.append({"town": int(town.id), "rect": rect})
	# The bandit camp, once someone has told you where it is (conversation.gd).
	if bool(state.get("player_status", {}).get("known_places", {}).get("bandit_camp", false)) and state.has("bandits"):
		var camp: Vector2 = screen_of(Vector2(state.bandits.cell[0], state.bandits.cell[1]) * CELL)
		var cleared: bool = bool(state.bandits.get("cleared", false))
		draw_line(camp + Vector2(-7, -7), camp + Vector2(7, 7), MARK, 3.0)
		draw_line(camp + Vector2(-7, 7), camp + Vector2(7, -7), MARK, 3.0)
		var label: String = "Bandit camp (cleared)" if cleared else "Bandit camp"
		draw_string_outline(_serif, camp + Vector2(11, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(PARCHMENT, 0.85))
		draw_string(_serif, camp + Vector2(11, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
	# The waypoint pin and the player's mark.
	if waypoint != Vector2.INF:
		var pin: Vector2 = screen_of(waypoint)
		draw_line(pin, pin + Vector2(0, -22), INK, 2.0)
		draw_circle(pin + Vector2(0, -24), 6.0, INK)
		draw_circle(pin + Vector2(0, -24), 4.4, MARK)
	var player_cell: Array = state.entities[str(state.player)].cell
	var me: Vector2 = screen_of(Vector2(player_cell[0], player_cell[1]) * CELL)
	draw_circle(me, 8.0, INK)
	draw_circle(me, 6.2, Color("f2e6c6"))
	draw_circle(me, 3.4, MARK)
	draw_string_outline(_serif, me + Vector2(11, 5), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(PARCHMENT, 0.85))
	draw_string(_serif, me + Vector2(11, 5), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
	_compass(Vector2(screen.x - 70, screen.y - BOTTOM_MARGIN - 50))
	var hint := "Click a town's name to travel there  ·  click elsewhere for a waypoint  ·  WASD and wheel to look around  ·  Esc or M to close"
	var hint_size: Vector2 = _serif.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var pill := Rect2(Vector2((screen.x - hint_size.x) * 0.5 - 14.0, 8.0), hint_size + Vector2(28, 12))
	draw_rect(pill, Color(PARCHMENT, 0.94))
	draw_rect(pill, INK, false, 1.2)
	draw_string(_serif, pill.position + Vector2(14, hint_size.y + 2), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)

func _compass(c: Vector2) -> void:
	draw_circle(c, 34.0, Color(PARCHMENT, 0.9))
	draw_arc(c, 34.0, 0, TAU, 40, INK, 1.4, true)
	draw_arc(c, 29.0, 0, TAU, 40, INK_FAINT, 1.0, true)
	for index in range(8):
		var angle: float = -PI / 2.0 + index * PI / 4.0
		var long: bool = index % 2 == 0
		var tip: Vector2 = c + Vector2.from_angle(angle) * (30.0 if long else 18.0)
		var side: Vector2 = Vector2.from_angle(angle + PI / 2.0) * (5.0 if long else 3.5)
		draw_colored_polygon(PackedVector2Array([c + side, tip, c - side]), MARK if index == 0 else (INK if long else INK_FAINT))
	draw_string(_serif, c + Vector2(-6, -38), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)

# --- the picture (painted once per opening) -----------------------------------------------------

func _paint(c: Node2D) -> void:
	var s: Dictionary = state
	var full := Rect2(Vector2.ZERO, picture_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.get("seed", 1)) * 7919 + 17
	c.draw_rect(full, PARCHMENT)
	# Age: soft stains, then a darker rim towards the edges.
	for index in range(70):
		var at := Vector2(rng.randf() * picture_size.x, rng.randf() * picture_size.y)
		c.draw_circle(at, rng.randf_range(30.0, 150.0), Color(PARCHMENT_SHADE, rng.randf_range(0.04, 0.1)))
	for index in range(500):
		var at := Vector2(rng.randf() * picture_size.x, rng.randf() * picture_size.y)
		c.draw_line(at, at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 14.0), Color(PARCHMENT_SHADE, 0.35), 0.8)
	for band in range(14):
		var inset: float = band * 5.0
		c.draw_rect(full.grow(-inset), Color(0.45, 0.32, 0.17, 0.05 - band * 0.003), false, 10.0)
	# Fields, then the town grounds, roads, woods and hills, buildings, and the frame.
	for plot in s.get("crops", {}).values():
		var r := Rect2(_picture(Vector2(plot.rect[0], plot.rect[1])), Vector2(plot.rect[2], plot.rect[3]) * PX)
		c.draw_rect(r, Color(FIELD, 0.85))
		var y: float = r.position.y + 1.5
		while y < r.end.y:
			c.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(INK, 0.25), 0.6)
			y += 2.5
		c.draw_rect(r, INK_FAINT, false, 0.8)
	for town in s.get("settlements", {}).values():
		var store: Array = s.entities[str(town.warehouse)].cell
		c.draw_circle(_picture(Vector2(store[0], store[1] + 10)), 46.0 * PX, Color(ROOF, 0.06))
	_paint_roads(c, s)
	_paint_hills(c, s)
	_paint_woods(c, s, rng)
	_paint_buildings(c, s)
	for post in World.of_kind(s, "signpost"):
		var p := _picture(Vector2(post.cell[0], post.cell[1]))
		c.draw_line(p, p + Vector2(0, -9), INK, 1.4)
		c.draw_line(p + Vector2(-5, -7), p + Vector2(5, -7), INK, 1.4)
		c.draw_line(p + Vector2(-4, -4), p + Vector2(4, -4), INK, 1.2)
	_paint_badges(c, s)
	_paint_frame(c)

## A small inked seal on each building that matters (sheriff, lodge, storehouse...), and a key.
func _paint_badges(c: Node2D, s: Dictionary) -> void:
	var list: Array = MapOverlay.markers(s)
	for marker in list:
		var data: Dictionary = MapOverlay.KINDS[marker.kind]
		var p: Vector2 = _picture(Vector2(marker.world[0], marker.world[1]))
		c.draw_circle(p, 7.5, INK)
		c.draw_circle(p, 6.2, Color(data.color).lerp(PARCHMENT, 0.25))
		c.draw_string(_serif, p + Vector2(-4.2, 4.6), data.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	var kinds: Array = MapOverlay.legend_kinds(list)
	var box := Rect2(Vector2(46, picture_size.y - 64 - kinds.size() * 20), Vector2(170, 34 + kinds.size() * 20))
	c.draw_rect(box, Color(PARCHMENT, 0.96))
	c.draw_rect(box, INK, false, 1.4)
	c.draw_string(_serif, box.position + Vector2(14, 22), "Key", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	for index in range(kinds.size()):
		var data: Dictionary = MapOverlay.KINDS[kinds[index]]
		var y: float = box.position.y + 42.0 + index * 20.0
		c.draw_circle(Vector2(box.position.x + 22, y - 4), 7.0, INK)
		c.draw_circle(Vector2(box.position.x + 22, y - 4), 5.8, Color(data.color).lerp(PARCHMENT, 0.25))
		c.draw_string(_serif, Vector2(box.position.x + 18, y + 0.5), data.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
		c.draw_string(_serif, Vector2(box.position.x + 38, y), data.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)

func _paint_roads(c: Node2D, s: Dictionary) -> void:
	for pass_index in range(2):
		for segment in TownLayout.segments(s):
			var link: bool = segment.kind == "link"
			var line := PackedVector2Array()
			for p in segment.points: line.append(_picture(Vector2(float(p[0]), float(p[1]))))
			if line.size() < 2: continue
			if pass_index == 0:
				c.draw_polyline(line, Color(INK, 0.5), (5.2 if link else 3.6), true)
				c.draw_polyline(line, ROAD, (3.8 if link else 2.4), true)
			elif link:
				_dashed(c, line, Color(INK, 0.7), 1.0, 6.0, 5.0)

## A dashed ink line along a polyline, the dashes running on across its corners.
func _dashed(c: Node2D, line: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var carried: float = 0.0
	var drawing: bool = true
	for index in range(line.size() - 1):
		var a: Vector2 = line[index]
		var b: Vector2 = line[index + 1]
		var length: float = a.distance_to(b)
		var along: float = 0.0
		while along < length:
			var left: float = (dash if drawing else gap) - carried
			var take: float = minf(left, length - along)
			if drawing: c.draw_line(a.lerp(b, along / length), a.lerp(b, (along + take) / length), color, width)
			along += take
			carried += take
			if carried >= (dash if drawing else gap) - 0.001:
				carried = 0.0
				drawing = not drawing

func _paint_hills(c: Node2D, s: Dictionary) -> void:
	var buckets: Dictionary = {}
	for key in s.world.blocked:
		var comma: int = String(key).find(",")
		var cell := Vector2i(int(String(key).substr(0, comma)), int(String(key).substr(comma + 1)))
		buckets[Vector2i(floori(cell.x / 4.0), floori(cell.y / 4.0))] = true
	var keys: Array = buckets.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for bucket in keys:
		var base: Vector2 = _picture(Vector2(bucket) * 4.0 + Vector2(2, 3))
		var peak: Vector2 = base + Vector2(0, -9)
		var hill := PackedVector2Array([base + Vector2(-7, 0), peak, base + Vector2(7, 0)])
		c.draw_colored_polygon(hill, HILL)
		c.draw_polyline(hill, INK, 1.1, true)
		c.draw_line(peak + Vector2(1, 2), base + Vector2(4, -1), Color(INK, 0.45), 0.8)

func _paint_woods(c: Node2D, s: Dictionary, rng: RandomNumberGenerator) -> void:
	var counts: Dictionary = {}
	for tree in World.of_kind(s, "tree"):
		if int(s.inventories.get(str(tree.id), {}).get("items", {}).get("log", 1)) == 0: continue   # stumps
		var bucket := Vector2i(floori(tree.cell[0] / 3.0), floori(tree.cell[1] / 3.0))
		counts[bucket] = int(counts.get(bucket, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for bucket in keys:
		var jitter := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var foot: Vector2 = _picture(Vector2(bucket) * 3.0 + Vector2(1.5, 2.5)) + jitter
		var radius: float = minf(3.4 + float(counts[bucket]) * 0.5, 5.4)
		var crown: Vector2 = foot + Vector2(0, -radius - 2.0)
		c.draw_line(foot, crown, INK, 1.0)
		c.draw_circle(crown, radius, WOOD if (bucket.x + bucket.y) % 3 != 0 else WOOD_SHADE)
		c.draw_arc(crown, radius, 0, TAU, 12, INK, 0.9, true)
		c.draw_arc(crown + Vector2(-radius * 0.25, radius * 0.2), radius * 0.55, PI * 0.2, PI * 0.9, 5, Color(INK, 0.35), 0.7)

func _paint_buildings(c: Node2D, s: Dictionary) -> void:
	for building in World.buildings(s):
		var r: Rect2i = World.building_rect(building)
		var rect := Rect2(_picture(Vector2(r.position)), Vector2(r.size) * PX)
		var civic: bool = not building.has("house_type")
		c.draw_rect(rect, ROOF if civic else ROOF_HOUSE)
		c.draw_rect(rect, INK, false, 1.2)
		var mid: float = rect.position.y + rect.size.y * 0.5
		c.draw_line(Vector2(rect.position.x + 1, mid), Vector2(rect.end.x - 1, mid), Color(INK, 0.55), 0.9)

func _paint_frame(c: Node2D) -> void:
	var full := Rect2(Vector2.ZERO, picture_size)
	c.draw_rect(full.grow(-14), INK, false, 2.4)
	c.draw_rect(full.grow(-22), INK, false, 0.9)
	for corner in [Vector2(18, 18), Vector2(picture_size.x - 18, 18), Vector2(18, picture_size.y - 18), picture_size - Vector2(18, 18)]:
		c.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -9), corner + Vector2(9, 0), corner + Vector2(0, 9), corner + Vector2(-9, 0)]), MARK)
		c.draw_polyline(PackedVector2Array([corner + Vector2(0, -9), corner + Vector2(9, 0), corner + Vector2(0, 9), corner + Vector2(-9, 0), corner + Vector2(0, -9)]), INK, 1.0)
	# A cartouche with the title.
	var box := Rect2(Vector2(46, 40), Vector2(330, 70))
	c.draw_rect(box, Color(PARCHMENT, 0.96))
	c.draw_rect(box, INK, false, 1.6)
	c.draw_rect(box.grow(-5), INK_FAINT, false, 0.8)
	c.draw_string(_serif, box.position + Vector2(22, 46), "The Frontier", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, INK)
	c.draw_string(_serif, box.position + Vector2(24, 63), "Alder Hollow, Reedbank and Dustvale", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.75))
