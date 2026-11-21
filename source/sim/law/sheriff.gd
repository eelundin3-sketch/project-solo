extends RefCounted
const KIT_BANDAGES := 2   # bandages each sheriff carries
## Sheriff's offices, their weapon racks and the sheriff's patrol rounds.
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const OFFICE_CELLS: Dictionary = {1: [29, 42], 2: [325, 42], 3: [116, 246]}
const RACK_SHOTGUNS := 2
const RACK_SHELLS := 30
const OFFICE_BANDAGES := 8

## One office per settlement; its rack is the office inventory (shotguns and shells).
static func install(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("settlements"): return
	for town in s.settlements.values():
		if town.has("office") or not OFFICE_CELLS.has(town.id): continue
		var id := World.add_entity(sim, "office", "%s sheriff's office" % town.name, OFFICE_CELLS[town.id], town.id)
		Inventory.create(s, id, 200)
		Inventory.produce(s, id, "rifle", RACK_SHOTGUNS)      # the office rack holds rifles
		Inventory.produce(s, id, "cartridge", RACK_SHELLS)
		Inventory.produce(s, id, "bandage", OFFICE_BANDAGES)   # the sheriffs' first-aid box
		town.office = id

## Every sheriff wears the badge and goes by "Sheriff <surname>", so the law is easy to spot.
static func dress(s: Dictionary) -> void:
	var Outfits = load("res://sim/entities/outfits.gd")
	var keys: Array = s.get("residents", {}).keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.occupation != "Sheriff" or npc.health <= 0: continue
		var entity: Dictionary = s.entities[str(npc.id)]
		if not String(entity.name).begins_with("Sheriff "):
			var parts: PackedStringArray = String(entity.name).split(" ")
			var title: String = "Sheriff " + parts[parts.size() - 1]
			# Names stay unique: a second sheriff with the same surname keeps his first name too.
			if load("res://sim/entities/names.gd").used(s).has(title): title = "Sheriff " + String(entity.name)
			entity.name = title
			load("res://sim/entities/names.gd").used(s)[entity.name] = true   # so reloads see the same pool
		if not npc.get("sheriff_dressed", false):
			Outfits.dress(s, npc.id, Outfits.SHERIFF)
			npc.sheriff_dressed = true

static func patrol_points(s: Dictionary, npc: Dictionary) -> Array:
	var town: Dictionary = s.settlements[str(npc.settlement)]
	var store: Array = s.entities[str(town.warehouse)].cell
	var points: Array = [[store[0], store[1] + 4], [store[0] - 14, store[1] + 4], [store[0] + 14, store[1] + 4], [store[0], store[1] + 10]]
	if town.has("office") and s.entities.has(str(town.office)): points.push_front(s.entities[str(town.office)].cell.duplicate())
	return points

## Gives an idle sheriff the next patrol leg. Returns true when a goal was set.
static func next_patrol(s: Dictionary, npc: Dictionary) -> bool:
	var points: Array = patrol_points(s, npc)
	if not npc.has("patrol_index"):
		npc.patrol_index = (roster(s, int(npc.settlement)).find(int(npc.id)) * 2) % points.size()   # spread the rounds out
	var index: int = (int(npc.get("patrol_index", -1)) + 1) % points.size()
	for attempt in range(points.size()):
		var route := Nav.request_path(s, s.entities[str(npc.id)].cell, points[index])
		if route.ok:
			npc.path = route.path
			npc.nav_revision = s.world.nav_revision
			npc.goal = "patrol"
			npc.patrol_index = index
			npc.status = "Patrolling the square"
			return true
		index = (index + 1) % points.size()
	npc.retry_at = s.tick + 100
	return false

## Sheriffs answer threats first, so they take the ranged defender slot.
static func defender_order(s: Dictionary) -> Array:
	var sheriffs: Array = []
	var others: Array = []
	for npc in s.residents.values():
		(sheriffs if npc.occupation == "Sheriff" else others).append(npc)
	return sheriffs + others

# --- how many, and what they do all day ---------------------------------------------------------

const ROTATION_TICKS := 1200        # how long one spell at the desk or on patrol lasts
const MIN_SHERIFFS := 2
const BIG_TOWN_RESIDENTS := 12      # a town with this many other adults keeps three

## The town's living sheriffs, by id.
static func roster(s: Dictionary, town: int) -> Array:
	var ids: Array = []
	for npc in s.get("residents", {}).values():
		if npc.occupation == "Sheriff" and npc.settlement == town and npc.health > 0: ids.append(int(npc.id))
	ids.sort()
	return ids

## Tops every town up to three sheriffs (five in the capital, capital.gd) with new residents who live at the
## office, so the people already there keep their trades.
static func ensure(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("settlements") or not s.has("residents"): return
	var towns: Array = s.settlements.keys()
	towns.sort()
	for key in towns:
		var town: Dictionary = s.settlements[key]
		if not town.has("office") or not s.entities.has(str(town.office)): continue
		var others := 0
		for npc in s.residents.values():
			if npc.settlement == town.id and npc.occupation not in ["Sheriff", "Child"] and npc.health > 0 and not npc.get("garrison", false): others += 1
		var want: int = load("res://sim/settlement/capital.gd").sheriffs_wanted(s, int(town.id))   # 3; 5 in the capital
		var have: int = roster(s, town.id).size()
		var office: Dictionary = s.entities[str(town.office)]
		while have < want:
			var door: Array = office.get("door", office.cell)
			var id: int = load("res://sim/entities/residents.gd").add_resident(sim, town.id, [door[0], door[1] + 1 + have])
			s.residents[str(id)].occupation = "Sheriff"
			s.residents[str(id)].garrison = true   # lives at the office; does not change the trades the town needs
			have += 1
		if have > 0: dress(s)
		# Every sheriff carries bandages for the wounds a gunfight leaves, refilled from the storehouse.
		for sheriff_id in roster(s, town.id):
			for source in [int(town.office), int(town.warehouse)]:   # the office's first-aid box, then the storehouse
				var short: int = KIT_BANDAGES - Inventory.amount(s, int(sheriff_id), "bandage")
				var spare: int = mini(short, mini(Inventory.amount(s, source, "bandage"), Inventory.available(s, int(sheriff_id))))
				if spare > 0: Inventory.transfer(s, source, int(sheriff_id), "bandage", spare)

## "desk" or "patrol": sheriffs take turns, so at least one is in the office at any time.
static func duty(s: Dictionary, npc: Dictionary) -> String:
	var ids: Array = roster(s, int(npc.settlement))
	var index: int = ids.find(int(npc.id))
	if index < 0 or ids.size() < 2: return "patrol"
	var phase: int = (s.tick / ROTATION_TICKS) % ids.size()
	return "desk" if (index + phase) % ids.size() == 0 else "patrol"

## The office chair, and the free cell beside it to walk to.
static func chair_of(s: Dictionary, npc: Dictionary) -> Dictionary:
	var office: Dictionary = s.entities.get(str(s.get("settlements", {}).get(str(npc.settlement), {}).get("office", 0)), {})
	for item in office.get("furniture", []):
		if item.kind != "chair": continue
		var cell: Array = [item.rect[0], item.rect[1]]
		for offset in [[0, 1], [0, -1], [-1, 0], [1, 0]]:
			var approach: Array = [cell[0] + offset[0], cell[1] + offset[1]]
			if World.walkable(s, approach):
				return {"cell": cell, "approach": approach, "face": [-offset[0], -offset[1]]}
	return {}

## Chooses between the desk and the rounds.
static func next_duty(s: Dictionary, npc: Dictionary) -> bool:
	if duty(s, npc) == "desk":
		if not npc.get("sitting", {}).is_empty():
			npc.work_pause_until = s.tick + 300
			npc.status = "Doing paperwork at his desk"
			return true
		if go_desk(s, npc): return true
	elif not npc.get("sitting", {}).is_empty():
		stand_up(s, npc)
	return next_patrol(s, npc)

static func go_desk(s: Dictionary, npc: Dictionary) -> bool:
	var chair := chair_of(s, npc)
	if chair.is_empty(): return false
	var route := Nav.request_path(s, s.entities[str(npc.id)].cell, chair.approach)
	if not route.ok: return false
	npc.path = route.path
	npc.nav_revision = s.world.nav_revision
	npc.goal = "desk"
	npc.status = "Going to his desk"
	return true

## Sits in the chair (the cell is furniture, so the body is put there by hand, as for a sleeper).
static func sit(s: Dictionary, npc: Dictionary) -> void:
	var chair := chair_of(s, npc)
	if chair.is_empty(): npc.goal = ""; return
	s.entities[str(npc.id)].cell = chair.cell.duplicate()
	npc.sitting = {"chair": chair.cell.duplicate(), "approach": chair.approach.duplicate(), "face": chair.face.duplicate(), "since": s.tick}
	npc.goal = ""
	npc.path = []
	npc.status = "Doing paperwork at his desk"
	npc.work_pause_until = s.tick + 600

static func stand_up(s: Dictionary, npc: Dictionary) -> void:
	var sitting: Dictionary = npc.get("sitting", {})
	if sitting.is_empty(): return
	s.entities[str(npc.id)].cell = sitting.approach.duplicate()
	npc.erase("sitting")
