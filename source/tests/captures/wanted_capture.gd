extends SceneTree
## Wanted: the HUD line while you're in a town that wants you, and the notice by the office door.
## Writes PNGs to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	var Law = load("res://sim/law/law.gd")
	Law.file(s, 1, "theft", load("res://sim/entities/outfits.gd").worn(s, int(s.player)), false)
	Law.file(s, 1, "assault", {}, false)
	var office: Dictionary = Law.office_of(s, 1)
	var at: Array = [office.door[0] + 2, office.door[1] + 3]
	s.entities[str(s.player)].cell = at
	var camera = main.get_node("ObserverCamera")
	camera.position = Vector2(at[0], at[1]) * 24
	camera.zoom = Vector2.ONE * 1.6
	main.refresh_view()
	main.get_node("WorldView").snap_visuals()
	for i in range(12):
		main.get_node("WorldView").animate(0.05, false, 1)
		main.refresh_view()
		await process_frame
	await RenderingServer.frame_post_draw
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	root.get_texture().get_image().save_png("%s/wanted.png" % dir)
	quit()
