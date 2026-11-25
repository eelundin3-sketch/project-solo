extends RefCounted
## Fist fights between the player and residents: anger, retaliation, knockdowns, knockouts and
## blood on the ground. Everything is simulation state; the view only reads `state.brawl`
## and each person's `knock`, `attack` and `brawl` records.
const World = preload("res://sim/world/world_db.gd")
const Jobs = preload("res://sim/jobs/job_board.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const BodyHealth = preload("res://sim/combat/body_health.gd")
const Society = preload("res://sim/factions/society.gd")
const Households = preload("res://sim/entities/households.gd")
const FALL_TICKS := 14          # an unforced collapse (and older saves)
## How long the drop itself takes: forced falls are quick. A shove throws you down; running out of
## breath at full tilt pitches you over at running pace; a beating crumples you a little slower.
const FALL_TICKS_BY_KIND := {"fall": 6, "exhaust": 5, "ko": 9}           # the drop to the ground
const SHOVE_LIE_TICKS := 16      # lying stunned after a shove
const KO_TICKS := 420            # lying unconscious after too many blows (about 42 s at 1x)
const RISE_TICKS := 26           # getting back to their feet
const HIT_WINDOW := 700
const ANGER_PUNCH := 55
const ANGER_SHOVE := 55          # a shove irritates exactly as much as a punch
const HOSTILE_AT := 50           # anger at which someone fights back
const PUNCH_DAMAGE := 9
const KICK_DAMAGE := 14           # 1.5x a punch, on someone who is down
const GIVE_UP_DISTANCE := 110.0   # cells from their own town square a chaser is willing to follow
const GIVE_UP_GAP := 60.0         # how far ahead of them you must get before they stop chasing
const RUN_WINDED_AT := 20         # NPC stamina rules mirror the player's (see BodyHealth)
const RUN_RECOVER_AT := 50
const KO_HEALTH := 20            # health below this and the person is out cold
const OFFENCE_MEMORY := 3000     # how long a first offence is remembered (about 5 minutes at 1x)
const BEAT_DAMAGE := 22          # what one punch of a furious beating does to the player's body
const BLEED_TICKS := 900         # a cut keeps bleeding this long unless it is bandaged
const EXHAUST_LIE_TICKS := 26    # lying winded after running the stamina bar dry
const ATTACK_TICKS := 10
const ATTACK_IMPACT := 3
const BLOOD_LIFETIME := 36000    # about 2.5 game days
const MAX_BLOOD := 96
## Where a punch lands, weighted: mostly the face and body, sometimes a raised forearm or hand.
const PLAYER_PARTS: Array[String] = ["head", "head", "head", "upper_torso", "upper_torso", "lower_torso", "right_forearm", "left_forearm", "right_hand", "neck"]
## Body regions for villagers (who have no per-part health): only a blow to the face draws blood.
const NPC_PARTS: Array[String] = ["head", "head", "head", "upper_torso", "upper_torso", "lower_torso", "arm"]

static func _law() -> GDScript:
	return load("res://sim/law/law.gd")

## Cuffed, being walked to a cell, booked or locked up: nobody may shove, hit or knock the player down.
static func in_custody(s: Dictionary) -> bool:
	return s.has("player_control") and (_law().restrained(s) or _law().in_custody(s))

static func _say(sim: RefCounted, speaker: int, topic: String) -> void:
	load("res://sim/entities/speech.gd").say(sim, speaker, topic)

## Villagers tire like the player: running costs a point per cell, rest gives one back every 3 ticks,
## and below 20 they are winded (walking pace) until they have recovered to 50.
static func npc_stamina(s: Dictionary, npc: Dictionary) -> void:
	if not npc.has("stamina"):
		npc.stamina = 100
		npc.winded = false
		npc.running_tick = -100
	var running: bool = int(npc.running_tick) >= s.tick - 1
	if not running and s.tick % 3 == 0: npc.stamina = mini(100, int(npc.stamina) + 1)
	if int(npc.stamina) <= RUN_WINDED_AT: npc.winded = true
	elif int(npc.stamina) >= RUN_RECOVER_AT: npc.winded = false

## One chase step at the pace the chaser can manage: a run (a cell a tick) while far behind and
## not winded, otherwise the same walk the player has (a cell every 2 ticks). True if a step is due.
static func chase_pace(s: Dictionary, npc: Dictionary, gap: float, diagonal: bool = false) -> bool:
	if s.tick < int(npc.get("next_step", 0)): return false
	var can_run: bool = gap > 4.0 and not bool(npc.get("winded", false)) and int(npc.get("stamina", 100)) > 0
	if can_run:
		npc.stamina = int(npc.get("stamina", 100)) - 1
		npc.running_tick = s.tick
		npc.next_step = s.tick + 1
		return true
	npc.next_step = s.tick + 2 + (1 if diagonal else 0)   # the player's walking cadence
	return true

static func initialize(s: Dictionary) -> void:
	if s.has("player_control") and not s.has("brawl"):
		s.brawl = {"blood": [], "events": [], "serial": 0}

static func event(s: Dictionary, kind: String, cell: Array, direction: Array = [0, 0]) -> void:
	if not s.has("brawl"): return
	s.brawl.serial += 1
	s.brawl.events.append({"serial": s.brawl.serial, "kind": kind, "cell": cell.duplicate(), "tick": s.tick, "dir": direction.duplicate()})
	if s.brawl.events.size() > 40: s.brawl.events.pop_front()

static func add_blood(s: Dictionary, cell: Array, direction: Array, size: int = 1) -> void:
	if not s.has("brawl"): return
	s.brawl.blood.append({"cell": cell.duplicate(), "tick": s.tick, "seed": (s.tick * 31 + cell[0] * 17 + cell[1] * 7) % 9973, "dir": direction.duplicate(), "size": size})
	if s.brawl.blood.size() > MAX_BLOOD: s.brawl.blood.pop_front()

static func knocked(s: Dictionary, holder: Dictionary) -> bool:
	var knock: Dictionary = holder.get("knock", {})
	return not knock.is_empty() and s.tick < int(knock.rise_until)

static func player_down(s: Dictionary) -> bool:
	return s.has("player_control") and knocked(s, s.player_control)

## True while a resident is lying down, fighting or mid-attack: other behaviour pauses.
static func busy(s: Dictionary, npc: Dictionary) -> bool:
	return knocked(s, npc) or not npc.get("brawl", {}).is_empty() or not npc.get("attack", {}).is_empty()

## How they go down depends on the blow: knocked backward off a hard hit, pitched forward when
## pushed away from the viewer, spread out by a heavy shove, and curled or slumped when out cold.
static func fall_style(s: Dictionary, cell: Array, kind: String, direction: Array) -> String:
	var seed_value: int = absi(s.tick * 31 + int(cell[0]) * 17 + int(cell[1]) * 7)
	var options: Array
	if kind == "ko":
		options = ["curled", "slump", "back", "front", "side", "sprawl"]
	elif absi(int(direction[1])) > absi(int(direction[0])) and int(direction[1]) < 0:
		options = ["front", "front", "side", "sprawl"]       # pushed away from the viewer: pitches forward
	elif absi(int(direction[1])) > absi(int(direction[0])):
		options = ["back", "back", "sprawl", "side"]          # pushed toward the viewer: falls backward
	else:
		options = ["back", "side", "sprawl", "back", "slump"] # pushed sideways
	return options[seed_value % options.size()]

static func knockdown(s: Dictionary, holder: Dictionary, cell: Array, kind: String, direction: Array = [0, 0], style: String = "") -> void:
	if holder == s.get("player_control", null) and in_custody(s): return   # a prisoner is not pushed about
	var lie: int = KO_TICKS if kind == "ko" else (EXHAUST_LIE_TICKS if kind == "exhaust" else SHOVE_LIE_TICKS)
	var side: int = 1 if int(direction[0]) > 0 else (-1 if int(direction[0]) < 0 else (1 if (s.tick + int(cell[0])) % 2 == 0 else -1))
	var drop: int = int(FALL_TICKS_BY_KIND.get(kind, FALL_TICKS))
	holder.knock = {"kind": kind, "start": s.tick, "fall_ticks": drop, "down_until": s.tick + drop + lie, "rise_until": s.tick + drop + lie + RISE_TICKS,
		"style": style if not style.is_empty() else fall_style(s, cell, kind, direction), "side": side,
		"dir": [signi(int(direction[0])), signi(int(direction[1]))]}
	event(s, "fall", cell, direction)
	if holder == s.get("player_control", null) and s.has("player_health") and not s.player_health.treatment.is_empty():
		s.player_health.treatment = {}
		s.player_health.notice = "Treatment interrupted."

## The player's blow lands on a resident.
static func on_player_hit(sim: RefCounted, npc: Dictionary, victim: Dictionary, kind: String, direction: Array, style: String = "straight") -> void:
	var s: Dictionary = sim.state
	Households.wake(s, npc)
	if npc.job != 0: Jobs.release(s, npc.job, "INTERRUPTED_BY_FIGHT")
	npc.goal = ""
	npc.path = []
	npc.work_path = []
	# Every blow is an offence. The first sends them after the player to shove them down and walk
	# off; a second, while the first is fresh, is answered with a beating.
	if s.tick - int(npc.get("last_offence", -99999)) > OFFENCE_MEMORY: npc.offences = 0
	npc.offences = int(npc.get("offences", 0)) + 1
	npc.last_offence = s.tick
	var was_down: bool = knocked(s, npc)
	npc.anger = mini(100, int(npc.get("anger", 0)) + (ANGER_PUNCH if kind == "punch" else ANGER_SHOVE))
	if kind == "punch":
		npc.health = maxi(0, int(npc.health) - roundi(PUNCH_DAMAGE * float(load("res://sim/combat/unarmed.gd").STYLE_DATA.get(style, {"damage": 1.0}).damage)))
		# Blunt damage: a bruise where the blow lands. A punch to the face can split a lip or bloody a nose.
		var landed: String = NPC_PARTS[sim.random_int("brawl", 0, NPC_PARTS.size() - 1)]
		if style == "uppercut": landed = "head"   # driven up under the chin
		var bruises: Dictionary = npc.get("bruises", {})
		bruises[landed] = int(bruises.get(landed, 0)) + 1
		npc.bruises = bruises
		npc.last_bruise = landed
		if landed == "head": add_blood(s, victim.cell, direction, 1)
		event(s, "punch_hit", victim.cell, direction)
		if int(npc.health) <= 0:
			_law().crime(s, npc.settlement, "murder", npc.id)
			kill(sim, npc, "beaten")
			return
		if int(npc.health) < KO_HEALTH and not was_down:
			knockdown(s, npc, victim.cell, "ko", direction)
			_say(sim, npc.id, "knocked_down")
			npc.status = "Knocked out"
			npc.brawl = {}
			npc.anger = 40
			add_blood(s, victim.cell, direction, 2)
		elif not was_down and style == "haymaker":
			knockdown(s, npc, victim.cell, "fall", direction)   # the finisher puts them on the ground
			_say(sim, npc.id, "knocked_down")
			npc.status = "Flattened by a haymaker"
			event(s, "shove_hit", victim.cell, direction)
		elif not was_down:
			npc.status = "Staggered by a punch"
			npc.impact_kind = "uppercut" if style == "uppercut" else ("hook" if style == "hook" else npc.get("impact_kind", "punch"))
	else:
		if not was_down:
			knockdown(s, npc, victim.cell, "fall", direction)
			_say(sim, npc.id, "knocked_down")
		npc.status = "Knocked to the ground"
		event(s, "shove_hit", victim.cell, direction)
	if s.has("factions"): Society.remember(s, npc.id, "assault", s.player, "The traveller struck me.", -25)
	_law().crime(s, npc.settlement, "assault_sheriff" if npc.occupation == "Sheriff" else "assault", npc.id)
	if npc.occupation == "Sheriff":
		npc.brawl = {}
		return   # the sheriff arrests rather than brawls (law.gd)
	var mode := "kill" if int(npc.offences) >= 3 else ("beat" if int(npc.offences) >= 2 else "shove")
	if not npc.get("brawl", {}).is_empty(): npc.brawl.mode = mode
	# Not everyone hits back. By temperament (fixed per person): some fight, most confront you and
	# then fetch the sheriff, the timid flee and call for help.
	var temper: String = temperament(npc)
	if temper != "fighter" and npc.get("brawl", {}).is_empty():
		npc.anger = mini(int(npc.anger), HOSTILE_AT - 1)   # not getting up swinging either
		var report: Dictionary = npc.get("reporting", {})
		if temper == "timid":
			_law()._say(sim, npc.id, ["Help! Somebody help me!", "Leave me alone! Help!", "Sheriff! Sheriff!"][int(npc.id) % 3])
			if report.is_empty() and not knocked(s, npc): load("res://sim/entities/fear.gd")._scare(sim, npc, s.entities[str(s.player)].cell)
			npc.status = "Fleeing from the traveller"
			s.player_control.notice = "%s backs away from you, calling for help." % s.entities[str(npc.id)].name
		elif int(npc.offences) >= 2 and not report.is_empty():
			report.erase("hold_until")      # hit again: off to the sheriff now
			_law()._say(sim, npc.id, "That's it! I'm getting the sheriff!")
			s.player_control.notice = "%s runs off to fetch the sheriff." % s.entities[str(npc.id)].name
		else:
			_law()._say(sim, npc.id, ["Hey! What do you think you're doing?!", "What's the matter with you?!", "Have you lost your mind, stranger?!"][int(npc.id) % 3])
			if not report.is_empty():
				report.hold_until = s.tick + CONFRONT_TICKS   # back off now, or they go for the sheriff
			npc.status = "Confronting the traveller"
			s.player_control.notice = "%s stands up to you. Back off, or they'll fetch the sheriff." % s.entities[str(npc.id)].name
		return
	if temper == "fighter" and not npc.get("reporting", {}).is_empty(): npc.reporting = {}   # fights instead of running
	if int(npc.anger) >= HOSTILE_AT and not knocked(s, npc):
		if npc.get("brawl", {}).is_empty():
			engage(s, npc, mode)
			_say(sim, npc.id, "angry_beat" if mode != "shove" else "angry_first")
			s.player_control.notice = ("%s is furious and comes at you!" if mode != "shove" else "%s is angry and storms after you!") % s.entities[str(npc.id)].name

## How someone takes a blow: "fighter" hits back (more of the heavy trades), "timid" flees and
## calls for help, "confront" (most people) stands up to you, then fetches the sheriff.
const HEAVY_TRADES := ["Blacksmith", "Sawyer", "Woodsman", "Miner"]
const CONFRONT_TICKS := 40
static func temperament(npc: Dictionary) -> String:
	if npc.get("occupation", "") == "Child": return "timid"
	var roll: int = posmod(int(npc.id) * 37 + 11, 100)
	var fighters: int = 30 + (20 if npc.get("occupation", "") in HEAVY_TRADES else 0)
	if roll < fighters: return "fighter"
	if roll < fighters + 20: return "timid"
	return "confront"

## Turns a resident hostile toward the player: they drop their work and fight until it burns out.
static func engage(s: Dictionary, npc: Dictionary, mode: String = "shove") -> void:
	if in_custody(s): return   # nobody starts on a prisoner
	Households.wake(s, npc)
	if npc.job != 0: Jobs.release(s, npc.job, "INTERRUPTED_BY_FIGHT")
	npc.goal = ""
	npc.path = []
	var town: Dictionary = s.settlements.get(str(npc.settlement), {})
	var home: Array = s.entities[str(town.warehouse)].cell.duplicate() if not town.is_empty() and s.entities.has(str(town.get("warehouse", 0))) else s.entities[str(npc.id)].cell.duplicate()
	npc.brawl = {"target": s.player, "since": s.tick, "next_attack": s.tick + 14, "path_tick": -100, "mode": mode, "landed": false, "home": home}
	npc.status = "Angry at the traveller"

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("brawl"): return
	var blood: Array = s.brawl.blood
	while not blood.is_empty() and s.tick - int(blood[0].tick) > BLOOD_LIFETIME: blood.pop_front()
	var control: Dictionary = s.player_control
	if not control.get("knock", {}).is_empty() and s.tick >= int(control.knock.rise_until):
		if control.knock.kind == "ko": BodyHealth.revive(s)
		control.knock = {}
	if not control.get("knock", {}).is_empty() and s.tick == int(control.knock.down_until): event(s, "get_up", s.entities[str(s.player)].cell)
	var player: Dictionary = s.entities[str(s.player)]
	_exhaustion(s, control, player)
	if s.tick % 10 == 0 and s.has("player_health") and not control.get("dead", false) and BodyHealth.overall(s) <= 0: kill_player(sim)
	if s.tick % 30 == 0: _bleed(s, player)
	for key in s.residents.keys():
		var npc: Dictionary = s.residents[key]
		var cell: Array = s.entities[key].cell
		if npc.health <= 0: continue
		npc_stamina(s, npc)
		var knock: Dictionary = npc.get("knock", {})
		if not knock.is_empty():
			if s.tick == int(knock.down_until): event(s, "get_up", cell)
			if s.tick >= int(knock.rise_until):
				if knock.kind == "ko": npc.health = maxi(int(npc.health), KO_HEALTH + 5)
				npc.knock = {}
				_say(sim, npc.id, "got_up")
				npc.status = "Back on their feet"
				npc.work_pause_until = s.tick + 20
				# Someone shoved down while angry gets up and goes after the player.
				if int(npc.get("anger", 0)) >= HOSTILE_AT and npc.get("brawl", {}).is_empty() and not player_down(s) and npc.occupation != "Sheriff" and temperament(npc) == "fighter":
					engage(s, npc, "beat" if int(npc.get("offences", 0)) >= 2 else "shove")
					s.player_control.notice = "%s gets up, angry!" % s.entities[str(npc.id)].name
			continue
		# Someone who was robbed while out cold comes round furious and goes after the thief.
		if npc.get("grudge", false) and npc.get("sleeping", {}).is_empty() and npc.get("brawl", {}).is_empty():
			npc.grudge = false
			npc.anger = 70
			engage(s, npc, "beat")
			_say(sim, npc.id, "robbed")
			_law().crime(s, npc.settlement, "theft", npc.id)
			s.player_control.notice = "%s has realised they were robbed!" % s.entities[str(npc.id)].name
		if s.tick % 100 == 0:
			if int(npc.get("anger", 0)) > 0 and npc.get("brawl", {}).is_empty(): npc.anger = maxi(0, int(npc.anger) - 3)
			if npc.health < 100 and npc.health > 0: npc.health = mini(100, int(npc.health) + 1)
		var fight: Dictionary = npc.get("brawl", {})
		if fight.is_empty(): continue
		if in_custody(s):
			npc.brawl = {}
			npc.attack = {}
			continue
		if npc.health <= 0 or s.get("local_combat", {}).get("fighters", {}).has(key):
			npc.brawl = {}
			continue
		var attack: Dictionary = npc.get("attack", {})
		if not attack.is_empty():
			_advance_attack(sim, npc, attack, cell, player)
			continue
		var gap := Vector2(player.cell[0] - cell[0], player.cell[1] - cell[1])
		# Nobody follows a grudge forever: too far from their own town, too far behind, or cooled off.
		var home: Array = fight.get("home", cell)
		var from_home := Vector2(cell[0] - home[0], cell[1] - home[1]).length()
		var killing: bool = str(fight.get("mode", "shove")) == "kill"
		var lost_you: bool = from_home > GIVE_UP_DISTANCE or gap.length() > GIVE_UP_GAP
		if lost_you or int(npc.get("anger", 0)) < 25 or (player_down(s) and not killing) or s.tick - int(fight.since) > 3600:
			if lost_you: _say(sim, npc.id, "give_up")
			npc.brawl = {}
			npc.anger = mini(int(npc.get("anger", 0)), 35)
			npc.status = "Gave up the chase" if lost_you else "Cooled off"
			npc.work_pause_until = s.tick + 60
			continue
		npc.status = "Fighting the traveller"
		if gap.length() > 1.5:
			# Charge in at a run while far away and fresh; otherwise at the same walk the player has.
			var heading_diagonal: bool = not npc.path.is_empty() and npc.path[0][0] != cell[0] and npc.path[0][1] != cell[1]
			if not chase_pace(s, npc, gap.length(), heading_diagonal): continue
			if s.tick - int(fight.path_tick) >= 8 or npc.path.is_empty():
				var goal: Array = player.cell.duplicate()
				var route := Nav.request_path(s, cell, goal)
				fight.path_tick = s.tick
				npc.path = route.path if route.ok else []
			if not npc.path.is_empty():
				var next: Array = npc.path.pop_front()
				if World.walkable(s, next) and next != player.cell: s.entities[key].cell = next
		elif s.tick >= int(fight.next_attack):
			var mode_now: String = str(fight.get("mode", "shove"))
			var kind := "punch" if mode_now in ["beat", "kill"] else "shove"
			if mode_now == "kill" and player_down(s): kind = "kick"
			npc.attack = {"kind": kind, "start": s.tick, "impact": s.tick + ATTACK_IMPACT, "end": s.tick + ATTACK_TICKS, "resolved": false, "direction": [signi(player.cell[0] - cell[0]), signi(player.cell[1] - cell[1])]}

## Running the stamina bar all the way to empty drops the player face first; they lie winded and get up.
static func _exhaustion(s: Dictionary, control: Dictionary, player: Dictionary) -> void:
	var health: Dictionary = s.get("player_health", {})
	if health.is_empty() or int(health.stamina) > 0 or player_down(s): return
	if int(control.get("running_tick", -100)) < s.tick - 1: return
	health.winded = true
	health.exhausted = true
	control.running = false
	control.travel_run = false
	control.pending = {}
	s.player_path = []
	var direction: Array = control.get("last_dir", [0, 1])
	knockdown(s, control, player.cell, "exhaust", direction, "front")
	control.notice = "You are out of breath and collapse!"

## A bleeding wound (the player's, or a villager's cut) leaves drops on the ground until it is bandaged.
static func _bleed(s: Dictionary, player: Dictionary) -> void:
	for part in s.get("player_health", {}).get("parts", {}).values():
		if part.bleeding:
			add_blood(s, player.cell, [0, 0], 1)
			break
	for key in s.residents.keys():
		if int(s.residents[key].get("bleeding_until", 0)) > s.tick:
			add_blood(s, s.entities[key].cell, [0, 0], 1)

static func _advance_attack(sim: RefCounted, npc: Dictionary, attack: Dictionary, cell: Array, player: Dictionary) -> void:
	var s: Dictionary = sim.state
	if not attack.resolved and s.tick >= attack.impact:
		attack.resolved = true
		var near: bool = absi(player.cell[0] - cell[0]) <= 1 and absi(player.cell[1] - cell[1]) <= 1
		if near and not player_down(s):
			_hit_player(sim, npc, attack, player)
			npc.brawl.landed = true
	if s.tick >= attack.end:
		npc.attack = {}
		if str(npc.brawl.get("mode", "shove")) == "shove" and npc.brawl.get("landed", false):
			# Satisfied once the traveller is on the ground: they turn and walk away.
			npc.brawl = {}
			npc.anger = mini(int(npc.get("anger", 0)), 30)
			npc.status = "Walked away"
			npc.work_pause_until = s.tick + 40
		else:
			npc.brawl.next_attack = s.tick + 10 + sim.random_int("brawl", 0, 12)

static func _hit_player(sim: RefCounted, npc: Dictionary, attack: Dictionary, player: Dictionary) -> void:
	var s: Dictionary = sim.state
	var control: Dictionary = s.player_control
	if in_custody(s):
		# The sheriffs step in: the prisoner is not touched, and whoever tried is sent off.
		npc.brawl = {}
		npc.attack = {}
		npc.anger = mini(int(npc.get("anger", 0)), 20)
		control.notice = "The sheriff won't let anyone lay a hand on you."
		return
	var direction: Array = attack.direction
	control.impact_until = s.tick + 12
	control.impact_kind = attack.kind
	control.unarmed = {}
	if attack.kind == "punch":
		var part: String = PLAYER_PARTS[sim.random_int("brawl", 0, PLAYER_PARTS.size() - 1)]
		BodyHealth.injure(s, part, BEAT_DAMAGE, "bruise")
		if part == "head" and sim.random_int("brawl", 0, 99) < 40: add_blood(s, player.cell, direction, 1)
		event(s, "punch_hit", player.cell, direction)
		if BodyHealth.overall(s) < KO_HEALTH:
			knockdown(s, control, player.cell, "ko", direction)
		else:
			control.notice = "%s punches you." % s.entities[str(npc.id)].name
	elif attack.kind == "kick":
		var kick_part: String = ["head", "upper_torso", "lower_torso", "upper_torso"][sim.random_int("brawl", 0, 3)]
		BodyHealth.injure(s, kick_part, BEAT_DAMAGE, "bruise")
		event(s, "punch_hit", player.cell, direction)
		control.notice = "%s kicks you while you are down!" % s.entities[str(npc.id)].name
	else:
		var destination: Array = [player.cell[0] + attack.direction[0], player.cell[1] + attack.direction[1]]
		if World.walkable(s, destination): player.cell = destination
		knockdown(s, control, player.cell, "fall", direction)
		event(s, "shove_hit", player.cell, direction)
		control.notice = "%s shoves you to the ground." % s.entities[str(npc.id)].name
	s.player_path = []
	if BodyHealth.overall(s) <= 0: kill_player(sim)

## A kick (Space) on someone lying on the ground, whether knocked out or just shoved down:
## one and a half punches of damage. Zero health is death.
static func on_player_kick(sim: RefCounted, npc: Dictionary, victim: Dictionary, direction: Array) -> void:
	var s: Dictionary = sim.state
	if npc.health <= 0: return
	if s.tick - int(npc.get("last_offence", -99999)) > OFFENCE_MEMORY: npc.offences = 0
	npc.offences = int(npc.get("offences", 0)) + 1
	npc.last_offence = s.tick
	npc.anger = mini(100, int(npc.get("anger", 0)) + ANGER_PUNCH)
	npc.health = maxi(0, int(npc.health) - KICK_DAMAGE)
	var bruises: Dictionary = npc.get("bruises", {})
	bruises["upper_torso"] = int(bruises.get("upper_torso", 0)) + 1
	npc.bruises = bruises
	if sim.random_int("brawl", 0, 99) < 35: add_blood(s, victim.cell, direction, 1)
	event(s, "punch_hit", victim.cell, direction)
	var knock: Dictionary = npc.get("knock", {})
	if not knock.is_empty() and knock.kind == "fall":
		knock.down_until = int(knock.down_until) + 6   # kept on the ground a moment longer
		knock.rise_until = int(knock.rise_until) + 6
	_law().crime(s, npc.settlement, "murder" if int(npc.health) <= 0 else "kick", npc.id)
	if int(npc.health) <= 0: kill(sim, npc, "kicked")
	elif s.has("factions"): Society.remember(s, npc.id, "assault", s.player, "The traveller kicked me while I was down.", -30)

## A villager dies: they drop where they are, their work and tent are given up and the body stays
## for anyone to search.
static func kill(sim: RefCounted, npc: Dictionary, cause: String) -> void:
	var s: Dictionary = sim.state
	if npc.get("dead", false): return
	Households.wake(s, npc)
	if npc.job != 0: Jobs.release(s, npc.job, "DIED")
	npc.health = 0
	npc.dead = true
	npc.died_tick = s.tick                              # for the investigation (investigation.gd)
	npc.died_at = s.entities[str(npc.id)].cell.duplicate()
	npc.cause = cause
	npc.knock = {}
	npc.brawl = {}
	npc.attack = {}
	npc.goal = ""
	npc.path = []
	npc.work_path = []
	npc.status = "Dead"
	var name_value: String = s.entities[str(npc.id)].name
	sim.record("%s has died (%s)." % [name_value, cause])
	event(s, "fall", s.entities[str(npc.id)].cell, [0, 0])
	# Who killed them is remembered where it happens (law.remember_crime): a death the player had
	# no hand in no longer turns the whole town against them.
	if s.has("residents"): load("res://sim/world/chronicle.gd").record(s, "death", int(npc.settlement), 0, int(npc.id), s.entities[str(npc.id)].cell, {"cause": cause})

## The player's health reached zero. Every command is refused from now on (see simulation.gd).
static func kill_player(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var control: Dictionary = s.player_control
	if control.get("dead", false): return
	control.dead = true
	control.running = false
	control.travel_run = false
	control.pending = {}
	control.notice = ""
	s.player_path = []
	if s.has("player_health"): s.player_health.treatment = {}
	var cell: Array = s.entities[str(s.player)].cell
	control.knock = {"kind": "dead", "start": s.tick, "fall_ticks": 9, "down_until": 1 << 40, "rise_until": 1 << 40, "style": "front", "side": 1, "dir": [0, 1]}
	sim.record("You have died.")
	event(s, "fall", cell, [0, 0])

## Gives a hand to someone who was shoved down: they start getting up right away.
static func help_up(s: Dictionary, npc: Dictionary) -> void:
	var knock: Dictionary = npc.get("knock", {})
	if knock.is_empty() or knock.kind != "fall" or s.tick >= int(knock.down_until): return
	knock.down_until = s.tick
	knock.rise_until = s.tick + RISE_TICKS
	npc.anger = maxi(0, int(npc.get("anger", 0)) - 20)
	event(s, "get_up", s.entities[str(npc.id)].cell)
