extends RefCounted
## Outlaws in town. Now and then a bandit walks into the nearest town for supplies (and runaways
## from a beaten gang drift in). Anyone who sees one there knows him (the duster and bandana):
## a sheriff who sees him moves at once; a townsperson runs to tell one (witness_reports.gd, kind
## "outlaw"). Two sheriffs close in with their guns on him. Alone in town he usually gives up: he's
## cuffed, walked to the office and locked in the cell for three days, then sent on his way. If he
## fights it's a shootout between people: both sides find cover and trade shots (wounds.gd works on
## anyone), townsfolk run for cover, and he gives up once he's hurt badly enough. Killing him is no
## crime. Deterministic (stream "outlaws").
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Wounds = preload("res://sim/combat/wounds.gd")
const SHERIFF_SEES := 12.0
const TOWNSFOLK_SEE := 10.0
const SURRENDER_CHANCE := 70     # alone; +10 with two sheriffs on him (a `stubborn` one always fights)
const CUFF_TICKS := 30
const SHOT_EVERY := 34
const SHERIFF_HIT := 48          # percent at point blank, less with distance
const OUTLAW_HIT := 34
const GIVES_UP_BELOW := 45       # health at which a fighting outlaw throws down his gun
const JAIL_TICKS := 14400 * 3
const LOITER_TICKS := 600        # an hour in town
const WALK_TICKS := 3            # ticks per cell on the road

static func _law() -> GDScript: return load("res://sim/law/law.gd")
static func _trip(s: Dictionary, from: Array, to: Array) -> Dictionary: return load("res://sim/law/reinforcements.gd")._trip(s, from, to, WALK_TICKS)
static func _along(s: Dictionary, trip: Dictionary) -> Array: return load("res://sim/law/reinforcements.gd")._along(s, trip)

## Away from the camp: on an errand in town, or in jail.
static func away(npc: Dictionary) -> bool:
	return not npc.get("errand", {}).is_empty() or not npc.get("jailed", {}).is_empty() or npc.has("prisoner_of") or bool(npc.get("gone", false))

## The town nearest to `cell` (by its store).
static func nearest_town(s: Dictionary, cell: Array) -> int:
	var best := 0
	var best_gap := 1 << 60
	var keys: Array = s.get("settlements", {}).keys()
	keys.sort()
	for key in keys:
		var store: Array = s.entities[str(s.settlements[key].warehouse)].cell
		var gap: int = (store[0] - cell[0]) * (store[0] - cell[0]) + (store[1] - cell[1]) * (store[1] - cell[1])
		if gap < best_gap: best_gap = gap; best = int(key)
	return best

## Where in `town` an outlaw heads: outside the saloon if there is one, else outside the store.
static func town_spot(s: Dictionary, town: int) -> Array:
	for saloon in World.of_kind(s, "saloon"):
		if int(saloon.get("settlement", 0)) == town: return _law().outside_of(s, saloon)
	var store: Dictionary = s.entities[str(s.settlements[str(town)].warehouse)]
	return _law().outside_of(s, store) if store.has("door") else store.cell.duplicate()

## Sends a bandit off to `town` ("supply": an hour there and back; "drifter": a runaway, longer).
static func send(s: Dictionary, npc: Dictionary, town: int, kind: String) -> bool:
	var from: Array = s.entities[str(npc.id)].cell
	var trip: Dictionary = _trip(s, from, town_spot(s, town))
	if trip.is_empty(): return false
	npc.erase("sitting")
	npc.erase("cooking")
	npc.sleeping = {}
	npc.gun_out = false
	npc.cover_cycle = {}
	npc.path = []
	npc.errand = {"kind": kind, "town": town, "phase": "going", "trip": trip, "since": s.tick}
	npc.status = "Heading into %s" % s.settlements[str(town)].name
	return true

# --- every tick ----------------------------------------------------------------------------------

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("bandits") or not s.has("residents"): return
	for id in s.bandits.members:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty() or bool(npc.get("gone", false)): continue
		if not npc.get("jailed", {}).is_empty():
			_jailed(sim, npc)
			continue
		var errand: Dictionary = npc.get("errand", {})
		if errand.is_empty(): continue
		if int(npc.health) <= 0 or bool(npc.get("dead", false)):
			npc.erase("errand")
			continue
		var entity: Dictionary = s.entities[str(npc.id)]
		match str(errand.phase):
			"going", "returning":
				var where: Array = _along(s, errand.trip)
				entity.cell = where[0].duplicate()
				if bool(where[1]):
					if str(errand.phase) == "going":
						errand.phase = "in_town"
						errand.since = s.tick
						npc.status = "Loitering about town"
					else:
						var leaving: bool = str(errand.kind) == "leaving"
						npc.erase("errand")
						if leaving:
							npc.gone = true          # off the edge of the map: out of the story
							npc.status = "Gone"
						else: npc.status = "Back at camp"
						continue
			"in_town":
				if s.tick % 20 == int(npc.id) % 20:
					var step: Array = [entity.cell[0] + sim.random_int("outlaws", -1, 1), entity.cell[1] + sim.random_int("outlaws", -1, 1)]
					if World.walkable(s, step) and World.inside_building(s, step) == 0: entity.cell = step
				if s.tick - int(errand.since) >= LOITER_TICKS * (3 if str(errand.kind) == "drifter" else 1):
					_head_back(s, npc)
			"duel":
				_outlaw_fights(sim, npc)
		if str(errand.get("phase", "")) in ["going", "in_town", "returning"] and s.tick % 10 == 0 and not bool(errand.get("spotted", false)):
			var town: int = load("res://sim/combat/gunfire.gd").town_of(s, entity.cell)
			if town != 0: _sightings(sim, npc, town)
	# The sheriffs bringing outlaws in.
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var sheriff: Dictionary = s.residents[key]
		if not sheriff.get("collar", {}).is_empty(): _collar(sim, sheriff)

static func _head_back(s: Dictionary, npc: Dictionary) -> void:
	var camp: Array = s.bandits.cell
	var trip: Dictionary = _trip(s, s.entities[str(npc.id)].cell, [camp[0], camp[1] + 2])
	if trip.is_empty():
		npc.erase("errand")
		return
	npc.errand.phase = "returning"
	npc.errand.trip = trip
	npc.status = "Heading back to camp"

## Who sees him: a sheriff moves in himself; a townsperson runs to fetch one.
static func _sightings(sim: RefCounted, bandit: Dictionary, town: int) -> void:
	var s: Dictionary = sim.state
	var at: Array = s.entities[str(bandit.id)].cell
	for sheriff in _law().sheriffs(s, town):
		if not _free(s, sheriff): continue
		var cell: Array = s.entities[str(sheriff.id)].cell
		if Vector2(cell[0] - at[0], cell[1] - at[1]).length() <= SHERIFF_SEES and Cover.line_clear(s, cell, at):
			start(sim, town, bandit, sheriff)
			return
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != town or npc.occupation in ["Sheriff", "Child", "Bandit"] or int(npc.health) <= 0: continue
		if not npc.get("sleeping", {}).is_empty() or not npc.get("reporting", {}).is_empty() or Brawl.knocked(s, npc): continue
		var cell: Array = s.entities[key].cell
		if Vector2(cell[0] - at[0], cell[1] - at[1]).length() > TOWNSFOLK_SEE or not Cover.line_clear(s, cell, at): continue
		_law()._say(sim, int(npc.id), "That's one of the bandits! Fetch the sheriff!")
		if int(npc.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, npc.job, "REPORTING_AN_OUTLAW")
		npc.goal = ""
		npc.path = []
		npc.reporting = {"town": town, "kind": "outlaw", "victim": int(bandit.id), "outfit": {}, "since": s.tick, "path_tick": -1000, "next_step": s.tick}
		npc.status = "Running to tell the sheriff"
		bandit.errand.spotted = true
		return

static func _free(s: Dictionary, sheriff: Dictionary) -> bool:
	return sheriff.get("arrest", {}).is_empty() and sheriff.get("collar", {}).is_empty() and sheriff.get("sleeping", {}).is_empty() \
		and not Brawl.knocked(s, sheriff) and int(sheriff.health) > 0 and not load("res://sim/law/reinforcements.gd").busy(sheriff)

## A townsperson told `sheriff` (witness_reports.gd): if the outlaw is still about, he goes for him.
static func reported(sim: RefCounted, town: int, bandit_id: int, sheriff: Dictionary) -> void:
	var s: Dictionary = sim.state
	var bandit: Dictionary = s.residents.get(str(bandit_id), {})
	if bandit.is_empty() or str(bandit.get("errand", {}).get("phase", "")) not in ["going", "in_town", "returning"]: return
	if not _free(s, sheriff): return
	start(sim, town, bandit, sheriff)

## Two sheriffs close in, guns on him.
static func start(sim: RefCounted, town: int, bandit: Dictionary, lead: Dictionary) -> void:
	var s: Dictionary = sim.state
	var team: Array = [lead]
	var at: Array = s.entities[str(bandit.id)].cell
	var partner: Dictionary = {}
	var best := 1.0e9
	for sheriff in _law().sheriffs(s, town):
		if int(sheriff.id) == int(lead.id) or not _free(s, sheriff): continue
		var cell: Array = s.entities[str(sheriff.id)].cell
		var d: float = Vector2(cell[0] - at[0], cell[1] - at[1]).length()
		if d < best and d < 60.0: best = d; partner = sheriff
	if not partner.is_empty(): team.append(partner)
	for sheriff in team:
		load("res://sim/law/sheriff.gd").stand_up(s, sheriff)
		if int(sheriff.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, sheriff.job, "ARRESTING_AN_OUTLAW")
		sheriff.goal = ""
		sheriff.path = []
		sheriff.work_path = []
		sheriff.collar = {"bandit": int(bandit.id), "lead": int(sheriff.id) == int(lead.id), "phase": "approach", "since": s.tick, "path_tick": -100, "next_step": s.tick, "town": town}
		sheriff.status = "Arresting an outlaw"
	bandit.errand.phase = "held"
	bandit.errand.spotted = true
	bandit.errand.town = town
	bandit.status = "Caught by the law"
	_law()._say(sim, int(lead.id), "You there! Hands where I can see them!")

# --- the sheriffs ----------------------------------------------------------------------------------

static func _collar(sim: RefCounted, sheriff: Dictionary) -> void:
	var s: Dictionary = sim.state
	var c: Dictionary = sheriff.collar
	var bandit: Dictionary = s.residents.get(str(c.bandit), {})
	if int(sheriff.health) <= 0 or Brawl.knocked(s, sheriff):
		_hand_over(s, sheriff)
		return
	if bandit.is_empty() or int(bandit.health) <= 0 or bool(bandit.get("dead", false)):
		_done(sim, int(c.bandit), "dead")
		return
	var me: Array = s.entities[str(sheriff.id)].cell
	var him: Array = s.entities[str(bandit.id)].cell
	var gap: float = Vector2(him[0] - me[0], him[1] - me[1]).length()
	match str(c.phase):
		"approach":
			var stop_at: float = 1.5 if bool(c.lead) else 4.0
			if gap > stop_at:
				if s.tick >= int(c.next_step): _walk(s, sheriff, c, him, 2)
				return
			if not bool(c.lead): return
			if bool(bandit.get("surrendered", false)) or Brawl.knocked(s, bandit):
				c.phase = "cuff"
				c.since = s.tick
				return
			# Face to face: he gives up, or he draws.
			var odds: int = SURRENDER_CHANCE + (10 if _team(s, int(bandit.id)).size() >= 2 else 0)
			if not bool(bandit.get("stubborn", false)) and (int(bandit.health) < 60 or sim.random_int("outlaws", 0, 99) < odds):
				bandit.surrendered = true
				bandit.status = "Hands up"
				_say_bandit(sim, bandit, ["All right, all right! Don't shoot!", "Easy, sheriff. I'm not looking for trouble.", "You got me."])
				c.phase = "cuff"
				c.since = s.tick
			else:
				_say_bandit(sim, bandit, ["You'll never take me alive!", "Not today, lawman!", "Back off!"])
				_start_duel(sim, bandit)
		"cuff":
			if gap > 1.5:
				if s.tick >= int(c.next_step): _walk(s, sheriff, c, him, 2)
				return
			if s.tick - int(c.since) < CUFF_TICKS or Brawl.knocked(s, bandit): return   # cuffed once he's back on his feet
			bandit.surrendered = false
			bandit.cuffed = true
			var office: Dictionary = _law().office_of(s, int(c.town))
			if office.is_empty():
				_done(sim, int(bandit.id), "let_go")
				return
			var route: Dictionary = Nav.request_path(s, me, _law().cell_door(office))
			sheriff.path = route.path.slice(1) if route.ok else []
			c.phase = "escort"
			c.since = s.tick
			_law()._say(sim, int(sheriff.id), "Come along. You've a cell waiting.")
			for other in _team(s, int(bandit.id)):
				if not bool(other.collar.lead): other.collar.phase = "follow"
		"escort":
			if s.tick < int(c.next_step): return
			if sheriff.path.is_empty():
				_lock_up(sim, sheriff, bandit, int(c.town))
				return
			var next: Array = sheriff.path.pop_front()
			if World.walkable(s, next) and next != him:
				s.entities[str(bandit.id)].cell = me.duplicate()   # a step behind him
				s.entities[str(sheriff.id)].cell = next
			c.next_step = s.tick + 3
		"follow":
			# The partner walks along behind, gun on the prisoner.
			if gap > 3.0 and s.tick >= int(c.next_step): _walk(s, sheriff, c, him, 2)
		"duel":
			_sheriff_fights(sim, sheriff, bandit, me, him, gap)

static func _walk(s: Dictionary, sheriff: Dictionary, c: Dictionary, goal: Array, every: int) -> void:
	var me: Array = s.entities[str(sheriff.id)].cell
	if sheriff.path.is_empty() or s.tick - int(c.get("path_tick", -100)) >= 20:
		var route: Dictionary = Nav.request_path(s, me, goal)
		sheriff.path = route.path.slice(1) if route.ok else []
		c.path_tick = s.tick
	if not sheriff.path.is_empty():
		var next: Array = sheriff.path.pop_front()
		if World.walkable(s, next) and next != goal: s.entities[str(sheriff.id)].cell = next
	c.next_step = s.tick + every

static func _team(s: Dictionary, bandit_id: int) -> Array:
	var team: Array = []
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.get("collar", {}).get("bandit", 0)) == bandit_id: team.append(npc)
	return team

## The lead went down: the partner takes over, or the outlaw is free to go.
static func _hand_over(s: Dictionary, sheriff: Dictionary) -> void:
	var bandit_id: int = int(sheriff.collar.bandit)
	var was_lead: bool = bool(sheriff.collar.lead)
	sheriff.collar = {}
	sheriff.cover_cycle = {}
	sheriff.status = "Hurt"
	var team: Array = _team(s, bandit_id)
	if was_lead and not team.is_empty(): team[0].collar.lead = true
	if team.is_empty():
		var bandit: Dictionary = s.residents.get(str(bandit_id), {})
		if not bandit.is_empty() and not bandit.get("errand", {}).is_empty():
			bandit.gun_out = false
			bandit.surrendered = false
			bandit.cuffed = false
			_head_back(s, bandit)

## Into the cell: three days, then he's walked out and sent on his way.
static func _lock_up(sim: RefCounted, sheriff: Dictionary, bandit: Dictionary, town: int) -> void:
	var s: Dictionary = sim.state
	var office: Dictionary = _law().office_of(s, town)
	var spot: Array = _law().cell_spot(office)
	if s.get("player_control", {}).get("jail", {}).get("office", -1) == office.id: spot = [spot[0] + 1, spot[1]]   # you're in there too
	s.entities[str(bandit.id)].cell = spot
	office.cell_open = false
	bandit.cuffed = false
	bandit.erase("errand")
	bandit.jailed = {"office": int(office.id), "town": town, "until": s.tick + JAIL_TICKS, "spot": spot.duplicate()}
	bandit.status = "Locked up in %s" % s.settlements[str(town)].name
	_law()._say(sim, int(sheriff.id), "That's one less of them on the roads.")
	load("res://sim/world/chronicle.gd").record(s, "outlaw_jailed", town, int(sheriff.id), int(bandit.id), spot)
	sim.record("%s jailed an outlaw, %s." % [s.entities[str(sheriff.id)].name, s.entities[str(bandit.id)].name])
	_done(sim, int(bandit.id), "")

## Every sheriff on this outlaw goes back to his day.
static func _done(sim: RefCounted, bandit_id: int, how: String) -> void:
	var s: Dictionary = sim.state
	for sheriff in _team(s, bandit_id):
		sheriff.collar = {}
		sheriff.cover_cycle = {}
		sheriff.path = []
		sheriff.status = "Back on duty"
		sheriff.work_pause_until = s.tick + 30
	var bandit: Dictionary = s.residents.get(str(bandit_id), {})
	if how == "dead" and not bandit.is_empty():
		bandit.erase("errand")
		load("res://sim/world/chronicle.gd").record(s, "outlaw_killed", 0, 0, bandit_id, s.entities[str(bandit_id)].cell)
	elif how == "let_go" and not bandit.is_empty():
		bandit.cuffed = false
		bandit.surrendered = false
		_head_back(s, bandit)

## Locked up: he sits it out, then he's shown out and heads back to his gang.
static func _jailed(sim: RefCounted, bandit: Dictionary) -> void:
	var s: Dictionary = sim.state
	var jail: Dictionary = bandit.jailed
	s.entities[str(bandit.id)].cell = jail.spot.duplicate()
	if s.tick < int(jail.until): return
	var office: Dictionary = s.entities.get(str(jail.office), {})
	bandit.erase("jailed")
	if office.is_empty(): return
	s.entities[str(bandit.id)].cell = _law().outside_of(s, office)
	bandit.errand = {"kind": "banished", "town": int(jail.town), "phase": "in_town", "since": s.tick - LOITER_TICKS, "spotted": true, "trip": {}}
	bandit.status = "Released and sent packing"
	_head_back(s, bandit)

# --- a shootout between people ---------------------------------------------------------------------

static func _start_duel(sim: RefCounted, bandit: Dictionary) -> void:
	var s: Dictionary = sim.state
	bandit.errand.phase = "duel"
	bandit.gun_out = true
	bandit.surrendered = false
	bandit.cover_cycle = {}
	for sheriff in _team(s, int(bandit.id)):
		sheriff.collar.phase = "duel"
		sheriff.collar.since = s.tick
	var at: Array = s.entities[str(bandit.id)].cell
	load("res://sim/entities/fear.gd").on_gunshot(sim, int(bandit.errand.town), at, false)

## A sheriff in the shootout: into cover against the outlaw, then a shot every so often.
static func _sheriff_fights(sim: RefCounted, sheriff: Dictionary, bandit: Dictionary, me: Array, him: Array, gap: float) -> void:
	var s: Dictionary = sim.state
	var c: Dictionary = sheriff.collar
	if bool(bandit.get("surrendered", false)) or Brawl.knocked(s, bandit) or load("res://sim/combat/limbs.gd").crawling(s, int(bandit.id)):
		# He's done: move in and cuff him.
		if not bandit.get("surrendered", false): bandit.surrendered = true
		bandit.gun_out = false
		if bandit.has("errand"): bandit.errand.phase = "held"
		for other in _team(s, int(bandit.id)):
			other.collar.phase = "approach"
		_law()._say(sim, int(sheriff.id), "He's down! Move in!")
		return
	var spot: Array = c.get("cover", [])
	if spot.is_empty() and not bool(c.get("looked", false)):
		c.looked = true
		spot = load("res://sim/combat/gunfire.gd").find_cover(s, me, him)
		c.cover = spot
	if not spot.is_empty() and me != spot:
		if s.tick >= int(c.next_step): _walk_to(s, sheriff, c, spot)
		return
	if gap > 14.0:
		if s.tick >= int(c.next_step): _walk(s, sheriff, c, him, 3)
		return
	if s.tick - int(c.get("last_shot", -1000)) >= SHOT_EVERY + int(sheriff.id) % 7:
		c.last_shot = s.tick
		_shoot(sim, sheriff, me, bandit, him, SHERIFF_HIT, false)

static func _walk_to(s: Dictionary, npc: Dictionary, c: Dictionary, goal: Array) -> void:
	var me: Array = s.entities[str(npc.id)].cell
	if npc.path.is_empty() or s.tick - int(c.get("path_tick", -100)) >= 20:
		var route: Dictionary = Nav.request_path(s, me, goal)
		npc.path = route.path.slice(1) if route.ok else []
		c.path_tick = s.tick
		if not route.ok: c.cover = []
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next): s.entities[str(npc.id)].cell = next
		npc.running_tick = s.tick
	c.next_step = s.tick + 1

## The outlaw in the shootout: into cover, shooting at the nearest sheriff; hurt badly, he gives up;
## with no sheriff left standing he runs for it.
static func _outlaw_fights(sim: RefCounted, bandit: Dictionary) -> void:
	var s: Dictionary = sim.state
	var team: Array = _team(s, int(bandit.id))
	if team.is_empty():
		bandit.gun_out = false
		_head_back(s, bandit)
		return
	if int(bandit.health) < GIVES_UP_BELOW:
		bandit.surrendered = true
		bandit.gun_out = false
		bandit.errand.phase = "held"
		_say_bandit(sim, bandit, ["Enough! I give up!", "Don't shoot! I'm done!"])
		return
	var me: Array = s.entities[str(bandit.id)].cell
	var target: Dictionary = team[0]
	var there: Array = s.entities[str(target.id)].cell
	bandit.aim_at = int(target.id)
	var e: Dictionary = bandit.errand
	if not bool(e.get("looked", false)):
		e.looked = true
		e.cover = load("res://sim/combat/gunfire.gd").find_cover(s, me, there)
	var spot: Array = e.get("cover", [])
	if not spot.is_empty() and me != spot:
		if s.tick >= int(e.get("next_step", 0)): _walk_to(s, bandit, e, spot)
		return
	if s.tick - int(e.get("last_shot", -1000)) >= SHOT_EVERY + 5:
		e.last_shot = s.tick
		_shoot(sim, bandit, me, target, there, OUTLAW_HIT, true)

static func _shoot(sim: RefCounted, shooter: Dictionary, from: Array, target: Dictionary, at: Array, base: int, lethal: bool) -> void:
	var s: Dictionary = sim.state
	var distance: float = Vector2(at[0] - from[0], at[1] - from[1]).length()
	var dir: Array = [roundi((at[0] - from[0]) / maxf(distance, 0.01) * 1000.0), roundi((at[1] - from[1]) / maxf(distance, 0.01) * 1000.0)]
	Brawl.event(s, "gunshot", from, dir)
	if s.has("shotgun"): s.shotgun.effects.append({"kind": "blast", "cell": from.duplicate(), "tick": s.tick, "dir": dir.duplicate()})
	shooter.shot_tick = s.tick
	shooter.shot_dir = dir
	if not Cover.line_clear(s, from, at):
		if s.has("shotgun"):
			var block: Array = Cover.first_block(s, from, at, false)
			s.shotgun.effects.append({"kind": "wall", "cell": block if not block.is_empty() else at.duplicate(), "tick": s.tick, "dir": dir.duplicate()})
		return
	var chance: int = base - int(maxf(0.0, distance - 4.0) * 3.0)
	if sim.random_int("outlaws", 0, 99) < chance:
		Wounds.shoot(sim, int(target.id), at, [signi(at[0] - from[0]), signi(at[1] - from[1])], 1.45, lethal, "" if lethal else "legs")
	elif s.has("shotgun"):
		s.shotgun.effects.append({"kind": "ground", "cell": [at[0] + sim.random_int("outlaws", -1, 1), at[1] + sim.random_int("outlaws", -1, 1)], "tick": s.tick, "dir": dir.duplicate()})

static func _say_bandit(sim: RefCounted, bandit: Dictionary, lines: Array) -> void:
	_law()._say(sim, int(bandit.id), lines[sim.random_int("outlaws", 0, lines.size() - 1)])
