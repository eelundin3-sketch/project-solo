extends SceneTree
## A new game's first moments: you start at home, mid-activity. One picture per start choice,
## a few seconds in, with the game running as normal. Writes home-start-<kind>.png to SOLO_SHEET_DIR.
const Activities = preload("res://sim/player/activities.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var dir: String = OS.get_environment("SOLO_SHEET_DIR")
	root.size = Vector2i(1280, 720)
	for choice in range(Activities.HOME_STARTS.size()):
		var main = load("res://app/main.tscn").instantiate()
		root.add_child(main)
		main.world_audio.enabled = false
		main.menu_active = false
		main.follow_player = true
		Activities.begin_at_home(main.simulation, choice)
		var s: Dictionary = main.simulation.state
		main.get_node("ObserverCamera").position = Vector2(s.entities[str(s.player)].cell[0], s.entities[str(s.player)].cell[1]) * 24.0
		main.get_node("ObserverCamera").zoom = Vector2.ONE * 2.0
		for i in range(150): await process_frame
		await RenderingServer.frame_post_draw
		var kind: String = Activities.HOME_STARTS[choice]
		root.get_texture().get_image().save_png("%s/home-start-%s.png" % [dir, kind])
		print("%s: stage %s" % [kind, str(Activities.stage_of(s))])
		main.queue_free()
		await process_frame
	quit(0)
