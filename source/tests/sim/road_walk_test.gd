extends SceneTree
## Everyday walks follow the roads, and walkers are quicker on them. Across town a walk keeps mostly
## to the road where the plain shortest way cut across; a short hop still goes straight; townsfolk
## near you step faster on a road; the same seed gives the same walks.
const Sim = preload("res://sim/core/simulation.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Pace = preload("res://sim/movement/pace.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func on_road_share(s: Dictionary, path: Array) -> float:
	if path.is_empty(): return 0.0
	var n := 0
	for c in path:
		if TownLayout.on_road(s, c): n += 1
	return float(n) / float(path.size())

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	# Across town: from each home's door to the store, the street walk keeps to the road more.
	var store: Dictionary = s.entities[str(s.settlements["1"].warehouse)]
	var goal: Array = World.Fixtures.interaction_cell(s, int(store.id))
	var better := 0
	var compared := 0
	var shares: Array = []
	var plain_shares: Array = []
	for home in World.of_kind(s, "home"):
		if int(home.get("settlement", 0)) != 1 or not home.has("door"): continue
		var from: Array = load("res://sim/law/law.gd").outside_of(s, home)
		var plain: Dictionary = Nav.request_path(s, from, goal)
		var street: Dictionary = Nav.request_walk_path(s, from, goal)
		if not plain.ok or not street.ok or plain.path.size() < 15: continue
		compared += 1
		var share: float = on_road_share(s, street.path)
		shares.append(share)
		plain_shares.append(on_road_share(s, plain.path))
		if share >= on_road_share(s, plain.path): better += 1
	var mean := 0.0
	for x in shares: mean += x
	mean /= maxf(1.0, float(shares.size()))
	var plain_mean := 0.0
	for x in plain_shares: plain_mean += x
	plain_mean /= maxf(1.0, float(plain_shares.size()))
	print("road share: plain %.0f%%, street %.0f%% over %d walks" % [plain_mean * 100.0, mean * 100.0, compared])
	check(compared >= 3, "Compared some walks across town (%d)" % compared)
	check(better == compared, "The street walk is never less on the road than the plain one (%d of %d)" % [better, compared])
	# Every walk starts in a yard and ends at a door, so part of it can never be road; the rest is.
	check(mean >= plain_mean + 0.25 and mean >= 0.4, "Walks across town keep to the road far more (%.0f%% against %.0f%%)" % [mean * 100.0, plain_mean * 100.0])
	# A short hop goes straight.
	var a: Array = goal
	var b: Array = [goal[0] + 3, goal[1] + 2]
	if World.walkable(s, b):
		check(Nav.request_walk_path(s, a, b).path.size() == Nav.request_path(s, a, b).path.size(), "A short hop takes the straight way")
	# Quicker on the road: the step timer's average on a main road against open ground.
	var road_cell: Array = []
	for key in TownLayout.road_map(s).kind:
		var c: Array = [int(key.get_slice(",", 0)), int(key.get_slice(",", 1))]
		if Pace.bonus(s, c) == 30: road_cell = c; break
	var off: Array = [-80, -70]
	var carry := {}
	var on_ticks := 0
	for i in range(100): on_ticks += Pace.delay(s, road_cell, 2, carry, "stride_carry")
	var off_ticks := 0
	carry = {}
	for i in range(100): off_ticks += Pace.delay(s, off, 2, carry, "stride_carry")
	check(not road_cell.is_empty() and float(on_ticks) / float(off_ticks) < 0.8, "On a main road a walker covers ground in about 77%% of the time (%d vs %d ticks)" % [on_ticks, off_ticks])
	# Townsfolk near you really step on that timer.
	var quick := false
	for i in range(2400):
		sim.step()
		for npc in s.residents.values():
			if npc.fidelity == "detailed" and int(npc.get("walk_next", 0)) - int(s.tick) == 1 and TownLayout.on_road(s, s.entities[str(npc.id)].cell): quick = true
		if quick: break
	check(quick, "Townsfolk on a road take quicker steps")
	# Deterministic.
	var x := Sim.new(); x.start_game()
	var y := Sim.new(); y.start_game()
	for i in range(1500): x.step(); y.step()
	check(x.state_hash() == y.state_hash(), "The same seed gives the same walks")
	var copy := Sim.new(); copy.restore(x.snapshot())
	check(copy.state_hash() == x.state_hash(), "Save and load keep the same hash")
	print("Road walk: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
