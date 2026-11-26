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
	# A long sentence (a day): caught up behind a card in a few seconds, the world simulated exactly.
	s.player_control.jail = {}
	s.player_control.notice = ""
	main.clock.speed = 1
	var twin = load("res://sim/core/simulation.gd").new()
	twin.restore(main.simulation.snapshot())
	s.entities[str(s.player)].cell = Law.cell_spot(office)
	var start_tick: int = s.tick
	s.player_control.jail = {"office": office.id, "until": s.tick + 14400, "hours": 24, "rect": Law.cell_rect(office), "sheriff": Law.sheriffs(s, 1)[0].id, "town": 1, "crimes": ["murder"]}
	twin.state.entities[str(twin.state.player)].cell = Law.cell_spot(office)
	twin.state.player_control.jail = s.player_control.jail.duplicate(true)
	main._wait_out()
	check(main.catching_up and main.catch_up_card.visible, "A day's sentence: time passes behind a card")
	var frames := 0
	var started := Time.get_ticks_msec()
	while main.catching_up and frames < 20000:
		main._process(1.0 / 60.0)
		frames += 1
	var spent: float = float(Time.get_ticks_msec() - started) / 1000.0
	var left2: int = int(s.player_control.jail.get("until", s.tick)) - int(s.tick)
	check(not main.catching_up and not main.catch_up_card.visible, "...the card goes when it's done")
	check(left2 == main.JAIL_WAIT_STOP, "...stopping with two minutes left (%d ticks)" % left2)
	check(spent < 30.0, "...in seconds, not minutes (%.1f s, %d frames)" % [spent, frames])
	for i in range(s.tick - start_tick): twin.step()
	twin.state.player_control.notice = s.player_control.notice   # the "Two minutes left." line is the only difference
	check(twin.state_hash() == main.simulation.state_hash(), "The world caught up is exactly the world stepped normally")
	print("Jail wait: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
