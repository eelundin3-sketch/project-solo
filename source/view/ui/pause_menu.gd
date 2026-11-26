extends CanvasLayer
## The pause menu (Esc while playing). The world stops and dims behind a panel in the middle of the
## screen: Resume, Save game, Load last save, Quit to title, Quit game. Esc again (or Resume) goes
## back to the game. It only emits what was chosen; the controller (world_controller.gd) pauses the
## clock and does the work. Same look as the title screen.
signal chosen(id: String)

const INK := Color("f3e7cc")
const MUTED := Color("b9a98a")
const ACCENT := Color("e2b55a")
const ENTRIES := [["Resume", "resume"], ["Save game", "save"], ["Load last save", "load"], ["Quit to title", "title"], ["Quit game", "quit"]]

var root_control: Control
var status: Label           # "Saved world." and the like, under the buttons
var buttons: Dictionary = {}

func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it gets clicks
	add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -230
	panel.offset_bottom = 230
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 1.0)
	style.border_color = Color(ACCENT, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", INK)
	var heavy := FontVariation.new()
	heavy.base_font = ThemeDB.fallback_font
	heavy.variation_embolden = 0.9
	heavy.spacing_glyph = 3
	title.add_theme_font_override("font", heavy)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	column.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	column.add_child(gap)
	for entry in ENTRIES:
		var button := _button(entry[0])
		button.pressed.connect(func() -> void: chosen.emit(entry[1]))
		column.add_child(button)
		buttons[entry[1]] = button
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", MUTED)
	status.custom_minimum_size = Vector2(0, 18)
	column.add_child(status)
	visible = false

## Shows the menu; `can_load` greys out "Load last save" when there is none.
func open(can_load: bool) -> void:
	status.text = ""
	buttons.load.disabled = not can_load
	visible = true

func close() -> void:
	visible = false

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.content_margin_left = 20
		style.set_corner_radius_all(6)
		match state:
			"normal":
				style.bg_color = Color(0.1, 0.08, 0.06, 0.55)
				style.border_color = Color(1, 1, 1, 0.08)
				style.border_width_left = 3
			"hover", "pressed":
				style.bg_color = Color(0.24, 0.17, 0.08, 0.85) if state == "hover" else Color(0.32, 0.22, 0.09, 0.95)
				style.border_color = ACCENT
				style.border_width_left = 5
				style.content_margin_left = 26
			"disabled":
				style.bg_color = Color(0.1, 0.08, 0.06, 0.3)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("ffe7b0"))
	button.add_theme_color_override("font_pressed_color", Color("ffe7b0"))
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	return button
