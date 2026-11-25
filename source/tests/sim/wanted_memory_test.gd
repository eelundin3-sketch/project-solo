extends SceneTree
## Wanted, and remembered. Where you're wanted and known (face, or the clothes witnesses described),
## townsfolk mutter about you and one may slip off to tell the sheriff, who comes looking; shops
## refuse you or charge double; new clothes get you past people who only knew your clothes. At the
## office you can pay a fine for small crimes (money to the town) or turn yourself in (half the
## time). Once the slate is clean, people still remember what you did. Save and load keep the hash.
const Sim = preload("res://sim/core/simulation.gd")
const Law = preload("res://sim/law/law.gd")
const Notoriety = preload("res://sim/law/notoriety.gd")
const Stalls = preload("res://sim/economy/stall_service.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func money(s: Dictionary) -> int:
	var total := 0
	for key in s.accounts: total += int(s.accounts[key])
	return total

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var food_price: int = Stalls.price(s, 1, "food", true, 0)
	# Wanted in Alder Hollow for theft, known by the clothes a witness described.
	Law.file(s, 1, "theft", Outfits.worn(s, int(s.player)), false)
	s.entities[str(s.player)].cell = [store[0], store[1] + 3]
	check(Notoriety.town_here(s) == 1 and Notoriety.known(s, 1), "In town, in the described clothes: known")
	check(Stalls.price(s, 1, "food", true, 0) >= food_price * 2 - 1, "A wanted man pays double")
	var refused := false
	for npc in s.residents.values():
		if int(npc.settlement) == 1 and npc.occupation not in ["Child", "Sheriff", "Trader", "Bandit"] and Brawl.temperament(npc) != "timid":
			refused = Stalls.unavailable(s, npc).contains("don't serve"); break
	check(refused, "Most shopkeepers won't serve you")
	# Townsfolk mutter; one slips off to the sheriff, who comes looking. (The sheriffs start at the
	# far edge of town, out of sight.)
	var World = load("res://sim/world/world_db.gd")
	var k := 0
	for sheriff in Law.sheriffs(s, 1):
		for dx in range(60, 90):
			var c: Array = [store[0] + dx, store[1] - 20 + k]
			if World.walkable(s, c): s.entities[str(sheriff.id)].cell = c; break
		sheriff.goal = ""
		sheriff.path = []
		k += 2
	var muttered := false
	var sighting := false
	var searching := false
	for i in range(1500):
		sim.step()
		for line in s.get("speech", []):
			if str(line.text).begins_with("That's the one") or str(line.text).contains("sheriff's after") or str(line.text).contains("Keep away"): muttered = true
		for npc in s.residents.values():
			if str(npc.get("reporting", {}).get("kind", "")) == "sighting": sighting = true
			if not npc.get("search", {}).is_empty() or str(npc.get("arrest", {}).get("phase", "")) == "standoff": searching = true
		# keep the player among the townsfolk, out of the sheriffs' sight to start with
		s.entities[str(s.player)].cell = [store[0], store[1] + 3]
		if searching: break
	check(muttered, "Townsfolk who know you mutter about it")
	check(sighting, "One slips off to tell the sheriff")
	check(searching, "...and a sheriff comes for you")
	# New clothes: people who only knew your clothes don't know you.
	var other: Dictionary = Outfits.worn(s, int(s.player)).duplicate()
	other.hat = "hat:2"; other.vest = "vest:2"; other.shirt = "shirt:2"; other.pants = "pants:1"
	Outfits.dress(s, int(s.player), other)
	check(not Notoriety.known(s, 1), "In different clothes, they don't know you")
	check(Stalls.price(s, 1, "food", true, 0) < food_price * 2 - 1, "...and you pay the usual price")
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load while wanted keep the same hash")

	# A fine for a small crime: the money goes to the town, the slate is wiped, memories stay.
	var victim: Dictionary = {}
	for npc in s.residents.values():
		if int(npc.settlement) == 2 and npc.occupation not in ["Child", "Sheriff", "Bandit"]: victim = npc; break
	Law.remember_crime(s, 2, "assault", int(victim.id))
	Law.file(s, 2, "assault", {}, true)
	var sheriff2: Dictionary = Law.sheriffs(s, 2)[0]
	var due: int = Notoriety.fine(s, 2)
	var treasury2: String = str(s.settlements["2"].warehouse)
	var topup: int = due + 5 - int(s.accounts[str(s.player)])
	s.accounts[str(s.player)] = int(s.accounts[str(s.player)]) + topup   # moved from the town's purse, so money is conserved
	s.accounts[treasury2] = int(s.accounts[treasury2]) - topup
	var before: int = money(s)
	var answer: String = Notoriety.pay_fine(sim, sheriff2)
	check(due > 0 and Law.wanted_hours(s, 2) == 0, "Paying the fine settles a small crime (%s)" % answer)
	check(money(s) == before and int(s.accounts[str(s.player)]) == 5, "The fine goes to the town; money is conserved")
	check(load("res://sim/factions/society.gd").opinion(s, int(victim.id), int(s.player)) < 0, "The one you hit still remembers")
	Law.file(s, 2, "theft", {}, true)
	check(Notoriety.fine(s, 2) == 0, "Theft is too serious for a fine")

	# Turning yourself in halves the time and he takes you in.
	Law.file(s, 3, "theft", {}, true)
	var hours: int = Law.wanted_hours(s, 3)
	var sheriff3: Dictionary = Law.sheriffs(s, 3)[0]
	Notoriety.turn_in(sim, sheriff3)
	check(Law.wanted_hours(s, 3) == maxi(1, (hours + 1) / 2), "Turning yourself in halves the time (%d -> %d)" % [hours, Law.wanted_hours(s, 3)])
	check(str(sheriff3.get("arrest", {}).get("phase", "")) == "standoff" and bool(s.player_control.surrender), "...and the sheriff takes you in")
	var options: Array = load("res://sim/player/talk.gd").wanted_options(s, Law.sheriffs(s, 1)[1])
	check(options.size() == 2, "A sheriff where you're wanted offers to take you in or settle a fine")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))
	print("Wanted and remembered: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
