extends RefCounted
## Roofs. Every finished building has a roof over its exact shape (L- and T-shaped houses too): a
## node of its own, y-sorted at the building's front edge, so people inside are covered and people
## in front of it are drawn over it. The roof of the building the player is in is lifted away, so
## you see the room you're standing in; from outside you see roofs. People inside a roofed building
## are not drawn (and cost nothing). Zoomed far out every building is just its roof. View only.
const World = preload("res://sim/world/world_db.gd")
const CELL := 24.0
const CIVIC := ["office", "warehouse", "market", "saloon", "town_hall"]
const WORKSHOP := ["sawmill", "bakery", "forge"]

class Roof extends Node2D:
	var spans: Array = []          # [Rect2] in pixels relative to this node, one per row run of cells
	var bounds := Rect2()
	var kind: String = "home"
	var base := Color("9c6a45")
	var chimney: bool = true
	func _draw() -> void:
		var dark: Color = base.darkened(0.28)
		var light: Color = base.lightened(0.12)
		var shade := Color(0, 0, 0, 0.22)
		draw_rect(Rect2(bounds.position + Vector2(5, 7), bounds.size), shade)        # the roof's shadow on the ground
		for span in spans:
			draw_rect(span, base)
		# Shingle courses across, and the ridge along the long side, with a lit and a shaded slope.
		var horizontal: bool = bounds.size.x >= bounds.size.y
		for span in spans:
			var r: Rect2 = span
			var y: float = r.position.y + 6.0
			while y < r.end.y - 1.0:
				draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), dark, 1.0)
				y += 7.0
		var mid: float = bounds.get_center().y if horizontal else bounds.get_center().x
		for span in spans:
			var r: Rect2 = span
			if horizontal:
				if r.position.y < mid: draw_rect(Rect2(r.position, Vector2(r.size.x, minf(r.size.y, mid - r.position.y))), Color(light, 0.35))
				if r.end.y > mid and r.position.y <= mid + 1: draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), dark.darkened(0.2), 3.0)
			else:
				if r.position.x < mid: draw_rect(Rect2(r.position, Vector2(minf(r.size.x, mid - r.position.x), r.size.y)), Color(light, 0.35))
				if r.position.x <= mid and r.end.x >= mid: draw_line(Vector2(mid, r.position.y), Vector2(mid, r.end.y), dark.darkened(0.2), 3.0)
		for span in spans:
			draw_rect(span, dark.darkened(0.25), false, 2.0)                           # eaves
		# A chimney on homes, workshops and the saloon.
		if chimney:
			var at := bounds.position + Vector2(bounds.size.x * 0.72, bounds.size.y * 0.25)
			draw_rect(Rect2(at, Vector2(14, 16)), Color("6b4a36"))
			draw_rect(Rect2(at + Vector2(-2, -3), Vector2(18, 4)), Color("4d3426"))

var nodes: Dictionary = {}          # building id -> Roof
var signature: Array = []
var hidden_id: int = 0              # the building whose roof is lifted (the player's), 0 for none
var inside_cache: Dictionary = {}   # actor key -> [cell, building id]

## Keeps a roof for every finished building; lifts the one the player is in (none when far out).
func sync(view: Node2D, s: Dictionary, player_point: Vector2, far: bool) -> void:
	var buildings: Array = World.buildings(s)
	var sig := [buildings.size(), World.entity_serial, s.get("completed_buildings", 0)]
	if sig != signature:
		signature = sig
		for id in nodes.keys():
			nodes[id].queue_free()
		nodes.clear()
		inside_cache.clear()
		for building in buildings:
			if not building.has("footprint"): continue
			var roof := _make(view, s, building)
			if roof != null: nodes[int(building.id)] = roof
	var player_cell: Array = [roundi(player_point.x / CELL), roundi(player_point.y / CELL)]
	hidden_id = 0 if far else World.inside_building(s, player_cell)
	for id in nodes:
		nodes[id].visible = int(id) != hidden_id

func _make(view: Node2D, s: Dictionary, building: Dictionary) -> Roof:
	var rect: Rect2i = World.building_rect(building)
	var roof := Roof.new()
	roof.kind = str(building.get("kind", "home"))
	var colour: Color = Color("a5523a") if roof.kind in CIVIC else (Color("7f6b58") if roof.kind in WORKSHOP else Color("9c6a45"))
	roof.base = colour * view.house_tint(s, int(building.id))
	roof.chimney = roof.kind not in ["warehouse", "market", "office", "town_hall"]
	# The node sits at the building's front (south) edge so it sorts with the people around it.
	var front_y: float = float(rect.end.y - 1) * CELL + CELL / 2.0 + 2.0
	roof.position = Vector2(float(rect.position.x) * CELL, front_y)
	var origin: Vector2 = roof.position
	var spans: Array = []
	var all := Rect2()
	for y in range(rect.position.y, rect.end.y):
		var start := -1
		for x in range(rect.position.x, rect.end.x + 1):
			var inside: bool = x < rect.end.x and World.building_contains(building, [x, y])
			if inside and start < 0: start = x
			elif not inside and start >= 0:
				var r := Rect2(Vector2(start, y) * CELL - Vector2.ONE * CELL / 2.0 - origin, Vector2(x - start, 1) * CELL)
				r = r.grow_individual(3, 0 if y > rect.position.y else 3, 3, 0)   # a little overhang
				spans.append(r)
				all = r if all.size == Vector2.ZERO else all.merge(r)
				start = -1
	if spans.is_empty(): return null
	roof.spans = spans
	roof.bounds = all
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
