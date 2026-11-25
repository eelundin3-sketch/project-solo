extends RefCounted
## A derived walkability grid for pathfinding, built from the world's blocked cells, building
## walls and fixtures (exactly what World.walkable reads). It lives outside the game state: it is
## rebuilt whenever its source changes and never saved, so it cannot change an outcome.
## The search itself is Godot's built-in AStarGrid2D (C++), four-neighbour with Manhattan costs.
const World = preload("res://sim/world/world_db.gd")
const Probe = preload("res://sim/diagnostics/perf_probe.gd")
const DerivedCache = preload("res://sim/core/derived_cache.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
static var _grids: Array = []
static var _travel: Array = []
static var _street: Array = []
## Weights for the travel grid: a road's centre costs 1, the rest of its corridor 1.5, open
## country 3, so long walks keep to the roads unless leaving them saves a great deal.
const OFF_ROAD := 3.0
const ROAD_EDGE := 1.5
## Weights for the street grid (everyday walks): milder, so a short way across a yard still wins.
const STREET_OFF_ROAD := 1.6
const STREET_EDGE := 1.2

## What the grid was built from. Any write that changes walkability either bumps nav_revision or
## changes one of the three tables' sizes (or replaces a table), so this catches every change.
static func _signature(state: Dictionary) -> Array:
	var w: Dictionary = state.world
	return [w.get("bounds", [0, 0, World.WIDTH, World.HEIGHT]), int(w.get("nav_revision", 0)),
		w.blocked.size(), w.get("building_walls", {}).size(), w.get("fixture_cells", {}).size()]

static func _parse(key: String) -> Vector2i:
	var comma := key.find(",")
	return Vector2i(int(key.substr(0, comma)), int(key.substr(comma + 1)))

## The grid for this state, rebuilt only when the world's walkability has changed.
static func grid(state: Dictionary) -> AStarGrid2D:
	var sig := _signature(state)
	var cache: Dictionary = DerivedCache.slot(_grids, state.world)
	if cache.get("signature") == sig:
		return cache.astar
	var started := Time.get_ticks_usec()
	var bounds: Array = sig[0]
	if not cache.has("astar"): cache.astar = AStarGrid2D.new()
	var astar: AStarGrid2D = cache.astar
	var region := Rect2i(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
	astar.region = region
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.jumping_enabled = false
	astar.update()
	astar.fill_solid_region(region, false)   # update() may keep old solids when nothing else changed
	for table in [state.world.blocked, state.world.get("building_walls", {}), state.world.get("fixture_cells", {})]:
		for key in table:
			var cell := _parse(key)
			if region.has_point(cell): astar.set_point_solid(cell, true)
	cache.signature = sig
	Probe.add("nav_grid_rebuild", Time.get_ticks_usec() - started)
	Probe.count("nav_grid_rebuilds")
	return astar

## The same walkability with road preference, for long trips. Rebuilt when walkability or the
## roads change; like grid(), derived from the state and never saved.
static func travel_grid(state: Dictionary) -> AStarGrid2D:
	return _weighted(state, _travel, OFF_ROAD, ROAD_EDGE, "travel_grid_rebuild")

## The same walkability with a milder road preference, for everyday walks about town: people join
## the nearest road and follow it, cutting across only when that saves a fair bit.
static func street_grid(state: Dictionary) -> AStarGrid2D:
	return _weighted(state, _street, STREET_OFF_ROAD, STREET_EDGE, "street_grid_rebuild")

static func _weighted(state: Dictionary, holder: Array, off_road: float, edge: float, probe: String) -> AStarGrid2D:
	var sig := _signature(state)
	sig.append(TownLayout.road_signature(state))
	var cache: Dictionary = DerivedCache.slot(holder, state.world)
	if cache.get("signature") == sig: return cache.astar
	var started := Time.get_ticks_usec()
	var base := grid(state)
	if not cache.has("astar"): cache.astar = AStarGrid2D.new()
	var astar: AStarGrid2D = cache.astar
	astar.region = base.region
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.jumping_enabled = false
	astar.update()
	var region: Rect2i = base.region
	astar.fill_solid_region(region, false)
	astar.fill_weight_scale_region(region, off_road)
	var roads := TownLayout.road_map(state)
	for key in roads.kind:
		var cell := _parse(key)
		if region.has_point(cell): astar.set_point_weight_scale(cell, 1.0 if roads.centre.has(key) else edge)
	for table in [state.world.blocked, state.world.get("building_walls", {}), state.world.get("fixture_cells", {})]:
		for key in table:
			var cell := _parse(key)
			if region.has_point(cell): astar.set_point_solid(cell, true)
	cache.signature = sig
	Probe.add(probe, Time.get_ticks_usec() - started)
	return astar

## Forget the grids (tests that swap worlds in place can call this; normal play never needs to).
static func reset() -> void:
	_grids.clear()
	_travel.clear()
	_street.clear()
