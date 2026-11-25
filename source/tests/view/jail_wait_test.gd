extends SceneTree
## "Wait it out" in jail fast-forwards, then stops with two in-game minutes of the sentence left,
## back at the speed you had, still in the cell; you then see the release at normal speed.
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.menu_active = false
	main.world_audio.enabled = false
	var s: Dictionary = main.simulation.state
	var Law = load("res://sim/law/law.gd")
	var office: Dictionary = Law.office_of(s, 1)
	s.entities[str(s.player)].cell = Law.cell_spot(office)
	s.player_control.jail = {"office": office.id, "until": s.tick + 600, "hours": 1, "rect": Law.cell_rect(office), "sheriff": Law.sheriffs(s, 1)[0].id, "town": 1, "crimes": ["theft"]}
	main.clock.speed = 1
	main._skip_ahead()
	check(main.skipping and main.clock.speed > 1, "Wait it out: time runs fast")
	var guard := 0
	while main.skipping and guard < 5000:
		main._process(1.0 / 60.0)
		guard += 1
	var left: int = int(s.player_control.jail.get("until", s.tick)) - int(s.tick)
	check(not main.skipping and main.clock.speed == 1, "It stops, back at your speed")
	check(left >= 18 and left <= 29, "...with two minutes left, give or take a frame of fast-forward (%d ticks)" % left)
	check(not s.player_control.get("jail", {}).is_empty() and Law.inside_cell(s, s.entities[str(s.player)].cell), "...still in the cell")
	check(str(s.player_control.get("notice", "")) == "Two minutes left.", "...and says so")
	print("Jail wait: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
