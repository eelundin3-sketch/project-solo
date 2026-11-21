extends RefCounted
## The shape of the roads. Each town gets its own layout (crossroads, a winding street, a ring road
## or scattered hamlets), drawn from a seeded stream so no two towns look alike. The civic row along
## the main street stays where it is; the lanes beyond it, the roads between the towns and the lots
## the houses stand on all come from here. Roads are simulation data (`world.roads`), and the view
## and the keep-out zones read the same polylines.
##
## world.roads = {"version", "segments": [{"id", "kind", "town", "radius", "reach", "points"}]}
##   kind   "main" (the street through the civic row), "link" (between towns), "lane", "spur", "ring"
##   radius how wide the sand track is drawn, in pixels
##   reach  how many cells either side of the line stay clear of buildings and trees
## world.layout[town] = {"archetype", "centre", "street_y", "extent": [x_lo, x_hi]}
const World = preload("res://sim/world/world_db.gd")
const RoadPlanner = preload("res://sim/world/road_planner.gd")
const ARCHETYPES: Array[String] = ["crossroads", "winding", "ring", "hamlets"]
const VERSION := 2   # 2: link roads planned around obstacles, with junctions
const LOT_SPACING := 5.0
const MAX_LOT_DISTANCE := 80.0   # how far from a town's square its lots reach (out along the roads leaving town)

# --- small helpers ----------------------------------------------------------------------------

static func _rf(sim: RefCounted, stream: String, lo: float, hi: float) -> float:
	return lo + (hi - lo) * float(sim.random_int(stream, 0, 10000)) / 10000.0

static func _pt(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]

static func _vec(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))

## A wandering line from `a` to `b`: it leaves each end straight and sways between them.
static func _curve(a: Vector2, b: Vector2, amplitude: float, waves: float, phase: float, step: float = 2.0, ends: String = "both") -> Array:
	var points: Array = []
	var length: float = a.distance_to(b)
	var count: int = maxi(2, ceili(length / step))
	var along: Vector2 = (b - a).normalized()
	var side := Vector2(-along.y, along.x)
	for index in range(count + 1):
		var t: float = float(index) / float(count)
		var envelope: float = 1.0
		if ends == "both": envelope = pow(sin(PI * t), 0.6)
		elif ends == "start": envelope = smoothstep(0.0, 0.25, t)
		var sway: float = amplitude * sin(t * waves * PI + phase) * envelope
		points.append(_pt(a.lerp(b, t) + side * sway))
	return points

static func _segment(segments: Array, kind: String, town: int, points: Array, radius: float, reach: float) -> int:
	var id: int = segments.size() + 1
	segments.append({"id": id, "kind": kind, "town": town, "radius": radius, "reach": reach, "points": points})
	return id

## Civic buildings stand in a row along each town's main street; the street runs past all of them.
static func _street_extent(s: Dictionary, town: int) -> Array:
	var lo: int = 100000
	var hi: int = -100000
	for entity in s.entities.values():
		if entity.get("settlement", 0) != town or not entity.has("footprint"): continue
		if entity.kind not in ["warehouse", "office", "market", "sawmill", "bakery", "forge", "saloon", "town_hall"] and not (entity.kind == "home" and "lodge" in str(entity.name).to_lower()): continue
		var rect := World.building_rect(entity)
		lo = mini(lo, rect.position.x)
		hi = maxi(hi, rect.end.x)
	if lo > hi:
		var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
		return [store[0] - 30, store[0] + 30]
	return [lo - 6, hi + 6]

# --- generation -------------------------------------------------------------------------------

static func generate(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("settlements"): return
	var towns: Array = s.settlements.keys()
	towns.sort()
	var pool: Array = ARCHETYPES.duplicate()
	for index in range(pool.size() - 1, 0, -1):
		var swap: int = sim.random_int("town_layout:pick", 0, index)
		var held: String = pool[index]
		pool[index] = pool[swap]
		pool[swap] = held
	var segments: Array = []
	var layout: Dictionary = {}
	for index in range(towns.size()):
		var town: int = int(towns[index])
		var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
		var extent := _street_extent(s, town)
		var street_y: int = int(store[1]) + 2
		layout[str(town)] = {"archetype": pool[index % pool.size()], "centre": [store[0], store[1]], "street_y": street_y, "extent": extent}
		_segment(segments, "main", town, _curve(Vector2(extent[0], street_y), Vector2(extent[1], street_y), 0.5, 4.0, 0.7, 4.0), 17.0, 4.0)
		_lanes(sim, segments, town, str(layout[str(town)].archetype), store, extent, street_y)
	# Roads between the towns, planned around what is in the way (road_planner.gd).
	var junctions: Array = RoadPlanner.plan(sim, segments, layout)
	s.world.roads = {"version": VERSION, "segments": segments, "junctions": junctions}
	s.world.layout = layout
	RoadPlanner.place_signposts(sim, junctions)

## The lanes that give a town its character, all leaving the main street.
static func _lanes(sim: RefCounted, segments: Array, town: int, archetype: String, store: Array, extent: Array, street_y: int) -> void:
	var stream := "town_layout:%d" % town
	var cx: float = float(store[0])
	var y0: float = float(street_y)
	match archetype:
		"crossroads":
			# A road straight down through the square, crossed by a lane further south.
			var x: float = cx + _rf(sim, stream, -4.0, 4.0)
			var length: float = _rf(sim, stream, 46.0, 56.0)
			_segment(segments, "lane", town, _curve(Vector2(x, y0), Vector2(x + _rf(sim, stream, -5.0, 5.0), y0 + length), _rf(sim, stream, 1.5, 3.0), _rf(sim, stream, 1.5, 3.0), _rf(sim, stream, 0.0, 6.0), 2.0, "start"), 13.0, 3.0)
			var cross_y: float = y0 + _rf(sim, stream, 30.0, 36.0)
			var west: float = _rf(sim, stream, 36.0, 46.0)
			var east: float = _rf(sim, stream, 36.0, 46.0)
			_segment(segments, "lane", town, _curve(Vector2(x - west, cross_y + _rf(sim, stream, -3.0, 3.0)), Vector2(x + east, cross_y + _rf(sim, stream, -3.0, 3.0)), _rf(sim, stream, 1.5, 3.5), _rf(sim, stream, 1.5, 3.0), _rf(sim, stream, 0.0, 6.0), 2.0, "both"), 13.0, 3.0)
		"winding":
			# Two lanes that leave the street at its ends and meander south, one with a side branch.
			var west_x: float = float(extent[0]) + _rf(sim, stream, 8.0, 18.0)
			var east_x: float = float(extent[1]) - _rf(sim, stream, 8.0, 18.0)
			var west_end := Vector2(west_x + _rf(sim, stream, -16.0, -4.0), y0 + _rf(sim, stream, 48.0, 60.0))
			var east_end := Vector2(east_x + _rf(sim, stream, 4.0, 16.0), y0 + _rf(sim, stream, 44.0, 58.0))
			var west_lane := _curve(Vector2(west_x, y0), west_end, _rf(sim, stream, 6.0, 9.0), _rf(sim, stream, 2.4, 3.6), _rf(sim, stream, 0.0, 6.0), 2.0, "start")
			_segment(segments, "lane", town, west_lane, 13.0, 3.0)
			_segment(segments, "lane", town, _curve(Vector2(east_x, y0), east_end, _rf(sim, stream, 5.0, 8.0), _rf(sim, stream, 2.2, 3.4), _rf(sim, stream, 0.0, 6.0), 2.0, "start"), 13.0, 3.0)
			var from: Vector2 = _vec(west_lane[int(west_lane.size() * 0.45)])
			_segment(segments, "lane", town, _curve(from, from + Vector2(_rf(sim, stream, 18.0, 28.0), _rf(sim, stream, 8.0, 16.0)), _rf(sim, stream, 2.0, 4.0), 1.5, _rf(sim, stream, 0.0, 6.0), 2.0, "start"), 11.0, 2.0)
		"ring":
			# A loop road below the square, joined to the street by a short stem.
			var centre_x: float = cx + _rf(sim, stream, -6.0, 6.0)
			var rx: float = _rf(sim, stream, 26.0, 32.0)
			var ry: float = _rf(sim, stream, 14.0, 18.0)
			var stem: float = _rf(sim, stream, 18.0, 22.0)
			var centre_y: float = y0 + stem + ry
			_segment(segments, "lane", town, _curve(Vector2(centre_x, y0), Vector2(centre_x, y0 + stem), 1.2, 1.0, 0.5, 2.0, "start"), 13.0, 3.0)
			var phase: float = _rf(sim, stream, 0.0, 6.0)
			var loop: Array = []
			var steps: int = 56
			for index in range(steps + 1):
				var angle: float = -PI / 2.0 + TAU * float(index) / float(steps)
				var wobble: float = 1.0 + 0.09 * sin(3.0 * angle + phase)
				loop.append(_pt(Vector2(centre_x + cos(angle) * rx * wobble, centre_y + sin(angle) * ry * wobble)))
			loop[steps] = loop[0]
			_segment(segments, "ring", town, loop, 13.0, 3.0)
		"hamlets":
			# Two or three tracks that run out to small clusters of houses in the clearings.
			var count: int = 2 + sim.random_int(stream, 0, 1)
			var offsets: Array = [-1.0, 1.0, (1.0 if sim.random_int(stream, 0, 1) == 0 else -1.0)]
			for index in range(count):
				var direction: float = offsets[index]
				var start_x: float = cx + direction * _rf(sim, stream, 26.0, 46.0) + float(index) * direction * 4.0
				var angle: float = _rf(sim, stream, 0.25, 0.9) * direction   # leaning away from the square
				var length: float = _rf(sim, stream, 28.0, 44.0)
				var tip := Vector2(start_x + sin(angle) * length, y0 + cos(angle) * length)
				var track := _curve(Vector2(start_x, y0), tip, _rf(sim, stream, 2.0, 4.5), _rf(sim, stream, 1.4, 2.6), _rf(sim, stream, 0.0, 6.0), 2.0, "start")
				_segment(segments, "spur", town, track, 12.0, 2.5)
				# A short cross-lane at the end holds the cluster.
				var end: Vector2 = _vec(track[track.size() - 1])
				_segment(segments, "spur", town, _curve(end - Vector2(7.0, -1.5), end + Vector2(7.0, 1.0), 1.0, 1.0, 0.0, 2.0, "both"), 11.0, 2.0)

# --- reading the roads ------------------------------------------------------------------------

## The road segments: the stored ones, or (for games saved before roads were data) the old fixed layout.
static func segments(s: Dictionary) -> Array:
	var roads: Dictionary = s.get("world", {}).get("roads", {})
	if roads.has("segments"): return roads.segments
	return _legacy_segments(s)

static func has_roads(s: Dictionary) -> bool:
	return s.get("world", {}).get("roads", {}).has("segments")

## The roads as they were drawn before layouts were generated: a straight street east to Reedbank, a
## curving road south to Dustvale, and Dustvale's own street.
static func _legacy_segments(s: Dictionary) -> Array:
	var result: Array = []
	var east: float = 226.0
	if s.get("settlements", {}).has("2"): east = float(s.entities[str(s.settlements["2"].warehouse)].cell[0]) + 46.0
	var line: Array = []
	var x: float = 28.0
	while x < east:
		line.append([x, 48.0 + (sin(x * 0.27) * 5.2 + sin(x * 0.61) * 2.6) / 24.0])
		x += 2.0
	result.append({"id": 1, "kind": "link", "town": 1, "radius": 17.0, "reach": 4.0, "points": line})
	if s.get("settlements", {}).has("3"):
		var store3: Array = s.entities[str(s.settlements["3"].warehouse)].cell
		var south: Array = []
		var start := Vector2(70, 50)
		var finish := Vector2(store3[0], store3[1] - 2)
		for step in range(0, 41):
			var t: float = float(step) / 40.0
			var along: Vector2 = start.lerp(finish, t)
			south.append([along.x + sin(t * 9.0) * 3.2 + sin(t * 23.0) * 1.2, along.y])
		result.append({"id": 2, "kind": "link", "town": 1, "radius": 16.0, "reach": 5.0, "points": south})
		var street: Array = []
		var sx: float = float(store3[0]) - 42.0
		while sx < float(store3[0]) + 36.0:
			street.append([sx, float(store3[1]) + 2.0 + sin(sx * 0.31) * 0.25])
			sx += 2.0
		result.append({"id": 3, "kind": "main", "town": 3, "radius": 16.0, "reach": 3.0, "points": street})
	return result

## Every cell kept clear by the roads (a set of "x,y" keys), memoised per layout.
static var _cell_cache: Dictionary = {}
static func road_cells(s: Dictionary) -> Dictionary:
	var list: Array = segments(s)
	var checksum: float = 0.0
	for segment in list: checksum += float(segment.points.size()) + float(segment.points[segment.points.size() - 1][0]) + float(segment.points[segment.points.size() - 1][1]) * 3.0
	var signature: String = "%d:%d:%s:%.1f" % [int(s.get("seed", 0)), list.size(), str(has_roads(s)), checksum]
	if _cell_cache.get("signature", "") == signature: return _cell_cache.cells
	var cells: Dictionary = {}
	for segment in list:
		var reach: int = ceili(float(segment.reach))
		var previous: Vector2 = _vec(segment.points[0])
		for index in range(segment.points.size()):
			var p: Vector2 = _vec(segment.points[index])
			var steps: int = maxi(1, ceili(previous.distance_to(p)))
			for step in range(steps + 1):
				var q: Vector2 = previous.lerp(p, float(step) / float(steps))
				var cx: int = roundi(q.x)
				var cy: int = roundi(q.y)
				for dy in range(-reach, reach + 1):
					for dx in range(-reach, reach + 1):
						if dx * dx + dy * dy <= reach * reach + reach: cells["%d,%d" % [cx + dx, cy + dy]] = true
			previous = p
	_cell_cache = {"signature": signature, "cells": cells}
	return cells

static func on_road(s: Dictionary, cell: Array) -> bool:
	return road_cells(s).has("%d,%d" % [cell[0], cell[1]])

## What kind of road each cell is on: {"kind": {"x,y": 2 on a road between towns, 1 on a town
## street or lane}, "centre": {"x,y": true within a cell of a road's line}}. Memoised like road_cells.
static var _map_cache: Dictionary = {}
static func road_map(s: Dictionary) -> Dictionary:
	var cells := road_cells(s)   # refreshes _cell_cache.signature for this layout
	var signature: String = _cell_cache.get("signature", "")
	if _map_cache.get("signature", "") == signature: return _map_cache.map
	var kind: Dictionary = {}
	var centre: Dictionary = {}
	for pass_link in [false, true]:   # links last, so where a link runs down a street it counts as the link
		for segment in segments(s):
			if (segment.kind == "link") != pass_link: continue
			var value: int = 2 if pass_link else 1
			var reach: int = ceili(float(segment.reach))
			var previous: Vector2 = _vec(segment.points[0])
			for index in range(segment.points.size()):
				var p: Vector2 = _vec(segment.points[index])
				var steps: int = maxi(1, ceili(previous.distance_to(p)))
				for step in range(steps + 1):
					var q: Vector2 = previous.lerp(p, float(step) / float(steps))
					var cx: int = roundi(q.x)
					var cy: int = roundi(q.y)
					for dy in range(-reach, reach + 1):
						for dx in range(-reach, reach + 1):
							if dx * dx + dy * dy > reach * reach + reach: continue
							var key := "%d,%d" % [cx + dx, cy + dy]
							kind[key] = value
							if absi(dx) <= 1 and absi(dy) <= 1: centre[key] = true
				previous = p
	var map := {"kind": kind, "centre": centre, "cells": cells.size()}
	_map_cache = {"signature": signature, "map": map}
	return map

## 2 on a road between towns, 1 on a town street or lane, 0 off the roads.
static func road_kind(s: Dictionary, cell: Array) -> int:
	return int(road_map(s).kind.get("%d,%d" % [cell[0], cell[1]], 0))

## A short text that changes whenever the roads do (for caches built on them).
static func road_signature(s: Dictionary) -> String:
	road_cells(s)
	return String(_cell_cache.get("signature", ""))

## Coarse rectangles over the road corridors (a box around every few points), for code that wants rectangles.
static func corridors(s: Dictionary) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for segment in segments(s):
		var reach: int = ceili(float(segment.reach))
		var points: Array = segment.points
		var start: int = 0
		while start < points.size() - 1:
			var finish: int = mini(start + 3, points.size() - 1)
			var low := Vector2i(1 << 30, 1 << 30)
			var high := Vector2i(-(1 << 30), -(1 << 30))
			for index in range(start, finish + 1):
				var p: Vector2 = _vec(points[index])
				low = Vector2i(mini(low.x, floori(p.x)), mini(low.y, floori(p.y)))
				high = Vector2i(maxi(high.x, ceili(p.x)), maxi(high.y, ceili(p.y)))
			result.append(Rect2i(low.x - reach, low.y - reach, high.x - low.x + 2 * reach + 1, high.y - low.y + 2 * reach + 1))
			start = finish
	return result

## The nearest point on any road to `point`, with the road's id.
static func nearest_road_point(s: Dictionary, point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for segment in segments(s):
		for index in range(segment.points.size() - 1):
			var a: Vector2 = _vec(segment.points[index])
			var b: Vector2 = _vec(segment.points[index + 1])
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
			var d: float = closest.distance_to(point)
			if d < best_distance:
				best_distance = d
				best = {"point": closest, "segment": int(segment.id), "distance": d, "tangent": (b - a).normalized()}
	return best

# --- lots -------------------------------------------------------------------------------------

## Cardinal facing (0 north, 1 east, 2 south, 3 west) closest to `direction`.
static func facing_of(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y): return 1 if direction.x > 0.0 else 3
	return 2 if direction.y > 0.0 else 0

static func facing_vector(side: int) -> Vector2i:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][posmod(side, 4)]

## Places a door could go along the roads near a town, both sides of each, at a few depths back from
## the road: {"door", "side" (the way the door faces, towards the road), "segment", "distance" from the
## square}. Positions are a plain function of the road lines, so nothing needs storing.
static func lots(s: Dictionary, town: int) -> Array:
	var result: Array = []
	var layout: Dictionary = s.get("world", {}).get("layout", {}).get(str(town), {})
	if layout.is_empty(): return result
	var centre: Vector2 = _vec(layout.centre)
	for segment in segments(s):
		var points: Array = segment.points
		var carried: float = 0.0
		var next_at: float = 4.0
		var index_on_road: int = 0
		for index in range(points.size() - 1):
			var a: Vector2 = _vec(points[index])
			var b: Vector2 = _vec(points[index + 1])
			var length: float = a.distance_to(b)
			if length < 0.001: continue
			var tangent: Vector2 = (b - a) / length
			var normal := Vector2(-tangent.y, tangent.x)
			while next_at <= carried + length:
				var at: Vector2 = a + tangent * (next_at - carried)
				if centre.distance_to(at) <= MAX_LOT_DISTANCE:
					for side_sign in [-1.0, 1.0]:
						for tier in range(3):
							var setback: float = float(segment.reach) + 2.0 + float(tier * 4) + float((index_on_road + tier) % 3)
							var door_point: Vector2 = at + normal * side_sign * setback
							var door: Array = [roundi(door_point.x), roundi(door_point.y)]
							result.append({"door": door, "side": facing_of(-normal * side_sign), "segment": int(segment.id), "distance": centre.distance_to(door_point)})
				next_at += LOT_SPACING
				index_on_road += 1
			carried += length
	return result
