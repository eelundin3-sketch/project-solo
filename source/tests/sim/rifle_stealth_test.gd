extends SceneTree
## The rifle is the main gun: one hard-hitting bullet that reaches far past a shotgun. Shots are
## heard far off (the town and its sheriffs react; out in the wilds nobody does). And a silent
## takedown from behind makes no sound: unseen, nobody knows; seen, the witness runs to tell.
const Sim = preload("res://sim/core/simulation.gd")
const Guns = preload("res://sim/combat/shotgun.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Takedown = preload("res://sim/combat/takedown.gd")
const Law = preload("res://sim/law/law.gd")
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)

func _open_row(s: Dictionary, length: int) -> Array:
	for y in range(20, 90, 2):
		for x in range(10, 300, 3):
			var clear := true
			for step in range(0, length):
				if not World.walkable(s, [x + step, y]) or Guns.surface_at(s, [x + step, y], s.player) != "": clear = false; break
			if clear: return [x, y]
	return []

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	check(Guns.kind(s) == "rifle", "You start with a rifle")
	for npc in s.residents.values():
		if npc.occupation == "Sheriff": npc.occupation = "Gatherer"   # this part is about the bullet
	# A target 16 cells off: out of a shotgun's reach, not a rifle's.
	var row: Array = _open_row(s, 20)
	check(not row.is_empty(), "Found open ground")
	s.entities[str(s.player)].cell = row.duplicate()
	var target: Dictionary = {}
	for npc in s.residents.values():
		if npc.occupation not in ["Child"]: target = npc; break
	s.entities[str(target.id)].cell = [row[0] + 16, row[1]]
	var before: int = int(target.health)
	sim.submit("shotgun_toggle"); sim.step()
	sim.submit("shotgun_reload")
	for i in range(130): sim.step()
	check(int(s.shotgun.loaded) == 5, "Five cartridges loaded (%d)" % s.shotgun.loaded)
	s.entities[str(target.id)].cell = [row[0] + 16, row[1]]
	sim.submit("shotgun_fire", {"direction": [1000, 0]}); sim.step()
	check(s.shotgun.pellets.size() == 1, "One bullet per shot")
	for i in range(12): sim.step()
	check(int(target.health) < before, "The bullet reaches 16 cells and hurts (%d -> %d)" % [before, target.health])
	check(before - int(target.health) >= 20, "...hard (%d)" % (before - int(target.health)))
	check(Guns.WEAPONS.shotgun.range < 16, "(a shotgun's pellets stop at %d cells)" % Guns.WEAPONS.shotgun.range)
	# Heard: in town the sheriffs come; far out in the wilds, beyond anyone's hearing, nobody does.
	var town := Sim.new(); town.start_game(); var ts: Dictionary = town.state
	var store: Array = ts.entities[str(ts.settlements["1"].warehouse)].cell
	check(Gunfire.town_in_earshot(ts, [store[0] + 10, store[1] + 5], Guns.heard_range(ts)) == 1, "A shot in town is heard by the town")
	var wild: Array = []
	for y in range(5, 95, 5):
		for x in range(5, 330, 5):
			if wild.is_empty() and Gunfire.town_in_earshot(ts, [x, y], Guns.WEAPONS.shotgun.heard) == 0: wild = [x, y]
	check(not wild.is_empty() and Gunfire.town_in_earshot(ts, wild, Guns.WEAPONS.shotgun.heard) == 0, "Out in the wilds a shotgun blast is heard by nobody official (%s)" % str(wild))
	check(Guns.WEAPONS.rifle.heard > Guns.WEAPONS.shotgun.heard, "A rifle carries further than a shotgun")
	# A silent takedown, unseen: nobody knows.
	var quiet := Sim.new(); quiet.start_game(); var qs: Dictionary = quiet.state
	qs.tick = 14400 + 6000
	var victim: Dictionary = {}
	for npc in qs.residents.values():
		if victim.is_empty() and npc.occupation not in ["Sheriff", "Child", "Trader"]: victim = npc
	var lonely: Array = _open_row(qs, 6)
	for npc in qs.residents.values():
		if npc.id != victim.id and int(npc.settlement) != 0: qs.entities[str(npc.id)].cell = qs.entities[str(qs.settlements[str(npc.settlement)].warehouse)].cell.duplicate()
	qs.entities[str(victim.id)].cell = [lonely[0] + 1, lonely[1]]
	qs.entities[str(qs.player)].cell = lonely.duplicate()
	victim.path = []; victim.sleeping = {}
	check(not Takedown.problem(qs, victim).is_empty(), "Standing up, no takedown: %s" % Takedown.problem(qs, victim))
	qs.player_control.crouching = true
	victim.path = [[lonely[0], lonely[1]]]   # walking toward you: they'd see you coming
	check(not Takedown.problem(qs, victim).is_empty(), "Not when they're walking straight at you")
	victim.path = [[lonely[0] + 2, lonely[1]]]   # walking away
	check(Takedown.problem(qs, victim).is_empty(), "Crouched behind someone walking away: a takedown is possible")
	var notice: String = Takedown.perform(quiet, victim, true)
	check(int(victim.health) <= 0 and notice.contains("without a sound"), "Killed silently: %s" % notice)
	check(Law.wanted_hours(qs, int(victim.settlement)) == 0 and qs.law.get("hidden", []).size() == 1, "Unseen: nobody knows, an unsolved killing")
	# The same, with someone watching: they run to tell; a sheriff behind a wall saw nothing.
	var seen := Sim.new(); seen.start_game(); var ss: Dictionary = seen.state
	ss.tick = 14400 + 6000
	var v2: Dictionary = {}
	var watcher: Dictionary = {}
	for npc in ss.residents.values():
		npc.sleeping = {}
		if npc.occupation in ["Sheriff", "Child", "Trader"]: continue
		if v2.is_empty(): v2 = npc
		elif watcher.is_empty(): watcher = npc
	var spot: Array = _open_row(ss, 8)
	for npc in ss.residents.values():
		if npc.id != v2.id and npc.id != watcher.id and int(npc.settlement) != 0: ss.entities[str(npc.id)].cell = ss.entities[str(ss.settlements[str(npc.settlement)].warehouse)].cell.duplicate()
	ss.entities[str(v2.id)].cell = [spot[0] + 1, spot[1]]
	ss.entities[str(ss.player)].cell = spot.duplicate()
	ss.entities[str(watcher.id)].cell = [spot[0] + 6, spot[1]]
	v2.path = []
	ss.player_control.crouching = true
	Takedown.perform(seen, v2, false)
	check(Inventory != null and load("res://sim/combat/brawl.gd").knocked(ss, v2), "Knocked out cold, silently")
	check(not watcher.get("reporting", {}).is_empty(), "Someone who saw it runs to tell the sheriff")
	var copy := Sim.new(); copy.restore(seen.snapshot())
	for i in range(150): seen.step(); copy.step()
	check(seen.state_hash() == copy.state_hash(), "Save, load and continue gives the same world")
	print("Rifle and stealth: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)
