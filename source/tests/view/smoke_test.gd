extends SceneTree
const Clock = preload("res://sim/core/sim_clock.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(Engine.get_version_info().major == 4 and Engine.get_version_info().minor == 6 and Engine.get_version_info().patch == 0 and Engine.get_version_info().status == "stable", "Pinned engine build")
	var main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	check(main.simulation.state.settlements["1"].population == 5 and main.simulation.state.residents.values().filter(func(r): return not r.get("garrison", false) and r.occupation not in ["Bandit", "Governor", "Barkeep"]).size() == 15, "Every town starts with five residents (plus the extra sheriffs at the office, the bandits, and the capital's governor and barkeep)")
	check(main.get_node("DebugHUD").heading.text.contains("ALDER"), "HUD displays world")
	check(main.get_node("WorldView").simulation == main.simulation, "View projects authoritative sim")
	var before: String = main.simulation.state_hash()
	main.handle_action("pause")
	main.clock.advance(5, main.simulation)
	check(main.simulation.state_hash() == before, "Pause leaves world unchanged")
	main.handle_action("speed3")
	check(main.clock.speed == 3, "Three-times speed control")
	var hud = main.get_node("DebugHUD")
	check(hud.pause_button.visible and main.bottom_bar.visible and hud.observer_panel.visible == false, "Compact play HUD keeps controls visible and tools closed")
	var local: int = main.simulation.state.residents.values().filter(func(npc): return npc.settlement == 1 and npc.health > 0).size()
	check(hud.stats.text.contains("%d local residents" % local) and hud.stats.text.contains("3×"), "HUD data still reports the local population and the current speed")
	var speed_labels: Array[String] = []
	for control in hud.pause_button.get_parent().get_children():
		if control is Button: speed_labels.append(control.text)
	check(hud.pause_button.text == "Resume" and speed_labels.has("1×") and speed_labels.has("2×") and speed_labels.has("3×"), "Top-left clock exposes resume/pause, 1x, 2x and 3x")
	main.handle_action("pause")
	main.clock.budget_usec = 1 << 30   # the per-frame time cap must not cut this check short on a slow machine
	main.clock.advance(0.1, main.simulation)
	check(main.simulation.state.tick >= 3, "3x simulation ticks")
	main.save_path = OS.get_temp_dir().path_join("solo-ui-save.dat")
	main.handle_action("save")
	var saved_hash: String = main.simulation.state_hash()
	main.simulation.step()
	main.handle_action("load")
	check(main.simulation.state_hash() == saved_hash, "Save/load UI restores authoritative state")
	var camera = main.get_node("ObserverCamera")
	camera.adjust_zoom(100)
	check(is_equal_approx(camera.zoom.x, 5.0), "Zoom upper bound")
	camera.adjust_zoom(0.001)
	check(is_equal_approx(camera.zoom.x, 0.06), "Regional zoom lower bound")
	main.clock.speed = 1
	var old_cell: Array = main.simulation.state.entities[str(main.simulation.state.player)].cell.duplicate()
	Input.action_press("walk_right")
	main._process(0.1)
	Input.action_release("walk_right")
	check(main.simulation.state.entities[str(main.simulation.state.player)].cell[0] == old_cell[0] + 1, "Mapped keyboard input moves authoritative player")
	main.handle_action("travel")
	main.simulation.step()
	check(not main.simulation.state.player_path.is_empty(), "Travel submits a path command")
	main.queue_free()
	await process_frame
	print("UI smoke: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
