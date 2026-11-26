extends SceneTree
## Smooth walking for everyone: a person the simulation steps every few ticks (a sheriff walking up
## with his gun on you, a bandit about camp) is drawn moving the whole way at their own pace, never
## standing still between steps or dropping to idle, and stays close to where they really are; a
## runner (a step every tick) still runs at full pace.
const Sim = preload("res://sim/core/simulation.gd")
const Director = preload("res://view/actors/animation_director.gd")
const World = preload("res://sim/world/world_db.gd")
const CELL := 24.0
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

## Steps `id` one cell east every `every` ticks for `steps` steps, drawing 6 frames a tick.
func walk(s: Dictionary, id: int, every: int, steps: int) -> Dictionary:
	var director = Director.new()
	var entity: Dictionary = s.entities[str(id)]
	var start: Array = entity.cell.duplicate()
	var stops := 0
	var idles := 0
	var worst_lag := 0.0
	var frames := 0
	var last := Vector2.INF
	director.update(s, 1.0 / 60.0, false, 1)
	for step in range(steps):
		for t in range(every):
			s.tick += 1
			if t == 0: entity.cell = [start[0] + step + 1, start[1]]
			for f in range(6):
				director.update(s, 1.0 / 60.0, false, 1)
				var pose: Dictionary = director.actors[str(id)]
				frames += 1
				if step >= 4 and step < steps - 1:
					if last != Vector2.INF and pose.position.distance_to(last) < 0.01: stops += 1
					if not bool(pose.moving): idles += 1
				last = pose.position
				worst_lag = maxf(worst_lag, pose.position.distance_to(Vector2(entity.cell[0], entity.cell[1]) * CELL))
	return {"stops": stops, "idles": idles, "lag": worst_lag / CELL, "pace": director.actors[str(id)].get("step_ticks", 0.0)}

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	# Someone in an open stretch: room to walk 20 cells east.
	var walker: Dictionary = {}
	for npc in s.residents.values():
		var c: Array = s.entities[str(npc.id)].cell
		var clear := true
		for dx in range(0, 22):
			if not World.walkable(s, [c[0] + dx, c[1]]): clear = false; break
		if clear and npc.occupation != "Child": walker = npc; break
	check(not walker.is_empty(), "Found room to walk")
	for npc in s.residents.values(): npc.sleeping = {}
	var slow: Dictionary = walk(s, int(walker.id), 3, 16)
	check(slow.stops == 0, "A slow walker (a step every 3 ticks) never stands still between steps (%d stopped frames)" % slow.stops)
	check(slow.idles == 0, "...and never drops to idle mid-walk (%d)" % slow.idles)
	check(slow.lag <= 1.3, "...and stays close to where they really are (%.2f cells behind)" % slow.lag)
	check(absf(float(slow.pace) - 3.0) < 0.3, "...walking at their own pace (%.2f ticks a cell)" % float(slow.pace))
	s.entities[str(walker.id)].cell = [s.entities[str(walker.id)].cell[0] - 16, s.entities[str(walker.id)].cell[1]]
	var slower: Dictionary = walk(s, int(walker.id), 4, 12)
	check(slower.stops == 0 and slower.idles == 0, "A step every 4 ticks glides too (%d stops, %d idle)" % [slower.stops, slower.idles])
	s.entities[str(walker.id)].cell = [s.entities[str(walker.id)].cell[0] - 12, s.entities[str(walker.id)].cell[1]]
	var runner: Dictionary = walk(s, int(walker.id), 1, 18)
	check(runner.lag <= 1.6, "A runner keeps up (%.2f cells behind)" % runner.lag)
	check(absf(float(runner.pace) - 1.0) < 0.3, "...at a step a tick")
	print("Slow walk: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
