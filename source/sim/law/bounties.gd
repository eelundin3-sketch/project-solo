extends RefCounted
## Bounties on the gang, and bringing bandits in. Every town's sheriff pays for bandits brought to
## his office: alive (a bandit who gave up, tied and led on a rope) pays the full bounty; dead (the
## body carried in over your shoulder) half. The leader is worth more. The money comes out of the
## town's purse (as much as it holds), so money is conserved; the town hears of it (reputation
## "bounty"). A tied prisoner follows you a step behind; he slips away if you're knocked down or
## taken. Deterministic.
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const ALIVE := 40
const LEADER := 100
const DEAD_PERCENT := 50
const HAND_IN_RANGE := 4.0      # the prisoner must be this close when you hand him in

static func _law() -> GDScript: return load("res://sim/law/law.gd")

static func reward(s: Dictionary, bandit: Dictionary, alive: bool) -> int:
	var full: int = LEADER if int(bandit.id) == int(s.get("bandits", {}).get("leader", -1)) else ALIVE
	return full if alive else full * DEAD_PERCENT / 100

## A bandit who has given up and stands within reach: you can tie him.
static func can_tie(s: Dictionary, npc: Dictionary) -> bool:
	if npc.is_empty() or int(npc.get("bandit", 0)) == 0 or int(npc.get("health", 0)) <= 0: return false
	if not bool(npc.get("surrendered", false)) or npc.has("prisoner_of") or not npc.get("jailed", {}).is_empty(): return false
	var me: Array = s.entities[str(s.player)].cell
	var at: Array = s.entities[str(npc.id)].cell
	return maxi(absi(me[0] - at[0]), absi(me[1] - at[1])) <= 1

static func tie(sim: RefCounted, npc: Dictionary) -> String:
	var s: Dictionary = sim.state
	if not can_tie(s, npc): return ""
	npc.prisoner_of = int(s.player)
	npc.surrendered = false
	npc.cuffed = true
	npc.gun_out = false
	npc.cover_cycle = {}
	npc.erase("fleeing")
	npc.erase("errand")
	npc.path = []
	npc.status = "Tied up, led by the stranger"
	_law()._say(sim, int(npc.id), "Easy with that rope...")
	return "You tie %s's hands. He'll follow you. Take him to any sheriff's office for the bounty." % String(s.entities[str(npc.id)].name).split(" ")[0]

static func prisoners(s: Dictionary) -> Array:
	var result: Array = []
	for id in s.get("bandits", {}).get("members", []):
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty() and int(npc.get("prisoner_of", 0)) == int(s.player): result.append(npc)
	return result

## Every tick: prisoners follow you a step behind; if you go down or are taken, they slip away.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("bandits") or not s.has("player_control"): return
	var pc: Dictionary = s.player_control
	var me: Array = s.entities[str(s.player)].cell
	for npc in prisoners(s):
		if Brawl.player_down(s) or not pc.get("captive", {}).is_empty() or _law().in_custody(s) or bool(pc.get("dead", false)):
			npc.erase("prisoner_of")
			npc.cuffed = false
			npc.status = "Slipped his rope"
			_law()._say(sim, int(npc.id), "So long, friend!")
			load("res://sim/law/outlaw_arrest.gd")._head_back(s, npc)
			continue
		if s.tick % 3 != int(npc.id) % 3: continue
		var at: Array = s.entities[str(npc.id)].cell
		if maxi(absi(me[0] - at[0]), absi(me[1] - at[1])) <= 1: continue
		if npc.path.is_empty() or s.tick - int(npc.get("path_tick", -100)) >= 15:
			var route: Dictionary = Nav.request_path(s, at, me)
			npc.path = route.path.slice(1) if route.ok else []
			npc.path_tick = s.tick
		if not npc.path.is_empty():
			var next: Array = npc.path.pop_front()
			if World.walkable(s, next) and next != me: s.entities[str(npc.id)].cell = next

## Something to hand in to this sheriff: a prisoner close by, or a dead bandit on your shoulder.
static func can_hand_in(s: Dictionary, sheriff: Dictionary) -> bool:
	return not _bringing(s).is_empty()

static func _bringing(s: Dictionary) -> Array:
	var result: Array = []
	var me: Array = s.entities[str(s.player)].cell
	for npc in prisoners(s):
		var at: Array = s.entities[str(npc.id)].cell
		if Vector2(at[0] - me[0], at[1] - me[1]).length() <= HAND_IN_RANGE: result.append([npc, true])
	var Carrying = load("res://sim/player/carrying.gd")
	var body: Dictionary = s.residents.get(str(Carrying.carried(s)), {})
	if not body.is_empty() and int(body.get("bandit", 0)) != 0 and int(body.get("health", 0)) <= 0: result.append([body, false])
	return result

## "I've brought in one of the bandits": paid from the town's purse; the living are locked up, the
## dead laid to rest.
static func hand_in(sim: RefCounted, sheriff: Dictionary) -> String:
	var s: Dictionary = sim.state
	var town: int = int(sheriff.settlement)
	var treasury: String = str(s.settlements[str(town)].warehouse)
	var total := 0
	var count := 0
	for pair in _bringing(s):
		var npc: Dictionary = pair[0]
		var alive: bool = pair[1]
		var pay: int = mini(reward(s, npc, alive), int(s.accounts.get(treasury, 0)))
		s.accounts[treasury] = int(s.accounts.get(treasury, 0)) - pay
		s.accounts[str(s.player)] = int(s.accounts.get(str(s.player), 0)) + pay
		total += pay
		count += 1
		load("res://sim/world/chronicle.gd").record(s, "bounty", town, int(s.player), int(npc.id), s.entities[str(s.player)].cell, {"coins": pay, "alive": alive})
		if alive:
			npc.erase("prisoner_of")
			npc.errand = {"kind": "prisoner", "town": town, "phase": "held"}   # off the gang's books until released
			load("res://sim/law/outlaw_arrest.gd")._lock_up(sim, sheriff, npc, town)
		else:
			load("res://sim/player/carrying.gd").put_down(s, true)
			npc.buried = true
			npc.status = "Laid to rest"
	if count == 0: return ""
	_law()._say(sim, int(sheriff.id), "Good work. Here's what's owed.")
	return "%s pays you %d coins for %d bandit%s." % [String(s.entities[str(sheriff.id)].name).split(" ")[0], total, count, "" if count == 1 else "s"]

## What each town pays, for the sheriff and the journal.
static func notice(s: Dictionary) -> String:
	if not s.has("bandits") or bool(s.bandits.get("cleared", false)): return "No bounties posted. The roads are quiet."
	var left: int = 0
	for id in s.bandits.members:
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty() and int(npc.health) > 0 and npc.get("jailed", {}).is_empty() and not bool(npc.get("gone", false)): left += 1
	return "%d coins a head for the bandits out in the wilds, %d for their leader. Half if they're dead. %d still at large." % [ALIVE, LEADER, left]
