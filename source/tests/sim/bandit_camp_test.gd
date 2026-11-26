extends SceneTree
## Camp life: over a day the bandits sit by the fire, cook, fetch firewood and keep watch, and at
## night each sleeps inside his own tent. When the shooting starts they dive for cover.
const Sim = preload("res://sim/core/simulation.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	var seen := {}
	var in_tent := 0
	var spot: Array = s.bandits.cell
	while s.tick < 14400 * 2:
		sim.step()
		if s.tick % 50 != 0: continue
		for i in range(s.bandits.members.size()):
			var npc: Dictionary = s.residents[str(s.bandits.members[i])]
			if not npc.get("sitting", {}).is_empty(): seen["sit"] = true
			if bool(npc.get("cooking", false)): seen["cook"] = true
			if str(npc.status) in ["Fetching firewood", "Picking up firewood"]: seen["wood"] = true
			if str(npc.status) == "Keeping watch": seen["watch"] = true
			if not npc.get("sleeping", {}).is_empty() and s.entities[str(npc.id)].cell == Bandits.at_camp(spot, Bandits.TENTS[i]): in_tent += 1
	for task in ["sit", "cook", "wood", "watch"]:
		check(seen.has(task), "Over a day the bandits %s" % {"sit": "sit by the fire", "cook": "cook", "wood": "fetch firewood", "watch": "keep watch"}[task])
	check(in_tent > 0, "At night they sleep inside their tents")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# A shot near the camp: they scatter to cover.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 11 * 600
	var camp: Array = s2.bandits.cell
	for dx in range(10, 16):
		var c: Array = [camp[0] + dx, camp[1] + 4]
		if load("res://sim/world/world_db.gd").walkable(s2, c): s2.entities[str(s2.player)].cell = c; break
	s2.shotgun.equipped = true; s2.shotgun.loaded = 5; s2.shotgun.last_shot = -1000
	sim2.submit("shotgun_fire", {"direction": [1000, 0]})
	var fought := false
	var took_cover := false
	for i in range(400):
		sim2.step()
		if str(s2.bandits.phase) == "fight": fought = true
		for id in s2.bandits.members:
			var npc: Dictionary = s2.residents[str(id)]
			var cover: Array = npc.get("cover_cycle", {}).get("cover", [])
			if not cover.is_empty() and s2.entities[str(id)].cell == cover: took_cover = true
		if took_cover: break
	check(fought, "Shooting near the camp starts a fight")
	check(took_cover, "In the fight a bandit gets behind cover")
	print("Bandit camp: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
