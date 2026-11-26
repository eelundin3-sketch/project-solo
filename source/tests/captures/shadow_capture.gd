extends SceneTree
## Light and shadows through the day: the same corner of Alder Hollow from dawn to night. The sun
## rises in the east at 05:00, is highest at 13:00 and sets in the west at 21:00 (DayClock).
## Writes PNGs to SOLO_SHEET_DIR (default res://docs/screenshots).
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	var sim = main.simulation; var s: Dictionary = sim.state
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	for hour in [5.0, 8.0, 13.0, 18.0, 21.0, 23.5]:
		s.tick = int(hour * 600.0) + 14400
		s.weather = {"kind": "clear"}
		main.refresh_view()
		main.get_node("WorldView").animate(0.016, true, 1)
		for i in range(4):
			main.get_node("WorldView").animate(0.016, true, 1)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/shadows-%02dh%02d.png" % [dir, int(hour), int(fmod(hour, 1.0) * 60)])
	quit()
