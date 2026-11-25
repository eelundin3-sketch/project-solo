extends SceneTree
## Roofs: outside, every finished building has a roof; inside, the roof of your own building is
## lifted; people inside a roofed building are not drawn; zoomed far out the building floors are
## hidden and there is no "YOU" marker.
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void: call_deferred("run")
func frames(main: Node, zoom: float, at: Vector2) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at
	camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	var world = main.get_node("WorldView")
	world.snap_visuals()
	for i in range(4):
		world.animate(0.05, false, 1)
		await process_frame
func run() -> void:
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var world = main.get_node("WorldView")
	var s: Dictionary = main.simulation.state
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var player: Dictionary = s.entities[str(s.player)]
	player.cell = [store[0], store[1] + 4]
	while World.inside_building(s, player.cell) != 0: player.cell = [player.cell[0], player.cell[1] + 1]
	await frames(main, 0.8, Vector2(player.cell[0], player.cell[1]) * 24)
	var roofs = world.roofs_layer
	var finished := 0
	var roofed := 0
	for b in World.buildings(s):
		if not b.has("footprint"): continue
		finished += 1
		if roofs.nodes.has(int(b.id)) and roofs.nodes[int(b.id)].visible: roofed += 1
	check(finished > 0 and roofed == finished, "Outside, every finished building is roofed (%d of %d)" % [roofed, finished])

	# Someone inside a roofed building is not drawn: put a nearby townsperson indoors.
	var shop: Dictionary = s.entities[str(s.settlements["1"].warehouse)]
	var indoor: Array = []
	for dy in range(1, 8):
		var c: Array = [shop.door[0], shop.door[1] - dy]
		if World.walkable(s, c) and World.inside_building(s, c) == int(shop.id): indoor = c; break
	var visitor := ""
	for key in world.character_models:
		if str(key) != str(s.player) and s.entities.get(str(key), {}).get("kind", "") == "resident": visitor = str(key); break
	check(visitor != "" and not indoor.is_empty(), "Found a townsperson and a floor cell in the store")
	if visitor != "" and not indoor.is_empty():
		s.entities[visitor].cell = indoor
		await frames(main, 0.8, Vector2(player.cell[0], player.cell[1]) * 24)
		check(not world.character_models[visitor].visible, "A person inside a roofed building is not drawn")
		check(roofs.covered(s, visitor, Vector2(indoor[0], indoor[1]) * 24), "The roof covers that person")

	# Inside a home: its roof is lifted, the others stay.
	var home: Dictionary = {}
	for b in World.of_kind(s, "home"):
		if int(b.settlement) == 1 and home.is_empty(): home = b
	var inside: Array = []
	for dy in range(1, 6):
		var c: Array = [home.door[0], home.door[1] - dy]
		if World.walkable(s, c) and World.inside_building(s, c) == int(home.id): inside = c; break
	check(not inside.is_empty(), "Found a floor cell inside a home")
	player.cell = inside
	await frames(main, 1.2, Vector2(inside[0], inside[1]) * 24)
	check(not roofs.nodes[int(home.id)].visible, "Inside your building its roof is lifted")
	var others_on := true
	for id in roofs.nodes:
		if int(id) != int(home.id) and not roofs.nodes[id].visible: others_on = false
	check(others_on, "Every other building keeps its roof")
	check(world.character_models[str(s.player)].visible, "You are drawn inside your building")

	# Zoomed far out: roofs only, no floors, no player marker.
	await frames(main, 0.2, Vector2(store[0], store[1]) * 24)
	check(world.is_far(), "Zoom 0.2 is the far view")
	check(roofs.nodes[int(home.id)].visible, "Far out, even your own building shows its roof")
	var floors_shown := 0
	for key in world.decor_nodes:
		if str(key).begins_with("building:") and world.decor_nodes[key].visible: floors_shown += 1
	check(floors_shown == 0, "Far out, no building floor images are drawn (%d shown)" % floors_shown)
	var source: String = FileAccess.get_file_as_string("res://view/world/world_view.gd")
	check(not source.contains("\"YOU\""), "No \"YOU\" label in the world view")
	print("Roofs: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
