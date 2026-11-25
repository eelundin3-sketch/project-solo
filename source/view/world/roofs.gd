extends RefCounted
## Buildings seen from outside, with height. The view is three-quarter top-down (looking slightly
## from the south), so a building shows its front wall standing up (planks, windows, the door) and
## its roof lifted by the wall's height: a house is about one and a half times as tall as a person,
## the saloon and the town house two storeys. Every finished building has one, over its exact
## shape (L- and T-shaped houses too), as a node of its own y-sorted at the building's front edge:
## people in front are drawn over it, people behind are hidden by it. The building the player is
## in is lifted away so you see the room; a building you stand behind (or one rising into your room
## from the south) fades so you can see yourself. People inside a roofed building are not drawn.
## Zoomed far out the walls are plain. View only.
const World = preload("res://sim/world/world_db.gd")
const CELL := 24.0
const CIVIC := ["office", "warehouse", "market", "saloon", "town_hall"]
const WORKSHOP := ["sawmill", "bakery", "forge"]
## Wall height in pixels by kind (a person is about 44 px tall).
const HEIGHTS := {"home": 64.0, "sawmill": 72.0, "bakery": 72.0, "forge": 72.0, "office": 80.0, "market": 80.0, "warehouse": 80.0, "saloon": 96.0, "town_hall": 96.0}
const FADED := 0.38
const PERSON_HEIGHT := 44.0

class Roof extends Node2D:
	var rows: Array = []           # per building row, north to south: {"span": Rect2 (roof, unshifted), "faces": [Rect2 ground cells with open ground to the south]}
	var bounds := Rect2()
	var kind: String = "home"
	var base := Color("9c6a45")
	var wall := Color("a57f55")
	var height: float = 64.0
	var chimney: bool = true
	var chimney_at := Vector2.ZERO
	var door_x: float = INF        # the door's x (node space) when it sits on a south face
	var door_ground: float = 0.0
	var far: bool = false
	var night: bool = false
	var smoking: bool = false
	var smoke_time: float = 0.0
	func _draw() -> void:
		var lift := Vector2(0, -height)
		var dark: Color = base.darkened(0.28)
		var light: Color = base.lightened(0.12)
		# The shadow it casts on the ground, south-east.
		var shade_len: float = height * 0.45
		for row in rows:
			for face in row.faces:
				var f: Rect2 = face
				draw_colored_polygon(PackedVector2Array([f.position + Vector2(0, f.size.y), f.end, f.end + Vector2(shade_len, shade_len * 0.35), f.position + Vector2(shade_len, f.size.y + shade_len * 0.35)]), Color(0, 0, 0, 0.2))
		var horizontal: bool = bounds.size.x >= bounds.size.y
		var mid: float = (bounds.get_center().y if horizontal else bounds.get_center().x)
		for row in rows:
			# The roof over this row, lifted by the wall's height.
			var r: Rect2 = row.span
			r.position += lift
			draw_rect(r, base)
			if not far:
				var y: float = r.position.y + 6.0
				while y < r.end.y - 1.0:
					draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), dark, 1.0)
					y += 7.0
				if horizontal:
					var m: float = mid - height
					if r.position.y < m: draw_rect(Rect2(r.position, Vector2(r.size.x, minf(r.size.y, m - r.position.y))), Color(light, 0.35))
					if r.end.y > m and r.position.y <= m + 1: draw_line(Vector2(r.position.x, m), Vector2(r.end.x, m), dark.darkened(0.2), 3.0)
				else:
					if r.position.x < mid: draw_rect(Rect2(r.position, Vector2(minf(r.size.x, mid - r.position.x), r.size.y)), Color(light, 0.35))
					if r.position.x <= mid and r.end.x >= mid: draw_line(Vector2(mid, r.position.y), Vector2(mid, r.end.y), dark.darkened(0.2), 3.0)
			draw_line(r.position + Vector2(0, 1), Vector2(r.end.x, r.position.y + 1), dark.darkened(0.25), 2.0)
			draw_line(Vector2(r.position.x, r.end.y), r.end, dark.darkened(0.35), 2.0)   # the eave over the front
			# Its front walls, standing on the ground.
			for face in row.faces:
				_wall(face)
		if chimney:
			var at := chimney_at + lift
			draw_rect(Rect2(at, Vector2(14, 22)), Color("6b4a36"))
			draw_rect(Rect2(at + Vector2(-2, -3), Vector2(18, 4)), Color("4d3426"))
			if smoking and not far:
				for i in range(5):
					var age: float = fmod(smoke_time * 0.35 + float(i) * 0.2, 1.0)
					var puff := at + Vector2(7 + sin(age * 6.0 + float(i)) * 4.0 + age * 10.0, -4 - age * 46.0)
					draw_circle(puff, 4.0 + age * 9.0, Color(0.78, 0.76, 0.72, 0.5 * (1.0 - age)))

	## A stretch of front wall: from the ground line up to the eaves.
	func _wall(face: Rect2) -> void:
		var top: float = face.end.y - height
		var w := Rect2(Vector2(face.position.x, top), Vector2(face.size.x, height))
		draw_rect(w, wall)
		if far:
			for x in range(int(w.position.x) + 8, int(w.end.x) - 6, 24):
				draw_rect(Rect2(Vector2(x, top + height * 0.3), Vector2(8, 10)), wall.darkened(0.5))
			return
		# Plank courses and the boards' joints.
		var y: float = top + 7.0
		while y < face.end.y - 2.0:
			draw_line(Vector2(w.position.x, y), Vector2(w.end.x, y), wall.darkened(0.16), 1.0)
			y += 7.0
		draw_rect(Rect2(Vector2(w.position.x, top), Vector2(w.size.x, 6)), wall.darkened(0.32))      # under the eaves
		draw_rect(Rect2(Vector2(w.position.x, face.end.y - 5), Vector2(w.size.x, 5)), wall.darkened(0.42))   # the sill on the ground
		draw_rect(Rect2(Vector2(w.position.x, top), Vector2(3, height)), wall.darkened(0.38))       # corner posts
		draw_rect(Rect2(Vector2(w.end.x - 3, top), Vector2(3, height)), wall.darkened(0.38))
		# Windows every couple of cells (a second row on two-storey buildings), not over the door.
		var storeys: int = 2 if height >= 90.0 else 1
		var pane: Color = Color("f2c766") if night else Color("3b4650")
		for storey in range(storeys):
			var wy: float = face.end.y - height * (0.62 if storeys == 1 else (0.42 + 0.4 * storey))
			var x: float = w.position.x + 14.0
			while x + 14.0 < w.end.x - 6.0:
				if absf(x + 7.0 - door_x) > 18.0 or storey > 0:
					draw_rect(Rect2(Vector2(x - 2, wy - 2), Vector2(18, 18)), wall.darkened(0.45))
					draw_rect(Rect2(Vector2(x, wy), Vector2(14, 14)), pane)
					draw_line(Vector2(x + 7, wy), Vector2(x + 7, wy + 14), wall.darkened(0.45), 1.2)
					draw_line(Vector2(x, wy + 7), Vector2(x + 14, wy + 7), wall.darkened(0.45), 1.2)
				x += 40.0
		# The door, where it sits in this wall.
		if door_x >= w.position.x and door_x <= w.end.x and absf(face.end.y - door_ground) < 1.0:
			var door := Rect2(Vector2(door_x - 9, face.end.y - 38), Vector2(18, 38))
			draw_rect(door.grow(2), wall.darkened(0.5))
			draw_rect(door, Color("5c3d24"))
			draw_line(door.position + Vector2(9, 2), door.position + Vector2(9, 36), Color("3f2918"), 1.0)
			draw_circle(door.position + Vector2(14, 21), 1.4, Color("d9b867"))
		# The saloon and the town house: a false front rising over the roof line.
		if kind in ["saloon", "town_hall"]:
			draw_rect(Rect2(Vector2(w.position.x, top - 14), Vector2(w.size.x, 16)), wall.darkened(0.08))
			draw_line(Vector2(w.position.x, top - 14), Vector2(w.end.x, top - 14), wall.darkened(0.45), 2.0)

var nodes: Dictionary = {}          # building id -> Roof
var signature: Array = []
var hidden_id: int = 0              # the building whose roof is lifted (the player's), 0 for none
var inside_cache: Dictionary = {}   # actor key -> [cell, building id]
var was_far: bool = false
var was_night: bool = false

## Keeps a roof for every finished building; lifts the one the player is in (none when far out),
## and fades one the player is behind or that rises into the player's room.
func sync(view: Node2D, s: Dictionary, player_point: Vector2, far: bool) -> bool:
	var buildings: Array = World.buildings(s)
	var sig := [buildings.size(), World.entity_serial, s.get("completed_buildings", 0)]
	var rebuilt := false
	if sig != signature:
		signature = sig
		rebuilt = true
		for id in nodes.keys():
			nodes[id].queue_free()
		nodes.clear()
		inside_cache.clear()
		for building in buildings:
			if not building.has("footprint"): continue
			var roof := _make(view, s, building)
			if roof != null: nodes[int(building.id)] = roof
	var night: bool = load("res://sim/world/light.gd").daylight(s) < 55
	if far != was_far or night != was_night:
		was_far = far
		was_night = night
		for id in nodes:
			nodes[id].far = far
			nodes[id].night = night
			nodes[id].queue_redraw()
	var player_cell: Array = [roundi(player_point.x / CELL), roundi(player_point.y / CELL)]
	var before: int = hidden_id
	hidden_id = 0 if far else World.inside_building(s, player_cell)
	var mine: Rect2 = Rect2()
	if hidden_id != 0 and nodes.has(hidden_id):
		var own: Roof = nodes[hidden_id]
		mine = Rect2(own.position + own.bounds.position, own.bounds.size)
	for id in nodes:
		var roof: Roof = nodes[id]
		roof.visible = int(id) != hidden_id
		var alpha := 1.0
		if not far and roof.visible:
			# Its raised part: the area above the footprint that the walls and roof stand over.
			var raised := Rect2(roof.position + roof.bounds.position - Vector2(0, roof.height), Vector2(roof.bounds.size.x, roof.height + 2.0))
			if raised.grow(-2).has_point(player_point + Vector2(0, -10)): alpha = FADED
			elif mine.size != Vector2.ZERO and raised.intersects(mine.grow(-4)): alpha = FADED
		if not is_equal_approx(roof.modulate.a, alpha): roof.modulate.a = alpha
	return rebuilt or before != hidden_id

## Chimneys smoke while the oven or forge inside is going.
func animate_smoke(running: Dictionary, time: float) -> void:
	for id in nodes:
		var roof: Roof = nodes[id]
		var on: bool = bool(running.get(str(id), false))
		if on or roof.smoking != on:
			roof.smoking = on
			roof.smoke_time = time
			roof.queue_redraw()

func _make(view: Node2D, s: Dictionary, building: Dictionary) -> Roof:
	var rect: Rect2i = World.building_rect(building)
	var roof := Roof.new()
	roof.kind = str(building.get("kind", "home"))
	roof.height = float(HEIGHTS.get(roof.kind, 64.0))
	var tint: Color = view.house_tint(s, int(building.id))
	var colour: Color = Color("a5523a") if roof.kind in CIVIC else (Color("7f6b58") if roof.kind in WORKSHOP else Color("9c6a45"))
	roof.base = colour * tint
	roof.wall = (Color("b89466") if roof.kind not in CIVIC else Color("c2a274")) * tint
	if roof.kind == "saloon": roof.wall = Color("a8744c") * tint
	if roof.kind == "town_hall": roof.wall = Color("d1c3a4") * tint
	roof.chimney = roof.kind not in ["warehouse", "market", "office", "town_hall"]
	# The node sits at the building's front (south) edge so it sorts with the people around it.
	var front_y: float = float(rect.end.y - 1) * CELL + CELL / 2.0 + 2.0
	roof.position = Vector2(float(rect.position.x) * CELL, front_y)
	var origin: Vector2 = roof.position
	var rows: Array = []
	var all := Rect2()
	for y in range(rect.position.y, rect.end.y):
		var start := -1
		for x in range(rect.position.x, rect.end.x + 1):
			var inside: bool = x < rect.end.x and World.building_contains(building, [x, y])
			if inside and start < 0: start = x
			elif not inside and start >= 0:
				var r := Rect2(Vector2(start, y) * CELL - Vector2.ONE * CELL / 2.0 - origin, Vector2(x - start, 1) * CELL)
				r = r.grow_individual(3, 0 if y > rect.position.y else 3, 3, 0)   # a little overhang
				# Front walls: the cells of this run with open ground to the south.
				var faces: Array = []
				var face_start := -1
				for fx in range(start, x + 1):
					var open: bool = fx < x and not World.building_contains(building, [fx, y + 1])
					if open and face_start < 0: face_start = fx
					elif not open and face_start >= 0:
						faces.append(Rect2(Vector2(face_start, y) * CELL - Vector2.ONE * CELL / 2.0 - origin, Vector2(fx - face_start, 1) * CELL))
						face_start = -1
				rows.append({"span": r, "faces": faces})
				all = r if all.size == Vector2.ZERO else all.merge(r)
				start = -1
	if rows.is_empty(): return null
	roof.rows = rows
	roof.bounds = all
	roof.chimney_at = all.position + Vector2(all.size.x * 0.72, all.size.y * 0.25)
	var door: Array = building.get("door", [])
	if door.size() == 2 and not World.building_contains(building, [door[0], door[1] + 1]):
		roof.door_x = float(door[0]) * CELL - origin.x
		roof.door_ground = (float(door[1]) + 0.5) * CELL - origin.y
	view.add_child(roof)
	return roof

## True when the actor at `point` is inside a building whose roof is on (so it is not drawn).
func covered(s: Dictionary, key: String, point: Vector2) -> bool:
	var cell: Array = [roundi(point.x / CELL), roundi(point.y / CELL)]
	var cached: Array = inside_cache.get(key, [])
	var building: int
	if not cached.is_empty() and cached[0] == cell: building = int(cached[1])
	else:
		building = World.inside_building(s, cell)
		inside_cache[key] = [cell, building]
	return building != 0 and building != hidden_id and nodes.has(building)

## Whether the building with this id is drawn roofed (so its doors and inside are hidden).
func roofed(id: int) -> bool:
	return nodes.has(id) and nodes[id].visible
