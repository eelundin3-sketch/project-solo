extends RefCounted
const DayClock = preload("res://sim/world/day_clock.gd")
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Jobs = preload("res://sim/jobs/job_board.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const LocalCombat = preload("res://sim/combat/local_combat.gd")
const Names = preload("res://sim/entities/names.gd")
const Needs = preload("res://sim/entities/needs.gd")
const Households = preload("res://sim/entities/households.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Limbs = preload("res://sim/combat/limbs.gd")
const Bleeding = preload("res://sim/combat/bleeding.gd")
const FamilyEconomy = preload("res://sim/entities/family_economy.gd")

static func spawn(sim: RefCounted, count: int, settlement: int = 1, origin: Array = [60, 49]) -> void:
	var s: Dictionary = sim.state
	if not s.has("residents"):
		s.residents = {}
	var columns: int = 20 if count > 40 else 5
	for index in range(count):
		add_resident(sim, settlement, [origin[0] + index % columns, origin[1] + index / columns])

## Creates one resident (an adult, or a child born into a household) with its inventory.
static func add_resident(sim: RefCounted, settlement: int, cell: Array, child: bool = false) -> int:
	var s: Dictionary = sim.state
	var id := World.add_entity(sim, "resident", Names.generate(sim), cell, settlement)
	s.residents[str(id)] = {"id": id, "settlement": settlement, "hunger": sim.random_int("needs", 5, 35) if not child else 8, "thirst": sim.random_int("needs", 5, 30) if not child else 8, "mood": 75, "fatigue": sim.random_int("needs", 0, 8) if not child else 5,
		"health": 100, "job": 0, "path": [], "nav_revision": 0, "goal": "", "status": "Available", "retry_at": 0,
		"fidelity": "detailed", "occupation": "Child" if child else "Gatherer", "memories": [], "relations": {}, "skill": 0,
		"age_days": 1 if child else 30 + id % 15, "partner": 0, "household": ""}
	Inventory.create(s, id, 10)
	if s.has("accounts"): s.accounts[str(id)] = 0
	return id

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	for key in s.residents:
		var npc: Dictionary = s.residents[key]
		if s.tick < int(npc.get("impact_until", 0)): continue
		if int(npc.get("bandit", 0)) != 0: continue   # bandits live by their own rules (bandits.gd)
		if LocalCombat.busy(s, npc.id) or npc.health <= 0: continue
		if Brawl.busy(s, npc): continue
		if not npc.get("migration", {}).is_empty():
			continue
		if not npc.get("fear", {}).is_empty(): continue   # running for cover or crouched behind it (fear.gd)
		if not npc.get("serving", {}).is_empty(): continue   # minding a market tent for the player (stall_service.gd)
		if not npc.get("bandaging", {}).is_empty(): continue   # binding a wound (bleeding.gd)
		if not npc.get("reporting", {}).is_empty(): continue   # running to tell the sheriff (witness_reports.gd)
		if not npc.get("arrest", {}).is_empty():
			if npc.has("sitting"): Sheriff.stand_up(s, npc)
			continue   # making an arrest (law.gd)
		if npc.occupation == "Trader" and load("res://sim/economy/traders.gd").away(s, npc):
			continue   # on the road, or waiting at a foreign market
		# Tiredness builds more slowly than hunger, so a normal day ends with people ready for bed.
		if s.tick % 150 == 0 and npc.get("sleeping", {}).is_empty(): npc.fatigue = mini(100, npc.fatigue + 1)
		if not npc.get("sleeping", {}).is_empty() and npc.goal != "sleep": Households.wake(s, npc)  # woken by something else
		if s.tick % 100 == 0:
			npc.hunger = mini(100, npc.hunger + 1)
			npc.thirst = mini(100, int(npc.get("thirst", 0)) + (2 if s.tick % 200 == 0 else 1))
			npc.mood = Needs.mood_value(npc.hunger, npc.thirst, npc.fatigue, 0, 0, 6 if npc.goal == "rest" else 0)
		var cadence: int = 2 if npc.fidelity == "detailed" else (10 if npc.fidelity == "coarse" else 100)
		if (npc.fidelity == "detailed" and s.tick % 10 == npc.id % 10) or (npc.fidelity != "detailed" and s.tick % cadence == 0):
			_decide(sim, npc)
		var step: int = Limbs.step_ticks(s, npc.id)
		if step > 2 and npc.job != 0 and Limbs.crawling(s, npc.id):
			Jobs.release(s, npc.job, "CRAWLING")   # nobody works on their belly
		if step > 2 and s.tick % step != 0: continue   # a limp or a crawl: far fewer steps
		if s.tick % cadence == 0:
			if npc.job != 0:
				Jobs.advance_many(sim, npc.id, cadence / 2)
			elif not npc.goal.is_empty():
				var actions: int = cadence / 2 if step <= 2 else 1
				var distance: int = mini(actions, npc.path.size())
				if distance > 0 and npc.nav_revision != s.world.nav_revision and Nav.still_clear(s, npc.path):
					npc.nav_revision = s.world.nav_revision   # the world changed elsewhere; this route is still open
				if distance > 0 and npc.nav_revision == s.world.nav_revision:
					s.entities[str(npc.id)].cell = npc.path[distance - 1]
					npc.path = npc.path.slice(distance)
					actions -= distance
				if actions > 0:
					if npc.goal == "rest" and npc.path.is_empty():
						npc.fatigue = maxi(10, npc.fatigue - actions + 1)
					_need_action(sim, npc)

## Things a villager keeps on them rather than putting in the store.
const KIT := ["bandage"]

## What a villager carries that belongs in the store (everything but their own kit).
static func cargo(s: Dictionary, npc: Dictionary) -> int:
	var total := 0
	var items: Dictionary = s.inventories[str(npc.id)].items
	for item in items:
		if not item in KIT: total += int(items[item])
	return total

static func _destination(s: Dictionary, npc: Dictionary, kind: String) -> int:
	if s.has("settlements"):
		return s.settlements[str(npc.settlement)][kind]
	return s[kind]

static func _decide(sim: RefCounted, npc: Dictionary) -> void:
	var s: Dictionary = sim.state
	if npc.retry_at > s.tick:
		return
	# After their own bedtime (21:00-22:00) anyone with some tiredness goes to bed; by day only the
	# exhausted lie down (DayClock).
	var sleepy: bool = (DayClock.bed_hours(s, npc) and npc.fatigue >= 20) or npc.fatigue >= 75
	if npc.hunger >= 60 or npc.get("thirst", 0) >= 60 or sleepy:
		if npc.job != 0:
			Jobs.release(s, npc.job, "INTERRUPTED_FOR_NEEDS")
		if npc.goal.is_empty():
			set_goal(s, npc, "eat" if npc.hunger >= 60 else ("drink" if npc.get("thirst", 0) >= 60 else "sleep"))
		return
	if npc.get("work_pause_until", 0) > s.tick:
		return
	if npc.job != 0 or not npc.goal.is_empty():
		return
	# Household chores run alongside the main trade: tending the garden in the morning and evening.
	if s.has("households") and not npc.get("work_cargo", false) and not npc.get("production_delivery", false) and cargo(s, npc) == 0 and Households.in_garden_hours(s):
		var window: int = s.tick / 14400 * 2 + (1 if Households.minute_of_day(s) >= 720 else 0)
		if npc.get("garden_window", -1) != window and not Households.garden_task(s, npc).is_empty():
			set_goal(s, npc, "garden")
			if npc.goal == "garden": npc.garden_window = window
			return
	if npc.occupation == "Builder" or npc.get("work_cargo", false) or npc.get("production_delivery", false):
		return
	if cargo(s, npc) > 0:
		set_goal(s, npc, "deposit")
	elif Professions.GATHERERS.has(npc.occupation):
		Jobs.assign(s, npc.id)
	elif npc.occupation == "Sheriff" and s.has("settlements"):
		Sheriff.next_duty(s, npc)

static func set_goal(s: Dictionary, npc: Dictionary, goal: String) -> void:
	if npc.has("sitting"): Sheriff.stand_up(s, npc)   # nobody walks off from a chair that is part of the furniture
	var destination_cell: Array = []
	if goal == "sleep":
		# Sleep in the bed assigned in the resident's home; with no bed, rest at the door as before.
		var bed: Dictionary = Households.bed_info(s, npc)
		if bed.is_empty(): goal = "rest"
		else:
			npc.bed_target = bed
			destination_cell = bed.approach
	var target: int = _destination(s, npc, "home" if goal in ["rest", "sleep"] else "warehouse")
	if goal in ["bandage", "shop", "stock_pantry"]:
		# Errands for the household: a bandage from the pantry (or the storehouse), shopping at the
		# storehouse, and carrying it home.
		if npc.job != 0: Jobs.release(s, npc.job, "ERRAND")
		var home: int = int(Households.household_of(s, npc).get("home", 0))
		var has_home: bool = home != 0 and s.inventories.has(str(home))
		if goal == "bandage" and has_home and Inventory.amount(s, home, "bandage") > 0: target = home
		if goal == "stock_pantry" and has_home: target = home
		npc.errand_target = target
	if goal == "eat":
		# Households eat from their own pantry first; the storehouse is the fallback.
		var household: Dictionary = Households.household_of(s, npc)
		if not household.is_empty() and s.inventories.has(str(household.home)) and (Inventory.amount(s, household.home, "food") >= 1 or Inventory.amount(s, household.home, "rye") >= 3):
			target = household.home
		npc.eat_target = target
	if goal == "patrol":
		var points: Array = Sheriff.patrol_points(s, npc)
		destination_cell = points[clampi(int(npc.get("patrol_index", 0)), 0, points.size() - 1)]
	if goal == "garden":
		var plot: Dictionary = Households.garden_task(s, npc)
		if plot.is_empty(): return
		npc.garden_plot = plot.id
		destination_cell = Households.garden_stance(plot)
	var route := Nav.request_path(s, s.entities[str(npc.id)].cell, destination_cell if not destination_cell.is_empty() else World.Fixtures.interaction_cell(s, target))
	if not route.ok:
		npc.status = goal + ": " + route.error_code
		npc.retry_at = s.tick + 100
		return
	npc.path = route.path
	npc.nav_revision = s.world.nav_revision
	npc.goal = goal
	npc.status = {"eat": "Going to eat", "rest": "Going home to rest", "deposit": "Returning carried goods", "drink": "Going to drink", "garden": "Going to the garden", "patrol": "Patrolling the square", "sleep": "Going to bed",
		"bandage": "Bleeding: going for a bandage", "shop": "Going to buy food for the family", "stock_pantry": "Carrying the shopping home"}.get(goal, "Walking")

static func _need_action(sim: RefCounted, npc: Dictionary) -> void:
	var s: Dictionary = sim.state
	if npc.nav_revision != s.world.nav_revision and not npc.path.is_empty() and Nav.still_clear(s, npc.path):
		npc.nav_revision = s.world.nav_revision   # a change elsewhere in the world: keep walking this route
	if npc.nav_revision != s.world.nav_revision and npc.get("sleeping", {}).is_empty():
		var goal: String = npc.goal
		npc.goal = ""
		set_goal(s, npc, goal)
		return
	if not npc.path.is_empty():
		s.entities[str(npc.id)].cell = npc.path.pop_front()
		return
	match npc.goal:
		"desk":
			Sheriff.sit(s, npc)
		"patrol":
			npc.goal = ""
			npc.status = "On patrol, watching the square"
			npc.work_pause_until = s.tick + 250
		"garden":
			var plot: Dictionary = s.crops.get(str(npc.get("garden_plot", 0)), {})
			if not plot.is_empty():
				var result: String = Crops.tend(s, plot)
				npc.status = {"sowed": "Sowed rye in the garden", "harvested": "Harvested the garden", "tended": "Weeded and watered the garden", "stalled": "Garden pantry is full"}.get(result, "Gardening")
			npc.goal = ""
			npc.work_pause_until = s.tick + 20
		"eat":
			var store: int = int(npc.get("eat_target", _destination(s, npc, "warehouse")))
			if not s.inventories.has(str(store)): store = _destination(s, npc, "warehouse")
			var at_home: bool = s.entities[str(store)].kind == "home"
			if at_home and Inventory.amount(s, store, "food") < 1 and Inventory.amount(s, store, "rye") >= 3:
				# Home baking: slower and wasteful compared with the village baker (3 rye makes 2 loaves, not 4).
				Inventory.consume(s, store, "rye", 3)
				Inventory.produce(s, store, "food", 2)
			var food_source: int = npc.id if Inventory.amount(s, npc.id, "food") > 0 else store
			if Inventory.consume(s, food_source, "food", 1):
				npc.hunger = maxi(0, npc.hunger - 45)
				npc.status = "Ate at home from the household pantry" if at_home else "Ate from communal stores"
				if not at_home and food_source == store: FamilyEconomy.pay_for_meal(s, npc, store)
			else:
				npc.status = "Hungry: store has no food"
				npc.retry_at = s.tick + 100
			npc.goal = ""
		"bandage":
			var source: int = int(npc.get("errand_target", 0))
			npc.goal = ""
			if s.inventories.has(str(source)) and Inventory.amount(s, source, "bandage") > 0 and Inventory.transfer(s, source, npc.id, "bandage", 1).ok:
				Bleeding.begin(s, npc)
			else:
				npc.status = "No bandage to be had"
				npc.retry_at = s.tick + 300
		"shop":
			npc.goal = ""
			FamilyEconomy.buy_food(sim, npc)
		"stock_pantry":
			npc.goal = ""
			FamilyEconomy.stock_pantry(s, npc)
		"drink":
			npc.thirst = maxi(0, int(npc.get("thirst", 0)) - 60)
			npc.status = "Drank from the well barrel"
			npc.goal = ""
		"sleep":
			if npc.get("sleeping", {}).is_empty():
				var bed: Dictionary = npc.get("bed_target", {})
				if bed.is_empty():
					npc.goal = ""
					return
				s.entities[str(npc.id)].cell = bed.lie.duplicate()
				npc.sleeping = {"lie": bed.lie, "approach": bed.approach, "rot": bed.rot, "bed_rect": bed.get("rect", []), "night": DayClock.bed_hours(s, npc), "since": s.tick}
				npc.status = "Sleeping in bed"
			if s.tick % 10 == 0: npc.fatigue = maxi(0, npc.fatigue - 1)
			# A night's sleep ends at the person's own waking time, 06:00-07:00.
			var morning: bool = not DayClock.bed_hours(s, npc)
			if (npc.sleeping.night and morning) or (not npc.sleeping.night and npc.fatigue <= 15) or npc.hunger >= 90 or npc.get("thirst", 0) >= 90:
				Households.wake(s, npc)
		"rest":
			npc.fatigue = maxi(0, npc.fatigue - 1)
			npc.status = "Resting at home"
			if npc.fatigue <= 10:
				npc.goal = ""
		"deposit":
			var store: int = _destination(s, npc, "warehouse")
			var items: Dictionary = s.inventories[str(npc.id)].items.duplicate()
			for item in items:
				if item in KIT: continue   # their own bandages stay with them
				var moved := Inventory.transfer(s, npc.id, store, item, items[item])
				if not moved.ok:
					npc.status = "Carrying goods: " + moved.error_code
					npc.retry_at = s.tick + 100
					break
			npc.goal = ""
			npc.production_delivery = false
			npc.work_pause_until = s.tick + 6
			npc.status = "Putting down carried goods"

static func remove(sim: RefCounted, id: int) -> void:
	var s: Dictionary = sim.state
	if not s.residents.has(str(id)):
		return
	var npc: Dictionary = s.residents[str(id)]
	if npc.job != 0:
		Jobs.release(s, npc.job, "WORKER_REMOVED")
	# Keep the inventory at its exact cell as a recoverable stash, never destroy goods.
	s.entities[str(id)].kind = "stash"
	World.entity_serial += 1
	s.entities[str(id)].name += "'s belongings"
	s.residents.erase(str(id))
