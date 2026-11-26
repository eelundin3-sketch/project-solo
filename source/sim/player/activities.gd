extends RefCounted
## Things you do at home, step by step: a cold drink from the fridge, lying down on the bed to rest,
## sitting on the sofa, and the workouts on the terrace (squat, bench press, deadlift, pull-ups;
## a set of five reps). Each is a timed run of stages kept in `player_control.activity`, so the view
## can draw every step (stepping under the bar, unracking, each rep, racking it again) and it is all
## deterministic and saved. F next to a piece starts it; F again, or moving, stops it, gracefully:
## a bar in your hands goes back on the rack (or down to the floor) first.
const World = preload("res://sim/world/world_db.gd")
const PlayerHouse = preload("res://sim/settlement/player_house.gd")
const REPS := 5
## Stages per activity: [name, ticks] (0 = until you stop). "rep" stages repeat REPS times.
const PLANS := {
	"squat": [["setup", 14], ["unrack", 10], ["walkout", 10], ["rep", 20], ["walkin", 10], ["rerack", 10], ["exit", 8]],
	"bench": [["sit", 10], ["lie", 12], ["grip", 6], ["unrack", 8], ["rep", 20], ["rerack", 8], ["situp", 12], ["stand", 8]],
	"deadlift": [["setup", 8], ["hinge", 12], ["rep", 22], ["release", 10]],
	"pullup": [["jump", 8], ["hang", 8], ["rep", 18], ["drop", 8]],
	"fridge": [["open", 8], ["reach", 8], ["close", 6], ["drink", 20], ["lower", 6]],
	"rest": [["sit", 10], ["swing", 10], ["lie", 0]],
	"sofa": [["sit", 0]],
}
## Stopping early: from these stages, skip to the one that puts things back.
const WIND_DOWN := {"squat": {"walkout": "walkin", "rep": "walkin"}, "bench": {"grip": "situp", "unrack": "rerack", "rep": "rerack"},
	"deadlift": {"hinge": "release", "rep": "release"}, "pullup": {"hang": "drop", "rep": "drop"}, "fridge": {}, "rest": {}, "sofa": {}}
## Which piece each activity uses, and where you stand at it (offset from the piece's top-left).
const PIECES := {"squat_rack": "squat", "bench_press": "bench", "deadlift_platform": "deadlift", "pullup_bar": "pullup", "fridge": "fridge", "bed": "rest", "sofa": "sofa"}
const STANCES := {"squat": [1, 2], "bench": [0, 1], "deadlift": [1, 1], "pullup": [0, 1], "fridge": [0, 1], "rest": [0, 1], "sofa": [1, 0]}
const LABELS := {"squat": "Squat (5 reps)", "bench": "Bench press (5 reps)", "deadlift": "Deadlift (5 reps)", "pullup": "Pull-ups (5 reps)", "fridge": "Take a cold drink", "rest": "Lie down and rest", "sofa": "Sit and relax"}
const WORKOUTS := ["squat", "bench", "deadlift", "pullup"]
const DRINK_EVERY := 600        # one healing drink an hour
const DRINK_HEAL := 12          # damage taken off each hurt part
const SPENT_AT := 80            # fatigue at which you can't train

## Whether the bar is in your hands (so the rack or platform shows empty): the view asks.
const BAR_OUT := {"squat": ["walkout", "rep", "walkin"], "bench": ["rep"], "deadlift": ["hinge", "rep"]}
static func bar_in_hands(kind: String, stage: String, phase: float) -> bool:
	if stage in BAR_OUT.get(kind, []): return true
	if stage == "unrack" and kind in ["squat", "bench"]: return phase > 0.45
	if stage == "rerack" and kind in ["squat", "bench"]: return phase < 0.55
	if stage == "release" and kind == "deadlift": return phase < 0.3   # set down at the floor, then you straighten up
	return false

static func active(s: Dictionary) -> bool:
	return not s.get("player_control", {}).get("activity", {}).is_empty()

static func current(s: Dictionary) -> Dictionary:
	return s.get("player_control", {}).get("activity", {})

## The piece of your house within reach of where you stand that F would use: {"index", "kind"}.
static func nearby(s: Dictionary) -> Dictionary:
	var house: Dictionary = PlayerHouse.house(s)
	if house.is_empty() or not s.has("player"): return {}
	var me: Array = s.entities[str(s.player)].cell
	var best: Dictionary = {}
	var best_gap := 99
	var items: Array = house.get("furniture", [])
	for index in range(items.size()):
		var item: Dictionary = items[index]
		if not PIECES.has(str(item.kind)): continue
		var r: Array = item.rect
		var dx: int = maxi(0, maxi(int(r[0]) - int(me[0]), int(me[0]) - (int(r[0]) + int(r[2]) - 1)))
		var dy: int = maxi(0, maxi(int(r[1]) - int(me[1]), int(me[1]) - (int(r[1]) + int(r[3]) - 1)))
		var gap: int = maxi(dx, dy)
		if gap <= 1 and gap < best_gap:
			best_gap = gap
			best = {"index": index, "kind": PIECES[str(item.kind)]}
	return best

## Why you can't do `kind` now ("" when you can).
static func problem(s: Dictionary, kind: String) -> String:
	if kind in WORKOUTS and int(s.get("player_needs", {}).get("fatigue", 0)) >= SPENT_AT: return "You're spent. Rest first."
	if kind == "fridge" and s.tick - int(s.get("player_status", {}).get("last_cold_drink", -100000)) < DRINK_EVERY: return "You've just had one. Give it an hour."
	if load("res://sim/combat/brawl.gd").player_down(s): return "Get up first."
	return ""

## F at a piece: start what it's for (or stop what you're doing).
static func use(sim: RefCounted) -> bool:
	var s: Dictionary = sim.state
	if active(s):
		stop(s)
		return true
	var here: Dictionary = nearby(s)
	if here.is_empty(): return false
	start(sim, int(here.index), str(here.kind))
	return true

static func start(sim: RefCounted, index: int, kind: String) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var why: String = problem(s, kind)
	if not why.is_empty():
		pc.notice = why
		return
	var house: Dictionary = PlayerHouse.house(s)
	var item: Dictionary = house.furniture[index]
	var stance: Array = STANCES[kind]
	var at: Array = [int(item.rect[0]) + int(stance[0]), int(item.rect[1]) + int(stance[1])]
	if not World.walkable(s, at) and not kind in ["rest", "sofa"]: at = s.entities[str(s.player)].cell.duplicate()   # (on the bed or sofa is fine)
	s.entities[str(s.player)].cell = at
	s.player_path = []
	pc.pending = {}
	pc.running = false
	pc.crouching = false
	if bool(s.get("shotgun", {}).get("equipped", false)): load("res://sim/combat/shotgun.gd").toggle(s)
	pc.activity = {"kind": kind, "index": index, "stage": 0, "rep": 0, "since": s.tick, "stopping": false}
	pc.notice = {"squat": "You step under the bar.", "bench": "You sit on the end of the bench.", "deadlift": "You step up to the bar.",
		"pullup": "You reach for the bar.", "fridge": "You open the fridge.", "rest": "You lie down for a while. F to get up.", "sofa": "You sink into the sofa. F to get up."}[kind]

## A new game begins at home, already doing one of the things there. `choice` picks which (the
## game passes a fresh number each new game; the same choice always gives the same start).
const HOME_STARTS := ["squat", "bench", "deadlift", "pullup", "fridge", "rest", "sofa"]
static func begin_at_home(sim: RefCounted, choice: int) -> String:
	var s: Dictionary = sim.state
	var house: Dictionary = PlayerHouse.house(s)
	if house.is_empty() or not s.has("player"): return ""
	var kind: String = HOME_STARTS[posmod(choice, HOME_STARTS.size())]
	var items: Array = house.get("furniture", [])
	for index in range(items.size()):
		if PIECES.get(str(items[index].kind), "") == kind:
			start(sim, index, kind)
			return kind if active(s) else ""
	return ""

## F again, or moving: wind down (the bar goes back first), or just get up.
static func stop(s: Dictionary) -> void:
	var act: Dictionary = current(s)
	if act.is_empty() or bool(act.get("stopping", false)): return
	act.stopping = true
	var plan: Array = PLANS[act.kind]
	var name: String = str(plan[int(act.stage)][0])
	var to: String = WIND_DOWN.get(act.kind, {}).get(name, "")
	if to != "":
		act.stage = _index_of(plan, to)
		act.since = s.tick
	elif int(plan[int(act.stage)][1]) == 0:
		s.player_control.activity = {}   # resting or sitting: you just get up
		s.player_control.notice = "You get up."
		_step_off(s)

static func _index_of(plan: Array, name: String) -> int:
	for i in range(plan.size()):
		if str(plan[i][0]) == name: return i
	return plan.size() - 1

## The stage you're in and how far through it (0..1): what the view draws.
static func stage_of(s: Dictionary) -> Dictionary:
	var act: Dictionary = current(s)
	if act.is_empty(): return {}
	var plan: Array = PLANS[act.kind]
	var step: Array = plan[int(act.stage)]
	var ticks: int = int(step[1])
	var phase: float = 1.0 if ticks == 0 else clampf(float(s.tick - int(act.since)) / float(ticks), 0.0, 1.0)
	return {"kind": act.kind, "stage": str(step[0]), "phase": phase, "rep": int(act.rep), "index": int(act.index)}

## Every tick.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var act: Dictionary = current(s)
	if act.is_empty(): return
	if load("res://sim/combat/brawl.gd").player_down(s) or bool(s.player_control.get("dead", false)):
		s.player_control.activity = {}
		return
	var plan: Array = PLANS[act.kind]
	var step: Array = plan[int(act.stage)]
	var ticks: int = int(step[1])
	if ticks == 0:
		if act.kind == "rest" and s.tick % 30 == 0: _rest(s)
		if act.kind == "sofa" and s.tick % 30 == 0: _rest(s, true)
		return
	if s.tick - int(act.since) < ticks: return
	if str(step[0]) == "rep":
		act.rep = int(act.rep) + 1
		if int(act.rep) < REPS and not bool(act.stopping):
			act.since = s.tick
			return
	if str(step[0]) == "drink": _drink(s)
	act.stage = int(act.stage) + 1
	act.since = s.tick
	if int(act.stage) >= plan.size(): _finish(sim, act)

## Off the bed or sofa onto the floor beside it.
static func _step_off(s: Dictionary) -> void:
	var me: Array = s.entities[str(s.player)].cell
	if World.walkable(s, me): return
	for r in range(1, 4):
		for d in [[0, 1], [1, 0], [-1, 0], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]:
			var c: Array = [me[0] + d[0] * r, me[1] + d[1] * r]
			if World.walkable(s, c):
				s.entities[str(s.player)].cell = c
				return

static func _finish(sim: RefCounted, act: Dictionary) -> void:
	var s: Dictionary = sim.state
	s.player_control.activity = {}
	_step_off(s)
	if act.kind in WORKOUTS:
		if int(act.rep) >= REPS: _trained(s, str(act.kind))
		else: s.player_control.notice = "You put the bar back after %d rep%s." % [int(act.rep), "" if int(act.rep) == 1 else "s"]

## A full set: fitness, and with it a bigger stamina pool and a little more carrying; tired and thirsty.
static func _trained(s: Dictionary, kind: String) -> void:
	var status: Dictionary = load("res://sim/player/player_status.gd").of(s)
	var fitness: int = mini(100, int(status.get("fitness", 0)) + 1)
	status.fitness = fitness
	var health: Dictionary = s.player_health
	health.stamina_max = 100 + mini(20, fitness / 5)
	var needs: Dictionary = s.get("player_needs", {})
	if not needs.is_empty():
		needs.fatigue = mini(100, int(needs.fatigue) + 6)
		needs.thirst = mini(100, int(needs.thirst) + 5)
		needs.mood = mini(100, int(needs.get("mood", 70)) + 3)
	s.player_control.notice = "%s done: five good reps. Fitness %d." % [{"squat": "Squats", "bench": "Bench press", "deadlift": "Deadlifts", "pullup": "Pull-ups"}[kind], fitness]

## The cold drink: thirst gone, wounds eased, once an hour.
static func _drink(s: Dictionary) -> void:
	var needs: Dictionary = s.get("player_needs", {})
	if not needs.is_empty(): needs.thirst = maxi(0, int(needs.thirst) - 50)
	for part in s.player_health.parts.values():
		part.damage = maxi(0, int(part.damage) - DRINK_HEAL)
	load("res://sim/player/player_status.gd").of(s).last_cold_drink = s.tick
	s.player_control.notice = "Cold and good. You feel better."

## Lying down or sitting back: stress eases, mood lifts, and lying down rests you a little.
static func _rest(s: Dictionary, sitting: bool = false) -> void:
	var needs: Dictionary = s.get("player_needs", {})
	if needs.is_empty(): return
	needs.stress = maxi(0, int(needs.get("stress", 0)) - 2)
	needs.mood = mini(100, int(needs.get("mood", 70)) + 1)
	if not sitting: needs.fatigue = maxi(0, int(needs.fatigue) - 1)

## Extra carrying from fitness, in tenths (encumbrance.gd): +1.0 per 10 fitness, at most +5.0.
static func carry_bonus(s: Dictionary) -> int:
	return mini(50, int(s.get("player_status", {}).get("fitness", 0)) / 10 * 10)
