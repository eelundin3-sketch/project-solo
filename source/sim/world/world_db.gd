extends RefCounted
const Fixtures = preload("res://sim/world/fixtures.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Names = preload("res://sim/entities/names.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Terrain = preload("res://sim/world/terrain.gd")
const DerivedCache = preload("res://sim/core/derived_cache.gd")
const CHUNK_SIDE: int = 64
const WIDTH: int = 128
const HEIGHT: int = 96
const METERS_PER_CELL: float = 1.0

const VILLAGE_HOME_PLOTS := [Vector2i(-18, 17), Vector2i(0, 19), Vector2i(0, 35)]

static func reserved_home_plots(center: Array) -> Array[Rect2i]:
	var plots: Array[Rect2i] = []
	for offset in VILLAGE_HOME_PLOTS:
		plots.append(footprint([center[0] + offset.x, center[1] + offset.y], "home").grow(1))
	return plots

static func in_reserved_plot(plots: Array[Rect2i], cell: Array) -> bool:
	var point := Vector2i(cell[0], cell[1])
	for plot in plots:
		if plot.has_point(point): return true
	return false

const WORKSHOP_KINDS: Array[String] = ["sawmill", "bakery", "forge"]
## Counts entity additions and removals in this process, so derived caches (outside the game
## state) know when to rebuild. Not part of the state and never saved.
static var entity_serial: int = 0

static func cell_key(cell: Array) -> String:
	return "%d,%d" % [cell[0], cell[1]]

static func chunk_coord(x: int, y: int) -> Vector2i:
	return Vector2i(floori(float(x) / CHUNK_SIDE), floori(float(y) / CHUNK_SIDE))

static func walkable(state: Dictionary, cell: Array) -> bool:
	var world: Dictionary = state.world
	var bounds: Array = world.get("bounds", [0, 0, WIDTH, HEIGHT])
	if cell[0] < bounds[0] or cell[1] < bounds[1] or cell[0] >= bounds[2] or cell[1] >= bounds[3]: return false
	var key: String = "%d,%d" % [cell[0], cell[1]]
	return not world.blocked.has(key) and not world.get("building_walls", {}).has(key) and not world.get("fixture_cells", {}).has(key)

static func get_cell(state: Dictionary, cell: Array) -> Dictionary:
	return {"cell": cell, "walkable": walkable(state, cell), "chunk": [chunk_coord(cell[0], cell[1]).x, chunk_coord(cell[0], cell[1]).y]}

static func get_chunk(state: Dictionary, coord: Vector2i) -> Dictionary:
	var key := "%d,%d" % [coord.x, coord.y]
	return state.world.chunks.get(key, {"seed": state.seed, "version": 1, "entities": [], "mutations": {}})

static func apply_mutation(state: Dictionary, cell: Array, blocked: bool) -> void:
	if blocked:
		state.world.blocked[cell_key(cell)] = true
	else:
		state.world.blocked.erase(cell_key(cell))
	state.world.nav_revision += 1
	var coord := chunk_coord(cell[0], cell[1])
	var key := "%d,%d" % [coord.x, coord.y]
	if not state.world.chunks.has(key):
		state.world.chunks[key] = {"seed": state.seed, "version": 1, "entities": [], "mutations": {}}
	state.world.chunks[key].mutations[cell_key(cell)] = blocked

## Every kind of finished building with walls, a footprint and fittings. One list, so adding a new
## kind of building (the saloon, the town house) is one line here plus its fittings and art.
const BUILDING_KINDS: Array[String] = ["home", "warehouse", "sawmill", "bakery", "forge", "office", "market", "saloon", "town_hall"]

static func add_entity(sim: RefCounted, kind: String, name_value: String, cell: Array, settlement: int = 0, extra: Dictionary = {}) -> int:
	var id: int = sim.new_id()
	entity_serial += 1
	if settlement > 0 and (kind in ["sawmill", "bakery", "forge", "office"] or (kind == "home" and "lodge" in name_value.to_lower())):
		# Each town's lodge, office and workshops sit back from the road by their own amount, so a
		# street is not one straight row. Only backwards: the road in front always stays clear.
		cell = [cell[0], cell[1] - sim.random_int("town_layout:%d" % settlement, 0, 5)]
	sim.state.entities[str(id)] = {"id": id, "kind": kind, "name": name_value, "cell": cell.duplicate(), "settlement": settlement}
	if kind in BUILDING_KINDS or kind == "construction":
		sim.state.entities[str(id)].building_scale = 2
	if kind == "home": sim.state.entities[str(id)].layout_shape = "stepped_joined"
	# House types (see housing.gd) carry their own size, shape, beds and style.
	for field in extra: sim.state.entities[str(id)][field] = extra[field]
	var coord := chunk_coord(cell[0], cell[1])
	var key := "%d,%d" % [coord.x, coord.y]
	if not sim.state.world.chunks.has(key):
		sim.state.world.chunks[key] = {"seed": sim.state.seed, "version": 1, "entities": [], "mutations": {}}
	sim.state.world.chunks[key].entities.append(id)
	if kind in BUILDING_KINDS:
		install_building(sim.state, id)
	elif kind in ["construction", "market_stall"]:
		Fixtures.install(sim.state, sim.state.entities[str(id)])
		sim.state.world.nav_revision += 1
	return id

static func seed_world(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	s.world = {"blocked": {}, "chunks": {}, "nav_revision": 0, "building_walls": {}, "architecture_version": 3, "house_layout_version": 2, "building_scale_version": 2, "fixture_version": 2, "fixture_cells": {}, "meters_per_cell": METERS_PER_CELL}
	s.inventories = {}
	s.accounting = {"initial": {}, "created": {}, "consumed": {}}
	s.player = add_entity(sim, "player", Names.generate(sim), [62, 49])
	Inventory.create(s, s.player, 40, {"food": 4, "rifle": 1, "cartridge": 10, "lantern": 1})   # you begin with a rifle, slung, ten cartridges and a lantern
	s.warehouse = add_entity(sim, "warehouse", "Alder Hollow storehouse", [64, 46], 1)
	Inventory.create(s, s.warehouse, 3000, {"food": 160})
	s.home = add_entity(sim, "home", "Common lodge", [46, 42], 1)
	s.farm = add_entity(sim, "farm", "Communal vegetable beds", [81, 57], 1)
	Inventory.create(s, s.farm, 1000, {"food": 300})
	Crops.add_plot(s, "field", [75, 54, 12, 6], 1, s.farm, 0, 23000)
	populate_forest(sim, 1, 280, [64, 46], false)
	populate_dense_groves(sim, 1, 100, [64, 46], false)
	s.world.forest_version = 3
	var plots := reserved_home_plots([64, 46])
	for index in range(60):
		var cell: Array = [sim.random_int("rocks", 15, 110), sim.random_int("rocks", 10, 85)]
		if (abs(cell[0] - 64) > 28 or abs(cell[1] - 46) > 25) and not in_reserved_plot(plots, cell):
			apply_mutation(s, cell, true)
	s.accounting.initial = Inventory.totals(s)

static func ensure_chunk(state: Dictionary, coord: Vector2i) -> Dictionary:
	var key := "%d,%d" % [coord.x, coord.y]
	if not state.world.chunks.has(key):
		var seed_value: int = (str(state.seed) + ":" + key).sha256_text().substr(0, 8).hex_to_int()
		state.world.chunks[key] = {"seed": seed_value, "version": 1, "entities": [], "mutations": {}, "biome": "meadow" if seed_value % 3 == 0 else "woodland"}
	return state.world.chunks[key]

static func footprint(cell: Array, kind: String, scale_version: int = 2) -> Rect2i:
	var width: int = 17 if kind in ["home", "warehouse"] else 15
	var height: int = 14 if kind == "home" else (15 if kind == "warehouse" else 13)
	if scale_version < 2:
		width = 11 if kind == "home" else 13
		height = 9 if kind == "home" else (10 if kind == "warehouse" else 8)
	return Rect2i(cell[0] - width / 2, cell[1] - height + 1, width, height)

## The box around a set of [x, y, w, h] rectangles.
static func rects_bounds(rects: Array) -> Rect2i:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for r in rects:
		low = Vector2i(mini(low.x, int(r[0])), mini(low.y, int(r[1])))
		high = Vector2i(maxi(high.x, int(r[0]) + int(r[2])), maxi(high.y, int(r[1]) + int(r[3])))
	return Rect2i(low, high - low)

static func plot_rect(entity: Dictionary, kind: String) -> Rect2i:
	if kind == "home" and entity.has("house_rects"): return rects_bounds(entity.house_rects)
	if kind == "home" and entity.has("house_size"):
		var size: Array = entity.house_size
		return Rect2i(int(entity.cell[0]) - int(size[0]) / 2, int(entity.cell[1]) - int(size[1]) + 1, int(size[0]), int(size[1]))
	return footprint(entity.cell, kind, entity.get("building_scale", 1))

## The cut-out back corner of a notched house: cells with x >= .x (right notch) or x < .x (left
## notch) and y < .y are outside the house.
static func shape_notch(rect: Rect2i, shape: String) -> Vector2i:
	var depth: int = maxi(2, rect.size.y / 4)
	if shape == "notch_left": return Vector2i(rect.position.x + rect.size.x * 2 / 5, rect.position.y + depth)
	return Vector2i(rect.position.x + rect.size.x * 3 / 5, rect.position.y + depth)

## Interior partition walls: typed houses have one only if their type says so.
static func partitions_for(entity: Dictionary, rect: Rect2i) -> Array:
	if entity.has("house_walls"): return entity.house_walls   # turned houses carry their own inside walls
	if entity.has("house_size") and not entity.get("house_partition", false): return []
	return partition_cells(rect)

static func house_notch(rect: Rect2i) -> Vector2i:
	return rect.position + (Vector2i(10, 3) if rect.size.x >= 17 else Vector2i(7, 2))

static func partition_cells(rect: Rect2i) -> Array:
	var cells: Array = []
	var large := rect.size.x >= 15
	var partition_x: int = rect.position.x + (rect.size.x / 2 - 2 if large else 4)
	var passage_start: int = rect.end.y - (6 if large else 4)
	var passage_width := 3 if large else 2
	for y in range(rect.position.y + 1, rect.end.y - 1):
		if y < passage_start or y >= passage_start + passage_width:
			cells.append([partition_x, y])
	return cells

# The same footprint drives floors, collision and construction; legacy sites retain
# their original rectangular layout until completed.
static func building_contains(entity: Dictionary, cell: Array, kind: String = "") -> bool:
	var actual_kind: String = kind if not kind.is_empty() else entity.kind
	if actual_kind == "home" and entity.has("house_rects"):
		for r in entity.house_rects:
			if cell[0] >= r[0] and cell[0] < r[0] + r[2] and cell[1] >= r[1] and cell[1] < r[1] + r[3]: return true
		return false
	var rect := plot_rect(entity, actual_kind)
	var notch := house_notch(rect)
	if not rect.has_point(Vector2i(cell[0], cell[1])): return false
	var shape: String = entity.get("layout_shape", "")
	if actual_kind == "home" and shape in ["notch_right", "notch_left"]:
		var cut := shape_notch(rect, shape)
		if cell[1] < cut.y and ((shape == "notch_right" and cell[0] >= cut.x) or (shape == "notch_left" and cell[0] < cut.x)): return false
		return true
	return not (actual_kind == "home" and shape in ["stepped", "stepped_joined"] and cell[0] >= notch.x and cell[1] < notch.y)

static func exterior_wall(entity: Dictionary, cell: Array, kind: String) -> bool:
	if not building_contains(entity, cell, kind): return false
	if kind == "home" and entity.has("house_rects"):
		# Turned houses: a wall wherever any of the eight neighbours is outside (this also closes the
		# inside corners of L, T and courtyard shapes).
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (dx != 0 or dy != 0) and not building_contains(entity, [cell[0] + dx, cell[1] + dy], kind): return true
		return false
	if kind == "home" and entity.get("layout_shape", "") == "stepped_joined":
		var corner := house_notch(plot_rect(entity, kind)) + Vector2i.LEFT
		if Vector2i(cell[0], cell[1]) == corner: return true
	if kind == "home" and entity.get("layout_shape", "") in ["notch_right", "notch_left"]:
		# Close the inside corner of the notch so the wall line has no diagonal gap.
		var cut := shape_notch(plot_rect(entity, kind), entity.layout_shape)
		var corner := cut + Vector2i.LEFT if entity.layout_shape == "notch_right" else cut
		if Vector2i(cell[0], cell[1]) == corner: return true
	for offset in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
		if not building_contains(entity, [cell[0] + offset[0], cell[1] + offset[1]], kind): return true
	return false

static func construction_stages(entity: Dictionary, kind: String) -> Array[Dictionary]:
	var rect := plot_rect(entity, kind)
	var floor_tiles: Array = []
	var roof_tiles: Array = []
	var wall_tiles: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell: Array = [x, y]
			if not building_contains(entity, cell, kind): continue
			if exterior_wall(entity, cell, kind):
				if cell != entity.cell: wall_tiles.append(cell)
			else:
				floor_tiles.append(cell)
				roof_tiles.append(cell.duplicate())
	wall_tiles.append_array(partitions_for(entity, rect))
	var walls := {"id": "walls", "label": "Building walls", "tiles": wall_tiles}
	var floor_stage := {"id": "floor", "label": "Laying floor", "tiles": floor_tiles}
	var door := {"id": "door", "label": "Fitting doorway", "tiles": [entity.cell.duplicate()]}
	var roof := {"id": "roof", "label": "Installing roof tiles", "tiles": roof_tiles}
	if entity.get("walls_first", false):
		return [walls, floor_stage, door, roof]
	return [floor_stage, walls, door, roof]

static func add_constructed_wall(s: Dictionary, id: int, cell: Array) -> void:
	if not walkable(s, cell): return
	s.world.building_walls[cell_key(cell)] = id
	s.world.nav_revision += 1

static func building_rect(entity: Dictionary) -> Rect2i:
	var data: Array = entity.get("footprint", [])
	return Rect2i(data[0], data[1], data[2], data[3]) if data.size() == 4 else plot_rect(entity, entity.kind)

## The passages through a building's inside walls: [{"cells": [[x, y], ...], "axis": "h" | "v"}], where
## "v" means the gap runs up and down a vertical partition. Worked out from the walls themselves, so
## old saves need nothing stored.
static func interior_doorways(entity: Dictionary) -> Array:
	var walls: Array = entity.get("interior_walls", [])
	if walls.is_empty(): return []
	var wall_set: Dictionary = {}
	var xs: Dictionary = {}
	var ys: Dictionary = {}
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell in walls:
		wall_set["%d,%d" % [cell[0], cell[1]]] = true
		xs[int(cell[0])] = true
		ys[int(cell[1])] = true
		low = Vector2i(mini(low.x, int(cell[0])), mini(low.y, int(cell[1])))
		high = Vector2i(maxi(high.x, int(cell[0])), maxi(high.y, int(cell[1])))
	var result: Array = []
	if xs.size() == 1:
		var gap: Array = []
		for y in range(low.y, high.y + 1):
			if not wall_set.has("%d,%d" % [low.x, y]) and building_contains(entity, [low.x, y]): gap.append([low.x, y])
		if not gap.is_empty(): result.append({"cells": gap, "axis": "v"})
	elif ys.size() == 1:
		var gap: Array = []
		for x in range(low.x, high.x + 1):
			if not wall_set.has("%d,%d" % [x, low.y]) and building_contains(entity, [x, low.y]): gap.append([x, low.y])
		if not gap.is_empty(): result.append({"cells": gap, "axis": "h"})
	return result

static func inside_building(s: Dictionary, cell: Array) -> int:
	for entity in buildings(s):
		if building_contains(entity, cell):
			return entity.id
	return 0

## Entities with a footprint, and entities by kind, in entity-table order. Derived lists (never
## saved) rebuilt when entities are added, removed or converted (entity_serial), so the dozens
## of buildings can be found without walking thousands of trees.
static var _lists_cache: Array = []
static func _entity_lists(s: Dictionary) -> Dictionary:
	var cache: Dictionary = DerivedCache.slot(_lists_cache, s.entities)
	var signature := [s.entities.size(), entity_serial]
	if cache.get("signature") == signature: return cache.lists
	var lists := {"__footprint": []}
	for entity in s.entities.values():
		var kind: String = entity.get("kind", "")
		if not lists.has(kind): lists[kind] = []
		lists[kind].append(entity)
		if entity.has("footprint"): lists["__footprint"].append(entity)
	cache.lists = lists
	cache.signature = signature
	return lists

static func buildings(s: Dictionary) -> Array:
	return _entity_lists(s)["__footprint"]

static func of_kind(s: Dictionary, kind: String) -> Array:
	return _entity_lists(s).get(kind, [])

static func install_building(s: Dictionary, id: int) -> void:
	var entity: Dictionary = s.entities[str(id)]
	var rect := plot_rect(entity, entity.kind)
	entity.footprint = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	entity_serial += 1   # a new building (or a site turned into one): derived lists rebuild
	entity.door = entity.cell.duplicate()
	if not s.world.has("building_walls"):
		s.world.building_walls = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if exterior_wall(entity, [x, y], entity.kind):
				if [x, y] != entity.door:
					s.world.building_walls[cell_key([x, y])] = id
	entity.interior_walls = partitions_for(entity, rect)
	for cell in entity.interior_walls:
		s.world.building_walls[cell_key(cell)] = id
	Fixtures.install(s, entity)
	s.world.nav_revision += 1
	for resource in s.entities.values():
		if resource.get("kind", "") in ["tree", "farm"] and rect.has_point(Vector2i(resource.cell[0], resource.cell[1])):
			for offset in range(1, 200):
				var candidate: Array = [entity.cell[0] + (offset % 15) - 7, entity.cell[1] + 2 + offset / 15]
				var occupied: bool = false
				for other in s.entities.values():
					if other.get("cell", []) == candidate:
						occupied = true
				if walkable(s, candidate) and inside_building(s, candidate) == 0 and not occupied:
					move_record(s, resource, candidate)
					break
	# Completion must never enclose a worker/player in a newly occupied wall cell.
	for actor in s.entities.values():
		if actor.get("kind", "") in ["resident", "player", "caravan"] and not walkable(s, actor.cell):
			actor.cell = entity.door.duplicate()

static func upgrade_layouts(s: Dictionary) -> void:
	if not s.has("world"):
		return
	s.world.meters_per_cell = METERS_PER_CELL
	if s.world.has("building_walls"):
		return
	s.world.building_walls = {}
	s.world.fixture_cells = {}
	for entity in s.entities.values():
		if entity.get("kind", "") in BUILDING_KINDS:
			# Earlier icons sat too close together for full-sized rooms.
			if s.has("settlements") and s.settlements.has(str(entity.settlement)):
				var store: Array = s.entities[str(s.settlements[str(entity.settlement)].warehouse)].cell
				if entity.kind == "sawmill":
					move_record(s, entity, [store[0] + 12, store[1] - 4])
				elif entity.kind == "home" and entity.id == s.settlements[str(entity.settlement)].home:
					move_record(s, entity, [store[0] - 10, store[1] - 4])
			for attempt in range(100):
				var rect := plot_rect(entity, entity.kind).grow(1)
				var overlaps: bool = false
				for other in s.entities.values():
					if other.id != entity.id and other.has("footprint") and rect.intersects(building_rect(other)):
						overlaps = true
				if not overlaps:
					break
				move_record(s, entity, [entity.cell[0], entity.cell[1] + 9])
			install_building(s, entity.id)

## Removes an entity whose inventory has already been emptied (its goods moved elsewhere first,
## so conservation holds): its chunk entry, fixture cells and inventory record go with it.
static func remove_entity(s: Dictionary, id: int) -> void:
	entity_serial += 1
	var entity: Dictionary = s.entities.get(str(id), {})
	if entity.is_empty(): return
	var coord := chunk_coord(entity.cell[0], entity.cell[1])
	var key := "%d,%d" % [coord.x, coord.y]
	if s.world.chunks.has(key): s.world.chunks[key].entities.erase(id)
	for cell_key_value in s.world.get("fixture_cells", {}).keys():
		if s.world.fixture_cells[cell_key_value] == id: s.world.fixture_cells.erase(cell_key_value)
	s.inventories.erase(str(id))
	s.entities.erase(str(id))
	s.world.nav_revision += 1

static func move_record(s: Dictionary, entity: Dictionary, destination: Array) -> void:
	if entity.get("kind", "") not in ["resident", "player", "raider"]: entity_serial += 1   # derived caches by cell
	var old := chunk_coord(entity.cell[0], entity.cell[1])
	var new_coord := chunk_coord(destination[0], destination[1])
	if old != new_coord:
		var old_key := "%d,%d" % [old.x, old.y]
		if s.world.chunks.has(old_key):
			s.world.chunks[old_key].entities.erase(entity.id)
		ensure_chunk(s, new_coord).entities.append(entity.id)
	entity.cell = destination.duplicate()

static func populate_forest(sim: RefCounted, town: int, desired: int, center: Array, account_growth: bool = true) -> void:
	var s: Dictionary = sim.state
	var occupied: Dictionary = {}
	var count: int = 0
	var plots := reserved_home_plots(center)
	for entity in s.entities.values():
		if entity.get("kind", "") == "tree":
			occupied[cell_key(entity.cell)] = true
			if entity.settlement == town:
				count += 1
	for attempt in range(15000):
		if count >= desired:
			break
		var cell: Array = [center[0] + sim.random_int("forest:%d" % town, -39, 39), center[1] + sim.random_int("forest:%d" % town, -33, 33)]
		if not walkable(s, cell) or in_reserved_plot(plots, cell) or inside_building(s, cell) != 0:
			continue
		# Keep the village expansion plots and road clear while filling surrounding woods.
		if absi(cell[0] - center[0]) < 27 and cell[1] > center[1] - 18 and cell[1] < center[1] + 25:
			continue
		if absi(cell[1] - 48) < 3:
			continue
		var close: bool = false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if occupied.has(cell_key([cell[0] + dx, cell[1] + dy])):
					close = true
		if close:
			continue
		var id := add_entity(sim, "tree", "Alder %03d" % (count + 1) if town == 1 else ("Reedbank willow %03d" % (count + 1) if town == 2 else "Scrub oak %03d" % (count + 1)), cell, town)
		if town == 3:
			# Dustvale's dry country: mostly dead trunks, some still in autumn leaf.
			if count % 3 == 0: s.entities[str(id)].autumn = true
			else: s.entities[str(id)].dead = true
		Inventory.create(s, id, 80, {} if account_growth else {"log": 60})
		if account_growth:
			Inventory.produce(s, id, "log", 60)
		occupied[cell_key(cell)] = true
		count += 1

static func populate_dense_groves(sim: RefCounted, town: int, desired: int, center: Array, account_growth: bool = true) -> void:
	var s: Dictionary = sim.state
	var occupied: Dictionary = {}
	var protected_plots := reserved_home_plots(center)
	for entity in s.entities.values():
		if entity.has("cell"): occupied[cell_key(entity.cell)] = true
		if entity.has("footprint"): protected_plots.append(building_rect(entity).grow(1))
		elif entity.get("kind", "") == "construction":
			var site: Dictionary = s.get("construction", {}).get(str(entity.id), {})
			var def: Dictionary = s.get("building_defs", {}).get(site.get("definition", ""), {})
			protected_plots.append(plot_rect(entity, def.get("kind", "home")).grow(1))
	# Small stands create dense canopy beside larger clearings, away from streets
	# and expansion plots. Trees remain real, harvestable inventory owners.
	var centers: Array = [[-34, -25], [34, -25], [-34, 29], [34, 29]]
	var added: int = 0
	for attempt in range(6000):
		if added >= desired: break
		var grove: Array = centers[attempt % centers.size()]
		var cell: Array = [center[0] + grove[0] + sim.random_int("grove:%d" % town, -7, 7), center[1] + grove[1] + sim.random_int("grove:%d" % town, -7, 7)]
		var key := cell_key(cell)
		if occupied.has(key) or not walkable(s, cell): continue
		var protected: bool = false
		for plot in protected_plots:
			if plot.has_point(Vector2i(cell[0], cell[1])): protected = true; break
		if protected: continue
		if absi(cell[0] - center[0]) < 27 and cell[1] > center[1] - 18 and cell[1] < center[1] + 25: continue
		if absi(cell[1] - 48) < 3: continue
		var id := add_entity(sim, "tree", "Woodland tree", cell, town)
		Inventory.create(s, id, 80, {} if account_growth else {"log": 60})
		if account_growth: Inventory.produce(s, id, "log", 60)
		occupied[key] = true
		added += 1

## Real woodland around the towns. Trees keep their distance from every house, door, workshop,
## square, field, plot and road (any tree that grew too close is moved out into the forest), and
## new trees fill coherent stands shaped by smooth noise, thicker the further from town they are.
## Deterministic: candidate cells are scored with seeded phases and taken best-first.
const WOODLAND_TARGETS := {1: 640, 2: 430}
## Trees across the open country, on the dark-green forest floor between the towns.
const WILD_TREES := 5200
static func lay_out_woodlands(sim: RefCounted, grow_new: bool = true) -> void:
	var s: Dictionary = sim.state
	if not s.get("settlements", {}).has("2"): return
	var keep_out := _woodland_keep_out(s)
	var occupied: Dictionary = {}
	var trees: Array = []
	for entity in s.entities.values():
		if entity.has("cell"): occupied[cell_key(entity.cell)] = true
		if entity.get("kind", "") == "tree": trees.append(entity)
	trees.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for town in [1, 2]:
		var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
		var candidates := _woodland_candidates(sim, s, town, store, keep_out, occupied)
		var next := 0
		# Move trees that stand too close to buildings, doors and roads out into the woods.
		for tree in trees:
			if tree.settlement != town or not keep_out.has(cell_key(tree.cell)): continue
			while next < candidates.size() and _crowded(occupied, candidates[next]): next += 1
			if next >= candidates.size(): break
			occupied.erase(cell_key(tree.cell))
			move_record(s, tree, candidates[next])
			occupied[cell_key(candidates[next])] = true
			next += 1
		var count := 0
		for tree in trees:
			if tree.settlement == town: count += 1
		while grow_new and count < int(WOODLAND_TARGETS[town]) and next < candidates.size():
			var cell: Array = candidates[next]
			next += 1
			if _crowded(occupied, cell): continue
			var id := add_entity(sim, "tree", "Alder %03d" % (count + 1) if town == 1 else "Reedbank willow %03d" % (count + 1), cell, town)
			Inventory.create(s, id, 80)
			Inventory.produce(s, id, "log", 60)
			occupied[cell_key(cell)] = true
			count += 1
	# Dustvale's few dry-country trees also keep clear of its buildings.
	if s.settlements.has("3"):
		var store3: Array = s.entities[str(s.settlements["3"].warehouse)].cell
		var spots := _woodland_candidates(sim, s, 3, store3, keep_out, occupied)
		var index := 0
		for tree in trees:
			if tree.settlement != 3 or not keep_out.has(cell_key(tree.cell)): continue
			while index < spots.size() and _crowded(occupied, spots[index]): index += 1
			if index >= spots.size(): break
			occupied.erase(cell_key(tree.cell))
			move_record(s, tree, spots[index])
			occupied[cell_key(spots[index])] = true
			index += 1
	if grow_new: _plant_wild_forests(sim, keep_out, occupied)
	s.world.forest_version = 4

## Fills the forest floor the ground shader draws (see terrain.gd) with trees, deepest woods first.
static func _plant_wild_forests(sim: RefCounted, keep_out: Dictionary, occupied: Dictionary) -> void:
	var s: Dictionary = sim.state
	var limits: Array = s.world.get("bounds", [0, 0, WIDTH, HEIGHT])
	var seed_value: int = int(s.seed) % 9973
	var centres: Dictionary = Terrain.town_centres(s)
	var towns: Array = []
	for key in s.settlements:
		towns.append([int(key), s.entities[str(s.settlements[key].warehouse)].cell])
	var spots: Array = []
	for y in range(int(limits[1]) + 3, int(limits[3]) - 3, 3):
		for x in range(int(limits[0]) + 3, int(limits[2]) - 3, 3):
			var cx: int = x + sim.random_int("wild", -1, 1)
			var cy: int = y + sim.random_int("wild", -1, 1)
			var key := "%d,%d" % [cx, cy]
			if keep_out.has(key) or occupied.has(key): continue
			var wood: float = Terrain.woodland(Vector2(cx, cy), seed_value, centres)
			if wood < 0.6: continue
			spots.append([wood + float(sim.random_int("wild", 0, 99)) * 0.001, cx, cy])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and (a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]))))
	var planted := 0
	for entry in spots:
		if planted >= WILD_TREES: break
		var cell: Array = [entry[1], entry[2]]
		if _crowded(occupied, cell) or not walkable(s, cell): continue
		# The nearest town's woodsmen count it as theirs.
		var town: int = 1
		var best: float = INF
		for item in towns:
			var d: float = Vector2(cell[0] - item[1][0], cell[1] - item[1][1]).length()
			if d < best:
				best = d
				town = item[0]
		var id := add_entity(sim, "tree", "Woodland tree", cell, town)
		if town == 3:
			if planted % 3 == 0: s.entities[str(id)].autumn = true
			else: s.entities[str(id)].dead = true
		Inventory.create(s, id, 80)
		Inventory.produce(s, id, "log", 60)
		occupied[cell_key(cell)] = true
		planted += 1

static func _crowded(occupied: Dictionary, cell: Array) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if occupied.has(cell_key([cell[0] + dx, cell[1] + dy])): return true
	return false

## The roads, as coarse rectangles (with a verge) that nothing may block. The roads themselves are
## data (`world.roads`, made by town_layout.gd); older saves get the old fixed layout.
static func road_corridors(s: Dictionary) -> Array[Rect2i]:
	return _layout().corridors(s)

## Loaded on demand: the layout code itself uses this file.
static func _layout() -> GDScript:
	return load("res://sim/world/town_layout.gd")

## Every cell where no tree may stand, as a set of cell keys.
static func _woodland_keep_out(s: Dictionary) -> Dictionary:
	var areas: Array[Rect2i] = []
	for entity in s.entities.values():
		if entity.has("footprint"):
			areas.append(building_rect(entity).grow(5))
			var door: Array = entity.get("door", entity.cell)
			# the yard in front of the door, whichever way it faces
			var side: int = int(entity.get("door_side", 2))
			var yard := Rect2i(door[0] - 3, door[1] - 1, 7, 10)
			if side == 0: yard = Rect2i(door[0] - 3, door[1] - 8, 7, 10)
			elif side == 1: yard = Rect2i(door[0] - 1, door[1] - 3, 10, 7)
			elif side == 3: yard = Rect2i(door[0] - 8, door[1] - 3, 10, 7)
			areas.append(yard)
		elif entity.get("kind", "") in ["market_stall", "chest", "ore", "farm"] + BUILDING_KINDS:
			areas.append(Rect2i(entity.cell[0] - 4, entity.cell[1] - 4, 9, 9))
		if entity.has("rock_rect"):
			var r: Array = entity.rock_rect
			areas.append(Rect2i(r[0], r[1], r[2], r[3]).grow(3))
	for site_key in s.get("construction", {}):
		var site_entity: Dictionary = s.entities.get(str(site_key), {})
		var def: Dictionary = s.get("building_defs", {}).get(s.construction[site_key].get("definition", ""), {})
		if not site_entity.is_empty(): areas.append(plot_rect(site_entity, def.get("kind", "home")).grow(5))
	for plot in s.get("crops", {}).values():
		var rect: Array = plot.rect
		areas.append(Rect2i(rect[0], rect[1], rect[2], rect[3]).grow(3))
	for town in s.get("settlements", {}).values():
		var store: Array = s.entities[str(town.warehouse)].cell
		for plot in reserved_home_plots(store): areas.append(plot.grow(4))
		areas.append(Rect2i(store[0] - 16, store[1] - 6, 33, 24))   # the market square and its stalls
	var blocked: Dictionary = {}
	for area in areas:
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				blocked["%d,%d" % [x, y]] = true
	# The roads and their verges.
	blocked.merge(_layout().road_cells(s))
	return blocked

## Free cells around a town, best woodland spots first.
static func _woodland_candidates(sim: RefCounted, s: Dictionary, town: int, store: Array, keep_out: Dictionary, occupied: Dictionary) -> Array:
	var phases: Array[float] = []
	for index in range(5): phases.append(float(sim.random_int("woods:%d" % town, 0, 6283)) / 1000.0)
	var scored: Array = []
	var span := Vector2i(74, 54) if town != 3 else Vector2i(40, 22)
	for y in range(store[1] - span.y, store[1] + span.y + 1):
		for x in range(store[0] - span.x, store[0] + span.x + 1):
			var key := "%d,%d" % [x, y]
			if keep_out.has(key) or occupied.has(key) or not walkable(s, [x, y]): continue   # buildings are inside keep_out already
			var fx := float(x)
			var fy := float(y)
			var noise: float = sin(fx * 0.105 + phases[0]) + sin(fy * 0.13 + phases[1]) + 0.8 * sin((fx + fy) * 0.071 + phases[2]) + 0.6 * sin((fx - fy) * 0.19 + phases[3]) + 0.35 * sin(fx * 0.37 + fy * 0.29 + phases[4])
			var distance: float = Vector2((fx - store[0]) / 34.0, (fy - store[1]) / 27.0).length()
			var score: float = noise * 0.5 + smoothstep(0.9, 1.7, distance) * 1.4
			if score < 0.35: continue
			scored.append([score, x, y])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and (a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]))))
	var cells: Array = []
	for entry in scored: cells.append([entry[1], entry[2]])
	return cells

static func upgrade_forests(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("world") or s.world.get("forest_version", 0) >= 4:
		return
	if s.world.get("forest_version", 0) < 3:
		if s.world.get("forest_version", 0) < 2:
			populate_forest(sim, 1, 280, [64, 46])
			if s.get("settlements", {}).has("2"): populate_forest(sim, 2, 140, [180, 46])
		populate_dense_groves(sim, 1, 100, [64, 46])
		if s.get("settlements", {}).has("2"): populate_dense_groves(sim, 2, 60, [180, 46])
		s.world.forest_version = 3
	# Version 4 (full game only): trees kept away from buildings. Old saves keep their timber
	# (moved, not created); new games are also filled out into real woods.
	lay_out_woodlands(sim, false)

static func upgrade_architecture(s: Dictionary) -> void:
	if not s.has("world") or s.world.get("architecture_version", 0) >= 3:
		return
	# Reflow legacy villages once. IDs, inventory owners and work records survive.
	var slots: Dictionary = {}
	var buildings: Array = []
	for entity in s.entities.values():
		if entity.kind not in ["home", "warehouse", "sawmill", "market", "construction"]: continue
		var town: Dictionary = s.get("settlements", {}).get(str(entity.settlement), {})
		var store_id: int = town.get("warehouse", s.get("warehouse", 0))
		if not s.entities.has(str(store_id)): continue
		var store: Array = s.entities[str(store_id)].cell
		var cell: Array = entity.cell.duplicate()
		if entity.kind == "sawmill": cell = [store[0]+17, store[1]-4]
		elif entity.kind in ["home", "construction"]:
			if entity.id == town.get("home", s.get("home", 0)):
				cell = [store[0]-15,store[1]-4]
			else:
				var slot: int = slots.get(str(entity.settlement),0)
				var offsets: Array = [[-15,12],[0,22],[17,22],[-15,25]]
				var offset: Array = offsets[slot%4]
				cell = [store[0]+offset[0],store[1]+offset[1]+(slot/4)*15]
				slots[str(entity.settlement)] = slot+1
		move_record(s,entity,cell)
		if entity.kind != "construction": buildings.append(entity.id)
	s.world.building_walls = {}
	s.world.fixture_cells = {}
	for id in buildings: install_building(s,id)
	s.player_path = []
	s.world.architecture_version = 3

static func upgrade_house_layouts(s: Dictionary) -> void:
	if not s.has("world") or s.world.get("house_layout_version", 0) >= 2: return
	# In-progress sites keep their original recorded stages and finish unchanged.
	for entity in s.entities.values():
		if entity.get("kind", "") != "home" or entity.has("house_type"): continue
		for key in s.world.building_walls.keys():
			if s.world.building_walls[key] == entity.id: s.world.building_walls.erase(key)
		entity.layout_shape = "stepped_joined"
		install_building(s, entity.id)
	s.world.house_layout_version = 2
	s.player_path = []

static func upgrade_building_scale(s: Dictionary) -> void:
	if not s.has("world") or s.world.get("building_scale_version", 0) >= 2: return
	var reserved: Dictionary = {}
	for entity in s.entities.values():
		if entity.has("footprint"):
			reserved[entity.id] = building_rect(entity)
		elif entity.kind == "construction":
			var site: Dictionary = s.get("construction", {}).get(str(entity.id), {})
			var definition: Dictionary = s.get("building_defs", {}).get(site.get("definition", ""), {})
			reserved[entity.id] = plot_rect(entity, definition.get("kind", "home"))
	# Grow completed buildings in place, or shift their doorway a few metres
	# east or west. Crowded plots and ongoing construction retain their layout.
	for entity in s.entities.values():
		if not entity.has("footprint") or entity.get("building_scale", 1) >= 2: continue
		for dx in [0, -3, 3, -6, 6]:
			var entrance: Array = [entity.cell[0] + dx, entity.cell[1]]
			var expanded := footprint(entrance, entity.kind)
			if not _fits_expansion(s, expanded, reserved, entity.id): continue
			for key in s.world.building_walls.keys():
				if s.world.building_walls[key] == entity.id: s.world.building_walls.erase(key)
			move_record(s, entity, entrance)
			entity.building_scale = 2
			reserved[entity.id] = expanded
			install_building(s, entity.id)
			break
	s.world.building_scale_version = 2
	s.player_path = []

static func _fits_expansion(s: Dictionary, rect: Rect2i, reserved: Dictionary, id: int) -> bool:
	var limits: Array = s.world.get("bounds", [0, 0, WIDTH, HEIGHT])
	var extent := Rect2i(limits[0], limits[1], limits[2] - limits[0], limits[3] - limits[1])
	if not extent.encloses(rect): return false
	for other in reserved:
		if other != id and rect.grow(1).intersects(reserved[other]): return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if s.world.blocked.has(cell_key([x, y])): return false
	return true
