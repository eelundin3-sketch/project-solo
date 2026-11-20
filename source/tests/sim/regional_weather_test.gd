extends SceneTree
## Weather per town, drought and crops, trades by climate, and farming families moving away
## (milestone 5, C5).
const Sim = preload("res://sim/core/simulation.gd")
const Weather = preload("res://sim/world/weather.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Professions = preload("res://sim/settlement/professions.gd")
const Society = preload("res://sim/factions/society.gd")
const FamilyEconomy = preload("res://sim/entities/family_economy.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func town_named(s: Dictionary, name: String) -> int:
	for town in s.settlements.values():
		if town.name == name: return int(town.id)
	return 0

func field_of(s: Dictionary, town: int) -> Dictionary:
	for plot in s.crops.values():
		if plot.kind == "field" and int(plot.settlement) == town: return plot
	return {}

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var reed := town_named(s, "Reedbank")
	var dust := town_named(s, "Dustvale")
	check(reed != 0 and dust != 0, "Reedbank and Dustvale exist")
	check(s.weather.has("regions") and s.weather.regions.size() == s.settlements.size(), "Each town has its own weather")

	# Same seed, same weather in every town; and after a reload too.
	var twin := Sim.new()
	twin.start_game()
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	var wet := {reed: 0, dust: 0}
	var start: int = s.tick
	for block in range(1, 241):
		for world in [sim, twin, copy]:
			world.state.tick = start - start % Weather.BLOCK_TICKS + block * Weather.BLOCK_TICKS
			Weather.update(world)
		for town in wet:
			if Weather.wet(str(Weather.of_town(s, town).kind)): wet[town] += 1
	check(s.weather.regions == twin.state.weather.regions, "The same seed gives the same weather in each town")
	check(s.weather.regions == copy.state.weather.regions, "A reloaded game rolls the same weather")
	check(wet[reed] > wet[dust], "Reedbank is wetter than Dustvale (%d vs %d wet blocks of 240)" % [wet[reed], wet[dust]])
	var here: Dictionary = Weather.of_town(s, int(s.weather.region))
	check(s.weather.kind == here.kind, "The top-level weather is the player's town's weather")

	# Drought: ten dry days stall Dustvale's field and cut its harvest; Reedbank's is untouched.
	var dust_field: Dictionary = field_of(s, dust)
	var reed_field: Dictionary = field_of(s, reed)
	check(not dust_field.is_empty() and not reed_field.is_empty(), "Both towns have a field")
	for plot in [dust_field, reed_field]:
		plot.grown = 1000
		plot.yield_loss = 0
		plot.state = "growing"
	var day0: int = (s.tick / Weather.DAY + 1) * Weather.DAY
	for day in range(6):
		Weather.of_town(s, dust).dry_days = 9 + day
		Weather.of_town(s, reed).dry_days = 0
		s.tick = day0 + day * Weather.DAY
		Crops.update(s)
	check(Crops.growth_step(s, dust_field) == 0, "After 9 dry days the crop stops growing")
	check(int(dust_field.grown) == 1000, "A stalled crop does not grow")
	check(int(reed_field.grown) > 1000, "Reedbank's crop keeps growing")
	check(Crops.expected_yield(dust_field) < Crops.cells(dust_field) * Crops.YIELD_PER_CELL, "Drought lowers Dustvale's expected harvest")
	check(Crops.expected_yield(reed_field) == Crops.cells(reed_field) * Crops.YIELD_PER_CELL, "Reedbank's harvest is unchanged")
	check(Crops.expected_yield(dust_field) >= Crops.cells(dust_field), "Every cell still gives at least 1")
	Weather.of_town(s, dust).dry_days = 6
	var held: int = s.tick
	s.tick = Weather.DAY + 100   # spring, so the season does not change the pace
	check(Crops.growth_step(s, dust_field) == 5, "From 5 dry days crops grow at half speed")
	s.tick = held

	# Trades follow the climate.
	check(Professions.farm_share(s, dust) < Professions.farm_share(s, reed), "Dustvale farms a smaller share than Reedbank")
	check(int(Professions.demand(s, dust).get("Farmer", 0)) <= int(Professions.demand(s, reed).get("Farmer", 0)), "Dustvale wants no more farmers than Reedbank")

	# A failed harvest makes a farming family with an empty pantry move away, together, with its purse.
	var mover := ""
	var keys: Array = s.households.keys()
	keys.sort()
	for key in keys:
		if int(s.households[key].settlement) == dust and not str(key).begins_with("player"): mover = key; break
	check(mover != "", "Dustvale has a family to move")
	var head: Dictionary = s.residents[str(s.households[mover].members[0])]
	head.occupation = "Farmer"
	# A second farmer elsewhere in town, so this is not the last one.
	for npc in s.residents.values():
		if int(npc.settlement) == dust and npc.id not in s.households[mover].members and npc.occupation != "Child" and npc.occupation != "Sheriff":
			npc.occupation = "Farmer"; break
	var home: int = int(s.households[mover].home)
	if s.inventories.has(str(home)):
		var food: int = Inventory.amount(s, home, "food")
		if food > 0: Inventory.transfer(s, home, int(s.settlements[str(dust)].warehouse), "food", food)
	var purse_before: int = FamilyEconomy.purse(s, mover)
	var members: Array = s.households[mover].members.duplicate()
	var total_before: int = 0
	for value in s.accounts.values(): total_before += int(value)
	var moved := false
	for day in range(40):
		s.tick = day0 + (6 + day) * Weather.DAY
		dust_field.last_harvest = {"tick": s.tick, "percent": 30}
		Society.drought_moves(sim)
		if int(s.households[mover].settlement) != dust: moved = true; break
	check(moved, "A drought makes a farming family move away")
	if moved:
		var destination: int = int(s.households[mover].settlement)
		for i in range(605): sim.step()
		s = sim.state
		for id in members:
			check(int(s.residents[str(id)].settlement) == destination, "Every member of the family moves")
			check(str(s.residents[str(id)].household) == mover, "They stay one household")
		check(FamilyEconomy.purse(s, mover) >= 0 and s.accounts.has(FamilyEconomy.purse_key(mover)), "The family keeps its purse")
	var total_after: int = 0
	for value in s.accounts.values(): total_after += int(value)
	check(total_after == total_before, "Money is conserved (%d -> %d)" % [total_before, total_after])
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# The purse of a migrant's household that breaks up goes to a town, not nowhere.
	s.accounts["household:migrant:%d" % int(head.id)] = 7
	var sum_before: int = 0
	for value in s.accounts.values(): sum_before += int(value)
	FamilyEconomy.ensure(s)
	var sum_after: int = 0
	for value in s.accounts.values(): sum_after += int(value)
	check(sum_after == sum_before, "A broken-up migrant household's coins go to a town")

	# An old save with one weather for the whole map loads with a record for each town.
	var old: Dictionary = sim.snapshot()
	old.weather = {"kind": "rain", "previous": "clear", "since": 0, "wind": 30, "snow": 0}
	var loaded := Sim.new()
	loaded.restore(old)
	check(loaded.state.weather.regions.size() == loaded.state.settlements.size(), "An old save gets weather for each town")
	check(Weather.of_town(loaded.state, dust).kind == "rain", "Each town starts with the weather the save had")
	var again := Sim.new()
	again.restore(loaded.snapshot())
	check(again.state_hash() == loaded.state_hash(), "Save and load keep the same hash")

	print("Regional weather: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
