extends SceneTree
## The bakery oven and the forge at work: flue pipes through the back wall and smoke rising
## outside. Writes smoke-bakery.png and smoke-forge.png to SOLO_SHEET_DIR (default res://docs/screenshots).
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	var view = main.get_node("WorldView")
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	for kind in ["bakery", "forge"]:
		var shop: Dictionary = {}
		for w in s.workshops.values():
			if w.get("kind", "") == kind and int(w.settlement) == 2: shop = w; break
		var entity: Dictionary = s.entities[str(shop.id)]
		var camera = main.get_node("ObserverCamera")
		camera.position = Vector2(entity.fixtures[0].rect[0] + 2, entity.fixtures[0].rect[1] - 1) * 24
		camera.zoom = Vector2.ONE * 2.0
		main.refresh_view()
		for i in range(20):
			view.animate(1.0 / 30.0, false, 1)
			view.fixture_motion.running[str(shop.id)] = true
			view.fixture_motion.phases[str(shop.id)] = float(i) * 3.0 + 40.0
			for node in view.depth_objects.values():
				if node.object_kind == "fixture" and node.entity_id == int(shop.id): node.queue_redraw()
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/smoke-%s.png" % [dir, kind])
	quit()
