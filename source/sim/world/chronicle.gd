extends RefCounted
## The world's record of notable happenings: who did what to whom, where, and who saw it. Gossip,
## reputation, wanted posters and the journal read it. Capped at the last MAX entries; witnesses
## are worked out once, when the thing happens (awake people within sight), never per tick.
## Stored as `s.chronicle` (`s.events` is the simulation's own scheduled-event queue).
const Cover = preload("res://sim/combat/cover.gd")
const MAX := 200
const SIGHT := 16

static func entries(s: Dictionary) -> Array:
	if not s.has("chronicle"): s.chronicle = []
	return s.chronicle

## Everyone awake and in sight of `cell`, within SIGHT cells, except those listed, in id order.
static func witnesses(s: Dictionary, cell: Array, except: Array = []) -> Array:
	var result: Array = []
	var reach: int = SIGHT * int(load("res://sim/world/weather.gd").sight_scale(s, cell)) / 100   # fog
	var keys: Array = s.get("residents", {}).keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.id) in except or int(npc.get("health", 0)) <= 0: continue
		if not npc.get("sleeping", {}).is_empty() or not npc.get("knock", {}).is_empty() or not npc.get("migration", {}).is_empty(): continue
		var at: Array = s.entities[key].cell
		if absi(at[0] - cell[0]) > reach or absi(at[1] - cell[1]) > reach: continue
		if Vector2(at[0] - cell[0], at[1] - cell[1]).length() > float(reach): continue
		if Cover.line_clear(s, at, cell): result.append(int(npc.id))
	return result

## Writes one entry and returns it. `actor` and `victim` are entity ids (0 when none).
static func record(s: Dictionary, kind: String, town: int, actor: int, victim: int, cell: Array, extra: Dictionary = {}) -> Dictionary:
	var all: Array = entries(s)
	var next: int = int(s.get("chronicle_next", 1))
	s.chronicle_next = next + 1
	var entry := {"id": next, "tick": int(s.tick), "kind": kind, "town": town, "actor": actor, "victim": victim,
		"cell": [int(cell[0]), int(cell[1])], "witnesses": witnesses(s, cell, [actor, victim])}
	for key in extra: entry[key] = extra[key]
	all.append(entry)
	while all.size() > MAX: all.pop_front()
	load("res://sim/entities/gossip.gd").witnessed(s, entry)   # who saw it knows it first
	return entry

## Entries since `since_tick`, optionally only in one town and of some kinds, oldest first.
static func recent(s: Dictionary, since_tick: int, town: int = 0, kinds: Array = []) -> Array:
	var result: Array = []
	for entry in s.get("chronicle", []):
		if int(entry.tick) < since_tick: continue
		if town != 0 and int(entry.town) != town: continue
		if not kinds.is_empty() and str(entry.kind) not in kinds: continue
		result.append(entry)
	return result

static func find(s: Dictionary, id: int) -> Dictionary:
	for entry in s.get("chronicle", []):
		if int(entry.id) == id: return entry
	return {}
