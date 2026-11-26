extends SceneTree
## Esc while playing: with nothing open it pauses the game and shows the pause menu (time stops);
## Esc again resumes, with the clock as it was. Esc closes the journal first. The menu's Save writes
## a save and Resume goes back to the game.
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void: call_deferred("run")
func esc(main: Node) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ESCAPE
	key.keycode = KEY_ESCAPE
	main._input(key)
	if not main.get_viewport().is_input_handled(): main._unhandled_input(key)
func run() -> void:
	var main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.menu_active = false
	main.world_audio.enabled = false
	main.save_dir = "user://pause_test"
	main.save_path = "user://pause_test/quick.save"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://pause_test"))
	var s: Dictionary = main.simulation.state
	check(not main.is_paused_menu(), "Playing: no pause menu")
	# The journal is open: Esc closes it first.
	main.journal.visible = true
	esc(main)
	check(not main.journal.visible and not main.is_paused_menu(), "Esc closes the journal first")
	# Nothing open: Esc pauses with the menu.
	esc(main)
	check(main.is_paused_menu() and main.clock.paused, "Esc pauses the game and shows the pause menu")
	var tick: int = s.tick
	for i in range(20): main._process(0.1)
	check(s.tick == tick, "While paused, time stands still")
	# Save from the menu.
	main._on_pause_chosen("save")
	await process_frame
	main._finish_save(true)
	check(main.pause_menu.status.text != "", "Save game reports back (%s)" % main.pause_menu.status.text)
	check(main.is_paused_menu(), "...and the menu stays open")
	# Esc resumes, the clock as it was.
	esc(main)
	check(not main.is_paused_menu() and not main.clock.paused, "Esc again resumes")
	for i in range(20): main._process(0.1)
	check(s.tick > tick, "Time runs again")
	# Paused before opening it: still paused after Resume.
	main.clock.paused = true
	esc(main)
	main._on_pause_chosen("resume")
	check(not main.is_paused_menu() and main.clock.paused, "Resume keeps a pause you set yourself")
	print("Pause menu: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
