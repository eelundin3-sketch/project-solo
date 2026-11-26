extends SceneTree
## Houses sized for their households, many house types, towns laid out clear of the roads, and
## towns a real journey apart on a larger map.
const Sim = preload("res://sim/core/simulation.gd")
const World = preload("res://sim/world/world_db.gd")
const Housing = preload("res://sim/settlement/housing.gd")
const Planner = preload("res://sim/settlement/planner.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const Orient = preload("res://sim/world/orient.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var ids: Dictionary = {}
	var beds_seen: Dictionary = {}
	for entry in Housing.TYPES:
		ids[entry.id] = true
		beds_seen[int(entry.beds)] = true
	check(ids.size() >= 12, "At least 12 house types (%d)" % ids.size())
	check(beds_seen.has(1) and beds_seen.has(2) and beds_seen.has(3) and beds_seen.size() == 3, "Houses have 1 to 3 beds")
	var sim := Sim.new(); sim.start_game()
	var s: Dictionary = sim.state
	var homes: Array = []
	var singles := 0
	var families := 0
	for household in s.households.values():
		var home: Dictionary = s.entities[str(household.home)]
		if home.kind in ["town_hall", "saloon"]: continue   # the governor and the barkeep live where they work
		check(home.has("house_type"), "Every household has a house of its own (%s)" % home.name)
		var beds := 0
		for item in home.get("furniture", []): if item.kind == "bed": beds += 1
		check(beds >= household.members.size() and beds >= 1 and beds <= 3, "%s: %d beds for %d people" % [home.name, beds, household.members.size()])
		if household.members.size() == 1:
			singles += 1
			check(int(home.house_beds) <= 2, "A single lives in a small house")
		else:
			families += 1
		homes.append(home)
	check(singles > 0 and families > 0, "Towns have both families and people living alone (%d, %d)" % [families, singles])
	var styles: Dictionary = {}
	for home in homes:
		styles[home.house_type] = true
		var rect := World.building_rect(home)
		var on_road := false
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if World.building_contains(home, [x, y]) and TownLayout.on_road(s, [x, y]): on_road = true
		check(not on_road, "%s does not block a road" % home.name)
		for other in s.entities.values():
			if other.has("footprint") and other.id != home.id:
				check(not World.building_rect(other).intersects(rect.grow(1)), "%s stands clear of %s" % [home.name, other.name])
		var store: Array = s.entities[str(s.settlements[str(home.settlement)].warehouse)].cell
		var out := Orient.outward(int(home.get("door_side", 2)))
		check(Nav.request_path(s, [home.door[0] + out.x, home.door[1] + out.y], store).ok, "%s is reachable from the square" % home.name)
	check(styles.size() >= 3, "The towns' houses are of different types (%d)" % styles.size())
	# A house planned later is a typed house on a clear plot too.
	var site := Planner.plan(sim, 1, "core:building/home")
	check(site != 0 and s.entities[str(site)].has("house_type"), "New houses are planned from the catalogue")
	if site != 0:
		var plot := World.plot_rect(s.entities[str(site)], "home")
		var site_entity: Dictionary = s.entities[str(site)]
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				if World.building_contains(site_entity, [x, y], "home"): check(not TownLayout.on_road(s, [x, y]), "A planned house keeps off the road")
	# The towns are far apart on a much larger map.
	var a: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var b: Array = s.entities[str(s.settlements["2"].warehouse)].cell
	var c: Array = s.entities[str(s.settlements["3"].warehouse)].cell
	check(Vector2(b[0] - a[0], b[1] - a[1]).length() > 250.0, "Reedbank is a long journey from Alder Hollow")
	check(Vector2(c[0] - a[0], c[1] - a[1]).length() > 180.0, "Dustvale is a long journey south")
	check(int(s.world.bounds[2]) - int(s.world.bounds[0]) > 500, "The map is much bigger")
	var copy := Sim.new(); copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Houses and households survive a reload unchanged")
	print("Housing: %s" % ("PASS" if failures == 0 else "FAIL")); quit(failures)
