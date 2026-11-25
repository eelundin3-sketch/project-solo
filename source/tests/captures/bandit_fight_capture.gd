extends SceneTree
## A bandit fight, frame by frame: positions, cover, aiming at you, firing, moving up. Writes
## bandit-fight-1..4.png to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var sim = main.simulation
	var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var camp: Array = s.bandits.cell
	var World = load("res://sim/world/world_db.gd")
	for dx in range(10, 16):
		var c: Array = [camp[0] + dx, camp[1] + 4]
		if World.walkable(s, c): s.entities[str(s.player)].cell = c; break
	s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	sim.submit("shotgun_fire", {"direction": [0, 1000]})
	var world = main.get_node("WorldView")
	var camera = main.get_node("ObserverCamera")
	var me: Array = s.entities[str(s.player)].cell
	camera.position = (Vector2(camp[0], camp[1]) + Vector2(me[0], me[1])) * 12.0
	camera.zoom = Vector2.ONE * 1.5
	main.refresh_view()
	world.snap_visuals()
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	var shot := 1
	for i in range(240):
		sim.step()
		s.player_control.knock = {}
		main.refresh_view()
		for f in range(6):
			world.animate(1.0 / 60.0, false, 1)
		if i in [30, 80, 140, 220]:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/bandit-fight-%d.png" % [dir, shot])
			shot += 1
	quit()
