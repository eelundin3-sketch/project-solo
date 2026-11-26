extends RefCounted
## Your own house, on the west side of Alder Hollow (the town you start in). Door to the south: an
## entrance hall; the bedroom to the left of it (a double bed, a chest, a lamp); straight ahead the
## living room across the house (a fireplace and sofa, a table and chairs, and the kitchen corner:
## a counter, a stove and the fridge); a back door from the living room onto a wooden terrace
## behind the house, outside, with a workout area: a squat rack, a bench press, a deadlift
## platform, a pull-up bar and a plate tree. It is yours (`s.player_home`): no household is given
## it and townsfolk keep out. Made once, for new games and for older saves on load. The things in
## it are used with F (activities.gd).
const World = preload("res://sim/world/world_db.gd")
const Housing = preload("res://sim/settlement/housing.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const ENTRY := {"id": "player_house", "name": "Your house", "size": [16, 12], "shape": "rect", "beds": 1, "partition": false, "style": "redwood"}
const W := 16
const H := 12
const TERRACE := 6
## Workout pieces stand on the open deck: you walk among them, nothing blocks.
const OPEN_KINDS := ["deck", "squat_rack", "bench_press", "deadlift_platform", "pullup_bar"]

static func house(s: Dictionary) -> Dictionary:
	return s.get("entities", {}).get(str(s.get("player_home", 0)), {})

static func is_player_house(building: Dictionary) -> bool:
	return bool(building.get("player_house", false))

static func ensure(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if s.has("player_home") or not s.has("settlements") or not s.settlements.has("1") or not s.has("residents"): return
	var door: Array = _plot(s)
	if door.is_empty(): return
	var left: int = int(door[0]) - W / 2
	var top: int = int(door[1]) - (H - 1)
	var terrace: Array = [left, top - TERRACE, W, TERRACE]
	_clear_trees(s, Rect2i(left, top - TERRACE, W, H + TERRACE))
	var fields: Dictionary = Housing.placed_fields(ENTRY, door, 2)
	fields.player_house = true
	fields.house_walls = _walls(left, top)
	fields.back_doors = [[int(door[0]), top]]
	fields.terrace = terrace
	var id: int = World.add_entity(sim, "home", "Your house", door, 1, fields)
	s.player_home = id
	if not s.inventories.has(str(id)): load("res://sim/inventory/inventory_store.gd").create(s, id, 200)
	load("res://sim/entities/chests.gd").ensure_all(sim)   # the bedroom chest
	sim.record("You have a house of your own on the west side of Alder Hollow.")

## Inside walls (door-south layout): the bedroom left of the entrance, with a doorway into it.
static func _walls(left: int, top: int) -> Array:
	var cells: Array = []
	for y in range(5, H - 1):
		if y != 8: cells.append([left + 6, top + y])   # the bedroom wall, with its doorway
	for x in range(1, 6): cells.append([left + x, top + 5])   # the bedroom's back wall
	return cells

## The furniture, in place (fixtures.gd calls this for your house).
static func furniture(building: Dictionary) -> Array:
	var f: Array = building.footprint
	var l: int = int(f[0])
	var t: int = int(f[1])
	return [
		# The bedroom.
		{"kind": "bed", "rect": [l + 1, t + 6, 2, 3], "rot": 0, "for": "player"},
		{"kind": "chest", "rect": [l + 4, t + 10, 2, 1], "rot": 2},
		{"kind": "lamp", "rect": [l + 5, t + 6, 1, 1], "rot": 2},
		# The living room: fire and sofa, table and chairs, the kitchen corner.
		{"kind": "fireplace", "rect": [l + 1, t + 1, 2, 1], "rot": 2},
		{"kind": "sofa", "rect": [l + 1, t + 3, 3, 1], "rot": 0},
		{"kind": "lamp", "rect": [l + 5, t + 1, 1, 1], "rot": 2},
		{"kind": "table", "rect": [l + 9, t + 4, 2, 2], "rot": 2},
		{"kind": "chair", "rect": [l + 8, t + 5, 1, 1], "rot": 1},
		{"kind": "chair", "rect": [l + 11, t + 4, 1, 1], "rot": 3},
		{"kind": "counter", "rect": [l + 10, t + 1, 3, 1], "rot": 2},
		{"kind": "stove", "rect": [l + 13, t + 1, 1, 1], "rot": 2},
		{"kind": "fridge", "rect": [l + 14, t + 1, 1, 1], "rot": 2},
		# The terrace behind the house: a plank deck and the workout area.
		{"kind": "deck", "rect": [l, t - TERRACE, W, TERRACE], "rot": 2},
		{"kind": "squat_rack", "rect": [l + 1, t - 5, 3, 2], "rot": 2},
		{"kind": "bench_press", "rect": [l + 5, t - 5, 2, 3], "rot": 2},
		{"kind": "deadlift_platform", "rect": [l + 9, t - 5, 3, 2], "rot": 2},
		{"kind": "pullup_bar", "rect": [l + 13, t - 5, 2, 1], "rot": 2},
		{"kind": "plate_tree", "rect": [l + 14, t - 2, 1, 1], "rot": 2},
	]

## A door cell on the west side of town with room for the house and its terrace behind it: clear of
## roads, other buildings, fields and the market, with open ground in front. Trees may stand there
## (they're moved aside).
static func _plot(s: Dictionary) -> Array:
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var blocked: Array = Housing.blocked_areas(s, false)
	var roads: Dictionary = TownLayout.road_cells(s)
	var trees: Dictionary = {}
	for e in s.entities.values():
		if str(e.get("kind", "")) == "tree": trees["%d,%d" % [e.cell[0], e.cell[1]]] = true
	for dx in range(22, 90):
		for dy in [4, 2, 6, 0, 8, -2, 10, -4, 12]:
			var door: Array = [int(store[0]) - dx, int(store[1]) + dy]
			var left: int = door[0] - W / 2
			var top: int = door[1] - (H - 1)
			var rect := Rect2i(left, top - TERRACE, W, H + TERRACE)
			var clear := true
			for area in blocked:
				if area.intersects(rect.grow(1)): clear = false; break
			if not clear: continue
			for y in range(rect.position.y - 1, rect.end.y + 1):
				for x in range(rect.position.x - 1, rect.end.x + 1):
					var key := "%d,%d" % [x, y]
					if roads.has(key) or (not World.walkable(s, [x, y]) and not trees.has(key)) or World.inside_building(s, [x, y]) != 0: clear = false; break
				if not clear: break
			if not clear: continue
			# Open ground in front of the door, to the street.
			for step in range(1, 4):
				var c: Array = [door[0], door[1] + step]
				if not World.walkable(s, c) and not trees.has("%d,%d" % [c[0], c[1]]): clear = false
			if clear: return door
	return []

## Trees standing on the plot are moved aside (moved, not removed: their wood stays counted).
static func _clear_trees(s: Dictionary, rect: Rect2i) -> void:
	var keys: Array = s.entities.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = s.entities[key]
		if str(e.get("kind", "")) != "tree" or not rect.grow(1).has_point(Vector2i(e.cell[0], e.cell[1])): continue
		for r in range(2, 30):
			var moved := false
			for d in [[-1, 0], [1, 0], [0, 1], [0, -1]]:
				var c: Array = [rect.position.x + rect.size.x / 2 + d[0] * (rect.size.x / 2 + r), rect.position.y + rect.size.y / 2 + d[1] * (rect.size.y / 2 + r)]
				c = [c[0] + int(key.hash()) % 5 - 2, c[1]]
				if World.walkable(s, c) and World.inside_building(s, c) == 0 and not rect.grow(1).has_point(Vector2i(c[0], c[1])):
					World.move_record(s, e, c)
					moved = true
					break
			if moved: break
