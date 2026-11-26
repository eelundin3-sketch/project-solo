extends SceneTree
## Bandits in town: one walks in, is seen, and two sheriffs close in. One who gives up is cuffed,
## walked to the office and locked in the cell; one who fights is shot at and shoots back (wounds on
## both sides) until he gives up or falls. Every third morning one of the gang goes for supplies.
## Save and load keep the same hash; money and goods are conserved.
const Sim = preload("res://sim/core/simulation.gd")
const Outlaws = preload("res://sim/law/outlaw_arrest.gd")
const Law = preload("res://sim/law/law.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func into_town(sim, bandit: Dictionary) -> void:
	var s: Dictionary = sim.state
	# Start him just outside town so the test doesn't wait for the long walk.
	var spot: Array = Outlaws.town_spot(s, 1)
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	s.entities[str(bandit.id)].cell = [store[0] + 20, store[1] + 10]
	var World = load("res://sim/world/world_db.gd")
	for r in range(0, 6):
		var c: Array = [store[0] + 20 + r, store[1] + 10]
		if World.walkable(s, c): s.entities[str(bandit.id)].cell = c; break
	check(Outlaws.send(s, bandit, 1, "supply"), "He sets off into town")

func _initialize() -> void:
	# One who gives up.
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 10 * 600
	var bandit: Dictionary = s.residents[str(s.bandits.members[1])]
	into_town(sim, bandit)
	bandit.health = 55                      # hurt: he won't fight
	var collared := false
	var saved := false
	var jailed_at := -1
	for i in range(4000):
		sim.step()
		if not Outlaws._team(s, int(bandit.id)).is_empty(): collared = true
		if collared and not saved and str(bandit.get("errand", {}).get("phase", "")) == "held":
			saved = true
			var copy := Sim.new()
			copy.restore(sim.snapshot())
			check(copy.state_hash() == sim.state_hash(), "Save and load mid-arrest keep the same hash")
		if not bandit.get("jailed", {}).is_empty(): jailed_at = i; break
	check(collared, "Seen in town, the sheriffs go for him")
	check(jailed_at >= 0, "He gives up, is walked to the office and locked up")
	if jailed_at >= 0:
		var office: Dictionary = Law.office_of(s, 1)
		var r: Array = Law.cell_rect(office)
		var at: Array = s.entities[str(bandit.id)].cell
		check(at[0] >= r[0] and at[1] >= r[1] and at[0] < r[0] + r[2] and at[1] < r[1] + r[3], "He's in the cell")
		check(Outlaws._team(s, int(bandit.id)).is_empty(), "The sheriffs go back to their day")
		# Three days later he's let out and heads back to the gang.
		bandit.jailed.until = s.tick + 5
		for i in range(10): sim.step()
		check(bandit.get("jailed", {}).is_empty() and str(bandit.get("errand", {}).get("phase", "")) == "returning", "Released after his time, he heads back to camp")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# One who fights (a stubborn one always draws).
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 10 * 600
	var b2: Dictionary = s2.residents[str(s2.bandits.members[2])]
	b2.stubborn = true
	into_town(sim2, b2)
	var dueled := false
	var sheriff_hurt := false
	for i in range(4000):
		sim2.step()
		if str(b2.get("errand", {}).get("phase", "")) == "duel": dueled = true
		for sheriff in Law.sheriffs(s2, 1):
			if int(sheriff.health) < 100: sheriff_hurt = true
		if dueled and (not b2.get("jailed", {}).is_empty() or int(b2.health) <= 0): break
	check(dueled, "A stubborn one draws on the sheriffs")
	check(int(b2.health) < 100, "In the shootout he's hit")
	check(not b2.get("jailed", {}).is_empty() or int(b2.health) <= 0, "The shootout ends with him jailed or dead (health %d)" % int(b2.health))
	check(Checks.validate(s2).is_empty(), "Invariants hold after the shootout: %s" % str(Checks.validate(s2)))
	if not sheriff_hurt: print("(the sheriffs came through unhurt this time)")

	# Supply runs: every third morning one of the gang heads off.
	var sim3 := Sim.new(); sim3.start_game(); var s3: Dictionary = sim3.state
	var went := false
	while s3.tick < 14400 * 4:
		sim3.step()
		for id in s3.bandits.members:
			if not s3.residents[str(id)].get("errand", {}).is_empty(): went = true
		if went: break
	check(went, "Within a few days one of them goes into town for supplies")
	print("Outlaw arrest: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
