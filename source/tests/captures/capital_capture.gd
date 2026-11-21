extends SceneTree
## Dustvale, the capital: the town house with the governor at his desk (late morning) and the
## saloon in the evening. Writes capital-town-house.png and capital-saloon.png to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func shot(main: Node, building: Dictionary, name: String) -> void:
	var fp: Array = building.footprint
	var camera = main.get_node("ObserverCamera")
	camera.position = Vector2(fp[0] + fp[2] / 2.0, fp[1] + fp[3] / 2.0) * 24
	camera.zoom = Vector2.ONE * 1.5
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
	var sim = main.simulation
	var s: Dictionary = sim.state
	var dust: Dictionary = s.settlements["3"]
	while s.tick < 11 * 600: sim.step()
	await shot(main, s.entities[str(dust.town_hall)], "capital-town-house")
	while s.tick < 20 * 600 + 30 * 10: sim.step()
	await shot(main, s.entities[str(dust.saloon)], "capital-saloon")
	quit()
