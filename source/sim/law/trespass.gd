extends RefCounted
## People claim their space. Walk into someone's home uninvited and whoever is in tells you to get
## out; stay and they get angrier (three warnings, a minute and a half apart). Then, if they're
## angry enough, they throw you out themselves; otherwise one runs for the sheriff (trespassing).
## At night the first warning is the only one. Family, close friends (opinion 35 or more) and
## invited guests are welcome. Shops and workshops are open from 06:00 to 21:00; the storehouse
## market, the sheriff's office and the common lodges are always open. Checked every 10 ticks.
const World = preload("res://sim/world/world_db.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const CHECK_EVERY := 10
const WARN_EVERY := 150
const WARNINGS := 3
const WELCOME_AT := 35
const RETURN_TICKS := 600       # back within an hour, and they remember the warnings
const SHOP_KINDS := ["sawmill", "bakery", "forge"]
const LINES := ["Hey! Get out of my house!", "I said OUT! This is my home!", "Last warning, stranger!"]
const CLOSED_LINES := ["We're closed. Come back in the morning.", "I said we're closed!", "Out, or I fetch the sheriff!"]

## The building with a footprint covering `cell`, or {}.
static func building_at(s: Dictionary, cell: Array) -> Dictionary:
	for entity in World.buildings(s):
		var f: Array = entity.footprint
		if cell[0] >= f[0] and cell[1] >= f[1] and cell[0] < f[0] + f[2] and cell[1] < f[1] + f[3]: return entity
	return {}

## Shops are open 07:00-21:00, from when people are up until they go to bed.
static func _open_hours(s: Dictionary) -> bool:
	var minute: int = (int(s.tick) / 10) % 1440
	return minute >= 420 and minute < 1260

static func _night(s: Dictionary) -> bool:
	return load("res://sim/world/day_clock.gd").is_night(s)

## "private" (someone's home), "closed" (a shop out of hours) or "" (you may be here).
static func kind_of_place(s: Dictionary, building: Dictionary) -> String:
	if building.is_empty(): return ""
	if building.kind in SHOP_KINDS: return "" if _open_hours(s) else "closed"
	if building.kind != "home": return ""
	if bool(building.get("player_house", false)): return ""   # your own house
	for town in s.get("settlements", {}).values():
		if int(town.get("home", 0)) == int(building.id): return ""   # the common lodge
	for household in s.get("households", {}).values():
		if int(household.home) == int(building.id): return "private"
	return ""

static func _welcome(s: Dictionary, building: Dictionary, present: Array) -> bool:
	var invited: Dictionary = s.get("player_status", {}).get("invited", {})
	if int(invited.get(str(building.id), -1)) > int(s.tick): return true
	var mine: Dictionary = s.get("households", {}).get("player", {})
	if not mine.is_empty() and int(mine.get("home", 0)) == int(building.id): return true
	var Society = load("res://sim/factions/society.gd")
	for npc in present:
		if Society.opinion(s, int(npc.id), int(s.player)) >= WELCOME_AT: return true
	return false

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if s.tick % CHECK_EVERY != 0 or not s.has("player_control") or not s.has("residents"): return
	var pc: Dictionary = s.player_control
	var Law = load("res://sim/law/law.gd")
	if bool(pc.get("dead", false)) or Law.in_custody(s) or Law.restrained(s): return
	var record: Dictionary = pc.get("trespass", {})
	var building: Dictionary = building_at(s, s.entities[str(s.player)].cell)
	var place: String = kind_of_place(s, building)
	if place.is_empty():
		if not record.is_empty() and not record.has("left"): record.left = int(s.tick)
		return
	# Who is in, awake and on their feet.
	var present: Array = []
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.health) <= 0 or Brawl.knocked(s, npc) or not npc.get("sleeping", {}).is_empty() or npc.occupation == "Child": continue
		if building_at(s, s.entities[key].cell).get("id", -1) == building.id: present.append(npc)
	if present.is_empty() or _welcome(s, building, present): return
	# Back in the same place within the hour: they remember; anywhere else starts afresh.
	if record.is_empty() or int(record.building) != int(building.id) or (record.has("left") and int(s.tick) - int(record.left) > RETURN_TICKS):
		record = {"building": int(building.id), "since": int(s.tick), "warnings": 0, "next": int(s.tick)}
		pc.trespass = record
	record.erase("left")
	if int(s.tick) < int(record.next) or bool(record.get("done", false)): return
	var speaker: Dictionary = present[0]
	var final: bool = int(record.warnings) >= WARNINGS or (_night(s) and int(record.warnings) >= 1)
	if not final:
		var lines: Array = CLOSED_LINES if place == "closed" else LINES
		Law._say(sim, int(speaker.id), lines[mini(int(record.warnings), lines.size() - 1)])
		pc.notice = "%s wants you out." % String(s.entities[str(speaker.id)].name).split(" ")[0]
		for npc in present:
			npc.anger = mini(100, int(npc.get("anger", 0)) + 25)
			load("res://sim/factions/society.gd").remember(s, int(npc.id), "insulted", int(s.player), "The stranger barged into our home.")
		record.warnings = int(record.warnings) + 1
		record.next = int(s.tick) + WARN_EVERY
		return
	# Enough: thrown out by an angry householder, or reported to the sheriff.
	record.done = true
	for npc in present:
		if int(npc.get("anger", 0)) >= Brawl.HOSTILE_AT and npc.occupation != "Sheriff":
			Law._say(sim, int(npc.id), "Right. OUT!")
			Brawl.engage(s, npc, "shove")
			return
	Law._say(sim, int(speaker.id), "That's it, I'm getting the sheriff!")
	Law.crime(s, int(building.get("settlement", speaker.settlement)), "trespass", int(speaker.id))
