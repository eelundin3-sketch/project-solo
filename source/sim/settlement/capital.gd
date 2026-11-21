extends RefCounted
## Dustvale is the capital. It keeps five sheriffs (the other towns three), and has two buildings
## of its own on the main street:
##   - the town house, where the Governor lives and works at his desk through the morning and day;
##   - the saloon, where the barkeep tends the bar from 14:00 into the night, townsfolk stop in for
##     a drink in the evening, and the traveller can buy one.
## Placed once (new games, and older saves on load). Deterministic: stream "saloon".
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const CAPITAL := "Dustvale"
const SHERIFFS := 3
const CAPITAL_SHERIFFS := 5
const WORK_FROM := 480      # the governor at his desk 08:00-16:00
const WORK_UNTIL := 960
const BAR_OPEN := 840       # the bar is tended 14:00-23:00
const BAR_CLOSE := 1380
const EVENING_FROM := 1080  # townsfolk drop in 18:00-21:00
const EVENING_UNTIL := 1260
const VISIT_CHANCE := 30
const DRINK_PRICE := 3

static func capital_id(s: Dictionary) -> int:
	for town in s.get("settlements", {}).values():
		if bool(town.get("capital", false)): return int(town.id)
	return 0

## How many sheriffs a town keeps: five in the capital, three elsewhere.
static func sheriffs_wanted(s: Dictionary, town: int) -> int:
	return CAPITAL_SHERIFFS if bool(s.get("settlements", {}).get(str(town), {}).get("capital", false)) else SHERIFFS

# --- setting up --------------------------------------------------------------------------------

static func ensure(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("settlements") or not s.has("households") or not s.has("accounts"): return
	var town: Dictionary = {}
	for t in s.settlements.values():
		if str(t.name) == CAPITAL: town = t
	if town.is_empty(): return
	town.capital = true
	if not town.has("town_hall"):
		var spot: Array = _plot(s, town, [])
		if spot.is_empty(): return
		town.town_hall = World.add_entity(sim, "town_hall", "Dustvale town house", spot, int(town.id))
		Inventory.create(s, int(town.town_hall), 200)
	var built: bool = not town.has("saloon")
	if not town.has("saloon"):
		var spot2: Array = _plot(s, town, [town.town_hall])
		if spot2.is_empty(): return
		town.saloon = World.add_entity(sim, "saloon", "The Dry Gulch saloon", spot2, int(town.id))
		Inventory.create(s, int(town.saloon), 200)
	var Residents = load("res://sim/entities/residents.gd")
	var added := false
	for role in [["governor", "Governor", town.town_hall], ["barkeep", "Barkeep", town.saloon]]:
		if town.has(role[0]): continue
		var building: Dictionary = s.entities[str(role[2])]
		var id: int = Residents.add_resident(sim, int(town.id), [building.door[0], building.door[1] - 1])
		var npc: Dictionary = s.residents[str(id)]
		npc.occupation = role[1]
		npc.age_days = 45
		var key: String = "%s:%d" % [role[0], id]
		s.households[key] = {"settlement": int(town.id), "members": [id], "home": int(role[2]), "formed": s.tick}
		npc.household = key
		town[role[0]] = id
		added = true
	if added: load("res://sim/entities/family_economy.gd").ensure(s)   # their purses, from the town's treasury
	if built: load("res://sim/entities/chests.gd").ensure_all(sim)      # the new buildings' chests
	_arm_offices(s)

## Every office rack holds a rifle for each sheriff the town keeps (made once, with the office).
static func _arm_offices(s: Dictionary) -> void:
	for town in s.settlements.values():
		if not town.has("office") or not s.inventories.has(str(town.office)) or bool(town.get("racks_filled", false)): continue
		var want: int = sheriffs_wanted(s, int(town.id))
		var have: int = Inventory.amount(s, int(town.office), "rifle")
		if have < want and Inventory.available(s, int(town.office)) >= want - have: Inventory.produce(s, int(town.office), "rifle", want - have)
		town.racks_filled = true

## A free plot on the main street for a 15 x 13 building: its door faces the street; nearest the
## storehouse first. Avoids other buildings, fields, the big rock and the roads.
static func _plot(s: Dictionary, town: Dictionary, also_avoid: Array) -> Array:
	var TownLayout = load("res://sim/world/town_layout.gd")
	var store: Array = s.entities[str(town.warehouse)].cell
	var taken: Array = []
	for entity in World.buildings(s): taken.append(World.building_rect(entity).grow(2))
	for plot in s.get("crops", {}).values(): taken.append(Rect2i(plot.rect[0], plot.rect[1], plot.rect[2], plot.rect[3]).grow(2))
	for entity in s.entities.values():
		if entity.has("rock_rect"): taken.append(Rect2i(entity.rock_rect[0], entity.rock_rect[1], entity.rock_rect[2], entity.rock_rect[3]).grow(2))
	for entity in s.entities.values():
		if str(entity.get("kind", "")) in ["street_lamp", "signpost", "stash", "market_stall"]: taken.append(Rect2i(int(entity.cell[0]) - 1, int(entity.cell[1]) - 1, 3, 3))
	for id in also_avoid:
		if s.entities.has(str(id)): taken.append(World.building_rect(s.entities[str(id)]).grow(2))
	for step in range(0, 90):
		for side in [1, -1]:
			var dx: int = (14 + step) * side
			for dy in [-3, -4, -2, -5, 6, 7]:
				var door: Array = [store[0] + dx, store[1] + dy]
				var rect := World.footprint(door, "town_hall")
				var clear := true
				for other in taken:
					if rect.intersects(other): clear = false; break
				if not clear: continue
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						if not World.walkable(s, [x, y]) or (TownLayout.on_road(s, [x, y]) and [x, y] != door): clear = false; break
					if not clear: break
				if clear and World.walkable(s, [door[0], door[1] + 1]): return door
	return []

# --- daily rounds ------------------------------------------------------------------------------

## Called from a resident's decision when they have nothing else to do. True if it set them going.
static func routine(sim: RefCounted, npc: Dictionary) -> bool:
	var s: Dictionary = sim.state
	var town: Dictionary = s.get("settlements", {}).get(str(npc.settlement), {})
	if town.is_empty() or not bool(town.get("capital", false)): return false
	var m: int = DayClock.minute(s)
	var at_work: bool = str(npc.occupation) == "Governor" and m >= WORK_FROM and m < WORK_UNTIL
	if npc.has("sitting") and not at_work:
		load("res://sim/law/sheriff.gd").stand_up(s, npc)   # the stay is over: up and about again
	match str(npc.occupation):
		"Governor":
			if m >= WORK_FROM and m < WORK_UNTIL:
				return _stay_or_sit(s, npc, int(town.get("town_hall", 0)), 0, "Governing at his desk", 300)
			if m >= EVENING_FROM and m < EVENING_UNTIL: return _maybe_visit(sim, npc, town)
		"Barkeep":
			if m >= BAR_OPEN and m < BAR_CLOSE: return _tend_bar(s, npc, town)
		"Sheriff", "Child", "Trader", "Bandit":
			return false
		_:
			if m >= EVENING_FROM and m < EVENING_UNTIL: return _maybe_visit(sim, npc, town)
	return false

## The chairs of a building, in furniture order: {"cell", "approach", "face"}.
static func seats(s: Dictionary, building_id: int) -> Array:
	var building: Dictionary = s.entities.get(str(building_id), {})
	var result: Array = []
	for item in building.get("furniture", []):
		if item.kind != "chair": continue
		var cell: Array = [item.rect[0], item.rect[1]]
		for offset in [[0, 1], [0, -1], [-1, 0], [1, 0]]:
			var approach: Array = [cell[0] + offset[0], cell[1] + offset[1]]
			if World.walkable(s, approach):
				result.append({"cell": cell, "approach": approach, "face": [-offset[0], -offset[1]]})
				break
	return result

static func _taken(s: Dictionary, cell: Array, except: int) -> bool:
	for other in s.residents.values():
		if int(other.id) == except: continue
		if other.get("sitting", {}).get("chair", []) == cell: return true
		if other.get("seat", {}).get("cell", []) == cell and str(other.get("goal", "")) == "seat": return true
	return false

## Sitting (or walking to sit) in chair `index` of a building; extends the stay if already there.
static func _stay_or_sit(s: Dictionary, npc: Dictionary, building_id: int, index: int, status: String, stay: int) -> bool:
	var chairs: Array = seats(s, building_id)
	if index >= chairs.size(): return false
	var chair: Dictionary = chairs[index]
	if npc.get("sitting", {}).get("chair", []) == chair.cell:
		npc.work_pause_until = s.tick + stay
		npc.status = status
		return true
	return _walk_to_seat(s, npc, chair, status, stay)

static func _walk_to_seat(s: Dictionary, npc: Dictionary, chair: Dictionary, status: String, stay: int) -> bool:
	if npc.has("sitting"): load("res://sim/law/sheriff.gd").stand_up(s, npc)
	var route := Nav.request_path(s, s.entities[str(npc.id)].cell, chair.approach)
	if not route.ok: return false
	npc.path = route.path
	npc.nav_revision = s.world.nav_revision
	npc.goal = "seat"
	npc.seat = {"cell": chair.cell.duplicate(), "approach": chair.approach.duplicate(), "face": chair.face.duplicate(), "status": status, "stay": stay}
	npc.status = "On the way: " + status.to_lower()
	return true

## Arrived by the chair (residents.gd goal "seat"): sit down for the stay.
static func sit(s: Dictionary, npc: Dictionary) -> void:
	var seat: Dictionary = npc.get("seat", {})
	npc.goal = ""
	npc.path = []
	if seat.is_empty() or _taken(s, seat.cell, int(npc.id)): return
	s.entities[str(npc.id)].cell = seat.cell.duplicate()
	npc.sitting = {"chair": seat.cell.duplicate(), "approach": seat.approach.duplicate(), "face": seat.face.duplicate(), "since": s.tick}
	npc.status = str(seat.status)
	npc.work_pause_until = s.tick + int(seat.stay)
	npc.erase("seat")

## The barkeep's place behind the counter.
static func counter_spot(s: Dictionary, town: Dictionary) -> Array:
	var saloon: Dictionary = s.entities.get(str(town.get("saloon", 0)), {})
	for item in saloon.get("furniture", []):
		if item.kind == "bar_counter": return [int(item.rect[0]) + 2, int(item.rect[1]) - 1]
	return []

static func _tend_bar(s: Dictionary, npc: Dictionary, town: Dictionary) -> bool:
	var spot: Array = counter_spot(s, town)
	if spot.is_empty(): return false
	var at: Array = s.entities[str(npc.id)].cell
	if at == spot:
		npc.work_pause_until = s.tick + 200
		npc.status = "Tending the bar"
		return true
	var route := Nav.request_path(s, at, spot)
	if not route.ok: return false
	npc.path = route.path
	npc.nav_revision = s.world.nav_revision
	npc.goal = "bar"
	npc.status = "Going to open the bar"
	return true

## True while the barkeep stands behind his counter, ready to serve.
static func serving(s: Dictionary, barkeep: Dictionary) -> bool:
	var town: Dictionary = s.get("settlements", {}).get(str(barkeep.get("settlement", 0)), {})
	var m: int = DayClock.minute(s)
	return str(barkeep.get("occupation", "")) == "Barkeep" and m >= BAR_OPEN and m < BAR_CLOSE \
		and s.entities[str(barkeep.id)].cell == counter_spot(s, town) and barkeep.get("sleeping", {}).is_empty()

## In the evening, now and then (once a day at most), someone goes for a drink and sits a while.
static func _maybe_visit(sim: RefCounted, npc: Dictionary, town: Dictionary) -> bool:
	var s: Dictionary = sim.state
	var day: int = int(s.tick) / DayClock.DAY
	if int(npc.get("bar_day", -1)) == day or not town.has("saloon"): return false
	npc.bar_day = day
	if sim.random_int("saloon", 0, 99) >= VISIT_CHANCE: return false
	for chair in seats(s, int(town.saloon)):
		if not _taken(s, chair.cell, int(npc.id)):
			return _walk_to_seat(s, npc, chair, "Having a drink at the saloon", 600 + sim.random_int("saloon", 0, 600))
	return false

# --- the traveller buys a drink ----------------------------------------------------------------

## A drink at the bar: 3 coins to the barkeep; it quenches your thirst and lifts your spirits.
static func buy_drink(s: Dictionary, barkeep: Dictionary) -> String:
	if not serving(s, barkeep): return "The bar isn't open just now."
	var player_key: String = str(s.player)
	if int(s.accounts.get(player_key, 0)) < DRINK_PRICE: return "A drink costs %d coins. You don't have enough." % DRINK_PRICE
	s.accounts[player_key] = int(s.accounts[player_key]) - DRINK_PRICE
	s.accounts[str(barkeep.id)] = int(s.accounts.get(str(barkeep.id), 0)) + DRINK_PRICE
	var needs: Dictionary = s.get("player_needs", {})
	if not needs.is_empty():
		needs.thirst = maxi(0, int(needs.thirst) - 45)
		needs.stress = maxi(0, int(needs.get("stress", 0)) - 10)
		needs.mood = mini(100, int(needs.get("mood", 70)) + 8)
	return "You buy a drink for %d coins. It goes down well." % DRINK_PRICE
