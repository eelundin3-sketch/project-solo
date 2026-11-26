extends SceneTree
## How townsfolk take being attacked. Punched, a "confront" person stands up to you; stay close and
## they run for the sheriff, back off and they let it go. A "fighter" hits back. A "timid" one flees
## calling for help. After a shooting nobody from the law saw, once it's quiet one witness runs to
## the sheriff and the stranger is wanted. Temperament is fixed per person (deterministic).
const Sim = preload("res://sim/core/simulation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Law = preload("res://sim/law/law.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

## Someone of `temper` in town 1, moved with the player to a quiet spot far from the sheriffs.
func setup(temper: String) -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var keys: Array = s.residents.keys()
	keys.sort()
	var npc: Dictionary = {}
	for key in keys:
		var r: Dictionary = s.residents[key]
		if int(r.settlement) == 1 and r.occupation not in ["Sheriff", "Child", "Trader"] and Brawl.temperament(r) == temper: npc = r; break
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var far: Array = []
	for dx in range(40, 70):
		var c: Array = [store[0] - dx, store[1] + 6]
		if World.walkable(s, c) and World.walkable(s, [c[0] + 1, c[1]]) and World.inside_building(s, c) == 0: far = c; break
	s.entities[str(npc.id)].cell = far.duplicate()
	s.entities[str(s.player)].cell = [far[0] + 1, far[1]]
	npc.goal = ""
	npc.path = []
	away_sheriffs(s)
	return [sim, s, npc]

## Out of sight: the town's sheriffs are off at the far edge of town (so only townsfolk see things).
func away_sheriffs(s: Dictionary) -> void:
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var k := 0
	for sheriff in Law.sheriffs(s, 1):
		for dx in range(60, 90):
			var c: Array = [store[0] + dx, store[1] - 20 + k]
			if World.walkable(s, c): s.entities[str(sheriff.id)].cell = c; break
		sheriff.goal = ""
		sheriff.path = []
		sheriff.work_pause_until = s.tick + 100000
		k += 2

func punch(sim, s: Dictionary, npc: Dictionary) -> void:
	Brawl.on_player_hit(sim, npc, s.entities[str(npc.id)], "punch", [-1, 0])

func _initialize() -> void:
	# Confront, and you stay: they go for the sheriff.
	var a: Array = setup("confront")
	var sim = a[0]; var s: Dictionary = a[1]; var npc: Dictionary = a[2]
	check(not npc.is_empty(), "Found a confronter")
	punch(sim, s, npc)
	check(npc.get("brawl", {}).is_empty(), "A confronter doesn't swing back")
	check(npc.get("reporting", {}).has("hold_until"), "They stand up to you first")
	var start: Array = s.entities[str(npc.id)].cell.duplicate()
	for i in range(Brawl.CONFRONT_TICKS + 40):
		s.entities[str(s.player)].cell = [start[0] + 1, start[1]]
		sim.step()
	check(not npc.get("reporting", {}).is_empty() and not npc.reporting.has("hold_until"), "You stayed close: they set off for the sheriff")
	check(s.entities[str(npc.id)].cell != start, "...and they're on their way")

	# Confront, and you back off: they let it go.
	var b: Array = setup("confront")
	var sim_b = b[0]; var s_b: Dictionary = b[1]; var npc_b: Dictionary = b[2]
	punch(sim_b, s_b, npc_b)
	var at: Array = s_b.entities[str(npc_b.id)].cell
	var away: Array = [at[0] + 8, at[1]] if World.walkable(s_b, [at[0] + 8, at[1]]) else [at[0], at[1] + 8]
	for i in range(20):
		s_b.entities[str(s_b.player)].cell = away
		sim_b.step()
	check(npc_b.get("reporting", {}).is_empty(), "You backed off: they let it go")
	check(Law.wanted_hours(s_b, 1) == 0, "...and you're not wanted")

	# A fighter hits back.
	var c: Array = setup("fighter")
	punch(c[0], c[1], c[2])
	check(not c[2].get("brawl", {}).is_empty(), "A fighter comes at you")

	# A timid one flees.
	var d: Array = setup("timid")
	punch(d[0], d[1], d[2])
	check(c[2].get("brawl", {}).is_empty() == false and d[2].get("brawl", {}).is_empty(), "The timid one doesn't fight")
	check(not d[2].get("fear", {}).is_empty() or not d[2].get("reporting", {}).is_empty(), "The timid one flees or runs for help")

	# Same person, same temperament, every game.
	var e: Array = setup("confront")
	check(Brawl.temperament(e[2]) == Brawl.temperament(a[2]) and int(e[2].id) == int(a[2].id), "Temperament is fixed per person")

	# A shooting in town: the sheriffs come, you leave before they get you; once it's quiet a
	# witness runs to tell them, and you're wanted.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 11 * 600
	var store: Array = s2.entities[str(s2.settlements["1"].warehouse)].cell
	s2.entities[str(s2.player)].cell = [store[0], store[1] + 4]
	away_sheriffs(s2)
	s2.shotgun.equipped = true; s2.shotgun.loaded = 5; s2.shotgun.last_shot = -1000
	sim2.submit("shotgun_fire", {"direction": [0, 1000]})
	sim2.step()
	var scared := 0
	for npc2 in s2.residents.values():
		if not npc2.get("fear", {}).is_empty(): scared += 1
	check(scared > 0, "Townsfolk who saw it run for cover")
	s2.entities[str(s2.player)].cell = [store[0] + 130, store[1]]   # gone, well away
	var runner := false
	for i in range(3000):
		sim2.step()
		for npc2 in s2.residents.values():
			if str(npc2.get("reporting", {}).get("kind", "")) == "discharge": runner = true
		if Law.wanted_hours(s2, 1) > 0: break
	check(runner, "Once it's quiet, a witness runs to tell the sheriff")
	check(Law.wanted_hours(s2, 1) > 0, "...and the stranger is wanted for it")
	print("Civilian reactions: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
