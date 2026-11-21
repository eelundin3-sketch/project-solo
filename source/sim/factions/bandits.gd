extends RefCounted
## A bandit camp far out in the wilds: three bandits around a fire, tents, and a pile of loot.
## They lounge about by day and sleep at night. Come near and the leader demands your coins and
## your gun. Hand them over (surrender) and they rob you, and may tie you up at the camp. Refuse,
## run or fight and they shoot until you surrender, are knocked down or die, or they are beaten.
## Tied up, you slip free at night once they are all asleep (or after about a day). Beat them and
## their loot is yours, and every town hears of it.
##
## Bandits are residents with no town (settlement 0, occupation "Bandit", `bandit` = true), so
## the town systems (jobs, families, trades, the law's towns) pass them by; this file runs them.
## Deterministic: stream "bandits". Coins move between accounts, goods by Inventory.transfer.
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const MEMBERS := 3
const NOTICE_RANGE := 14       # an awake bandit notices you this close to the camp
const SLEEPER_RANGE := 3       # a sleeping one only this close
const DEMAND_WAIT := 150       # ticks they wait for you to hand things over
const SHOOT_RANGE := 11
const SHOT_EVERY := 45
const GIVE_UP_RANGE := 32      # they stop chasing you this far from the camp
const CAPTIVE_MIN := 1200      # held at least two hours before you can slip free at night
const CAPTIVE_MAX := 14400     # and never longer than a day
const COOLDOWN := 14400        # after robbing you they leave you alone for a day
const LOOT := ["rifle", "shotgun", "cartridge", "shell", "lantern"]
const LINES := {
	"demand": ["Hold it right there. Coins and the gun, now.", "That's far enough, friend. Empty your pockets.", "Easy now. Hand over your valuables and nobody gets hurt."],
	"robbed": ["Pleasure doing business.", "Much obliged, stranger.", "Now that wasn't so hard."],
	"let_go": ["Now get out of here.", "Off you go. Don't come back.", "Run along now."],
	"captive": ["Tie this one up. Might be worth something.", "You're staying with us a while.", "Sit down and keep quiet."],
	"fight": ["Wrong choice!", "Get him!", "You'll regret that!"],
	"give_up": ["Let him run.", "Not worth the bullets.", "And stay away!"],
	"beaten": ["Don't shoot! We're done!", "Enough! You win!"],
	"chat": ["Quiet out here.", "Pass the coffee.", "Reckon a caravan's due soon.", "My boots are falling apart.", "Who's on watch tonight?", "Fine evening for it."],
}

# --- setting up --------------------------------------------------------------------------------

## Places the camp and its three bandits once (a new game, or an older save on load).
static func ensure_camp(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	# Full games only (towns with families); bare test worlds get no camp.
	if s.has("bandits") or not s.has("settlements") or not s.has("residents") or not s.has("accounts") or not s.has("households"): return
	var spot: Array = _camp_spot(s)
	if spot.is_empty(): return
	var camp_id: int = World.add_entity(sim, "bandit_camp", "Bandit camp", spot, 0)
	var stash: int = World.add_entity(sim, "stash", "Bandit loot", [spot[0] + 3, spot[1] - 2], 0)
	Inventory.create(s, stash, 200)
	for item in {"food": 8, "bandage": 2, "cartridge": 6}.keys():   # recorded as made, so goods stay accounted for
		Inventory.produce(s, stash, item, {"food": 8, "bandage": 2, "cartridge": 6}[item])
	var members: Array = []
	var Residents = load("res://sim/entities/residents.gd")
	for i in range(MEMBERS):
		var cell: Array = _seat(spot, i)
		var id: int = Residents.add_resident(sim, 0, cell)
		var npc: Dictionary = s.residents[str(id)]
		npc.occupation = "Bandit"
		npc.bandit = camp_id
		npc.status = "Lounging by the fire"
		Inventory.produce(s, id, "rifle", 1)
		members.append(id)
	s.bandits = {"camp": camp_id, "cell": spot.duplicate(), "stash": stash, "members": members, "phase": "idle",
		"since": s.tick, "leader": members[0], "cooldown_until": 0, "cleared": false, "health": {}}
	sim.record("Somewhere out in the wilds, a band of outlaws has made camp.")

## The camp spot: as far from every town as the map allows, well off the roads, on open ground.
static func _camp_spot(s: Dictionary) -> Array:
	var TownLayout = load("res://sim/world/town_layout.gd")
	var bounds: Array = s.world.get("bounds", [-96, -84, 486, 336])
	var best: Array = []
	var best_score := -1
	var y: int = int(bounds[1]) + 24
	while y < int(bounds[3]) - 24:
		var x: int = int(bounds[0]) + 24
		while x < int(bounds[2]) - 24:
			var score := 1 << 60
			for town in s.settlements.values():
				var store: Array = s.entities[str(town.warehouse)].cell
				score = mini(score, (store[0] - x) * (store[0] - x) + (store[1] - y) * (store[1] - y))
			if score > best_score and _clear(s, TownLayout, [x, y]):
				best_score = score
				best = [x, y]
			x += 12
		y += 12
	return best

static func _clear(s: Dictionary, TownLayout: GDScript, at: Array) -> bool:
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			var c: Array = [at[0] + dx, at[1] + dy]
			if not World.walkable(s, c) or World.inside_building(s, c) != 0: return false
	for r in [6, 10]:
		for d in [[r, 0], [-r, 0], [0, r], [0, -r], [r, r], [-r, -r], [r, -r], [-r, r]]:
			if TownLayout.on_road(s, [at[0] + d[0], at[1] + d[1]]): return false
	return true

## Where each bandit sits by the fire.
static func _seat(spot: Array, i: int) -> Array:
	return [[spot[0] - 2, spot[1] + 1], [spot[0] + 2, spot[1] + 1], [spot[0], spot[1] + 2]][i % 3]

## Where a bandit sleeps (in front of the tents) and where a captive is tied (the post).
static func _bed(spot: Array, i: int) -> Array:
	return [[spot[0] - 3, spot[1] - 2], [spot[0], spot[1] - 3], [spot[0] + 3, spot[1] - 3]][i % 3]

static func post(s: Dictionary) -> Array:
	var spot: Array = s.bandits.cell
	return [spot[0] - 4, spot[1] + 2]

# --- questions other systems ask ---------------------------------------------------------------

static func is_bandit(s: Dictionary, id: int) -> bool:
	return int(s.get("residents", {}).get(str(id), {}).get("bandit", 0)) != 0

static func captive(s: Dictionary) -> bool:
	return not s.get("player_control", {}).get("captive", {}).is_empty()

## True while the bandits are demanding your valuables or fighting you (you may surrender).
static func demanding(s: Dictionary) -> bool:
	return s.has("bandits") and str(s.bandits.phase) in ["demand", "fight"]

static func _members(s: Dictionary) -> Array:
	var result: Array = []
	for id in s.bandits.members:
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty(): result.append(npc)
	return result

static func _able(s: Dictionary, npc: Dictionary) -> bool:
	return not npc.get("dead", false) and int(npc.health) > 0 and npc.get("knock", {}).is_empty() and s.entities.has(str(npc.id))

static func _say(sim: RefCounted, npc: Dictionary, topic: String) -> void:
	var lines: Array = LINES[topic]
	var s: Dictionary = sim.state
	if not s.has("speech"): s.speech = []
	s.speech.append({"speaker": int(npc.id), "text": lines[sim.random_int("bandits", 0, lines.size() - 1)], "tick": s.tick, "until": s.tick + 60})
	while s.speech.size() > 30: s.speech.pop_front()

# --- every tick --------------------------------------------------------------------------------

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("bandits") or not s.has("player_control"): return
	var b: Dictionary = s.bandits
	if captive(s): _captive(sim)
	if bool(b.cleared):
		if s.tick % 30 == 0: _leave(sim)
		return
	if s.tick % 2 != 0: return
	var pc: Dictionary = s.player_control
	var player: Array = s.entities[str(s.player)].cell
	var camp: Array = b.cell
	var from_camp: int = maxi(absi(player[0] - camp[0]), absi(player[1] - camp[1]))
	var members: Array = _members(s)
	var able: Array = members.filter(func(n: Dictionary) -> bool: return _able(s, n))
	if able.is_empty():
		_cleared(sim)
		return
	var hurt: bool = _hurt_since_last(s, members)
	if bool(pc.get("dead", false)):
		if str(b.phase) != "idle": _home(sim, "idle")
	elif str(b.phase) == "idle":
		if s.tick % 10 == 0: _idle(sim, able)
		var shot: int = int(s.get("shotgun", {}).get("last_shot", -1000))
		if hurt or (from_camp <= NOTICE_RANGE + 8 and shot > s.tick - 4):
			_start_fight(sim, able)
		elif not captive(s) and s.tick >= int(b.cooldown_until) and _notices(s, able, player, from_camp):
			_start_demand(sim, able)
	elif str(b.phase) == "demand":
		_demand(sim, able, player, from_camp, hurt)
	elif str(b.phase) == "fight":
		_fight(sim, able, player, from_camp)

## Damage taken since the last check (the player shot, stabbed or punched one of them).
static func _hurt_since_last(s: Dictionary, members: Array) -> bool:
	var hurt := false
	for npc in members:
		var before: int = int(s.bandits.health.get(str(npc.id), 100))
		var now: int = int(npc.health) if not npc.get("dead", false) else 0
		if now < before or not npc.get("brawl", {}).is_empty(): hurt = true
		s.bandits.health[str(npc.id)] = now
	return hurt

## Lounging: drifting about the fire, chatting; asleep in front of the tents at night.
static func _idle(sim: RefCounted, able: Array) -> void:
	var s: Dictionary = sim.state
	var spot: Array = s.bandits.cell
	for i in range(able.size()):
		var npc: Dictionary = able[i]
		var index: int = s.bandits.members.find(int(npc.id))
		var entity: Dictionary = s.entities[str(npc.id)]
		if DayClock.bed_hours(s, npc):
			if npc.get("sleeping", {}).is_empty():
				var bed: Array = _bed(spot, index)
				entity.cell = bed.duplicate()
				npc.sleeping = {"lie": bed.duplicate(), "approach": bed.duplicate(), "rot": 1, "bed_rect": [], "night": true, "since": s.tick}
				npc.status = "Asleep by the tents"
			continue
		if not npc.get("sleeping", {}).is_empty():
			npc.sleeping = {}
			entity.cell = _seat(spot, index)
		npc.status = "Lounging by the fire"
		if s.tick % 300 == int(npc.id) % 30 * 10:
			var seat: Array = _seat(spot, index)
			var c: Array = [seat[0] + sim.random_int("bandits", -1, 1), seat[1] + sim.random_int("bandits", -1, 1)]
			if World.walkable(s, c): entity.cell = c
	if s.tick % 1200 == 0 and able.size() >= 2 and able[0].get("sleeping", {}).is_empty() and able[1].get("sleeping", {}).is_empty():
		_say(sim, able[0], "chat")

static func _notices(s: Dictionary, able: Array, player: Array, from_camp: int) -> bool:
	if from_camp > NOTICE_RANGE: return false
	for npc in able:
		var reach: int = SLEEPER_RANGE if not npc.get("sleeping", {}).is_empty() else NOTICE_RANGE
		var at: Array = s.entities[str(npc.id)].cell
		if maxi(absi(at[0] - player[0]), absi(at[1] - player[1])) <= reach: return true
	return false

static func _wake_all(s: Dictionary, able: Array) -> void:
	for npc in able:
		if not npc.get("sleeping", {}).is_empty():
			npc.sleeping = {}

static func _leader(s: Dictionary, able: Array) -> Dictionary:
	for npc in able:
		if int(npc.id) == int(s.bandits.leader): return npc
	return able[0]

static func _start_demand(sim: RefCounted, able: Array) -> void:
	var s: Dictionary = sim.state
	_wake_all(s, able)
	s.bandits.phase = "demand"
	s.bandits.since = s.tick
	var leader: Dictionary = _leader(s, able)
	leader.status = "Demanding your valuables"
	_say(sim, leader, "demand")
	s.player_control.notice = "Bandits! %s wants your coins and your gun. Surrender (F) to hand them over, or fight." % s.entities[str(leader.id)].name

## The leader walks up to you and waits. Hand things over (surrender) and you are robbed; walk
## off, wait too long or hurt one of them and they fight.
static func _demand(sim: RefCounted, able: Array, player: Array, from_camp: int, hurt: bool) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var leader: Dictionary = _leader(s, able)
	if bool(pc.get("surrender", false)):
		_rob(sim, leader)
		pc.surrender = false
		if sim.random_int("bandits", 0, 99) < 50:
			_take_captive(sim, leader)
		else:
			_say(sim, leader, "let_go")
			pc.notice = "The bandits take your coins and your gun and let you go."
		_home(sim, "idle")
		s.bandits.cooldown_until = s.tick + COOLDOWN
		return
	if hurt or from_camp > NOTICE_RANGE + 6 or s.tick - int(s.bandits.since) > DEMAND_WAIT:
		_start_fight(sim, able)
		return
	var at: Array = s.entities[str(leader.id)].cell
	if maxi(absi(at[0] - player[0]), absi(at[1] - player[1])) > 2 and s.tick % 4 == 0: _step(s, leader, player)

static func _start_fight(sim: RefCounted, able: Array) -> void:
	var s: Dictionary = sim.state
	_wake_all(s, able)
	s.bandits.phase = "fight"
	s.bandits.since = s.tick
	_say(sim, _leader(s, able), "fight")
	for npc in able: npc.status = "Fighting you"
	s.player_control.notice = "The bandits open fire! Surrender (F) to give up."

## Fighting: each bandit closes to rifle range and shoots. You give up (surrender) or go down:
## they rob you and tie you up. Run far enough and they let you go.
static func _fight(sim: RefCounted, able: Array, player: Array, from_camp: int) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var Brawl = load("res://sim/combat/brawl.gd")
	if bool(pc.get("surrender", false)) or Brawl.player_down(s):
		var leader: Dictionary = _leader(s, able)
		_rob(sim, leader)
		pc.surrender = false
		_take_captive(sim, leader)
		_home(sim, "idle")
		s.bandits.cooldown_until = s.tick + COOLDOWN
		return
	if from_camp > GIVE_UP_RANGE:
		_say(sim, able[0], "give_up")
		_home(sim, "idle")
		s.bandits.cooldown_until = s.tick + COOLDOWN / 4
		return
	var Gunfire = load("res://sim/combat/gunfire.gd")
	for npc in able:
		if not npc.get("brawl", {}).is_empty(): continue   # in a fistfight with you (brawl.gd)
		var at: Array = s.entities[str(npc.id)].cell
		var gap: float = Vector2(player[0] - at[0], player[1] - at[1]).length()
		if gap > SHOOT_RANGE - 2:
			if s.tick % 4 == int(npc.id) % 4: _step(s, npc, player)
		elif s.tick >= int(npc.get("next_shot", 0)):
			npc.next_shot = s.tick + SHOT_EVERY + sim.random_int("bandits", 0, 20)
			Gunfire.fire_at_player(sim, npc, at, true)

static func _step(s: Dictionary, npc: Dictionary, goal: Array) -> void:
	var entity: Dictionary = s.entities[str(npc.id)]
	if npc.get("path", []).is_empty() or int(npc.get("path_tick", -1000)) < s.tick - 40:
		var route := Nav.request_path(s, entity.cell, goal)
		npc.path = route.path if route.ok else []
		npc.path_tick = s.tick
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next) and next != goal: entity.cell = next

## Everyone back to their seats by the fire.
static func _home(sim: RefCounted, phase: String) -> void:
	var s: Dictionary = sim.state
	s.bandits.phase = phase
	s.bandits.since = s.tick
	var members: Array = _members(s)
	for i in range(members.size()):
		var npc: Dictionary = members[i]
		npc.path = []
		if _able(s, npc):
			s.entities[str(npc.id)].cell = _seat(s.bandits.cell, i)
			npc.status = "Lounging by the fire"

# --- robbing, captivity, escape ----------------------------------------------------------------

## They take your coins (to the leader's purse) and your guns, ammunition and lantern (to their
## loot pile). Nothing is created or lost.
static func _rob(sim: RefCounted, leader: Dictionary) -> void:
	var s: Dictionary = sim.state
	var gun: Dictionary = s.get("shotgun", {})
	if not gun.is_empty() and bool(gun.get("equipped", false)): load("res://sim/combat/shotgun.gd").toggle(s)
	var pc: Dictionary = s.player_control
	if int(pc.get("held_quantity", 0)) > 0: load("res://sim/player/player_actions.gd").hold(s, "")
	var coins: int = int(s.accounts.get(str(s.player), 0))
	if coins > 0:
		s.accounts[str(s.player)] = 0
		s.accounts[str(leader.id)] = int(s.accounts.get(str(leader.id), 0)) + coins
	var taken: Array = []
	for item in LOOT:
		var amount: int = Inventory.amount(s, int(s.player), item)
		if amount > 0 and Inventory.transfer(s, int(s.player), int(s.bandits.stash), item, amount).ok: taken.append(item)
	s.bandits.last_take = {"coins": coins, "items": taken, "tick": s.tick}
	_say(sim, leader, "robbed")
	load("res://sim/world/chronicle.gd").record(s, "robbed_by_bandits", 0, int(leader.id), int(s.player), s.entities[str(s.player)].cell, {"coins": coins})

## Tied to the post at the camp.
static func _take_captive(sim: RefCounted, leader: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	s.entities[str(s.player)].cell = post(s)
	s.player_path = []
	pc.knock = {}
	pc.running = false
	pc.pending = {}
	pc.captive = {"since": s.tick}
	_say(sim, leader, "captive")
	pc.notice = "The bandits tie you up at their camp. Wait for them to sleep."

## Held at the camp: you slip free at night once every bandit is asleep (after two hours at least),
## or after a day whatever happens. Your things stay in their loot pile.
static func _captive(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	if s.tick % 20 != 0: return
	var since: int = int(pc.captive.since)
	var all_asleep := true
	for npc in _members(s):
		if _able(s, npc) and npc.get("sleeping", {}).is_empty(): all_asleep = false
	var cleared: bool = bool(s.bandits.get("cleared", false))
	if cleared or s.tick - since >= CAPTIVE_MAX or (all_asleep and s.tick - since >= CAPTIVE_MIN):
		pc.captive = {}
		pc.notice = "You work the ropes loose and slip free. Your things are in their loot pile." if all_asleep else "The bandits cut you loose and tell you to go."
		sim.record("The traveller slipped free of the bandits.")

# --- beaten ------------------------------------------------------------------------------------

## Every bandit is dead or down: the camp is cleared. Their loot pile is yours to take, the
## leader's purse is on him, and every town hears of it.
static func _cleared(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var b: Dictionary = s.bandits
	if bool(b.cleared): return
	b.cleared = true
	b.phase = "cleared"
	b.since = s.tick
	var towns: Array = s.settlements.keys().map(func(k): return int(k))
	towns.sort()
	load("res://sim/world/chronicle.gd").record(s, "bandits_cleared", 0, int(s.player), 0, b.cell, {"heard_in": towns})
	s.player_control.notice = "The bandits are beaten. Their loot is yours, and the towns will hear of it."
	sim.record("The traveller drove the bandits from their camp.")

## Beaten bandits who come round have had enough: they sit by the fire and never fight again.
static func _leave(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var members: Array = _members(s)
	for i in range(members.size()):
		var npc: Dictionary = members[i]
		if not _able(s, npc) or npc.has("beaten"): continue
		npc.beaten = true
		npc.status = "Beaten; keeping out of your way"
		s.entities[str(npc.id)].cell = _seat(s.bandits.cell, i)
		_say(sim, npc, "beaten")
