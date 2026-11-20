extends RefCounted
## Households, families and private gardens. A household lives in a home, keeps a
## pantry (the home's own inventory), tends a garden beside the house and still
## relies on the settlement economy for whatever the garden cannot supply.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const HOME_CAPACITY := 4
const LODGE_CAPACITY := 8
const CHILD_GROWN_DAYS := 8
const MAX_CHILDREN := 3
const MORNING := Vector2i(360, 450)   # 06:00-07:30
const EVENING := Vector2i(1050, 1170) # 17:30-19:30

static func capacity(s: Dictionary, home_id: int) -> int:
	var town: Dictionary = s.settlements.get(str(s.entities[str(home_id)].settlement), {})
	if s.entities[str(home_id)].has("house_beds"): return int(s.entities[str(home_id)].house_beds)   # one bed each
	return LODGE_CAPACITY if town.get("home", 0) == home_id else HOME_CAPACITY

static func members_of(s: Dictionary, home_id: int) -> int:
	var total := 0
	for household in s.get("households", {}).values():
		if household.home == home_id: total += household.members.size()
	return total

static func household_of(s: Dictionary, npc: Dictionary) -> Dictionary:
	return s.get("households", {}).get(str(npc.get("household", "")), {})

static func pantry(s: Dictionary, household: Dictionary) -> int:
	return int(household.get("home", 0))

## Makes sure every household's home has a pantry inventory and a garden; also
## fills fields on records created by older saves.
static func upgrade(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("households") or not s.has("settlements"): return
	for key in s.households:
		var household: Dictionary = s.households[key]
		if not household.has("children"): household.children = 0
		if not household.has("formed"): household.formed = 0
		if not s.inventories.has(str(household.home)) and s.entities.has(str(household.home)):
			Inventory.create(s, household.home, 400)
	for npc in s.residents.values():
		if not npc.has("age_days"): npc.age_days = 30 + npc.id % 15
		if not npc.has("partner"): npc.partner = 0
	var homes: Dictionary = {}
	for household in s.households.values(): homes[household.home] = true
	for home_id in homes:
		ensure_garden(sim, int(home_id))

static func occupants(s: Dictionary, home_id: int) -> int:
	return maxi(1, members_of(s, home_id))

## Garden size follows the household and the free space: from 6 cells up to 28.
static func ensure_garden(sim: RefCounted, home_id: int) -> bool:
	var s: Dictionary = sim.state
	if not s.entities.has(str(home_id)) or not s.entities[str(home_id)].has("footprint"): return false
	if not Crops.plots_for_home(s, home_id).is_empty(): return true
	var wanted: int = clampi(occupants(s, home_id) * 3 + 4, 6, 28)
	var rect: Array = find_garden_rect(s, home_id, wanted)
	if rect.is_empty():
		return false
	_clear_trees(s, Rect2i(rect[0] - 1, rect[1] - 1, rect[2] + 2, rect[3] + 4))
	var grown: int = sim.random_int("garden", 0, Crops.CYCLE_TICKS / 2)
	Crops.add_plot(s, "garden", rect, s.entities[str(home_id)].settlement, 0, home_id, grown)
	return true

## Settlers clear the land for a garden: trees inside the bed are moved (not destroyed) to
## the nearest free ground outside it, so their logs stay in the world.
static func _clear_trees(s: Dictionary, area: Rect2i) -> void:
	var taken: Dictionary = {}
	for entity in s.entities.values():
		if entity.has("cell"): taken[World.cell_key(entity.cell)] = true
	for entity in s.entities.values():
		if entity.get("kind", "") != "tree" or not area.has_point(Vector2i(entity.cell[0], entity.cell[1])): continue
		var placed := false
		for radius in range(2, 14):
			for dx in range(-radius, radius + 1):
				for dy in [-radius, radius]:
					for candidate in [[area.position.x + area.size.x / 2 + dx, area.position.y + area.size.y / 2 + dy], [area.position.x + area.size.x / 2 + dy, area.position.y + area.size.y / 2 + dx]]:
						if placed or area.has_point(Vector2i(candidate[0], candidate[1])): continue
						if taken.has(World.cell_key(candidate)) or not World.walkable(s, candidate) or World.inside_building(s, candidate) != 0: continue
						taken.erase(World.cell_key(entity.cell))
						World.move_record(s, entity, candidate)
						taken[World.cell_key(candidate)] = true
						placed = true
			if placed: break

static func _free(s: Dictionary, rect: Rect2i, home_id: int) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not World.walkable(s, [x, y]): return false
	var padded: Rect2i = rect.grow(1)
	for entity in s.entities.values():
		if not entity.has("cell") or entity.kind in ["resident", "player", "caravan", "raider"]: continue
		if entity.has("footprint") and padded.intersects(World.building_rect(entity)) and entity.id != home_id: return false
		if entity.kind in ["construction", "farm", "market_stall", "stash", "ore"] and padded.has_point(Vector2i(entity.cell[0], entity.cell[1])): return false
		if entity.kind == "construction" and padded.intersects(World.plot_rect(entity, "home")): return false
	for plot in s.get("crops", {}).values():
		if padded.intersects(Rect2i(plot.rect[0], plot.rect[1], plot.rect[2], plot.rect[3])): return false
	for plot in World.reserved_home_plots(s.entities[str(s.settlements[str(s.entities[str(home_id)].settlement)].warehouse)].cell):
		if rect.intersects(plot): return false
	return true

## Tries the sides of the house (west, east, north) and then the front corners,
## largest garden first, so a cramped plot still gets a smaller bed.
static func find_garden_rect(s: Dictionary, home_id: int, wanted: int) -> Array:
	var house: Dictionary = s.entities[str(home_id)]
	var fp: Rect2i = World.building_rect(house)
	var sizes: Array = []
	for cells in range(wanted, 5, -1):
		for height in range(2, 6):
			if cells % height == 0 and cells / height >= 3 and cells / height <= 8:
				sizes.append([cells / height, height])
	for size in sizes:
		var w: int = size[0]
		var h: int = size[1]
		var candidates: Array = [
			Rect2i(fp.position.x - w - 2, fp.end.y - h - 1, w, h),         # west, beside the front rooms
			Rect2i(fp.end.x + 2, fp.end.y - h - 1, w, h),                  # east
			Rect2i(fp.position.x - w - 2, fp.position.y + 1, w, h),        # west, rear
			Rect2i(fp.end.x + 2, fp.position.y + 1, w, h),                 # east, rear
			Rect2i(fp.position.x + 1, fp.position.y - h - 2, w, h),        # north, behind the house
			Rect2i(fp.position.x - w - 2, fp.end.y + 1, w, h),             # front corner, west
			Rect2i(fp.end.x + 2, fp.end.y + 1, w, h)]                      # front corner, east
		for rect in candidates:
			if _free(s, rect, home_id): return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return []

static func minute_of_day(s: Dictionary) -> int:
	return (s.tick / 10) % 1440

static func in_garden_hours(s: Dictionary) -> bool:
	var minute := minute_of_day(s)
	return (minute >= MORNING.x and minute < MORNING.y) or (minute >= EVENING.x and minute < EVENING.y)

## First garden of the resident's home that wants work (sow, tend or harvest).
static func garden_task(s: Dictionary, npc: Dictionary) -> Dictionary:
	if npc.occupation == "Child" and npc.get("age_days", 0) < 4: return {}
	var household: Dictionary = household_of(s, npc)
	if household.is_empty(): return {}
	for plot in Crops.plots_for_home(s, household.home):
		if Crops.needs_attention(plot): return plot
	return {}

static func garden_stance(plot: Dictionary) -> Array:
	return [plot.rect[0] + plot.rect[2] / 2, plot.rect[1] + plot.rect[3]]

## Daily household life: children grow up, adults pair off, couples may have a child.
static func daily(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("households"): return
	for npc in s.residents.values():
		npc.age_days = int(npc.get("age_days", 30)) + 1
		if npc.occupation == "Child" and npc.age_days >= CHILD_GROWN_DAYS:
			npc.occupation = "Gatherer"
			sim.record(s.entities[str(npc.id)].name + " has grown up and is ready to work.")
	for town in s.settlements.values():
		Professions.assign(s, town.id)
		load("res://sim/law/sheriff.gd").ensure(sim)
		_pair_up(sim, town)
		_births(sim, town)
	load("res://sim/entities/family_economy.gd").ensure(s)   # new families get their purse and name now
	load("res://sim/entities/gossip.gd").daily(s)
	load("res://sim/player/requests.gd").daily(sim)           # people ask for what they lack             # families share news; towns come to know it
	load("res://sim/factions/society.gd").drought_moves(sim)   # farming families leave after a failed harvest
	load("res://sim/factions/reputation.gd").update(s)        # the player's standing in each town, from what each knows

static func _pair_up(sim: RefCounted, town: Dictionary) -> void:
	var s: Dictionary = sim.state
	var singles: Array = []
	for npc in s.residents.values():
		if npc.settlement == town.id and npc.partner == 0 and npc.occupation != "Child" and npc.health > 0 and npc.get("migration", {}).is_empty() and int(npc.age_days) >= 16:
			singles.append(npc.id)
	singles.sort()
	# Each adult wants a family: partners are drawn in id order, with some chance each day.
	while singles.size() >= 2:
		var a: int = singles.pop_front()
		var b: int = singles.pop_front()
		if sim.random_int("family", 0, 99) >= 40: continue
		s.residents[str(a)].partner = b
		s.residents[str(b)].partner = a
		_move_in_together(sim, town, a, b)
		sim.record("%s and %s start a family." % [s.entities[str(a)].name, s.entities[str(b)].name])

static func _move_in_together(sim: RefCounted, town: Dictionary, a: int, b: int) -> void:
	var s: Dictionary = sim.state
	var best_home: int = 0
	var best_room: int = 1
	for entity in s.entities.values():
		if entity.kind == "home" and entity.settlement == town.id and entity.has("footprint"):
			var room: int = capacity(s, entity.id) - members_of(s, entity.id)
			if room > best_room or (room == best_room and best_home != 0 and entity.id < best_home and room >= 2):
				best_home = entity.id
				best_room = room
	if best_home == 0 or best_room < 2: best_home = int(s.residents[str(a)].get("home_override", 0))
	for id in [a, b]:
		var old: Dictionary = household_of(s, s.residents[str(id)])
		if not old.is_empty(): old.members.erase(id)
	var home: int = best_home if best_home != 0 else (household_of(s, s.residents[str(a)]).get("home", town.home) if not household_of(s, s.residents[str(a)]).is_empty() else town.home)
	var key := "%d:f%d" % [town.id, s.households.size() + sim.state.tick]
	while s.households.has(key): key += "x"
	s.households[key] = {"settlement": town.id, "members": [a, b], "home": home, "children": 0, "formed": s.tick}
	s.residents[str(a)].household = key
	s.residents[str(b)].household = key
	if not s.inventories.has(str(home)): Inventory.create(s, home, 400)
	ensure_garden(sim, home)

static func _births(sim: RefCounted, town: Dictionary) -> void:
	var s: Dictionary = sim.state
	for key in s.households.keys():
		var household: Dictionary = s.households[key]
		if household.settlement != town.id or household.members.size() < 2 or household.children >= MAX_CHILDREN: continue
		if s.tick - int(household.formed) < 14400 * 3: continue
		var parents := 0
		for id in household.members:
			if s.residents.has(str(id)) and s.residents[str(id)].partner != 0 and s.residents[str(id)].occupation != "Child": parents += 1
		if parents < 2: continue
		if members_of(s, household.home) >= capacity(s, household.home): continue
		if int(town.get("population", 0)) >= int(town.housing) + 2: continue
		var food: int = Inventory.amount(s, household.home, "food") + Inventory.amount(s, household.home, "rye") / 2
		if food < 3 and Inventory.amount(s, town.warehouse, "food") < 40: continue
		if sim.random_int("family", 0, 99) >= 18: continue
		var door: Array = s.entities[str(household.home)].cell.duplicate()
		var residents_script: GDScript = load("res://sim/entities/residents.gd")  # loaded lazily: residents.gd also depends on this file
		var child: int = residents_script.add_resident(sim, town.id, door, true)
		household.members.append(child)
		household.children += 1
		s.residents[str(child)].household = key
		town.population = int(town.get("population", 0)) + 1
		load("res://sim/world/chronicle.gd").record(s, "birth", int(town.id), int(household.members[0]), child, door)
		sim.record("%s was born to the %s household." % [s.entities[str(child)].name, s.entities[str(household.members[0])].name.split(" ")[-1]])

## A newly built house takes in the most crowded household and gets a garden.
static func on_home_built(sim: RefCounted, home_id: int) -> void:
	var s: Dictionary = sim.state
	var town_id: int = s.entities[str(home_id)].settlement
	var chosen := ""
	var crowd := 0
	for key in s.households:
		var household: Dictionary = s.households[key]
		if household.settlement != town_id or household.home == home_id: continue
		var load: int = household.members.size()
		if load > crowd and load <= capacity(s, home_id) and members_of(s, household.home) > capacity(s, household.home) / 2:
			crowd = load
			chosen = key
	if not s.inventories.has(str(home_id)): Inventory.create(s, home_id, 400)
	if not chosen.is_empty():
		s.households[chosen].home = home_id
		sim.record("A household moves into the new house.")
	ensure_garden(sim, home_id)

## Each resident has a bed in their home; with more people than beds some share one.
## Returns {"lie": cell, "approach": cell, "rot": orientation} or {} when the home has no bed.
static func bed_info(s: Dictionary, npc: Dictionary) -> Dictionary:
	var household: Dictionary = household_of(s, npc)
	var home: Dictionary = {}
	var beds: Array = []
	# The sheriff sleeps at his office, in his own bed (never on the prisoner's cot).
	var office: Dictionary = s.entities.get(str(s.get("settlements", {}).get(str(npc.settlement), {}).get("office", 0)), {})
	if npc.occupation == "Sheriff" and not office.is_empty():
		for item in office.get("furniture", []):
			if item.kind == "bed" and item.get("for", "") == "sheriff": beds.append(item)
		if not beds.is_empty():
			home = office
	if home.is_empty():
		if household.is_empty() or not s.entities.has(str(household.home)): return {}
		home = s.entities[str(household.home)]
		for item in home.get("furniture", []):
			if item.kind == "bed" and item.get("for", "") != "prisoner": beds.append(item)
	if beds.is_empty(): return {}
	var members: Array = []
	if home == office: members = [npc.id]
	else:
		for other in s.households.values():
			if other.home == household.home: members.append_array(other.members)
	members.sort()
	if home == office: members = load("res://sim/law/sheriff.gd").roster(s, int(npc.settlement))   # each sheriff has his own bunk
	var bed: Dictionary = beds[maxi(0, members.find(npc.id)) % beds.size()]
	var rect: Array = bed.rect
	var lie: Array = [rect[0] + rect[2] / 2, rect[1] + rect[3] / 2]
	var best: Array = []
	var best_distance := 9999
	for y in range(rect[1] - 1, rect[1] + rect[3] + 1):
		for x in range(rect[0] - 1, rect[0] + rect[2] + 1):
			if x >= rect[0] and x < rect[0] + rect[2] and y >= rect[1] and y < rect[1] + rect[3]: continue
			var distance: int = absi(x - lie[0]) + absi(y - lie[1])
			if distance < best_distance and World.walkable(s, [x, y]):
				best = [x, y]
				best_distance = distance
	if best.is_empty(): return {}
	return {"lie": lie, "approach": best, "rot": int(bed.get("rot", 3)), "rect": rect.duplicate()}

## Gets a sleeper out of bed (woken by morning, hunger, or a fight).
static func wake(s: Dictionary, npc: Dictionary) -> void:
	var sleeping: Dictionary = npc.get("sleeping", {})
	if sleeping.is_empty(): return
	s.entities[str(npc.id)].cell = sleeping.approach.duplicate()
	npc.sleeping = {}
	if npc.goal == "sleep": npc.goal = ""
	npc.work_pause_until = s.tick + 20
	npc.status = "Woke up"
