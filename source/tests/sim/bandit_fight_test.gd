extends SceneTree
## The bandits fight the way the sheriffs do: each takes a position (front, flank, camp), hides,
## leans out and fires, reloads behind cover, and one works round your side. They want you alive
## (no shots to kill until you hurt one). Nobody jumps across the map: every move is one step.
## Lose the leader and the rest give up or run. Deterministic.
const Sim = preload("res://sim/core/simulation.gd")
const World = preload("res://sim/world/world_db.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func start(sim) -> Dictionary:
	sim.start_game()
	var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var camp: Array = s.bandits.cell
	for dx in range(10, 16):
		var c: Array = [camp[0] + dx, camp[1] + 4]
		if World.walkable(s, c): s.entities[str(s.player)].cell = c; break
	s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	sim.submit("shotgun_fire", {"direction": [0, 1000]})   # a shot into the ground near the camp
	return s

func _initialize() -> void:
	var sim := Sim.new()
	var s: Dictionary = start(sim)
	var roles := {}
	var phases := {}
	var reloaded := false
	var flanked := false
	var biggest_step := 0
	var last := {}
	var lethal_early := false
	for i in range(900):
		sim.step()
		for id in s.bandits.members:
			var npc: Dictionary = s.residents[str(id)]
			var cell: Array = s.entities[str(id)].cell
			if last.has(id): biggest_step = maxi(biggest_step, maxi(absi(cell[0] - last[id][0]), absi(cell[1] - last[id][1])))
			last[id] = cell.duplicate()
			if npc.has("fight_role"): roles[str(npc.fight_role)] = true
			var cycle: Dictionary = npc.get("cover_cycle", {})
			if not cycle.is_empty():
				phases[str(cycle.phase)] = true
				if int(cycle.get("ammo", 5)) <= 0: reloaded = true
				if bool(cycle.get("flank", false)): flanked = true
		if str(s.bandits.phase) == "fight" and bool(s.bandits.get("lethal", false)): lethal_early = true
		s.player_control.knock = {}       # keep the player up so the fight runs on
		if s.has("body"): pass
	check(roles.has("front") and roles.has("flank") and roles.has("camp"), "They take positions: front, flank and camp (%s)" % str(roles.keys()))
	check(phases.has("hide") and phases.has("peek") and phases.has("fire"), "They hide, lean out and fire (%s)" % str(phases.keys()))
	check(reloaded, "They run dry and reload")
	check(flanked, "One works round the side")
	check(not lethal_early, "Until you hurt one, they don't shoot to kill")
	check(biggest_step <= 1, "Nobody jumps: every move is one step (biggest %d)" % biggest_step)
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# Lose the leader: the rest give up or run.
	var sim2 := Sim.new()
	var s2: Dictionary = start(sim2)
	for i in range(30): sim2.step()
	check(str(s2.bandits.phase) == "fight", "The fight is on")
	var leader: Dictionary = s2.residents[str(s2.bandits.leader)]
	leader.health = 0
	for i in range(10): sim2.step()
	var broke := 0
	for id in s2.bandits.members:
		var npc: Dictionary = s2.residents[str(id)]
		if int(id) == int(s2.bandits.leader): continue
		if bool(npc.get("surrendered", false)) or not npc.get("fleeing", []).is_empty(): broke += 1
	check(broke == s2.bandits.members.size() - 1, "With the leader down, the rest give up or run (%d)" % broke)

	# The same seed and the same shot: the same fight.
	var a := Sim.new(); start(a)
	var b := Sim.new(); start(b)
	for i in range(300): a.step(); b.step()
	check(a.state_hash() == b.state_hash(), "Deterministic")
	print("Bandit fight: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
