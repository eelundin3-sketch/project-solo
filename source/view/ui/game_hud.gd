extends CanvasLayer
signal action(kind: String)

var heading: Label
var stats: Label
var notice: Label
var pause_button: Button
var stamina_bar: ProgressBar
var sound_button: Button
var motion_button: Button
var observer_panel: PanelContainer
var large_text: bool = false
var details_visible: bool = true

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(480, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.075, 0.88)
	style.border_color = Color("87734e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false  # the old title/stats/speed panel was removed; the clock and speed live in the bottom bar
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 17)
	column.add_child(heading)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 12)
	column.add_child(stats)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	column.add_child(controls)
	pause_button = _button(controls, "Pause", "pause")
	_button(controls, "1×", "speed1")
	_button(controls, "2×", "speed2")
	_button(controls, "3×", "speed3")
	var tool_button := Button.new()
	tool_button.text = "Tools"
	tool_button.tooltip_text = "Open observer and accessibility tools"
	tool_button.pressed.connect(func() -> void: action.emit("observer"))
	controls.add_child(tool_button)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(115, 20)
	stamina_bar.max_value = 100
	stamina_bar.show_percentage = false
	stamina_bar.tooltip_text = "Stamina · hold Shift while walking to run"
	stamina_bar.visible = false  # the stamina bar lives above the bottom hotbar now
	controls.add_child(stamina_bar)
	# The interaction prompt and short messages stay, as a line above the hotbar.
	notice = Label.new()
	notice.add_theme_font_size_override("font_size", 14)
	notice.add_theme_color_override("font_color", Color("f4ecd6"))
	notice.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.95))
	notice.add_theme_constant_override("outline_size", 5)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notice.offset_top = -152
	notice.offset_bottom = -130
	notice.offset_left = -360
	notice.offset_right = 360
	root.add_child(notice)

	observer_panel = PanelContainer.new()
	observer_panel.position = Vector2(84, 130)
	observer_panel.custom_minimum_size = Vector2(300, 0)
	observer_panel.visible = false
	observer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(observer_panel)
	var tools := VBoxContainer.new()
	observer_panel.add_child(tools)
	_add_button(tools, "Test player injury", "injury_demo")
	_add_button(tools, "Start raider encounter", "encounter_demo")
	_add_button(tools, "Open / close road", "road")
	_add_button(tools, "Toggle road danger", "risk")
	_add_button(tools, "Toggle trade treaty", "treaty")
	_add_button(tools, "Load recipe.json", "mod")
	sound_button = _add_button(tools, "Sound on", "sound")
	motion_button = _add_button(tools, "Motion: full", "motion")
	_add_button(tools, "Toggle movement details", "details")
	_add_button(tools, "Larger text", "large_text")
	for direction in ["up", "left", "down", "right"]:
		_add_button(tools, "Bind move " + direction, "bind:walk_" + direction)
	_add_button(tools, "Cancel selected worker's job", "cancel")

func _button(parent: Control, label: String, command: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(48, 24)
	button.pressed.connect(func() -> void: action.emit(command))
	parent.add_child(button)
	return button

func _add_button(parent: Control, label: String, command: String) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: action.emit(command))
	parent.add_child(button)
	return button

func refresh(sim: RefCounted, clock: RefCounted, _selected: int, frame_ms: float) -> void:
	var s: Dictionary = sim.state
	var day: int = s.tick / 14400 + 1
	var minute: int = (s.tick / 10) % 1440
	var part: String = load("res://sim/world/day_clock.gd").phase_name(s).to_upper()
	heading.text = "ALDER HOLLOW · DAY %d · %02d:%02d · %s" % [day, minute / 60, minute % 60, part]
	var stock: Dictionary = s.inventories[str(s.warehouse)].items
	var clock_state: String = ("Paused · " if clock.paused else "") + "%d×" % clock.speed
	var local_count: int = s.residents.values().filter(func(npc: Dictionary) -> bool: return npc.settlement == 1 and npc.health > 0).size()
	stats.text = "%d local residents   ·   %d logs  %d food  %d planks   ·   %s   ·   %.1f ms" % [local_count, stock.get("log", 0), stock.get("food", 0), stock.get("plank", 0), clock_state, frame_ms]
	pause_button.text = "Resume" if clock.paused else "Pause"
	stamina_bar.value = s.get("player_health", {}).get("stamina", 100)
	stamina_bar.max_value = s.get("player_health", {}).get("stamina_max", 100)
	if not details_visible: stats.visible = false

func toggle_observer() -> void:
	observer_panel.visible = not observer_panel.visible

func toggle_details() -> void:
	details_visible = not details_visible
	stats.visible = details_visible
	notice.visible = details_visible

func toggle_large_text() -> void:
	large_text = not large_text
	stats.add_theme_font_size_override("font_size", 16 if large_text else 12)
	notice.add_theme_font_size_override("font_size", 18 if large_text else 14)
