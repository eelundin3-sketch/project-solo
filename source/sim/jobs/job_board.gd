extends RefCounted
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Professions = preload("res://sim/settlement/professions.gd")

static func initialize(state: Dictionary) -> void:
	state.jobs = {}
	state.job_archive = []
	state.completed_jobs = 0

static func refresh(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	for key in s.jobs.keys():
		var job: Dictionary = s.jobs[key]
		if job.owner != 0 and (not s.residents.has(str(job.owner)) or job.lease_until <= s.tick):
			release(s, job.id, "LEASE_EXPIRED")
	var targets: Dictionary = {}
	for job in s.jobs.values():
		targets[int(job.target)] = true
	for id in _resource_ids(s):
		if targets.has(id): continue
		var entity: Dictionary = s.entities.get(str(id), {})
		if entity.is_empty(): continue
		var destination: int = s.warehouse
		if s.has("settlements") and s.settlements.has(str(entity.settlement)):
			destination = s.settlements[str(entity.settlement)].warehouse
		var item: String = "log" if entity.kind == "tree" else ("ore" if entity.kind == "ore" else farm_item(s, entity.id, destination))
		if Inventory.amount(s, entity.id, item) < 1:
			continue
		var job_id: int = sim.new_id()
		var fresh := _index_valid(s)
		s.jobs[str(job_id)] = {"id": job_id, "kind": "gather", "target": entity.id,
			"destination": destination, "item": item, "quantity": 5, "owner": 0,
			"state": "OPEN", "lease_until": 0, "retry_count": 0, "retry_at": 0,
			"reason": "", "progress": 0, "settlement": entity.settlement}
		if fresh: _index_add(s, s.jobs[str(job_id)])

## How much of an item the storehouse takes in before gatherers stop bringing it. Food and rye
## are laid up for the winter (a 15-day season without a harvest), so the store keeps far more.
static func store_cap(item: String) -> int:
	if item == "log": return 800
	if item == "food" or item == "rye": return 800
	return 200

## What to carry from a farm: whichever of food and rye the storehouse is shorter of (so the rye
## harvest reaches the baker instead of piling up at the farm), if the farm has any.
static func farm_item(s: Dictionary, farm: int, store: int) -> String:
	var food: int = Inventory.amount(s, farm, "food")
	var rye: int = Inventory.amount(s, farm, "rye")
	if food < 1: return "rye"
	if rye < 1: return "food"
	return "food" if Inventory.amount(s, store, "food") <= Inventory.amount(s, store, "rye") else "rye"

## Jobs grouped by settlement, so a resident looking for work only walks their own town's jobs.
## Derived (never saved): kept up to date where jobs are created and removed, and rebuilt from
## the job table whenever it does not match (a load, or a change made elsewhere).
static var _town_cache: Array = []
static func _index_valid(s: Dictionary) -> bool:
	return World.DerivedCache.slot(_town_cache, s.jobs).get("count", -1) == s.jobs.size()

static func _index_add(s: Dictionary, job: Dictionary) -> void:
	var cache: Dictionary = World.DerivedCache.slot(_town_cache, s.jobs)
	var town: int = int(job.get("settlement", 0))
	if not cache.towns.has(town): cache.towns[town] = []
	cache.towns[town].append(job)
	cache.count = s.jobs.size()

static func _index_remove(s: Dictionary, job: Dictionary) -> void:
	var cache: Dictionary = World.DerivedCache.slot(_town_cache, s.jobs)
	cache.towns.get(int(job.get("settlement", 0)), []).erase(job)
	cache.count = s.jobs.size()

static func jobs_of_town(s: Dictionary, town: int) -> Array:
	var cache: Dictionary = World.DerivedCache.slot(_town_cache, s.jobs)
	if cache.get("count", -1) != s.jobs.size():
		var towns := {}
		for job in s.jobs.values():
			var key: int = int(job.get("settlement", 0))
			if not towns.has(key): towns[key] = []
			towns[key].append(job)
		cache.towns = towns
		cache.count = s.jobs.size()
	return cache.towns.get(town, [])

## Ids of every tree, farm and ore deposit, in entity-table order. Derived from the state and
## cached until entities are added or removed (resources never change kind).
static var _resources_cache: Array = []
static func _resource_ids(s: Dictionary) -> Array:
	var cache: Dictionary = World.DerivedCache.slot(_resources_cache, s.entities)
	var signature := [s.entities.size(), World.entity_serial]
	if cache.get("signature") == signature: return cache.ids
	var ids: Array = []
	for entity in s.entities.values():
		var kind: String = entity.get("kind", "")
		if kind == "tree" or kind == "farm" or kind == "ore": ids.append(int(entity.id))
	cache.ids = ids
	cache.signature = signature
	return ids

static func release(state: Dictionary, job_id: int, reason: String) -> void:
	if not state.jobs.has(str(job_id)):
		return
	var job: Dictionary = state.jobs[str(job_id)]
	Inventory.release(state, job.destination, str(job.id))
	if state.residents.has(str(job.owner)):
		var npc: Dictionary = state.residents[str(job.owner)]
		if npc.job == job_id:
			npc.job = 0
			npc.path = []
			npc.status = reason
	job.owner = 0
	job.state = "OPEN"
	job.lease_until = 0
	job.reason = reason
	job.retry_count += 1
	job.retry_at = state.tick + 40
	job.progress = 0

static func try_claim(state: Dictionary, job_id: int, npc_id: int) -> bool:
	if state.get("player_control",{}).get("work",{}).get("target",0) == state.jobs.get(str(job_id),{}).get("target",-1): return false
	if not state.jobs.has(str(job_id)) or not state.residents.has(str(npc_id)):
		return false
	var job: Dictionary = state.jobs[str(job_id)]
	var npc: Dictionary = state.residents[str(npc_id)]
	if job.owner != 0 or npc.job != 0 or job.retry_at > state.tick:
		return false
	var target: Dictionary = state.entities.get(str(job.target), {})
	if target.is_empty():
		return false
	var quantity: int = mini(job.quantity, Inventory.amount(state, job.target, job.item))
	if quantity <= 0 or Inventory.available(state, npc_id) < quantity:
		return false
	if not Inventory.reserve(state, job.destination, str(job.id), quantity):
		job.reason = "STORE_FULL"
		job.retry_at = state.tick + 100
		return false
	var route := Nav.request_path(state, state.entities[str(npc_id)].cell, source_stance(state, job))
	if not route.ok:
		Inventory.release(state, job.destination, str(job.id))
		job.reason = route.error_code
		job.retry_at = state.tick + 100
		job.retry_count += 1
		return false
	job.owner = npc_id
	job.quantity = quantity
	job.state = "MOVING_TO_SOURCE"
	job.lease_until = state.tick + (150 if npc.fidelity == "aggregate" else 50)
	npc.job = job.id
	npc.path = route.path
	npc.nav_revision = state.world.nav_revision
	npc.status = "Gathering " + job.item
	return true

static func assign(state: Dictionary, npc_id: int) -> bool:
	var npc: Dictionary = state.residents[str(npc_id)]
	var cell: Array = state.entities[str(npc_id)].cell
	var threshold: int = 200 if state.get("settlements", {}).get(str(npc.settlement), {}).get("policy", "") == "Food first" else 100
	# Store levels and trade rules are the same for every job of a kind: look each up once.
	var store_open: Dictionary = {}
	var food_short: Dictionary = {}
	var gathers: Dictionary = {}
	# Candidates as one sortable number each: best score first, then lowest id (as before).
	var order := PackedInt64Array()
	for job in jobs_of_town(state, int(npc.settlement)):
		if job.owner != 0 or job.retry_at > state.tick or job.settlement != npc.settlement: continue
		var store_key: String = "%d:%s" % [job.destination, job.item]
		if not store_open.has(store_key):
			store_open[store_key] = Inventory.amount(state, job.destination, job.item) < store_cap(job.item)
		if not store_open[store_key] and job.item in ["food", "rye"]:
			# The store is full of this one: carry the farm's other crop instead, if it has room for that.
			var other: String = "rye" if job.item == "food" else "food"
			if Inventory.amount(state, job.target, other) >= 1 and Inventory.amount(state, job.destination, other) < store_cap(other):
				job.item = other
				store_key = "%d:%s" % [job.destination, job.item]
				store_open[store_key] = true
		if not store_open[store_key]: continue
		var target: Dictionary = state.entities[str(job.target)]
		var kind: String = target.kind
		if not gathers.has(kind): gathers[kind] = Professions.gathers(npc, kind)
		if not gathers[kind]: continue
		var distance: int = absi(cell[0] - target.cell[0]) + absi(cell[1] - target.cell[1])
		var priority: int = 0
		if job.item == "food":
			if not food_short.has(job.destination): food_short[job.destination] = Inventory.amount(state, job.destination, "food") < threshold
			priority = 100 if food_short[job.destination] else 0
		order.append((int(1 << 20) - (priority - distance)) * (int(1) << 32) + int(job.id))
	order.sort()
	for key in order:
		if try_claim(state, int(key & 0xFFFFFFFF), npc_id):
			return true
	npc.status = "No reachable work / store full"
	return false

static func advance(sim: RefCounted, npc_id: int) -> void:
	var s: Dictionary = sim.state
	var npc: Dictionary = s.residents[str(npc_id)]
	if not s.jobs.has(str(npc.job)):
		npc.job = 0
		return
	var job: Dictionary = s.jobs[str(npc.job)]
	job.lease_until = s.tick + (150 if npc.fidelity == "aggregate" else 50)
	var actor: Dictionary = s.entities[str(npc_id)]
	if npc.nav_revision != s.world.nav_revision:
		var goal: Array = World.Fixtures.interaction_cell(s, job.destination) if job.state in ["MOVING_TO_DEST", "DEPOSITING"] else source_stance(s, job)
		var keeps: bool = (npc.path.is_empty() and actor.cell == goal) or (not npc.path.is_empty() and npc.path.back() == goal and Nav.still_clear(s, npc.path))
		var route := {"ok": true, "path": npc.path} if keeps else Nav.request_path(s, actor.cell, goal)
		if not route.ok:
			release(s, job.id, route.error_code)
			return
		npc.path = route.path
		npc.nav_revision = s.world.nav_revision
	if not npc.path.is_empty():
		actor.cell = npc.path.pop_front()
		return
	match job.state:
		"MOVING_TO_SOURCE":
			job.state = "WORKING"
			npc.status = "Harvesting " + job.item
		"WORKING":
			job.progress += 2
			if job.progress < 20:
				return
			var tree: Dictionary = state_entity(s, job.target)
			if tree.get("kind", "") == "tree" and not tree.get("felled", false):
				tree.felled = true  # chopped down: it falls and its wood is hauled from the trunk
				tree.felled_tick = s.tick
			job.state = "PICKING_UP"
			job.progress = 0
			npc.status = "Picking up " + job.item
		"PICKING_UP":
			job.progress += 2
			if job.progress < 6:
				return
			var moved := Inventory.transfer(s, job.target, npc_id, job.item, job.quantity)
			if not moved.ok:
				release(s, job.id, moved.error_code)
				return
			var route := Nav.request_path(s, actor.cell, World.Fixtures.interaction_cell(s, job.destination))
			if not route.ok:
				release(s, job.id, route.error_code)
				return
			npc.path = route.path
			job.state = "MOVING_TO_DEST"
			npc.status = "Hauling %d %s" % [job.quantity, job.item]
		"MOVING_TO_DEST":
			job.state = "DEPOSITING"
			job.progress = 0
			npc.status = "Putting down " + job.item
		"DEPOSITING":
			job.progress += 2
			if job.progress < 6:
				return
			var moved := Inventory.transfer(s, npc_id, job.destination, job.item, job.quantity, str(job.id))
			if not moved.ok:
				release(s, job.id, moved.error_code)
				return
			job.state = "DONE"
			s.completed_jobs += 1
			npc.work_done = int(npc.get("work_done", 0)) + 1   # paid each evening (family_economy.gd)
			npc.skill = mini(100, npc.skill + 1)
			s.job_archive.append(job.duplicate(true))
			if s.job_archive.size() > 64:
				s.job_archive.pop_front()
			var indexed := _index_valid(s)
			s.jobs.erase(str(job.id))
			if indexed: _index_remove(s, job)
			npc.job = 0
			npc.status = "Delivered " + job.item
			if s.completed_jobs % 10 == 0:
				sim.record("Workers completed %d deliveries" % s.completed_jobs)

static func advance_many(sim: RefCounted, npc_id: int, actions: int) -> void:
	# Aggregate travel/work algebraically, crossing only transaction boundaries.
	# The same record owns cargo and reservations throughout the coarse interval.
	var s: Dictionary = sim.state
	var npc: Dictionary = s.residents[str(npc_id)]
	while actions > 0 and npc.job != 0:
		var job: Dictionary = s.jobs[str(npc.job)]
		job.lease_until = s.tick + 150
		if npc.nav_revision != s.world.nav_revision:
			advance(sim, npc_id)
			actions -= 1
			continue
		if not npc.path.is_empty():
			var distance: int = mini(actions, npc.path.size())
			s.entities[str(npc_id)].cell = npc.path[distance - 1]
			npc.path = npc.path.slice(distance)
			actions -= distance
			continue
		if job.state == "WORKING" and job.progress < 18:
			var work: int = mini(actions, (18 - int(job.progress)) / 2)
			job.progress += work * 2
			actions -= work
			if actions == 0:
				break
		advance(sim, npc_id)
		actions -= 1

static func source_stance(s: Dictionary, job: Dictionary) -> Array:
	var cell: Array = s.entities[str(job.target)].cell
	if not World.walkable(s, cell):
		return cell
	for offset in [[0, 1], [-1, 0], [1, 0], [0, -1]]:
		var stance: Array = [cell[0] + offset[0], cell[1] + offset[1]]
		if World.walkable(s, stance):
			return stance
	return cell

static func state_entity(s: Dictionary, id: int) -> Dictionary:
	return s.entities.get(str(id), {})
