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
	if s.has("bandits") and not bool(s.bandits.get("props", false)): _place_props(s)
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
	_place_props(s)
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
	for dy in range(-9, 8):
		for dx in range(-9, 10):
			var c: Array = [at[0] + dx, at[1] + dy]
			if not World.walkable(s, c) or World.inside_building(s, c) != 0: return false
	for r in [6, 10]:
		for d in [[r, 0], [-r, 0], [0, r], [0, -r], [r, r], [-r, -r], [r, -r], [-r, r]]:
			if TownLayout.on_road(s, [at[0] + d[0], at[1] + d[1]]): return false
	return true

## The camp's layout, in cells from the fire: three tents behind it (each bandit sleeps inside
## his own), log seats round the fire, the cooking pot, a woodpile, the lookout spot and the post.
const TENTS := [[-6, -5], [0, -7], [6, -5]]
const SEATS := [[-2, 1], [2, 1], [0, 2]]
const POT := [1, -1]
const WOODPILE := [8, 2]
const LOOKOUT := [0, 7]
const POST := [-5, 3]
const ROUTINE := ["sit", "cook", "wood", "watch"]
## Solid things round the camp to crouch behind in a fight: the woodpile (beside its fetching
## spot), crates and a couple of rocks. Blocked cells, so they are low cover (cover.gd).
const PROPS := {"woodpile": [[9, 2], [10, 2]], "crate": [[-3, -2], [4, -2], [-3, 5], [3, 5]], "rock": [[-8, 2], [7, -1]]}   # what each bandit does, turn by turn, hour by hour

static func _place_props(s: Dictionary) -> void:
	for kind in PROPS:
		for offset in PROPS[kind]: World.apply_mutation(s, at_camp(s.bandits.cell, offset), true)
	s.bandits.props = true

## True on this bandit's turn to step. Bandits are updated on even ticks only (update()), so a step
## every `every` updates is spread over them by id (a plain `tick % 4 == id % 4` never fired for
## odd ids, and they stood still).
static func _turn(s: Dictionary, npc: Dictionary, every: int) -> bool:
	return (int(s.tick) / 2 + int(npc.id)) % maxi(1, every) == 0

static func at_camp(spot: Array, offset: Array) -> Array:
	return [spot[0] + offset[0], spot[1] + offset[1]]

## Where each bandit sits by the fire.
static func _seat(spot: Array, i: int) -> Array:
	return at_camp(spot, SEATS[i % 3])

## Where a bandit sleeps: inside his tent.
static func _bed(spot: Array, i: int) -> Array:
	return at_camp(spot, TENTS[i % 3])

static func post(s: Dictionary) -> Array:
	return at_camp(s.bandits.cell, POST)

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
		_idle(sim, able)
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

## Camp life. At night each sleeps in his tent. By day each does, hour by hour and in turn: sits by
## the fire, cooks at the pot, fetches wood from the pile, or keeps watch at the edge of camp.
static func _idle(sim: RefCounted, able: Array) -> void:
	var s: Dictionary = sim.state
	var spot: Array = s.bandits.cell
	var hour: int = DayClock.hour(s)
	for npc in able:
		var index: int = s.bandits.members.find(int(npc.id))
		var entity: Dictionary = s.entities[str(npc.id)]
		if DayClock.bed_hours(s, npc):
			_sit_up(npc)
			var bed: Array = _bed(spot, index)
			if entity.cell != bed and npc.get("sleeping", {}).is_empty():
				if _turn(s, npc, 2): _walk(s, npc, bed)
				npc.status = "Turning in"
				if entity.cell != bed: continue
			if npc.get("sleeping", {}).is_empty():
				entity.cell = bed.duplicate()
				npc.sleeping = {"lie": bed.duplicate(), "approach": bed.duplicate(), "rot": 1, "bed_rect": [], "night": true, "since": s.tick}
				npc.status = "Asleep in his tent"
			continue
		if not npc.get("sleeping", {}).is_empty():
			npc.sleeping = {}
		var task: String = ROUTINE[(hour + index) % ROUTINE.size()]
		match task:
			"sit": _do_at(s, npc, _seat(spot, index), "Sitting by the fire", SEATS[index % 3], false)
			"cook": _do_at(s, npc, at_camp(spot, POT), "Cooking at the fire", POT, true)
			"watch":
				_sit_up(npc)
				var post_cell: Array = at_camp(spot, LOOKOUT)
				if entity.cell != post_cell and _turn(s, npc, 2): _walk(s, npc, post_cell)
				npc.status = "Keeping watch" if entity.cell == post_cell else "Going to keep watch"
			"wood":
				_sit_up(npc)
				# To the woodpile and back with an armful, then sit for the rest of the hour.
				var pile: Array = at_camp(spot, WOODPILE)
				var fetched: bool = int(npc.get("wood_hour", -1)) == int(s.tick) / 600
				if not fetched:
					if entity.cell != pile:
						if _turn(s, npc, 2): _walk(s, npc, pile)
						npc.status = "Fetching firewood"
					else:
						npc.wood_hour = int(s.tick) / 600
						npc.status = "Picking up firewood"
				else:
					_do_at(s, npc, _seat(spot, index), "Back with the firewood", SEATS[index % 3], false)
	if s.tick % 1200 == 0 and able.size() >= 2 and able[0].get("sleeping", {}).is_empty() and able[1].get("sleeping", {}).is_empty():
		_say(sim, able[0], "chat")

## Walk to `cell` (a step at a time) and sit down there on the ground, facing the fire.
static func _do_at(s: Dictionary, npc: Dictionary, cell: Array, status: String, offset: Array, cooking: bool) -> void:
	var entity: Dictionary = s.entities[str(npc.id)]
	if entity.cell != cell:
		_sit_up(npc)
		if _turn(s, npc, 2): _walk(s, npc, cell)
		npc.status = "Walking over to the fire"
		return
	var face: Array = [-signi(int(offset[0])), -signi(int(offset[1]))]
	if face == [0, 0]: face = [0, -1]
	if npc.get("sitting", {}).is_empty() or bool(npc.get("cooking", false)) != cooking:
		npc.sitting = {"chair": cell.duplicate(), "approach": cell.duplicate(), "face": face, "since": s.tick, "ground": true}
		npc.cooking = cooking
	npc.status = status

static func _sit_up(npc: Dictionary) -> void:
	npc.erase("sitting")
	npc.erase("cooking")

## One step towards `goal` (onto it on arrival) along a path worked out now and then.
static func _walk(s: Dictionary, npc: Dictionary, goal: Array) -> void:
	var entity: Dictionary = s.entities[str(npc.id)]
	if npc.get("path", []).is_empty() or int(npc.get("path_tick", -1000)) < s.tick - 40 or npc.get("path_goal", []) != goal:
		var route := Nav.request_path(s, entity.cell, goal)
		npc.path = route.path if route.ok else []
		npc.path_tick = s.tick
		npc.path_goal = goal.duplicate()
		if not route.ok: entity.cell = goal.duplicate()   # no way round: they get there anyway (camp ground)
	if not npc.path.is_empty():
		var next: Array = npc.path.pop_front()
		if World.walkable(s, next): entity.cell = next

static func _notices(s: Dictionary, able: Array, player: Array, from_camp: int) -> bool:
	if from_camp > NOTICE_RANGE: return false
	for npc in able:
		var reach: int = SLEEPER_RANGE if not npc.get("sleeping", {}).is_empty() else NOTICE_RANGE
		var at: Array = s.entities[str(npc.id)].cell
		if maxi(absi(at[0] - player[0]), absi(at[1] - player[1])) <= reach: return true
	return false

static func _wake_all(s: Dictionary, able: Array) -> void:
	for npc in able:
		_sit_up(npc)
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
	var player: Array = s.entities[str(s.player)].cell
	var Gunfire = load("res://sim/combat/gunfire.gd")
	for npc in able:
		npc.status = "Diving for cover"
		npc.fight_cover = Gunfire.find_cover(s, s.entities[str(npc.id)].cell, player)   # behind a tree or a rock; [] if none
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
		var cover: Array = npc.get("fight_cover", [])
		if not cover.is_empty() and at != cover:
			# Running for cover first.
			if _turn(s, npc, 1): _walk(s, npc, cover)
			npc.status = "Diving for cover"
			continue
		if gap > SHOOT_RANGE - 2:
			# Out of range: on to cover nearer the gunman, or straight at him.
			if s.tick - int(npc.get("cover_tick", -1000)) > 120:
				npc.cover_tick = s.tick
				npc.fight_cover = Gunfire.next_cover(s, at, player)
			if npc.get("fight_cover", []).is_empty() and _turn(s, npc, 2): _step(s, npc, player)
			npc.status = "Closing in"
		elif s.tick >= int(npc.get("next_shot", 0)):
			npc.next_shot = s.tick + SHOT_EVERY + sim.random_int("bandits", 0, 20)
			npc.status = "Shooting from cover" if not cover.is_empty() else "Shooting"
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
		npc.erase("fight_cover")
		_sit_up(npc)
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
