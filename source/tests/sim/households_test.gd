extends SceneTree
const Sim = preload("res://sim/core/simulation.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Households = preload("res://sim/entities/households.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Invariants = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	# Every household's home has a garden of sensible size beside the house.
	var homes: Dictionary = {}
	for household in s.households.values():
		if s.entities[str(household.home)].kind == "home": homes[household.home] = true   # not the governor's town house or the saloon
	check(not homes.is_empty(), "Households exist")
	for home in homes:
		var gardens: Array = Crops.plots_for_home(s, home)
		check(gardens.size() == 1, "Home %d has a garden" % home)
		if gardens.is_empty(): continue
		var g: Dictionary = gardens[0]
		check(Crops.cells(g) >= 6 and Crops.cells(g) <= 28, "Garden size is bounded")
		var fp: Array = s.entities[str(home)].footprint
		var outside: bool = g.rect[0] + g.rect[2] <= fp[0] or g.rect[0] >= fp[0] + fp[2] or g.rect[1] + g.rect[3] <= fp[1] or g.rect[1] >= fp[1] + fp[3]
		check(outside, "Garden lies outside the house footprint")
	# Professions are derived from resources: farmers and a sheriff emerge, a miner does not without ore.
	var want: Dictionary = Professions.demand(s, 1)
	check(want.get("Farmer", 0) >= 1 and want.get("Sheriff", 0) >= 1, "Farmer and sheriff demand follow from food and safety: " + str(want))
	check(not want.has("Miner") and not want.has("Blacksmith"), "No miner demand without ore nearby")
	check(want.has("Woodsman") and want.has("Sawyer") and not want.has("Baker"), "Wood trades follow the trees; a baker waits until the town has six people")
	for tick in range(14400 * 2): sim.step()
	var trades: Dictionary = {}
	for npc in s.residents.values():
		if npc.settlement == 1: trades[npc.occupation] = int(trades.get(npc.occupation, 0)) + 1
	check(trades.get("Farmer", 0) >= 1 and trades.get("Sheriff", 0) >= 1 and trades.get("Woodsman", 0) >= 1, "Residents hold varied trades: " + str(trades))
	# Residents tend gardens and the household lives from them while still doing their own trade.
	var tended := 0
	var harvests := 0
	for plot in s.crops.values():
		if plot.kind == "garden": tended += int(plot.tended); harvests += int(plot.harvests)
	check(tended + harvests > 0, "Household members tend their gardens")
	# Families form over time without breaking names or conservation.
	for tick in range(14400 * 8): sim.step()
	var partnered := 0
	for npc in s.residents.values():
		if npc.partner != 0: partnered += 1
	check(partnered >= 2, "Adults form partnerships: %d" % partnered)
	var seen: Dictionary = {}
	for entity in s.entities.values():
		if entity.kind in ["resident", "player"]:
			check(not seen.has(entity.name), "Name stays unique after births: " + entity.name)
			seen[entity.name] = true
	check(Invariants.validate(s).is_empty(), "Invariants hold: " + str(Invariants.validate(s)))
	if failures == 0: print("Households and professions: PASS")
	quit(failures)
