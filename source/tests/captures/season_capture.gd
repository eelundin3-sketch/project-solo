extends SceneTree
## The land through the year (milestone 5, V2): the edge of Alder Hollow on the fourth day of each
## season, plus a wide view in autumn. Writes PNGs to SOLO_SHEET_DIR (default res://docs/screenshots).
func _initialize() -> void: call_deferred("run")
func shot(main: Node, at: Vector2, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at; camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	for i in range(10):
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
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var names := ["spring", "summer", "autumn", "winter"]
	for season in range(4):
		s.tick = load("res://sim/world/weather.gd").season_start_tick(season) + 14400 * 3 + 600 * 11
		for region in s.weather.regions.values():
			region.kind = "clear"; region.previous = "clear"; region.snow = 0; region.mud = 0
		s.weather.kind = "clear"; s.weather.previous = "clear"; s.weather.snow = 0
		await shot(main, Vector2(store[0] + 30, store[1] + 30) * 24, 0.6, "season-%s" % names[season])
	quit()
