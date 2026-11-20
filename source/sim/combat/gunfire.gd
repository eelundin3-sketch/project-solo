extends RefCounted
## What firing a gun in town sets off. The player's shots raise an *alert* in the nearest town:
##   engage   shots are being fired. Sheriffs take cover and fight in a cycle: hide (and reload),
##            peek out, fire, back to cover. They shout for the player to drop the weapon and try
##            to wound; their shots can hit the player (see wounds.gd).
##   hold     the player stopped firing but still has the gun up: sheriffs hold at gunpoint.
##   arrest   the player stopped and put the weapon away (or went down): the lead sheriff arrests them.
##   lethal   the player fired again after stopping: sheriffs shoot to kill until it is over.
## Villagers who see or hear it take cover (fear.gd). Everything is plain data in `law.alert[town]`.
const Cover = preload("res://sim/combat/cover.gd")
const Wounds = preload("res://sim/combat/wounds.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const World = preload("res://sim/world/world_db.gd")
const STOP_TICKS := 60            # this long without a shot counts as having stopped
const HEAR_RANGE := 45.0          # sheriffs this close respond
const SHOOT_RANGE := 12.0
const FIRE_EVERY := 38            # ticks between a sheriff's shots from cover
const AIM_TICKS := 9
const HIDE_TICKS := 16
const RELOAD_TICKS := 60
const MAGAZINE := 4
const WOUND_STRENGTH := 1.45
const KILL_STRENGTH := 4.0
const WOUND_HIT_CHANCE := 38
const KILL_HIT_CHANCE := 62
const COVER_SEARCH := 8
const ADVANCE_BEYOND := 8.0       # farther than this from the gunman, a sheriff works closer for a better shot
const SHOTS_BEFORE_ADVANCE := 2   # shots from one cover before moving up, when still too far
const ADVANCE_STEP_TICKS := 3     # moving between covers is slow and low: a step every third tick
const SAFE_AFTER_SHOT := 15       # only move while the gunman has not fired for this long (or is reloading)
const Bleeding = preload("res://sim/combat/bleeding.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")

static func _law(s: Dictionary) -> Dictionary:
	if not s.has("law"): s.law = {"wanted": {}}
	if not s.law.has("alert"): s.law.alert = {}
	return s.law

static func Law() -> GDScript:
	return load("res://sim/law/law.gd")

## The town the player is in or next to (nearest square within 70 cells), or 0.
static func town_of(s: Dictionary, cell: Array) -> int:
	var Region = load("res://sim/world/region.gd")
	var town: int = Region.of(s, cell)
	return town if town != 0 and Region.gap_squared(s, town, cell) < 70 * 70 else 0

## The town that hears a shot at `origin` (0 when nobody official is in earshot).
static func town_in_earshot(s: Dictionary, origin: Array, heard: int) -> int:
	var nearest: int = 0
	var nearest_gap := 1.0e9
	for town in s.get("settlements", {}).values():
		var store: Array = s.entities[str(town.warehouse)].cell
		var gap: float = Vector2(store[0] - origin[0], store[1] - origin[1]).length()
		if gap < nearest_gap: nearest_gap = gap; nearest = int(town.id)
	if nearest == 0: return 0
	if nearest_gap <= float(heard) + 25.0: return nearest   # in town, or near enough that the town hears it
	for sheriff in Law().sheriffs(s, nearest):
		var cell: Array = s.entities[str(sheriff.id)].cell
		if Vector2(cell[0] - origin[0], cell[1] - origin[1]).length() <= float(heard): return nearest
	return 0

## Those who hear a shot without seeing it: a few nearby look up and say so (once per shot).
static func _heard_by(sim: RefCounted, origin: Array, heard: int) -> void:
	var s: Dictionary = sim.state
	var Cover = load("res://sim/combat/cover.gd")
	var keys: Array = s.get("residents", {}).keys()
	keys.sort()
	var spoken := 0
	for key in keys:
		if spoken >= 2: break
		var npc: Dictionary = s.residents[key]
		if int(npc.health) <= 0 or not npc.get("sleeping", {}).is_empty() or npc.occupation == "Sheriff": continue
		if s.tick < int(npc.get("heard_shot_until", 0)): continue
		var cell: Array = s.entities[key].cell
		var gap: float = Vector2(cell[0] - origin[0], cell[1] - origin[1]).length()
		if gap > float(heard) or gap <= 26.0 and Cover.line_clear(s, origin, cell): continue   # out of earshot, or saw it (fear.gd)
		npc.heard_shot_until = s.tick + 300
		Law()._say(sim, int(npc.id), ["Was that a gunshot?", "Shooting! Somewhere out there...", "Did you hear that?"][sim.random_int("speech", 0, 2)])
		spoken += 1

static func alert_of(s: Dictionary, town: int) -> Dictionary:
	return _law(s).alert.get(str(town), {})

## The player fired. Raises or escalates the town's alert, and tells the villagers.
## A shot is loud: it carries `heard` cells (a rifle further than a shotgun). The nearest town is
## alarmed if the shot is within earshot of the town or of one of its sheriffs (then the sheriffs
## come); out in the wilds, beyond anyone's hearing, nothing happens. People who hear it but can't
## see where it came from look up and say so; only those who SEE it know who fired.
static func on_player_shot(sim: RefCounted, origin: Array, heard: int = 45) -> void:
	var s: Dictionary = sim.state
	if not s.has("law") and not s.has("settlements"): return
	_heard_by(sim, origin, heard)
	var town := town_in_earshot(s, origin, heard)
	if town == 0: return
	var alerts: Dictionary = _law(s).alert
	var alert: Dictionary = alerts.get(str(town), {})
	if alert.is_empty():
		alert = {"phase": "engage", "since": s.tick, "lethal": false, "shots": 0, "stopped_at": 0}
		alerts[str(town)] = alert
		Law().crime(s, town, "discharge", 0)
	elif alert.phase in ["hold", "arrest"]:
		# Fired again after stopping: from here on they shoot to kill.
		alert.phase = "lethal"
		alert.lethal = true
		alert.since = s.tick
	alert.shots = int(alert.shots) + 1
	alert.last_shot = s.tick
	load("res://sim/entities/fear.gd").on_gunshot(sim, town, origin)

## A pellet of the player's hit a person: once per blast, it is a serious crime.
static func on_player_hit(sim: RefCounted, victim: Dictionary) -> void:
	var s: Dictionary = sim.state
	var town: int = int(victim.get("settlement", 0))
	if town == 0: return
	var alert: Dictionary = alert_of(s, town)
	if not alert.is_empty() and int(alert.get("hit_tick", -1)) == s.tick: return
	if not alert.is_empty(): alert.hit_tick = s.tick
	Law().crime(s, town, "shooting", int(victim.id))

# --- the alert, every tick -----------------------------------------------------------------------

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("law") or not s.law.has("alert") or s.law.alert.is_empty(): return
	var player: Array = s.entities[str(s.player)].cell
	var gun: Dictionary = s.get("shotgun", {})
	for key in s.law.alert.keys():
		var alert: Dictionary = s.law.alert[key]
		var town := int(key)
		# Over: the player is locked up, dead, or far away.
		var store: Array = s.entities[str(s.settlements[key].warehouse)].cell
		var far: bool = Vector2(store[0] - player[0], store[1] - player[1]).length() > 95.0
		if Law().in_custody(s) or bool(s.player_control.get("dead", false)) or far or Law().sheriffs(s, town).is_empty():
			_end(s, town)
			continue
		var since_shot: int = s.tick - int(alert.get("last_shot", s.tick))
		match str(alert.phase):
			"lethal":
				# Once it has gone lethal it ends only with the player's hands up (F), custody, death or distance.
				if bool(s.player_control.get("surrender", false)):
					alert.phase = "arrest"
					alert.lethal = false
					alert.stopped_at = s.tick
			"engage":
				if since_shot >= STOP_TICKS:
					alert.phase = "arrest" if (not bool(gun.get("equipped", false)) or Brawl.player_down(s)) else "hold"
					alert.stopped_at = s.tick
					alert.lethal_was = bool(alert.lethal)
			"hold":
				if not bool(gun.get("equipped", false)) or Brawl.player_down(s):
					alert.phase = "arrest"
			"arrest":
				pass
		if Brawl.player_down(s) and alert.phase in ["engage", "hold"] and not bool(alert.lethal):
			alert.phase = "arrest"
		_assign(sim, town, alert, player)

## Gives every nearby sheriff his part: the lead fights or arrests, the others cover.
static func _assign(sim: RefCounted, town: int, alert: Dictionary, player: Array) -> void:
	var s: Dictionary = sim.state
	var lead := 0
	var lead_distance := 1.0e9
	var responders: Array = []
	for npc in Law().sheriffs(s, town):
		var cell: Array = s.entities[str(npc.id)].cell
		var d: float = Vector2(cell[0] - player[0], cell[1] - player[1]).length()
		if d > HEAR_RANGE or Brawl.knocked(s, npc): continue
		var phase: String = str(npc.get("arrest", {}).get("phase", ""))
		if phase in ["cuff", "escort", "book", "lock", "fetch", "unlock", "return"]: continue   # already taking someone in
		responders.append(npc)
		if d < lead_distance and _hands_ok(s, npc):
			lead_distance = d
			lead = int(npc.id)
	alert.lead = lead
	for npc in responders:
		var arrest: Dictionary = npc.get("arrest", {})
		if str(alert.phase) == "arrest" and int(npc.id) == lead:
			if str(arrest.get("phase", "")) != "pursue":
				npc.cover_cycle = {}
				npc.arrest = {"phase": "pursue", "since": s.tick, "path_tick": -100, "announce": "Hands where I can see them! You're under arrest!"}
				npc.goal = ""
				npc.path = []
				npc.status = "Arresting the shooter"
				load("res://sim/law/sheriff.gd").stand_up(s, npc)
			continue
		if arrest.is_empty() or str(arrest.phase) in ["standoff", "approach"] or (str(arrest.phase) == "pursue" and str(alert.phase) != "arrest"):
			load("res://sim/law/sheriff.gd").stand_up(s, npc)
			npc.arrest = {"phase": "engage", "since": s.tick}
			npc.goal = ""
			npc.path = []
			npc.work_path = []
			npc.status = "Facing the gunman"
			npc.cover_cycle = {"phase": "hide", "since": s.tick, "ammo": MAGAZINE, "cover": [], "peek_to": []}
		elif str(arrest.phase) == "engage" and str(alert.phase) == "arrest" and int(npc.id) != lead:
			_stand_down(s, npc)

static func _stand_down(s: Dictionary, npc: Dictionary) -> void:
	npc.arrest = {}
	npc.cover_cycle = {}
	npc.status = "Back on duty"
	npc.work_pause_until = s.tick + 30

static func _end(s: Dictionary, town: int) -> void:
	s.law.alert.erase(str(town))
	for npc in s.get("residents", {}).values():
		if npc.settlement == town and str(npc.get("arrest", {}).get("phase", "")) == "engage": _stand_down(s, npc)

# --- a sheriff under fire: hide, peek, fire, hide --------------------------------------------------

## One tick of a sheriff in the `engage` phase (called from law.gd).
static func engage(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array, gap: float) -> void:
	var s: Dictionary = sim.state
	var alert: Dictionary = alert_of(s, int(npc.settlement))
	if alert.is_empty() or str(alert.phase) == "arrest":
		_stand_down(s, npc)
		return
	if not _hands_ok(s, npc) or Limbs_crawling(s, npc):
		# A shot-up sheriff falls back and stops fighting.
		npc.cover_cycle = {"phase": "hide", "since": s.tick, "ammo": 0, "cover": cell.duplicate(), "peek_to": []}
		return
	var cycle: Dictionary = npc.get("cover_cycle", {})
	if cycle.is_empty():
		cycle = {"phase": "hide", "since": s.tick, "ammo": MAGAZINE, "cover": [], "peek_to": []}
		npc.cover_cycle = cycle
	var lethal: bool = bool(alert.get("lethal", false))
	var holding: bool = str(alert.phase) == "hold"
	npc.status = "Shooting to kill" if lethal else ("Holding the gunman at gunpoint" if holding else "Taking cover and returning fire")
	# Shout now and then.
	if s.tick % 70 == int(npc.id) % 70:
		var line: String = "That's it! No more warnings!" if lethal else ("Put the gun down. Now." if holding else ["Drop the weapon!", "Stop shooting!", "Put it down, I won't ask again!"][(int(npc.id) + s.tick / 70) % 3])
		Law()._say(sim, npc.id, line)
	var age: int = s.tick - int(cycle.since)
	match str(cycle.phase):
		"hide":
			# Make sure there is cover to hide in and a clear shot from its corner.
			if cycle.cover.is_empty() or not Cover.is_cover(s, cycle.cover):
				# Already behind something the gunman cannot see past: stay put and work from here.
				if Cover.is_cover(s, cell) and not Cover.line_clear(s, cell, player, true, false): cycle.cover = cell.duplicate()
				else: cycle.cover = find_cover(s, cell, player)   # caught in the open: get behind something, fast
			if not cycle.cover.is_empty() and cell != cycle.cover:
				_run_to(s, npc, cycle.cover)
				return
			# Hit and bleeding: bind the wound here, behind cover, before anything else.
			if Bleeding.bleeding(npc) and Inventory.amount(s, int(npc.id), "bandage") > 0 and Bleeding.begin(s, npc):
				cycle.phase = "bandage"
				cycle.since = s.tick
				npc.status = "Bandaging a wound behind cover"
				return
			if int(cycle.ammo) <= 0:
				if age >= RELOAD_TICKS:
					cycle.ammo = MAGAZINE
					cycle.since = s.tick
				return   # reloading, safely behind the wall
			if holding:
				return    # no shooting at someone who has stopped
			if age >= HIDE_TICKS:
				var corner: Array = Cover.peek_cell(s, cell, Vector2(player[0] - cell[0], player[1] - cell[1])) if not cycle.cover.is_empty() else cell.duplicate()
				if cycle.cover.is_empty(): corner = cell.duplicate()
				var no_view: bool = corner.is_empty() or not Cover.line_clear(s, corner, player, false, Cover.player_low(s))
				var too_far: bool = Vector2(player[0] - cell[0], player[1] - cell[1]).length() > ADVANCE_BEYOND and int(cycle.get("shots_here", 0)) >= SHOTS_BEFORE_ADVANCE
				if no_view or too_far:
					# Work closer one cover at a time, only while it is safe to move, one sheriff at a time.
					var next: Array = next_cover(s, cell, player)
					if next.is_empty() and no_view: next = find_cover(s, cell, player, true)   # a cover to one side that sees them
					if not next.is_empty() and _may_move(s, alert, npc):
						cycle.phase = "advance"
						cycle.target = next
						cycle.since = s.tick
						alert.mover = int(npc.id)
						alert.mover_until = s.tick + 150
						npc.status = "Moving up to the next cover"
						return
					if no_view:
						cycle.waits = int(cycle.get("waits", 0)) + 1
						cycle.since = s.tick
						if next.is_empty() and int(cycle.waits) >= 3 and _may_move(s, alert, npc):
							# No cover with a view anywhere near: edge closer, still slowly.
							cycle.phase = "advance"
							cycle.target = [player[0] + signi(cell[0] - player[0]) * 6, player[1] + signi(cell[1] - player[1]) * 6]
							cycle.since = s.tick
							alert.mover = int(npc.id)
							alert.mover_until = s.tick + 150
						return
				cycle.peek_to = corner
				cycle.phase = "peek"
				cycle.since = s.tick
		"peek":
			if age >= AIM_TICKS:
				cycle.phase = "fire"
				cycle.since = s.tick
				cycle.shot_done = false
		"fire":
			if not bool(cycle.get("shot_done", false)):
				cycle.shot_done = true
				cycle.ammo = int(cycle.ammo) - 1
				cycle.shots_here = int(cycle.get("shots_here", 0)) + 1
				fire_at_player(sim, npc, cycle.peek_to if not cycle.peek_to.is_empty() else cell, lethal)
			if age >= 8:
				cycle.phase = "hide"
				cycle.since = s.tick
				cycle.peek_to = []
		"advance":
			# Low and slow between covers; back to hiding on arrival (or if it takes too long).
			var arrived: bool = cell == cycle.target
			if arrived or age > 150 or (Bleeding.bleeding(npc) and Inventory.amount(s, int(npc.id), "bandage") > 0):
				cycle.phase = "hide"
				cycle.cover = cycle.target.duplicate() if arrived and Cover.is_cover(s, cycle.target) else []
				cycle.since = s.tick
				cycle.shots_here = 0
				cycle.waits = 0
				if int(alert.get("mover", 0)) == int(npc.id): alert.mover = 0
				return
			npc.status = "Moving up to the next cover"
			if (s.tick + int(npc.id)) % ADVANCE_STEP_TICKS == 0: _creep_to(s, npc, cycle.target)
		"bandage":
			# bleeding.gd ties the bandage; back to the fight once it is done (or interrupted).
			npc.status = "Bandaging a wound behind cover"
			if npc.get("bandaging", {}).is_empty():
				cycle.phase = "hide"
				cycle.since = s.tick

## Moving is safe only while the gunman is quiet (or reloading), and one sheriff moves at a time.
static func _may_move(s: Dictionary, alert: Dictionary, npc: Dictionary) -> bool:
	var quiet: bool = s.tick - int(alert.get("last_shot", -1000)) >= SAFE_AFTER_SHOT or bool(s.get("shotgun", {}).get("reloading", false))
	var mover: int = int(alert.get("mover", 0))
	var free: bool = mover == 0 or mover == int(npc.id) or s.tick > int(alert.get("mover_until", 0))
	return quiet and free

## The next cover towards the gunman: hidden from them, with a corner that sees them, nearer than
## where the sheriff is now (but not on top of them), and a short walk away. [] if there is none.
static func next_cover(s: Dictionary, from: Array, target: Array) -> Array:
	var here: float = Vector2(target[0] - from[0], target[1] - from[1]).length()
	var best: Array = []
	var best_score := 1.0e9
	for dy in range(-COVER_SEARCH, COVER_SEARCH + 1):
		for dx in range(-COVER_SEARCH, COVER_SEARCH + 1):
			if dx == 0 and dy == 0: continue
			var cell: Array = [from[0] + dx, from[1] + dy]
			if not Cover.is_cover(s, cell) or not World.walkable(s, cell): continue
			var look := Vector2(target[0] - cell[0], target[1] - cell[1])
			if look.length() < 4.0 or look.length() > here - 1.5 or look.length() > SHOOT_RANGE + 6.0: continue
			if Cover.line_clear(s, cell, target, true, false): continue   # in the open from where the gunman stands (a sheriff in cover crouches)
			var corner: Array = Cover.peek_cell(s, cell, look)
			if corner.is_empty() or not Cover.line_clear(s, corner, target, false, Cover.player_low(s)): continue
			var score: float = float(absi(dx) + absi(dy)) + look.length() * 0.6
			if score < best_score:
				best_score = score
				best = cell
	if best.is_empty(): return best
	var route = load("res://sim/movement/navigation.gd").request_path(s, from, best)
	return best if route.ok and route.path.size() <= 14 else []

## One careful step along a path (no running).
static func _creep_to(s: Dictionary, npc: Dictionary, goal: Array) -> void:
	var arrest: Dictionary = npc.arrest
	if s.tick - int(arrest.get("path_tick", -100)) >= 12 or npc.path.is_empty():
		var route = load("res://sim/movement/navigation.gd").request_path(s, s.entities[str(npc.id)].cell, goal)
		arrest.path_tick = s.tick
		npc.path = route.path if route.ok else []
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next): s.entities[str(npc.id)].cell = next

static func _hands_ok(s: Dictionary, npc: Dictionary) -> bool:
	return load("res://sim/combat/limbs.gd").arms_ok(s, int(npc.id)) == 2

static func Limbs_crawling(s: Dictionary, npc: Dictionary) -> bool:
	return load("res://sim/combat/limbs.gd").crawling(s, int(npc.id))

static func _run_to(s: Dictionary, npc: Dictionary, goal: Array) -> void:
	var arrest: Dictionary = npc.arrest
	if s.tick - int(arrest.get("path_tick", -100)) >= 8 or npc.path.is_empty():
		var route = load("res://sim/movement/navigation.gd").request_path(s, s.entities[str(npc.id)].cell, goal)
		arrest.path_tick = s.tick
		npc.path = route.path if route.ok else []
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next): s.entities[str(npc.id)].cell = next
		npc.running_tick = s.tick

## The best cover near `from` against a shooter at `target`: a cover cell the shooter cannot see,
## with a corner from which the shooter can be seen. [] if there is none.
static func find_cover(s: Dictionary, from: Array, target: Array, avoid_current: bool = false) -> Array:
	var best: Array = []
	var best_score := 1.0e9
	for dy in range(-COVER_SEARCH, COVER_SEARCH + 1):
		for dx in range(-COVER_SEARCH, COVER_SEARCH + 1):
			var cell: Array = [from[0] + dx, from[1] + dy]
			if avoid_current and dx == 0 and dy == 0: continue
			if not Cover.is_cover(s, cell): continue
			var look: Vector2 = Vector2(target[0] - cell[0], target[1] - cell[1])
			if look.length() > SHOOT_RANGE or look.length() < 3.0: continue
			if Cover.line_clear(s, cell, target, true, false): continue   # still in the open: not cover from them
			var corner: Array = Cover.peek_cell(s, cell, look)
			if corner.is_empty() or not Cover.line_clear(s, corner, target, false, Cover.player_low(s)): continue
			var score: float = float(absi(dx) + absi(dy)) + look.length() * 0.2
			if score < best_score:
				best_score = score
				best = cell
	return best

## A sheriff's shot from `from` at the player. It must have a clear line, and the player must be
## exposed (not behind cover). Hits are rolled with a seeded draw.
static func fire_at_player(sim: RefCounted, npc: Dictionary, from: Array, lethal: bool) -> void:
	var s: Dictionary = sim.state
	var player: Array = s.entities[str(s.player)].cell
	var distance: float = Vector2(player[0] - from[0], player[1] - from[1]).length()
	var direction: Array = [signi(player[0] - from[0]), signi(player[1] - from[1])]
	var shot: Array = [roundi((player[0] - from[0]) / maxf(distance, 0.01) * 1000.0), roundi((player[1] - from[1]) / maxf(distance, 0.01) * 1000.0)]
	Brawl.event(s, "gunshot", from, shot)
	if s.has("shotgun"):
		s.shotgun.effects.append({"kind": "blast", "cell": from.duplicate(), "tick": s.tick, "dir": shot.duplicate()})
	npc.shot_tick = s.tick
	npc.shot_dir = shot
	if distance > SHOOT_RANGE or not Cover.line_clear(s, from, player, false, Cover.player_low(s)) or not Cover.player_exposed(s):
		if s.has("shotgun"): s.shotgun.effects.append({"kind": "wall", "cell": Cover.first_block(s, from, player, Cover.player_low(s)) if not Cover.first_block(s, from, player, Cover.player_low(s)).is_empty() else player.duplicate(), "tick": s.tick, "dir": shot.duplicate()})
		return
	var chance: int = (KILL_HIT_CHANCE if lethal else WOUND_HIT_CHANCE) - int(maxf(0.0, distance - 5.0) * 3.0)
	if sim.random_int("gunfire", 0, 99) < chance:
		Wounds.shoot(sim, int(s.player), player, direction, KILL_STRENGTH if lethal else WOUND_STRENGTH, lethal)
		s.player_control.notice = "%s shoots you!" % s.entities[str(npc.id)].name
	elif s.has("shotgun"):
		s.shotgun.effects.append({"kind": "ground", "cell": [player[0] + sim.random_int("gunfire", -1, 1), player[1] + sim.random_int("gunfire", -1, 1)], "tick": s.tick, "dir": shot.duplicate()})
