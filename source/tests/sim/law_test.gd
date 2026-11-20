extends SceneTree
## The sheriff's office and cell, arrests after a crime (chase, tackle, cuffs, escort, jail),
## being recognised later (gun drawn), surrendering, and running from a standoff.
const Reports = preload("res://sim/law/witness_reports.gd")
const World = preload("res://sim/world/world_db.gd")
const Sim = preload("res://sim/core/simulation.gd")
const Law = preload("res://sim/law/law.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const BodyHealth = preload("res://sim/combat/body_health.gd")
const Households = preload("res://sim/entities/households.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func setup() -> Array:
	var sim := Sim.new(); sim.start_game()
	var s: Dictionary = sim.state
	s.tick = 14400 + 5400   # mid-morning: everyone is up
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	for npc in s.residents.values():
		npc.sleeping = {}
		npc.goal = ""
		npc.path = []
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	s.entities[str(sheriff.id)].cell = [store[0], store[1] + 5]
	s.entities[str(s.player)].cell = [store[0] + 1, store[1] + 5]
	return [sim, s, sheriff]
func run_until(sim: RefCounted, limit: int, done: Callable) -> int:
	for t in range(limit):
		sim.step()
		if done.call(): return t
	return -1
func _initialize() -> void:
	var made := setup(); var sim: RefCounted = made[0]; var s: Dictionary = made[1]; var sheriff: Dictionary = made[2]
	# The office: a cell with a cot, and a bed for the sheriff.
	var office: Dictionary = Law.office_of(s, 1)
	check(not office.is_empty(), "Every town has a sheriff's office")
	var beds: Array = office.furniture.filter(func(f): return f.kind == "bed")
	check(beds.any(func(f): return f.get("for", "") == "prisoner") and beds.any(func(f): return f.get("for", "") == "sheriff"), "The office has a prisoner's cot and the sheriff's bed")
	check(Households.bed_info(s, sheriff).get("rect", []) == beds.filter(func(f): return f.get("for", "") == "sheriff")[0].rect, "The sheriff sleeps in his office bed")
	for town in ["2", "3"]: check(not Law.office_of(s, int(town)).is_empty(), "Office in town " + town)
	var bed_cells: Dictionary = {}
	for f in office.furniture: bed_cells[f.kind] = true
	check(bed_cells.has("booking_desk") and bed_cells.has("locker") and bed_cells.has("toilet"), "The office has a booking desk, a locker and a toilet")
	check(not Law.in_custody(s) and Law.stage(s) == "", "Free before any arrest")
	# What the player owns before the arrest: it must all come back at release.
	Inventory.produce(s, s.player, "food", 3)
	Inventory.produce(s, s.player, "bandage", 2)
	s.accounts[str(s.player)] = int(s.accounts.get(str(s.player), 0)) + 37
	s.money_initial += 37
	var owned_items: Dictionary = s.inventories[str(s.player)].items.duplicate()
	var owned_coins: int = int(s.accounts[str(s.player)])
	var owned_outfit: Dictionary = Outfits.worn(s, s.player).duplicate()
	# Shove the sheriff: he gives chase, tackles, cuffs and walks the player to the cell.
	sim.submit("player_strike", {"kind": "shove", "direction": [-1000, 0]})
	for t in range(10): sim.step()
	check(Law.wanted_hours(s, 1) >= Law.SENTENCE.assault_sheriff, "Shoving the sheriff is a crime (%d h)" % Law.wanted_hours(s, 1))
	check(str(sheriff.get("arrest", {}).get("phase", "")) == "pursue", "The sheriff comes after you")
	var cuffed := run_until(sim, 900, func(): return Law.restrained(s))
	check(cuffed >= 0, "He catches you and cuffs you")
	var escorted := run_until(sim, 400, func(): return str(sheriff.get("arrest", {}).get("phase", "")) == "escort")
	check(escorted >= 0 and str(sheriff.arrest.dest) == "desk", "Then walks you to the booking desk")
	var booked := run_until(sim, 1500, func(): return str(sheriff.get("arrest", {}).get("phase", "")) == "book")
	check(booked >= 0 and s.entities[str(s.player)].cell == Law.desk_stance(office), "You are standing at the booking desk")
	check(Law.stage(s) == "booking", "The jail reports a booking")
	var searched := run_until(sim, 200, func(): return s.player_control.has("property"))
	check(searched >= 0, "The search empties your pockets")
	check(s.inventories[str(s.player)].items.is_empty() and int(s.accounts[str(s.player)]) == 0, "Items and coins are in the office's keeping")
	check(Checks.validate(s).is_empty(), "Invariants hold during booking: " + str(Checks.validate(s)))
	var dressed := run_until(sim, 200, func(): return Outfits.worn(s, s.player).shirt == Outfits.PRISONER.shirt)
	check(dressed >= 0 and Outfits.worn(s, s.player).hat == "", "The prison uniform goes on")
	var mid := Sim.new(); mid.restore(sim.snapshot())
	check(mid.state_hash() == sim.state_hash(), "Booking survives a reload")
	var walking := run_until(sim, 400, func(): return str(sheriff.get("arrest", {}).get("phase", "")) == "escort")
	check(walking >= 0 and str(sheriff.arrest.dest) == "cell" and bool(office.get("cell_open", false)), "Then to the cell, whose door stands open")
	var copy := Sim.new(); copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "An arrest in progress survives a reload")
	var jailed := run_until(sim, 3000, func(): return Law.jailed(s))
	check(jailed >= 0, "You end up in jail")
	check(Law.inside_cell(s, s.entities[str(s.player)].cell), "Inside the cell")
	check(Law.wanted_hours(s, 1) == 0 and not Law.restrained(s), "The slate is wiped and the cuffs come off")
	check(not bool(office.get("cell_open", false)) and Law.stage(s) == "cell", "The cell door is shut")
	var hours: int = int(s.player_control.jail.hours)
	check(hours >= Law.SENTENCE.assault_sheriff, "The sentence fits the crime (%d h)" % hours)
	var here: Array = s.entities[str(s.player)].cell.duplicate()
	var r: Array = s.player_control.jail.rect
	s.entities[str(s.player)].cell = [r[0] + r[2] - 1, r[1] + 7]
	sim.submit("move_player", {"direction": [1, 0]}); sim.step()
	check(Law.inside_cell(s, s.entities[str(s.player)].cell), "The cell door holds")
	var held_hunger: int = int(s.player_needs.hunger)
	for t in range(1500): sim.step()
	check(int(s.player_needs.hunger) == held_hunger, "Hunger holds while jailed (meals provided)")
	s.player_control.jail.until = s.tick + 2
	for t in range(4): sim.step()
	check(not Law.jailed(s), "The sentence runs out")
	# Release: he comes into the cell and takes you by the arm, walks you to the desk for your
	# things, then to the door, and shoves you out into the street.
	var seen := {}
	var freed := -1
	for t in range(4000):
		sim.step()
		for npc in s.residents.values():
			var phase: String = str(npc.get("arrest", {}).get("phase", ""))
			if phase != "": seen[phase + ":" + str(npc.get("arrest", {}).get("dest", ""))] = true
		if not Law.in_custody(s) and not Law.restrained(s): freed = t; break
	check(freed >= 0, "The sheriff lets you out")
	check(seen.has("grab:"), "He comes into the cell to fetch you (%s)" % str(seen.keys()))
	check(seen.has("escort:release"), "He walks you to the desk for your things")
	check(seen.has("escort:door") and seen.has("show_out:door"), "Then he walks you to the door")
	check(World.inside_building(s, s.entities[str(s.player)].cell) == 0, "You end up outside in the street")
	check(s.inventories[str(s.player)].items == owned_items, "Your belongings are returned: " + str(s.inventories[str(s.player)].items))
	check(int(s.accounts[str(s.player)]) == owned_coins, "Your coins are returned")
	check(Outfits.worn(s, s.player) == owned_outfit, "Your own clothes are back on")
	check(not s.player_control.has("property") and not bool(office.get("cell_open", false)), "The locker is empty and the door is shut")
	check(Checks.validate(s).is_empty(), "Invariants hold: " + str(Checks.validate(s)))
	# Recognised later: the gun comes out; surrender and he walks up and arrests you.
	var made2 := setup(); var sim2: RefCounted = made2[0]; var s2: Dictionary = made2[1]; var sheriff2: Dictionary = made2[2]
	var away2: Array = s2.entities[str(sheriff2.id)].cell
	s2.entities[str(s2.player)].cell = [away2[0] + 40, away2[1]]
	Law.file(s2, 1, "theft", Reports.description(s2), false)   # a witness reported it (described your clothes): wanted, no chase yet
	check(Law.wanted_hours(s2, 1) > 0 and sheriff2.get("arrest", {}).is_empty(), "A reported crime makes you wanted")
	var cell2: Array = s2.entities[str(sheriff2.id)].cell
	s2.entities[str(s2.player)].cell = [cell2[0] + 6, cell2[1]]
	sim2.step()
	check(str(sheriff2.get("arrest", {}).get("phase", "")) == "standoff", "When he sees you he draws his gun")
	sim2.submit("surrender"); sim2.step()
	check(bool(s2.player_control.get("surrender", false)), "F raises your hands")
	sim2.step()
	check(str(sheriff2.arrest.phase) == "approach", "He walks up to you")
	var cuffed2 := run_until(sim2, 400, func(): return Law.restrained(s2))
	check(cuffed2 >= 0 and not Brawl.player_down(s2), "You are cuffed standing, without a tackle")
	# Run instead and he gives chase.
	var made3 := setup(); var sim3: RefCounted = made3[0]; var s3: Dictionary = made3[1]; var sheriff3: Dictionary = made3[2]
	var away3: Array = s3.entities[str(sheriff3.id)].cell
	s3.entities[str(s3.player)].cell = [away3[0] + 40, away3[1]]
	Law.file(s3, 1, "theft", Reports.description(s3), false)
	var cell3: Array = s3.entities[str(sheriff3.id)].cell
	s3.entities[str(s3.player)].cell = [cell3[0] + 6, cell3[1]]
	sim3.step()
	s3.entities[str(s3.player)].cell = [cell3[0] + 30, cell3[1]]
	sim3.step(); sim3.step()
	check(str(sheriff3.arrest.phase) == "pursue", "Running from a standoff makes him chase you")
	# Two sheriffs: both take part. One cuffs and escorts; the other helps and walks beside him.
	var made4 := setup(); var sim4: RefCounted = made4[0]; var s4: Dictionary = made4[1]; var first4: Dictionary = made4[2]
	var partner: Dictionary = {}
	for npc in Law.sheriffs(s4, 1): if npc.id != first4.id: partner = npc
	check(not partner.is_empty(), "A town has more than one sheriff")
	var near4: Array = s4.entities[str(first4.id)].cell
	s4.entities[str(partner.id)].cell = [near4[0] - 2, near4[1] + 1]
	partner.sleeping = {}; partner.goal = ""; partner.path = []
	Law.crime(s4, 1, "assault_sheriff", first4.id)
	check(not first4.get("arrest", {}).is_empty() and not partner.get("arrest", {}).is_empty(), "Both sheriffs go after the player, not just one")
	var partner_helped := false
	var lead_escorted := false
	var bled_before := false
	s4.player_health.parts.left_forearm.damage = 40
	s4.player_health.parts.left_forearm.bleeding = true
	s4.player_health.parts.left_forearm.wound = "cut"
	for t in range(1500):
		sim4.step()
		if str(partner.get("arrest", {}).get("phase", "")) == "assist": partner_helped = true
		if str(first4.get("arrest", {}).get("phase", "")) == "escort": lead_escorted = true
		if str(first4.get("arrest", {}).get("phase", "")) == "escort" and not bled_before:
			bled_before = true
			# Someone tries to shove the cuffed player to the ground: it does nothing.
			Brawl.knockdown(s4, s4.player_control, s4.entities[str(s4.player)].cell, "fall", [1, 0])
			check(s4.player_control.get("knock", {}).is_empty(), "A prisoner cannot be knocked down")
		if Law.jailed(s4): break
	check(lead_escorted and partner_helped, "One sheriff escorts while the other helps (lead %s, partner %s)" % [str(lead_escorted), str(partner_helped)])
	check(Law.jailed(s4), "The prisoner ends up in the cell")
	check(not s4.player_health.parts.left_forearm.bleeding and s4.player_health.parts.left_forearm.bandage == "clean", "The officers dressed the wound before locking the cell")
	check(Checks.validate(s4).is_empty(), "Invariants hold: " + str(Checks.validate(s4)))
	for t in range(60): sim4.step()
	check(str(partner.get("arrest", {}).get("phase", "")) == "" , "The helper goes back to his duties once the prisoner is locked up")
	# Nearly dead on arrest: they bring the prisoner round.
	var made5 := setup(); var sim5: RefCounted = made5[0]; var s5: Dictionary = made5[1]; var first5: Dictionary = made5[2]
	for name in ["head", "upper_torso", "lower_torso"]:
		s5.player_health.parts[name].damage = 50; s5.player_health.parts[name].bleeding = true; s5.player_health.parts[name].wound = "cut"
	check(BodyHealth.overall(s5) < 25, "The prisoner starts nearly dead (health %d)" % BodyHealth.overall(s5))
	Law.crime(s5, 1, "assault_sheriff", first5.id)
	for t in range(1500):
		sim5.step()
		if Law.jailed(s5): break
	check(Law.jailed(s5) and not bool(s5.player_control.get("dead", false)), "Arrested while badly hurt, the prisoner does not die")
	for t in range(3000): sim5.step()
	check(not bool(s5.player_control.get("dead", false)) and BodyHealth.overall(s5) >= 20, "...and is still alive hours later (health %d)" % BodyHealth.overall(s5))
	print("Law: %s" % ("PASS" if failures == 0 else "FAIL")); quit(failures)
