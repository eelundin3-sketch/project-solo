extends SceneTree
## New poses: the governor sitting at his desk, a captive tied up at the bandit camp, a sheriff
## holding a prisoner down, and hauling them up. Writes PNGs to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func shot(main: Node, cell: Array, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = Vector2(cell[0], cell[1]) * 24
	camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	main.get_node("WorldView").snap_visuals()
	for i in range(14):
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
	var hall: Dictionary = s.entities[str(dust.town_hall)]
	await shot(main, [hall.cell[0], hall.cell[1] - 8], 2.2, "pose-sitting")
	# Tied up at the bandit camp.
	s.player_control.captive = {"since": s.tick}
	s.entities[str(s.player)].cell = load("res://sim/factions/bandits.gd").post(s)
	await shot(main, s.entities[str(s.player)].cell, 2.6, "pose-tied")
	s.player_control.captive = {}
	# Held down, then hauled up.
	var Law = load("res://sim/law/law.gd")
	var Brawl = load("res://sim/combat/brawl.gd")
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	var at: Array = s.entities[str(sheriff.id)].cell
	var spot: Array = [at[0] + 1, at[1]]
	s.entities[str(s.player)].cell = spot
	Law.file(s, 1, "theft", {}, true)
	Brawl.knockdown(s, s.player_control, spot, "fall", [1, 0])
	sheriff.arrest = {"phase": "pursue", "since": s.tick, "path_tick": -100}
	var pinned := false
	for i in range(300):
		sim.step()
		if str(sheriff.arrest.get("phase", "")) == "cuff" and s.tick - int(sheriff.arrest.since) > 15 and not pinned:
			pinned = true
			await shot(main, spot, 2.6, "pose-pinned")
		if str(sheriff.arrest.get("phase", "")) == "lift" and s.tick - int(sheriff.arrest.since) > 20:
			await shot(main, spot, 2.6, "pose-lift")
			break
	quit()
