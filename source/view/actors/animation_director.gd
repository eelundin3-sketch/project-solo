extends RefCounted
## Presentation state only. Inventory, work progress and positions remain in Simulation.
const Planner = preload("res://sim/settlement/planner.gd")
const World = preload("res://sim/world/world_db.gd")
const BuildMotion = preload("res://view/actors/build_motion.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Limbs = preload("res://sim/combat/limbs.gd")
const Pace = preload("res://sim/movement/pace.gd")
const Traders = preload("res://sim/economy/traders.gd")
const CELL: float = 24.0
const WALK_CYCLE_METERS := 2.0
const RUN_CYCLE_METERS := 3.25
var actors: Dictionary = {}
var trees: Dictionary = {}
var cues: Array[Dictionary] = []
var time: float = 0.0
var previous_tick: int = -1
var reduced_motion: bool = false
var last_brawl_serial: int = 0
var wind_strength: float = 1.0
var player_aiming: bool = false
var player_ready: bool = false
var player_aim_position: Vector2 = Vector2.ZERO
## How far the clock is between the last tick and the next (0..1), set by the controller each
## frame, so a walking trader can be placed exactly where its schedule has it.
var tick_fraction: float = 0.0
## Trees are tracked only inside this rectangle of cells (set by the world view to what is on
## screen plus a margin). Empty means every tree, which is what headless tests use.
var view_cells: Rect2i = Rect2i()
var tree_pass: int = 0
var tree_pass_view: Rect2i = Rect2i(0, 0, -1, -1)
var tree_pass_tick: int = -1
var tree_serial: int = 0   # bumps whenever a tracked tree falls, empties or dies (shadows repaint)

func reset() -> void:
	actors.clear()
	trees.clear()
	cues.clear()
	time = 0.0
	previous_tick = -1

static func action_for(s: Dictionary, entity: Dictionary, aim_held: bool = false) -> Dictionary:
	var npc: Dictionary = s.get("residents", {}).get(str(entity.id), {})
	var result := {"action": "idle", "phase": -1.0, "target": 0, "target_cell": [], "expected_item": "", "expected_quantity": 0}
	if not npc.is_empty() and int(npc.get("health", 100)) <= 0:
		result.action = "down"
		return result
	# Falling, lying and getting up after a shove or a knockout (resident or player).
	var knock: Dictionary = npc.get("knock", {}) if not npc.is_empty() else (s.get("player_control", {}).get("knock", {}) if entity.kind == "player" else {})
	if not knock.is_empty() and s.tick < int(knock.rise_until):
		result.style = knock.get("style", "back")
		result.side = int(knock.get("side", 1))
		result.fall_dir = knock.get("dir", [0, 0])
		var drop: int = int(knock.get("fall_ticks", Brawl.FALL_TICKS))
		var fall_end: int = int(knock.start) + drop
		if s.tick < fall_end:
			result.action = "fall"
			result.phase = float(s.tick - int(knock.start)) / float(drop)
			result.duration = float(drop) / 10.0
		elif s.tick < int(knock.down_until):
			result.action = "down"
		else:
			result.action = "getup"
			result.rise_ticks = int(knock.get("rise_ticks", Brawl.RISE_TICKS))
			result.phase = float(s.tick - int(knock.down_until)) / float(result.rise_ticks)
		return result
	# Both legs shot out: crawling along the ground.
	if Limbs.crawling(s, int(entity.id)) and (npc.is_empty() or int(npc.get("health", 100)) > 0):
		result.action = "crawl"
		return result
	if int(npc.get("impact_until", 0)) > s.tick:
		result.action = "stagger" if npc.get("impact_kind", "") == "shove" else "hit"
		result.phase = 1.0 - float(npc.impact_until - s.tick) / 12.0
		return result
	# A bandit taking you to the post: hauling you up, then leading you by the arm.
	if not npc.is_empty() and not npc.get("captor", {}).is_empty():
		result.target = s.get("player", 0)
		match str(npc.captor.phase):
			"lift":
				result.action = "lift"
				result.phase = clampf(float(s.tick - int(npc.captor.since)) / 40.0, 0.0, 1.0)
				return result
			"escort":
				result.action = "escort"
				return result
	# A bandit who has given up: hands in the air (bandits.gd morale).
	if not npc.is_empty() and bool(npc.get("surrendered", false)):
		result.action = "surrender"
		return result
	# Anyone else with a gun out (a bandit holding you up or fighting, bandits.gd): the cover cycle
	# if they have one, otherwise the gun up and pointed at whoever they're covering, walking or not.
	if not npc.is_empty() and bool(npc.get("gun_out", false)) and npc.get("arrest", {}).is_empty():
		result.target = int(npc.get("aim_at", s.get("player", 0)))
		var gun_cycle: Dictionary = npc.get("cover_cycle", {})
		if gun_cycle.is_empty():
			result.action = "aim"
		else:
			match str(gun_cycle.get("phase", "hide")):
				"peek": result.action = "aim"
				"fire":
					result.action = "shoot"
					result.phase = clampf(float(s.tick - int(gun_cycle.get("since", s.tick))) / 8.0, 0.0, 1.0)
				"advance": result.action = "gun_carry"
				_: result.action = "reload" if int(gun_cycle.get("ammo", 1)) <= 0 else "gun_carry"
		return result
	# The sheriff making an arrest (law.gd): gun drawn, walking up (pointed at you), cuffing, escorting.
	var arrest: Dictionary = npc.get("arrest", {}) if not npc.is_empty() else {}
	if not arrest.is_empty():
		result.target = s.get("player", 0)
		match str(arrest.phase):
			"standoff": result.action = "aim"
			"approach": result.action = "aim"   # walking up with the gun on you
			"cuff":
				# Over a prisoner on the ground he kneels and holds them down; standing, he cuffs.
				result.action = "pin" if bool(arrest.get("pinned", false)) else "cuff"
				result.phase = clampf(float(s.tick - int(arrest.since)) / 30.0, 0.0, 1.0)
			"lift":
				result.action = "lift"
				result.phase = clampf(float(s.tick - int(arrest.since)) / 40.0, 0.0, 1.0)
			"escort": result.action = "escort"
			"book": result.action = "search" if s.tick - int(arrest.since) < 50 else "idle"   # the pat-down, then the paperwork
			"engage":
				# Hide behind cover, lean out and aim, fire, and reload while hidden.
				var cycle: Dictionary = npc.get("cover_cycle", {})
				match str(cycle.get("phase", "hide")):
					"peek": result.action = "aim"
					"fire":
						result.action = "shoot"
						result.phase = clampf(float(s.tick - int(cycle.get("since", s.tick))) / 8.0, 0.0, 1.0)
					_:
						# Holding a gunman who has stopped: the gun stays on him, even while moving in.
						var holding: bool = str(s.get("law", {}).get("alert", {}).get(str(npc.get("settlement", 0)), {}).get("phase", "")) == "hold"
						result.action = "reload" if int(cycle.get("ammo", 1)) <= 0 else ("aim" if holding else "gun_carry")
			"backup": result.action = "aim"
			"assist": result.action = "aim" if not bool(s.get("player_control", {}).get("restrained", false)) else "gun_carry"
			"pursue": result.action = "combat_idle"
			_: result.action = "idle"
		return result
	# Sitting in a chair (the sheriff at his desk, the governor, drinkers) or on the ground (bandits).
	if not npc.is_empty() and not npc.get("sitting", {}).is_empty() and npc.get("sleeping", {}).is_empty():
		result.action = "cook" if bool(npc.get("cooking", false)) else "sit"
		result.face = npc.sitting.get("face", [0, 1])
		result.sit_ground = bool(npc.sitting.get("ground", false))
		return result
	# A villager binding a wound (bleeding.gd): the same motions as the player's bandaging.
	if not npc.is_empty() and not npc.get("bandaging", {}).is_empty():
		var binding: Dictionary = npc.bandaging
		result.action = "treat"
		result.phase = clampf(float(s.tick - int(binding.since)) / maxf(1.0, float(int(binding.until) - int(binding.since))), 0.0, 1.0)
		result.duration = maxf(0.1, float(int(binding.until) - int(binding.since)) / 10.0)
		result.treat_part = "left_forearm"
		result.treat_kind = "bandage"
		return result
	# The player asleep in a bed.
	if entity.kind == "player" and not s.get("player_control", {}).get("sleeping", {}).is_empty():
		result.action = "rest"
		result.rest_rot = int(s.player_control.sleeping.get("rot", 0))
		return result
	# Tied up at the bandits' camp: sitting on the ground, roped.
	if entity.kind == "player" and not s.get("player_control", {}).get("captive", {}).is_empty():
		# Being walked to the post: hands bound behind the back; there, sat and roped.
		result.action = "tied" if str(s.player_control.captive.get("stage", "tied")) == "tied" else "cuffed"
		return result
	# The player under arrest (hands cuffed behind the back) or giving up (hands raised).
	if entity.kind == "player" and bool(s.get("player_control", {}).get("restrained", false)):
		result.action = "cuffed"
		return result
	if entity.kind == "player" and bool(s.get("player_control", {}).get("surrender", false)):
		result.action = "surrender"
		return result
	# A villager throwing a punch or shove at the player.
	var attack: Dictionary = npc.get("attack", {}) if not npc.is_empty() else {}
	if not attack.is_empty() and s.tick < int(attack.end):
		result.action = attack.kind
		result.target = int(npc.get("brawl", {}).get("target", 0))
		result.phase = clampf(float(s.tick - int(attack.start)) / float(int(attack.end) - int(attack.start)), 0.0, 1.0)
		return result
	if not npc.is_empty() and not npc.get("brawl", {}).is_empty():
		result.target = int(npc.brawl.get("target", 0))
		result.action = "combat_idle"
	if entity.kind == "player" and int(s.get("player_control", {}).get("impact_until", 0)) > s.tick:
		result.action = "stagger" if s.player_control.get("impact_kind", "") == "shove" else "hit"
		result.phase = 1.0 - float(s.player_control.impact_until - s.tick) / 12.0
		return result
	var fighter: Dictionary = s.get("local_combat", {}).get("fighters", {}).get(str(entity.id), {})
	if not fighter.is_empty():
		result.target = fighter.target
		if fighter.health <= 0: result.action = "down"
		elif int(fighter.get("impact_until", 0)) > s.tick: result.action = "hit"
		elif s.tick - fighter.hit_tick < 5: result.action = "hit"
		elif s.tick - fighter.attack_tick < 8: result.action = "shoot" if fighter.weapon == "ranged" else "melee"
		else: result.action = "aim" if fighter.weapon == "ranged" else "combat_idle"
		if result.action in ["shoot", "melee"]:
			result.phase = clampf(float(s.tick - fighter.attack_tick) / 8.0, 0.0, 1.0)
		elif result.action == "hit":
			result.phase = clampf(float(s.tick - fighter.hit_tick) / 5.0, 0.0, 1.0)
		return result
	if entity.kind == "player" and s.get("shotgun", {}).get("equipped", false):
		var gun: Dictionary = s.shotgun
		if aim_held and s.tick - int(gun.last_shot) < 8:
			result.action = "shoot"
			result.phase = clampf(float(s.tick - int(gun.last_shot)) / 8.0, 0.0, 1.0)
		elif gun.reloading:
			result.action = "reload"
			result.phase = float(s.tick % 12) / 12.0
		else:
			result.action = "aim" if aim_held else "gun_carry"
		return result
	if entity.kind == "player":
		var unarmed: Dictionary = s.get("player_control", {}).get("unarmed", {})
		if not unarmed.is_empty() and s.tick < int(unarmed.end):
			result.action = unarmed.kind
			result.style = str(unarmed.get("style", "straight"))
			result.phase = clampf(float(s.tick - unarmed.start) / maxf(1.0, float(unarmed.end - unarmed.start)), 0.0, 1.0)
			return result
	if entity.kind == "player" and not s.get("player_health", {}).get("treatment", {}).is_empty():
		var treatment: Dictionary = s.player_health.treatment
		var started: int = int(treatment.get("start", int(treatment.finish) - 30))
		result.action = "treat"
		result.phase = clampf(float(s.tick - started) / maxf(1.0, float(int(treatment.finish) - started)), 0.0, 1.0)
		result.duration = maxf(0.1, float(int(treatment.finish) - started) / 10.0)
		result.treat_part = str(treatment.part)
		result.treat_kind = str(treatment.action)
		return result
	if entity.kind=="player" and s.get("player_control",{}).get("running",false) and s.get("player_control",{}).get("running_tick",-1)==s.tick:
		result.action="run"
		return result
	if entity.kind=="player" and not s.get("player_control",{}).get("work",{}).is_empty():
		var work: Dictionary=s.player_control.work
		result.action="harvest" if work.kind=="gather" else work.kind; result.target=work.target
		return result
	var job: Dictionary = s.get("jobs", {}).get(str(npc.get("job", 0)), {})
	if not job.is_empty():
		result.target = job.target
		result.expected_item = job.item
		result.expected_quantity = job.quantity
		match job.state:
			"WORKING": result.action = "chop" if job.item == "log" else ("mine" if job.item == "ore" else "harvest")
			"PICKING_UP":
				result.action = "pickup"
				result.phase = clampf(float(job.progress) / 6.0, 0, 1)
			"DEPOSITING":
				result.action = "drop"
				result.phase = clampf(float(job.progress) / 6.0, 0, 1)
	if result.action == "idle":
		for workshop in s.get("workshops", {}).values():
			if workshop.worker == entity.id and workshop.active and workshop.get("enabled",true) and npc.get("hunger",0)<60 and npc.get("fatigue",0)<75 and entity.cell == World.Fixtures.interaction_cell(s,workshop.id) and npc.get("goal", "").is_empty() and npc.get("status", "") == "Sawing logs into planks":
				result.action = "saw"
				result.target = workshop.id
		var status: String = npc.get("status", "")
		var pause_left: int = npc.get("work_pause_until", 0) - s.tick
		if pause_left > 0 and (status.begins_with("Picking up") or status.begins_with("Putting down")):
			result.action = "pickup" if status.begins_with("Picking up") else "drop"
			var duration := 4 if status == "Putting down planks at work" else 6
			result.phase = clampf(1.0 - float(pause_left) / duration, 0.0, 1.0)
			result.duration = float(duration) / 10.0
			if status == "Putting down planks at work":
				for site in s.get("construction", {}).values():
					if site.worker != entity.id or site.done: continue
					result.target_cell = Planner.current_tile(site).get("cell", [])
					break
		elif status.begins_with("Building:"):
			for site in s.get("construction", {}).values():
				if site.worker != entity.id or site.done or site.get("build_phase", "") != "build": continue
				var tile := Planner.current_tile(site)
				if tile.is_empty(): break
				result.action = "build"
				result.target_cell = tile.cell
				result.build_kind = tile.kind
				result.phase = tile.progress
				break
		elif not npc.get("sleeping", {}).is_empty():
			result.action = "rest"
			result.rest_rot = int(npc.sleeping.rot)
		elif status == "Resting at home": result.action = "rest"
		elif status == "Ate from communal stores": result.action = "eat"
	return result

## Where a travelling trader is now: their fractional place along the path from the trip's
## schedule, averaged over half a cell either side so corners are rounded off.
static func trip_point(s: Dictionary, trip: Dictionary, fraction: float) -> Vector2:
	var path: Array = trip.path
	var eta: Array = trip.get("eta", [])
	var elapsed: float = float(s.tick - int(trip.depart_tick)) + fraction
	var u: float
	if eta.size() != path.size():
		u = elapsed / float(Traders.TICKS_PER_CELL)
	else:
		var index: int = clampi(eta.bsearch(int(floor(elapsed)), false) - 1, 0, path.size() - 1)
		if index >= path.size() - 1: u = float(path.size() - 1)
		else:
			var span: float = maxf(1.0, float(int(eta[index + 1]) - int(eta[index])))
			u = float(index) + clampf((elapsed - float(eta[index])) / span, 0.0, 1.0)
	return (_path_at(path, u - 0.5) + _path_at(path, u) + _path_at(path, u + 0.5)) / 3.0 * CELL

static func _path_at(path: Array, u: float) -> Vector2:
	var clamped: float = clampf(u, 0.0, float(path.size() - 1))
	var i: int = mini(int(floor(clamped)), path.size() - 2)
	var a: Array = path[i]
	var b: Array = path[i + 1]
	return Vector2(a[0], a[1]).lerp(Vector2(b[0], b[1]), clamped - float(i))

## Pixel centre of a bed's mattress for its rect (cells) and orientation; matches the bed art.
static func bed_center(rect: Array, rot: int) -> Vector2:
	var corner := Vector2(rect[0], rect[1]) * CELL - Vector2(12, 12)
	return corner + (Vector2(36, 19.5) if rot % 2 == 1 else Vector2(20.5, 35.0))

func update(s: Dictionary, delta: float, paused: bool, speed: int) -> void:
	cues.clear()
	wind_strength = 0.4 + float(s.get("weather", {}).get("wind", 25)) / 100.0
	if previous_tick > s.tick:
		reset()
	var first: bool = previous_tick < 0
	# Fight sounds come from the simulation's event log: a punch, a shove, a body hitting the ground.
	var fight_events: Array = s.get("brawl", {}).get("events", [])
	if first or previous_tick > s.tick: last_brawl_serial = int(s.get("brawl", {}).get("serial", 0))
	for fight_event in fight_events:
		if int(fight_event.serial) <= last_brawl_serial: continue
		last_brawl_serial = int(fight_event.serial)
		var cue_kind: String = {"punch_hit": "punch", "shove_hit": "shove", "fall": "thud", "gunshot": "shot"}.get(fight_event.kind, "")
		if not cue_kind.is_empty(): cues.append({"kind": cue_kind, "position": Vector2(fight_event.cell[0], fight_event.cell[1]) * CELL})
	var dt: float = 0.0 if paused else minf(delta, 0.1) * speed
	time += dt
	_update_trees(s, first)
	var live_ids: Dictionary = {}
	for key in _actor_keys(s):
		var entity: Dictionary = s.entities.get(key, {})
		if entity.is_empty() or not entity.has("cell"):
			continue
		if entity.kind not in ["resident", "player", "raider"]:
			continue
		live_ids[key] = true
		var target := Vector2(entity.cell[0], entity.cell[1]) * CELL
		# A sleeper lies in the middle of the bed's mattress, not on the cell the simulation uses.
		var sleeping_in: Dictionary = s.get("residents", {}).get(key, {}).get("sleeping", {})
		if entity.kind == "player": sleeping_in = s.get("player_control", {}).get("sleeping", {})
		var old_pose: Dictionary = actors.get(key, {})
		if not sleeping_in.get("bed_rect", []).is_empty():
			target = bed_center(sleeping_in.bed_rect, int(sleeping_in.rot))
		elif float(old_pose.get("rest_blend", 0.0)) > 0.25 and old_pose.has("bed_center"):
			target = old_pose.bed_center   # still climbing out of bed
		# A trader on the road walks a schedule (traders.gd eta): place them exactly on it, on a line
		# rounded through the path's corners, so the walk is steady and does not zig-zag.
		var trip: Dictionary = s.get("caravans", {}).get(key, {})
		var on_trip: bool = not trip.is_empty() and bool(trip.get("in_transit", false)) and trip.get("path", []).size() > 1
		if on_trip: target = trip_point(s, trip, 0.0 if paused else tick_fraction)
		var items: Dictionary = s.inventories[key].items
		if entity.kind=="player" and s.has("player_control"):
			items={}
			if s.player_control.held_quantity>0: items[s.player_control.held_item]=s.player_control.held_quantity
		var pose: Dictionary = actors.get(key, {"position": target, "facing": 1.0, "back": false, "heading": PI / 2.0, "gait": 0.0, "action": "idle", "age": 0.0, "items": items.duplicate(), "handling": "", "handling_age": 1.0, "last_item": "", "last_quantity": 0})
		var before: Vector2 = pose.position
		# Villagers sprint exactly when the simulation steps them at a run (see Brawl.chase_pace).
		var run_tick: int = s.get("player_control", {}).get("running_tick", -100) if entity.kind == "player" else int(s.get("residents", {}).get(key, {}).get("running_tick", -100))
		var sprinting: bool = (entity.kind == "player" and run_tick > 0 and run_tick >= s.tick - 1) or (s.get("residents", {}).has(key) and run_tick > 0 and run_tick >= s.tick - 2)
		var jumped: bool = before.distance_to(target) > CELL * 8
		if jumped:
			pose.position = target
		elif not paused:
			# Match the authoritative tile cadence: five walking cells per second,
			# ten sprinting cells per second. A faster interpolation reaches each
			# cell too early and produces a visible stop before the next tick.
			# Follow the authoritative cell at walking/sprinting pace, but speed up in proportion to the
			# gap so diagonal steps (1.41 cells) and fast game speeds never leave the figure far behind.
			# Constant pace while the gap is within one cell (so motion is smooth), plus a catch-up term
			# only for the part of the gap beyond that, which is what diagonals and high game speed produce.
			# The player's walking pace: slower crouched, a little quicker on the roads (pace.gd), as
			# the simulation steps them, so the figure keeps an even stride instead of stop-and-go.
			var walk_pace: float = 5.0
			if entity.kind == "player":
				walk_pace *= lerpf(1.0, 0.667, clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0)) * (1.0 + float(Pace.bonus(s, entity.cell)) / 100.0)
			var follow: float = CELL * dt * lerpf(walk_pace, 10.0, float(pose.get("run_blend", 0.0))) + maxf(0.0, before.distance_to(target) - CELL * 1.05) * dt / 0.1
			if on_trip: follow = maxf(follow, before.distance_to(target))   # the schedule is exact: keep to it
			# Someone knocked off their feet is thrown, not walked: settle the body fast instead of
			# letting it slide on at walking pace while it falls.
			var resident: Dictionary = s.get("residents", {}).get(key, {})
			var thrown: bool = (not resident.is_empty() and Brawl.knocked(s, resident)) or (entity.kind == "player" and Brawl.player_down(s))
			if thrown: follow = maxf(follow, CELL * dt * 18.0)
			var gait_mode: String = Limbs.mode(s, int(entity.id))
			if gait_mode == "crawl": follow = CELL * dt * 1.05
			elif gait_mode == "limp": follow = minf(follow, CELL * dt * 2.7)
			pose.position = before.move_toward(target, follow)
		# At high simulation speed a frame can skip a corner; never interpolate feet
		# through a solid fixture/wall while catching up with authoritative movement.
		if not World.walkable(s,[roundi(pose.position.x/CELL),roundi(pose.position.y/CELL)]):
			pose.position=target
			jumped=true
		var motion: Vector2 = pose.position - before
		pose.moving = motion.length() > 0.01 and not jumped
		# Carried over someone's shoulder: drawn up at shoulder height (carrying.gd).
		var shoulder: float = -20.0 if s.get("residents", {}).get(key, {}).has("carried_by") else 0.0
		pose.shoulder = shoulder
		if entity.kind == "player": pose.look = s.get("player_status", {}).get("look", {})   # beard, dirt, blood (look.gd)
		# Sprint ramp: eases in over about 0.3 s and out over about 0.5 s after shift is released.
		var old_blend: float = float(pose.get("run_blend", 0.0))
		var wanted_blend: float = 1.0 if (sprinting and pose.moving) else 0.0
		pose.run_blend = move_toward(old_blend, wanted_blend, (3.4 if wanted_blend > old_blend else 2.0) * dt)
		pose.run_trend = lerpf(float(pose.get("run_trend", 0.0)), signf(float(pose.run_blend) - old_blend), clampf(dt * 10.0, 0.0, 1.0))
		var old_gait: float = pose.gait
		if pose.moving:
			pose.move_direction = motion.normalized()
			pose.gait += motion.length() / (CELL * lerpf(WALK_CYCLE_METERS, RUN_CYCLE_METERS, float(pose.get("run_blend", 0.0))) * (1.0 - 0.35 * clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0)))
			if absf(motion.x) > 0.05: pose.facing = signf(motion.x)
			pose.back = motion.y < -0.05 and absf(motion.y) > absf(motion.x)
			if floori((old_gait + 0.00001) * 2) != floori((float(pose.gait) + 0.00001) * 2):
				cues.append({"kind": "step", "position": pose.position, "actor": entity.id})
		var is_player: bool = entity.kind == "player"
		var gun_equipped: bool = is_player and s.get("shotgun", {}).get("equipped", false)
		var state_action := action_for(s, entity, is_player and player_aiming)
		# Someone who dies on their feet goes down with the full forward fall rather than snapping flat.
		if state_action.action == "down" and not state_action.has("fall_dir"):
			if not pose.has("dead_since"): pose.dead_since = time - (10.0 if first else 0.0)
			var dying: float = (time - float(pose.dead_since)) / (Brawl.FALL_TICKS / 10.0)
			if dying < 1.0:
				state_action.action = "fall"
				state_action.phase = clampf(dying, 0.0, 1.0)
		elif pose.has("dead_since"):
			pose.erase("dead_since")
		# The inventory: kneel, swing the backpack off onto the ground and go through it; on closing,
		# put it back on and stand. Timed here because it is presentation only.
		if is_player:
			var rummaging: bool = bool(s.get("player_control", {}).get("rummaging", false)) and state_action.action in ["idle", "ready", "gun_carry"]
			if rummaging and not pose.moving:
				pose.rummage_t = float(pose.get("rummage_t", 0.0)) + dt
				pose.pack_up_t = -1.0
				state_action.action = "rummage"
			elif float(pose.get("rummage_t", 0.0)) > 0.0 and not pose.moving:
				pose.pack_up_t = maxf(0.0, float(pose.get("pack_up_t", -1.0))) + dt
				# Packing up takes as long as what had already happened, up to the full sequence.
				var span: float = minf(1.2, float(pose.rummage_t))
				if float(pose.pack_up_t) >= span:
					pose.rummage_t = 0.0
					pose.pack_up_t = -1.0
				else:
					state_action.action = "pack_up"
					pose.pack_up_phase = 1.0 - (span - float(pose.pack_up_t)) / 1.2
			else:
				pose.rummage_t = 0.0
				pose.pack_up_t = -1.0
		# Getting into bed (sit on the edge, swing the legs up, lie back) and out again.
		var resting: bool = state_action.action == "rest"
		pose.rest_blend = move_toward(float(pose.get("rest_blend", 0.0)), 1.0 if resting else 0.0, dt / 1.6)
		if resting:
			pose.last_rest_rot = int(state_action.get("rest_rot", -1))
			if not sleeping_in.get("bed_rect", []).is_empty(): pose.bed_center = target
			if first: pose.rest_blend = 1.0
		elif float(pose.rest_blend) > 0.0 and state_action.action in ["idle", "walk"]:
			state_action.action = "rest"
			state_action.rest_rot = int(pose.get("last_rest_rot", -1))
		var action: String = state_action.action
		var look: Vector2 = motion if pose.moving else Vector2.ZERO
		if action in ["build", "drop"] and not state_action.target_cell.is_empty() and not pose.moving:
			look = Vector2(state_action.target_cell[0] - entity.cell[0], state_action.target_cell[1] - entity.cell[1])
		if action in ["sit", "cook"]:
			var face: Array = state_action.get("face", [0, 1])
			look = Vector2(float(face[0]), float(face[1]))
		if action in ["aim", "shoot", "reload", "melee", "hit", "combat_idle", "chop", "saw", "harvest", "pickup", "punch", "shove", "kick", "mine", "cuff", "pin", "lift", "search", "gun_carry"] and s.entities.has(str(state_action.target)):
			var target_cell: Array = s.entities[str(state_action.target)].cell
			var dx: int = target_cell[0] - entity.cell[0]
			look = Vector2(dx, target_cell[1] - entity.cell[1])
		if entity.kind == "player" and player_aiming:
			var aim_vector: Vector2 = player_aim_position - pose.position
			if aim_vector.length_squared() > 16.0: look = aim_vector
		if entity.kind == "player" and action in ["punch", "shove", "kick"]:
			var strike: Dictionary = s.player_control.unarmed
			look = Vector2(strike.direction[0], strike.direction[1])
		if pose.moving and action in ["combat_idle", "gun_carry"] and entity.kind != "player":
			look = motion
		# A fall goes forward along the direction of the blow (or of the run that ended in a collapse).
		var fall_dir: Array = state_action.get("fall_dir", [0, 0])
		if action in ["fall", "down", "getup"] and fall_dir.size() == 2 and (int(fall_dir[0]) != 0 or int(fall_dir[1]) != 0):
			look = Vector2(int(fall_dir[0]), int(fall_dir[1]))
		if look.length_squared() > 0.0001:
			var desired: float = look.angle()
			# Mouse aim follows exactly; other turns ease across the shortest arc.
			if first or jumped or (entity.kind == "player" and player_aiming):
				pose.heading = desired
			else:
				pose.heading = lerp_angle(float(pose.get("heading", desired)), desired, clampf(dt * 12.0, 0.0, 1.0))
		pose.facing = -1.0 if cos(float(pose.heading)) < 0.0 else 1.0
		pose.back = sin(float(pose.heading)) < -0.35
		pose.aiming = entity.kind == "player" and player_aiming
		pose.bloom = int(s.get("shotgun", {}).get("bloom", 0)) if entity.kind == "player" else 0
		# A useless leg drags; a hurt one (not yet useless) still makes you favour it.
		var hurt_left: bool = Limbs.state(s, int(entity.id), "left_leg") != "ok"
		var hurt_right: bool = Limbs.state(s, int(entity.id), "right_leg") != "ok"
		pose.limp = Limbs.mode(s, int(entity.id)) == "limp" or (hurt_left != hurt_right)
		pose.limp_side = -1 if (Limbs.disabled(s, int(entity.id), "left_leg") or (hurt_left and not hurt_right)) else 1
		var dead_arms: Array = []
		# "right_*" is the figure's side -1 (see the health screen), so the right arm is arms[-1].
		if Limbs.disabled(s, int(entity.id), "right_arm"): dead_arms.append(-1)
		if Limbs.disabled(s, int(entity.id), "left_arm"): dead_arms.append(1)
		pose.dead_arms = dead_arms
		pose.ready = entity.kind == "player" and player_ready
		# An unreadied shotgun, and every sheriff's, hangs from a sling across the back.
		var carried_items: Dictionary = s.inventories.get(key, {}).get("items", {})
		pose.slung = ((int(carried_items.get("shotgun", 0)) + int(carried_items.get("rifle", 0))) > 0 and not (entity.kind == "player" and s.get("shotgun", {}).get("equipped", false))) or s.get("residents", {}).get(key, {}).get("occupation", "") == "Sheriff"
		if bool(s.get("residents", {}).get(key, {}).get("gun_out", false)): pose.slung = false   # the rifle is in his hands
		var status: String = s.get("residents", {}).get(key, {}).get("status", "")
		if status != pose.get("last_status", "") and status == "Ate from communal stores" and not first:
			pose.eat_until = time + 0.8
		pose.last_status = status
		if action == "eat" and time >= float(pose.get("eat_until", 0)):
			action = "idle"
		var item: String = ""
		var quantity: int = 0
		for candidate in ["log", "plank", "food", "bandage", "antiseptic"]:
			if int(items.get(candidate, 0)) > 0:
				item = candidate
				quantity = items[candidate]
				break
		if entity.kind == "player" and int(s.get("player_control", {}).get("carrying", {}).get("id", 0)) != 0:
			quantity = 1   # a body over the shoulder: the carrying walk
		pose.handling_age += dt
		if not first and not paused and pose.items != items:
			var old_total: int = 0
			var new_total: int = 0
			for value in pose.items.values(): old_total += value
			for value in items.values(): new_total += value
			if old_total != new_total:
				pose.handling = "pickup" if new_total > old_total else "drop"
				# An authored pickup/drop may have already played before the transfer.
				pose.handling_age = 1.0 if pose.action == pose.handling else 0.0
				pose.last_item = item if new_total > old_total else pose.get("cargo_item", "")
				pose.last_quantity = quantity if new_total > old_total else pose.get("cargo_quantity", 0)
				cues.append({"kind": "pickup" if new_total > old_total else "drop", "position": pose.position})
		pose.items = items.duplicate()
		pose.cargo_item = item
		pose.cargo_quantity = quantity
		# Explicit handling phases take precedence; other transfers receive a short follow-through.
		if pose.handling_age < 0.5 and action == "idle" and not pose.moving:
			action = pose.handling
			state_action.phase = pose.handling_age / 0.5
		# An armed upper-body pose can play over the walking or running legs.
		var lawman_armed: bool = str(s.get("residents", {}).get(key, {}).get("arrest", {}).get("phase", "")) in ["standoff", "approach", "engage", "backup", "assist"] or bool(s.get("residents", {}).get(key, {}).get("gun_out", false))
		var gun_pose := (gun_equipped or lawman_armed) and action in ["gun_carry", "aim", "reload", "shoot"]
		if pose.moving and not gun_pose and action not in ["punch", "shove", "kick", "hit", "stagger", "down", "fall", "getup", "rest", "cuffed", "escort", "surrender", "cuff", "pin", "lift", "search", "crawl", "sit", "cook", "tied"]:
			action = "run" if sprinting else ("carry" if quantity > 0 else "walk")
		elif entity.kind == "player" and player_ready and action == "idle":
			action = "ready"
		var changed: bool = action != pose.action
		var old_age: float = pose.age
		var old_phase: float = pose.get("phase", 0.0)
		pose.age = (float(state_action.phase) * 0.6 if state_action.phase >= 0 else 0.0) if changed else pose.age + dt
		pose.action = action
		pose.phase = clampf(float(pose.age) / 0.6, 0, 1) if state_action.phase >= 0 else fmod(float(pose.age), 1.0)
		if action in ["punch", "shove", "kick", "stagger", "cuff", "pin", "lift", "shoot", "reload", "melee", "hit", "fall", "getup", "treat"] and state_action.phase >= 0:
			var duration: float = 1.0
			match action:
				"punch": duration = {"hook": 1.1, "uppercut": 1.2, "haymaker": 1.6}.get(str(state_action.get("style", "straight")), 1.0)
				"stagger": duration = 1.2
				"cuff", "pin": duration = 3.0
				"lift": duration = 4.0
				"fall": duration = float(state_action.get("duration", Brawl.FALL_TICKS / 10.0))
				"getup": duration = float(state_action.get("rise_ticks", Brawl.RISE_TICKS)) / 10.0
				"treat": duration = float(state_action.get("duration", 3.0))
				"shoot", "melee": duration = 0.8
				"hit": duration = 0.5 if not s.get("local_combat", {}).get("fighters", {}).get(key, {}).is_empty() else 1.2
			if changed or float(state_action.phase) + 0.25 < float(pose.get("authored_phase", 0.0)):
				pose.age = float(state_action.phase) * duration
			pose.authored_phase = state_action.phase
			# Blend between authoritative ticks; impact remains on its fixed tick.
			pose.phase = clampf(maxf(float(state_action.phase), float(pose.age) / duration), 0.0, 1.0)
		if action == "build":
			var duration: float = Planner.WORK_PER_TILE / 10.0
			if changed: pose.age = float(state_action.phase) * duration
			pose.phase = clampf(pose.age / duration, maxf(0.0, state_action.phase), minf(1.0, state_action.phase + 0.2))
			if not paused and not first and BuildMotion.build_strikes(float(pose.phase)) > BuildMotion.build_strikes(old_phase):
				cues.append({"kind": "build", "position": pose.position})
		elif action in ["pickup", "drop"] and state_action.has("duration"):
			var duration: float = state_action.duration
			if changed: pose.age = float(state_action.phase) * duration
			pose.phase = clampf(maxf(state_action.phase, pose.age / duration), 0.0, 1.0)
		pose.build_kind = state_action.get("build_kind", "")
		if action in ["pickup", "drop"] and state_action.phase < 0:
			pose.phase = clampf(float(pose.age) / 0.6, 0, 1)
		pose.gait_phase = fmod(float(pose.gait), 1.0)
		pose.reduced_motion = reduced_motion
		pose.machine_work = action == "saw" and state_action.target != 0
		if pose.machine_work: pose.back = true
		pose.expected_item = state_action.expected_item
		pose.outfit = Outfits.worn(s, int(entity.id))
		# Crouching eases down in about a third of a second with a small dip past the final
		# height, and rises again a little more slowly, so neither is a snap.
		var wants_sneak: bool = is_player and bool(s.get("player_control", {}).get("crouching", false)) and action not in ["fall", "down", "getup", "treat", "rest"]
		# A sheriff moving up between covers goes low (gunfire.gd "advance").
		if not is_player and str(s.get("residents", {}).get(key, {}).get("cover_cycle", {}).get("phase", "")) == "advance": wants_sneak = true
		# In cover the body is low against the wall; leaning out lifts it a little and shifts it towards the corner.
		var in_cover: bool = false
		var lean_to := Vector2.ZERO
		if entity.kind == "player":
			var control: Dictionary = s.get("player_control", {})
			in_cover = control.has("cover") and not pose.moving
			if control.has("peek"): lean_to = Vector2(control.peek.to[0] - control.peek.from[0], control.peek.to[1] - control.peek.from[1])
		else:
			var cycle: Dictionary = s.get("residents", {}).get(key, {}).get("cover_cycle", {})
			in_cover = not cycle.is_empty() or bool(s.get("residents", {}).get(key, {}).get("fear", {}).get("arrived", false))
			if str(cycle.get("phase", "")) in ["peek", "fire"] and not cycle.get("peek_to", []).is_empty():
				lean_to = Vector2(cycle.peek_to[0] - entity.cell[0], cycle.peek_to[1] - entity.cell[1])
		pose.peek_lean = Vector2(pose.get("peek_lean", Vector2.ZERO)).move_toward(lean_to, dt * 6.0)
		var cover_target: float = 0.0
		if in_cover: cover_target = 0.46 if lean_to != Vector2.ZERO else 0.82
		var sneak_goal: float = 1.0 if wants_sneak else cover_target
		var sneak_raw: float = move_toward(float(pose.get("sneak_raw", 0.0)), sneak_goal, dt * (3.0 if sneak_goal > float(pose.get("sneak_raw", 0.0)) else 2.4))
		pose.sneak_raw = sneak_raw
		var eased: float = smoothstep(0.0, 1.0, sneak_raw)
		pose.sneak = eased + (0.1 * sin(sneak_raw * PI) * sneak_raw if wants_sneak else 0.0)
		# Stamina state of the player: heavy breathing while winded, a labouring run on empty.
		var stamina_state: Dictionary = s.get("player_health", {}) if entity.kind == "player" else s.get("residents", {}).get(key, {})
		var stamina_now: int = int(stamina_state.get("stamina", 100))
		pose.fatigue = clampf(1.0 - float(stamina_now) / 20.0, 0.0, 1.0) if not stamina_state.is_empty() and stamina_now <= 20 else 0.0
		pose.breath = clampf(1.0 - float(stamina_now - 20) / 40.0, 0.35, 1.0) if bool(stamina_state.get("winded", false)) else 0.0
		pose.gun_equipped = gun_equipped
		pose.treat_part = state_action.get("treat_part", "")
		pose.punch_style = str(state_action.get("style", "straight")) if action == "punch" else "straight"
		pose.treat_kind = state_action.get("treat_kind", "")
		pose.fall_style = state_action.get("style", "back")
		pose.rest_rot = state_action.get("rest_rot", -1)
		pose.sit_ground = bool(state_action.get("sit_ground", false)) or action in ["tied", "cook"]
		pose.fall_side = state_action.get("side", 1)
		pose.expected_quantity = state_action.expected_quantity
		if action in ["chop", "mine", "saw", "harvest"] and not paused and not first:
			var period: float = 1.0 if action == "chop" else (0.9 if action == "mine" else (0.6 if action == "saw" else 0.8))
			pose.phase = fmod(float(pose.age) / period, 1.0)
			if not changed and floori((old_age / period - 0.5)) < floori((float(pose.age) / period - 0.5)):
				cues.append({"kind": "chop" if action == "mine" else action, "position": pose.position})
				if action == "chop" and trees.has(str(state_action.target)):
					trees[str(state_action.target)].hit = time
		actors[key] = pose
	for key in actors.keys():
		if not live_ids.has(key): actors.erase(key)
	previous_tick = s.tick

## The people to animate: the player, every resident and any raiders, without walking the
## thousands of trees and buildings in the entity table.
static func _actor_keys(s: Dictionary) -> Array:
	var keys: Array = []
	if s.has("player"): keys.append(str(s.player))
	keys.append_array(s.get("residents", {}).keys())
	for key in s.get("local_combat", {}).get("fighters", {}):
		if not s.get("residents", {}).has(key): keys.append(key)
	return keys

## Tree state for falling and chopping animation. It only changes on a tick, and only the trees
## near the screen are ever drawn, so the pass runs on a new tick or a new view, over the chunks
## the view covers. A tree seen for the first time (or again after being off screen) starts in
## its current state, so a tree felled out of sight lies there already rather than toppling.
var track_trees: bool = true   # off on the map view, where trees are plain dots
func _update_trees(s: Dictionary, first: bool) -> void:
	if not track_trees: return
	if not first and s.tick == tree_pass_tick and view_cells == tree_pass_view: return
	tree_pass += 1
	tree_pass_tick = s.tick
	tree_pass_view = view_cells
	if view_cells.size.x <= 0 or view_cells.size.y <= 0:
		for entity in s.entities.values():
			if entity.get("kind", "") == "tree": _track_tree(s, entity, first)
		return
	var low := World.chunk_coord(view_cells.position.x, view_cells.position.y)
	var high := World.chunk_coord(view_cells.end.x, view_cells.end.y)
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			var chunk: Dictionary = s.world.chunks.get("%d,%d" % [cx, cy], {})
			for id in chunk.get("entities", []):
				var entity: Dictionary = s.entities.get(str(id), {})
				if entity.get("kind", "") != "tree": continue
				if view_cells.has_point(Vector2i(entity.cell[0], entity.cell[1])): _track_tree(s, entity, first)

func _track_tree(s: Dictionary, entity: Dictionary, first: bool) -> void:
	var key: String = str(entity.id)
	var logs: int = s.inventories[key].items.get("log", 0)
	var felled: bool = entity.get("felled", false)
	var tree: Dictionary = trees.get(key, {})
	if tree.is_empty() or int(tree.get("pass", -1)) != tree_pass - 1:
		tree = {"logs": logs, "fall": float(tree.get("fall", -1.0)) if not tree.is_empty() else -1.0, "hit": float(tree.get("hit", -10.0)) if not tree.is_empty() else -10.0, "felled": felled}
	if tree.has("pass") and (bool(tree.get("felled", false)) != felled or (int(tree.get("logs", 0)) > 0) != (logs > 0) or bool(tree.get("dead", false)) != bool(entity.get("dead", false))):
		tree_serial += 1
	if felled and not tree.get("felled", false) and not first:
		tree.fall = time
		cues.append({"kind": "fall", "position": Vector2(entity.cell[0], entity.cell[1]) * CELL})
	tree.felled = felled
	tree.dead = entity.get("dead", false)
	tree.autumn = entity.get("autumn", false)
	tree.logs = logs
	tree.pass = tree_pass
	trees[key] = tree

func tree_pose(id: int, point: Vector2) -> Dictionary:
	var tree: Dictionary = trees.get(str(id), {})
	var wind: float = sin(time * 0.8 + point.x * 0.003) * 0.7 + sin(time * 1.7 + point.y * 0.005 + id * 0.37) * 0.3
	var hit_age: float = time - float(tree.get("hit", -10.0))
	var shake: float = sin(hit_age * 50) * exp(-hit_age * 12) * 3 if hit_age < 0.5 else 0.0
	# 0..1 while the tree is toppling, 1 once it lies on the ground, -1 while it still stands.
	var fall: float = -1.0
	if tree.get("felled", false):
		fall = 1.0 if float(tree.get("fall", -1.0)) < 0 else clampf((time - float(tree.fall)) / 2.1, 0.0, 1.0)
	return {"sway": wind * wind_strength * (0.5 if reduced_motion else 2.5) + shake, "fall": fall, "dead": tree.get("dead", false), "autumn": tree.get("autumn", false)}
