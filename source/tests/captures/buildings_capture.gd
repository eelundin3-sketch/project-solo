extends SceneTree
## Each kind of building from the front (what it's for, on its face): writes building-<kind>.png to
## SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	var World = load("res://sim/world/world_db.gd")
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	s.entities[str(s.player)].cell = [-90, -80]   # out of the way
	for kind in ["home", "office", "warehouse", "market", "saloon", "town_hall", "bakery", "forge", "sawmill"]:
		var list: Array = World.of_kind(s, kind).filter(func(b): return b.has("footprint"))
		if list.is_empty(): continue
		var b: Dictionary = list[0]
		var r: Rect2i = World.building_rect(b)
		var camera = main.get_node("ObserverCamera")
		camera.position = Vector2(r.get_center().x, r.end.y - 2) * 24
		camera.zoom = Vector2.ONE * 1.6
		main.refresh_view()
		main.get_node("WorldView").snap_visuals()
		for i in range(6):
			main.get_node("WorldView").animate(0.05, false, 1)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/building-%s.png" % [dir, kind])
	quit()
