extends SceneTree
## Crouching and sneaking, the woodland layout around the towns, and the sun's shadow through a day.
const Sim = preload("res://sim/core/simulation.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game()
	var s: Dictionary = sim.state
	var player: Dictionary = s.entities[str(s.player)]
	# Crouch toggles, slows walking, and a sprint stands you up (measured off the roads, where
	# walking has no road bonus: see pace.gd).
	var TownLayout = load("res://sim/world/town_layout.gd")
	for dy in range(0, 40):
		var probe: Array = [player.cell[0], player.cell[1] + dy]
		if World.walkable(s, probe) and World.walkable(s, [probe[0] + 1, probe[1]]) and not TownLayout.on_road(s, probe) and not TownLayout.on_road(s, [probe[0] + 1, probe[1]]):
			player.cell = probe
			break
	sim.submit("crouch_toggle"); sim.step()
	check(s.player_control.crouching, "X crouches")
	var start: Array = player.cell.duplicate()
	sim.submit("move_player", {"direction": [1, 0]}); sim.step()
	check(player.cell != start and s.player_control.next_move - s.tick == 3, "Crouched steps are slower (%d ticks)" % (s.player_control.next_move - s.tick))
	for t in range(4): sim.step()
	sim.submit("move_player", {"direction": [1, 0], "run": true}); sim.step()
	check(not s.player_control.crouching, "Sprinting stands you up")
	sim.submit("crouch_toggle"); sim.step()
	sim.submit("crouch_toggle"); sim.step()
	check(not s.player_control.crouching, "X again stands up")
	# Sneaking past a sleeper: crouched theft does not wake them; standing theft does.
	var sleeper: Dictionary = {}
	for npc in s.residents.values():
		if npc.settlement == 1: sleeper = npc; break
	var Inventory = load("res://sim/inventory/inventory_store.gd")
	var Looting = load("res://sim/player/looting.gd")
	Inventory.produce(s, sleeper.id, "food", 2)
	Inventory.produce(s, sleeper.id, "bandage", 1)
	sleeper.sleeping = {"bed": 0, "since": s.tick, "approach": s.entities[str(sleeper.id)].cell.duplicate()}
	sleeper.job = 0
	player.cell = [s.entities[str(sleeper.id)].cell[0] + 1, s.entities[str(sleeper.id)].cell[1]]
	s.player_control.crouching = true
	Looting.take(s, sleeper.id, "food")
	check(not sleeper.get("sleeping", {}).is_empty() and sleeper.get("brawl", {}).is_empty(), "A crouched thief does not wake the sleeper")
	s.player_control.crouching = false
	player.cell = [s.entities[str(sleeper.id)].cell[0] + 1, s.entities[str(sleeper.id)].cell[1]]
	Looting.take(s, sleeper.id, "bandage")
	check(sleeper.get("sleeping", {}).is_empty() and not sleeper.get("brawl", {}).is_empty(), "A standing thief wakes them and they fight")
	# Forests: many trees, none crowding a building, door, field or the road.
	var trees: Array = s.entities.values().filter(func(e: Dictionary) -> bool: return e.kind == "tree")
	check(trees.size() >= 1000, "Real forests: %d trees" % trees.size())
	var close := 0
	for building in s.entities.values():
		if not building.has("footprint"): continue
		var near := World.building_rect(building).grow(4)
		for tree in trees:
			if near.has_point(Vector2i(tree.cell[0], tree.cell[1])): close += 1
	check(close == 0, "No tree stands within four cells of a building (%d do)" % close)
	var on_road := 0
	for tree in trees:
		if load("res://sim/world/town_layout.gd").on_road(s, tree.cell): on_road += 1
	check(on_road == 0, "The road and its verges stay clear (%d trees on it)" % on_road)
	# The sun: long shadows to the left in the morning, short at noon, long to the right in the evening, none at night.
	var view = load("res://view/world/world_view.gd").new()
	var morning: Dictionary = view.sun_shadow(14400 + 7 * 600)
	var noon: Dictionary = view.sun_shadow(14400 + 13 * 600)      # the sun is highest at 13:00 (DayClock)
	var evening: Dictionary = view.sun_shadow(14400 + 19 * 600)
	var night: Dictionary = view.sun_shadow(14400 + 23 * 600)
	check(morning.vector.x < -1.0, "Morning shadows reach left (%s)" % str(morning.vector))
	check(evening.vector.x > 1.0, "Evening shadows reach right (%s)" % str(evening.vector))
	check(noon.vector.length() < morning.vector.length() * 0.5 and absf(noon.vector.x) < 0.2, "Noon shadows are short (%s)" % str(noon.vector))
	check(night.strength == 0.0 and noon.strength > morning.strength * 0.99, "Shadows fade out at night")
	view.free()
	print("Crouch, forest and sun: %s" % ("PASS" if failures == 0 else "FAIL")); quit(failures)
