extends SceneTree
## Carrying a body: pick up someone out cold, they move with you, you can't run or shoot, F puts
## them down; anyone who sees you with a body raises the alarm; a body hidden away isn't found,
## one left in the open is; and someone only knocked out comes round and struggles free.
const Sim = preload("res://sim/core/simulation.gd")
const Context = preload("res://sim/player/context_actions.gd")
const Carrying = preload("res://sim/player/carrying.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const World = preload("res://sim/world/world_db.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)

## A world with one victim out cold in a lonely spot, the player beside them, nobody else near.
func _scene(dead: bool) -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 6000
	var victim: Dictionary = {}
	for npc in s.residents.values():
		npc.sleeping = {}
		if victim.is_empty() and npc.settlement == 1 and npc.occupation not in ["Sheriff", "Child", "Trader"]: victim = npc
	var lonely: Array = []
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	for dy in range(30, 50):
		for dx in range(-60, -40):
			if lonely.is_empty() and World.walkable(s, [store[0] + dx, store[1] + dy]) and World.walkable(s, [store[0] + dx + 12, store[1] + dy]): lonely = [store[0] + dx, store[1] + dy]
	for npc in s.residents.values():
		if npc.id != victim.id and int(npc.settlement) != 0: s.entities[str(npc.id)].cell = s.entities[str(s.settlements[str(npc.settlement)].warehouse)].cell.duplicate()
	s.entities[str(victim.id)].cell = lonely.duplicate()
	s.entities[str(s.player)].cell = [lonely[0] + 1, lonely[1]]
	if dead: Brawl.kill(sim, victim, "test")
	else: Brawl.knockdown(s, victim, lonely, "ko")
	return [sim, s, victim, lonely]

func _initialize() -> void:
	var scene: Array = _scene(true); var sim = scene[0]; var s: Dictionary = scene[1]; var victim: Dictionary = scene[2]; var lonely: Array = scene[3]
	check("carry" in Context.options(s, int(victim.id)).map(func(o): return o.id), "A body can be carried")
	Context.perform(sim, int(victim.id), "carry")
	check(Carrying.carried(s) == int(victim.id), "Picked up")
	# Walk away: the body comes too; no running, no shooting.
	var route: Dictionary = Nav.request_path(s, s.entities[str(s.player)].cell, [lonely[0] + 12, lonely[1]])
	s.player_path = route.path
	for i in range(80): sim.step()
	check(s.entities[str(victim.id)].cell == s.entities[str(s.player)].cell and s.entities[str(s.player)].cell != [lonely[0] + 1, lonely[1]], "The body moves with you")
	check(not sim._can_run_route(), "No running with a body over your shoulder")
	sim.submit("shotgun_toggle"); sim.step()
	check(str(s.player_control.notice).begins_with("Put the body down"), "No reaching for the gun either")
	# F puts them down where you stand.
	sim.submit("interact", {}); sim.step()
	check(Carrying.carried(s) == 0 and s.entities[str(victim.id)].cell == s.entities[str(s.player)].cell, "F puts the body down here")
	# Hidden away from everyone: not found in half a day.
	s.entities[str(s.player)].cell = s.entities[str(s.settlements["1"].warehouse)].cell.duplicate()
	for i in range(3000): sim.step()
	check(not bool(victim.get("found", false)), "A body hidden away isn't found")
	# Left where people are: found.
	var square: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	s.entities[str(victim.id)].cell = [square[0], square[1] + 3]
	var found_at := -1
	for i in range(600):
		sim.step()
		if bool(victim.get("found", false)): found_at = i; break
	check(found_at >= 0, "A body left in the square is found (after %d ticks)" % found_at)
	check(load("res://sim/world/chronicle.gd").entries(s).any(func(e): return e.kind == "body_found"), "...and it's news")
	# Seen carrying a body: someone runs for the sheriff.
	scene = _scene(true); sim = scene[0]; s = scene[1]; victim = scene[2]; lonely = scene[3]
	Context.perform(sim, int(victim.id), "carry")
	var onlooker: Dictionary = {}
	for npc in s.residents.values():
		if npc.id != victim.id and npc.occupation not in ["Sheriff", "Child", "Trader"]: onlooker = npc; break
	s.entities[str(onlooker.id)].cell = [lonely[0] + 4, lonely[1]]
	for i in range(70): sim.step(); s.entities[str(onlooker.id)].cell = [lonely[0] + 4, lonely[1]] if onlooker.get("reporting", {}).is_empty() else s.entities[str(onlooker.id)].cell
	check(not onlooker.get("reporting", {}).is_empty() or load("res://sim/law/law.gd").wanted_hours(s, 1) > 0, "Someone who sees you with a body raises the alarm")
	# Out cold, not dead: they come round on your shoulder and struggle free.
	scene = _scene(false); sim = scene[0]; s = scene[1]; victim = scene[2]
	Context.perform(sim, int(victim.id), "carry")
	var freed := -1
	for i in range(Brawl.KO_TICKS + 100):
		sim.step()
		if Carrying.carried(s) == 0: freed = i; break
	check(freed > 0 and int(victim.health) > 0, "Someone knocked out comes round and struggles free (after %d ticks)" % freed)
	# Save, load and continue while carrying.
	scene = _scene(true); sim = scene[0]; s = scene[1]; victim = scene[2]
	Context.perform(sim, int(victim.id), "carry")
	var copy := Sim.new(); copy.restore(sim.snapshot())
	for i in range(120): sim.step(); copy.step()
	check(sim.state_hash() == copy.state_hash(), "Save, load and continue while carrying gives the same world")
	print("Carrying: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)
