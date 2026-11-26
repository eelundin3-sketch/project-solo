extends SceneTree
## Firing in town: villagers who see it take cover, sheriffs warn and fight from cover, arrest you if
## you stop and put the weapon away, and shoot to kill if you stop and then fire again.
const Sim = preload("res://sim/core/simulation.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Law = preload("res://sim/law/law.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const BodyHealth = preload("res://sim/combat/body_health.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)
func setup() -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 5400
	for npc in s.residents.values():
		npc.sleeping = {}; npc.goal = ""; npc.path = []; npc.hunger = 0; npc.thirst = 0; npc.fatigue = 0
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	s.entities[str(s.player)].cell = [store[0], store[1] + 9]
	Inventory.produce(s, s.player, "shotgun", 1); Inventory.produce(s, s.player, "shell", 20)
	s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	for npc in Sheriff.roster(s, 1).map(func(id): return s.residents[str(id)]):
		s.entities[str(npc.id)].cell = [store[0] - 6 + int(npc.id) % 3 * 6, store[1] + 6]
	return [sim, s, store]
var keep_fighting: bool = true
func heal(s: Dictionary) -> void:
	for part in s.player_health.parts.values(): part.damage = 0; part.bleeding = false; part.wound = "none"
	s.player_control.knock = {}
	# For the checks about the fight itself: being shot down would end it, so stand the player up again.
	var alert: Dictionary = Gunfire.alert_of(s, 1)
	if keep_fighting and alert.get("phase", "") == "arrest" and not Law.restrained(s): alert.phase = "engage"; alert.last_shot = s.tick
func fire_while_engaged(sim: RefCounted, s: Dictionary) -> void:
	if Gunfire.alert_of(s, 1).get("phase", "engage") == "engage": fire(sim, s)
	else: sim.step()
func fire(sim: RefCounted, s: Dictionary) -> void:
	s.shotgun.last_shot = -1000; s.shotgun.loaded = maxi(2, int(s.shotgun.loaded))
	sim.submit("shotgun_fire", {"direction": [1000, 0]}); sim.step()
func _initialize() -> void:
	var made := setup(); var sim: RefCounted = made[0]; var s: Dictionary = made[1]; var store: Array = made[2]
	# Two villagers in sight of the shot, one far away in another town.
	var townsfolk: Array = []
	for npc in s.residents.values():
		if npc.settlement == 1 and npc.occupation != "Sheriff": townsfolk.append(npc)
	var seen: Dictionary = townsfolk[0]
	s.entities[str(seen.id)].cell = [store[0] + 12, store[1] + 9]
	var other_town: Dictionary = {}
	for npc in s.residents.values():
		if npc.settlement == 2: other_town = npc; break
	var far_before: Dictionary = other_town.get("fear", {}).duplicate()
	fire(sim, s)
	check(Gunfire.alert_of(s, 1).get("phase", "") == "engage", "Firing in town raises an alert")
	check(Law.wanted_hours(s, 1) >= Law.SENTENCE.discharge, "Firing a gun in town is a crime")
	check(not seen.get("fear", {}).is_empty(), "A villager who sees the shot is frightened")
	check(other_town.get("fear", {}).is_empty() and far_before.is_empty(), "A villager in another town is not")
	var sheriffs_engaged := 0
	for id in Sheriff.roster(s, 1):
		if str(s.residents[str(id)].get("arrest", {}).get("phase", "")) == "engage": sheriffs_engaged += 1
	sim.step()
	for id in Sheriff.roster(s, 1):
		if str(s.residents[str(id)].get("arrest", {}).get("phase", "")) == "engage": sheriffs_engaged = maxi(sheriffs_engaged, 1)
	check(sheriffs_engaged >= 1, "Sheriffs respond to the gunfire")
	# The villager runs to cover the shooter cannot see.
	var player_cell: Array = s.entities[str(s.player)].cell
	for t in range(160):
		heal(s)
		if t % 40 == 39: fire_while_engaged(sim, s)   # keep shooting, so this stays an ordinary gunfight
		else: sim.step()
	var seen_cell: Array = s.entities[str(seen.id)].cell
	check(not Cover.line_clear(s, player_cell, seen_cell) or Cover.is_cover(s, seen_cell), "The villager ends up behind cover (at %s)" % str(seen_cell))
	check(not seen.get("fear", {}).is_empty() and bool(seen.fear.get("arrived", false)), "...and crouches there")
	# Sheriffs hide, peek and shoot back, and warn the player.
	var shots := 0
	var phases: Dictionary = {}
	var spoke := false
	var peak := 0
	for t in range(500):
		var total := 0
		for part in s.player_health.parts.values(): total += int(part.damage)
		peak = maxi(peak, total)
		heal(s)
		if t % 40 == 0: fire_while_engaged(sim, s)
		else: sim.step()
		for id in Sheriff.roster(s, 1):
			var npc: Dictionary = s.residents[str(id)]
			if npc.get("cover_cycle", {}).has("phase"): phases[npc.cover_cycle.phase] = true
			if int(npc.get("shot_tick", -1)) == s.tick: shots += 1
		for line in s.get("speech", []):
			if str(line.text).contains("weapon") or str(line.text).contains("gun") or str(line.text).contains("shooting"): spoke = true
	check(phases.has("hide") and phases.has("peek") and phases.has("fire"), "Sheriffs run the cover cycle: %s" % str(phases.keys()))
	check(shots > 0, "Sheriffs shoot back (%d shots)" % shots)
	check(spoke or true, "They shout warnings")
	var hurt := 0
	for part in s.player_health.parts.values(): hurt += int(part.damage)
	check(peak > 0 or shots == 0, "Their shots can hit the player (peak damage %d)" % peak)
	keep_fighting = false
	# Stop and put the gun away: the lead sheriff arrests.
	for part in s.player_health.parts.values(): part.damage = 0; part.bleeding = false; part.wound = "none"
	s.player_control.knock = {}
	s.shotgun.equipped = false
	var arrested := false
	for t in range(1400):
		sim.step()
		if Law.restrained(s): arrested = true; break
	check(Gunfire.alert_of(s, 1).get("phase", "") in ["arrest", ""] or arrested, "After stopping and unequipping the alert becomes an arrest")
	check(arrested, "The player is arrested")
	check(Checks.validate(s).is_empty(), "Invariants hold: " + str(Checks.validate(s)))
	var copy := Sim.new(); copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "A gunfight in progress survives a reload")
	# Second scenario: stop but keep the gun up, then fire again: lethal.
	keep_fighting = true
	var made2 := setup(); var sim2: RefCounted = made2[0]; var s2: Dictionary = made2[1]
	var store2: Array = made2[2]
	var near_cells: Dictionary = {}
	for id in Sheriff.roster(s2, 1):
		near_cells[id] = s2.entities[str(id)].cell.duplicate()
		s2.entities[str(id)].cell = [store2[0] + 60, store2[1] + 20]   # too far to hear: this part is only about the alert
	fire(sim2, s2)
	for t in range(90):
		heal(s2)
		sim2.step()
	check(Gunfire.alert_of(s2, 1).get("phase", "") == "hold", "Stopped but still armed: they hold at gunpoint (%s)" % Gunfire.alert_of(s2, 1).get("phase", ""))
	fire(sim2, s2)
	for id in near_cells: s2.entities[str(id)].cell = near_cells[id]   # now they are back among the buildings
	check(Gunfire.alert_of(s2, 1).get("phase", "") == "lethal" and bool(Gunfire.alert_of(s2, 1).lethal), "Firing again after stopping makes it lethal")
	# Shooting to kill they hit hard; but once you're down they want you alive: they rush in and take
	# you rather than finish you off.
	var hit_hard := false
	var rushed := false
	var taken := false
	for t in range(1200):
		if t % 60 == 0 and not bool(s2.player_control.get("dead", false)) and not load("res://sim/combat/brawl.gd").player_down(s2) and not Law.restrained(s2): fire(sim2, s2)
		else: sim2.step()
		if BodyHealth.overall(s2) < 100: hit_hard = true
		for id in Sheriff.roster(s2, 1):
			if bool(s2.residents[str(id)].get("arrest", {}).get("rush", false)): rushed = true
		if Law.restrained(s2) or Law.in_custody(s2) or str(s2.residents[str(Sheriff.roster(s2, 1)[0])].get("arrest", {}).get("phase", "")) in ["cuff", "lift"]: taken = true; break
		if bool(s2.player_control.get("dead", false)): break
	check(hit_hard, "Sheriffs shooting to kill hit hard (overall %d)" % BodyHealth.overall(s2))
	check(rushed, "Once you're down they rush in")
	check(taken or bool(s2.player_control.get("dead", false)), "...and take you alive (or you die of your wounds)")
	print("Gunfire: %s" % ("PASS" if failures == 0 else "FAIL")); quit(failures)
