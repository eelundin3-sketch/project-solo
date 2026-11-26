extends SceneTree
## Your house: from outside, inside, the terrace, and each exercise and the fridge at a few moments.
## Writes house-*.png to SOLO_SHEET_DIR.
const Activities = preload("res://sim/player/activities.gd")
func _initialize() -> void: call_deferred("run")
var main
var dir: String
func snap(at: Vector2, zoom: float, name: String) -> void:
	var camera = main.get_node("ObserverCamera")
	camera.position = at
	camera.zoom = Vector2.ONE * zoom
	main.refresh_view()
	for i in range(8):
		main.get_node("WorldView").animate(1.0 / 60.0, false, 1)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/house-%s.png" % [dir, name])
func use(kind: String) -> void:
	var s: Dictionary = main.simulation.state
	var house: Dictionary = s.entities[str(s.player_home)]
	for i in range(house.furniture.size()):
		if house.furniture[i].kind == kind:
			var r: Array = house.furniture[i].rect
			s.entities[str(s.player)].cell = [int(r[0]), int(r[1]) + int(r[3])]
			Activities.start(main.simulation, i, Activities.PIECES[kind])
			return
func until(stage: String, rep: int, phase: float) -> void:
	var s: Dictionary = main.simulation.state
	for i in range(800):
		var st: Dictionary = Activities.stage_of(s)
		if st.is_empty() or (st.stage == stage and int(st.rep) >= rep and float(st.phase) >= phase): return
		main.simulation.step()
func run() -> void:
	root.size = Vector2i(1280, 720)
	main = load("res://app/main.tscn").instantiate(); root.add_child(main); main.set_process(false)
	main.world_audio.enabled = false
	main.menu_active = false
	main.follow_player = false
	var s: Dictionary = main.simulation.state
	s.tick = 14400 + 600 * 11
	s.player_needs.fatigue = 5
	dir = OS.get_environment("SOLO_SHEET_DIR")
	if dir == "": dir = "res://docs/screenshots"
	var house: Dictionary = s.entities[str(s.player_home)]
	var f: Array = house.footprint
	var centre := Vector2(int(f[0]) + 8, int(f[1]) + 2) * 24
	s.entities[str(s.player)].cell = [house.door[0], house.door[1] + 3]
	main.get_node("WorldView").snap_visuals()
	await snap(centre, 0.9, "outside")
	s.entities[str(s.player)].cell = [house.door[0], house.door[1] - 3]
	await snap(Vector2(int(f[0]) + 8, int(f[1]) + 6) * 24, 1.3, "inside")
	var terrace := Vector2(int(f[0]) + 8, int(f[1]) - 3) * 24
	for shot in [["squat_rack", "setup", 0, 0.9, "squat-1"], ["squat_rack", "rep", 1, 0.5, "squat-2"], ["bench_press", "rep", 1, 0.0, "bench-1"], ["bench_press", "rep", 1, 0.5, "bench-2"],
			["deadlift_platform", "rep", 1, 0.0, "deadlift-1"], ["deadlift_platform", "rep", 1, 0.5, "deadlift-2"], ["pullup_bar", "hang", 0, 0.8, "pullup-1"], ["pullup_bar", "rep", 1, 0.45, "pullup-2"]]:
		s.player_control.activity = {}
		s.player_needs.fatigue = 5
		use(shot[0])
		until(shot[1], int(shot[2]), float(shot[3]))
		await snap(terrace, 2.0, shot[4])
	s.player_control.activity = {}
	use("fridge")
	until("drink", 0, 0.5)
	var fridge_at: Array = s.entities[str(s.player)].cell
	await snap(Vector2(fridge_at[0], fridge_at[1]) * 24, 2.0, "fridge")
	quit()
