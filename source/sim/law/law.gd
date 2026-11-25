extends RefCounted
## The law. Crimes the sheriff sees (or that are done to him) make the player wanted in that town.
## A sheriff who saw it gives chase, shoves the player down, cuffs them and walks them to the cell
## in his office. A player who got away is remembered: the next time the sheriff sees them he draws
## his gun. Press F to surrender (hands up) and he walks up slowly and arrests you; run and he
## chases. Prisoners serve a number of hours that depends on what they did.
##
## The jail follows a Prison Architect-style intake: cuffed at the arrest, walked to the booking desk,
## searched (everything they carry goes in the locker, coins into the office's keeping), photographed
## and issued an orange uniform, then walked to the cell and locked in. When the sentence ends the
## sheriff unlocks the cell, walks the prisoner back to the desk, returns their belongings and clothes,
## and lets them go.
const Brawl = preload("res://sim/combat/brawl.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const BodyHealth = preload("res://sim/combat/body_health.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const World = preload("res://sim/world/world_db.gd")
const HOUR := 600                     # ticks in an in-game hour
const SENTENCE := {"bribery": 2, "trespass": 1, "assault": 2, "assault_sheriff": 4, "kick": 3, "theft": 3, "murder": 24, "discharge": 2, "shooting": 6}
const CRIME_NAMES := {"bribery": "trying to bribe the law", "trespass": "trespassing", "assault": "assault", "assault_sheriff": "assaulting the sheriff", "kick": "kicking a man when he's down", "theft": "theft", "murder": "murder", "discharge": "firing a gun in town", "shooting": "shooting someone"}
const MAX_HOURS := 48
const WITNESS_RANGE := 24.0           # a sheriff this close sees a crime happen
const SEE_RANGE := 14.0               # a sheriff this close recognises a wanted player
const STANDOFF_TICKS := 140           # how long he holds you at gunpoint before he comes for you
const LIFT_TICKS := 40               # hauling a prisoner who was held down up onto their feet
const CUFF_TICKS := 30
const LOCK_TICKS := 16
const BOOK_TICKS := 76                # the whole booking at the desk
const PROPERTY_AT := 24               # tick of the booking when pockets are emptied into the locker
const PHOTO_AT := 50                  # the mugshot stage begins
const UNIFORM_AT := 58                # the flash goes off and the uniform is on
const RETURN_TICKS := 46              # handing belongings back at release
const RELEASE_WAIT := 1200            # how long a release waits for a busy sheriff before letting you out anyway

static func _say(sim: RefCounted, speaker: int, text: String) -> void:
	var s: Dictionary = sim.state
	if not s.has("speech"): s.speech = []
	for index in range(s.speech.size() - 1, -1, -1):
		if int(s.speech[index].speaker) == speaker: s.speech.remove_at(index)
	s.speech.append({"speaker": speaker, "text": text, "tick": s.tick, "until": s.tick + 55})

static func _law(s: Dictionary) -> Dictionary:
	if not s.has("law"): s.law = {"wanted": {}}
	return s.law

## The town's sheriff(s) still standing.
static func sheriffs(s: Dictionary, town: int) -> Array:
	var result: Array = []
	var keys: Array = s.get("residents", {}).keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.occupation == "Sheriff" and npc.settlement == town and npc.health > 0: result.append(npc)
	return result

static func wanted_hours(s: Dictionary, town: int) -> int:
	return int(_law(s).wanted.get(str(town), {}).get("hours", 0))

## Cuffed, or being walked somewhere by the sheriff: either way the player's own controls are off.
static func restrained(s: Dictionary) -> bool:
	var pc: Dictionary = s.get("player_control", {})
	return bool(pc.get("restrained", false)) or bool(pc.get("escorted", false))

## True from booking until the release is finished.
static func in_custody(s: Dictionary) -> bool:
	var pc: Dictionary = s.get("player_control", {})
	return not pc.get("jail", {}).is_empty() or pc.has("booking")

## "booking", "cell" or "release" (empty when free): what the jail banner reports.
static func stage(s: Dictionary) -> String:
	var pc: Dictionary = s.get("player_control", {})
	var jail: Dictionary = pc.get("jail", {})
	if jail.is_empty(): return "booking" if pc.has("booking") else ""
	return "release" if bool(jail.get("releasing", false)) else "cell"

static func jailed(s: Dictionary) -> bool:
	var jail: Dictionary = s.get("player_control", {}).get("jail", {})
	return not jail.is_empty() and s.tick < int(jail.until)

## The sheriff holding the player at gunpoint right now, or 0.
static func standoff_sheriff(s: Dictionary) -> int:
	for npc in s.get("residents", {}).values():
		if npc.get("arrest", {}).get("phase", "") == "standoff": return int(npc.id)
	return 0

## A crime in `town`. If a sheriff saw it (or suffered it) he comes for the player at once;
## either way the town remembers.
## What a crime leaves behind besides the law: an entry in the chronicle (with who saw it) and
## memories, in the victim, their family and the witnesses. Also used where a killing is not
## handed to the law as a separate crime (a shotgun kill in a gunfight).
const MEMORY_OF := {"trespass": "insulted", "theft": "robbed", "assault": "assaulted", "assault_sheriff": "assaulted", "kick": "assaulted",
	"shooting": "shot_at", "murder": "killed_kin"}
static func remember_crime(s: Dictionary, town: int, kind: String, victim: int) -> Dictionary:
	if not s.has("player") or not s.entities.has(str(s.player)): return {}
	var cell: Array = s.entities[str(victim)].cell if s.entities.has(str(victim)) else s.entities[str(s.player)].cell
	var entry: Dictionary = load("res://sim/world/chronicle.gd").record(s, kind, town, int(s.player), victim, cell)
	if s.has("factions"):
		var victim_name: String = str(s.entities.get(str(victim), {}).get("name", "someone"))
		var text: String = "The stranger %s %s." % [{"theft": "robbed", "murder": "killed", "shooting": "shot at"}.get(kind, "attacked"), victim_name] if victim != 0 else "The stranger fired a gun in town."
		load("res://sim/factions/society.gd").witnessed(s, victim, str(MEMORY_OF.get(kind, "assaulted")), int(s.player), text, entry.witnesses, "saw_murder" if kind == "murder" else "saw_crime")
	return entry

## `silent`: nothing to hear (a takedown from behind), so a sheriff must actually see it.
static func crime(s: Dictionary, town: int, kind: String, victim: int, silent: bool = false) -> void:
	if not s.has("player_control") or not SENTENCE.has(kind): return
	if town == 0 or int(s.get("residents", {}).get(str(victim), {}).get("bandit", 0)) != 0: return   # outlaws: no town's law covers them
	var entry: Dictionary = remember_crime(s, town, kind, victim)
	var player: Array = s.entities[str(s.player)].cell
	var Cover = load("res://sim/combat/cover.gd")
	var witness: Dictionary = {}
	var witnesses: Array = []
	var nearest := 1.0e9
	for sheriff in sheriffs(s, town):
		var cell: Array = s.entities[str(sheriff.id)].cell
		var d: float = Vector2(cell[0] - player[0], cell[1] - player[1]).length()
		if sheriff.id == victim or (d <= load("res://sim/world/weather.gd").sight(s, player, WITNESS_RANGE) and (not silent or (sheriff.get("sleeping", {}).is_empty() and Cover.line_clear(s, cell, player)))):
			witnesses.append(sheriff)   # everyone who saw it (or was hit) comes
			if d < nearest:
				witness = sheriff       # the nearest takes the case
				nearest = d
	# No sheriff saw it: whoever did see it (or the victim) runs to tell one, and only then is it on
	# the books (witness_reports.gd). Nobody saw it at all: nobody knows who did it.
	if witness.is_empty():
		if kind in ["discharge", "shooting"]: return   # answered by the gunfight (gunfire.gd)
		var Reports = load("res://sim/law/witness_reports.gd")
		if not Reports.send(s, town, kind, victim, entry) and kind in ["murder", "theft"]: Reports.hide(s, town, kind, victim)
		return
	file(s, town, kind, {}, true)
	# Gunfire is answered by the gunfight (gunfire.gd), not by a chase.
	if kind in ["discharge", "shooting"] or in_custody(s): return
	for sheriff in witnesses:
		if not sheriff.get("arrest", {}).is_empty(): continue
		sheriff.arrest = {"phase": "pursue", "since": s.tick, "path_tick": -100, "announce": "Stop! You're under arrest!" if sheriff.id == witness.get("id", 0) else "Stop right there!"}
		sheriff.brawl = {}
		sheriff.goal = ""
		sheriff.path = []
		sheriff.status = "Arresting the traveller"
		load("res://sim/law/sheriff.gd").stand_up(s, sheriff)

## Puts a crime on the town's books: more hours wanted, and how the culprit is known: by face (a
## sheriff saw it) or by the clothes a witness described.
static func file(s: Dictionary, town: int, kind: String, outfit: Dictionary, face: bool) -> void:
	var record: Dictionary = _law(s).wanted.get(str(town), {"hours": 0, "crimes": [], "since": s.tick})
	record.hours = mini(MAX_HOURS, int(record.hours) + int(SENTENCE.get(kind, 1)))
	record.crimes.append(kind)
	if face: record.face = true
	elif not outfit.is_empty(): record.outfit = outfit.duplicate()
	_law(s).wanted[str(town)] = record

## Whether the sheriffs of `town` know the player on sight: by face, or because enough of what
## the player is wearing matches what witnesses described (change clothes and they may not).
static func recognised(s: Dictionary, town: int) -> bool:
	var record: Dictionary = _law(s).wanted.get(str(town), {})
	if bool(record.get("face", false)) or not record.has("outfit"): return true
	var described: Dictionary = record.outfit
	var now: Dictionary = Outfits.worn(s, int(s.player))
	var pieces := 0
	var matches := 0
	for slot in described:
		if str(described[slot]).is_empty(): continue
		pieces += 1
		if str(now.get(slot, "")) == str(described[slot]): matches += 1
	return matches >= mini(3, pieces)

static func surrender(s: Dictionary) -> void:
	var pc: Dictionary = s.player_control
	var under_fire: bool = not s.get("law", {}).get("alert", {}).is_empty()
	var bandits: bool = load("res://sim/factions/bandits.gd").demanding(s)
	if standoff_sheriff(s) == 0 and not _approaching(s) and not under_fire and not bandits:
		pc.notice = "Nobody is asking you to surrender."
		return
	pc.surrender = true
	pc.running = false
	pc.pending = {}
	s.player_path = []
	pc.notice = "You raise your hands."

static func _approaching(s: Dictionary) -> bool:
	for npc in s.get("residents", {}).values():
		if npc.get("arrest", {}).get("phase", "") == "approach": return true
	return false

## The officers see to a prisoner's injuries so nobody dies in the cells: every bleeding or neglected
## wound is bandaged and cleaned, infections are treated, and someone close to death is brought round.
## Returns true if anything was done.
static func tend_prisoner(sim: RefCounted, healer: int) -> bool:
	var s: Dictionary = sim.state
	if not s.has("player_health"): return false
	var done := false
	for part in s.player_health.parts.values():
		if int(part.damage) <= 0: continue
		if bool(part.bleeding) or (part.bandage != "clean" and int(part.damage) >= 8):
			part.bandage = "clean"
			part.bandage_until = s.tick + 2400
			part.bleeding = false
			done = true
		if int(part.infection) > 0:
			part.infection = maxi(0, int(part.infection) - 30)
			done = true
	if BodyHealth.overall(s) < 25:
		BodyHealth.revive(s, 25)
		done = true
	if done:
		s.player_health.notice = "The sheriff has dressed your wounds."
		s.player_control.notice = "The sheriff dresses your wounds."
		if healer != 0 and s.residents.has(str(healer)): _say(sim, healer, "Let's get those wounds seen to. You'll not die on my watch.")
	return done

## Every tick: release prisoners whose time is up, and run each sheriff's arrest.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("player_control") or not s.has("residents"): return
	var pc: Dictionary = s.player_control
	load("res://sim/law/witness_reports.gd").update(sim)   # witnesses hurrying to tell a sheriff
	var jail: Dictionary = pc.get("jail", {})
	if not jail.is_empty() and s.tick >= int(jail.until): _start_release(sim, jail)
	# In the cells the keeper keeps an eye on the wounds, so nobody bleeds out in custody.
	if (not jail.is_empty() or bool(pc.get("restrained", false))) and s.tick % 50 == 0: tend_prisoner(sim, int(jail.get("sheriff", pc.get("escort", 0))))
	if bool(pc.get("dead", false)): return
	var player: Array = s.entities[str(s.player)].cell
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.occupation != "Sheriff": continue
		if not npc.get("reinforcing", {}).is_empty() and load("res://sim/law/reinforcements.gd").busy(npc): continue   # on the road or visiting (reinforcements.gd)
		if not npc.get("collar", {}).is_empty(): continue   # bringing in an outlaw (outlaw_arrest.gd)
		if npc.health <= 0:
			if not npc.get("arrest", {}).is_empty(): _abandon(sim, npc)
			continue
		if Brawl.knocked(s, npc): continue
		var arrest: Dictionary = npc.get("arrest", {})
		var cell: Array = s.entities[key].cell
		var gap := Vector2(player[0] - cell[0], player[1] - cell[1]).length()
		if arrest.is_empty():
			# A wanted player who comes into view is held at gunpoint by the nearest sheriff; the rest cover him.
			if wanted_hours(s, npc.settlement) > 0 and gap <= load("res://sim/world/weather.gd").sight(s, player, SEE_RANGE) and recognised(s, int(npc.settlement)) and not in_custody(s) and not restrained(s) and not Brawl.player_down(s) and npc.get("sleeping", {}).is_empty():
				if _nearer_sheriff(s, npc, player) != 0:
					npc.arrest = {"phase": "backup", "since": s.tick}
					npc.goal = ""
					npc.path = []
					npc.status = "Covering his partner"
					load("res://sim/law/sheriff.gd").stand_up(s, npc)
					continue
				npc.arrest = {"phase": "standoff", "since": s.tick}
				npc.goal = ""
				npc.path = []
				npc.status = "Holding the traveller at gunpoint"
				_say(sim, npc.id, "Hands up! You're wanted for %s!" % CRIME_NAMES.get(str(_law(s).wanted[str(npc.settlement)].crimes[-1]), "your crimes"))
				pc.notice = "%s draws his gun on you. Press F to surrender, or run." % s.entities[key].name
				npc.search = {}
			elif not npc.get("search", {}).is_empty():
				load("res://sim/law/notoriety.gd").search(s, npc)   # told you were seen: he comes looking
			continue
		match str(arrest.phase):
			"engage": load("res://sim/combat/gunfire.gd").engage(sim, npc, arrest, cell, player, gap)
			"backup": _backup(sim, npc, arrest, cell, player)
			"assist": _assist(sim, npc, arrest, cell)
			"pursue": _pursue(sim, npc, arrest, cell, player, gap)
			"standoff": _standoff(sim, npc, arrest, cell, player, gap)
			"approach": _approach(sim, npc, arrest, cell, player, gap)
			"cuff": _cuff(sim, npc, arrest, cell, player)
			"lift": _lift(sim, npc, arrest, cell)
			"escort": _escort(sim, npc, arrest, cell)
			"book": _book(sim, npc, arrest)
			"lock": _lock(sim, npc, arrest)
			"fetch": _fetch(sim, npc, arrest, cell)
			"unlock": _unlock(sim, npc, arrest, cell, player)
			"return": _return(sim, npc, arrest)
			"grab": _grab(sim, npc, arrest, cell, player)
			"show_out": _show_out(sim, npc, arrest)

## A sheriff of the same town who is nearer the player and free to take the lead (0 if `npc` is the nearest).
static func _nearer_sheriff(s: Dictionary, npc: Dictionary, player: Array) -> int:
	var mine := Vector2(s.entities[str(npc.id)].cell[0] - player[0], s.entities[str(npc.id)].cell[1] - player[1]).length()
	for other in sheriffs(s, int(npc.settlement)):
		if other.id == npc.id or Brawl.knocked(s, other): continue
		var phase: String = str(other.get("arrest", {}).get("phase", ""))
		if phase not in ["", "backup", "standoff", "approach", "pursue"]: continue
		if not other.get("sleeping", {}).is_empty(): continue
		var c: Array = s.entities[str(other.id)].cell
		var d := Vector2(c[0] - player[0], c[1] - player[1]).length()
		if d < mine - 0.01 or (is_equal_approx(d, mine) and other.id < npc.id): return int(other.id)
	return 0

## The sheriff of this town who has the prisoner (cuffing, escorting, booking...), or 0.
static func _other_lead(s: Dictionary, npc: Dictionary) -> int:
	for other in sheriffs(s, int(npc.settlement)):
		if other.id != npc.id and str(other.get("arrest", {}).get("phase", "")) in ["cuff", "lift", "escort", "book", "lock", "fetch", "unlock", "return"]: return int(other.id)
	return 0

static func _join_lead(sim: RefCounted, npc: Dictionary, arrest: Dictionary, lead: int) -> void:
	arrest.phase = "assist"
	arrest.lead = lead
	arrest.since = sim.state.tick
	npc.path = []
	npc.status = "Helping take the prisoner in"

## Covers his partner during a standoff: gun on the player, until the arrest begins or it is over.
static func _backup(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array) -> void:
	var s: Dictionary = sim.state
	npc.status = "Covering his partner"
	var lead: int = _other_lead(s, npc)
	if lead != 0:
		_join_lead(sim, npc, arrest, lead)
		return
	var leader_busy := false
	for other in sheriffs(s, int(npc.settlement)):
		if other.id != npc.id and str(other.get("arrest", {}).get("phase", "")) in ["standoff", "approach", "pursue"]: leader_busy = true
	if not leader_busy or in_custody(s):
		npc.arrest = {}
		npc.status = "Back on duty"
		npc.work_pause_until = s.tick + 30

## Walks beside the sheriff who has the prisoner, gun ready, until the prisoner is locked up.
static func _assist(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array) -> void:
	var s: Dictionary = sim.state
	var lead: Dictionary = s.residents.get(str(arrest.get("lead", 0)), {})
	if lead.is_empty() or lead.health <= 0 or lead.get("arrest", {}).is_empty() or str(lead.arrest.phase) in ["", "engage", "pursue", "standoff"]:
		npc.arrest = {}
		npc.path = []
		npc.status = "Back on duty"
		npc.work_pause_until = s.tick + 30
		return
	npc.status = "Helping take the prisoner in"
	var lead_cell: Array = s.entities[str(lead.id)].cell
	var player: Array = s.entities[str(s.player)].cell
	var here := Vector2(lead_cell[0] - cell[0], lead_cell[1] - cell[1]).length()
	if here <= 1.9 or s.tick % 2 != 0: return
	# Take the free cell beside the lead that is on the other side from the prisoner.
	var goal: Array = lead_cell.duplicate()
	var best := -1.0
	for offset in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var candidate: Array = [lead_cell[0] + offset[0], lead_cell[1] + offset[1]]
		if candidate == player or not World.walkable(s, candidate): continue
		var score: float = Vector2(candidate[0] - player[0], candidate[1] - player[1]).length() - Vector2(candidate[0] - cell[0], candidate[1] - cell[1]).length() * 0.3
		if score > best:
			best = score
			goal = candidate
	_step_toward(s, npc, arrest, cell, goal)

static func _give_up(sim: RefCounted, npc: Dictionary, text: String) -> void:
	_say(sim, npc.id, text)
	npc.arrest = {}
	npc.status = "Lost the traveller"
	npc.work_pause_until = sim.state.tick + 60

static func _step_toward(s: Dictionary, npc: Dictionary, arrest: Dictionary, cell: Array, goal: Array) -> void:
	if s.tick - int(arrest.get("path_tick", -100)) >= 8 or npc.path.is_empty():
		var route := Nav.request_path(s, cell, goal)
		arrest.path_tick = s.tick
		npc.path = route.path if route.ok else []
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next) and next != s.entities[str(s.player)].cell: s.entities[str(npc.id)].cell = next

## Chase at the same pace rules as anyone else; shove the player down when he catches up.
static func _pursue(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array, gap: float) -> void:
	var s: Dictionary = sim.state
	var in_charge: int = _other_lead(s, npc)
	if in_charge != 0:
		_join_lead(sim, npc, arrest, in_charge)   # his partner already has the prisoner: help him
		return
	if arrest.has("announce"):
		_say(sim, npc.id, str(arrest.announce))
		arrest.erase("announce")
	var home: Array = s.entities[str(s.settlements[str(npc.settlement)].warehouse)].cell
	if Vector2(cell[0] - home[0], cell[1] - home[1]).length() > Brawl.GIVE_UP_DISTANCE or gap > Brawl.GIVE_UP_GAP:
		_give_up(sim, npc, "You can run, but I'll find you!")
		return
	npc.status = "Chasing the traveller"
	if Brawl.player_down(s) and gap <= 1.6:
		_begin_cuffing(sim, npc, arrest)
		return
	if gap > 1.5:
		var diagonal: bool = not npc.path.is_empty() and npc.path[0][0] != cell[0] and npc.path[0][1] != cell[1]
		if Brawl.chase_pace(s, npc, gap, diagonal): _step_toward(s, npc, arrest, cell, player)
	elif s.tick >= int(arrest.get("next_grab", 0)):
		# Tackle: put the traveller on the ground, then cuff.
		var direction: Array = [signi(player[0] - cell[0]), signi(player[1] - cell[1])]
		Brawl.knockdown(s, s.player_control, player, "fall", direction)
		Brawl.event(s, "shove_hit", player, direction)
		s.player_control.notice = "%s tackles you to the ground!" % s.entities[str(npc.id)].name
		s.player_path = []
		arrest.next_grab = s.tick + 20

## At gunpoint: wait for the player to raise their hands; run, and he comes after you.
static func _standoff(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array, gap: float) -> void:
	var s: Dictionary = sim.state
	npc.status = "Holding the traveller at gunpoint"
	if bool(s.player_control.get("surrender", false)):
		arrest.phase = "approach"
		arrest.since = s.tick
		_say(sim, npc.id, "Good. Nice and slow now...")
		return
	if gap > SEE_RANGE + 6.0 or s.tick - int(arrest.since) > STANDOFF_TICKS:
		arrest.phase = "pursue"
		arrest.since = s.tick
		arrest.announce = "Stop right there!"
		return

## Hands up: he walks up slowly, gun still on you.
static func _approach(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array, gap: float) -> void:
	var s: Dictionary = sim.state
	if not bool(s.player_control.get("surrender", false)):
		arrest.phase = "pursue"
		arrest.since = s.tick
		arrest.announce = "I said hands up!"
		return
	npc.status = "Walking up to arrest the traveller"
	if gap <= 1.5:
		_begin_cuffing(sim, npc, arrest)
		return
	if s.tick % 3 == 0: _step_toward(s, npc, arrest, cell, player)   # slower than a walk

static func _begin_cuffing(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	arrest.phase = "cuff"
	arrest.since = s.tick
	# On the ground: he kneels and holds the prisoner down while the cuffs go on, then hauls them up.
	arrest.pinned = Brawl.player_down(s)
	pc.restrained = true
	pc.surrender = false
	pc.escort = npc.id
	pc.running = false
	pc.pending = {}
	pc.unarmed = {}
	s.player_path = []
	if s.has("player_health"): s.player_health.treatment = {}
	npc.status = "Cuffing the traveller"
	_say(sim, npc.id, "You're under arrest.")
	pc.notice = "You are being arrested."

## Cuffs on; the player is helped up (if down) and walked to the booking desk.
static func _cuff(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	if bool(arrest.get("pinned", false)):
		# Held down: the prisoner stays on the ground (the knock-down is stretched) until he's done.
		var knock: Dictionary = pc.get("knock", {})
		if not knock.is_empty():
			knock.down_until = maxi(int(knock.down_until), s.tick + 4)
			knock.rise_until = int(knock.down_until) + LIFT_TICKS
		npc.status = "Holding the prisoner down"
		if s.tick - int(arrest.since) < CUFF_TICKS: return
		# Cuffed: now he hauls the prisoner to their feet (law.gd _lift), then the walk begins.
		arrest.phase = "lift"
		arrest.since = s.tick
		if not knock.is_empty():
			knock.down_until = s.tick
			knock.rise_until = s.tick + LIFT_TICKS
			knock.rise_ticks = LIFT_TICKS
		_say(sim, npc.id, "Up you get.")
		npc.status = "Pulling the prisoner to their feet"
		return
	if s.tick - int(arrest.since) < CUFF_TICKS: return
	pc.knock = {}   # on your feet, hands behind your back
	var office: Dictionary = office_of(s, npc.settlement)
	if office.is_empty():
		_release_custody(s, npc)
		return
	_start_escort(sim, npc, arrest, cell, desk_spot(office), "desk", office)
	tend_prisoner(sim, npc.id)   # first aid on the spot
	_say(sim, npc.id, "Come along. Don't try anything.")
	npc.status = "Taking the traveller to be booked"

## Hauling a cuffed prisoner up off the ground, then walking them to the desk.
static func _lift(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array) -> void:
	var s: Dictionary = sim.state
	npc.status = "Pulling the prisoner to their feet"
	if s.tick - int(arrest.since) < LIFT_TICKS: return
	s.player_control.knock = {}
	arrest.pinned = false
	var office: Dictionary = office_of(s, npc.settlement)
	if office.is_empty():
		_release_custody(s, npc)
		return
	_start_escort(sim, npc, arrest, cell, desk_spot(office), "desk", office)
	tend_prisoner(sim, npc.id)
	_say(sim, npc.id, "Come along. Don't try anything.")
	npc.status = "Taking the traveller to be booked"

## Sets the sheriff walking to `goal`, the prisoner a step behind him. `dest` says what happens on arrival.
static func _start_escort(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, goal: Array, dest: String, office: Dictionary) -> void:
	var s: Dictionary = sim.state
	var route := Nav.request_path(s, cell, goal)
	arrest.phase = "escort"
	arrest.dest = dest
	arrest.since = s.tick
	arrest.next_step = s.tick
	npc.path = route.path if route.ok else []
	if not route.ok:
		# No way through: they arrive by the office door instead.
		s.entities[str(npc.id)].cell = office.door.duplicate()
		npc.path = []

## Walk to the destination, the prisoner one step behind.
static func _escort(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array) -> void:
	var s: Dictionary = sim.state
	if s.tick < int(arrest.get("next_step", 0)): return
	if npc.path.is_empty():
		_arrive(sim, npc, arrest)
		return
	var next: Array = npc.path.pop_front()
	var diagonal: bool = next[0] != cell[0] and next[1] != cell[1]
	if World.walkable(s, next):
		s.entities[str(s.player)].cell = cell.duplicate()   # the prisoner steps where the sheriff was
		s.entities[str(npc.id)].cell = next
	arrest.next_step = s.tick + 2 + (1 if diagonal else 0)

static func _arrive(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var office: Dictionary = office_of(s, npc.settlement)
	match str(arrest.get("dest", "cell")):
		"desk":
			s.entities[str(s.player)].cell = desk_stance(office)
			arrest.phase = "book"
			arrest.since = s.tick
			pc.booking = {"step": "search", "since": s.tick, "flash": -1000, "dressed": false}
			_say(sim, npc.id, "Right. Stand still while I search you.")
			npc.status = "Booking the prisoner"
		"release":
			s.entities[str(s.player)].cell = desk_stance(office)
			arrest.phase = "return"
			arrest.since = s.tick
			_say(sim, npc.id, "Let's get your things.")
		"door":
			# At the door, the prisoner just behind him: he steps aside, ready to give them a push.
			arrest.phase = "show_out"
			arrest.since = s.tick
			pc.notice = "%s walks you to the door." % s.entities[str(npc.id)].name
		_:
			s.entities[str(s.player)].cell = cell_spot(office)
			office.cell_open = false   # the door clangs shut
			arrest.phase = "lock"
			arrest.since = s.tick
			_say(sim, npc.id, "Think about what you did.")

## Booking: search, property into the locker, mugshot, then the uniform goes on under the flash.
static func _book(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var booking: Dictionary = pc.get("booking", {})
	var age: int = s.tick - int(arrest.since)
	npc.status = "Booking the prisoner"
	booking.step = "search" if age < PROPERTY_AT else ("property" if age < PHOTO_AT else "photo")
	pc.booking = booking
	if age >= PROPERTY_AT and not pc.has("property"):
		_take_property(sim, npc)
		tend_prisoner(sim, npc.id)
		_say(sim, npc.id, "Everything goes in the locker.")
	if age >= UNIFORM_AT and not bool(booking.get("dressed", false)):
		booking.dressed = true
		booking.flash = s.tick
		Outfits.dress(s, s.player, Outfits.PRISONER)
		_say(sim, npc.id, "Smile. ... Put these on.")
	if age < BOOK_TICKS: return
	var office: Dictionary = office_of(s, npc.settlement)
	var cell: Array = s.entities[str(npc.id)].cell
	office.cell_open = true
	_start_escort(sim, npc, arrest, cell, cell_door(office), "cell", office)
	npc.status = "Taking the prisoner to the cells"
	pc.erase("booking")

## Everything the player carries goes into the office's keeping: items out of the pack (conserved through
## the accounting), coins into the office's account, the outfit (restored at release) and the gun's load.
static func _take_property(sim: RefCounted, npc: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var office: Dictionary = office_of(s, npc.settlement)
	var property := {"items": {}, "coins": 0, "outfit": Outfits.worn(s, s.player).duplicate(), "gun_loaded": 0, "office": office.get("id", 0)}
	var carried: Dictionary = s.inventories[str(s.player)].items
	for item in carried.keys():
		var quantity: int = int(carried[item])
		if Inventory.consume(s, s.player, item, quantity): property.items[item] = quantity
	if s.has("shotgun"):
		property.gun_loaded = int(s.shotgun.get("loaded", 0))
		s.shotgun.equipped = false
		s.shotgun.reloading = false
		s.shotgun.loaded = 0
	var coins: int = int(s.get("accounts", {}).get(str(s.player), 0))
	if coins > 0 and office.has("id"):
		s.accounts[str(s.player)] -= coins
		s.accounts[str(office.id)] = int(s.accounts.get(str(office.id), 0)) + coins
		property.coins = coins
	pc.property = property
	pc.held_item = ""
	pc.held_quantity = 0

## Gives everything back: items, coins, clothes and the gun's load.
static func _return_property(s: Dictionary) -> void:
	var pc: Dictionary = s.player_control
	var property: Dictionary = pc.get("property", {})
	if property.is_empty(): return
	for item in property.items:
		var quantity: int = int(property.items[item])
		quantity = mini(quantity, Inventory.available(s, s.player))
		if quantity > 0: Inventory.produce(s, s.player, item, quantity)
	var coins: int = int(property.get("coins", 0))
	var keeper: String = str(property.get("office", 0))
	if coins > 0 and s.has("accounts"):
		s.accounts[keeper] = int(s.accounts.get(keeper, 0)) - coins
		s.accounts[str(s.player)] = int(s.accounts.get(str(s.player), 0)) + coins
	Outfits.dress(s, s.player, property.outfit)
	if s.has("shotgun") and int(property.get("gun_loaded", 0)) > 0 and load("res://sim/combat/shotgun.gd").owns(s):
		s.shotgun.loaded = int(property.gun_loaded)
	pc.erase("property")
	pc.erase("booking")

## Lock the cell: the player serves their sentence.
static func _lock(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	if s.tick - int(arrest.since) < LOCK_TICKS: return
	var office: Dictionary = office_of(s, npc.settlement)
	var hours: int = maxi(1, wanted_hours(s, npc.settlement))
	var record: Dictionary = _law(s).wanted.get(str(npc.settlement), {})
	s.player_control.jail = {"office": office.id, "until": s.tick + hours * HOUR, "hours": hours, "rect": cell_rect(office), "sheriff": npc.id,
		"town": npc.settlement, "crimes": record.get("crimes", []).duplicate()}
	_law(s).wanted.erase(str(npc.settlement))
	_release_custody(s, npc)
	s.player_control.notice = "Locked up for %d hour%s." % [hours, "" if hours == 1 else "s"]
	sim.record("The traveller was jailed in %s for %d hours." % [s.settlements[str(npc.settlement)].name, hours])

static func _release_custody(s: Dictionary, npc: Dictionary) -> void:
	npc.arrest = {}
	npc.path = []
	npc.status = "Back on duty"
	npc.work_pause_until = s.tick + 30
	s.player_control.restrained = false
	s.player_control.escorted = false
	s.player_control.escort = 0

# --- release -----------------------------------------------------------------------------------

## The keeper if he is free, else any free sheriff of the town; empty when nobody can do it.
static func _keeper(s: Dictionary, jail: Dictionary) -> Dictionary:
	var candidates: Array = []
	var keeper: Dictionary = s.get("residents", {}).get(str(jail.get("sheriff", 0)), {})
	if not keeper.is_empty() and keeper.health > 0: candidates.append(keeper)
	for sheriff in sheriffs(s, int(jail.get("town", 0))):
		if sheriff.id != keeper.get("id", -1): candidates.append(sheriff)
	for npc in candidates:
		if npc.get("arrest", {}).is_empty() and not Brawl.knocked(s, npc): return npc
	return {}

## The sentence is up: a free sheriff fetches the prisoner. If nobody can, they are let out in place.
static func _start_release(sim: RefCounted, jail: Dictionary) -> void:
	var s: Dictionary = sim.state
	if bool(jail.get("releasing", false)):
		var holder: Dictionary = s.residents.get(str(jail.get("releaser", 0)), {})
		if holder.is_empty() or holder.health <= 0 or holder.get("arrest", {}).is_empty(): jail.releasing = false   # he was lost: start over
		else: return
	if not jail.has("release_since"): jail.release_since = s.tick
	var keeper: Dictionary = _keeper(s, jail)
	if keeper.is_empty():
		if s.tick - int(jail.release_since) > RELEASE_WAIT or sheriffs(s, int(jail.get("town", 0))).is_empty(): _release_in_place(sim, jail)
		return
	jail.releasing = true
	jail.releaser = keeper.id
	keeper.arrest = {"phase": "fetch", "since": s.tick, "path_tick": -100}
	keeper.goal = ""
	keeper.path = []
	keeper.brawl = {}
	keeper.status = "Going to let the prisoner out"

static func _release_in_place(sim: RefCounted, jail: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	_return_property(s)
	var office: Dictionary = s.entities.get(str(jail.get("office", 0)), {})
	if not office.is_empty(): office.cell_open = false
	pc.jail = {}
	pc.escorted = false
	pc.notice = "Your sentence is served. Your belongings are returned. You are free to go."

## The sheriff walks to the cell door.
static func _fetch(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array) -> void:
	var s: Dictionary = sim.state
	var office: Dictionary = office_of(s, npc.settlement)
	npc.status = "Going to let the prisoner out"
	var door: Array = cell_door(office)
	if cell == door or s.tick - int(arrest.since) > 900:
		s.entities[str(npc.id)].cell = door
		arrest.phase = "unlock"
		arrest.since = s.tick
		arrest.next_step = s.tick
		return
	if s.tick % 2 == 0: _step_toward(s, npc, arrest, cell, door)

## He unlocks the cell; the prisoner walks out to him, then he leads them to the desk.
static func _unlock(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var office: Dictionary = office_of(s, npc.settlement)
	npc.status = "Letting the prisoner out"
	if s.tick - int(arrest.since) < 12: return
	if not bool(office.get("cell_open", false)):
		office.cell_open = true
		pc.escorted = true
		pc.notice = "The cell door is unlocked."
		_say(sim, npc.id, "Time's served. Come with me.")
		return
	# He comes into the cell to take hold of the prisoner (release step 2: grab).
	arrest.phase = "grab"
	arrest.since = s.tick
	npc.path = []

## Release: the sheriff walks into the cell up to the prisoner and takes them by the arm, then
## leads them to the desk for their things.
static func _grab(sim: RefCounted, npc: Dictionary, arrest: Dictionary, cell: Array, player: Array) -> void:
	var s: Dictionary = sim.state
	var office: Dictionary = office_of(s, npc.settlement)
	npc.status = "Fetching the prisoner from the cell"
	var gap := Vector2(player[0] - cell[0], player[1] - cell[1]).length()
	if gap <= 1.5 or s.tick - int(arrest.since) > 400:
		s.player_control.escorted = true
		s.player_control.notice = "%s takes you by the arm." % s.entities[str(npc.id)].name
		_say(sim, npc.id, "Up you get. This way.")
		_start_escort(sim, npc, arrest, cell, desk_spot(office), "release", office)
		return
	if s.tick % 2 == 0: _step_toward(s, npc, arrest, cell, player)

## At the desk: the uniform comes off, everything is handed back and the prisoner goes free.
static func _return(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var age: int = s.tick - int(arrest.since)
	npc.status = "Returning the prisoner's belongings"
	var office: Dictionary = office_of(s, npc.settlement)
	if age >= 24 and pc.has("property"):
		_return_property(s)
		if not office.is_empty(): office.cell_open = false
		pc.jail = {}
		pc.escorted = true   # he still has you by the arm: he sees you out
		pc.escort = npc.id
		pc.notice = "Your belongings are returned."
		_say(sim, npc.id, "There's your things. Now, out.")
	if age >= RETURN_TICKS and pc.jail.is_empty():
		if office.is_empty() or not office.has("door"):
			_free(sim, npc, "You are free to go.")
			return
		var cell: Array = s.entities[str(npc.id)].cell
		_start_escort(sim, npc, arrest, cell, office.door, "door", office)
		npc.status = "Showing the traveller out"

## At the door: the sheriff gives the prisoner a shove out into the street, and they are free.
static func _show_out(sim: RefCounted, npc: Dictionary, arrest: Dictionary) -> void:
	var s: Dictionary = sim.state
	npc.status = "Showing the traveller out"
	if s.tick - int(arrest.since) < 8: return
	var office: Dictionary = office_of(s, npc.settlement)
	var door: Array = office.get("door", s.entities[str(npc.id)].cell)
	var out: Array = outside_of(s, office)
	var landing: Array = [door[0] + out[0] * 2, door[1] + out[1] * 2]
	if not World.walkable(s, landing): landing = [door[0] + out[0], door[1] + out[1]]
	s.entities[str(s.player)].cell = landing
	s.entities[str(npc.id)].cell = door.duplicate()
	Brawl.event(s, "shove_hit", landing, out)
	_free(sim, npc, "%s shoves you out into the street. You are free." % s.entities[str(npc.id)].name)
	_say(sim, npc.id, "Out you go. Don't come back.")

## The release is over: the player is free and the sheriff goes back to his work.
static func _free(sim: RefCounted, npc: Dictionary, notice: String) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	pc.jail = {}
	pc.escorted = false
	pc.escort = 0
	pc.restrained = false
	pc.notice = notice
	_release_custody(s, npc)

## The direction from a building's door out into the street (the side away from the building).
static func outside_of(s: Dictionary, building: Dictionary) -> Array:
	var door: Array = building.get("door", building.cell)
	for d in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
		var c: Array = [door[0] + d[0], door[1] + d[1]]
		if World.walkable(s, c) and World.inside_building(s, c) == 0: return d
	return [0, 1]

## A sheriff in the middle of an arrest died: let the player go and give everything back.
static func _abandon(sim: RefCounted, npc: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	npc.arrest = {}
	npc.path = []
	if int(pc.get("escort", 0)) == npc.id or bool(pc.get("escorted", false)):
		pc.restrained = false
		pc.escorted = false
		pc.escort = 0
	if pc.has("property") and (pc.get("jail", {}).is_empty() or bool(pc.jail.get("releasing", false))):
		_return_property(s)
		if not pc.get("jail", {}).is_empty(): pc.jail = {}

# --- the office and its cell -----------------------------------------------------------------

static func office_of(s: Dictionary, town: int) -> Dictionary:
	var id: int = int(s.get("settlements", {}).get(str(town), {}).get("office", 0))
	return s.entities.get(str(id), {})

## The cell is the office's small room, left of the partition; its door is the partition's gap.
static func cell_rect(office: Dictionary) -> Array:
	var f: Array = office.footprint
	return [int(f[0]) + 1, int(f[1]) + 1, 4, int(f[3]) - 2]

static func cell_spot(office: Dictionary) -> Array:
	var f: Array = office.footprint
	return [int(f[0]) + 3, int(f[1]) + 6]

static func cell_door(office: Dictionary) -> Array:
	var f: Array = office.footprint
	return [int(f[0]) + 6, int(f[1]) + 8]

## Where the prisoner stands at the booking desk, and the sheriff beside them.
static func desk_stance(office: Dictionary) -> Array:
	var f: Array = office.footprint
	return [int(f[0]) + 11, int(f[1]) + 11]

static func desk_spot(office: Dictionary) -> Array:
	var f: Array = office.footprint
	return [int(f[0]) + 12, int(f[1]) + 11]

## True when `cell` is inside the prisoner's cell (movement in jail is kept to it).
static func inside_cell(s: Dictionary, cell: Array) -> bool:
	var jail: Dictionary = s.get("player_control", {}).get("jail", {})
	if jail.is_empty(): return true
	var r: Array = jail.rect
	return cell[0] >= r[0] and cell[1] >= r[1] and cell[0] < r[0] + r[2] and cell[1] < r[1] + r[3]
