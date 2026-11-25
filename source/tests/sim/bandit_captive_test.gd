extends SceneTree
## The hold-up and captivity: at the hold-up the other two cover you from both sides and the leader
## counts down; taken captive, you're hauled up and walked to the post a step at a time (no jumps)
## and tied; at night one of them is always on watch; working the ropes (F) frees you unless the
## watch is close; and they won't let you go through their loot pile.
const Sim = preload("res://sim/core/simulation.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const World = preload("res://sim/world/world_db.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func place(s: Dictionary, offset: Array) -> void:
	var camp: Array = s.bandits.cell
	for r in range(0, 4):
		var c: Array = [camp[0] + offset[0] + r, camp[1] + offset[1]]
		if World.walkable(s, c): s.entities[str(s.player)].cell = c; return

func said(s: Dictionary, text: String) -> bool:
	for line in s.get("speech", []):
		if str(line.text) == text: return true
	return false

func _initialize() -> void:
	# The hold-up.
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	place(s, [0, 11])
	var heard_count := false
	var flanked_both := false
	for i in range(140):
		sim.step()
		if said(s, "One..."): heard_count = true
		if str(s.bandits.phase) != "demand": continue
		var me: Array = s.entities[str(s.player)].cell
		var camp: Array = s.bandits.cell
		var dir := Vector2(me[0] - camp[0], me[1] - camp[1]).normalized()
		var sides := {}
		for id in s.bandits.members:
			if int(id) == int(s.bandits.leader): continue
			var at: Array = s.entities[str(id)].cell
			var off := Vector2(at[0] - me[0], at[1] - me[1])
			if off.length() > 1.5 and bool(s.residents[str(id)].get("gun_out", false)): sides[signf(dir.x * off.y - dir.y * off.x)] = true
		if sides.has(1.0) and sides.has(-1.0): flanked_both = true
	check(str(s.bandits.phase) in ["demand", "fight"], "They hold you up")
	check(flanked_both, "The other two cover you from both sides, guns out")
	check(heard_count, "The leader counts down out loud")

	# Taken captive while down: hauled up, then walked to the post a step at a time, then tied.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 11 * 600
	place(s2, [0, 12])
	var me2: Array = s2.entities[str(s2.player)].cell
	Brawl.knockdown(s2, s2.player_control, me2, "fall", [1, 0])
	var leader: Dictionary = s2.residents[str(s2.bandits.leader)]
	Bandits._take_captive(sim2, leader)
	Bandits._home(sim2, "idle")
	var stages := []
	var biggest := 0
	var last: Array = me2.duplicate()
	var down_until_lift := true
	for i in range(1500):
		sim2.step()
		var c: Dictionary = s2.player_control.get("captive", {})
		if c.is_empty(): break
		var stage: String = str(c.get("stage", ""))
		if stages.is_empty() or stages[-1] != stage: stages.append(stage)
		if stage == "fetch" and not Brawl.player_down(s2): down_until_lift = false
		var at: Array = s2.entities[str(s2.player)].cell
		biggest = maxi(biggest, maxi(absi(at[0] - last[0]), absi(at[1] - last[1])))
		last = at.duplicate()
		if stage == "tied": break
	check(stages == ["fetch", "lift", "walk", "tied"], "Fetched, hauled up, walked, tied (%s)" % str(stages))
	check(down_until_lift, "Left on the ground until he hauls you up")
	check(biggest <= 1, "Walked there a step at a time (biggest jump %d)" % biggest)
	check(s2.entities[str(s2.player)].cell == Bandits.post(s2), "Tied at the post (at %s, post %s, captor %s, walkable %s)" % [str(s2.entities[str(s2.player)].cell), str(Bandits.post(s2)), str(s2.entities[str(s2.bandits.leader)].cell), str(World.walkable(s2, Bandits.post(s2)))])
	check(Bandits.captive(s2), "Still their captive")

	# Working the ropes: the watch close by hears it; with him away you get free.
	var watcher: Dictionary = s2.residents[str(s2.bandits.members[1])]
	var post: Array = Bandits.post(s2)
	s2.entities[str(watcher.id)].cell = [post[0] + 1, post[1]]
	watcher.sleeping = {}
	sim2.submit("surrender")
	for i in range(45):
		s2.entities[str(watcher.id)].cell = [post[0] + 1, post[1]]
		sim2.step()
	check(not bool(s2.player_control.captive.get("working", true)), "The watch close by hears you and you stop")
	sim2.submit("surrender")
	var freed := -1
	for i in range(600):
		for id in s2.bandits.members:   # keep them all well away from the post
			s2.entities[str(id)].cell = Bandits.at_camp(s2.bandits.cell, [8, -6 + int(id) % 3])
		sim2.step()
		if not Bandits.captive(s2): freed = i; break
	check(freed >= 0 and freed <= Bandits.ROPE_TICKS + 40, "With nobody near, you work the ropes loose (%d ticks)" % freed)
	check(Checks.validate(s2).is_empty(), "Invariants hold: %s" % str(Checks.validate(s2)))

	# At night one of them is always awake on watch.
	var sim3 := Sim.new(); sim3.start_game(); var s3: Dictionary = sim3.state
	s3.tick = 14400 + 23 * 600
	var always_watch := true
	for i in range(14400 / 2):
		sim3.step()
		if i < 600 or s3.tick % 100 != 0: continue
		var npc0: Dictionary = s3.residents[str(s3.bandits.members[0])]
		if not DayClock.bed_hours(s3, npc0): continue
		var awake := 0
		for id in s3.bandits.members:
			if s3.residents[str(id)].get("sleeping", {}).is_empty(): awake += 1
		if awake < 1: always_watch = false
	check(always_watch, "At night one of them is always awake on watch")

	# Their loot pile: go through it in the day and they open fire, cool-down or not.
	var sim4 := Sim.new(); sim4.start_game(); var s4: Dictionary = sim4.state
	s4.tick = 14400 + 11 * 600
	s4.bandits.cooldown_until = s4.tick + 14400
	var pile: Array = s4.entities[str(s4.bandits.stash)].cell
	s4.entities[str(s4.player)].cell = Bandits._open_near(s4, [pile[0] + 1, pile[1]])
	for i in range(10): sim4.step()
	check(str(s4.bandits.phase) == "fight", "Caught at their loot pile, they fight")
	print("Bandit captive: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
