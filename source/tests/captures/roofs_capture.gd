extends SceneTree
## Roofs: a town from outside (roofs on), the player inside a house (that roof lifted), and the
## overview zoom (roofs only, no player marker). Writes PNGs to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func shot(main: Node, at: Vector2, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at
	camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	main.get_node("WorldView").snap_visuals()
	for i in range(12):
		main.get_node("WorldView").animate(0.05, false, 1)
		await process_frame
	await RenderingServer.frame_post_draw
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	await shot(main, Vector2(store[0], store[1] + 4) * 24, 0.8, "roofs-outside")
	# Inside the first home in town.
	var World = load("res://sim/world/world_db.gd")
	var home: Dictionary = {}
	for b in World.of_kind(s, "home"):
		if int(b.settlement) == 1 and home.is_empty(): home = b
	var r: Rect2i = World.building_rect(home)
	var inside: Array = home.door.duplicate()
	for dy in range(1, 6):
		var c: Array = [home.door[0], home.door[1] - dy]
		if World.walkable(s, c) and World.inside_building(s, c) == int(home.id): inside = c; break
	s.entities[str(s.player)].cell = inside
	await shot(main, Vector2(inside[0], inside[1]) * 24, 1.2, "roofs-inside")
	await shot(main, Vector2(store[0], store[1]) * 24, 0.2, "roofs-overview")
	quit()
