extends SceneTree
## At home with F: each workout runs its steps in order (under the bar, unrack, five reps, rack it)
## and ends with the bar back; a set adds fitness, stamina pool and carrying, and makes you tired
## and thirsty; moving mid-set racks the bar first; spent, you can't train; the fridge drink heals
## once an hour; resting on the bed and the sofa; save and load mid-set keep the hash.
const Sim = preload("res://sim/core/simulation.gd")
const Activities = preload("res://sim/player/activities.gd")
const PlayerHouse = preload("res://sim/settlement/player_house.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func piece(s: Dictionary, kind: String) -> int:
	var house: Dictionary = PlayerHouse.house(s)
	for i in range(house.furniture.size()):
		if house.furniture[i].kind == kind: return i
	return -1

## Stand beside a piece and press F.
func use(sim, kind: String) -> void:
	var s: Dictionary = sim.state
	var item: Dictionary = PlayerHouse.house(s).furniture[piece(s, kind)]
	var r: Array = item.rect
	var spot: Array = [int(r[0]), int(r[1]) + int(r[3])]
	s.entities[str(s.player)].cell = spot
	sim.submit("interact", {"target": 0})
	sim.step()

func run_out(sim) -> Array:
	var stages: Array = []
	for i in range(600):
		var st: Dictionary = Activities.stage_of(sim.state)
		if st.is_empty(): break
		if stages.is_empty() or stages[-1] != st.stage: stages.append(st.stage)
		sim.step()
	return stages

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.player_needs.fatigue = 10
	var expected := {"squat_rack": ["setup", "unrack", "walkout", "rep", "walkin", "rerack", "exit"], "bench_press": ["sit", "lie", "grip", "unrack", "rep", "rerack", "situp", "stand"],
		"deadlift_platform": ["setup", "hinge", "rep", "release"], "pullup_bar": ["jump", "hang", "rep", "drop"]}
	for kind in expected:
		s.player_needs.fatigue = 10
		var before: int = int(s.get("player_status", {}).get("fitness", 0))
		use(sim, kind)
		check(Activities.active(s), "F at the %s starts it" % kind)
		var reps_seen := 0
		var stages: Array = []
		for i in range(600):
			var st: Dictionary = Activities.stage_of(s)
			if st.is_empty(): break
			if stages.is_empty() or stages[-1] != st.stage: stages.append(st.stage)
			reps_seen = maxi(reps_seen, int(st.rep))
			sim.step()
		check(stages == expected[kind], "%s goes step by step: %s" % [kind, str(stages)])
		check(int(s.player_status.fitness) == before + 1, "A full set of %s adds fitness" % kind)
	check(int(s.player_health.stamina_max) >= 100, "Your stamina pool keeps up with your fitness")
	var spent: int = int(s.player_needs.fatigue)
	check(spent > 10, "Training tires you")
	# Moving mid-set: the bar goes back first.
	s.player_needs.fatigue = 10
	use(sim, "squat_rack")
	for i in range(60): sim.step()
	check(Activities.stage_of(s).stage == "rep", "Mid-set")
	var copy := Sim.new(); copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load mid-set keep the hash")
	var fit: int = int(s.player_status.fitness)
	sim.submit("move_player", {"direction": [1, 0]}); sim.step()
	var after: Array = run_out(sim)
	check(after.size() > 0 and after[0] in ["walkin", "rep"] and "rerack" in after, "Moving mid-set racks the bar first (%s)" % str(after))
	check(int(s.player_status.fitness) == fit, "An unfinished set doesn't count")
	# Spent: no training.
	s.player_needs.fatigue = 95
	use(sim, "deadlift_platform")
	check(not Activities.active(s) and str(s.player_control.notice).begins_with("You're spent"), "Spent, you can't train")
	# The fridge: heals, once an hour.
	for part in s.player_health.parts.values(): part.damage = 0
	s.player_health.parts.values()[0].damage = 30
	s.player_needs.thirst = 80
	use(sim, "fridge")
	var fridge_steps: Array = run_out(sim)
	check(fridge_steps == ["open", "reach", "close", "drink", "lower"], "The fridge: open, reach in, close, drink (%s)" % str(fridge_steps))
	check(int(s.player_health.parts.values()[0].damage) < 30 and int(s.player_needs.thirst) < 80, "The cold drink heals and quenches")
	use(sim, "fridge")
	check(not Activities.active(s), "...but only once an hour")
	# Resting on the bed and the sofa; F gets you up.
	s.player_needs.stress = 40
	use(sim, "bed")
	for i in range(80): sim.step()
	check(Activities.stage_of(s).stage == "lie" and int(s.player_needs.stress) < 40, "Lying down on the bed eases you")
	sim.submit("interact", {"target": 0}); sim.step()
	check(not Activities.active(s) and load("res://sim/world/world_db.gd").walkable(s, s.entities[str(s.player)].cell), "F gets you up, onto the floor")
	use(sim, "sofa")
	check(Activities.stage_of(s).get("kind", "") == "sofa", "You sit back on the sofa")
	sim.submit("move_player", {"direction": [0, 1]}); sim.step()
	check(not Activities.active(s), "Moving gets you up")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))
	print("Workout: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
