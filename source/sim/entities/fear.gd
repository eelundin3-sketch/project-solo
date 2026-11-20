extends RefCounted
## Villagers who see a gun go off run for cover: behind the nearest tree or the corner of the
## nearest building, out of the shooter's sight, and crouch there until things have been quiet for
## a while. Only people in the shooter's town, or close by, who can actually see it are affected.
const Cover = preload("res://sim/combat/cover.gd")
const Limbs = preload("res://sim/combat/limbs.gd")
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const SEE_RANGE := 26.0
const COVER_RANGE := 16
const QUIET_TICKS := 320          # how long they stay down after the last shot they saw
const FLEE_DISTANCE := 12

static func _speech() -> GDScript:
	return load("res://sim/entities/speech.gd")

## A gun went off at `origin` in `town`. Everyone in that town who can see it takes cover.
static func on_gunshot(sim: RefCounted, town: int, origin: Array) -> void:
	var s: Dictionary = sim.state
	var keys: Array = s.get("residents", {}).keys()
	keys.sort()
	var see: float = load("res://sim/world/weather.gd").sight(s, origin, SEE_RANGE)   # less in fog
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.settlement != town or npc.occupation == "Sheriff" or npc.health <= 0: continue
		if npc.get("fidelity", "detailed") != "detailed": continue   # far from the player: not simulated closely
		if not npc.get("sleeping", {}).is_empty() or not npc.get("migration", {}).is_empty() or not npc.get("arrest", {}).is_empty(): continue
		if load("res://sim/combat/brawl.gd").busy(s, npc) or not npc.get("brawl", {}).is_empty(): continue
		if npc.occupation == "Trader" and load("res://sim/economy/traders.gd").away(s, npc): continue
		var cell: Array = s.entities[key].cell
		if Vector2(cell[0] - origin[0], cell[1] - origin[1]).length() > see: continue
		if not Cover.line_clear(s, origin, cell): continue   # behind a wall: they did not see it
		_scare(sim, npc, origin)

static func _scare(sim: RefCounted, npc: Dictionary, origin: Array) -> void:
	var s: Dictionary = sim.state
	var fear: Dictionary = npc.get("fear", {})
	if not fear.is_empty():
		fear.until = s.tick + QUIET_TICKS   # another shot: stay down longer
		fear.from = origin.duplicate()
		return
	var cell: Array = s.entities[str(npc.id)].cell
	if npc.job != 0: load("res://sim/jobs/job_board.gd").release(s, npc.job, "SHOOTING")
	npc.goal = ""
	npc.path = []
	npc.work_path = []
	var spot: Array = find_cover(s, cell, origin)
	npc.fear = {"until": s.tick + QUIET_TICKS, "from": origin.duplicate(), "cover": spot, "arrived": false, "path_tick": -100}
	npc.status = "Running for cover"
	if sim.random_int("fear", 0, 99) < 35: _speech().say(sim, npc.id, "scared")

## A cell the shooter at `origin` cannot see, next to a tree or a wall, near `from`; the nearest
## wins. If there is none, a point straight away from the shooter.
static func find_cover(s: Dictionary, from: Array, origin: Array) -> Array:
	var best: Array = []
	var best_score := 1.0e9
	for dy in range(-COVER_RANGE, COVER_RANGE + 1):
		for dx in range(-COVER_RANGE, COVER_RANGE + 1):
			var cell: Array = [from[0] + dx, from[1] + dy]
			var score: float = float(absi(dx) + absi(dy))
			if score >= best_score or not Cover.is_cover(s, cell): continue
			if Vector2(cell[0] - origin[0], cell[1] - origin[1]).length() < 2.5: continue
			if Cover.line_clear(s, origin, cell, false, true): continue   # still in the shooter's sight (they crouch to hide)
			best_score = score
			best = cell
	if not best.is_empty(): return best
	var away := Vector2(from[0] - origin[0], from[1] - origin[1])
	away = away.normalized() if away.length() > 0.1 else Vector2.RIGHT
	for distance in range(FLEE_DISTANCE, 3, -2):
		var spot: Array = [roundi(from[0] + away.x * distance), roundi(from[1] + away.y * distance)]
		if World.walkable(s, spot): return spot
	return from.duplicate()

## Every tick: scared villagers run to their cover and crouch there until it has been quiet a while.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("residents"): return
	for key in s.residents.keys():
		var npc: Dictionary = s.residents[key]
		var fear: Dictionary = npc.get("fear", {})
		if fear.is_empty(): continue
		if npc.health <= 0 or not npc.get("arrest", {}).is_empty():
			npc.erase("fear")
			continue
		if s.tick >= int(fear.until):
			npc.erase("fear")
			npc.status = "Calming down"
			npc.work_pause_until = s.tick + 60
			continue
		var load_brawl = load("res://sim/combat/brawl.gd")
		if load_brawl.knocked(s, npc): continue
		var cell: Array = s.entities[key].cell
		var spot: Array = fear.cover
		if spot.is_empty() or cell == spot:
			fear.arrived = true
			continue
		var step: int = Limbs.step_ticks(s, int(key))
		if step > 2 and s.tick % step != 0: continue    # a limp or a crawl: slow going
		if s.tick - int(fear.path_tick) >= 10 or npc.path.is_empty():
			var route := Nav.request_path(s, cell, spot)
			fear.path_tick = s.tick
			npc.path = route.path if route.ok else []
			if not route.ok: fear.cover = cell.duplicate()   # no way there: crouch where they are
		if not npc.path.is_empty():
			var next: Array = npc.path.pop_front()
			if World.walkable(s, next): s.entities[key].cell = next
			if step <= 2: npc.running_tick = s.tick   # a sprint, as in a chase
