extends RefCounted
const BodyHealth = preload("res://sim/combat/body_health.gd")
const PlayerActions = preload("res://sim/player/player_actions.gd")
const Canonical = preload("res://sim/core/canonical.gd")
const Streams = preload("res://sim/core/random_streams.gd")
const World = preload("res://sim/world/world_db.gd")
const Names = preload("res://sim/entities/names.gd")
const Needs = preload("res://sim/entities/needs.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Households = preload("res://sim/entities/households.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const Shotgun = preload("res://sim/combat/shotgun.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Placement = preload("res://sim/world/placement.gd")
const Hotbar = preload("res://sim/player/hotbar.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Speech = preload("res://sim/entities/speech.gd")
const Law = preload("res://sim/law/law.gd")
const Housing = preload("res://sim/settlement/housing.gd")
const Limbs = preload("res://sim/combat/limbs.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Fear = preload("res://sim/entities/fear.gd")
const DoorAssist = preload("res://sim/player/door_assist.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const ContextActions = preload("res://sim/player/context_actions.gd")
const Looting = preload("res://sim/player/looting.gd")
const Chests = preload("res://sim/entities/chests.gd")
const Residents = preload("res://sim/entities/residents.gd")
const Jobs = preload("res://sim/jobs/job_board.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Recipes = preload("res://sim/production/recipe_system.gd")
const Planner = preload("res://sim/settlement/planner.gd")
const Market = preload("res://sim/economy/market.gd")
const Regional = preload("res://sim/economy/regional_trade.gd")
const Fidelity = preload("res://sim/world/fidelity.gd")
const Society = preload("res://sim/factions/society.gd")
const Risk = preload("res://sim/factions/risk_system.gd")
const Content = preload("res://sim/production/content_loader.gd")
const Navigation = preload("res://sim/movement/navigation.gd")
const Weather = preload("res://sim/world/weather.gd")
const LocalCombat = preload("res://sim/combat/local_combat.gd")
const Unarmed = preload("res://sim/combat/unarmed.gd")
const Probe = preload("res://sim/diagnostics/perf_probe.gd")
const Sleep = preload("res://sim/player/sleep.gd")
const Pace = preload("res://sim/movement/pace.gd")
const Encumbrance = preload("res://sim/player/encumbrance.gd")
const Carrying = preload("res://sim/player/carrying.gd")
const Trespass = preload("res://sim/law/trespass.gd")
const Look = preload("res://sim/player/look.gd")
const Bleeding = preload("res://sim/combat/bleeding.gd")
const FamilyEconomy = preload("res://sim/entities/family_economy.gd")
const StallService = preload("res://sim/economy/stall_service.gd")
const Light = preload("res://sim/world/light.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const OutlawArrest = preload("res://sim/law/outlaw_arrest.gd")
const Notoriety = preload("res://sim/law/notoriety.gd")
const Investigation = preload("res://sim/law/investigation.gd")
const Bounties = preload("res://sim/law/bounties.gd")
const Capital = preload("res://sim/settlement/capital.gd")
const Reinforcements = preload("res://sim/law/reinforcements.gd")
## Commands that are the player doing something: refused while down or restrained, and they wake
## a sleeping player.
const PLAYER_ACTS := ["move_player", "player_strike", "interact", "shotgun_fire", "hotbar_use", "eat", "drink", "treat_body", "context_action", "walk_to", "travel", "loot_take", "loot_all", "loot_coins", "loot_strip", "loot_give", "wear_item", "take_off", "hold_item", "hotbar_assign", "crouch_toggle", "travel_run", "shotgun_toggle", "shotgun_reload", "person_trade", "take_item", "surrender", "haggle"]
var state: Dictionary

func _init(seed_value: int = 417) -> void:
	state = {"format_version": 2, "content_version": 1, "seed": seed_value,
		"tick": 0, "next_id": 1, "commands": [], "events": [], "rng": {},
		"entities": {}, "history": [], "event_results": [], "ticks_per_minute": 10}

func start_village(population: int = 10) -> void:
	World.seed_world(self)
	Weather.initialize(state)
	LocalCombat.initialize(state)
	Jobs.initialize(state)
	Residents.spawn(self, population)
	record("Welcome to Alder Hollow. Residents work without your direction.")

func enable_production() -> void:
	Recipes.initialize(self)

func enable_economy() -> void:
	Planner.initialize(self)
	Market.initialize(state)

func enable_region() -> void:
	Regional.initialize(self)
	BodyHealth.initialize(state)
	PlayerActions.initialize(state)
	Needs.initialize(state)
	Shotgun.initialize(state)
	Hotbar.initialize(state)
	Brawl.initialize(state)

func enable_society() -> void:
	Society.initialize(state)
	Risk.initialize(state)

## A new game: the first day of summer, at 07:00 (DayClock: morning).
const START_TICK := 4200

func start_game(population: int = 5) -> void:
	state.tick = START_TICK
	start_village(population)
	enable_production()
	enable_economy()
	enable_region()
	Market.install_stalls(self)
	enable_society()
	Sheriff.install(self)
	TownLayout.generate(self)
	Housing.settle(self)
	Households.upgrade(self)
	FamilyEconomy.ensure(state)
	Chests.ensure_all(self)
	Capital.ensure(self)   # Dustvale, the capital: the town house, the governor, the saloon and its barkeep (before the woods, which keep clear of buildings)
	World.lay_out_woodlands(self)
	for town in state.settlements.values(): Professions.assign(state, town.id)
	Sheriff.ensure(self)
	Market.ensure_tents(self)
	load("res://sim/world/road_planner.gd").ensure_ways(state)   # last: the roads, woods and towns are all in place
	Light.ensure_lamps(self)
	Weather.ensure_regions(state)   # each town its own weather, now that the towns exist
	Bandits.ensure_camp(self)       # a bandit camp far out in the wilds
	warm_scripts()

## Scripts that daily and occasional work loads on demand (load() inside functions, to avoid
## preload cycles). Loading them once when a game starts or is restored keeps the first noon of a
## session from paying for reading them from disk. Changes no game state.
const WARM_SCRIPTS := ["res://sim/player/requests.gd", "res://sim/entities/gossip.gd", "res://sim/factions/reputation.gd",
	"res://sim/factions/society.gd", "res://sim/entities/family_economy.gd", "res://sim/economy/market.gd",
	"res://sim/economy/traders.gd", "res://sim/world/chronicle.gd", "res://sim/law/witness_reports.gd"]
static func warm_scripts() -> void:
	for path in WARM_SCRIPTS: load(path)

func new_id() -> int:
	var result: int = state.next_id
	state.next_id += 1
	return result

func submit(kind: String, payload: Dictionary = {}, due_tick: int = -1) -> int:
	if kind == "load_recipe":
		var loaded := Content.read_recipe(payload.get("path", "user://recipe.json"))
		kind = "install_recipe" if loaded.ok else "reject_recipe"
		payload = {"recipe": loaded.recipe} if loaded.ok else {"error": loaded.error}
	var id := new_id()
	state.commands.append({"id": id, "due": maxi(state.tick + 1, due_tick), "kind": kind, "payload": payload.duplicate(true)})
	return id

func schedule(kind: String, due_tick: int, payload: Dictionary = {}) -> int:
	var id := new_id()
	state.events.append({"id": id, "due": maxi(state.tick + 1, due_tick), "kind": kind, "payload": payload.duplicate(true)})
	return id

func random_int(stream: String, low: int, high: int) -> int:
	return Streams.next_int(state.rng, state.seed, stream, low, high)

func step() -> void:
	Probe.begin()
	state.tick += 1
	_drain("commands", true)
	_drain("events", false)
	Probe.mark("commands")
	if state.has("residents"):
		Weather.update(self)
		Unarmed.update(self)
		Probe.mark("weather+unarmed")
		Brawl.update(self)
		Probe.mark("brawl")
		Law.update(self)
		Bandits.update(self)
		OutlawArrest.update(self)   # bandits in town, and the sheriffs bringing them in
		Notoriety.update(self)      # a wanted stranger, as the townsfolk see it
		Investigation.update(self)  # missing people, found bodies, the sheriff's cases
		Bounties.update(self)       # bandits you've tied up, following you in
		Reinforcements.update(self)
		Probe.mark("law")
		Gunfire.update(self)
		Probe.mark("gunfire")
		Fear.update(self)
		Probe.mark("fear")
		Bleeding.update(self)
		StallService.update(self)
		FamilyEconomy.update(self)
		Probe.mark("bleeding+stalls+families")
		Speech.update(self)
		Probe.mark("speech")
		ContextActions.update(self)
		Probe.mark("context")
		LocalCombat.update(self)
		var travelling: bool = not state.get("player_path", []).is_empty()
		# Holding Shift while following a route runs it: a step every tick (three in four when fatigued).
		var run_route: bool = travelling and _can_run_route()
		var tired_route: bool = run_route and state.player_health.stamina <= BodyHealth.WINDED_AT
		if run_route: state.player_control.crouching = false
		var sneaking_route: bool = travelling and bool(state.get("player_control", {}).get("crouching", false))
		# Walking a route: a step every two ticks (three crouched), a little quicker on the roads (pace.gd).
		var route_step: bool = (state.tick % 4 != 3 if tired_route else true) if run_route else state.tick >= int(state.get("player_control", {}).get("route_next", 0))
		if travelling and Law.jailed(state) and not Law.inside_cell(state, state.player_path[0]):
			state.player_path = []
			travelling = false
		if travelling and route_step:
			var next: Array = state.player_path.pop_front()
			if World.walkable(state, next):
				var from_cell: Array = state.entities[str(state.player)].cell
				state.player_control.last_dir = [signi(next[0] - from_cell[0]), signi(next[1] - from_cell[1])]
				state.entities[str(state.player)].cell = next
				if not run_route and state.has("player_control"):
					state.player_control.route_next = state.tick + Pace.delay(state, next, 3 if sneaking_route else 2, state.player_control, "stride_carry", Encumbrance.slower_percent(state))
				if run_route:
					state.player_control.running = true
					state.player_control.running_tick = state.tick
					state.player_health.stamina = maxi(0, state.player_health.stamina - 1)
				if state.player_path.is_empty():
					state.player_control.travel_run = false
					var arrived: int = int(state.player_control.get("travelling", 0))
					if arrived != 0:
						state.player_control.travelling = 0
						state.player_control.notice = "You arrive in %s." % state.settlements.get(str(arrived), {}).get("name", "town")
			else:
				var destination: Array = state.get("player_travel_goal", [])
				state.player_path = []
				if not destination.is_empty():
					var by_road: bool = int(state.player_control.get("travelling", 0)) != 0
					var reroute := Navigation.request_travel_path(state, state.entities[str(state.player)].cell, destination) if by_road else Navigation.request_walk_path(state, state.entities[str(state.player)].cell, destination)
					if reroute.ok: state.player_path = reroute.path
		Probe.mark("local_combat+route")
		if state.tick % 10 == 0:
			Jobs.refresh(self)
		Probe.mark("jobs_refresh")
		if state.has("routes"):
			Fidelity.update(state)
			Regional.update(self)
		Probe.mark("regional")
		Residents.update(self)
		Probe.mark("residents")
		if state.has("factions"):
			Society.update(self)
			Risk.update(self)
		Probe.mark("society")
		if state.has("workshops"):
			Recipes.update(self)
		Probe.mark("recipes")
		if state.has("construction"):
			Planner.update(self)
		Probe.mark("planner")
		if state.has("markets") and state.tick % 600 == 300: Market.ensure_tents(self)
		if state.has("markets") and state.tick % 600 == 310: Market.note_prices(state)
		if state.has("markets") and state.tick % 300 == 0:
			for town_id in state.markets:
				Market.clear_market(state, int(town_id))
		Probe.mark("market")
		BodyHealth.update(state)
		Limbs.update(state)
		Cover.update(state)
		Probe.mark("body+cover")
		PlayerActions.update(self)
		Carrying.update(self)
		Trespass.update(self)
		Needs.update(state)
		Look.update(state)
		Sleep.update(state)
		Hotbar.update(state)
		Shotgun.update(self)
		Probe.mark("player+needs+shotgun")
		if state.has("households"):
			var noon: int = state.tick % 14400 - 7200
			if noon == 0: Households.daily(self, false)   # each town's share follows on its own tick
			elif noon > 0 and noon % 40 == 0 and noon / 40 <= state.settlements.size():
				# Each town's share on its own tick: 12:04, 12:08, 12:12 (in town id order).
				var keys: Array = state.settlements.keys()
				keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
				Households.daily_town(self, state.settlements[keys[noon / 40 - 1]])
		if state.has("households") and state.tick % 14400 == 11400: FamilyEconomy.payday(self)   # 19:00
		Crops.update(state)
		Probe.mark("daily+crops")
		if state.tick % 600 == 0:
			# Woodland grows once a day per tree, spread over the hours: each tree at the hour its id
			# gives it (about 260 trees an hour, not all ~6,300 on the stroke of midnight).
			var hour: int = (state.tick / 600) % 24
			for entity in World.of_kind(state, "tree"):
				if int(entity.id) % 24 == hour:
					if entity.get("felled", false):
						# A stump sprouts a new tree after a week; a fallen trunk waits to be gathered.
						if Inventory.amount(state, entity.id, "log") == 0 and state.tick - int(entity.get("felled_tick", 0)) >= 7 * 14400:
							entity.felled = false
							Inventory.produce(state, entity.id, "log", mini(10, Inventory.available(state, entity.id)))
					else:
						Inventory.produce(state, entity.id, "log", mini(2, Inventory.available(state, entity.id)))
			if state.tick % 14400 == 0: record("A new day: rye grew in the fields and woodland grew.")

func _stamina_allows_run() -> bool:
	return state.player_health.stamina > 0 and not state.player_health.get("exhausted", false)

func _can_run_route() -> bool:
	return state.has("player_control") and state.has("player_health") and state.player_control.get("travel_run", false) and _stamina_allows_run() and BodyHealth.move_delay(state) == 1 and Limbs.mode(state, state.player) == "walk" and not Brawl.player_down(state) and Encumbrance.can_run(state)

func _drain(queue_name: String, is_command: bool) -> void:
	if state[queue_name].size() > 1:   # an empty or single-entry queue is already in order
		state[queue_name].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.due < b.due or (a.due == b.due and a.id < b.id))
	while not state[queue_name].is_empty() and state[queue_name][0].due <= state.tick:
		var entry: Dictionary = state[queue_name].pop_front()
		if is_command:
			apply_command(entry)
		else:
			apply_event(entry)

## Tied up you can still talk: to the bandit on watch, when he's close.
func _captive_talk(entry: Dictionary) -> bool:
	var target: int = int(entry.get("payload", {}).get("target", 0))
	var npc: Dictionary = state.get("residents", {}).get(str(target), {})
	if npc.is_empty() or int(npc.get("bandit", 0)) == 0: return false
	if entry.kind == "context_action" and not str(entry.payload.get("action", "")).begins_with("c_"): return false
	if not entry.kind in ["interact", "context_action"]: return false
	var me: Array = state.entities[str(state.player)].cell
	var at: Array = state.entities[str(target)].cell
	return maxi(absi(me[0] - at[0]), absi(me[1] - at[1])) <= 4

func apply_command(entry: Dictionary) -> void:
	# Someone lying on the ground cannot act until they are back on their feet.
	if state.has("brawl") and entry.kind in PLAYER_ACTS and entry.kind != "surrender" and Bandits.captive(state) and not _captive_talk(entry):
		state.player_control.notice = "You're tied up. F: work at the ropes when the watch is away."
		return
	if state.has("brawl") and entry.kind in PLAYER_ACTS and (Brawl.player_down(state) or Law.restrained(state)):
		return
	# Asleep: any action (or a key press, sent as "wake") gets the player up; a step only wakes them.
	if Sleep.asleep(state) and (entry.kind == "wake" or (entry.kind in PLAYER_ACTS and entry.kind != "travel_run")):
		Sleep.wake(state, "You get up.")
		if entry.kind in ["wake", "move_player"]: return
	if entry.kind == "wake": return
	# Taking over: any action of the player's own ends a travel to a town.
	if entry.kind in PLAYER_ACTS and entry.kind not in ["travel", "travel_run"] and int(state.get("player_control", {}).get("travelling", 0)) != 0:
		state.player_control.travelling = 0
	if entry.kind in ["shotgun_fire", "player_strike", "shotgun_toggle", "shotgun_reload"] and Carrying.carried(state) != 0 and state.has("player_control"):
		state.player_control.notice = "Put the body down first (F)."
		return
	var limb_problem: String = Limbs.action_problem(state, entry.kind)
	if not limb_problem.is_empty() and state.has("player_control"):
		state.player_control.notice = limb_problem
		return
	if entry.kind == "peek" and state.has("player_control"):
		var toward: Array = entry.payload.get("toward", [0, 0])
		state.player_control.peek_hold = bool(entry.payload.get("on", false)) and not Brawl.player_down(state) and not Law.restrained(state)
		state.player_control.peek_toward = [int(toward[0]), int(toward[1])] if toward.size() == 2 else [0, 0]
		return
	if entry.kind == "player_strike":
		Unarmed.begin(state, str(entry.payload.get("kind", "")), entry.payload.get("direction", []))
		return
	if entry.kind == "demo_encounter" and state.has("residents"):
		LocalCombat.start_encounter(self)
		return
	if entry.kind in ["eat", "drink"] and state.has("player_needs"):
		state.player_control.notice = Needs.eat(state) if entry.kind == "eat" else Needs.drink(state)
		return
	if entry.kind in ["hotbar_assign", "hotbar_use"] and state.has("hotbar"):
		var message: String = Hotbar.assign(state, int(entry.payload.get("slot", -1)), str(entry.payload.get("item", ""))) if entry.kind == "hotbar_assign" else Hotbar.use(state, int(entry.payload.get("slot", -1)))
		if not message.is_empty(): state.player_control.notice = message
		return
	if entry.kind in ["rotate_furniture", "rearrange_furniture", "place_furniture"] and state.has("player_control"):
		var notice: String = _furniture_command(entry)
		if not notice.is_empty(): state.player_control.notice = notice
		return
	if entry.kind in ["shotgun_toggle", "shotgun_reload", "shotgun_fire"] and state.has("shotgun"):
		match entry.kind:
			"shotgun_toggle": state.player_control.notice = Shotgun.toggle(state)
			"shotgun_reload": state.player_control.notice = Shotgun.start_reload(state)
			"shotgun_fire": Shotgun.fire(self, entry.payload.get("direction", []))
		return
	if entry.kind in ["loot_take", "loot_all", "loot_coins", "loot_strip", "loot_give", "wear_item", "take_off"] and state.has("player_control"):
		var payload: Dictionary = entry.payload
		match entry.kind:
			"loot_take": Looting.take(state, int(payload.get("target", 0)), str(payload.get("item", "")))
			"loot_give": Looting.give(state, int(payload.get("target", 0)), str(payload.get("item", "")))
			"loot_all": Looting.take_all(state, int(payload.get("target", 0)))
			"loot_coins": Looting.take_coins(state, int(payload.get("target", 0)))
			"loot_strip": Looting.strip(state, int(payload.get("target", 0)), str(payload.get("slot", "")), bool(payload.get("wear", false)))
			"wear_item": Looting.wear(state, str(payload.get("item", "")))
			"take_off": Looting.take_off(state, str(payload.get("slot", "")))
		return
	if entry.kind == "walk_to" and state.has("player_control") and Law.jailed(state):
		state.player_control.notice = "You are locked in a cell."
		return
	if entry.kind == "walk_to" and state.has("player_control"):
		# Double right-click on the ground: find a route and walk it (a blocked square goes to the nearest free neighbour).
		var goal: Array = entry.payload.get("cell", [])
		if goal.size() == 2:
			var from: Array = state.entities[str(state.player)].cell
			var target: Array = goal.duplicate()
			if not World.walkable(state, target):
				var best := 9999
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var candidate: Array = [goal[0] + dx, goal[1] + dy]
						if World.walkable(state, candidate) and absi(dx) + absi(dy) < best: best = absi(dx) + absi(dy); target = candidate
			var route := Navigation.request_walk_path(state, from, target)
			state.player_control.pending = {}
			if route.ok and not route.path.is_empty():
				state.player_path = route.path
				state.player_travel_goal = target.duplicate()
				state.player_control.notice = "Walking there…"
			else:
				state.player_control.notice = "You cannot find a way there."
		return
	if entry.kind == "context_action" and state.has("player_control"):
		ContextActions.request(self, int(entry.payload.get("target", 0)), str(entry.payload.get("action", "")), str(entry.payload.get("part", "")))
		return
	if entry.kind=="surrender" and state.has("player_control"):
		if Bandits.captive(state):
			Bandits.work_ropes(state)   # tied up: F works at the knots
			return
		Law.surrender(state)
		return
	if entry.kind=="rummage" and state.has("player_control"):
		# Opening the inventory: kneel and go through the backpack (purely a pose; it ends on any move).
		state.player_control.rummaging=bool(entry.payload.get("open",false)) and not Brawl.player_down(state)
		return
	if entry.kind=="crouch_toggle" and state.has("player_control"):
		if Brawl.player_down(state): return
		state.player_control.crouching=not bool(state.player_control.get("crouching",false))
		state.player_control.notice="You crouch low and move quietly." if state.player_control.crouching else "You stand up."
		return
	if entry.kind=="travel_run" and state.has("player_control"):
		state.player_control.travel_run=bool(entry.payload.get("run",false))
		return
	if entry.kind=="stop_travel":
		state.player_path=[]; state.player_travel_goal=[]
		if state.has("player_control"): state.player_control.travelling = 0
		return
	if entry.kind == "haggle" and state.has("player_control"):
		StallService.haggle(self, int(entry.payload.get("target", 0)))
		return
	if entry.kind in ["interact","hold_item","take_item","person_trade","treat_body","debug_injury"] and state.has("player_control"):
		match entry.kind:
			"interact":
				state.player_path=[]
				PlayerActions.interact(self,int(entry.payload.get("target",0)))
			"hold_item": PlayerActions.hold(state,str(entry.payload.get("item","")))
			"take_item": PlayerActions.take(state,int(entry.payload.get("target",0)),str(entry.payload.get("item","")))
			"person_trade": PlayerActions.trade(self,entry.payload)
			"treat_body":
				PlayerActions.stop(state)
				BodyHealth.begin(state,str(entry.payload.get("part","")),str(entry.payload.get("action","")))
			"debug_injury": BodyHealth.injure(state,str(entry.payload.get("part","right_hand")),int(entry.payload.get("damage",18)),str(entry.payload.get("kind","cut")))
		return
	if entry.kind == "move_player" and state.has("player"):
		state.player_path = []
		if state.has("player_control"):
			state.player_control.pending = {}  # walking by hand cancels a click-to-act walk
			state.player_control.rummaging = false
			state.player_control.surrender = false   # lowering your hands to move
		if state.has("player_control"):
			if BodyHealth.incapacitated(state) or state.tick<state.player_control.next_move: return
		var direction: Array = entry.payload.get("direction", [0, 0])
		# One step in any of the eight directions. A diagonal step may not cut a
		# blocked corner, so both neighbouring orthogonal cells must be walkable.
		if direction.size() == 2 and abs(direction[0]) <= 1 and abs(direction[1]) <= 1 and abs(direction[0]) + abs(direction[1]) >= 1:
			var cell: Array = state.entities[str(state.player)].cell
			if state.has("player_control"): direction = DoorAssist.adjust(state, cell, direction)   # help into a doorway after repeated tries
			var next: Array = [cell[0] + direction[0], cell[1] + direction[1]]
			var diagonal: bool = direction[0] != 0 and direction[1] != 0
			if Law.inside_cell(state, next) and World.walkable(state, next) and (not diagonal or (World.walkable(state, [cell[0] + direction[0], cell[1]]) and World.walkable(state, [cell[0], cell[1] + direction[1]]))):
				if state.has("player_control"):
					var load_band: int = Encumbrance.band(state)
					if bool(entry.payload.get("run",false)) and load_band >= 2 and state.tick >= int(state.player_control.get("load_notice_tick", -1000)) + 300:
						state.player_control.notice = "You can hardly move under this load." if load_band == 3 else "Too much to carry to run. Drop something (I)."
						state.player_control.load_notice_tick = state.tick
					var requested_run: bool=bool(entry.payload.get("run",false)) and _stamina_allows_run() and BodyHealth.move_delay(state)==1 and Limbs.mode(state, state.player)=="walk" and load_band < 2
					# Sprinting from a crouch stands you up; otherwise a crouch is a slow, quiet walk.
					if requested_run: state.player_control.crouching=false
					var sneaking: bool=bool(state.player_control.get("crouching",false))
					# Fatigued (orange stamina) running drops every other stride, so the pace visibly flags.
					var tired_run: bool=requested_run and state.player_health.stamina<=BodyHealth.WINDED_AT and state.tick%2==0
					state.player_control.running=requested_run
					state.player_control.running_tick=state.tick if requested_run else -1
					state.player_control.last_dir=[direction[0],direction[1]]
					var walk_ticks: int = maxi(maxi(3 if sneaking else 2, BodyHealth.move_delay(state)+(1 if sneaking else 0)), Limbs.step_ticks(state, state.player))+(1 if diagonal else 0)
					state.player_control.next_move=state.tick+(2 if tired_run else (1 if requested_run else Pace.delay(state, next, walk_ticks, state.player_control, "stride_carry", Encumbrance.SLOWER[load_band])))
					if requested_run: state.player_health.stamina=maxi(0,state.player_health.stamina-1)
				state.entities[str(state.player)].cell = next
	elif entry.kind == "cancel_job" and state.has("jobs"):
		Jobs.release(state, int(entry.payload.get("id", 0)), "CANCELLED")
	elif entry.kind == "trade" and state.has("markets"):
		var result := Market.player_trade(self, entry.payload)
		if not result.ok:
			record("Trade rejected: " + result.error_code)
		elif state.has("factions") and not entry.payload.get("buy", false):
			Society.helpful_trade(self, int(entry.payload.get("town", 1)), entry.payload.get("item", "log"))
	elif entry.kind == "cancel_production" and state.has("workshops"):
		var key := str(entry.payload.get("id", 0))
		if state.workshops.has(key):
			Recipes.cancel(state, state.workshops[key])
	elif entry.kind == "route_block" and state.has("routes"):
		state.routes["1"].blocked = bool(entry.payload.get("blocked", false))
		record("Moss Road " + ("closed" if state.routes["1"].blocked else "reopened"))
	elif entry.kind == "treaty" and state.has("treaty"):
		state.treaty.open_trade = bool(entry.payload.get("open", true))
		state.treaty.since = state.tick
		record("Councils " + ("reopened regional trade" if state.treaty.open_trade else "suspended regional trade"))
	elif entry.kind == "risk" and state.has("routes"):
		state.routes["1"].risk = clampi(int(entry.payload.get("value", 0)), 0, 100)
		record("Moss Road danger is now %d/100" % state.routes["1"].risk)
	elif entry.kind == "migrate" and state.has("factions"):
		Society.migrate(self, int(entry.payload.get("id", 0)), int(entry.payload.get("destination", 2)))
	elif entry.kind == "travel" and state.has("settlements"):
		_travel_to(int(entry.payload.get("town", 1)))
	elif entry.kind == "install_recipe" and state.has("recipes"):
		var result: Dictionary = {"ok": true, "recipe": entry.payload.recipe}
		if result.ok:
			var recipe: Dictionary = result.recipe
			state.recipes[recipe.id] = recipe
			for workshop in state.workshops.values():
				if not workshop.active and workshop.get("kind", "sawmill") == "sawmill":
					workshop.recipe = recipe.id
			record("Loaded recipe " + recipe.id + "; idle sawmills now use it")
		else:
			record("Recipe rejected: " + result.error)
	elif entry.kind == "reject_recipe":
		record("Recipe rejected: " + str(entry.payload.get("error", "Invalid recipe")))
	elif entry.kind == "spawn_test":
		var id := new_id()
		state.entities[str(id)] = {"id": id, "value": random_int("test", 0, 9999)}
	else:
		record("Rejected command: " + entry.kind)

## Furniture commands act on a building by id, or the one the player is standing in.
func _furniture_command(entry: Dictionary) -> String:
	var cell: Array = state.entities[str(state.player)].cell
	var id: int = int(entry.payload.get("building", World.inside_building(state, cell)))
	if id == 0 or not state.entities.has(str(id)) or not state.entities[str(id)].has("furniture"):
		return "Stand inside a building to arrange its furniture."
	var building: Dictionary = state.entities[str(id)]
	var index: int = int(entry.payload.get("index", Placement.nearest_index(building, cell)))
	match entry.kind:
		"place_furniture":
			var kind: String = str(entry.payload.get("kind", ""))
			var ok: bool = Placement.place(state, building, kind, entry.payload.get("cell", [0, 0]), int(entry.payload.get("rot", 2)))
			return ("Placed a %s." % kind) if ok else "There is no room for that here."
		"rotate_furniture":
			var turned: int = Placement.rotate_item(state, building, index, int(entry.payload.get("steps", 1)))
			if turned < 0: return "There is no room to turn that."
			return "Turned the %s to face %s." % [building.furniture[index].kind, ["up", "right", "down", "left"][turned]]
		"rearrange_furniture":
			return ("Moved the %s against the wall." % building.furniture[index].kind) if Placement.rearrange(state, building, index) else "It already sits as well as it can."
	return ""

## Travel to a town: walk there along the roads by yourself, to the street in front of its
## storehouse. Any step or action of the player's own takes over again (apply_command).
func _travel_to(town_id: int) -> void:
	var town: Dictionary = state.settlements.get(str(town_id), {})
	if town.is_empty(): return
	var pc: Dictionary = state.get("player_control", {})
	if Law.jailed(state) or Law.in_custody(state):
		if not pc.is_empty(): pc.notice = "You are locked in a cell."
		return
	var goal: Array = load("res://sim/world/road_planner.gd").town_gate(state, town)
	var from: Array = state.entities[str(state.player)].cell
	if absi(from[0] - goal[0]) + absi(from[1] - goal[1]) <= 3:
		if not pc.is_empty(): pc.notice = "You are already in %s." % town.name
		return
	var route := Navigation.request_travel_path(state, from, goal)
	if not route.ok or route.path.is_empty():
		if not pc.is_empty(): pc.notice = "You cannot find a way to %s." % town.name
		return
	state.player_path = route.path
	state.player_travel_goal = goal.duplicate()
	if not pc.is_empty():
		pc.pending = {}
		pc.travelling = town_id
		pc.notice = "Travelling to %s. Move to take over." % town.name

func apply_event(entry: Dictionary) -> void:
	if entry.kind == "caravan_arrival" and state.has("caravans"):
		Regional.arrive(self, entry)
	elif entry.kind == "migration_arrival" and state.has("factions"):
		Society.arrive(self, entry)
	elif entry.kind == "encounter" and state.has("conflicts"):
		Risk.resolve(self, entry)
	state.event_results.append(entry.id)
	if state.event_results.size() > 64:
		state.event_results.pop_front()

func record(message: String) -> void:
	state.history.append({"tick": state.tick, "text": message})
	if state.history.size() > 64:
		state.history.pop_front()

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(snapshot_data: Dictionary) -> void:
	state = snapshot_data.duplicate(true)
	if state.has("world"): Weather.initialize(state)
	if state.has("residents"): LocalCombat.initialize(state)
	Names.upgrade(state)
	Needs.upgrade(state)
	Shotgun.initialize(state) if state.has("player_health") else null
	Hotbar.initialize(state)
	if state.has("hotbar") and int(state.hotbar.get("active", -1)) < 0: state.hotbar.active = 0
	Brawl.initialize(state)
	Crops.initialize(state) if state.has("world") else null
	World.upgrade_layouts(state)
	World.upgrade_architecture(state)
	World.upgrade_house_layouts(state)
	World.upgrade_building_scale(state)
	World.upgrade_forests(self)
	World.Fixtures.upgrade(state)
	if state.has("households") and state.has("accounts") and not state.accounts.keys().any(func(k): return String(k).begins_with("household:")):
		FamilyEconomy.ensure(state)   # purses for saves made before families kept their own money
	# After the layout upgrades, which may rebuild furniture: re-links the existing chests.
	if state.has("households"): Chests.ensure_all(self)
	load("res://sim/world/road_planner.gd").ensure_ways(state)   # signposts in older saves learn their distances
	Light.ensure_lamps(self)   # street lamps for saves made before they existed
	Bandits.ensure_camp(self)  # and the bandit camp
	Capital.ensure(self)       # and the capital's town house and saloon
	warm_scripts()
	if state.has("routes"):
		BodyHealth.initialize(state)
		PlayerActions.initialize(state)
		Market.install_stalls(self)

func state_hash() -> String:
	return Canonical.hash_state(state)
