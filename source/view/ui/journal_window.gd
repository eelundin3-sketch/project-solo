extends Control
## The journal (J): a parchment book of what you know. Pages: People you've met (their trade,
## town and how they feel about you), News you've heard, Favours (what you promised, what you did)
## and You (your standing in each town, how you look, what you carry). Reads simulation state
## only; nothing here changes the world.
const Society = preload("res://sim/factions/society.gd")
const Reputation = preload("res://sim/factions/reputation.gd")
const Requests = preload("res://sim/player/requests.gd")
const WIDTH := 760.0
const HEIGHT := 520.0
const BAR := 34.0
const WOOD := Color("231a12")
const WOOD_EDGE := Color("5b4429")
const PAPER := Color("efe2c2")
const PAPER_SHADE := Color("e2d1aa")
const RULE := Color(0.42, 0.31, 0.18, 0.28)
const INK := Color("33251a")
const INK_SOFT := Color("6e5a42")
const PAGES := [["people", "People"], ["news", "News"], ["favours", "Favours"], ["you", "You"]]
const ROWS := 9

var simulation: RefCounted
var page: String = "people"
var buttons: Array = []
var hover: int = -1
var _serif: Font
var _sans: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(WIDTH, HEIGHT)
	custom_minimum_size = size
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Baskerville", "Georgia", "Times New Roman", "serif"])
	serif.font_weight = 600
	_serif = serif
	_sans = ThemeDB.fallback_font

func toggle() -> void:
	visible = not visible
	if visible:
		position = ((get_viewport_rect().size - size) * 0.5).floor()
		queue_redraw()

func refresh() -> void:
	if visible: queue_redraw()

## What each page lists, as [title, detail] rows (newest first).
func rows(s: Dictionary) -> Array:
	var status: Dictionary = s.get("player_status", {})
	var result: Array = []
	match page:
		"people":
			var met: Dictionary = status.get("met", {})
			var ids: Array = met.keys()
			ids.sort_custom(func(a, b) -> bool: return int(met[a]) > int(met[b]))
			for id in ids:
				var npc: Dictionary = s.get("residents", {}).get(str(id), {})
				var person: Dictionary = s.get("entities", {}).get(str(id), {})
				if npc.is_empty() or person.is_empty(): continue
				var town: String = str(s.settlements.get(str(npc.settlement), {}).get("name", ""))
				var feeling: int = Society.opinion(s, int(id), int(s.player))
				var word: String = "dead" if int(npc.health) <= 0 else ("warm to you" if feeling >= 35 else ("friendly" if feeling >= 15 else ("cold to you" if feeling <= -30 else ("wary" if feeling <= -10 else "neutral"))))
				result.append([str(person.name), "%s of %s · %s" % [str(npc.occupation), town, word]])
		"news":
			# The sheriffs' cases you know of (investigation.gd), then what you've heard.
			for c in s.get("law", {}).get("cases", []):
				var who: String = str(s.entities.get(str(c.victim), {}).get("name", "Someone"))
				var town_name: String = str(s.settlements.get(str(c.town), {}).get("name", ""))
				var state: String = {"solved": "solved", "outlaw": "closed: an outlaw", "suspect": "the sheriff suspects you", "unsolved": "open, nobody saw anything", "missing": "open: still missing"}.get(str(c.get("outcome", "")), "under investigation")
				result.append(["Case: %s%s" % [who, (" (%s)" % c.cause) if str(c.get("cause", "")) != "" else ""], "%s · %s" % [town_name, state]])
			var heard: Array = status.get("heard", [])
			for index in range(heard.size() - 1, -1, -1):
				result.append([str(heard[index].text), "Heard from %s, day %d" % [str(heard[index].get("from", "someone")), int(heard[index].tick) / 14400 + 1]])
		"favours":
			var list: Array = s.get("requests", {}).values()
			list.sort_custom(func(a, b) -> bool: return int(a.id) > int(b.id))
			for request in list:
				if not str(request.state) in ["accepted", "done", "failed"]: continue
				var giver: String = str(s.entities.get(str(request.giver), {}).get("name", "Someone"))
				var state: String = {"accepted": "promised, due day %d" % (int(request.deadline) / 14400 + 1), "done": "done", "failed": "let them down"}[str(request.state)]
				result.append([Requests.describe(s, request).split(".")[0] + ".", "%s · %s" % [giver, state]])
		"you":
			var keys: Array = s.get("settlements", {}).keys()
			keys.sort()
			for key in keys:
				var standing: int = Reputation.value(s, int(key))
				result.append([str(s.settlements[key].name), "You are %s here (%+d)" % [Reputation.label(standing), standing]])
			for key in keys:
				var record: Dictionary = s.get("law", {}).get("wanted", {}).get(key, {})
				if record.is_empty(): continue
				var Notoriety = load("res://sim/law/notoriety.gd")
				result.append(["Wanted in %s" % str(s.settlements[key].name), "%s · %d hours · known by %s" % [Notoriety.crimes_line(s, int(key)), int(record.hours), "face" if bool(record.get("face", false)) else "your clothes"]])
			var Look = load("res://sim/player/look.gd")
			result.append(["Your looks", "You look %s." % Look.label(s)])
			var Encumbrance = load("res://sim/player/encumbrance.gd")
			result.append(["Your pack", Encumbrance.describe(s, int(s.player))])
	return result

func _draw() -> void:
	buttons.clear()
	if simulation == null: return
	var s: Dictionary = simulation.state
	var frame := StyleBoxFlat.new()
	frame.bg_color = WOOD
	frame.set_corner_radius_all(12)
	frame.border_color = WOOD_EDGE
	frame.set_border_width_all(2)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 22
	frame.anti_aliasing = true
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	draw_string(_serif, Vector2(0, BAR * 0.5 + 6.0), "Journal", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color("e9dcbc"))
	draw_circle(Vector2(20, BAR * 0.5), 6.2, Color("ff5f57"))
	buttons.append({"rect": Rect2(Vector2(12, 9), Vector2(16, 16)), "kind": "close", "page": ""})
	var sheet := Rect2(Vector2(12, BAR + 6), size - Vector2(24, BAR + 18))
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(8)
	draw_style_box(paper, sheet)
	var x: float = sheet.position.x + 18
	for entry in PAGES:
		var w: float = _sans.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
		var rect := Rect2(Vector2(x, sheet.position.y + 14), Vector2(w, 26))
		var open: bool = entry[0] == page
		buttons.append({"rect": rect, "kind": "page", "page": entry[0]})
		var tab := StyleBoxFlat.new()
		tab.bg_color = Color("fbf4e2") if open else Color(PAPER_SHADE, 0.9 if buttons.size() - 1 == hover else 0.6)
		tab.border_color = Color(0.42, 0.31, 0.18, 0.5)
		tab.set_border_width_all(1)
		tab.corner_radius_top_left = 7
		tab.corner_radius_top_right = 7
		draw_style_box(tab, rect)
		draw_string(_serif if open else _sans, rect.position + Vector2(0, 18), entry[1], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14 if open else 13, INK if open else INK_SOFT)
		x += w + 6
	var top: float = sheet.position.y + 40
	draw_line(Vector2(sheet.position.x + 18, top), Vector2(sheet.end.x - 18, top), RULE, 1.0)
	var listed: Array = rows(s)
	if listed.is_empty():
		var empty: String = {"people": "You haven't really met anyone yet. Talk to people.", "news": "You haven't heard any news. Ask people what's going on.", "favours": "No favours promised yet. Ask people if they need help.", "you": ""}[page]
		draw_string(_serif, Vector2(sheet.position.x + 22, top + 40), empty, HORIZONTAL_ALIGNMENT_LEFT, sheet.size.x - 44, 15, INK_SOFT)
		return
	for index in range(mini(listed.size(), ROWS)):
		var y: float = top + 8 + index * 46
		var row := Rect2(Vector2(sheet.position.x + 18, y), Vector2(sheet.size.x - 36, 42))
		if index % 2 == 0: draw_rect(row, Color(PAPER_SHADE, 0.5))
		draw_string(_serif, row.position + Vector2(12, 18), str(listed[index][0]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24, 15, INK)
		draw_string(_sans, row.position + Vector2(12, 35), str(listed[index][1]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 24, 12, INK_SOFT)
	if listed.size() > ROWS:
		draw_string(_sans, Vector2(sheet.position.x + 22, sheet.end.y - 10), "...and %d more" % (listed.size() - ROWS), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_SOFT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for button in buttons:
			if button.rect.has_point(event.position):
				if button.kind == "close": visible = false
				else: page = str(button.page); queue_redraw()
				accept_event()
				return
		accept_event()
	elif event is InputEventMouseMotion:
		var over := -1
		for index in range(buttons.size()):
			if buttons[index].rect.has_point(event.position): over = index
		if over != hover: hover = over; queue_redraw()
