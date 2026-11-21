extends SceneTree
## Dustvale, the capital: five sheriffs there and three in the other towns; the governor's town
## house (he works at his desk by day and sleeps there); the saloon (the barkeep tends the bar from
## 14:00, townsfolk drop in for a drink in the evening, and the traveller can buy one).
const Sim = preload("res://sim/core/simulation.gd")
const Capital = preload("res://sim/settlement/capital.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Households = preload("res://sim/entities/households.gd")
const World = preload("res://sim/world/world_db.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func money(s: Dictionary) -> int:
	var total := 0
	for value in s.accounts.values(): total += int(value)
	return total

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var dust: Dictionary = {}
	for town in s.settlements.values():
		if town.name == "Dustvale": dust = town
	check(bool(dust.get("capital", false)), "Dustvale is the capital")
	check(s.entities.has(str(dust.get("town_hall", 0))) and s.entities[str(dust.town_hall)].kind == "town_hall", "Dustvale has a town house")
	check(s.entities.has(str(dust.get("saloon", 0))) and s.entities[str(dust.saloon)].kind == "saloon", "Dustvale has a saloon")
	var hall: Dictionary = s.entities[str(dust.town_hall)]
	var saloon: Dictionary = s.entities[str(dust.saloon)]
	check(not World.building_rect(hall).intersects(World.building_rect(saloon)), "The two buildings do not overlap")
	var governor: Dictionary = s.residents[str(dust.governor)]
	var barkeep: Dictionary = s.residents[str(dust.barkeep)]
	check(governor.occupation == "Governor" and int(Households.household_of(s, governor).home) == int(dust.town_hall), "The governor lives in the town house")
	check(barkeep.occupation == "Barkeep" and int(Households.household_of(s, barkeep).home) == int(dust.saloon), "The barkeep lives at the saloon")
	for town in s.settlements.values():
		var want: int = 5 if town.name == "Dustvale" else 3
		check(Sheriff.roster(s, int(town.id)).size() == want, "%s keeps %d sheriffs (has %d)" % [town.name, want, Sheriff.roster(s, int(town.id)).size()])
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# A day in the capital.
	var at_desk := false
	var bar_tended := false
	var drinkers := 0
	var governor_in_bed := false
	var chairs: Array = Capital.seats(s, int(dust.saloon)).map(func(c): return c.cell)
	while s.tick < 14400 * 2 + 600:   # to 01:00 on day 3
		sim.step()
		var m: int = (int(s.tick) / 10) % 1440
		if m == 11 * 60 and governor.get("sitting", {}).get("chair", []) == Capital.seats(s, int(dust.town_hall))[0].cell: at_desk = true
		if m == 15 * 60 + 30 and Capital.serving(s, barkeep): bar_tended = true
		if m >= 18 * 60 + 30 and m < 21 * 60 and s.tick % 60 == 0:
			var now := 0
			for npc in s.residents.values():
				if npc.get("sitting", {}).get("chair", []) in chairs: now += 1
			drinkers = maxi(drinkers, now)
		if m == 23 * 60 + 30 and not governor.get("sleeping", {}).is_empty(): governor_in_bed = true
	check(at_desk, "The governor works at his desk in the morning")
	check(bar_tended, "The barkeep tends the bar in the afternoon")
	check(drinkers >= 1, "Townsfolk drop in for a drink in the evening (up to %d at once)" % drinkers)
	check(governor_in_bed, "The governor is asleep at night")

	# The traveller buys a drink.
	s.tick = 14400 * 3 + 16 * 600
	var spot: Array = Capital.counter_spot(s, dust)
	s.entities[str(barkeep.id)].cell = spot.duplicate()
	barkeep.sleeping = {}
	s.entities[str(s.player)].cell = [spot[0], spot[1] + 2]
	s.accounts[str(s.player)] = maxi(10, int(s.accounts.get(str(s.player), 0)))
	s.player_needs.thirst = 70
	var total: int = money(s)
	var coins: int = int(s.accounts[str(s.player)])
	var said: String = Capital.buy_drink(s, barkeep)
	check(int(s.accounts[str(s.player)]) == coins - Capital.DRINK_PRICE, "A drink costs %d coins (%s)" % [Capital.DRINK_PRICE, said])
	check(int(s.player_needs.thirst) < 70, "A drink quenches your thirst")
	check(money(s) == total, "Money is conserved")
	s.tick = 14400 * 3 + 9 * 600
	check(Capital.buy_drink(s, barkeep).begins_with("The bar isn't open"), "No drinks in the morning")

	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	print("Dustvale capital: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
