extends RefCounted
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")

static func initialize(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	s.recipes = JSON.parse_string(FileAccess.get_file_as_string("res://content/recipes/core.json")).recipes
	s.workshops = {}
	add_workshop(sim, 1, [81, 42], s.warehouse)
	add_workshop(sim, 1, [97, 42], s.warehouse, "bakery")

## Trade table shared by every workshop kind: building name, recipe, worker title and work label.
const TRADES: Dictionary = {
	"sawmill": {"name": "Timber workshop", "recipe": "core:recipe/planks", "occupation": "Sawyer", "label": "Sawing logs into planks", "waiting": "Waiting for logs"},
	"bakery": {"name": "Bakery", "recipe": "core:recipe/bread", "occupation": "Baker", "label": "Baking rye bread", "waiting": "Waiting for rye"},
	"forge": {"name": "Forge", "recipe": "core:recipe/tools", "occupation": "Blacksmith", "label": "Forging iron tools", "waiting": "Waiting for ore"}}

static func add_workshop(sim: RefCounted, settlement: int, cell: Array, store: int, kind: String = "sawmill") -> int:
	var trade: Dictionary = TRADES[kind]
	var id := World.add_entity(sim, kind, trade.name, cell, settlement)
	Inventory.create(sim.state, id, 100)
	sim.state.workshops[str(id)] = {"id": id, "settlement": settlement, "store": store, "recipe": trade.recipe, "worker": 0, "kind": kind,
		"progress": 0, "work_ticks": 40, "batch": 0, "completed": 0, "active": false, "status": trade.waiting, "enabled": true}
	return id

static func assign_worker(s: Dictionary, workshop: Dictionary) -> void:
	if s.residents.has(str(workshop.worker)) and s.residents[str(workshop.worker)].health > 0:
		return
	workshop.worker = 0
	var occupation: String = TRADES[workshop.get("kind", "sawmill")].occupation
	# A resident already trained for the trade is preferred; otherwise an idle gatherer retrains.
	for wanted in [occupation, "Gatherer"]:
		for npc in s.residents.values():
			if npc.settlement == workshop.settlement and npc.occupation == wanted and npc.get("migration", {}).is_empty() and npc.job == 0 and npc.health > 0 and not _is_assigned(s, npc.id):
				npc.occupation = occupation
				workshop.worker = npc.id
				return

static func _is_assigned(s: Dictionary, npc_id: int) -> bool:
	for workshop in s.workshops.values():
		if workshop.worker == npc_id: return true
	return false

static func start(s: Dictionary, workshop: Dictionary, source: int = 0) -> bool:
	if workshop.active:
		return false
	var recipe: Dictionary = workshop.get("batch_recipe", s.recipes[workshop.recipe]) if workshop.active else s.recipes[workshop.recipe]
	if source == workshop.id:
		if Inventory.amount(s, source, recipe.input) < recipe.input_quantity: return false
	else:
		var moved := Inventory.transfer(s, workshop.store if source == 0 else source, workshop.id, recipe.input, recipe.input_quantity)
		if not moved.ok:
			workshop.status = "Stopped: " + moved.error_code + " (logs)"
			return false
	workshop.batch_local = source == workshop.id
	workshop.batch_recipe = recipe.duplicate(true)
	workshop.batch += 1
	workshop.progress = 0
	workshop.active = true
	workshop.work_ticks = recipe.work_ticks
	workshop.status = "Working reserved " + str(recipe.input)
	return true

static func finish(s: Dictionary, workshop: Dictionary) -> bool:
	if not workshop.active or workshop.progress < workshop.work_ticks:
		return false
	var recipe: Dictionary = workshop.get("batch_recipe", s.recipes[workshop.recipe]) if workshop.active else s.recipes[workshop.recipe]
	if Inventory.amount(s, workshop.id, recipe.input) < recipe.input_quantity:
		workshop.status = "Reserved inputs missing"
		return false
	if Inventory.available(s, workshop.id) + int(recipe.input_quantity) < int(recipe.output_quantity):
		workshop.status = "Output full"
		return false
	# Commit point: prevalidated consume and produce, synchronously and exactly once.
	Inventory.consume(s, workshop.id, recipe.input, recipe.input_quantity)
	Inventory.produce(s, workshop.id, recipe.output, recipe.output_quantity)
	workshop.active = false
	workshop.completed += 1
	workshop.output_item = recipe.output
	workshop.progress = 0
	workshop.status = "Batch complete"
	return true

static func cancel(s: Dictionary, workshop: Dictionary) -> bool:
	if not workshop.active:
		return false
	var recipe: Dictionary = workshop.get("batch_recipe", s.recipes[workshop.recipe]) if workshop.active else s.recipes[workshop.recipe]
	if not workshop.get("batch_local", false):
		var moved := Inventory.transfer(s, workshop.id, workshop.store, recipe.input, recipe.input_quantity)
		if not moved.ok:
			workshop.status = "Cancellation awaiting storage capacity"
			return false
	workshop.active = false
	workshop.progress = 0
	workshop.status = "Batch cancelled; inputs returned"
	return true

static func work_at(s: Dictionary, npc: Dictionary, destination: int, station: int = 0) -> bool:
	var actor: Dictionary = s.entities[str(npc.id)]
	var target := World.Fixtures.interaction_cell(s, destination, station)
	if actor.cell == target:
		return true
	if npc.get("work_revision", -1) != s.world.nav_revision and npc.get("work_destination", 0) == destination and npc.get("work_station", 0) == station and npc.get("work_from", []) == actor.cell and not npc.get("work_path", []).is_empty() and npc.work_path.back() == target and Nav.still_clear(s, npc.work_path):
		npc.work_revision = s.world.nav_revision   # changed elsewhere; the route is still open
	if npc.get("work_destination", 0) != destination or npc.get("work_station", 0) != station or npc.get("work_revision", -1) != s.world.nav_revision or npc.get("work_from", []) != actor.cell:
		var route := Nav.request_path(s, actor.cell, target)
		if not route.ok:
			npc.status = "Work: " + route.error_code
			return false
		npc.work_path = route.path
		npc.work_destination = destination
		npc.work_station = station
		npc.work_revision = s.world.nav_revision
	if not npc.get("work_path", []).is_empty():
		actor.cell = npc.work_path.pop_front()
	npc.work_from = actor.cell.duplicate()
	return false

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if s.tick % 2 != 0:
		return
	for workshop in s.workshops.values():
		if workshop.get("player_operator",0)!=0: continue
		assign_worker(s, workshop)
		if workshop.worker == 0 or not workshop.enabled:
			continue
		var npc: Dictionary = s.residents[str(workshop.worker)]
		if npc.health <= 0 or s.get("local_combat", {}).get("fighters", {}).has(str(npc.id)): continue
		if npc.job != 0 or not npc.goal.is_empty() or npc.hunger >= 60 or npc.fatigue >= 75 or Brawl.busy(s, npc):
			workshop.status = "Worker attending to needs"
			continue
		if npc.get("work_pause_until", 0) > s.tick:
			continue
		_update_workshop(s, workshop, npc)

static func _update_workshop(s: Dictionary, workshop: Dictionary, npc: Dictionary) -> void:
	var recipe: Dictionary = workshop.get("batch_recipe", s.recipes[workshop.recipe]) if workshop.active else s.recipes[workshop.recipe]
	if npc.get("production_delivery", false):
		_deliver_output(s, workshop, npc, workshop.get("delivery_item", workshop.get("output_item", recipe.output)))
		return
	if workshop.active:
		if not work_at(s, npc, workshop.id):
			npc.status = "Walking to " + String(workshop.get("kind", "sawmill"))
			return
		workshop.progress += 2
		npc.status = TRADES[workshop.get("kind", "sawmill")].label
		if finish(s, workshop): npc.work_done = int(npc.get("work_done", 0)) + 1   # a batch earns the family a wage
		return

	var rack := World.Fixtures.stock_station(s, workshop.id)
	var output: String = workshop.get("output_item", recipe.output)
	var outputs := Inventory.amount(s, workshop.id, output)
	var inputs := Inventory.amount(s, workshop.id, recipe.input)
	var input_ready: bool = inputs >= recipe.input_quantity
	var has_room: bool = Inventory.available(s, workshop.id) + recipe.input_quantity >= recipe.output_quantity
	if outputs > 0 and (not input_ready or not has_room or output != recipe.output):
		if not work_at(s, npc, workshop.id, rack):
			npc.status = "Walking to the finished stock rack"
			return
		var quantity := mini(outputs, Inventory.available(s, npc.id))
		if quantity > 0 and Inventory.transfer(s, workshop.id, npc.id, output, quantity).ok:
			npc.production_delivery = true
			workshop.delivery_item = output
			workshop.delivery_target = _delivery_destination(s, workshop, output, quantity)
			_handling_pause(s, npc, "Picking up " + output)
		return
	if npc.get("work_cargo", false) or Inventory.amount(s, npc.id, recipe.input) > 0:
		if not work_at(s, npc, workshop.id, rack):
			npc.status = "Carrying inputs to " + String(workshop.get("kind", "sawmill"))
			return
		var quantity := mini(Inventory.amount(s, npc.id, recipe.input), Inventory.available(s, workshop.id))
		if quantity > 0 and Inventory.transfer(s, npc.id, workshop.id, recipe.input, quantity).ok:
			npc.work_cargo = Inventory.amount(s, npc.id, recipe.input) > 0
			_handling_pause(s, npc, "Putting down " + str(recipe.input))
		else:
			npc.work_cargo = false
		return
	if input_ready and has_room:
		if not work_at(s, npc, workshop.id):
			npc.status = "Walking from stock rack to " + String(workshop.get("kind", "sawmill"))
			return
		start(s, workshop, workshop.id)
		return
	# Bread is laid up for the winter: the baker keeps baking until the store holds plenty.
	if Inventory.amount(s, workshop.store, recipe.output) >= (800 if recipe.output == "food" else 300): return
	npc.status = "Walking to collect bulk workshop inputs"
	if not work_at(s, npc, workshop.store): return
	var requested := maxi(0, recipe.input_quantity * 4 - inputs)
	var quantity := mini(requested, mini(Inventory.available(s, npc.id), Inventory.amount(s, workshop.store, recipe.input)))
	if quantity > 0 and Inventory.transfer(s, workshop.store, npc.id, recipe.input, quantity).ok:
		npc.work_cargo = true
		workshop.status = "Worker stocking the workshop"
		_handling_pause(s, npc, "Picking up " + str(recipe.input))
	else:
		workshop.status = "Waiting for bulk inputs"

static func _delivery_destination(s: Dictionary, workshop: Dictionary, item: String, quantity: int) -> int:
	var town: Dictionary = s.get("settlements", {}).get(str(workshop.settlement), {})
	for id in town.get("stalls", []):
		var stall: Dictionary = s.entities[str(id)]
		if item in stall.sale_items and Inventory.amount(s, id, item) < 10 and Inventory.available(s, id) >= quantity:
			return id
	return workshop.store

static func _deliver_output(s: Dictionary, workshop: Dictionary, npc: Dictionary, item: String) -> void:
	var quantity := Inventory.amount(s, npc.id, item)
	if quantity <= 0:
		npc.production_delivery = false
		return
	var destination: int = workshop.get("delivery_target", workshop.store)
	if Inventory.available(s, destination) < quantity and destination != workshop.store:
		destination = workshop.store
		workshop.delivery_target = destination
	npc.status = "Delivering finished goods to market" if destination != workshop.store else "Delivering finished goods to warehouse"
	if not work_at(s, npc, destination): return
	if Inventory.transfer(s, npc.id, destination, item, quantity).ok:
		npc.production_delivery = false
		_handling_pause(s, npc, "Putting down " + item)

static func _handling_pause(s: Dictionary, npc: Dictionary, status: String) -> void:
	npc.work_pause_until = s.tick + 6
	npc.status = status
