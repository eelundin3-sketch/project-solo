extends SceneTree
## The bandit camp by day (lounging by the fire) and by night (asleep by the tents, firelight).
## Writes bandits-day.png and bandits-night.png to SOLO_SHEET_DIR (default res://docs/screenshots).
func _initialize() -> void: call_deferred("run")
func shot(main: Node, name: String) -> void:
	var s: Dictionary = main.simulation.state
	var camp: Array = s.bandits.cell
	var camera = main.get_node("ObserverCamera")
	camera.position = Vector2(camp[0], camp[1] - 1) * 24
	camera.zoom = Vector2.ONE * 1.3
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
	s.tick = 14400 + 600 * 15 - 300
	for i in range(300): sim.step()
	await shot(main, "bandits-day")
	s.tick = 14400 * 2 + 600 * 23 - 300
	for i in range(300): sim.step()
	await shot(main, "bandits-night")
	quit()
