extends SceneTree
## Price trends (milestone 5, E1): yesterday's quote gives the arrow, prices seen in a town are
## remembered, and a better price known elsewhere (3 coins or more) is offered as a hint.
const Sim = preload("res://sim/core/simulation.gd")
const Market = preload("res://sim/economy/market.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var store: int = int(s.markets["1"].store)
	var other: int = int(s.settlements["2"].warehouse)

	check(Market.trend(s, 1, "food") == 0, "No arrow before the first daily snapshot")
	Market.snapshot_trend(s)
	check(Market.trend(s, 1, "food") == 0, "Unchanged since yesterday: no arrow")
	# Food leaves the store (a move, so goods are conserved): the price goes up.
	var food: int = Inventory.amount(s, store, "food")
	var moved: int = mini(food, maxi(40, food / 2))
	var sent: Dictionary = Inventory.transfer(s, store, other, "food", moved)
	check(sent.get("ok", false), "Moved food out of the store: %s" % str(sent))
	check(Market.trend(s, 1, "food") > 0, "Less food in store: the price is rising")
	Inventory.transfer(s, other, store, "food", moved)
	Market.snapshot_trend(s)
	var log_stock: int = Inventory.amount(s, other, "log")
	if log_stock > 0:
		Inventory.transfer(s, other, store, "log", log_stock)
		check(Market.trend(s, 1, "log") < 0, "More logs in store: the price is falling")
		Inventory.transfer(s, store, other, "log", log_stock)

	# Visiting a town remembers its prices.
	var reed_store: Array = s.entities[str(s.settlements["2"].warehouse)].cell
	s.entities[str(s.player)].cell = [reed_store[0], reed_store[1] + 3]
	Market.note_prices(s)
	var known: Dictionary = s.player_status.get("known_prices", {})
	check(known.has("2"), "Prices in Reedbank are remembered after a visit")
	check(int(known["2"].prices.food.buy) == Market.quote(s, 2, "food", true), "The remembered price is what the stall asks")
	check(not known.has("1"), "A town not visited is not known")

	# A hint only when another town is 3 coins or more better.
	known["2"].prices.food.buy = 4
	check(Market.better_elsewhere(s, 1, "food", true, 7).get("price", 0) == 4, "Food 3 coins cheaper in Reedbank is shown")
	check(Market.better_elsewhere(s, 1, "food", true, 6).is_empty(), "2 coins cheaper is not worth a hint")
	known["2"].prices.plank.sell = 15
	check(Market.better_elsewhere(s, 1, "plank", false, 10).get("name", "") == s.settlements["2"].name, "Planks sell better in Reedbank")
	check(not Market.better_elsewhere(s, 1, "food", true, 7).stale, "A fresh price is not greyed")
	s.tick += 14400 * 4
	check(Market.better_elsewhere(s, 1, "food", true, 7).stale, "A price older than 3 days is greyed")

	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	print("Price trends: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
