extends RefCounted
## Being wanted, as the town sees it. Where you're wanted and recognised (by face, or by the clothes
## witnesses described: law.gd `recognised`), townsfolk know you: they step back and mutter about
## what you did, those you hurt (or their kin) round on you, and now and then one slips off to tell
## the sheriff where you are (a "sighting": he comes looking). Shopkeepers won't serve you, or the
## timid ones do at double the price (stall_service.gd). At the office you can turn yourself in (half
## the time) or, for small crimes, pay a fine. Deterministic; nothing here touches money except the fine.
const Cover = preload("res://sim/combat/cover.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const NOTICE_RANGE := 7.0
const NOTICE_GAP := 3000          # a person mutters about you at most once in this many ticks
const SIGHTING_GAP := 1200        # at most one sighting report per town in this many ticks
const SEARCH_TICKS := 1200        # a sheriff looks for you this long after a sighting
const FINE_CRIMES := ["trespass", "assault", "discharge", "kick"]
const FINE_PER_HOUR := 12

static func _law() -> GDScript: return load("res://sim/law/law.gd")

## The town you're in, if any (0 in the wilds).
static func town_here(s: Dictionary) -> int:
	if not s.has("player") or not s.entities.has(str(s.player)): return 0
	return load("res://sim/combat/gunfire.gd").town_of(s, s.entities[str(s.player)].cell)

## Whether `town`'s people know you on sight as wanted.
static func known(s: Dictionary, town: int) -> bool:
	return town != 0 and _law().wanted_hours(s, town) > 0 and _law().recognised(s, town)

## "assault, theft" — what you're wanted for in `town`, each crime once.
static func crimes_line(s: Dictionary, town: int) -> String:
	var names: Array = []
	for crime in s.get("law", {}).get("wanted", {}).get(str(town), {}).get("crimes", []):
		var name: String = str(_law().CRIME_NAMES.get(str(crime), str(crime)))
		if not name in names: names.append(name)
	return ", ".join(names)

## The fine that settles `town`'s record, or 0 when it's too serious to pay off.
static func fine(s: Dictionary, town: int) -> int:
	var record: Dictionary = s.get("law", {}).get("wanted", {}).get(str(town), {})
	if record.is_empty(): return 0
	for crime in record.get("crimes", []):
		if not str(crime) in FINE_CRIMES: return 0
	return maxi(1, int(record.hours)) * FINE_PER_HOUR

# --- every 30 ticks ------------------------------------------------------------------------------

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if s.tick % 30 != 0 or not s.has("player_control") or not s.has("residents"): return
	var pc: Dictionary = s.player_control
	if bool(pc.get("dead", false)) or _law().in_custody(s) or _law().restrained(s) or not pc.get("captive", {}).is_empty(): return
	var town: int = town_here(s)
	if not known(s, town): return
	var me: Array = s.entities[str(s.player)].cell
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != town or npc.occupation in ["Sheriff", "Child", "Bandit"] or int(npc.health) <= 0: continue
		if not npc.get("sleeping", {}).is_empty() or Brawl.knocked(s, npc) or not npc.get("brawl", {}).is_empty() or not npc.get("reporting", {}).is_empty() or not npc.get("fear", {}).is_empty(): continue
		if s.tick - int(npc.get("noticed_wanted", -100000)) < NOTICE_GAP: continue
		var at: Array = s.entities[key].cell
		if Vector2(at[0] - me[0], at[1] - me[1]).length() > NOTICE_RANGE or not Cover.line_clear(s, at, me): continue
		npc.noticed_wanted = s.tick
		var Society = load("res://sim/factions/society.gd")
		var bitter: bool = s.has("factions") and Society.opinion(s, int(npc.id), int(s.player)) <= -40
		var crimes: String = crimes_line(s, town)
		if bitter:
			_law()._say(sim, int(npc.id), ["You've got some nerve showing your face here.", "After what you did? Get out of my sight.", "I know who you are. Everyone does."][int(npc.id) % 3])
		else:
			_law()._say(sim, int(npc.id), ["That's the one wanted for %s..." % crimes, "Keep away from that one.", "Isn't that the stranger the sheriff's after?"][(int(npc.id) + s.tick / 30) % 3])
		# Now and then one of them slips off to tell the sheriff where you are.
		if Brawl.temperament(npc) == "confront" and _no_one_coming(s, town):
			var law: Dictionary = _law()._law(s)
			var told: Dictionary = law.get("sighted", {})
			if s.tick - int(told.get(str(town), -100000)) >= SIGHTING_GAP:
				told[str(town)] = s.tick
				law.sighted = told
				if int(npc.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, npc.job, "REPORTING_A_SIGHTING")
				npc.goal = ""
				npc.path = []
				npc.reporting = {"town": town, "kind": "sighting", "victim": 0, "outfit": {}, "cell": me.duplicate(), "since": s.tick, "path_tick": -1000, "next_step": s.tick}
				npc.status = "Slipping off to tell the sheriff"
		return   # one at a time

## No sheriff already on you (holding you, chasing you or searching).
static func _no_one_coming(s: Dictionary, town: int) -> bool:
	for sheriff in _law().sheriffs(s, town):
		if not sheriff.get("arrest", {}).is_empty() or not sheriff.get("search", {}).is_empty(): return false
	return true

## A townsperson told `sheriff` the wanted stranger is about: he goes to look.
static func sighted(sim: RefCounted, sheriff: Dictionary, cell: Array) -> void:
	var s: Dictionary = sim.state
	if not sheriff.get("arrest", {}).is_empty(): return
	load("res://sim/law/sheriff.gd").stand_up(s, sheriff)
	if int(sheriff.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, sheriff.job, "SEARCHING")
	sheriff.goal = ""
	sheriff.path = []
	sheriff.search = {"cell": cell.duplicate(), "until": s.tick + SEARCH_TICKS, "path_tick": -100, "next_step": s.tick}
	sheriff.status = "Looking for the wanted stranger"
	_law()._say(sim, int(sheriff.id), "Show me where.")

## A sheriff searching (law.gd calls this while he has no arrest): walk to where you were seen.
static func search(s: Dictionary, sheriff: Dictionary) -> void:
	var look: Dictionary = sheriff.search
	if s.tick >= int(look.until):
		sheriff.search = {}
		sheriff.status = "Back on duty"
		return
	if s.tick < int(look.next_step): return
	var here: Array = s.entities[str(sheriff.id)].cell
	if Vector2(look.cell[0] - here[0], look.cell[1] - here[1]).length() <= 1.5:
		sheriff.search = {}
		sheriff.status = "Lost the trail"
		return
	if sheriff.path.is_empty() or s.tick - int(look.path_tick) >= 30:
		var route: Dictionary = load("res://sim/movement/navigation.gd").request_path(s, here, look.cell)
		sheriff.path = route.path.slice(1) if route.ok else []
		look.path_tick = s.tick
		if not route.ok:
			sheriff.search = {}
			return
	if not sheriff.path.is_empty():
		var next: Array = sheriff.path.pop_front()
		if load("res://sim/world/world_db.gd").walkable(s, next): s.entities[str(sheriff.id)].cell = next
	look.next_step = s.tick + 2

# --- settling up at the office -------------------------------------------------------------------

## "I'll pay the fine": the money goes to the town, the slate is wiped (people still remember).
static func pay_fine(sim: RefCounted, sheriff: Dictionary) -> String:
	var s: Dictionary = sim.state
	var town: int = int(sheriff.settlement)
	var amount: int = fine(s, town)
	var first: String = String(s.entities[str(sheriff.id)].name).split(" ")[0]
	if amount <= 0: return "%s: That's not something a fine will settle." % first
	var coins: int = int(s.accounts.get(str(s.player), 0))
	if coins < amount: return "%s: The fine's %d. You haven't got it." % [first, amount]
	var treasury: String = str(s.settlements[str(town)].warehouse)
	s.accounts[str(s.player)] = coins - amount
	s.accounts[treasury] = int(s.accounts.get(treasury, 0)) + amount
	_law()._law(s).wanted.erase(str(town))
	load("res://sim/world/chronicle.gd").record(s, "fine_paid", town, int(s.player), int(sheriff.id), s.entities[str(s.player)].cell, {"coins": amount})
	_law()._say(sim, int(sheriff.id), "Paid in full. Keep your nose clean.")
	return "%s: %d coins. Paid in full. Keep your nose clean." % [first, amount]

## "I'd like to turn myself in": half the time, and he takes you in.
static func turn_in(sim: RefCounted, sheriff: Dictionary) -> String:
	var s: Dictionary = sim.state
	var town: int = int(sheriff.settlement)
	var record: Dictionary = s.get("law", {}).get("wanted", {}).get(str(town), {})
	var first: String = String(s.entities[str(sheriff.id)].name).split(" ")[0]
	if record.is_empty(): return "%s: You're not wanted here." % first
	if not bool(record.get("turned_in", false)):
		record.hours = maxi(1, (int(record.hours) + 1) / 2)
		record.turned_in = true
	record.face = true
	load("res://sim/law/sheriff.gd").stand_up(s, sheriff)
	sheriff.goal = ""
	sheriff.path = []
	sheriff.search = {}
	sheriff.arrest = {"phase": "standoff", "since": s.tick}
	s.player_control.surrender = true
	s.player_control.running = false
	s.player_path = []
	_law()._say(sim, int(sheriff.id), "Smart choice. Hands behind your back.")
	return "%s: Smart choice. Coming in yourself counts for something: %d hours." % [first, int(record.hours)]
