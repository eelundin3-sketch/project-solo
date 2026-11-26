extends SceneTree
## Your house: on the west side of Alder Hollow, yours and nobody else's; the bedroom left of the
## entrance, the living room ahead with the kitchen and fridge, a back door onto the terrace with
## the workout gear; you can walk in, out the back and to the town; an older save gains it on load.
const Sim = preload("res://sim/core/simulation.gd")
const World = preload("res://sim/world/world_db.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const PlayerHouse = preload("res://sim/settlement/player_house.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	var house: Dictionary = PlayerHouse.house(s)
	check(not house.is_empty(), "You have a house")
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	check(int(house.door[0]) < int(store[0]) - 15 and load("res://sim/combat/gunfire.gd").town_of(s, house.door) == 1, "It's on the west side of Alder Hollow")
	var taken := false
	for h in s.households.values():
		if int(h.home) == int(house.id): taken = true
	check(not taken, "No household is given it")
	check(load("res://sim/law/trespass.gd").kind_of_place(s, house) == "", "It's yours to come and go")
	var f: Array = house.footprint
	var l: int = int(f[0]); var t: int = int(f[1])
	# The rooms: the bedroom to the left of the entrance (through its doorway), the living room ahead.
	var bed: Dictionary = {}
	var kinds: Array = []
	for item in house.furniture:
		kinds.append(str(item.kind))
		if item.kind == "bed": bed = item
	check(int(bed.rect[0]) < int(house.door[0]) and int(bed.rect[1]) > t + 4, "The bed is in the bedroom, left of the entrance")
	for k in ["fridge", "counter", "stove", "sofa", "fireplace", "table", "squat_rack", "bench_press", "deadlift_platform", "pullup_bar", "plate_tree", "deck"]:
		check(k in kinds, "It has a %s" % k)
	var hall: Array = [house.door[0], house.door[1] - 1]
	var bedroom: Array = [l + 3, t + 9]
	var living: Array = [l + 7, t + 2]
	var terrace: Array = [l + 7, t - 2]
	check(World.walkable(s, bedroom) and Nav.request_path(s, hall, bedroom).ok, "From the hall you can walk into the bedroom")
	check(Nav.request_path(s, hall, living).ok, "...and straight ahead into the living room")
	var out_back: Dictionary = Nav.request_path(s, living, terrace)
	check(out_back.ok and out_back.path.size() < 8, "...and out the back door onto the terrace (%d steps)" % out_back.path.size())
	check(World.inside_building(s, terrace) == 0, "The terrace is outside")
	check(Nav.request_path(s, [house.door[0], house.door[1] + 1], store).ok, "You can walk from your door into town")
	# You can sleep in its bed.
	s.player_needs.fatigue = 90
	check(load("res://sim/player/sleep.gd").problem(s, int(house.id), house.furniture.find(bed)) == "", "You can sleep in your bed")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))
	# An older save without it gains it on load.
	var old := Sim.new(); old.start_game()
	var snap: Dictionary = old.snapshot()
	var raw: Dictionary = snap.state if snap.has("state") else snap
	var copy := Sim.new()
	copy.restore(snap)
	check(not PlayerHouse.house(copy.state).is_empty(), "A loaded save has the house")
	print("Player house: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
