extends SceneTree
## Night lighting (milestone 5, V1): street lamps on a timer, Light.level near and far, the
## player's lantern, the view's light list cap, and saves (including old saves without lamps).
const Sim = preload("res://sim/core/simulation.gd")
const Light = preload("res://sim/world/light.gd")
const World = preload("res://sim/world/world_db.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
const NightLayer = preload("res://view/world/night_layer.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var lamps: Array = World.of_kind(s, "street_lamp")
	check(lamps.size() >= 9, "Every town has street lamps (found %d)" % lamps.size())
	var towns := {}
	for lamp in lamps:
		towns[int(lamp.settlement)] = true
		check(World.walkable(s, lamp.cell) and World.inside_building(s, lamp.cell) == 0, "A lamp stands on open ground, not in a building")
	check(towns.size() == s.settlements.size(), "Each town has its own lamps")

	var day := 14400 * 2
	s.tick = day + 20 * 600
	check(Light.lamps_lit(s), "Lamps are lit at 20:00")
	s.tick = day + 6 * 600
	check(not Light.lamps_lit(s), "Lamps are out at 06:00")
	s.tick = day + 12 * 600
	check(Light.level(s, lamps[0].cell) == 100, "Noon is full light everywhere")

	s.tick = day + 23 * 600
	var near: int = Light.level(s, lamps[0].cell)
	var far_cell: Array = [lamps[0].cell[0] + 40, lamps[0].cell[1] + 40]
	var far: int = Light.level(s, far_cell)
	check(near >= 60, "Next to a lit lamp it is bright at night (%d)" % near)
	check(far <= 20, "Far from any lamp it is dark at night (%d)" % far)

	# The lantern lights the player's surroundings while it is in hand.
	var player_cell: Array = s.entities[str(s.player)].cell
	var before: int = Light.level(s, player_cell)
	sim.submit("hold_item", {"item": "lantern"})
	sim.step()
	check(Light.lantern_on(sim.state), "Holding the lantern lights it")
	check(Light.level(sim.state, player_cell) > before + 30 or Light.level(sim.state, player_cell) == 100, "The lantern raises the light level around you")
	check(Checks.validate(sim.state).is_empty(), "Invariants hold with lamps and a lantern")

	# Save and load give the same world, lamps included.
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	check(World.of_kind(copy.state, "street_lamp").size() == lamps.size(), "Lamps survive a reload")

	# An old save with no lamps gets them on load.
	var old: Dictionary = sim.snapshot()
	for key in old.entities.keys():
		if old.entities[key].kind == "street_lamp":
			var lamp: Dictionary = old.entities[key]
			old.entities.erase(key)
			for chunk in old.world.chunks.values(): chunk.entities.erase(int(lamp.id))
	World.entity_serial += 1
	var upgraded := Sim.new()
	upgraded.restore(old)
	check(World.of_kind(upgraded.state, "street_lamp").size() == lamps.size(), "An old save gets the same street lamps on load")
	check(Checks.validate(upgraded.state).is_empty(), "Invariants hold after the upgrade")

	# The view never sends more than 64 lights, even with the whole map in view.
	var night: Node2D = NightLayer.new()
	root.add_child(night)
	night.simulation = sim
	sim.state.tick = day + 22 * 600
	night.update(1.0, Rect2(Vector2(-96, -84) * 24.0, Vector2(582, 420) * 24.0), 0.0)
	check(night.visible and night.darkness > 0.5, "It is dark at 22:00")
	check(night.lights.size() <= 64 and night.lights.size() > 0, "The light list is capped at 64 (%d)" % night.lights.size())
	sim.state.tick = day + 12 * 600
	night.update(1.0, Rect2(0, 0, 100, 100), 0.0)
	check(not night.visible, "No night layer at noon")

	print("Light: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
