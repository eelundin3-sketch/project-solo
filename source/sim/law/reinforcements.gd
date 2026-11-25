extends RefCounted
## Help from the next town. When the traveller kills someone in a town and somebody sees it, a
## townsperson runs for help to the nearest other town. That town sends two of its sheriffs
## (always keeping one at home). They walk the road to the town in trouble and:
##   - if the fight is still on, they join it as that town's sheriffs;
##   - if the killer has already been caught, they come to the office, talk it over with the
##     sheriff there, and go home;
##   - otherwise they look in at the office, ask after the killer, and go home.
## Movement is a trip like a trader's (a road path worked out once, then a position lookup), so it
## costs nothing per tick. While helping, a sheriff counts as the town's own (settlement switched,
## home kept in `reinforcing.home`); Sheriff.ensure still counts him at home. Stream: "reinforce".
const World = preload("res://sim/world/world_db.gd")
const Pace = preload("res://sim/movement/pace.gd")
const SEND := 2              # sheriffs sent
const RUN_TICKS := 2         # ticks per cell for the runner (running)
const WALK_TICKS := 3        # ticks per cell for the sheriffs (a fast walk)
const HELP_AT_MOST := 3600   # they stay at most six hours before going home
const TALK_EVERY := 90       # ticks between lines of the office talk
const TALK := [
	["helper", "We came as fast as we could."],
	["host", "Appreciate it. We got him, he's in the cell."],
	["helper", "Good. Good that he was caught. Anyone else hurt?"],
	["host", "We lost one. Could have been worse."],
	["helper", "Terrible business. Send word if you need us again."],
	["host", "I will. Safe road home."],
	["helper", "We'll be heading back, then."],
]
const ASK := [
	["helper", "We came as fast as we could. Where's the killer?"],
	["host", "Gone. Lit out before we could take him."],
	["helper", "Then keep your eyes open. We'll be heading back."],
]

static func _law() -> GDScript:
	return load("res://sim/law/law.gd")

static func list(s: Dictionary) -> Array:
	var law: Dictionary = _law()._law(s)   # created the law's own way if it isn't there yet
	if not law.has("reinforcements"): law.reinforcements = []
	return s.law.reinforcements

## The traveller killed someone in `town` at `cell`. If anyone saw it, a runner goes for help
## (once per town until that call is over).
static func on_killing(sim: RefCounted, town: int, cell: Array, witnesses: Array) -> void:
	var s: Dictionary = sim.state
	if town == 0 or not s.has("settlements") or not s.settlements.has(str(town)) or witnesses.is_empty(): return
	for call in list(s):
		if int(call.town) == town and str(call.phase) != "done": return
	var helper_town: int = _nearest_other(s, town)
	if helper_town == 0: return
	var runner: Dictionary = _pick_runner(s, town, witnesses, cell)
	if runner.is_empty(): return
	var gate: Array = load("res://sim/world/road_planner.gd").town_gate(s, s.settlements[str(helper_town)])
	var trip := _trip(s, s.entities[str(runner.id)].cell, gate, RUN_TICKS)
	if trip.is_empty(): return
	var call := {"id": int(s.law.get("reinforce_next", 1)), "town": town, "from": helper_town, "phase": "runner",
		"runner": int(runner.id), "sheriffs": [], "trip": trip, "since": s.tick, "talk": 0}
	s.law.reinforce_next = int(call.id) + 1
	list(s).append(call)
	_hold(s, runner, call)
	runner.status = "Running to %s for help" % s.settlements[str(helper_town)].name
	_law()._say(sim, int(runner.id), "I'm going for help! I'll fetch the sheriffs from %s!" % s.settlements[str(helper_town)].name)
	sim.record("%s runs to %s for help." % [s.entities[str(runner.id)].name, s.settlements[str(helper_town)].name])

static func _nearest_other(s: Dictionary, town: int) -> int:
	var here: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
	var best := 0
	var best_gap := 1 << 60
	var keys: Array = s.settlements.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for key in keys:
		if int(key) == town: continue
		var there: Array = s.entities[str(s.settlements[key].warehouse)].cell
		var gap: int = (there[0] - here[0]) * (there[0] - here[0]) + (there[1] - here[1]) * (there[1] - here[1])
		if gap < best_gap: best_gap = gap; best = int(key)
	return best

## A townsperson to run: a witness if one can, else whoever is nearest. Not a sheriff, a child,
## a trader, a bandit, or anyone hurt, asleep or busy elsewhere.
static func _pick_runner(s: Dictionary, town: int, witnesses: Array, cell: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 1 << 60
	var keys: Array = s.residents.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != town or npc.occupation in ["Sheriff", "Child", "Trader", "Bandit", "Governor"] or int(npc.health) <= 0: continue
		if not npc.get("sleeping", {}).is_empty() or not npc.get("knock", {}).is_empty() or not npc.get("reinforcing", {}).is_empty(): continue
		var at: Array = s.entities[key].cell
		var gap: int = absi(at[0] - cell[0]) + absi(at[1] - cell[1]) - (1000 if int(npc.id) in witnesses else 0)
		if gap < best_gap: best_gap = gap; best = npc
	return best

## A walk along the roads from `from` to `to`: {"path", "times", "start"}; {} if there is no way.
static func _trip(s: Dictionary, from: Array, to: Array, ticks_per_cell: int) -> Dictionary:
	var route: Dictionary = load("res://sim/movement/navigation.gd").request_travel_path(s, from, to)
	if not route.ok or route.path.is_empty(): return {}
	var path: Array = [from.duplicate()] + route.path
	return {"path": path, "times": Pace.schedule(s, path, ticks_per_cell), "start": s.tick}

## Where a traveller on `trip` is now, and whether they have arrived.
static func _along(s: Dictionary, trip: Dictionary) -> Array:
	var elapsed: int = int(s.tick) - int(trip.start)
	var times: Array = trip.times
	var index: int = times.bsearch(elapsed, false) - 1
	index = clampi(index, 0, trip.path.size() - 1)
	return [trip.path[index], index >= trip.path.size() - 1]

## Takes someone out of their normal life for the call (residents.gd and law.gd skip them).
static func _hold(s: Dictionary, npc: Dictionary, call: Dictionary) -> void:
	if int(npc.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, npc.job, "REINFORCING")
	if npc.has("sitting"): load("res://sim/law/sheriff.gd").stand_up(s, npc)
	npc.goal = ""
	npc.path = []
	npc.work_path = []
	npc.arrest = {} if str(npc.get("arrest", {}).get("phase", "")) in ["", "engage", "backup", "standoff"] else npc.arrest
	npc.cover_cycle = {}
	npc.reinforcing = {"call": int(call.id), "home": int(npc.get("reinforcing", {}).get("home", npc.settlement))}

static func _release(s: Dictionary, npc: Dictionary) -> void:
	var home: int = int(npc.get("reinforcing", {}).get("home", npc.settlement))
	npc.settlement = home
	s.entities[str(npc.id)].settlement = home
	npc.erase("reinforcing")
	npc.arrest = {}
	npc.cover_cycle = {}
	npc.goal = ""
	npc.path = []
	npc.status = "Back on duty"

static func busy(npc: Dictionary) -> bool:
	return not npc.get("reinforcing", {}).is_empty() and str(npc.reinforcing.get("role", "")) != "helping"

# --- every tick --------------------------------------------------------------------------------

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("law") or not s.law.has("reinforcements") or s.law.reinforcements.is_empty(): return
	for call in s.law.reinforcements:
		match str(call.phase):
			"runner": _runner(sim, call)
			"coming": _coming(sim, call)
			"helping": _helping(sim, call)
			"visiting": _visiting(sim, call)
			"returning": _returning(sim, call)
	s.law.reinforcements = s.law.reinforcements.filter(func(c: Dictionary) -> bool: return str(c.phase) != "done" or s.tick - int(c.get("since", 0)) < 14400)

static func _runner(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var runner: Dictionary = s.residents.get(str(call.runner), {})
	if runner.is_empty() or int(runner.health) <= 0 or not runner.get("knock", {}).is_empty():
		call.phase = "done"
		if not runner.is_empty(): runner.erase("reinforcing")
		return
	var at: Array = _along(s, call.trip)
	s.entities[str(runner.id)].cell = at[0].duplicate()
	if not at[1]: return
	# Arrived: tells the sheriffs, and two of them set off (one always stays at home).
	var roster: Array = load("res://sim/law/sheriff.gd").roster(s, int(call.from))
	var free: Array = roster.filter(func(id) -> bool:
		var n: Dictionary = s.residents[str(id)]
		return n.get("reinforcing", {}).is_empty() and str(n.get("arrest", {}).get("phase", "")) in ["", "backup"])
	var sending: int = mini(SEND, roster.size() - 1)
	var town_name: String = s.settlements[str(call.town)].name
	_law()._say(sim, int(runner.id), "There's been a killing in %s! They need help!" % town_name)
	if sending <= 0 or free.is_empty():
		call.phase = "done"
		runner.erase("reinforcing")
		return
	var target: Array = load("res://sim/world/road_planner.gd").town_gate(s, s.settlements[str(call.town)])
	for i in range(mini(sending, free.size())):
		var npc: Dictionary = s.residents[str(free[i])]
		var trip := _trip(s, s.entities[str(npc.id)].cell, target, WALK_TICKS)
		if trip.is_empty(): continue
		_hold(s, npc, call)
		npc.reinforcing.trip = trip
		npc.reinforcing.role = "coming"
		npc.status = "Riding to %s to help" % town_name
		call.sheriffs.append(int(npc.id))
		if i == 0: _law()._say(sim, int(npc.id), "Right. We're on our way to %s." % town_name)
	if call.sheriffs.is_empty():
		call.phase = "done"
		runner.erase("reinforcing")
		return
	# The runner goes back with them.
	runner.reinforcing.trip = _trip(s, s.entities[str(runner.id)].cell, target, WALK_TICKS)
	call.phase = "coming"
	call.since = s.tick
	sim.record("Sheriffs set out from %s to help %s." % [s.settlements[str(call.from)].name, town_name])

static func _coming(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var arrived := true
	for id in call.sheriffs + [call.runner]:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty() or npc.get("reinforcing", {}).is_empty() or not npc.reinforcing.has("trip"): continue
		var at: Array = _along(s, npc.reinforcing.trip)
		s.entities[str(id)].cell = at[0].duplicate()
		if not at[1]: arrived = false
	if not arrived: return
	# The runner is home again.
	var runner: Dictionary = s.residents.get(str(call.runner), {})
	if not runner.is_empty(): runner.erase("reinforcing"); runner.status = "Back home"
	var Law = _law()
	var town: int = int(call.town)
	var fighting: bool = not s.law.get("alert", {}).get(str(town), {}).is_empty() and not Law.in_custody(s)
	call.since = s.tick
	for id in call.sheriffs:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty(): continue
		npc.reinforcing.erase("trip")
		npc.settlement = town                      # for now, one of this town's sheriffs
		s.entities[str(id)].settlement = town
		npc.reinforcing.role = "helping" if fighting else "visiting"
	call.phase = "helping" if fighting else "visiting"
	call.caught = Law.in_custody(s)
	call.talk = 0
	if fighting: _law()._say(sim, int(call.sheriffs[0]), "We're here! Where is he?")

## Helping in the fight: they are the town's sheriffs until it is over, then go to the office.
static func _helping(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var over: bool = s.law.get("alert", {}).get(str(call.town), {}).is_empty()
	if not over and s.tick - int(call.since) < HELP_AT_MOST: return
	call.phase = "visiting"
	call.caught = _law().in_custody(s)
	call.since = s.tick
	call.talk = 0
	for id in call.sheriffs:
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty() and not npc.get("reinforcing", {}).is_empty():
			if str(npc.get("arrest", {}).get("phase", "")) in ["cuff", "lift", "escort", "book", "lock"]: continue   # still taking him in
			npc.arrest = {}
			npc.cover_cycle = {}
			npc.reinforcing.role = "visiting"

## At the office: walk to the desk, talk it over with the sheriff there, then head home.
static func _visiting(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var Law = _law()
	var office: Dictionary = Law.office_of(s, int(call.town))
	var lead: Dictionary = s.residents.get(str(call.sheriffs[0]), {}) if not call.sheriffs.is_empty() else {}
	if office.is_empty() or lead.is_empty():
		_head_home(sim, call)
		return
	# Walk to the office (a step every other tick), side by side.
	var spot: Array = Law.desk_spot(office)
	var arrived := true
	for i in range(call.sheriffs.size()):
		var npc: Dictionary = s.residents.get(str(call.sheriffs[i]), {})
		if npc.is_empty(): continue
		if str(npc.get("arrest", {}).get("phase", "")) in ["cuff", "lift", "escort", "book", "lock"]: arrived = false; continue
		npc.reinforcing.role = "visiting"
		var goal: Array = [spot[0] - 2 - i, spot[1] + 1]
		if not World.walkable(s, goal): goal = spot
		var cell: Array = s.entities[str(npc.id)].cell
		if cell == goal: continue
		arrived = false
		npc.status = "Walking to the sheriff's office"
		if s.tick % 2 == 0:
			if npc.get("path", []).is_empty() or s.tick - int(npc.get("path_tick", -100)) > 60:
				var route: Dictionary = load("res://sim/movement/navigation.gd").request_path(s, cell, goal)
				npc.path = route.path if route.ok else []
				npc.path_tick = s.tick
			if not npc.path.is_empty(): s.entities[str(npc.id)].cell = npc.path.pop_front()
			elif s.tick - int(call.since) > 1200: s.entities[str(npc.id)].cell = goal.duplicate()   # can't find the way: there now
	if not arrived: return
	# The talk: a line every TALK_EVERY ticks, the helper and the town's own sheriff in turn.
	var lines: Array = TALK if bool(call.get("caught", false)) or Law.in_custody(s) else ASK
	var host: Dictionary = {}
	for npc in Law.sheriffs(s, int(call.town)):
		if npc.get("reinforcing", {}).is_empty(): host = npc; break
	var index: int = int(call.talk)
	if index >= lines.size():
		if s.tick - int(call.get("talk_tick", 0)) >= TALK_EVERY: _head_home(sim, call)
		return
	if s.tick - int(call.get("talk_tick", -10000)) < TALK_EVERY: return
	var who: Dictionary = lead if str(lines[index][0]) == "helper" or host.is_empty() else host
	Law._say(sim, int(who.id), str(lines[index][1]))
	for id in call.sheriffs:
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty(): npc.status = "Talking with the sheriff"
	call.talk = index + 1
	call.talk_tick = s.tick

static func _head_home(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var home_gate: Array = load("res://sim/world/road_planner.gd").town_gate(s, s.settlements[str(call.from)])
	for id in call.sheriffs:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty() or npc.get("reinforcing", {}).is_empty(): continue
		var home: int = int(npc.reinforcing.home)
		npc.settlement = home
		s.entities[str(id)].settlement = home
		npc.reinforcing.role = "returning"
		npc.reinforcing.trip = _trip(s, s.entities[str(id)].cell, home_gate, WALK_TICKS)
		npc.status = "Heading home to %s" % s.settlements[str(home)].name
	call.phase = "returning"
	call.since = s.tick

static func _returning(sim: RefCounted, call: Dictionary) -> void:
	var s: Dictionary = sim.state
	var all_home := true
	for id in call.sheriffs:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty() or npc.get("reinforcing", {}).is_empty(): continue
		var trip: Dictionary = npc.reinforcing.get("trip", {})
		if trip.is_empty(): _release(s, npc); continue
		var at: Array = _along(s, trip)
		s.entities[str(id)].cell = at[0].duplicate()
		if at[1]: _release(s, npc)
		else: all_home = false
	if all_home:
		call.phase = "done"
		call.since = s.tick
