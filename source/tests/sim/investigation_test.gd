extends SceneTree
## Missing people and investigations. A killing nobody saw alerts no one at first; an hour later the
## family misses them and tells the sheriff, who goes to the house and searches round town; a body
## out of the way where nobody saw stays hidden and they stay missing. A body he's shown is examined
## (how they died), people are asked, and the dead are laid to rest. A witness who saw the stranger gets the crime filed by description. A body
## stumbled on is reported at once. A motive alone and the sheriff wants a word with you. Money is
## conserved; save and load keep the hash.
const Sim = preload("res://sim/core/simulation.gd")
const Investigation = preload("res://sim/law/investigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Law = preload("res://sim/law/law.gd")
const World = preload("res://sim/world/world_db.gd")
const Chronicle = preload("res://sim/world/chronicle.gd")
const Society = preload("res://sim/factions/society.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

## Someone with family in town 1.
func victim_of(s: Dictionary) -> Dictionary:
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != 1 or npc.occupation in ["Sheriff", "Child", "Trader", "Governor", "Barkeep"]: continue
		var household: Dictionary = s.get("households", {}).get(str(npc.get("household", "")), {})
		if household.get("members", []).size() >= 2: return npc
	return {}

## A quiet spot at the edge of town, away from everyone.
func lonely(s: Dictionary) -> Array:
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	for r in range(40, 70, 2):
		for d in [[1, 1], [-1, 1], [1, -1], [-1, -1]]:
			var c: Array = [store[0] + d[0] * r, store[1] + d[1] * r / 2]
			if not World.walkable(s, c) or World.inside_building(s, c) != 0: continue
			if load("res://sim/combat/gunfire.gd").town_of(s, c) != 1: continue
			var alone := true
			for npc in s.residents.values():
				var at: Array = s.entities[str(npc.id)].cell
				if Vector2(at[0] - c[0], at[1] - c[1]).length() < 20.0: alone = false
			if alone: return c
	return [store[0] + 50, store[1] + 20]

func _initialize() -> void:
	# A killing nobody saw.
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 9 * 600
	var victim: Dictionary = victim_of(s)
	check(not victim.is_empty(), "Found someone with family")
	var spot: Array = lonely(s)
	s.entities[str(victim.id)].cell = spot
	Brawl.kill(sim, victim, "shot")
	var reported_early := false
	var missing_report := false
	var phases := []
	var saved := false
	for i in range(9000):
		sim.step()
		var c: Dictionary = Investigation.case_of(s, int(victim.id))
		if i < Investigation.MISSED_AFTER - 60 and (not c.is_empty() or bool(victim.get("missed", false))): reported_early = true
		for npc in s.residents.values():
			if str(npc.get("reporting", {}).get("kind", "")) == "missing" and int(npc.reporting.victim) == int(victim.id): missing_report = true
		if not c.is_empty() and (phases.is_empty() or phases[-1] != str(c.phase)): phases.append(str(c.phase))
		if not saved and str(c.get("phase", "")) == "house":
			saved = true
			var copy := Sim.new()
			copy.restore(sim.snapshot())
			check(copy.state_hash() == sim.state_hash(), "Save and load mid-search keep the same hash")
		if not c.is_empty() and str(c.phase) in ["open", "closed"]: break
	var case1: Dictionary = Investigation.case_of(s, int(victim.id))
	check(not reported_early, "Nobody knows for the first hour")
	check(missing_report, "Then the family reports them missing")
	check(phases.size() > 0 and phases[0] == "house" and ("search" in phases or "to_body" in phases), "The sheriff goes to the house first, then looks for them (%s)" % str(phases))
	check(saved, "(saved and loaded during the case)")
	check(str(case1.get("outcome", "")) == "missing", "Died out of the way where nobody saw: they're still missing (%s)" % str(case1.get("outcome", "")))
	check(not bool(victim.get("found", false)), "...a body out of the way stays hidden")
	check(Law.wanted_hours(s, 1) == 0, "...and nobody is wanted")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# A witness saw the stranger: filed by description.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 9 * 600
	var v2: Dictionary = victim_of(s2)
	var spot2: Array = lonely(s2)
	s2.entities[str(v2.id)].cell = spot2
	var watcher: Dictionary = {}
	for npc in s2.residents.values():
		if int(npc.settlement) == 1 and npc.occupation not in ["Sheriff", "Child", "Trader"] and int(npc.id) != int(v2.id): watcher = npc; break
	s2.entities[str(watcher.id)].cell = [spot2[0] + 2, spot2[1]]
	s2.entities[str(s2.player)].cell = [spot2[0] - 1, spot2[1]]
	var entry: Dictionary = Law.remember_crime(s2, 1, "murder", int(v2.id))
	check(int(watcher.id) in entry.get("witnesses", []), "Someone saw it")
	Brawl.kill(sim2, v2, "shot")
	Investigation.open(sim2, 1, int(v2.id), "body", Law.sheriffs(s2, 1)[0])
	for i in range(6000):
		sim2.step()
		if str(Investigation.case_of(s2, int(v2.id)).get("phase", "")) in ["open", "closed"]: break
	check(str(Investigation.case_of(s2, int(v2.id)).get("outcome", "")) == "solved", "A witness: the case is solved")
	check(Law.wanted_hours(s2, 1) > 0 and not s2.law.wanted["1"].get("outfit", {}).is_empty(), "...and you're wanted by the clothes they saw")

	# A body stumbled on is reported at once.
	var sim3 := Sim.new(); sim3.start_game(); var s3: Dictionary = sim3.state
	s3.tick = 14400 + 11 * 600
	var v3: Dictionary = victim_of(s3)
	var passer: Dictionary = {}
	for npc in s3.residents.values():
		if int(npc.settlement) == 1 and npc.occupation not in ["Sheriff", "Child", "Trader"] and int(npc.id) != int(v3.id) and npc.get("sleeping", {}).is_empty(): passer = npc; break
	var at3: Array = s3.entities[str(passer.id)].cell
	for d in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
		if World.walkable(s3, [at3[0] + d[0], at3[1] + d[1]]): s3.entities[str(v3.id)].cell = [at3[0] + d[0], at3[1] + d[1]]; break
	Brawl.kill(sim3, v3, "beaten")
	var runner := false
	for i in range(200):
		sim3.step()
		for npc in s3.residents.values():
			if str(npc.get("reporting", {}).get("kind", "")) == "body": runner = true
		if runner or not Investigation.case_of(s3, int(v3.id)).is_empty(): break
	check(runner or not Investigation.case_of(s3, int(v3.id)).is_empty(), "A body stumbled on is reported at once")

	# A motive and no witness: he wants a word; denying it holds.
	var sim4 := Sim.new(); sim4.start_game(); var s4: Dictionary = sim4.state
	s4.tick = 14400 + 9 * 600
	var v4: Dictionary = victim_of(s4)
	s4.entities[str(v4.id)].cell = lonely(s4)
	Society.remember(s4, int(v4.id), "assaulted", int(s4.player), "The stranger struck me.")
	Brawl.kill(sim4, v4, "beaten")
	var sheriff4: Dictionary = Law.sheriffs(s4, 1)[0]
	Investigation.open(sim4, 1, int(v4.id), "body", sheriff4)
	for i in range(6000):
		sim4.step()
		if str(Investigation.case_of(s4, int(v4.id)).get("phase", "")) in ["open", "closed"]: break
	check(str(Investigation.case_of(s4, int(v4.id)).get("outcome", "")) == "suspect", "A motive, no witness: you're a suspect")
	check(str(Investigation.case_of(s4, int(v4.id)).get("cause", "")) == "beaten to death", "The cause of death matches the wound (%s)" % str(Investigation.case_of(s4, int(v4.id)).get("cause", "")))
	check(bool(v4.get("buried", false)), "The dead are laid to rest")
	var options: Array = load("res://sim/player/conversation.gd").options(s4, sheriff4).map(func(o): return o.id)
	check("c_deny" in options and "c_confess" in options, "The sheriff wants a word: deny it or own up")
	var reply: String = Investigation.answer(sim4, sheriff4, false)
	check(reply.contains("eye on you") and Law.wanted_hours(s4, 1) == 0, "With nobody having seen you two fight, a denial holds")
	check(Checks.validate(s4).is_empty(), "Invariants hold: %s" % str(Checks.validate(s4)))
	print("Investigation: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
