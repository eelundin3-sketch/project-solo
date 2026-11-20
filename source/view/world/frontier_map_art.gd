extends RefCounted
## Original, deterministic presentation shapes; no gameplay state is stored here.
const TREES = [preload("res://content/art/tree_0.svg"), preload("res://content/art/tree_1.svg"), preload("res://content/art/tree_2.svg"), preload("res://content/art/tree_3.svg")]
const DEAD_TREES = [preload("res://content/art/tree_dead_0.svg"), preload("res://content/art/tree_dead_1.svg")]
const World = preload("res://sim/world/world_db.gd")
const Props = preload("res://view/world/prop_art.gd")
const Furniture = preload("res://view/world/interior_art.gd")
const FLOOR = preload("res://content/art/floor.svg")
const INK := Color("30291e")
const Character = preload("res://view/actors/frontier_character.gd")
## The season shown (0 spring .. 3 winter) and how far into it (0..1 over its first day), set by
## the world view each frame from the clock. Trees and grass tufts take their colours from it.
static var season: int = 1
static var previous_season: int = 0
static var season_blend: float = 1.0
const SEASON_LEAVES := [Color(1.05, 1.12, 0.78), Color.WHITE, Color(1.0, 0.84, 0.40), Color(0.80, 0.86, 0.82)]

## The leaf colour for this moment of the year, blended over the first day of a season.
static func season_leaves() -> Color:
	return SEASON_LEAVES[previous_season].lerp(SEASON_LEAVES[season], season_blend)

## Most trees drop their leaves in winter; one in three is evergreen.
static func bare_in_winter(id: int) -> bool:
	return season == 3 and season_blend >= 0.5 and posmod(id, 3) != 0

## Grass tufts follow the season: fresh in spring, gold-brown in autumn, dull in winter.
static func season_grass(color: Color) -> Color:
	var tints := [Color(0.92, 1.06, 0.82), Color.WHITE, Color(1.25, 0.95, 0.55), Color(0.85, 0.82, 0.78)]
	return color * Color(tints[previous_season]).lerp(tints[season], season_blend)

static func box(c: Node2D, r: Rect2, color: Color, border: float = 2.0) -> void:
	c.draw_rect(r, color)
	c.draw_rect(r, INK, false, border)

## A convex 3- or 4-cornered fill drawn as a primitive, which the renderer batches with its
## neighbours (a polygon is a draw call of its own). The pixels are the same.
static func _fill(c: Node2D, points: PackedVector2Array, color: Color) -> void:
	if points.size() <= 4 and _convex(points):
		c.draw_primitive(points, PackedColorArray([color]), PackedVector2Array())
	else:
		c.draw_colored_polygon(points, color)

static func _convex(points: PackedVector2Array) -> bool:
	var sign := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var d := points[(i + 2) % points.size()]
		var cross := (b - a).cross(d - b)
		if is_zero_approx(cross): return false
		if sign == 0.0: sign = signf(cross)
		elif signf(cross) != sign: return false
	return true

static func poly(c: Node2D, points: PackedVector2Array, color: Color) -> void:
	c.draw_colored_polygon(points, color)
	var edge := points.duplicate()
	edge.append(edge[0])
	c.draw_polyline(edge, INK, 2, true)

static func floor_tile(c: Node2D, rect: Rect2, x: int, y: int) -> void:
	var sample := Rect2(Vector2(posmod(x, 4), posmod(y, 4)) * 48, Vector2(48, 48))
	c.draw_texture_rect_region(FLOOR, rect, sample)
	# The timber grain spans neighbouring cells; avoid drawing a second grid on top.
	c.draw_rect(rect, Color(0.26, 0.12, 0.03, 0.04))

static func tree(c: Node2D, p: Vector2, logs: int, id: int, pose: Dictionary = {}) -> void:
	var fall: float = float(pose.get("fall", -1.0))
	if logs == 0:
		_stump(c, p)
		return
	if fall >= 0.0:
		# Felled: the tree topples from its stump (slowly at first, then faster) and stays lying
		# there, leaning the way its id decides, until its wood has been gathered.
		_stump(c, p)
		var direction: float = 1.0 if id % 2 == 0 else -1.0
		# A felled tree creaks over slowly, gathers speed like anything falling, and keeps
		# accelerating until it hits the ground, where it bounces once and settles.
		var lie := 1.42
		var angle: float
		if fall < 0.8:
			var u := fall / 0.8
			angle = lie * (0.06 * u + 0.94 * u * u * u)
		else:
			var v := (fall - 0.8) / 0.2
			angle = lie - 0.09 * sin(v * PI) * (1.0 - 0.4 * v)
		angle *= direction
		c.draw_set_transform(p + Vector2(0, -6), angle)
		c.draw_texture_rect(_tree_texture(id, pose), Rect2(Vector2(-40, -88), Vector2(80, 100)), false, _tree_tint(id, pose))
		c.draw_set_transform(Vector2.ZERO)
		return
	var sway: float = float(pose.get("sway", 0))
	c.draw_texture_rect(_tree_texture(id, pose), Rect2(p + Vector2(-40 + sway, -94), Vector2(80, 100)), false, _tree_tint(id, pose))

## Dry-country trees: bare dead trunks, and a few trees still holding autumn-coloured leaves.
static func _tree_texture(id: int, pose: Dictionary) -> Texture2D:
	return DEAD_TREES[posmod(id, 2)] if pose.get("dead", false) or bare_in_winter(id) else TREES[posmod(id, 4)]

static func _tree_tint(id: int, pose: Dictionary) -> Color:
	if pose.get("dead", false) or bare_in_winter(id): return Color.WHITE
	if pose.get("autumn", false): return Color(1.0, 0.82, 0.36).lerp(Color(1.0, 0.7, 0.3), float(posmod(id * 7, 5)) / 8.0)
	var leaves: Color = season_leaves()
	if season == 2: leaves = leaves.lerp(Color(1.0, 0.70, 0.30), float(posmod(id * 7, 5)) / 6.0)   # autumn: each tree its own shade
	return Color("d7e5c9").lerp(Color.WHITE, float(posmod(id * 13, 17)) / 24.0) * leaves

static func _stump(c: Node2D, p: Vector2) -> void:
	box(c, Rect2(p - Vector2(7, 10), Vector2(14, 12)), Color("83623c"))
	Character.oval(c, p + Vector2(0, -10), Vector2(8, 4), Color("bd9860"))
	for ring in [Vector2(5.2, 2.4), Vector2(2.6, 1.2)]:
		Character.oval(c, p + Vector2(0, -10), ring, Color("a98048"))

static func rock(c: Node2D, p: Vector2) -> void:
	poly(c, PackedVector2Array([p + Vector2(-11, 5), p + Vector2(-12, -4), p + Vector2(-5, -12), p + Vector2(7, -9), p + Vector2(12, 1), p + Vector2(7, 7)]), Color("8c896f"))
	poly(c, PackedVector2Array([p+Vector2(-5,-10),p+Vector2(0,-2),p+Vector2(9,-7)]), Color("b3ae96"))
	c.draw_polyline(PackedVector2Array([p + Vector2(-5, -10), p + Vector2(0, -1), p + Vector2(10, 1)]), Color("b4ad8b"), 1.4, true)
	c.draw_polyline(PackedVector2Array([p + Vector2(-8, -4), p + Vector2(-6, 0), p + Vector2(-8, 4)]), Color("6d6b55"), 0.65, true)
	c.draw_line(p + Vector2(2, 2), p + Vector2(6, 4), Color("6a6955"), 0.65, true)

## The large iron-bearing boulder: a faceted grey-brown mass streaked with rust and glints of ore,
## with fewer veins showing as it is mined out. `area` is its blocked footprint in pixels.
static func big_rock(c: Node2D, area: Rect2, ore_left: int, id: int) -> void:
	var centre := area.get_center() + Vector2(0, 4)
	var rx := area.size.x * 0.5 + 6.0
	var ry := area.size.y * 0.5 + 2.0
	Props.ellipse(c, centre + Vector2(6, 12), Vector2(rx + 6, ry * 0.55), Color(0, 0, 0, 0.26), 0.0, INK, 0.0)
	var outline := PackedVector2Array()
	for step in range(18):
		var angle := TAU * float(step) / 18.0
		var wobble := 0.86 + 0.24 * fposmod(sin(float(step) * 12.9898 + float(id)) * 43758.5453, 1.0)
		outline.append(centre + Vector2(cos(angle) * rx * wobble, sin(angle) * ry * wobble * 0.86 - 6.0))
	poly(c, outline, Color("6e655c"))
	var lit := PackedVector2Array()
	for point in outline:
		lit.append(centre + (point - centre) * 0.78 + Vector2(-5, -9))
	c.draw_colored_polygon(lit, Color("8c8174"))
	var crown := PackedVector2Array()
	for point in outline:
		crown.append(centre + (point - centre) * 0.5 + Vector2(-8, -16))
	c.draw_colored_polygon(crown, Color("a39787"))
	# Facet lines and rust-coloured iron veins running across the stone.
	for index in range(7):
		var start: Vector2 = outline[(index * 3) % outline.size()]
		var finish: Vector2 = centre + (start - centre) * 0.3 + Vector2(-4, -12)
		c.draw_line(start.lerp(finish, 0.12), start.lerp(finish, 0.72), Color("4e463e"), 1.4, true)
	var veins: int = clampi(ore_left / 60, 1, 10)
	for vein in range(veins):
		var a: Vector2 = outline[(vein * 5 + 2) % outline.size()].lerp(centre, 0.2 + 0.1 * float(vein % 3))
		var b: Vector2 = a.lerp(centre + Vector2(-6, -12), 0.55)
		c.draw_line(a, b, Color("a8512f"), 3.0, true)
		c.draw_line(a, b, Color("d27a45"), 1.3, true)
		c.draw_circle(a.lerp(b, 0.5), 1.8, Color("f2d29a"))
	for chip in range(5):
		var base := centre + Vector2((float(chip) - 2.0) * 26.0 + 4.0, ry * 0.62)
		poly(c, PackedVector2Array([base + Vector2(-5, 2), base + Vector2(-2, -4), base + Vector2(4, -3), base + Vector2(6, 2)]), Color("7b6e62"))

static func crate(c: Node2D, p: Vector2) -> void:
	c.draw_rect(Rect2(p - Vector2(10, 14), Vector2(20, 17)), Color(0, 0, 0, 0.16))   # contact only
	Furniture.timber(c, Rect2(p - Vector2(10, 16), Vector2(20, 18)), Color("a67a4b"), 2.0)
	Props.polygon(c, PackedVector2Array([p + Vector2(-10, -16), p + Vector2(-6, -22),
		p + Vector2(14, -22), p + Vector2(10, -16)]), Color("c6a16f"))
	Props.polygon(c, PackedVector2Array([p + Vector2(10, -16), p + Vector2(14, -22),
		p + Vector2(14, -4), p + Vector2(10, 2)]), Color("735237"))
	for y in [-11, -5]:
		c.draw_line(p + Vector2(-10, y), p + Vector2(10, y), Color("745334"), 0.7, true)
	c.draw_line(p + Vector2(-8, 0), p + Vector2(8, -14), Color("d2a572"), 2.4, true)
	for x in [-8, 8]:
		for y in [-13, 0]: Props.nail(c, p + Vector2(x, y), 0.65)

static func barrel(c: Node2D, p: Vector2) -> void:
	Character.oval(c, p - Vector2(0, 9), Vector2(10, 14), Color("956b3d"))
	for dx in [-5,0,5]:
		c.draw_line(p+Vector2(dx,-18),p+Vector2(dx,-1),Color("64462c"),1)
	for y in [-15, -3]:
		c.draw_line(p + Vector2(-9, y), p + Vector2(9, y), Color("514b3b"), 3)
	Character.oval(c, p - Vector2(0, 21), Vector2(9, 4), Color("ba945b"))

static func farm(c: Node2D, p: Vector2, food: int) -> void:
	box(c, Rect2(p - Vector2(58, 36), Vector2(116, 72)), Color("705236"))
	for row in range(4):
		c.draw_line(p + Vector2(-53, row * 17 - 29), p + Vector2(53, row * 17 - 29), Color("3d3021"), 3)
		for column in range(7):
			var q := p + Vector2(column * 15 - 46, row * 17 - 30)
			if food > 0:
				Character.oval(c, q, Vector2(5, 3), Color("9b9a51"))
				c.draw_line(q, q + Vector2(-4, -8), Color("b7b66d"), 2)
				c.draw_line(q, q + Vector2(5, -6), Color("525c32"), 2)
	for dx in [-62, 62]:
		box(c, Rect2(p + Vector2(dx, -38), Vector2(4, 78)), Color("a7844d"), 1)

static func building(c: Node2D, entity: Dictionary) -> void:
	for y in range(entity.footprint[1] + 1, entity.footprint[1] + entity.footprint[3] - 1):
		for x in range(entity.footprint[0] + 1, entity.footprint[0] + entity.footprint[2] - 1):
			if World.building_contains(entity, [x, y]):
				floor_tile(c, Rect2(Vector2(x, y) * 24 - Vector2(12, 12), Vector2(24, 24)), x, y)
	var threshold := Rect2(Vector2(entity.cell[0], entity.cell[1]) * 24 - Vector2(12, 12), Vector2(24, 24))
	floor_tile(c, threshold, entity.cell[0], entity.cell[1])
	if entity.kind == "office":
		# The jail cell's iron bars across the gap in the partition; the door swings open for escorts and release.
		var bar_x: float = (float(entity.footprint[0]) + 5.0) * 24.0
		var top: float = (float(entity.footprint[1]) + 7.0) * 24.0 - 12.0
		if bool(entity.get("cell_open", false)):
			c.draw_rect(Rect2(Vector2(bar_x - 12, top), Vector2(24, 72)), Color(0.0, 0.0, 0.0, 0.10))
			# the open leaf lies along the main-room side of the gap, hinged at its top end
			c.draw_rect(Rect2(Vector2(bar_x + 12, top - 2), Vector2(4, 4)), Color("3a3a3d"))
			c.draw_rect(Rect2(Vector2(bar_x + 12, top - 3), Vector2(48, 7)), Color("2d2d2f"))
			c.draw_line(Vector2(bar_x + 12, top - 2), Vector2(bar_x + 60, top - 2), Color("8a8c90"), 0.9, true)
			for i in range(5): c.draw_line(Vector2(bar_x + 18 + i * 9, top - 1), Vector2(bar_x + 18 + i * 9, top + 18), Color("2d2d2f"), 2.0, true)
			c.draw_line(Vector2(bar_x + 12, top + 18), Vector2(bar_x + 60, top + 18), Color("3a3a3d"), 2.0, true)
		else:
			c.draw_rect(Rect2(Vector2(bar_x - 12, top), Vector2(24, 72)), Color(0.12, 0.1, 0.09, 0.25))
			for i in range(6):
				var x: float = bar_x - 10.0 + float(i) * 4.0
				c.draw_line(Vector2(x, top), Vector2(x, top + 72), Color("2d2d2f"), 2.2, true)
				c.draw_line(Vector2(x - 0.6, top), Vector2(x - 0.6, top + 72), Color("8a8c90"), 0.8, true)
			for y in [top + 4, top + 36, top + 68]:
				c.draw_line(Vector2(bar_x - 12, y), Vector2(bar_x + 12, y), Color("3a3a3d"), 2.6, true)
	# The sill: a strip along the doorway's outer edge, whichever way the door faces.
	var sill := Rect2(threshold.position + Vector2(0, 19), Vector2(24, 5))
	var sill_line: Array = [threshold.end - Vector2(24, 1), threshold.end - Vector2(0, 1)]
	match int(entity.get("door_side", 2)):
		0:
			sill = Rect2(threshold.position, Vector2(24, 5))
			sill_line = [threshold.position + Vector2(0, 5), threshold.position + Vector2(24, 5)]
		1:
			sill = Rect2(threshold.position + Vector2(19, 0), Vector2(5, 24))
			sill_line = [threshold.position + Vector2(23, 0), threshold.position + Vector2(23, 24)]
		3:
			sill = Rect2(threshold.position, Vector2(5, 24))
			sill_line = [threshold.position + Vector2(5, 0), threshold.position + Vector2(5, 24)]
	c.draw_rect(sill, Color("b58f5f"))
	c.draw_line(sill_line[0], sill_line[1], Color("634327"), 1)

static func furnishings(entity: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for layout in entity.get("furniture", []):
		var cells: Array = layout.rect
		var rect := Rect2(Vector2(cells[0], cells[1]) * 24 - Vector2(12, 12), Vector2(cells[2], cells[3]) * 24)
		var point := rect.position + Vector2(4, 3)
		var bottom := 0.0
		var rot: int = int(layout.get("rot", 3 if layout.kind == "bed" else 2))
		match layout.kind:
			"lamp", "chair", "chest", "locker", "toilet": point = rect.get_center() + Vector2(0, 8)
			"bed": bottom = rect.size.y - 12.0
			"table", "booking_desk": bottom = rect.size.y - 9.0
			"shelf": bottom = rect.size.y - 13.0
		items.append({"kind": layout.kind, "point": point, "bottom": bottom, "rot": rot, "center": rect.get_center(), "size": rect.size,
			"width": rect.size.x - 8, "color": Color("9fa7a5")})
	return items

## Art is authored for one base pose; the other three orientations rotate or mirror it about the
## object's own centre. Beds have dedicated vertical art so the pillow end always reads correctly.
static func draw_furnishing(c: Node2D, item: Dictionary, outer: Vector2 = Vector2.ZERO) -> void:
	var rot: int = int(item.get("rot", 3 if item.kind == "bed" else 2))
	var kind: String = item.kind
	if kind == "bed":
		var p: Vector2 = item.point
		match rot:
			3: Furniture.bed(c, p, item.color)
			1:  # head right: mirror the head-left art about the bed's own centre
				var center: Vector2 = item.center
				c.draw_set_transform_matrix(Transform2D(Vector2(-1, 0), Vector2(0, 1), outer + Vector2(2.0 * center.x, 0)))
				Furniture.bed(c, p, item.color)
				c.draw_set_transform(outer)
			0: Furniture.bed_vertical(c, p, item.color, true)
			2: Furniture.bed_vertical(c, p, item.color, false)
		return
	var turn: float = 0.0
	var flip: bool = false
	if kind in ["table", "shelf", "chest"] and rot % 2 == 1: turn = float(rot - 2) * PI / 2.0
	elif kind in ["chair", "lamp", "stove"] and rot % 2 == 1: flip = rot == 3
	if turn != 0.0:
		var middle: Vector2 = item.center
		c.draw_set_transform_matrix(Transform2D(turn, outer + middle) * Transform2D(0.0, -middle))
	elif flip:
		var middle: Vector2 = item.center
		c.draw_set_transform_matrix(Transform2D(Vector2(-1, 0), Vector2(0, 1), outer + Vector2(2.0 * middle.x, 0)))
	_draw_base_pose(c, item)
	if turn != 0.0 or flip: c.draw_set_transform(outer)

static func _draw_base_pose(c: Node2D, item: Dictionary) -> void:
	var p: Vector2 = item.point
	match item.kind:
		"lamp": lamp(c, p)
		"bed": Furniture.bed(c, p, item.color)
		"table": Furniture.table(c, p)
		"chair": chair(c, p)
		"shelf": Furniture.shelf(c, p, item.width)
		"stove": Furniture.stove(c, p)
		"chest": chest(c, p)
		"booking_desk": booking_desk(c, p, item.size)
		"locker": locker(c, p, item.size)
		"toilet": toilet(c, p)

## The intake desk in the sheriff's office: ledger, ink, a stamp, and the box camera used for mugshots.
static func booking_desk(c: Node2D, p: Vector2, size: Vector2) -> void:
	var width: float = size.x - 8.0
	var height: float = size.y - 10.0
	for offset in [Vector2(3, height - 4), Vector2(width - 8, height - 4)]:
		Furniture.timber(c, Rect2(p + offset, Vector2(5, 12)), Color("5c3d29"), 1.0)
	Furniture.timber(c, Rect2(p, Vector2(width, height)), Color("8f6540"), 4.0)
	for y in [9.0, 18.0, 27.0]:
		if y < height - 2.0: c.draw_line(p + Vector2(1, y), p + Vector2(width - 1, y), Color("6a472e"), 0.65)
	# ledger and pen
	c.draw_rect(Rect2(p + Vector2(10, 7), Vector2(20, 14)), Color("d9ccaa"))
	c.draw_line(p + Vector2(20, 7), p + Vector2(20, 21), Color("8d7c5a"), 0.8)
	c.draw_line(p + Vector2(12, 11), p + Vector2(18, 11), Color("5b5646"), 0.6)
	c.draw_line(p + Vector2(22, 11), p + Vector2(28, 11), Color("5b5646"), 0.6)
	c.draw_line(p + Vector2(32, 18), p + Vector2(38, 9), Color("3b2f26"), 1.1, true)
	Props.ellipse(c, p + Vector2(44, 13), Vector2(3.2, 2.6), Color("26241f"), 0.0, Color("6b6a66"), 0.5)
	# the box camera on a short tripod
	var camera: Vector2 = p + Vector2(width - 18, 8)
	c.draw_line(camera + Vector2(0, 8), camera + Vector2(-6, 18), Color("3b2f26"), 1.2, true)
	c.draw_line(camera + Vector2(0, 8), camera + Vector2(6, 18), Color("3b2f26"), 1.2, true)
	Furniture.timber(c, Rect2(camera + Vector2(-7, -7), Vector2(14, 14)), Color("352e28"), 1.5)
	Props.ellipse(c, camera + Vector2(0, 1), Vector2(3.6, 3.6), Color("1a1a1c"), 0.0, Color("a7adb4"), 0.8)
	c.draw_rect(Rect2(camera + Vector2(-5, -10), Vector2(10, 3)), Color("6f5e49"))

## A steel prisoner-property locker: two doors with vents and numbered plates.
static func locker(c: Node2D, p: Vector2, size: Vector2) -> void:
	var width: float = size.x - 6.0
	Props.ellipse(c, p + Vector2(0, 3), Vector2(width * 0.5 + 2.0, 4.0), Color(0, 0, 0, 0.18), 0, INK, 0)
	var left: Vector2 = p + Vector2(-width * 0.5, -36)
	Furniture.timber(c, Rect2(left, Vector2(width, 36)), Color("6d737a"), 1.6)
	var half: float = width * 0.5
	for i in range(2):
		var door: Rect2 = Rect2(left + Vector2(2 + i * half, 2), Vector2(half - 3, 32))
		c.draw_rect(door, Color("868d94") if i == 0 else Color("7d848b"))
		c.draw_rect(door, Color("40454a"), false, 0.9)
		for slot in range(3):
			c.draw_line(door.position + Vector2(3, 5 + slot * 2.2), door.position + Vector2(door.size.x - 3, 5 + slot * 2.2), Color("3f444a"), 0.8)
		c.draw_rect(Rect2(door.position + Vector2(door.size.x * 0.5 - 4, 14), Vector2(8, 5)), Color("d4cbb0"))
		c.draw_line(door.position + Vector2(door.size.x * 0.5 - 3, 16.5), door.position + Vector2(door.size.x * 0.5 + 3, 16.5), Color("5e5748"), 0.6)
		Props.ellipse(c, door.position + Vector2(door.size.x * (0.78 if i == 0 else 0.22), 24), Vector2(1.5, 1.8), Color("b9a35a"), 0.0, Color("5f4f23"), 0.5)

## A plain porcelain toilet with a cistern against the cell wall.
static func toilet(c: Node2D, p: Vector2) -> void:
	Props.ellipse(c, p + Vector2(0, 3), Vector2(11, 4), Color(0, 0, 0, 0.18), 0, INK, 0)
	Furniture.timber(c, Rect2(p + Vector2(-8, -24), Vector2(16, 12)), Color("d8d6cc"), 1.4)
	c.draw_rect(Rect2(p + Vector2(-5, -27), Vector2(10, 3)), Color("b7b6ae"))
	Props.ellipse(c, p + Vector2(0, -6), Vector2(8.5, 7.0), Color("e5e3da"), 0.0, Color("8d8b82"), 0.7)
	Props.ellipse(c, p + Vector2(0, -6), Vector2(5.6, 4.2), Color("85888a"), 0.0, Color("5b5e60"), 0.5)
	c.draw_line(p + Vector2(5, -19), p + Vector2(8, -23), Color("8e949a"), 1.2, true)

## A signpost at a fork in the road: a weathered post with a board pointing down each road (the
## sim measures `ways`: which way each road leaves the post). Older posts keep the three stock boards.
static func signpost(c: Node2D, p: Vector2, ways: Array = []) -> void:
	Props.ellipse(c, p + Vector2(0, 4), Vector2(9, 3.2), Color(0, 0, 0, 0.2), 0, INK, 0)
	Character.limb(c, p + Vector2(0, 3), p + Vector2(0, -34), Color("6e5338"), 3.2)
	var boards: Array = [[Vector2(1, -31), 1.0, Color("a98a5c"), 0.0], [Vector2(-1, -25), -1.0, Color("9b7c50"), 0.0], [Vector2(1, -19), 1.0, Color("a3845a"), 0.0]]
	if not ways.is_empty():
		boards = []
		var shades := [Color("a98a5c"), Color("9b7c50"), Color("a3845a")]
		for index in range(mini(3, ways.size())):
			var heading: Array = ways[index].get("dir", [1000, 0])
			var side: float = 1.0 if int(heading[0]) >= 0 else -1.0
			# A road heading north or south tilts its board a little up or down.
			boards.append([Vector2(side, -31 + index * 6), side, shades[index], clampf(float(heading[1]) / 1000.0, -1.0, 1.0) * 4.0])
	for board in boards:
		var at: Vector2 = board[0] + p
		var dir: float = board[1]
		var tip := at + Vector2(dir * 17, board[3])
		var points := PackedVector2Array([at + Vector2(0, -2.6), tip + Vector2(-dir * 3, -2.6), tip, tip + Vector2(-dir * 3, 2.6), at + Vector2(0, 2.6)])
		c.draw_colored_polygon(points, board[2])
		c.draw_polyline(points + PackedVector2Array([points[0]]), INK, 0.8, true)
		c.draw_line(at + Vector2(dir * 3, 0), tip + Vector2(-dir * 5, 0), Color(0.25, 0.18, 0.11, 0.55), 0.7)
	Props.nail(c, p + Vector2(0, -31), 0.9)

static func cart(c: Node2D, p: Vector2) -> void:
	Props.ellipse(c, p + Vector2(1, 9), Vector2(27, 9), Color(0, 0, 0, 0.17), 0, INK, 0)
	for x in [-21, 21]:
		var hub := p + Vector2(x, 2)
		Props.ellipse(c, hub, Vector2(5.1, 10.1), Color("4d4537"))
		Props.ellipse(c, hub, Vector2(3.7, 7.9), Color("8e6b43"), 0, Color("b39162"), 0.5)
		for spoke in range(5):
			var radius := Vector2.from_angle(spoke * TAU / 5.0) * Vector2(3.5, 7.1)
			c.draw_line(hub, hub + radius, Color("574331"), 0.7, true)
		Props.nail(c, hub, 1.25)
	for x in [-11, 11]:
		Character.limb(c, p + Vector2(x, 1), p + Vector2(x, 23), Color("a27a4b"), 2.8)
	Furniture.timber(c, Rect2(p - Vector2(19, 21), Vector2(38, 24)), Color("9c754b"), 4)
	for y in [-16, -10, -4]:
		c.draw_line(p + Vector2(-18, y), p + Vector2(18, y), Color("6e4f33"), 0.75, true)
	crate(c, p + Vector2(-7, -1))
	Props.ellipse(c, p + Vector2(11, -10), Vector2(7.5, 9.5), Color("bbab84"), 0.19)
	c.draw_line(p + Vector2(7, -16), p + Vector2(14, -17), Color("726343"), 0.8, true)
	Props.nail(c, p + Vector2(16, -3), 0.9)

# Coordinates are relative to the southern ground edge used for depth sorting.
# The wall top sits inside its 1 m footprint. Only exposed edges get bevels.
static func cutaway_wall(c: Node2D, neighbours: Dictionary) -> void:
	var north: bool = neighbours.get("north", false)
	var south: bool = neighbours.get("south", false)
	var west: bool = neighbours.get("west", false)
	var east: bool = neighbours.get("east", false)
	var left: float = -12.0 if west else -8.0
	var right: float = 12.0 if east else 8.0
	var front: float = 0.0 if south else -9.0
	var top_color := Color("704722")
	var bevel := Color("caa576")
	var lip := Color("dfbf8f")
	var edge := Color("51341f")
	c.draw_rect(Rect2(-12, -24, 24, 24), top_color)
	if not west:
		_fill(c, PackedVector2Array([
			Vector2(-12, -24), Vector2(left, -24), Vector2(left, front), Vector2(-12, 0),
		]), Color("b49264"))
		c.draw_line(Vector2(-12, -24), Vector2(-12, 0), edge, 1)
		c.draw_line(Vector2(left, -24), Vector2(left, front), Color("896540"), 0.8)
	if not east:
		_fill(c, PackedVector2Array([
			Vector2(right, -24), Vector2(12, -24), Vector2(12, 0), Vector2(right, front),
		]), Color("ad875a"))
		c.draw_line(Vector2(12, -24), Vector2(12, 0), edge, 1)
		c.draw_line(Vector2(right, -24), Vector2(right, front), Color("896540"), 0.8)
	if not south:
		c.draw_rect(Rect2(-12, 0, 24, 3), Color(0.16, 0.09, 0.04, 0.22))
		var ridge_left := lerpf(left, -12.0, 0.55)
		var ridge_right := lerpf(right, 12.0, 0.55)
		_fill(c, PackedVector2Array([
			Vector2(left, front), Vector2(right, front), Vector2(ridge_right, -4), Vector2(ridge_left, -4),
		]), bevel)
		_fill(c, PackedVector2Array([
			Vector2(ridge_left, -4), Vector2(ridge_right, -4), Vector2(12, 0), Vector2(-12, 0),
		]), lip)
		c.draw_line(Vector2(left, front), Vector2(right, front), Color("8f6943"), 0.8)
		c.draw_line(Vector2(-12, 0), Vector2(12, 0), edge, 1)
	else:
		# At a concave corner the neighbouring front and side bevels meet
		# inside this tile, without drawing a border across the solid top.
		for side in [-1, 1]:
			var connected: bool = west if side < 0 else east
			var diagonal: bool = neighbours.get("southwest" if side < 0 else "southeast", false)
			if connected and not diagonal:
				var corner := Vector2(side * 12, 0)
				var inset := Vector2(side * 8, -9)
				var ridge := Vector2(side * 12, -4)
				_fill(c, PackedVector2Array([corner, ridge, inset, Vector2(side * 8, 0)]), Color("b49264") if side < 0 else Color("ad875a"))
				_fill(c, PackedVector2Array([corner, Vector2(side * 12, -9), inset]), bevel)
	if north:
		for side in [-1, 1]:
			var connected: bool = west if side < 0 else east
			var diagonal: bool = neighbours.get("northwest" if side < 0 else "northeast", false)
			if connected and not diagonal:
				_fill(c, PackedVector2Array([
					Vector2(side * 8, -24), Vector2(side * 12, -24), Vector2(side * 12, -20),
				]), Color("b49264") if side < 0 else Color("ad875a"))
	else:
		c.draw_line(Vector2(-12, -24), Vector2(12, -24), edge, 1)

static func build_piece(c: Node2D, kind: String, fraction: float, cell: Array) -> void:
	var progress := clampf(fraction, 0.0, 1.0)
	match kind:
		"walls":
			# A timber sill becomes a full wall, anchored at the eventual depth edge.
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, progress))
			cutaway_wall(c, {"west": true, "east": true})
			c.draw_set_transform(Vector2.ZERO)
		"floor":
			var sample := Rect2(Vector2(posmod(int(cell[0]), 4), posmod(int(cell[1]), 4)) * 48, Vector2(48, 48 * progress))
			c.draw_texture_rect_region(FLOOR, Rect2(-12, -24, 24, 24 * progress), sample)
		"roof":
			roof_shakes(c, Vector2(-12, -24), progress)
		"door":
			var door := Rect2(-12, -24, 24 * progress, 24)
			c.draw_rect(door, Color("ad854f"))

static func roof_shakes(c: Node2D, point: Vector2, progress: float = 1.0) -> void:
	var height := progress * 24.0
	c.draw_rect(Rect2(point, Vector2(24, height)), Color("8d654d"))
	for i in range(4):
		var y := float(i * 6)
		if height <= y: break
		c.draw_line(point + Vector2(0, y + 1), point + Vector2(24, y + 1), Color("b68d65"), 1)
		var x := 7.0 if i % 2 == 0 else 16.0
		c.draw_line(point + Vector2(x, y), point + Vector2(x, minf(y + 6, height)), Color("674532"), 1)

static func construction(c: Node2D, entity: Dictionary, site: Dictionary, rect: Rect2) -> void:
	c.draw_rect(rect, Color(0.13, 0.09, 0.04, 0.13))
	var tiles: Dictionary = site.get("built_tiles", {})
	for cell in tiles.get("floor", []):
		var tile := Rect2(Vector2(cell[0], cell[1]) * 24 - Vector2(12, 12), Vector2(24, 24))
		floor_tile(c, tile, cell[0], cell[1])
	for cell in tiles.get("roof", []):
		roof_shakes(c, Vector2(cell[0], cell[1]) * 24 - Vector2(12, 12))
	if not tiles.get("door", []).is_empty():
		var door := Vector2(entity.cell[0], entity.cell[1]) * 24 - Vector2(12, 12)
		box(c, Rect2(door, Vector2(24, 24)), Color("ad854f"), 1)
		box(c, Rect2(door + Vector2(4, 0), Vector2(16, 6)), Color("d2b47e"), 1)
	c.draw_rect(rect, Color("dfc58f", 0.55), false, 1)

## A street lamp: a tall iron post with a glass lantern box on top. The light pool itself comes
## from the night layer, so the drawing is the same by day and by night.
static func street_lamp(c: Node2D, p: Vector2) -> void:
	Props.ellipse(c, p + Vector2(0, 3), Vector2(8, 2.8), Color(0, 0, 0, 0.2), 0, INK, 0)
	c.draw_rect(Rect2(p + Vector2(-4, -2), Vector2(8, 4)), Color("3e3a36"))
	c.draw_line(p + Vector2(0, -1), p + Vector2(0, -44), Color("2f2b28"), 3.0, true)
	c.draw_line(p + Vector2(0.8, -3), p + Vector2(0.8, -42), Color("6a625a"), 1.0, true)
	c.draw_line(p + Vector2(0, -44), p + Vector2(6, -46), Color("2f2b28"), 2.0, true)
	var box := Rect2(p + Vector2(-5, -56), Vector2(10, 11))
	c.draw_rect(box, Color("f1d48a", 0.9))
	c.draw_rect(box, Color("2f2b28"), false, 1.5)
	c.draw_line(p + Vector2(0, -56), p + Vector2(0, -45), Color("2f2b28", 0.7), 1.0)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -56), p + Vector2(7, -56), p + Vector2(0, -61)]), Color("2f2b28"))

static func lamp(c: Node2D, p: Vector2) -> void:
	for radius in [23, 17, 11]:
		c.draw_circle(p + Vector2(0, -24), radius, Color(1.0, 0.77, 0.32, 0.045))
	c.draw_colored_polygon(PackedVector2Array([
		p + Vector2(-8, 0), p + Vector2(-4, -4), p + Vector2(4, -4),
		p + Vector2(8, 0), p + Vector2(5, 3), p + Vector2(-5, 3),
	]), Color("8f5b31"))
	c.draw_line(p, p + Vector2(0, -25), Color("6c462b"), 3, true)
	c.draw_line(p + Vector2(0.5, -2), p + Vector2(0.5, -25), Color("b18653"), 1, true)
	var shade := PackedVector2Array([
		p + Vector2(-6, -32), p + Vector2(-10, -26), p + Vector2(-9, -22),
		p + Vector2(-5, -19), p + Vector2(5, -19), p + Vector2(9, -22),
		p + Vector2(10, -26), p + Vector2(6, -32),
	])
	c.draw_colored_polygon(shade, Color("e1c586"))
	shade.append(shade[0])
	c.draw_polyline(shade, Color("85643e"), 1, true)
	for side in [-1, 1]:
		c.draw_line(p + Vector2(side * 4, -30), p + Vector2(side * 5, -20), Color("ad8e57"), 0.8, true)
	var crown := PackedVector2Array()
	for index in range(24):
		var angle := TAU * index / 24.0
		crown.append(p + Vector2(7 * cos(angle), -32 + 3.6 * sin(angle)))
	c.draw_colored_polygon(crown, Color("f2dfae"))
	crown.append(crown[0])
	c.draw_polyline(crown, Color("85643e"), 1, true)
	c.draw_arc(p + Vector2(0, 0.1), 4.0, PI * 0.12, PI * 0.90, 10, Color("cb9e63"), 0.6, true)
	c.draw_line(p + Vector2(7, -21), p + Vector2(7, -16), Color("714d2d"), 0.68, true)
	Props.ellipse(c, p + Vector2(7, -15.5), Vector2(0.85, 1.3), Color("ad7745"), 0, Color("805735"), 0.45)

static func chair(c: Node2D, p: Vector2) -> void:
	for x in [-7, 7]:
		Character.limb(c, p + Vector2(x, -7), p + Vector2(x, 5), Color("745237"), 2.3)
		Character.limb(c, p + Vector2(x, -26), p + Vector2(x, -8), Color("926a43"), 2.4)
	Furniture.timber(c, Rect2(p - Vector2(9, 12), Vector2(18, 10)), Color("ba8f5f"), 2.7)
	for offset in [-4, 1, 5]:
		c.draw_line(p + Vector2(offset, -11), p + Vector2(offset, -3), Color("967046"), 0.63, true)
	for y in [-26, -19]:
		Furniture.timber(c, Rect2(p + Vector2(-9, y), Vector2(18, 4)), Color("9f744a"), 1.4)
		for x in [-7, 7]: Props.nail(c, p + Vector2(x, y + 2), 0.65)

static func chest(c: Node2D, p: Vector2) -> void:
	Props.ellipse(c, p + Vector2(1, 3), Vector2(18, 4), Color(0, 0, 0, 0.18), 0, INK, 0)
	Furniture.timber(c, Rect2(p - Vector2(16, 17), Vector2(32, 17)), Color("815637"), 2.0)
	for y in [-9, -4]:
		c.draw_line(p + Vector2(-15, y), p + Vector2(15, y), Color("64412c"), 0.7, true)
	Props.polygon(c, PackedVector2Array([p + Vector2(-16, -14), p + Vector2(-14, -21),
		p + Vector2(-10, -24), p + Vector2(11, -24), p + Vector2(15, -21),
		p + Vector2(16, -14)]), Color("a57b4d"))
	Props.grain(c, Rect2(p - Vector2(12, 23), Vector2(24, 9)), Color("89613d"))
	for x in [-11, 10]:
		c.draw_polyline(PackedVector2Array([p + Vector2(x, -23), p + Vector2(x, -15),
			p + Vector2(x, -6), p + Vector2(x, 0)]), Color("57615a"), 3.1, true)
		c.draw_line(p + Vector2(x - 0.6, -21), p + Vector2(x - 0.6, -3), Color("9da396"), 0.7, true)
		for y in [-20, -11, -4]: Props.nail(c, p + Vector2(x, y), 0.66)
	Props.ellipse(c, p + Vector2(0, -12), Vector2(3.1, 2.7), Color("cead62"), 0, Color("6c572f"))
	c.draw_line(p + Vector2(0, -13), p + Vector2(0, -10.8), Color("604823"), 1.0, true)

static func frontage(c: Node2D, entity: Dictionary, rect: Rect2) -> void:
	var door := Vector2(entity.cell[0], entity.cell[1]) * 24
	# A short stoop marks the open doorway and leaves the rest of the facade clear.
	var stoop: Rect2
	match int(entity.get("door_side", 2)):
		0: stoop = Rect2(door.x - 12, door.y - 24, 24, 12)
		1: stoop = Rect2(door.x + 12, door.y - 12, 12, 24)
		3: stoop = Rect2(door.x - 24, door.y - 12, 12, 24)
		_: stoop = Rect2(door.x - 12, rect.end.y, 24, 12)
	c.draw_rect(stoop, Color("9e7448"))
	if stoop.size.x > stoop.size.y:
		c.draw_line(stoop.position + Vector2(0, 5), stoop.position + Vector2(24, 5), Color("bd9665"), 1)
		c.draw_line(stoop.end - Vector2(24, 1), stoop.end - Vector2(0, 1), Color("65452c"), 1)
	else:
		c.draw_line(stoop.position + Vector2(5, 0), stoop.position + Vector2(5, 24), Color("bd9665"), 1)
		c.draw_line(stoop.end - Vector2(1, 24), stoop.end - Vector2(1, 0), Color("65452c"), 1)

static func square(c: Node2D, center: Vector2) -> void:
	for dx in [-75, 75]:
		box(c, Rect2(center + Vector2(dx - 20, 26), Vector2(40, 9)), Color("8d643a"), 1)
		lamp(c, center + Vector2(dx, -20))

static func vegetation(c: Node2D, bounds: Rect2, buildings: Array, wind_phase: float = 0.0, wind_strength: float = 0.0, road_coverage: Callable = Callable(), dry_center: Vector2 = Vector2(122, 126)) -> void:
	for y in range(floori(bounds.position.y / 24), ceili(bounds.end.y / 24)):
		for x in range(floori(bounds.position.x / 24), ceili(bounds.end.x / 24)):
			var hash_value: int = absi(x * 719 ^ y * 113 ^ x * y * 31)
			if hash_value % 5 != 0: continue
			var cell_rect := Rect2(Vector2(x, y) * 24, Vector2(24, 24))
			var intersects: bool = false
			for rect in buildings:
				if rect.has_point(cell_rect.get_center()): intersects = true; break
			if intersects: continue
			var base := cell_rect.position + Vector2(6 + hash_value % 9, 17)
			if road_coverage.is_valid() and road_coverage.call(base) > 0.53: continue
			var shade: Color = season_grass(Color("355a33") if hash_value % 2 == 0 else Color("53723e"))
			if Vector2(float(x) - dry_center.x, (float(y) - dry_center.y) * 1.2).length() < 46.0: shade = Color("8a7448") if hash_value % 2 == 0 else Color("a38b57")  # dry grass around Dustvale
			var sway: float = sin(wind_phase + float(x) * 0.19 + float(y) * 0.13) * wind_strength * 2.0
			c.draw_line(base, base + Vector2(-2 + sway, -6), shade, 1.4, true)
			c.draw_line(base + Vector2(1, 0), base + Vector2(3 + sway, -8), shade.lightened(0.12), 1.4, true)

## A door leaf (or a pair) in a doorway. `data`: a and b are the two ends of the gap, in the node's own
## coordinates; `inward` is the unit vector the door swings towards; `style` is "plank" or "heavy";
## `double` hangs two half-width leaves. `openness` is 0 (shut) to 1 (swung about 100 degrees).
static func door(c: Node2D, data: Dictionary, openness: float) -> void:
	var a: Vector2 = data.a
	var b: Vector2 = data.b
	var along: Vector2 = (b - a).normalized()
	var length: float = a.distance_to(b)
	var inward: Vector2 = data.inward
	var angle: float = openness * deg_to_rad(100.0)
	var heavy: bool = str(data.get("style", "plank")) == "heavy"
	var wood: Color = Color("5f4636") if heavy else Color("8c6340")
	var light: Color = Color("7a6048") if heavy else Color("a97b4d")
	# Posts either side of the opening.
	for end in [a, b]:
		c.draw_rect(Rect2(end - Vector2(3, 3), Vector2(6, 6)), Color("4a3524"))
		c.draw_rect(Rect2(end - Vector2(2, 2), Vector2(4, 4)), Color("6d4e34"))
	var leaves: Array = []
	if bool(data.get("double", false)):
		leaves.append([a, along, length * 0.5, 1.0])
		leaves.append([b, -along, length * 0.5, 1.0])
	else:
		leaves.append([a, along, length, 1.0])
	for leaf in leaves:
		var hinge: Vector2 = leaf[0]
		var u: Vector2 = leaf[1]
		var size: float = leaf[2]
		var direction: Vector2 = (u * cos(angle) + inward * sin(angle)).normalized()
		var tip: Vector2 = hinge + direction * (size - 1.0)
		var normal := Vector2(-direction.y, direction.x) * 2.6
		var polygon := PackedVector2Array([hinge + normal, tip + normal, tip - normal, hinge - normal])
		c.draw_colored_polygon(polygon, wood)
		c.draw_polyline(PackedVector2Array([hinge + normal, tip + normal, tip - normal, hinge - normal, hinge + normal]), Color("30291e"), 1.2, true)
		c.draw_line(hinge + direction * 2.0, tip - direction * 2.0, light, 1.4, true)
		var planks: int = 3 if size > 14.0 else 1
		for index in range(1, planks + 1):
			var at: Vector2 = hinge + direction * (size * float(index) / float(planks + 1))
			c.draw_line(at + normal * 0.8, at - normal * 0.8, Color("3d2d1f"), 0.9)
		c.draw_circle(tip - direction * 3.0, 1.1, Color("2d2d2f") if not heavy else Color("c4b37a"))   # the latch
		if heavy:
			for index in range(3): c.draw_circle(hinge + direction * (size * (0.25 + 0.25 * index)), 0.9, Color("34353a"))
