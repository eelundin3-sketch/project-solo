extends SceneTree
const Sim = preload("res://sim/core/simulation.gd")
const Households = preload("res://sim/entities/households.gd")
const Invariants = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func sleepers(s: Dictionary) -> Array:
	# Townsfolk only: the bandits sleep in bedrolls at their camp (bandits.gd), not in beds.
	return s.residents.values().filter(func(n: Dictionary) -> bool: return not n.get("sleeping", {}).is_empty() and n.occupation != "Bandit")
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	var lodge: Dictionary = s.entities[str(s.home)]
	var beds: int = lodge.furniture.filter(func(f: Dictionary) -> bool: return f.kind == "bed").size()
	check(beds >= 5, "The lodge has enough beds: %d" % beds)
	# Middle of the day: nobody is in bed.
	while s.tick < 6000: sim.step()
	check(sleepers(s).is_empty(), "Nobody sleeps in the afternoon")
	# Late evening: people tired from the day go to bed.
	while s.tick < 14000: sim.step()   # about 23:20
	var asleep: Array = sleepers(s)
	check(asleep.size() >= 2, "Tired villagers are asleep in bed at night: %d" % asleep.size())
	for npc in asleep:
		var bed: Dictionary = Households.bed_info(s, npc)
		check(not bed.is_empty() and s.entities[str(npc.id)].cell == bed.lie, "A sleeper lies on their own bed")
		check(npc.status == "Sleeping in bed", "Sleepers are labelled asleep")
	# Morning: they wake and get up beside the bed, then go to work.
	while s.tick < 14400 + 4200: sim.step()   # about 06:50 next day
	check(sleepers(s).filter(func(n: Dictionary) -> bool: return n.occupation != "Barkeep").is_empty(), "Everyone is up in the morning (the barkeep keeps later hours)")
	check(Invariants.validate(s).is_empty(), "Invariants hold: " + str(Invariants.validate(s)))
	if failures == 0: print("Sleep: PASS")
	quit(failures)
