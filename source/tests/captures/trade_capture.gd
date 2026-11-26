extends SceneTree
## Screenshot of the trade window at a market tent once its keeper has hurried over, after a
## haggle, then its Talk tab after asking about work. Writes trade_window.png and
## talk_window.png to SOLO_SHEET_DIR.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var out := OS.get_environment("SOLO_SHEET_DIR")
	if out.is_empty(): out = OS.get_temp_dir()
	var main: Node = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	for warm in range(5): await process_frame
	main.menu_active = false
	if main.menu != null: main.menu.visible = false
	var sim = main.simulation
	var s: Dictionary = sim.state
	s.tick = 14400 + 10 * 600
	var tent: Dictionary = {}
	for e in load("res://sim/world/world_db.gd").of_kind(s, "market_stall"):
		if e.has("keeper") and int(e.settlement) == 1: tent = e; break
	s.residents[str(tent.keeper)].sleeping = {}
	s.entities[str(s.player)].cell = load("res://sim/world/world_db.gd").Fixtures.interaction_cell(s, tent.id).duplicate()
	main.get_node("WorldView").snap_visuals()
	sim.submit("interact", {"target": tent.id})
	for i in range(80):
		sim.step()
		if load("res://sim/economy/stall_service.gd").staffed(s, tent): break
	sim.submit("haggle", {"target": tent.id}); sim.step()
	# Price trends (milestone 5): yesterday's prices were different, and Reedbank's are known.
	var Market = load("res://sim/economy/market.gd")
	Market.snapshot_trend(s)
	for key in s.markets["1"].trend: s.markets["1"].trend[key] = int(s.markets["1"].trend[key]) + (2 if key in ["food", "rye"] else -2)
	var known: Dictionary = load("res://sim/player/player_status.gd").part(s, "known_prices", {})
	var prices := {}
	for item in Market.BASE: prices[item] = {"buy": maxi(1, Market.quote(s, 1, item, true) - 4), "sell": Market.quote(s, 1, item, false) + 4}
	known["2"] = {"tick": s.tick, "prices": prices}
	main.clock.paused = true
	for settle in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("trade_window.png"))
	var window = main.player_panels.trade_window
	window.tab = "talk"
	sim.submit("context_action", {"target": int(tent.keeper), "action": "ask_work"}); sim.step()
	for settle in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("talk_window.png"))
	quit(0)
