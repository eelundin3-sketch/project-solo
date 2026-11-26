extends Node2D
const Simulation = preload("res://sim/core/simulation.gd")
const Clock = preload("res://sim/core/sim_clock.gd")
const Save = preload("res://sim/persistence/save_manager.gd")
const Activities = preload("res://sim/player/activities.gd")
const Settings = preload("res://app/input_settings.gd")
const PlayerPanels = preload("res://view/ui/player_panels.gd")
const Health = preload("res://sim/combat/body_health.gd")
const PlayerActions = preload("res://sim/player/player_actions.gd")
const Audio = preload("res://view/audio/world_audio.gd")
const ActionPointer = preload("res://view/ui/action_pointer.gd")
const Cover = preload("res://sim/combat/cover.gd")
const MapOverlay = preload("res://view/ui/map_overlay.gd")
const MedievalMap = preload("res://view/ui/medieval_map.gd")
const SaveMigration = preload("res://app/save_migration.gd")
const SaveSlots = preload("res://app/save_slots.gd")
const Moodles = preload("res://view/ui/moodles.gd")
const BottomBar = preload("res://view/ui/bottom_bar.gd")
const PerfOverlay = preload("res://view/ui/perf_overlay.gd")
const ContextMenu = preload("res://view/ui/context_menu.gd")
const ContextActions = preload("res://sim/player/context_actions.gd")
const MainMenu = preload("res://view/ui/main_menu.gd")
const JournalWindow = preload("res://view/ui/journal_window.gd")
const PauseMenu = preload("res://view/ui/pause_menu.gd")
const KnockoutScreen = preload("res://view/ui/knockout_screen.gd")
const Law = preload("res://sim/law/law.gd")
const Probe = preload("res://sim/diagnostics/perf_probe.gd")
const CELL: float = 24.0
var player_panels: CanvasLayer
var world_audio: Node2D
var simulation := Simulation.new()
var clock := Clock.new()
var follow_player: bool = true
var kick_seen: int = 0
var right_down_msec: int = 0
var peek_on: bool = false
var peek_octant: int = -1
var lean_offset: Vector2 = Vector2.ZERO
var kick_offset: Vector2 = Vector2.ZERO
var last_input_tick: int = -1
var last_draw_tick: int = -1
var tick_ms: float = 0.0
var selected_id: int = 0
var last_selected_id: int = -1
var map_mode: bool = false
var map_return_zoom: Vector2 = Vector2(2, 2)
var map_return_follow: bool = true
var pending_binding: String = ""
var last_left_press: int = -10000
var last_left_position: Vector2 = Vector2.ZERO
var save_path: String = "user://project_solo.save"
var save_dir: String = "user://"
var last_autosave_day: int = -1   # the in-game day already autosaved (each morning at 06:00)
var save_thread: Thread            # a save being written in the background (one at a time)
var save_label: String = ""
var aiming: bool = false
var pointer_held: bool = false
var action_pointer: Control
var map_overlay: Control
var moodles: Control
var bottom_bar: Control
var perf: Control
var context_menu: Control
var menu: CanvasLayer
var knockout: CanvasLayer
var skipping: bool = false
const SLEEP_SPEED := 8
var medieval_map: Control
var journal: Control
var pause_menu: CanvasLayer           # Esc while playing (pause_menu.gd)
var paused_before_menu: bool = false   # the clock's state when the pause menu opened
var context_part: String = ""   # the furniture or fixture the open menu is about
var skip_previous_speed: int = 1
var menu_active: bool = false
var menu_time: float = 0.0
var intro_tween: Tween
var last_right_press: int = -10000
var last_right_position: Vector2 = Vector2.ZERO
var overlay_was_live: bool = true
var pointer_was_shown: bool = true

func _ready() -> void:
	SaveMigration.migrate()   # saves from before the game was renamed come across once
	Settings.setup()
	simulation.start_game()
	_mark_autosaved_today()
	player_panels=PlayerPanels.new()
	player_panels.simulation=simulation
	add_child(player_panels)
	var pointer_layer := CanvasLayer.new()
	pointer_layer.layer = 20
	add_child(pointer_layer)
	action_pointer = ActionPointer.new()
	pointer_layer.add_child(action_pointer)
	map_overlay = MapOverlay.new()
	var map_layer := CanvasLayer.new()
	map_layer.layer = 8
	add_child(map_layer)
	map_layer.add_child(map_overlay)
	# The drawn map (M) sits under the hotbar and moodles, over the (then hidden) world.
	medieval_map = MedievalMap.new()
	var drawn_map_layer := CanvasLayer.new()
	drawn_map_layer.layer = 4
	add_child(drawn_map_layer)
	drawn_map_layer.add_child(medieval_map)
	var moodle_layer := CanvasLayer.new()
	moodle_layer.layer = 5
	add_child(moodle_layer)
	moodles = Moodles.new()
	moodles.simulation = simulation
	moodle_layer.add_child(moodles)
	var bar_layer := CanvasLayer.new()
	bar_layer.layer = 6
	add_child(bar_layer)
	bottom_bar = BottomBar.new()
	bottom_bar.simulation = simulation
	bottom_bar.clock = clock
	bottom_bar.action.connect(handle_action)
	bottom_bar.slot_pressed.connect(func(index: int) -> void: simulation.submit("hotbar_use", {"slot": index}))
	bar_layer.add_child(bottom_bar)
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 12
	add_child(menu_layer)
	context_menu = ContextMenu.new()
	context_menu.chosen.connect(_on_context_chosen)
	menu_layer.add_child(context_menu)
	journal = JournalWindow.new()   # J: people met, news heard, favours, your standing
	journal.simulation = simulation
	journal.visible = false
	menu_layer.add_child(journal)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.chosen.connect(_on_pause_chosen)
	var perf_layer := CanvasLayer.new()
	perf_layer.layer = 8
	add_child(perf_layer)
	perf = PerfOverlay.new()
	perf.main = self
	perf_layer.add_child(perf)
	knockout = KnockoutScreen.new()
	add_child(knockout)
	knockout.skip_requested.connect(_skip_ahead)
	knockout.wait_requested.connect(_wait_out)
	knockout.load_requested.connect(func() -> void: handle_action("load"))
	knockout.new_game_requested.connect(func() -> void:
		Engine.set_meta("skip_title", true)
		get_tree().reload_current_scene())
	knockout.quit_to_title_requested.connect(func() -> void: get_tree().reload_current_scene())
	$WorldView.simulation = simulation
	world_audio = Audio.new()
	add_child(world_audio)
	$DebugHUD.sound_button.text = "Sound on" if world_audio.enabled else "Sound off"
	$DebugHUD.action.connect(handle_action)
	$ObserverCamera.position = Vector2(64, 46) * CELL
	$ObserverCamera.set_process(false)
	selected_id = simulation.state.player
	refresh_view()
	call_deferred("_maybe_open_menu")

## The title screen appears only when the game is launched normally (tests add this scene by hand).
func _maybe_open_menu() -> void:
	if get_tree().current_scene != self: return
	if Engine.has_meta("skip_title"):
		Engine.remove_meta("skip_title")   # "New game" from the death screen goes straight in
		_begin_at_home()
		return
	menu_active = true
	menu = MainMenu.new()
	var newest: Dictionary = SaveSlots.newest(save_dir, [save_path])
	if not newest.is_empty(): menu.continue_text = SaveSlots.describe(newest.info)
	add_child(menu)
	menu.start_requested.connect(func() -> void:
		_begin_at_home()
		_start_from_menu())
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu.continue_requested.connect(func() -> void:
		handle_action("load")
		_start_from_menu())
	_set_hud_visible(false)
	follow_player = false
	$ObserverCamera.zoom = Vector2.ONE * 0.6
	$ObserverCamera.position = _menu_camera(0.0)

var hud_was_visible: Dictionary = {}
func _set_hud_visible(shown: bool) -> void:
	for node in [moodles, bottom_bar, perf]:
		if node != null:
			if not shown: hud_was_visible[node.get_instance_id()] = node.visible
			node.visible = bool(hud_was_visible.get(node.get_instance_id(), true)) if shown else false
			if shown and node.visible:
				node.modulate.a = 0.0
				create_tween().tween_property(node, "modulate:a", 1.0, 0.6)
	$DebugHUD.visible = shown
	if not shown: player_panels.show_mode("")

## A new game starts in your house, in the middle of one of the things there (a workout, a drink
## from the fridge, resting on the bed, the sofa): a different one each new game.
func _begin_at_home() -> void:
	Activities.begin_at_home(simulation, int(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system())))

## A slow drift over the countryside around the first town.
func _menu_camera(t: float) -> Vector2:
	return Vector2(66, 54) * CELL + Vector2(sin(t * 0.045) * 1150.0, sin(t * 0.031 + 1.0) * 560.0)

## Start: fly down to the player and zoom in; control is handed over once the camera has landed.
func _start_from_menu() -> void:
	var player_key := str(simulation.state.player)
	var cell: Array = simulation.state.entities[player_key].cell
	var landing: Vector2 = $WorldView.motion.actors.get(player_key, {}).get("position", Vector2(cell[0], cell[1]) * CELL)
	intro_tween = create_tween()
	intro_tween.tween_property($ObserverCamera, "position", landing, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro_tween.parallel().tween_property($ObserverCamera, "zoom", Vector2.ONE * 0.9, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro_tween.tween_property($ObserverCamera, "zoom", Vector2.ONE * 2.0, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	intro_tween.tween_callback(_finish_intro)

# --- a long sentence passes in a few seconds -------------------------------------------------------

const CATCH_UP_OVER := 2400       # ticks: sentences longer than four hours are caught up, not fast-forwarded
const CATCH_UP_BUDGET := 12000    # microseconds of simulation a frame while catching up
var catching_up: bool = false
var catch_up_card: CanvasLayer
var catch_up_clock: Label
var catch_up_bar: ProgressBar
var catch_up_total: int = 1

## "Wait it out": a long sentence is caught up behind a card (the world simulated flat out, nothing
## drawn); a short one fast-forwards as before.
func _wait_out() -> void:
	var jail: Dictionary = simulation.state.get("player_control", {}).get("jail", {})
	var left: int = int(jail.get("until", 0)) - int(simulation.state.tick)
	if not jail.is_empty() and not bool(jail.get("releasing", false)) and left > CATCH_UP_OVER: _start_catch_up(left)
	else: _skip_ahead()

func _start_catch_up(left: int) -> void:
	if catch_up_card == null: _build_catch_up_card()
	catching_up = true
	catch_up_total = maxi(1, left - JAIL_WAIT_STOP)
	catch_up_card.visible = true
	world_audio.stop_effects()
	_catch_up_labels()

func _catch_up_frame() -> void:
	var s: Dictionary = simulation.state
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < CATCH_UP_BUDGET:
		var jail: Dictionary = s.get("player_control", {}).get("jail", {})
		if jail.is_empty() or bool(jail.get("releasing", false)) or int(jail.until) - int(s.tick) <= JAIL_WAIT_STOP or bool(s.player_control.get("dead", false)):
			_end_catch_up()
			return
		simulation.step()
	_catch_up_labels()

func _end_catch_up() -> void:
	catching_up = false
	if catch_up_card != null: catch_up_card.visible = false
	clock.accumulator = 0
	$WorldView.snap_visuals()
	simulation.state.player_control.notice = "Two minutes left."
	refresh_view()

func _catch_up_labels() -> void:
	var s: Dictionary = simulation.state
	var jail: Dictionary = s.get("player_control", {}).get("jail", {})
	var left: int = maxi(0, int(jail.get("until", s.tick)) - int(s.tick) - JAIL_WAIT_STOP)
	var minute: int = (int(s.tick) / 10) % 1440
	catch_up_clock.text = "Day %d · %02d:%02d" % [int(s.tick) / 14400 + 1, minute / 60, minute % 60]
	catch_up_bar.value = 100.0 * (1.0 - float(left) / float(catch_up_total))

func _build_catch_up_card() -> void:
	catch_up_card = CanvasLayer.new()
	catch_up_card.layer = 40
	add_child(catch_up_card)
	var dark := ColorRect.new()
	dark.color = Color(0.04, 0.035, 0.03, 1.0)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catch_up_card.add_child(dark)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.offset_left = -200
	column.offset_right = 200
	column.offset_top = -60
	column.offset_bottom = 60
	column.add_theme_constant_override("separation", 12)
	catch_up_card.add_child(column)
	var title := Label.new()
	title.text = "Time passes…"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("efe3c6"))
	column.add_child(title)
	catch_up_clock = Label.new()
	catch_up_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catch_up_clock.add_theme_font_size_override("font_size", 18)
	catch_up_clock.add_theme_color_override("font_color", Color("b9a98a"))
	column.add_child(catch_up_clock)
	catch_up_bar = ProgressBar.new()
	catch_up_bar.custom_minimum_size = Vector2(400, 10)
	catch_up_bar.show_percentage = false
	column.add_child(catch_up_bar)
	var hint := Label.new()
	hint.text = "Serving your sentence · Esc to stop"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("8f826a"))
	column.add_child(hint)
	catch_up_card.visible = false

## Waiting out a jail sentence: the fast-forward stops with two in-game minutes left (looking one
## frame ahead so it never overshoots), so the release plays out at the speed you had.
const JAIL_WAIT_STOP := 20   # ticks: two in-game minutes
func _stop_jail_wait(delta: float) -> void:
	if not skipping: return
	var jail: Dictionary = simulation.state.get("player_control", {}).get("jail", {})
	if jail.is_empty() or bool(jail.get("releasing", false)): return
	var left: int = int(jail.until) - int(simulation.state.tick)
	var next_frame: int = ceili(minf(delta, 0.1) * 10.0 * float(clock.speed)) + 1
	if left <= JAIL_WAIT_STOP + next_frame:
		skipping = false
		clock.speed = skip_previous_speed
		clock.accumulator = 0
		simulation.state.player_control.notice = "Two minutes left."

## Knocked out: run time at top speed until the player comes round, then back to the usual speed.
func _skip_ahead(fast: int = 40) -> void:
	if skipping: return
	var jail: Dictionary = simulation.state.get("player_control", {}).get("jail", {})
	if not jail.is_empty() and int(jail.until) - int(simulation.state.tick) <= JAIL_WAIT_STOP + 2: return   # nearly done: no point
	skipping = true
	skip_previous_speed = clock.speed
	clock.paused = false
	clock.speed = fast

func _finish_intro() -> void:
	menu_active = false
	follow_player = true
	intro_tween = null
	if menu != null: menu.queue_free()
	menu = null
	_set_hud_visible(true)

func _process(delta: float) -> void:
	if perf != null: perf.sample(delta)
	if catching_up:
		_catch_up_frame()
		return   # nothing of the world is drawn or animated while time passes
	if menu_active and intro_tween == null:
		menu_time += delta
		$ObserverCamera.position = _menu_camera(menu_time)
	var direction := Vector2(
		Input.get_action_strength("walk_right") - Input.get_action_strength("walk_left"),
		Input.get_action_strength("walk_down") - Input.get_action_strength("walk_up"))
	if player_panels.visible or menu_active: direction=Vector2.ZERO
	if follow_player:
		# Commands execute on the next tick. Queue at the end of the preceding
		# tick so the two-tick walking cadence has no extra idle tick.
		if direction != Vector2.ZERO and simulation.state.tick >= last_input_tick and simulation.state.tick + 1 >= simulation.state.player_control.next_move and not clock.paused:
			var sprint: bool=Input.is_key_pressed(KEY_SHIFT)
			# W+A, W+D, S+A and S+D combine both axes into one diagonal step.
			var cell_direction: Array = [int(signf(direction.x)), int(signf(direction.y))]
			simulation.submit("move_player", {"direction": cell_direction,"run":sprint})
			last_input_tick = simulation.state.tick+1
	elif map_mode:
		if direction != Vector2.ZERO: medieval_map.pan(direction.limit_length() * 700.0 * delta)
	else:
		$ObserverCamera.position += direction.limit_length() * 480 * delta / $ObserverCamera.zoom.x
	# Holding Shift while a route is being followed (double-click, or walking up to a target) runs it.
	var route_active: bool = not simulation.state.get("player_path", []).is_empty()
	if route_active and Input.is_key_pressed(KEY_SHIFT) != bool(simulation.state.player_control.get("travel_run", false)):
		simulation.submit("travel_run", {"run": Input.is_key_pressed(KEY_SHIFT)})
	_stop_jail_wait(delta)
	var started := Time.get_ticks_usec()
	var advanced: int = clock.advance(delta, simulation)
	Probe.add("f:simulation", Time.get_ticks_usec() - started)
	Probe.count("ticks", advanced)
	if advanced > 0:
		tick_ms = float(clock.worst_step_usec) / 1000.0   # the slowest tick this frame: spikes show
		_maybe_autosave()
	_finish_save()
	var shotgun_equipped: bool = simulation.state.get("shotgun", {}).get("equipped", false)
	$WorldView.motion.player_aiming = (aiming or (pointer_held and not shotgun_equipped)) and not player_panels.visible and not map_mode
	$WorldView.motion.player_ready = pointer_held and not player_panels.visible
	$WorldView.motion.player_aim_position = get_global_mouse_position()
	_update_peek()
	_update_pointer()
	map_overlay.state = simulation.state
	map_overlay.active = false   # the drawn map shows the markings now; the overlay is the in-play waypoint
	map_overlay.visible = not map_mode
	$WorldView.overlay_labels = false
	if map_mode: medieval_map.refresh_live(simulation.state)
	map_overlay.zoom = $ObserverCamera.zoom.x
	map_overlay.player_world = $WorldView.motion.actors.get(str(simulation.state.player), {}).get("position", Vector2.ZERO)
	# The overlay draws only on the map or with a waypoint set; otherwise one last clearing redraw.
	var overlay_live: bool = map_overlay.waypoint != Vector2.INF or int(simulation.state.get("player_control", {}).get("travelling", 0)) != 0
	if overlay_live or overlay_was_live: map_overlay.queue_redraw()
	overlay_was_live = overlay_live
	var view_started := Time.get_ticks_usec()
	$WorldView.motion.tick_fraction = clampf(clock.accumulator / clock.STEP_SECONDS, 0.0, 1.0)
	if not map_mode: $WorldView.animate(delta, clock.paused, clock.speed)   # nothing of the world shows behind the map
	Probe.add("f:animate", Time.get_ticks_usec() - view_started)
	if follow_player:
		var cell: Array = simulation.state.entities[str(simulation.state.player)].cell
		$ObserverCamera.position = $WorldView.motion.actors.get(str(simulation.state.player), {}).get("position", Vector2(cell[0], cell[1]) * CELL)
	_update_camera_kick(delta)
	var knock_now: Dictionary = simulation.state.player_control.get("knock", {})
	# Asleep in a bed: time runs fast (SLEEP_SPEED) until the player wakes.
	var sleeping_now: bool = not simulation.state.player_control.get("sleeping", {}).is_empty()
	if sleeping_now and not skipping: _skip_ahead(SLEEP_SPEED)
	var waiting_out: bool = (not knock_now.is_empty() and str(knock_now.get("kind", "")) == "ko") or Law.in_custody(simulation.state) or sleeping_now
	if skipping and (not waiting_out or simulation.state.player_control.get("dead", false)):
		skipping = false
		clock.speed = skip_previous_speed
	var body_world: Vector2 = $WorldView.motion.actors.get(str(simulation.state.player), {}).get("position", $ObserverCamera.position)
	knockout.update_state(simulation.state, get_viewport().get_canvas_transform() * (body_world + Vector2(0, -6)), delta)
	world_audio.present($WorldView.motion.cues, simulation.state, $ObserverCamera.position, clock.paused, delta)
	if simulation.state.tick != last_draw_tick:
		var refresh_started := Time.get_ticks_usec()
		refresh_view()
		Probe.add("f:refresh_ui", Time.get_ticks_usec() - refresh_started)
	if not follow_player and not map_mode:
		$WorldView.queue_redraw()

func refresh_view() -> void:
	last_draw_tick = simulation.state.tick
	$WorldView.selected_id = selected_id
	$WorldView.queue_redraw()
	# The static background repaints on a timer and when the selection changes, not every tick.
	if $WorldView.background != null and selected_id != last_selected_id:
		last_selected_id = selected_id
		$WorldView.background.queue_redraw()
	var t := Time.get_ticks_usec()
	$DebugHUD.refresh(simulation, clock, selected_id, tick_ms)
	t = _lap("u:debug_hud", t)
	player_panels.refresh()
	if journal != null: journal.refresh()
	t = _lap("u:panels", t)
	if moodles != null: moodles.refresh()
	t = _lap("u:moodles", t)
	if bottom_bar != null:
		bottom_bar.blocked = player_panels.visible
		bottom_bar.refresh()
	t = _lap("u:bottom_bar", t)
	if not map_mode: $DebugHUD.notice.text = PlayerActions.prompt(simulation.state, selected_id)
	_lap("u:prompt", t)

func _lap(name: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	Probe.add(name, now - since)
	return now

func handle_action(kind: String) -> void:
	if kind.begins_with("buy:") or kind.begins_with("sell:"):
		var town: int = nearest_town()
		simulation.submit("trade", {"town": town, "item": kind.split(":")[1], "buy": kind.begins_with("buy:"), "quantity": 1})
	elif kind.begins_with("bind:"):
		pending_binding = kind.split(":")[1]
		$DebugHUD.notice.text = "Press a movement key (Esc cancels)."
	match kind:
		"inventory":
			simulation.submit("stop_travel")
			player_panels.toggle("inventory")
		"health":
			simulation.submit("stop_travel")
			player_panels.toggle("health")
		"interact":
			if player_panels.visible: player_panels.show_mode("")
			elif Law.standoff_sheriff(simulation.state) != 0 or not simulation.state.get("player_control", {}).get("captive", {}).is_empty(): simulation.submit("surrender")
			else: simulation.submit("interact",{"target":selected_id})
		"injury_demo": simulation.submit("debug_injury",{"part":"right_forearm","damage":24,"kind":"cut"})
		"encounter_demo": simulation.submit("demo_encounter")
		"sound":
			world_audio.toggle()
			$DebugHUD.sound_button.text = "Sound on" if world_audio.enabled else "Sound off"
		"motion":
			$WorldView.motion.reduced_motion = not $WorldView.motion.reduced_motion
			$DebugHUD.motion_button.text = "Motion: low" if $WorldView.motion.reduced_motion else "Motion: full"
		"map": toggle_map()
		"pause": clock.paused = not clock.paused
		"slower": clock.speed = BottomBar.SPEEDS[maxi(0, BottomBar.SPEEDS.find(clock.speed) - 1)]
		"faster": clock.speed = BottomBar.SPEEDS[mini(BottomBar.SPEEDS.size() - 1, BottomBar.SPEEDS.find(clock.speed) + 1)]
		"speed1": clock.speed = 1
		"speed2": clock.speed = 2
		"speed3": clock.speed = 3
		"details": $DebugHUD.toggle_details()
		"follow": follow_player = not follow_player
		"travel":
			var town: int = 2 if simulation.state.entities[str(simulation.state.player)].cell[0] < 122 else 1
			simulation.submit("travel", {"town": town})
			follow_player = true
		"road": simulation.submit("route_block", {"blocked": not simulation.state.routes["1"].blocked})
		"risk": simulation.submit("risk", {"value": 0 if simulation.state.routes["1"].risk > 0 else 70})
		"treaty": simulation.submit("treaty", {"open": not simulation.state.treaty.open_trade})
		"mod": simulation.submit("load_recipe", {"path": "user://recipe.json"})
		"large_text": $DebugHUD.toggle_large_text()
		"observer": $DebugHUD.toggle_observer()
		"cancel_batch":
			if simulation.state.workshops.has(str(selected_id)):
				simulation.submit("cancel_production", {"id": selected_id})
		"save":
			if not _save_in_background(save_path, "quick", "Saved world."):
				$DebugHUD.notice.text = "Still saving..."
		"load":
			_finish_save(true)   # a save still being written completes before anything loads
			# The newest save, whether the quick save (F5) or a morning autosave.
			var newest: Dictionary = SaveSlots.newest(save_dir, [save_path])
			var result := Save.load_into(simulation, str(newest.get("path", save_path)))
			if result.ok:
				_mark_autosaved_today()
				clock.accumulator = 0
				$WorldView.snap_visuals()
				world_audio.stop_effects()
				selected_id = simulation.state.player
				$DebugHUD.notice.text = "Recovered backup." if result.get("recovered_backup", false) else "Loaded world."
			else:
				$DebugHUD.notice.text = result.error
		"cancel":
			if simulation.state.residents.has(str(selected_id)):
				simulation.submit("cancel_job", {"id": simulation.state.residents[str(selected_id)].job})
	refresh_view()

func _input(event: InputEvent) -> void:
	if menu_active: return
	if catching_up:
		# Time passing behind the card: Esc stops it there; nothing else gets through.
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			catching_up = false
			catch_up_card.visible = false
			clock.accumulator = 0
			$WorldView.snap_visuals()
		get_viewport().set_input_as_handled()
		return
	if is_paused_menu():
		# The pause menu is up: Esc resumes; everything else goes to its buttons (or nowhere).
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			close_pause_menu()
			get_viewport().set_input_as_handled()
		return
	# Handle zoom before modal UI panels can consume trackpad/mouse scroll events.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		aiming = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pointer_held = false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and player_panels.scrolls_health_list_at(event.position):
			return
		if map_mode and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			medieval_map.zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			get_viewport().set_input_as_handled()
			return
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: $ObserverCamera.adjust_zoom(1.15); get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: $ObserverCamera.adjust_zoom(1.0/1.15); get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		if map_mode: medieval_map.zoom_at(event.position, event.factor)
		else: $ObserverCamera.adjust_zoom(event.factor)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if menu_active or is_paused_menu(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Two quick right-clicks on the same spot: walk there by the shortest route.
			var now := Time.get_ticks_msec()
			if not simulation.state.get("shotgun", {}).get("equipped", false) and now - last_right_press < 380 and event.position.distance_to(last_right_position) < 30.0 and not player_panels.visible and not map_mode and follow_player:
				var spot := get_global_mouse_position()
				simulation.submit("walk_to", {"cell": [roundi(spot.x / CELL), roundi(spot.y / CELL)]})
				context_menu.close()
				aiming = false
				last_right_press = -10000
				return
			last_right_press = now
			last_right_position = event.position
		aiming = event.pressed
		if event.pressed: right_down_msec = Time.get_ticks_msec()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		$DebugHUD.toggle_details()
		return
	if event is InputEventKey and event.pressed and not event.echo and not pending_binding.is_empty():
		if event.physical_keycode != KEY_ESCAPE:
			Settings.bind(pending_binding, event.physical_keycode)
			$DebugHUD.notice.text = pending_binding.replace("walk_", "Move ") + " bound to " + OS.get_keycode_string(event.physical_keycode)
		pending_binding = ""
		get_viewport().set_input_as_handled()
		return
	if map_mode and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var town_id: int = medieval_map.town_at(event.position)
			if town_id != 0:
				_open_travel_menu(town_id, event.position)
				return
			context_menu.close()
			map_overlay.set_waypoint(medieval_map.world_of(event.position))
			medieval_map.waypoint = map_overlay.waypoint
			medieval_map.queue_redraw()
			$DebugHUD.notice.text = "Waypoint set: %s" % MapOverlay.bearing_text(map_overlay.player_world, map_overlay.waypoint)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			map_overlay.clear_waypoint()
			medieval_map.waypoint = Vector2.INF
			medieval_map.queue_redraw()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_held = true
		if aiming and not player_panels.visible and not clock.paused and not map_mode:
			if simulation.state.get("shotgun", {}).get("equipped", false): _submit_shot()
			else: _submit_strike("punch")
		elif not player_panels.visible:
			selected_id = $WorldView.pick(get_global_mouse_position())
			refresh_view()
			var now_left := Time.get_ticks_msec()
			if selected_id == 0 and now_left - last_left_press < 380 and event.position.distance_to(last_left_position) < 30.0 and not map_mode and follow_player:
				# Two quick left-clicks on open ground: walk there by the shortest route (Shift runs).
				var spot_left := get_global_mouse_position()
				simulation.submit("walk_to", {"cell": [roundi(spot_left.x / CELL), roundi(spot_left.y / CELL)]})
				context_menu.close()
				last_left_press = -10000
			else:
				last_left_press = now_left
				last_left_position = event.position
				_open_context_menu(selected_id, event.position)
	if event is InputEventMouseButton:
		$WorldView.queue_redraw()
	if event is InputEventKey and event.pressed and not event.echo and not simulation.state.get("player_control", {}).get("sleeping", {}).is_empty():
		simulation.submit("wake")   # any key gets the player out of bed
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_I: handle_action("inventory")
			KEY_H: handle_action("health")
			KEY_E: simulation.submit("eat")
			KEY_M: toggle_map()
			KEY_C: simulation.submit("context_action", {"target": simulation.state.player, "action": "wardrobe"})
			KEY_X: simulation.submit("crouch_toggle")
			KEY_T: simulation.submit("rotate_furniture")
			KEY_G: simulation.submit("rearrange_furniture")
			KEY_R: simulation.submit("shotgun_reload")
			KEY_Q: simulation.submit("drink")
			KEY_F: handle_action("interact")
			KEY_J: journal.toggle()
			KEY_ESCAPE:
				if journal.visible: journal.visible = false
				elif map_mode: toggle_map()   # Esc closes the map first, then stops a travel, then closes panels
				elif int(simulation.state.get("player_control", {}).get("travelling", 0)) != 0: simulation.submit("stop_travel")
				elif player_panels.visible: player_panels.show_mode("")
				else: open_pause_menu()   # nothing open: pause, with the pause menu
			KEY_SPACE:
				if not player_panels.visible and not clock.paused: _submit_strike("shove")
			KEY_P: handle_action("pause")
			KEY_1: simulation.submit("hotbar_use", {"slot": 0})
			KEY_2: simulation.submit("hotbar_use", {"slot": 1})
			KEY_3: simulation.submit("hotbar_use", {"slot": 2})
			KEY_4: simulation.submit("hotbar_use", {"slot": 3})
			KEY_COMMA: handle_action("slower")
			KEY_PERIOD: handle_action("faster")
			KEY_F5: handle_action("save")
			KEY_F9: handle_action("load")
			KEY_TAB: handle_action("follow")
			KEY_F3: handle_action("observer")

# --- the pause menu (Esc) ---------------------------------------------------------------------------

func is_paused_menu() -> bool:
	return pause_menu != null and pause_menu.visible

func open_pause_menu() -> void:
	if menu_active or is_paused_menu() or (knockout != null and knockout.visible): return
	context_menu.close()
	aiming = false
	pointer_held = false
	paused_before_menu = clock.paused
	clock.paused = true
	pause_menu.open(not SaveSlots.newest(save_dir, [save_path]).is_empty())

func close_pause_menu() -> void:
	if not is_paused_menu(): return
	pause_menu.close()
	clock.paused = paused_before_menu

func _on_pause_chosen(id: String) -> void:
	match id:
		"resume": close_pause_menu()
		"save":
			handle_action("save")
			pause_menu.status.text = $DebugHUD.notice.text
			pause_menu.buttons.load.disabled = false
		"load":
			close_pause_menu()
			handle_action("load")
		"title": get_tree().reload_current_scene()
		"quit": get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		aiming = false
		pointer_held = false

## Map view: leaves the character and frames every settlement. Move with WASD, zoom with
## the wheel; press M again to return to the character at the previous zoom.
## The settlement whose storehouse is closest to the player (for trading at its stalls).
func nearest_town() -> int:
	var cell: Array = simulation.state.entities[str(simulation.state.player)].cell
	var best: int = 1
	var best_distance: float = INF
	for town in simulation.state.get("settlements", {}).values():
		var store: Array = simulation.state.entities[str(town.warehouse)].cell
		var distance: float = Vector2(store[0] - cell[0], store[1] - cell[1]).length()
		if distance < best_distance:
			best_distance = distance
			best = int(town.id)
	return best

## Clicking a person or thing opens a menu of what can be done to it; F stays the quick way.
func _open_context_menu(id: int, at: Vector2) -> void:
	if id == 0 or map_mode:
		context_menu.close()
		return
	var s: Dictionary = simulation.state
	context_part = $WorldView.last_pick_part
	var options: Array = ContextActions.options(s, id, context_part)
	if options.is_empty():
		context_menu.close()
		return
	var subtitle: String = ContextActions.subtitle(s, id) if context_part.is_empty() else String(s.entities[str(id)].name)
	context_menu.open(id, ContextActions.title(s, id, context_part), subtitle, options, at)
	pointer_held = false

## On the map: a town's name was clicked.
func _open_travel_menu(town_id: int, at: Vector2) -> void:
	var s: Dictionary = simulation.state
	var town: Dictionary = s.settlements.get(str(town_id), {})
	if town.is_empty(): return
	var store: Array = s.entities[str(town.warehouse)].cell
	var here: Array = s.entities[str(s.player)].cell
	var distance: int = absi(store[0] - here[0]) + absi(store[1] + 2 - here[1])
	var reason := ""
	if Law.jailed(s) or Law.in_custody(s): reason = "You are locked up"
	elif distance <= 3: reason = "You are here"
	var options: Array = [{"id": "travel_town", "label": "Travel here", "icon": "sun", "enabled": reason.is_empty(), "reason": reason}]
	context_part = ""
	context_menu.open(town_id, str(town.name), "About %d m along the roads" % distance if distance > 3 else "You are here", options, at)

func _on_context_chosen(target: int, action: String) -> void:
	if action in ["inventory", "health"]:
		handle_action(action)
		return
	if action == "travel_town":
		simulation.submit("travel", {"town": target})
		if map_mode: toggle_map()   # back to the world: the camera follows the walk, and a step takes over
		return
	simulation.submit("context_action", {"target": target, "action": action, "part": context_part})

func toggle_map() -> void:
	map_mode = not map_mode
	context_menu.close()
	if map_mode:
		map_return_follow = follow_player
		follow_player = false
		medieval_map.waypoint = map_overlay.waypoint
		medieval_map.open(simulation.state)   # a fresh picture each time the map opens
		$WorldView.visible = false
		$DebugHUD.notice.text = "Map: click a town's name to travel there. WASD and the wheel to look around, Esc or M to close."
	else:
		medieval_map.close()
		$WorldView.visible = true
		follow_player = map_return_follow
		$WorldView.snap_visuals()   # catch up with whatever moved while the map was open
	refresh_view()

func _submit_shot() -> void:
	var actor: Dictionary = $WorldView.motion.actors.get(str(simulation.state.player), {})
	var cell: Array = simulation.state.entities[str(simulation.state.player)].cell
	var origin: Vector2 = actor.get("position", Vector2(cell[0], cell[1]) * CELL)
	var direction: Vector2 = get_global_mouse_position() - origin
	if direction.length_squared() < 16.0: direction = Vector2.from_angle(float(actor.get("heading", PI / 2.0)))
	direction = direction.normalized()
	simulation.submit("shotgun_fire", {"direction": [roundi(direction.x * 1000.0), roundi(direction.y * 1000.0)]})

func _submit_strike(kind: String) -> void:
	var actor: Dictionary = $WorldView.motion.actors.get(str(simulation.state.player), {})
	var cell: Array = simulation.state.entities[str(simulation.state.player)].cell
	var origin: Vector2 = actor.get("position", Vector2(cell[0], cell[1]) * CELL)
	var direction: Vector2 = get_global_mouse_position() - origin if aiming or pointer_held else Vector2.from_angle(float(actor.get("heading", PI / 2.0)))
	if direction.length_squared() < 16.0: direction = Vector2.from_angle(float(actor.get("heading", PI / 2.0)))
	direction = direction.normalized()
	simulation.submit("player_strike", {"kind": kind, "direction": [roundi(direction.x * 1000.0), roundi(direction.y * 1000.0)]})

## Each shot shoves the camera back against the aim for a moment (presentation only).
func _update_camera_kick(delta: float) -> void:
	var gun: Dictionary = simulation.state.get("shotgun", {})
	var kicks: int = int(gun.get("kicks", 0))
	if kicks != kick_seen:
		if kicks > kick_seen:
			var aim := Vector2(float(gun.get("last_dir", [0, 1000])[0]), float(gun.get("last_dir", [0, 1000])[1])).normalized()
			kick_offset = -aim * (7.0 + 5.0 * float(gun.get("bloom", 0)) / 900.0) / maxf(0.5, $ObserverCamera.zoom.x)
		kick_seen = kicks
	kick_offset = kick_offset.move_toward(Vector2.ZERO, (60.0 + kick_offset.length() * 9.0) * delta)
	# Leaning out of cover: the view slides towards the corner so you can see past it.
	var pc: Dictionary = simulation.state.player_control
	var lean_target := Vector2.ZERO
	if pc.has("peek"):
		lean_target = Vector2(pc.peek.to[0] - pc.peek.from[0], pc.peek.to[1] - pc.peek.from[1]) * CELL * 2.2
	lean_offset = lean_offset.lerp(lean_target, clampf(delta * 7.0, 0.0, 1.0))
	$ObserverCamera.offset = kick_offset + lean_offset

## Holding the right button for a moment at a corner leans the player out; releasing returns them.
func _update_peek() -> void:
	var holding: bool = aiming and not player_panels.visible and not map_mode and not clock.paused and Time.get_ticks_msec() - right_down_msec > 150
	var player_pos: Vector2 = $WorldView.motion.actors.get(str(simulation.state.player), {}).get("position", Vector2.ZERO)
	var toward: Vector2 = get_global_mouse_position() - player_pos
	var octant: int = roundi(toward.angle() / (PI / 4.0)) if holding else -1
	if holding != peek_on or (holding and octant != peek_octant):
		peek_on = holding
		peek_octant = octant
		var unit: Vector2 = toward.normalized() if toward.length() > 1.0 else Vector2.ZERO
		simulation.submit("peek", {"on": holding, "toward": [roundi(unit.x * 1000.0), roundi(unit.y * 1000.0)]})

## The pointer: a reticle for fists, an eye when leaning out unarmed, a crosshair and aim line with the gun.
func _update_pointer() -> void:
	var s: Dictionary = simulation.state
	var armed: bool = s.get("shotgun", {}).get("equipped", false)
	var show: bool = (pointer_held or aiming) and not player_panels.visible and not map_mode
	action_pointer.active = show
	if not show:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if pointer_was_shown: action_pointer.queue_redraw()   # one redraw to clear it
		pointer_was_shown = false
		return
	pointer_was_shown = true
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN: Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var player_pos: Vector2 = $WorldView.motion.actors.get(str(s.player), {}).get("position", Vector2.ZERO)
	var transform: Transform2D = get_viewport().get_canvas_transform()
	var muzzle_world: Vector2 = player_pos + Vector2(0, -22)
	action_pointer.muzzle = transform * muzzle_world
	action_pointer.peeking = s.player_control.has("peek")
	if armed and aiming:
		action_pointer.mode = "aim"
		action_pointer.bloom = float(s.shotgun.get("bloom", 0)) / 900.0
		var from_cell: Array = Cover.eye_cell(s)
		var mouse_world: Vector2 = get_global_mouse_position()
		var to_cell: Array = [roundi(mouse_world.x / CELL), roundi(mouse_world.y / CELL)]
		var hit: Array = Cover.first_block(s, from_cell, to_cell)
		action_pointer.blocked = not hit.is_empty()
		if not hit.is_empty(): action_pointer.line_end = transform * (Vector2(hit[0], hit[1]) * CELL)
	elif aiming and not armed:
		action_pointer.mode = "look" if (s.player_control.has("cover") or s.player_control.has("peek")) else "fist"
		action_pointer.blocked = false
	else:
		action_pointer.mode = "fist"
		action_pointer.blocked = false
	action_pointer.queue_redraw()

## Each in-game morning at 06:00 the world is written to the older of two autosave files, so a
## crash or a bad decision never costs more than a day. Never in the middle of a gunfight, while
## the title screen is up, or when the player is dead.
func _maybe_autosave() -> void:
	var s: Dictionary = simulation.state
	if menu_active or not SaveSlots.autosave_due(s, last_autosave_day): return
	if not s.get("law", {}).get("alert", {}).is_empty() or bool(s.get("player_control", {}).get("dead", false)): return
	if save_thread != null: return   # try again next frame
	last_autosave_day = int(s.tick) / SaveSlots.DAY_TICKS
	_save_in_background(SaveSlots.next_autosave(save_dir), "autosave", "Autosaved: " + SaveSlots.describe(SaveSlots.info_for(s, "autosave")))

## Copies the world now (a few ms) and writes it on a background thread, so saving never stalls
## play. False when another save is still being written.
func _save_in_background(path: String, kind: String, done_text: String) -> bool:
	if save_thread != null and save_thread.is_alive(): return false
	_finish_save(true)
	var data: Dictionary = simulation.snapshot()
	var save_info: Dictionary = SaveSlots.info_for(simulation.state, kind)
	save_label = done_text
	save_thread = Thread.new()
	save_thread.start(SaveSlots.write.bind(data, save_info, path))
	return true

## Collects a finished background save and reports it. With `wait`, blocks until it is done.
func _finish_save(wait: bool = false) -> void:
	if save_thread == null or (not wait and save_thread.is_alive()): return
	var result: Dictionary = save_thread.wait_to_finish()
	save_thread = null
	$DebugHUD.notice.text = save_label if result.get("ok", false) else "Save failed: " + str(result.get("error", ""))

func _exit_tree() -> void:
	_finish_save(true)   # never quit halfway through writing a save

## A new or freshly loaded game that is already past 06:00 counts as saved for today.
func _mark_autosaved_today() -> void:
	var tick: int = int(simulation.state.get("tick", 0))
	last_autosave_day = tick / SaveSlots.DAY_TICKS if (tick / 10) % 1440 >= SaveSlots.AUTOSAVE_MINUTE else tick / SaveSlots.DAY_TICKS - 1
