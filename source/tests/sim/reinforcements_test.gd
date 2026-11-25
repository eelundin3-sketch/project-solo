extends SceneTree
## Help from the next town: a witnessed killing sends a runner; two sheriffs come (one stays home);
## if the killer is already caught they visit the office, talk it over and go home; if the fight is
## still on they join it as the town's sheriffs. Saves keep it all.
const Sim = preload("res://sim/core/simulation.gd")
const Reinforcements = preload("res://sim/law/reinforcements.gd")
const Law = preload("res://sim/law/law.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func start() -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 5400
	for npc in s.residents.values():
		npc.sleeping = {}; npc.hunger = 0; npc.thirst = 0; npc.fatigue = 0
	var witness: Dictionary = {}
	for npc in s.residents.values():
		if witness.is_empty() and int(npc.settlement) == 1 and npc.occupation not in ["Sheriff", "Child", "Trader"]: witness = npc
	return [sim, s, witness]

func call_of(s: Dictionary) -> Dictionary:
	var calls: Array = s.get("law", {}).get("reinforcements", [])
	return calls[0] if not calls.is_empty() else {}

func spoken(s: Dictionary, text: String) -> bool:
	for line in s.get("speech", []):
		if str(line.text).contains(text): return true
	return false

func _initialize() -> void:
	# A. Caught before they arrive: they visit the office, talk, and go home.
	var a: Array = start()
	var sim: RefCounted = a[0]; var s: Dictionary = a[1]; var witness: Dictionary = a[2]
	var helper_town := 0
	var home_before := 0
	Reinforcements.on_killing(sim, 1, s.entities[str(witness.id)].cell, [int(witness.id)])
	var call: Dictionary = call_of(s)
	check(not call.is_empty() and str(call.phase) == "runner", "A witnessed killing sends someone running for help")
	if not call.is_empty():
		helper_town = int(call.from)
		home_before = Sheriff.roster(s, helper_town).size()
		check(helper_town != 1, "Help comes from another town")
		var reached := -1
		for i in range(6000):
			sim.step()
			if str(call.phase) == "coming": reached = i; break
		check(reached >= 0, "The runner reaches the next town (%d ticks)" % reached)
		check(call.sheriffs.size() == mini(2, home_before - 1), "Two sheriffs set out (%d of %d)" % [call.sheriffs.size(), home_before])
		check(Sheriff.roster(s, helper_town).size() >= 1, "At least one sheriff stays at home")
		var copy := Sim.new()
		copy.restore(sim.snapshot())
		check(copy.state_hash() == sim.state_hash(), "Save and load on the road keep the same hash")
		# Meanwhile the killer is caught and in the cell.
		var office: Dictionary = Law.office_of(s, 1)
		s.player_control.jail = {"office": office.id, "until": s.tick + 200000, "hours": 24, "rect": Law.cell_rect(office), "sheriff": int(Law.sheriffs(s, 1)[0].id), "town": 1}
		s.entities[str(s.player)].cell = Law.cell_spot(office)
		var talked := false
		var home := -1
		for i in range(12000):
			sim.step()
			if spoken(s, "We came as fast as we could"): talked = true
			if str(call.phase) in ["returning", "done"] and talked and home < 0: home = i
			if str(call.phase) == "done": break
		check(talked, "At the office they say they came as fast as they could")
		check(int(call.talk) >= Reinforcements.TALK.size(), "They talk it over (%d lines)" % int(call.talk))
		check(str(call.phase) == "done", "Then they go home (%s)" % str(call.phase))
		for id in call.sheriffs:
			check(int(s.residents[str(id)].settlement) == helper_town and s.residents[str(id)].get("reinforcing", {}).is_empty(), "Each is back on duty at home")
		check(Sheriff.strength(s, helper_town) == home_before, "No sheriffs were lost or recruited")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# B. Still fighting when they arrive: they join in as the town's sheriffs.
	var b: Array = start()
	var sim2: RefCounted = b[0]; var s2: Dictionary = b[1]; var witness2: Dictionary = b[2]
	Reinforcements.on_killing(sim2, 1, s2.entities[str(witness2.id)].cell, [int(witness2.id)])
	var call2: Dictionary = call_of(s2)
	var joined := false
	if not call2.is_empty():
		var store: Array = s2.entities[str(s2.settlements["1"].warehouse)].cell
		for i in range(12000):
			# A fight is on in town 1 the whole time (the player keeps a gun out and fires now and then).
			if not s2.law.has("alert"): s2.law.alert = {}
			s2.law.alert["1"] = {"phase": "engage", "since": s2.tick, "lethal": false, "shots": 1, "stopped_at": 0, "last_shot": s2.tick}
			s2.entities[str(s2.player)].cell = [store[0], store[1] + 9]
			sim2.step()
			if str(call2.phase) == "helping":
				for id in call2.sheriffs:
					var npc: Dictionary = s2.residents[str(id)]
					if int(npc.settlement) == 1 and npc in Law.sheriffs(s2, 1): joined = true
			if joined: break
	check(joined, "Arriving mid-fight, they join it as the town's sheriffs")

	print("Reinforcements: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
