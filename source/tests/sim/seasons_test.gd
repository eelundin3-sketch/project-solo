extends SceneTree
## Seasons and harvest (milestone 5, E7): no growth in winter, faster in summer, the first frost
## spoils what is left in the fields, spring sowing, a bare field after the autumn harvest, and
## farmers turning to other work for the winter and back in spring.
const Sim = preload("res://sim/core/simulation.gd")
const Weather = preload("res://sim/world/weather.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Households = preload("res://sim/entities/households.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
const SEASON := 14400 * 7
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func a_field(s: Dictionary) -> Dictionary:
	var keys: Array = s.crops.keys()
	keys.sort()
	for key in keys:
		if s.crops[key].kind == "field": return s.crops[key]
	return {}

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var field: Dictionary = a_field(s)
	check(not field.is_empty(), "There is a field")
	for region in s.weather.regions.values(): region.dry_days = 0

	# Growth by season.
	s.tick = SEASON * 0 + 14400 + 100
	check(Crops.growth_step(s, field) == 10, "Spring: normal growth")
	s.tick = SEASON * 1 + 14400 + 100
	check(Crops.growth_step(s, field) == 12, "Summer: 20% faster")
	s.tick = SEASON * 3 + 14400 + 100
	check(Crops.growth_step(s, field) == 0, "Winter: no growth")
	field.state = "growing"; field.grown = 2000
	for i in range(20):
		s.tick += 10
		Crops.update(s)
	check(int(field.grown) == 2000, "A crop waits through the winter")

	# The first frost spoils whatever is still in the field.
	field.state = "growing"; field.grown = Crops.CYCLE_TICKS; field.ripe_since = 0
	s.tick = SEASON * 3
	Crops.update(s)
	check(field.state == "fallow" and int(field.spoiled) == 1, "An unharvested crop spoils at the first frost")
	check(Crops.stage(field) == -1, "The field lies bare in winter")

	# Spring: the fields are sown again.
	s.tick = SEASON * 4
	Crops.update(s)
	check(field.state == "growing" and int(field.grown) <= 10, "Bare fields are sown in spring")

	# The autumn harvest leaves the field bare; a summer harvest resows it.
	field.grown = Crops.CYCLE_TICKS
	s.tick = SEASON * 2 + 14400 * 3
	check(Crops.harvest(s, field) > 0, "An autumn harvest brings in rye")
	check(field.state == "fallow", "After the autumn harvest the field is bare")
	field.state = "growing"; field.grown = Crops.CYCLE_TICKS
	s.tick = SEASON * 1 + 14400 * 3
	Crops.harvest(s, field)
	check(field.state == "growing", "A summer harvest is sown again")
	var garden: Dictionary = {}
	for plot in s.crops.values():
		if plot.kind == "garden": garden = plot; break
	if not garden.is_empty():
		garden.state = "fallow"
		s.tick = SEASON * 2 + 14400
		check(Crops.tend(s, garden) == "stalled" and garden.state == "fallow", "Gardens are not sown in autumn")
		check(not Crops.needs_attention(garden, s), "A bare garden needs no work in autumn")
		s.tick = SEASON * 0 + 14400 * 8 * 4 + 14400
		check(Crops.tend(s, garden) == "sowed", "Gardens are sown in spring")

	# Farmers turn to other work for the winter, and back to farming in spring.
	var farmers: Array = []
	for npc in s.residents.values():
		if npc.occupation == "Farmer": farmers.append(int(npc.id))
	check(not farmers.is_empty(), "There are farmers")
	s.tick = SEASON * 3 + 7200
	Households.daily(sim)
	for town in s.settlements.values():
		check(Professions.count(s, int(town.id), "Farmer") == 0, "No farmers in %s in winter" % town.name)
		check(not Professions.demand(s, int(town.id)).has("Farmer"), "Nobody is wanted to farm in winter")
	for id in farmers:
		check(str(s.residents[str(id)].get("seasonal", "")) == "Farmer", "A farmer remembers the trade over the winter")
	s.tick = SEASON * 4 + 7200
	Households.daily(sim)
	for id in farmers:
		check(s.residents[str(id)].occupation == "Farmer", "Farmers go back to the fields in spring")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# Deterministic across a season change, and through a save.
	var a := Sim.new(91); a.start_game()
	var b := Sim.new(91); b.start_game()
	for world in [a, b]: world.state.tick = SEASON * 3 - 1500
	for i in range(3000):
		a.step(); b.step()
	check(a.state_hash() == b.state_hash(), "The same seed gives the same world across the first frost")
	var copy := Sim.new()
	copy.restore(a.snapshot())
	check(copy.state_hash() == a.state_hash(), "Save and load keep the same hash in winter")

	print("Seasons: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
