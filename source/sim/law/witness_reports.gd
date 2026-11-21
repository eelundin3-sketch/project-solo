extends RefCounted
## Townspeople as witnesses. When nobody from the law saw a crime, whoever did see it (or the
## victim, awake and on their feet) hurries to the nearest sheriff; the crime is only on the books
## once they get there. Stop them on the way and it never is. A crime nobody saw is a mystery:
## it is kept in s.law.hidden (a found body or an empty chest may surface it later) but nobody
## knows who did it. Witnesses describe the clothes they saw, and that is how sheriffs know you.
const Nav = preload("res://sim/movement/navigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const STEP_TICKS := 2          # hurrying: a step every other tick
const REPATH_TICKS := 60
const GIVE_UP_TICKS := 1800    # three hours of looking for a sheriff
const ARRIVE := 2.5            # cells from the sheriff to tell him
const MAX_HIDDEN := 30

static func _law() -> GDScript: return load("res://sim/law/law.gd")

## Awake, standing people who know who did it: the witnesses in the chronicle entry and the victim.
static func tellers(s: Dictionary, entry: Dictionary, victim: int) -> Array:
	var result: Array = []
	var candidates: Array = entry.get("witnesses", []).duplicate()
	if victim != 0: candidates.append(victim)
	for id in candidates:
		var npc: Dictionary = s.get("residents", {}).get(str(id), {})
		if npc.is_empty() or int(npc.get("health", 0)) <= 0 or Brawl.knocked(s, npc) or not npc.get("sleeping", {}).is_empty(): continue
		if npc.occupation in ["Child", "Bandit"] or not npc.get("reporting", {}).is_empty(): continue
		if not id in result: result.append(int(id))
	result.sort()
	return result

## What the player has on, as a witness would describe it.
static func description(s: Dictionary) -> Dictionary:
	return Outfits.worn(s, int(s.player)).duplicate()

## Sends the nearest teller to the sheriff with the news. True when someone set off.
static func send(s: Dictionary, town: int, kind: String, victim: int, entry: Dictionary) -> bool:
	var people: Array = tellers(s, entry, victim)
	if people.is_empty(): return false
	var at: Array = entry.get("cell", s.entities[str(s.player)].cell)
	var best: int = people[0]
	var best_gap := 1.0e9
	for id in people:
		var cell: Array = s.entities[str(id)].cell
		var gap := Vector2(cell[0] - at[0], cell[1] - at[1]).length()
		if gap < best_gap: best_gap = gap; best = id
	var npc: Dictionary = s.residents[str(best)]
	if npc.job != 0: load("res://sim/jobs/job_board.gd").release(s, npc.job, "REPORTING_A_CRIME")
	npc.goal = ""
	npc.path = []
	npc.reporting = {"town": town, "kind": kind, "victim": victim, "outfit": description(s), "since": s.tick, "path_tick": -1000, "next_step": s.tick}
	npc.status = "Running to tell the sheriff"
	return true

## Kept for later discovery: a crime nobody saw.
static func hide(s: Dictionary, town: int, kind: String, victim: int) -> void:
	var law: Dictionary = _law()._law(s)
	if not law.has("hidden"): law.hidden = []
	var cell: Array = s.entities[str(victim)].cell if s.entities.has(str(victim)) else [0, 0]
	law.hidden.append({"kind": kind, "town": town, "victim": victim, "cell": cell.duplicate(), "tick": s.tick})
	while law.hidden.size() > MAX_HIDDEN: law.hidden.pop_front()

## Every tick: each reporting witness hurries on; on reaching a sheriff the crime is filed.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("residents"): return
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		var report: Dictionary = npc.get("reporting", {})
		if report.is_empty(): continue
		# Stopped on the way (knocked down, killed, dragged off to sleep): the news never arrives.
		if int(npc.health) <= 0 or Brawl.knocked(s, npc) or s.tick - int(report.since) > GIVE_UP_TICKS:
			_finish(npc)
			continue
		var sheriff: Dictionary = _nearest_sheriff(s, int(report.town), s.entities[key].cell)
		if sheriff.is_empty():
			if s.tick - int(report.since) > 300: _finish(npc)   # no law left in town to tell
			continue
		var here: Array = s.entities[key].cell
		var there: Array = s.entities[str(sheriff.id)].cell
		if Vector2(there[0] - here[0], there[1] - here[1]).length() <= ARRIVE:
			_tell(sim, npc, sheriff, report)
			continue
		if s.tick < int(report.next_step): continue
		if npc.path.is_empty() or s.tick - int(report.path_tick) >= REPATH_TICKS:
			var route: Dictionary = Nav.request_path(s, here, there)
			npc.path = route.path.slice(1) if route.ok else []
			report.path_tick = s.tick
		if not npc.path.is_empty():
			s.entities[key].cell = npc.path.pop_front()
			npc.running_tick = s.tick
		report.next_step = s.tick + STEP_TICKS

static func _nearest_sheriff(s: Dictionary, town: int, from: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 1.0e9
	for sheriff in _law().sheriffs(s, town):
		if Brawl.knocked(s, sheriff): continue
		var cell: Array = s.entities[str(sheriff.id)].cell
		var gap := Vector2(cell[0] - from[0], cell[1] - from[1]).length()
		if gap < best_gap: best_gap = gap; best = sheriff
	return best

static func _tell(sim: RefCounted, npc: Dictionary, sheriff: Dictionary, report: Dictionary) -> void:
	var s: Dictionary = sim.state
	var Law: GDScript = _law()
	var what: String = {"theft": "robbed", "murder": "killed", "assault": "attacked", "kick": "beat", "shooting": "shot at", "assault_sheriff": "attacked"}.get(str(report.kind), "attacked")
	var victim_name: String = String(s.entities.get(str(report.victim), {}).get("name", "someone")).split(" ")[0]
	Law._say(sim, int(npc.id), "Sheriff! The stranger %s %s!" % [what, victim_name if int(report.victim) != int(npc.id) else "me"])
	Law.file(s, int(report.town), str(report.kind), report.outfit, false)
	_finish(npc)

static func _finish(npc: Dictionary) -> void:
	npc.reporting = {}
	npc.path = []
	npc.goal = ""
	npc.status = ""
