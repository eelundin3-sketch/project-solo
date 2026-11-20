extends SceneTree
## Weather you can see (milestone 5, W1): rain with wet ground and muddy roads, fog, snow, and a
## dry Dustvale beside a rainy Reedbank. Writes PNGs to SOLO_SHEET_DIR (default res://docs/screenshots).
func _initialize() -> void: call_deferred("run")
func set_weather(s: Dictionary, kind: String, mud: int, snow: int, only_town: String = "") -> void:
	for key in s.weather.regions:
		var region: Dictionary = s.weather.regions[key]
		var here: bool = only_town == "" or s.settlements[key].name == only_town
		region.kind = kind if here else "clear"; region.previous = region.kind; region.since = s.tick - 1000
		region.mud = mud if here else 0; region.snow = snow if here else 0
	s.weather.kind = "clear"
func shot(main: Node, at: Vector2, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at; camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	for i in range(30):
		main.get_node("WorldView").animate(1.0 / 30.0, false, 1)
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
	s.tick = 14400 * 2 + 600 * 11
	var reed: Array = s.entities[str(s.settlements["2"].warehouse)].cell
	var dust: Array = s.entities[str(s.settlements["3"].warehouse)].cell
	set_weather(s, "rain", 85, 0)
	await shot(main, Vector2(reed[0], reed[1] + 6) * 24, 0.8, "weather-rain-reedbank")
	set_weather(s, "fog", 0, 0)
	await shot(main, Vector2(reed[0], reed[1] + 6) * 24, 0.8, "weather-fog-reedbank")
	set_weather(s, "snow", 0, 80)
	await shot(main, Vector2(reed[0], reed[1] + 6) * 24, 0.8, "weather-snow-reedbank")
	set_weather(s, "rain", 85, 0, "Reedbank")
	await shot(main, (Vector2(reed[0], reed[1]) + Vector2(dust[0], dust[1])) * 12, 0.25, "weather-wet-reedbank-dry-dustvale")
	quit()
