extends RefCounted
## Light in the world, as simulation data so later systems (stealth) can ask how lit a cell is.
## Street lamps are entities beside the town streets, lit on a timer from dusk to dawn (the
## lamplighter is a simple switch for now). The player's lantern is lit while it is held in hand.
## Nothing here is random: lamps sit at fixed spacing along the planned streets.
const World = preload("res://sim/world/world_db.gd")
const DerivedCache = preload("res://sim/core/derived_cache.gd")

const LIT_FROM := 1170      # 19:30, minutes into the day
const LIT_UNTIL := 330      # 05:30
const SPACING := 10         # cells between lamps along a street
const LAMP_REACH := 5       # cells a lamp lights
const LANTERN_REACH := 4
const MAX_LAMPS_PER_TOWN := 24

static func minute(s: Dictionary) -> int:
	return (int(s.tick) / 10) % 1440

## Street lamps burn from 19:30 to 05:30.
static func lamps_lit(s: Dictionary) -> bool:
	var m := minute(s)
	return m >= LIT_FROM or m < LIT_UNTIL

## Daylight alone, 0 (deep night) to 100 (full day), with an hour of dusk and dawn.
static func daylight(s: Dictionary) -> int:
	var m := minute(s)
	if m >= 420 and m < 1140: return 100            # 07:00-19:00
	if m >= 1260 or m < 300: return 10              # 21:00-05:00
	if m >= 1140: return 100 - (m - 1140) * 90 / 120 # dusk, 19:00-21:00
	return 10 + (m - 300) * 90 / 120                 # dawn, 05:00-07:00

## Whether the player's lantern is burning (it is lit while held in hand).
static func lantern_on(s: Dictionary) -> bool:
	return str(s.get("player_control", {}).get("held_item", "")) == "lantern"

## How lit a cell is, 0 to 100: daylight plus lit lamps within 5 cells plus the player's lantern.
static func level(s: Dictionary, cell: Array) -> int:
	var total := daylight(s)
	if total >= 100: return 100
	if lamps_lit(s):
		var best := 0
		for lamp_cell in _lamps_near(s, cell):
			var d: int = maxi(absi(int(lamp_cell[0]) - int(cell[0])), absi(int(lamp_cell[1]) - int(cell[1])))
			if d <= LAMP_REACH: best = maxi(best, 70 - d * 10)
		total += best
	if lantern_on(s) and s.has("player"):
		var p: Array = s.entities[str(s.player)].cell
		var d2: int = maxi(absi(int(p[0]) - int(cell[0])), absi(int(p[1]) - int(cell[1])))
		if d2 <= LANTERN_REACH: total += 60 - d2 * 10
	return clampi(total, 0, 100)

## Lamps bucketed by 8x8 block (derived, never saved), so a level lookup reads a few buckets.
static var _bucket_cache: Array = []
static func _lamps_near(s: Dictionary, cell: Array) -> Array:
	var lamps: Array = World.of_kind(s, "street_lamp")
	var cache: Dictionary = DerivedCache.slot(_bucket_cache, s.entities)
	if cache.get("signature") != [lamps.size(), World.entity_serial]:
		var buckets := {}
		for lamp in lamps:
			var key := "%d,%d" % [floori(lamp.cell[0] / 8.0), floori(lamp.cell[1] / 8.0)]
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(lamp.cell)
		cache.buckets = buckets
		cache.signature = [lamps.size(), World.entity_serial]
	var result: Array = []
	var bx: int = floori(int(cell[0]) / 8.0)
	var by: int = floori(int(cell[1]) / 8.0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			result.append_array(cache.buckets.get("%d,%d" % [bx + dx, by + dy], []))
	return result

## Places street lamps along every town street and lane, once (new worlds after the roads are
## planned, and older saves on load). Lamps stand just off the road, alternating sides.
static func ensure_lamps(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("settlements") or not s.has("world") or not s.world.has("roads"): return
	if not World.of_kind(s, "street_lamp").is_empty(): return
	var TownLayout = load("res://sim/world/town_layout.gd")
	var placed: Array = []
	var per_town := {}
	for segment in TownLayout.segments(s):
		if str(segment.get("kind", "")) == "link": continue
		var town: int = int(segment.get("town", 0))
		if not s.settlements.has(str(town)): continue
		var offset: int = ceili(float(segment.get("reach", 3.0))) + 1
		var walked := 0.0
		var next_at := float(SPACING) / 2.0
		var side := 1
		var points: Array = segment.points
		for index in range(1, points.size()):
			var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
			var b := Vector2(float(points[index][0]), float(points[index][1]))
			var length := a.distance_to(b)
			if length <= 0.0: continue
			while walked + length >= next_at:
				if int(per_town.get(town, 0)) >= MAX_LAMPS_PER_TOWN: break
				var at := a.lerp(b, (next_at - walked) / length)
				var normal := (b - a).normalized().orthogonal() * float(side)
				var spot := _spot(s, TownLayout, at, normal, offset, placed)
				if not spot.is_empty():
					World.add_entity(sim, "street_lamp", "Street lamp", spot, town)
					placed.append(spot)
					per_town[town] = int(per_town.get(town, 0)) + 1
				side = -side
				next_at += float(SPACING)
			walked += length

static func _spot(s: Dictionary, TownLayout: GDScript, at: Vector2, normal: Vector2, offset: int, placed: Array) -> Array:
	for extra in [0, 1, 2]:
		var q := at + normal * float(offset + extra)
		var cell: Array = [roundi(q.x), roundi(q.y)]
		if not World.walkable(s, cell) or TownLayout.on_road(s, cell) or World.inside_building(s, cell) != 0: continue
		var crowded := false
		for other in placed:
			if absi(int(other[0]) - cell[0]) + absi(int(other[1]) - cell[1]) < 5: crowded = true; break
		if not crowded: return cell
	return []
