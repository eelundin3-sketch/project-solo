extends SceneTree
## Two or three sheriffs in every town; they take turns at the desk and on patrol; each has a bunk.
const Sim = preload("res://sim/core/simulation.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Households = preload("res://sim/entities/households.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	for key in ["1", "2", "3"]:
		var ids: Array = Sheriff.roster(s, int(key))
		var wanted: int = load("res://sim/settlement/capital.gd").sheriffs_wanted(s, int(key))   # 3; 5 in the capital
		check(ids.size() == wanted, "Town %s has %d sheriffs (%d)" % [key, wanted, ids.size()])
		for id in ids:
			check(String(s.entities[str(id)].name).begins_with("Sheriff "), "Every sheriff is dressed and named")
		var beds: Array = []
		for id in ids:
			var info: Dictionary = Households.bed_info(s, s.residents[str(id)])
			check(not info.is_empty(), "Every sheriff has somewhere to sleep")
			if not info.is_empty(): beds.append(str(info.rect))
		var distinct: Dictionary = {}
		for b in beds: distinct[b] = true
		check(distinct.size() >= mini(2, ids.size()), "Sheriffs do not share a bunk (%d bunks)" % distinct.size())
	# A town with plenty of people keeps three.
	var third: int = Sheriff.roster(s, 1).size()
	for i in range(14): load("res://sim/entities/residents.gd").add_resident(sim, 1, [60 + i, 50])
	Sheriff.ensure(sim)
	check(Sheriff.roster(s, 1).size() == 3, "A bigger town keeps three sheriffs (had %d)" % third)
	# Duty: someone is at the desk at all times, and the rest patrol.
	s.tick = 14400 + 4000
	var on_desk := 0
	var on_patrol := 0
	for id in Sheriff.roster(s, 1):
		match Sheriff.duty(s, s.residents[str(id)]):
			"desk": on_desk += 1
			"patrol": on_patrol += 1
	check(on_desk == 1 and on_patrol >= 1, "One sheriff is at the desk and the others patrol (%d / %d)" % [on_desk, on_patrol])
	# The one on desk duty walks to the chair and sits; the rest are out and about.
	for npc in s.residents.values():
		npc.sleeping = {}
		npc.hunger = 0; npc.thirst = 0; npc.fatigue = 0
	s.tick = 14400 + 3000
	var sat := false
	var chair_cell: Array = []
	for t in range(1800):
		sim.step()
		for id in Sheriff.roster(s, 1):
			var npc: Dictionary = s.residents[str(id)]
			if not npc.get("sitting", {}).is_empty():
				sat = true
				chair_cell = npc.sitting.chair
				check(s.entities[str(id)].cell == npc.sitting.chair, "A seated sheriff is in the chair cell")
		if sat: break
	check(sat, "A sheriff sits at the desk")
	# When his turn is over he stands up and goes on patrol.
	var stood := false
	for t in range(3000):
		sim.step()
		var any_sitting := false
		for id in Sheriff.roster(s, 1):
			if not s.residents[str(id)].get("sitting", {}).is_empty(): any_sitting = true
		if not any_sitting: stood = true; break
	check(stood, "The desk is taken in turns (someone stands up again)")
	for id in Sheriff.roster(s, 1):
		var cell: Array = s.entities[str(id)].cell
		if s.residents[str(id)].get("sitting", {}).is_empty(): check(World.walkable(s, cell), "A standing sheriff is on a walkable cell")
	check(Checks.validate(s).is_empty(), "Invariants hold: " + str(Checks.validate(s)))
	var copy := Sim.new(); copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Rosters and chairs survive a reload")
	print("Sheriff roster: %s" % ("PASS" if failures == 0 else "FAIL")); quit(failures)
