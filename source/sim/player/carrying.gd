extends RefCounted
## Carrying a person: pick up someone knocked out or dead, carry them over the shoulder (slowly:
## it counts as an overload, so no running), and put them down somewhere else. Anyone who sees
## you carrying a body knows something is wrong and it becomes a witnessed crime. A body left
## lying where people pass is found; one put down out of sight may never be.
const Brawl = preload("res://sim/combat/brawl.gd")
const Cover = preload("res://sim/combat/cover.gd")
const WEIGHT_TENTHS := 250        # a grown person: 25.0, far over a pack's limit
const SEEN_RANGE := 10
const CHECK_EVERY := 60
const FIND_RANGE := 10

static func carried(s: Dictionary) -> int:
	return int(s.get("player_control", {}).get("carrying", {}).get("id", 0))

static func can_carry(s: Dictionary, npc: Dictionary) -> bool:
	return not npc.is_empty() and (bool(npc.get("dead", false)) or int(npc.get("health", 0)) <= 0 or Brawl.knocked(s, npc)) and carried(s) == 0

static func pick_up(s: Dictionary, id: int) -> void:
	var pc: Dictionary = s.player_control
	var npc: Dictionary = s.get("residents", {}).get(str(id), {})
	if not can_carry(s, npc):
		pc.notice = "You can only carry someone who is out cold." if not npc.is_empty() else "There's nobody to carry."
		return
	pc.carrying = {"id": id, "since": int(s.tick)}
	npc.carried_by = int(s.player)
	npc.goal = ""
	npc.path = []
	pc.held_item = ""
	pc.held_quantity = 0
	s.entities[str(id)].cell = s.entities[str(s.player)].cell.duplicate()
	pc.notice = "You heave %s over your shoulder. F puts them down." % s.entities[str(id)].name
	if int(npc.get("health", 0)) <= 0: load("res://sim/player/look.gd").bloodied(s, 10)

static func put_down(s: Dictionary, quiet: bool = false) -> void:
	var pc: Dictionary = s.get("player_control", {})
	var id: int = carried(s)
	if id == 0: return
	pc.carrying = {}
	var npc: Dictionary = s.get("residents", {}).get(str(id), {})
	if not npc.is_empty():
		npc.erase("carried_by")
		npc.erase("seen_carried")
		npc.found = false
	s.entities[str(id)].cell = s.entities[str(s.player)].cell.duplicate()
	if not quiet: pc.notice = "You put %s down." % s.entities[str(id)].name

## Every tick: the body moves with you; you drop it if you're knocked down, cuffed or killed; a
## knocked-out person who comes round struggles free; and every so often, anyone who sees you
## carrying a body raises the alarm.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var id: int = carried(s)
	if id != 0:
		var npc: Dictionary = s.residents.get(str(id), {})
		var Law = load("res://sim/law/law.gd")
		if npc.is_empty() or Brawl.player_down(s) or Law.restrained(s) or bool(s.player_control.get("dead", false)):
			put_down(s, true)
		elif int(npc.get("health", 0)) > 0 and not Brawl.knocked(s, npc):
			put_down(s, true)   # they came round on your shoulder
			s.player_control.notice = "%s comes round and struggles free!" % s.entities[str(id)].name
			load("res://sim/factions/society.gd").remember(s, id, "assaulted", int(s.player), "The stranger carried me off.")
		else:
			s.entities[str(id)].cell = s.entities[str(s.player)].cell.duplicate()
			if s.tick % CHECK_EVERY == 0: _seen_carrying(s, npc)
	if s.tick % CHECK_EVERY == 30: _find_bodies(sim)

## Somebody saw you carrying them: a crime with witnesses (murder if they are dead).
static func _seen_carrying(s: Dictionary, npc: Dictionary) -> void:
	var player: Array = s.entities[str(s.player)].cell
	var seen: Array = npc.get("seen_carried", [])
	var Chronicle = load("res://sim/world/chronicle.gd")
	var new_eyes: Array = Chronicle.witnesses(s, player, [int(s.player), int(npc.id)]).filter(func(w): return not w in seen and Vector2(s.entities[str(w)].cell[0] - player[0], s.entities[str(w)].cell[1] - player[1]).length() <= SEEN_RANGE)
	if new_eyes.is_empty(): return
	npc.seen_carried = seen + new_eyes
	load("res://sim/law/law.gd").crime(s, int(npc.settlement), "murder" if int(npc.get("health", 0)) <= 0 else "assault", int(npc.id))

## Bodies lying where people can see them are found (once): it's news, and the family mourns.
static func _find_bodies(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var Chronicle = load("res://sim/world/chronicle.gd")
	var keys: Array = s.get("residents", {}).keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.get("health", 1)) > 0 or bool(npc.get("found", false)) or npc.has("carried_by"): continue
		var cell: Array = s.entities[key].cell
		var finders: Array = Chronicle.witnesses(s, cell, [int(npc.id)]).filter(func(w): return Vector2(s.entities[str(w)].cell[0] - cell[0], s.entities[str(w)].cell[1] - cell[1]).length() <= FIND_RANGE)
		if finders.is_empty(): continue
		npc.found = true
		Chronicle.record(s, "body_found", int(npc.settlement), int(finders[0]), int(npc.id), cell)
		load("res://sim/law/law.gd")._say(sim, int(finders[0]), "Oh no... %s! Somebody fetch the sheriff!" % String(s.entities[key].name).split(" ")[0])
		if not bool(npc.get("buried", false)): load("res://sim/law/investigation.gd").body_found(sim, npc, s.residents.get(str(finders[0]), {}))
