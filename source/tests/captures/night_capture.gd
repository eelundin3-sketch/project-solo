extends SceneTree
## Night in each town (milestone 5): lamp pools, lit windows, lanterns. Also dusk in Alder Hollow.
## Writes PNGs to SOLO_SHEET_DIR (default res://docs/screenshots). Needs a window (not --headless).
func _initialize() -> void: call_deferred("run")
func shot(main: Node, at: Vector2, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at; camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	for i in range(8):
		main.get_node("WorldView").animate(0.05, true, 1)
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
	var s: Dictionary = main.simulation.state
	s.weather = {"kind": "clear"}
	main.follow_player = false
	main.simulation.submit("hold_item", {"item": "lantern"})
	main.simulation.step()
	s.tick = 14400 * 2 + 600 * 22
	for key in ["1", "2", "3"]:
		var store: Array = s.entities[str(s.settlements[key].warehouse)].cell
		await shot(main, Vector2(store[0], store[1] + 6) * 24, 0.8, "night-%s" % s.settlements[key].name.to_lower().replace(" ", "-"))
	var player: Array = s.entities[str(s.player)].cell
	await shot(main, Vector2(player[0], player[1]) * 24, 2.0, "night-lantern")
	s.tick = 14400 * 2 + 600 * 20
	var first: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	await shot(main, Vector2(first[0], first[1] + 6) * 24, 0.8, "dusk-alder-hollow")
	quit()
