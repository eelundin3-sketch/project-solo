extends SceneTree
## Frame strips of every home activity: the whole sequence, a frame every few ticks, close up, so each
## step can be checked by eye (stepping in, the turn, the grip, each rep, racking, getting up).
## Writes strip-<kind>.png (a grid of frames) to SOLO_SHEET_DIR.
const Activities = preload("res://sim/player/activities.gd")
func _initialize() -> void: call_deferred("run")
var main
func frame_image(center: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var size := Vector2i(220, 220)
	var at := Vector2i(int(center.x) - size.x / 2, int(center.y) - size.y / 2)
	return img.get_region(Rect2i(at, size))
func run() -> void:
	root.size = Vector2i(1280, 720)
	main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	var house: Dictionary = s.entities[str(s.player_home)]
	var world = main.get_node("WorldView")
	var camera = main.get_node("ObserverCamera")
	camera.zoom = Vector2.ONE * 3.0
	var only: String = OS.get_environment("SOLO_STRIP")
	for kind in ["squat_rack", "bench_press", "deadlift_platform", "pullup_bar", "fridge", "bed", "sofa"]:
		if only != "" and only != kind: continue
		var index := -1
		for i in range(house.furniture.size()):
			if house.furniture[i].kind == kind: index = i
		var r: Array = house.furniture[index].rect
		s.player_control.activity = {}
		s.player_needs.fatigue = 5
		s.player_status.erase("last_cold_drink") if s.has("player_status") else null
		s.entities[str(s.player)].cell = [int(r[0]), int(r[1]) + int(r[3])]
		world.snap_visuals()
		var stance: Array = Activities.STANCES[Activities.PIECES[kind]]
		var focus := Vector2(int(r[0]) + int(stance[0]), int(r[1]) + int(stance[1])) * 24 + Vector2(12 if kind == "pullup_bar" else 0, -40 if kind == "pullup_bar" else -20)
		camera.position = focus
		main.refresh_view()
		for i in range(4):
			world.animate(1.0 / 60.0, false, 1)
			await process_frame
		main.simulation.submit("interact", {"target": 0})
		var frames: Array = []
		var ticks := 0
		var limit: int = 260 if kind in ["bed", "sofa"] else 400
		while ticks < limit:
			main.simulation.step()
			ticks += 1
			for f in range(6): world.animate(1.0 / 60.0, false, 1)
			if ticks % 4 == 0:
				await process_frame
				frames.append(await frame_image(Vector2(640, 360)))
			if kind in ["bed", "sofa"] and ticks == 120: main.simulation.submit("interact", {"target": 0})   # and get up
			if Activities.stage_of(s).is_empty() and ticks > 20: break
		var cols := 10
		var rows: int = (frames.size() + cols - 1) / cols
		var sheet := Image.create(220 * cols, 220 * rows, false, Image.FORMAT_RGBA8)
		for i in range(frames.size()):
			sheet.blit_rect(frames[i], Rect2i(0, 0, 220, 220), Vector2i((i % cols) * 220, (i / cols) * 220))
		sheet.save_png("%s/strip-%s.png" % [dir, kind])
	quit()
