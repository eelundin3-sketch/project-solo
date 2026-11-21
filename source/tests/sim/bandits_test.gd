extends SceneTree
## The bandit camp: far from the towns, three bandits; they demand your valuables; hand them
## over and you are robbed (and maybe tied up until they sleep); refuse and they fight; beat them
## and their loot is yours and the towns hear of it. Money and goods are conserved throughout.
const Sim = preload("res://sim/core/simulation.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Reputation = preload("res://sim/factions/reputation.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
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

func near_camp(sim: RefCounted, gap: int) -> void:
	var s: Dictionary = sim.state
	var camp: Array = s.bandits.cell
	for dx in range(gap, gap + 6):
		var c: Array = [camp[0] + dx, camp[1] + 3]
		if load("res://sim/world/world_db.gd").walkable(s, c): s.entities[str(s.player)].cell = c; return

func step_until(sim: RefCounted, limit: int, done: Callable) -> int:
	for i in range(limit):
		sim.step()
		if done.call(): return i
	return -1

func _initialize() -> void:
	# The camp: far from every town, off the roads, three bandits around it.
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	check(s.has("bandits"), "There is a bandit camp")
	var camp: Array = s.bandits.cell
	var nearest := 1 << 30
	for town in s.settlements.values():
		var store: Array = s.entities[str(town.warehouse)].cell
		nearest = mini(nearest, maxi(absi(store[0] - camp[0]), absi(store[1] - camp[1])))
	check(nearest >= 80, "The camp is far out in the wilds (%d cells from the nearest town)" % nearest)
	check(not TownLayout.on_road(s, camp), "The camp is off the roads")
	check(s.bandits.members.size() == 3, "Three bandits")
	for id in s.bandits.members:
		check(s.residents[str(id)].occupation == "Bandit" and int(s.residents[str(id)].settlement) == 0, "A bandit belongs to no town")
	check(Checks.validate(s).is_empty(), "Invariants hold with the camp: %s" % str(Checks.validate(s)))

	# Walk up by day: the leader demands your valuables; hand them over.
	s.tick = 14400 + 11 * 600
	s.accounts[str(s.player)] = int(s.accounts.get(str(s.player), 0))
	var coins: int = int(s.accounts[str(s.player)])
	var total: int = money(s)
	near_camp(sim, 6)
	check(step_until(sim, 200, func(): return str(s.bandits.phase) == "demand") >= 0, "They notice you and demand your valuables")
	sim.submit("surrender"); sim.step(); sim.step(); sim.step()
	check(int(s.accounts[str(s.player)]) == 0, "Your coins are taken")
	check(int(s.accounts[str(s.bandits.leader)]) >= coins, "The leader has your coins")
	check(Inventory.amount(s, int(s.bandits.stash), "rifle") >= 1 and Inventory.amount(s, int(s.player), "rifle") == 0, "Your rifle is in their loot pile")
	check(money(s) == total, "Money is conserved by the robbery")
	if Bandits.captive(s):
		# Tied up: you slip free at night once they are all asleep.
		sim.submit("move_player", {"direction": [1, 0]}); sim.step()
		check(Bandits.captive(s), "Tied up, you cannot walk away")
		var freed := step_until(sim, 14400 + 2000, func(): return not Bandits.captive(s))
		check(freed >= 0, "You slip free in the end")
		var minute: int = (int(s.tick) / 10) % 1440
		check(minute >= 1260 or minute < 420 or freed >= 14000, "You slip free at night (%02d:%02d) or after a day" % [minute / 60, minute % 60])
	else:
		check(str(s.bandits.phase) == "idle", "Robbed and let go, they go back to the fire")

	# Refuse: walk away while they wait, and they open fire until you surrender.
	var sim2 := Sim.new()
	sim2.start_game()
	var s2: Dictionary = sim2.state
	s2.tick = 14400 + 11 * 600
	near_camp(sim2, 6)
	step_until(sim2, 200, func(): return str(s2.bandits.phase) == "demand")
	var fought := step_until(sim2, 400, func(): return str(s2.bandits.phase) == "fight")
	check(fought >= 0, "Ignore the demand and they fight")
	var shots := step_until(sim2, 400, func():
		for id in s2.bandits.members:
			if int(s2.residents[str(id)].get("next_shot", 0)) > 0: return true
		return false)
	check(shots >= 0, "They shoot at you")
	sim2.submit("surrender"); sim2.step(); sim2.step(); sim2.step()
	check(Bandits.captive(s2) or bool(s2.player_control.get("dead", false)), "Surrender in a fight and they tie you up")
	check(Checks.validate(s2).is_empty(), "Invariants hold after the fight: %s" % str(Checks.validate(s2)))

	# Beat them: the camp is cleared, no crime is recorded, the towns think better of you,
	# and the loot pile is yours.
	var sim3 := Sim.new()
	sim3.start_game()
	var s3: Dictionary = sim3.state
	for id in s3.bandits.members: Brawl.kill(sim3, s3.residents[str(id)], "shot")
	for i in range(4): sim3.step()
	check(bool(s3.bandits.cleared), "With every bandit down, the camp is cleared")
	check(s3.get("law", {}).get("wanted", {}).is_empty(), "Killing outlaws is no crime")
	Reputation.update(s3)
	for town in s3.settlements.values():
		check(Reputation.value(s3, int(town.id)) > 0, "%s hears of it and thinks better of you" % town.name)
	var stash: Dictionary = s3.entities[str(s3.bandits.stash)]
	s3.entities[str(s3.player)].cell = [stash.cell[0] + 1, stash.cell[1]]
	var food_before: int = Inventory.amount(s3, int(s3.player), "food")
	sim3.submit("take_item", {"target": int(stash.id), "item": "food"}); sim3.step()
	check(Inventory.amount(s3, int(s3.player), "food") > food_before, "You can take their loot")
	check(s3.get("law", {}).get("wanted", {}).is_empty(), "Taking it is no theft")

	# Saves: the same hash after a reload; an old save gets the camp.
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	var old: Dictionary = sim3.snapshot()
	old.erase("bandits")
	var loaded := Sim.new()
	loaded.restore(old)
	check(loaded.state.has("bandits"), "An old save gets a bandit camp")
	print("Bandits: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
