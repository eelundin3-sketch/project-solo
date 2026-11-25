extends SceneTree
## The pause menu over the game. Writes pause.png to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main._finish_intro()
	var s: Dictionary = main.simulation.state
	var cell: Array = s.entities[str(s.player)].cell
	main.get_node("ObserverCamera").position = Vector2(cell[0], cell[1]) * 24
	main.get_node("ObserverCamera").zoom = Vector2.ONE * 1.6
	main.refresh_view()
	main.get_node("WorldView").snap_visuals()
	for i in range(8):
		main.get_node("WorldView").animate(0.05, false, 1)
		await process_frame
	main.open_pause_menu()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	root.get_texture().get_image().save_png("%s/pause.png" % dir)
	quit()
