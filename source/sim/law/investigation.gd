extends RefCounted
## Missing people, found bodies, and the sheriff's investigation. A death nobody saw changes nothing
## at first. An hour later the family (or, for someone living alone, a neighbour a few hours later)
## misses them and tells the sheriff, who opens a case: he goes to their house first, then to where
## they were last about, and searches round it. A body anyone stumbles on is reported at once. At
## the body he kneels and works out how they died from their wounds, then asks round the people who
## were near at the time. A witness who saw the stranger is enough: the crime is filed against the
## description they give (law.gd). Only a motive (the dead remembered you hurting them): he'll want
## a word with you (conversation.gd: you can deny it or own up). Nothing: the case stays open. The
## dead are then laid to rest. Cases are listed in the journal. Deterministic; no randomness here.
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Chronicle = preload("res://sim/world/chronicle.gd")
const MISSED_AFTER := 600          # family miss them after an hour
const MISSED_ALONE := 1800         # someone living alone, after three hours
const SEES_BODY := 9.0
const EXAMINE_TICKS := 60
const ASK_TICKS := 30
const SEARCH_RADIUS := 8
const MAX_CASES := 20
const WINDOW := 1200               # who was near in the two hours either side of the death

static func _law() -> GDScript: return load("res://sim/law/law.gd")

static func cases(s: Dictionary) -> Array:
	var law: Dictionary = _law()._law(s)
	if not law.has("cases"): law.cases = []
	return law.cases

static func case_of(s: Dictionary, victim: int) -> Dictionary:
	for c in s.get("law", {}).get("cases", []):
		if int(c.victim) == victim: return c
	return {}

# --- noticing ------------------------------------------------------------------------------------

## Every 60 ticks: the dead who are missed, and the sheriffs at work on cases.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("residents") or not s.has("settlements"): return
	if s.tick % 60 == 0: _missed(sim)
	if s.tick % 30 == 0: _wants_a_word(sim)
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var sheriff: Dictionary = s.residents[key]
		if not sheriff.get("case", {}).is_empty(): _work(sim, sheriff)

static func _missed(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.get("health", 1)) > 0 or int(npc.settlement) == 0 or bool(npc.get("found", false)) or bool(npc.get("buried", false)): continue
		if not case_of(s, int(npc.id)).is_empty() or npc.has("carried_by"): continue
		var since: int = int(npc.get("died_tick", s.tick))
		var family: Array = _family(s, npc)
		var wait: int = MISSED_AFTER if not family.is_empty() else MISSED_ALONE
		if s.tick - since < wait: continue
		var teller: Dictionary = family[0] if not family.is_empty() else _neighbour(s, npc)
		if teller.is_empty() or not teller.get("reporting", {}).is_empty(): continue
		npc.missed = true
		if int(teller.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, teller.job, "REPORTING_MISSING")
		teller.goal = ""
		teller.path = []
		teller.reporting = {"town": int(npc.settlement), "kind": "missing", "victim": int(npc.id), "outfit": {}, "since": s.tick, "path_tick": -1000, "next_step": s.tick}
		teller.status = "Going to the sheriff: %s hasn't come home" % _first(s, int(npc.id))
		_law()._say(sim, int(teller.id), "%s hasn't come home. Something's wrong." % _first(s, int(npc.id)))

static func _family(s: Dictionary, npc: Dictionary) -> Array:
	var result: Array = []
	var household: Dictionary = s.get("households", {}).get(str(npc.get("household", "")), {})
	for id in household.get("members", []):
		var other: Dictionary = s.residents.get(str(id), {})
		if int(id) == int(npc.id) or other.is_empty() or int(other.health) <= 0 or other.occupation == "Child": continue
		if Brawl.knocked(s, other): continue
		result.append(other)
	return result

static func _neighbour(s: Dictionary, npc: Dictionary) -> Dictionary:
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var other: Dictionary = s.residents[key]
		if int(other.settlement) == int(npc.settlement) and int(other.health) > 0 and other.occupation not in ["Child", "Sheriff", "Bandit"] and other.get("sleeping", {}).is_empty() and int(other.id) != int(npc.id):
			return other
	return {}

static func _first(s: Dictionary, id: int) -> String:
	return String(s.entities.get(str(id), {}).get("name", "someone")).split(" ")[0]

## A body found where people pass (carrying.gd): the finder runs to the sheriff (a sheriff who finds
## it starts at once).
static func body_found(sim: RefCounted, npc: Dictionary, finder: Dictionary) -> void:
	var s: Dictionary = sim.state
	if not case_of(s, int(npc.id)).is_empty() and str(case_of(s, int(npc.id)).phase) != "missing": return
	var town: int = int(npc.settlement) if int(npc.settlement) != 0 else int(finder.settlement)
	if finder.occupation == "Sheriff":
		open(sim, town, int(npc.id), "body", finder)
		return
	if not finder.get("reporting", {}).is_empty() or finder.occupation in ["Child", "Bandit"]: return
	if int(finder.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, finder.job, "REPORTING_A_BODY")
	finder.goal = ""
	finder.path = []
	finder.reporting = {"town": town, "kind": "body", "victim": int(npc.id), "outfit": {}, "since": s.tick, "path_tick": -1000, "next_step": s.tick}
	finder.status = "Running to tell the sheriff"

# --- the case ------------------------------------------------------------------------------------

## A sheriff takes the case ("missing": start at the house; "body": go straight to it).
static func open(sim: RefCounted, town: int, victim: int, how: String, sheriff: Dictionary) -> void:
	var s: Dictionary = sim.state
	var c: Dictionary = case_of(s, victim)
	if c.is_empty():
		c = {"id": int(s.get("chronicle_next", 1)) * 1000 + victim, "town": town, "victim": victim, "phase": "", "opened": s.tick, "cause": "", "suspect": 0, "outcome": "", "known_by": how}
		cases(s).append(c)
		while cases(s).size() > MAX_CASES: cases(s).pop_front()
	if str(c.phase) in ["closed", "examine", "questions"]: return
	var dead: Dictionary = s.residents.get(str(victim), {})
	var found: bool = how == "body" or bool(dead.get("found", false))
	c.phase = "to_body" if found else "house"
	c.sheriff = int(sheriff.id)
	load("res://sim/law/sheriff.gd").stand_up(s, sheriff)
	if int(sheriff.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, sheriff.job, "INVESTIGATING")
	sheriff.goal = ""
	sheriff.path = []
	sheriff.case = {"victim": victim, "since": s.tick, "path_tick": -100, "next_step": s.tick, "stops": _stops(s, dead), "stop": 0}
	sheriff.status = ("Looking into %s's death" if found else "Searching for %s") % _first(s, victim)
	_law()._say(sim, int(sheriff.id), ("Show me." if found else "When did you last see %s? I'll go and look." % _first(s, victim)))

## Where to look for someone missing: their house, then where they were last about, then round it.
static func _stops(s: Dictionary, dead: Dictionary) -> Array:
	var stops: Array = []
	var home: Dictionary = s.entities.get(str(dead.get("home", 0)), {})
	if not home.is_empty() and home.has("door"): stops.append(_law().outside_of(s, home))
	# Where they were last about: where they died if anyone was near at the time; otherwise nobody
	# knows, and he looks round the middle of town (a body hidden out of the way stays hidden).
	var last: Array = s.entities[str(s.settlements[str(dead.settlement)].warehouse)].cell if s.get("settlements", {}).has(str(dead.settlement)) else dead.get("died_at", [0, 0])
	for entry in s.get("chronicle", []):
		if str(entry.kind) == "death" and int(entry.victim) == int(dead.id) and not entry.get("witnesses", []).is_empty(): last = entry.cell
	stops.append(last.duplicate())
	for d in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
		var c: Array = [last[0] + d[0] * SEARCH_RADIUS, last[1] + d[1] * SEARCH_RADIUS]
		for r in range(0, 4):
			var near: Array = [c[0] + r, c[1]]
			if World.walkable(s, near): stops.append(near); break
	return stops

static func _work(sim: RefCounted, sheriff: Dictionary) -> void:
	var s: Dictionary = sim.state
	var job: Dictionary = sheriff.case
	var c: Dictionary = case_of(s, int(job.victim))
	if c.is_empty() or int(sheriff.health) <= 0 or Brawl.knocked(s, sheriff) or not sheriff.get("arrest", {}).is_empty():
		sheriff.case = {}
		return
	var dead: Dictionary = s.residents.get(str(c.victim), {})
	var body: Array = s.entities[str(c.victim)].cell
	var me: Array = s.entities[str(sheriff.id)].cell
	match str(c.phase):
		"house", "search":
			# Looking: anywhere along the way, a body in sight is found.
			if not dead.has("carried_by") and Vector2(body[0] - me[0], body[1] - me[1]).length() <= SEES_BODY and Cover.line_clear(s, me, body):
				dead.found = true
				Chronicle.record(s, "body_found", int(c.town), int(sheriff.id), int(c.victim), body)
				_law()._say(sim, int(sheriff.id), "Over here... it's %s." % _first(s, int(c.victim)))
				c.phase = "to_body"
				return
			var stops: Array = job.stops
			if int(job.stop) >= stops.size():
				c.phase = "open"
				c.outcome = "missing"
				sheriff.case = {}
				sheriff.status = "Back on duty"
				_law()._say(sim, int(sheriff.id), "No sign of %s anywhere." % _first(s, int(c.victim)))
				return
			var goal: Array = stops[int(job.stop)]
			if Vector2(goal[0] - me[0], goal[1] - me[1]).length() <= 1.5:
				if str(c.phase) == "house" and int(job.stop) == 0 and job.get("asked_at", -1) < 0:
					job.asked_at = s.tick
					_law()._say(sim, int(sheriff.id), "Has anyone seen %s since this morning?" % _first(s, int(c.victim)))
				if s.tick - int(job.get("asked_at", s.tick)) < ASK_TICKS and int(job.stop) == 0: return
				job.stop = int(job.stop) + 1
				c.phase = "search"
				sheriff.status = "Searching for %s" % _first(s, int(c.victim))
				return
			_walk(s, sheriff, job, goal)
		"to_body":
			if dead.has("carried_by"): return
			if Vector2(body[0] - me[0], body[1] - me[1]).length() <= 1.5:
				c.phase = "examine"
				job.since = s.tick
				sheriff.status = "Examining the body"
				return
			_walk(s, sheriff, job, body)
		"examine":
			if s.tick - int(job.since) < EXAMINE_TICKS: return
			c.cause = cause_of(s, dead)
			_law()._say(sim, int(sheriff.id), "%s. Poor soul." % c.cause.capitalize())
			job.witnesses = _who_was_near(s, dead)
			job.asked = 0
			c.phase = "questions"
			sheriff.status = "Asking around"
		"questions":
			var people: Array = job.witnesses
			if int(job.asked) >= people.size():
				_conclude(sim, sheriff, c, dead)
				return
			var who: Dictionary = s.residents.get(str(people[int(job.asked)]), {})
			if who.is_empty() or int(who.health) <= 0:
				job.asked = int(job.asked) + 1
				return
			var at: Array = s.entities[str(who.id)].cell
			if Vector2(at[0] - me[0], at[1] - me[1]).length() <= 2.0:
				if job.get("asking", -1) < 0:
					job.asking = s.tick
					_law()._say(sim, int(sheriff.id), "Did you see anything when %s died?" % _first(s, int(c.victim)))
				if s.tick - int(job.asking) < ASK_TICKS: return
				job.asking = -1
				job.asked = int(job.asked) + 1
				return
			_walk(s, sheriff, job, at)

static func _walk(s: Dictionary, sheriff: Dictionary, job: Dictionary, goal: Array) -> void:
	if s.tick < int(job.next_step): return
	var me: Array = s.entities[str(sheriff.id)].cell
	if sheriff.path.is_empty() or s.tick - int(job.path_tick) >= 40:
		var route: Dictionary = Nav.request_walk_path(s, me, goal)
		sheriff.path = route.path.slice(1) if route.ok else []
		job.path_tick = s.tick
		if not route.ok:
			job.stop = int(job.get("stop", 0)) + 1   # can't get there: move on
	if not sheriff.path.is_empty():
		var next: Array = sheriff.path.pop_front()
		if World.walkable(s, next) and next != goal: s.entities[str(sheriff.id)].cell = next
	job.next_step = s.tick + 2

## How they died, from the body: the recorded cause and the wounds on them.
static func cause_of(s: Dictionary, dead: Dictionary) -> String:
	var cause: String = str(dead.get("cause", ""))
	var Limbs = load("res://sim/combat/limbs.gd")
	var shot_limb := false
	for limb in ["left_leg", "right_leg", "left_arm", "right_arm"]:
		if Limbs.state(s, int(dead.id), limb) != "ok": shot_limb = true
	match cause:
		"shot": return "shot dead"
		"bled to death": return "bled to death from a wound" + (" in the leg" if shot_limb else "")
		"beaten": return "beaten to death"
		"starved": return "starved"
		"froze": return "froze to death"
		"stabbed": return "stabbed"
	if cause.contains("shot"): return "shot dead"
	if not dead.get("bruises", {}).is_empty(): return "beaten to death"
	return cause if cause != "" else "died, cause unknown"

## Who was near when they died: the witnesses of what happened to them around that time.
static func _who_was_near(s: Dictionary, dead: Dictionary) -> Array:
	var died: int = int(dead.get("died_tick", s.tick))
	var people: Array = []
	for entry in s.get("chronicle", []):
		if absi(int(entry.tick) - died) > WINDOW: continue
		if int(entry.victim) != int(dead.id) and str(entry.kind) not in ["murder", "shooting", "assault", "theft"]: continue
		for id in entry.get("witnesses", []):
			if int(id) != int(dead.id) and not int(id) in people and s.residents.has(str(id)) and int(s.residents[str(id)].health) > 0: people.append(int(id))
	people.sort()
	return people.slice(0, 3)

## The verdict: a witness saw the stranger do it (filed); a motive (he'll want a word); or open.
static func _conclude(sim: RefCounted, sheriff: Dictionary, c: Dictionary, dead: Dictionary) -> void:
	var s: Dictionary = sim.state
	var died: int = int(dead.get("died_tick", s.tick))
	var seen: Dictionary = {}
	for entry in s.get("chronicle", []):
		if int(entry.victim) != int(dead.id) or int(entry.actor) != int(s.player): continue
		if absi(int(entry.tick) - died) > WINDOW or str(entry.kind) not in ["murder", "shooting", "assault"]: continue
		if not entry.get("witnesses", []).is_empty(): seen = entry
	var outlaw: bool = int(dead.get("bandit", 0)) != 0
	if outlaw:
		c.outcome = "outlaw"
		_law()._say(sim, int(sheriff.id), "One of the bandits. Nobody will miss him.")
	elif not seen.is_empty():
		c.outcome = "solved"
		c.suspect = int(s.player)
		var knew_face: bool = false
		for id in seen.witnesses:
			if bool(s.residents.get(str(id), {}).get("knows_name", false)): knew_face = true
		_law().file(s, int(c.town), "murder", seen.get("outfit", {}), knew_face)
		_law()._say(sim, int(sheriff.id), "The stranger did this. I've a description.")
	elif _motive(s, dead):
		c.outcome = "suspect"
		c.suspect = int(s.player)
		_law()._say(sim, int(sheriff.id), "%s had trouble with that stranger. I'll be wanting a word." % _first(s, int(dead.id)))
	else:
		c.outcome = "unsolved"
		_law()._say(sim, int(sheriff.id), "Nobody saw a thing. I'll keep it open.")
	c.phase = "closed" if c.outcome in ["solved", "outlaw"] else "open"
	c.closed = s.tick
	# Laid to rest.
	dead.buried = true
	dead.status = "Laid to rest"
	Chronicle.record(s, "buried", int(c.town), int(sheriff.id), int(dead.id), s.entities[str(dead.id)].cell)
	sheriff.case = {}
	sheriff.status = "Back on duty"

static func _motive(s: Dictionary, dead: Dictionary) -> bool:
	for memory in dead.get("memories", []):
		if int(memory.subject) == int(s.player) and str(memory.kind) in ["assaulted", "robbed", "shot_at", "threatened"]: return true
	return false

# --- talking to the suspect --------------------------------------------------------------------------

## A sheriff who sees the stranger he suspects calls out that he wants a word (once per case).
static func _wants_a_word(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("player") or not s.has("law"): return
	var me: Array = s.entities[str(s.player)].cell
	for c in s.law.get("cases", []):
		if str(c.outcome) != "suspect" or bool(c.get("called", false)): continue
		for sheriff in _law().sheriffs(s, int(c.town)):
			var at: Array = s.entities[str(sheriff.id)].cell
			if Vector2(at[0] - me[0], at[1] - me[1]).length() > 8.0 or not Cover.line_clear(s, at, me): continue
			c.called = true
			_law()._say(sim, int(sheriff.id), "You there. I want a word about %s's death." % _first(s, int(c.victim)))
			s.player_control.notice = "%s wants a word with you about %s's death. Talk to him." % [s.entities[str(sheriff.id)].name, _first(s, int(c.victim))]
			break

## An open case where you're the one he wants a word with, in this sheriff's town.
static func suspect_case(s: Dictionary, sheriff: Dictionary) -> Dictionary:
	for c in s.get("law", {}).get("cases", []):
		if str(c.outcome) == "suspect" and int(c.suspect) == int(s.player) and int(c.town) == int(sheriff.settlement) and not bool(c.get("talked", false)): return c
	return {}

## "I had nothing to do with it" (believed, unless your story doesn't hold up) or owning up.
static func answer(sim: RefCounted, sheriff: Dictionary, confess: bool) -> String:
	var s: Dictionary = sim.state
	var c: Dictionary = suspect_case(s, sheriff)
	if c.is_empty(): return ""
	c.talked = true
	var name: String = _first(s, int(c.victim))
	if confess:
		c.outcome = "solved"
		c.phase = "closed"
		_law().file(s, int(c.town), "murder", {}, true)
		load("res://sim/law/notoriety.gd").turn_in(sim, sheriff)
		return "...Then you'll hang up your gun and come with me. Coming clean counts for something."
	# A denial holds unless people saw you two fight that day.
	var dead: Dictionary = s.residents.get(str(c.victim), {})
	var fought: bool = false
	for entry in s.get("chronicle", []):
		if int(entry.victim) == int(c.victim) and int(entry.actor) == int(s.player) and absi(int(entry.tick) - int(dead.get("died_tick", 0))) <= WINDOW and not entry.get("witnesses", []).is_empty(): fought = true
	if fought:
		c.outcome = "solved"
		c.phase = "closed"
		_law().file(s, int(c.town), "murder", {}, true)
		return "Funny. Folks saw you two at it that very day. You're under arrest."
	return "Hm. Maybe. But I've got my eye on you, stranger. Don't leave the valley."
