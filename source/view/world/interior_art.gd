extends RefCounted
## Furniture drawn in a low oblique view, with material detail sized to the prop.
const Props = preload("res://view/world/prop_art.gd")
const INK := Color("3b2a1d")

static func slab(c: Node2D, r: Rect2, color: Color, depth: float = 5.0) -> void:
	var front := Rect2(Vector2(r.position.x, r.end.y), Vector2(r.size.x, depth))
	c.draw_rect(front, color.darkened(0.34))
	c.draw_rect(front, INK, false, 0.8)
	c.draw_rect(r, color)
	c.draw_rect(r, INK, false, 1.0)
	c.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), color.lightened(0.20), 0.75, true)

static func timber(c: Node2D, r: Rect2, color: Color, depth: float = 4.0) -> void:
	slab(c, r, color, depth)
	if r.size.x > 9 and r.size.y > 4:
		Props.grain(c, r.grow(-1), color.darkened(0.18))

static func bed(c: Node2D, p: Vector2, color: Color) -> void:
	c.draw_rect(Rect2(p + Vector2(0, 2), Vector2(64, 33)), Color(0, 0, 0, 0.16))   # contact only: no sun indoors
	timber(c, Rect2(p, Vector2(64, 33)), Color("795332"))
	for leg in [Vector2(3, 30), Vector2(59, 30)]:
		timber(c, Rect2(p + leg, Vector2(4, 5)), Color("725034"), 1.5)
	slab(c, Rect2(p + Vector2(5, 4), Vector2(54, 24)), Color("d8cfb2"), 2.0)
	slab(c, Rect2(p + Vector2(19, 4), Vector2(40, 25)), color, 1.7)
	for y in [8, 16, 24]:
		c.draw_polyline(PackedVector2Array([p + Vector2(21, y), p + Vector2(33, y + 1),
			p + Vector2(44, y + 0.4), p + Vector2(57, y + 1)]), color.darkened(0.21), 0.62, true)
	c.draw_line(p + Vector2(22, 5), p + Vector2(22, 28), color.lightened(0.32), 1.1, true)
	c.draw_line(p + Vector2(56, 5), p + Vector2(56, 28), color.darkened(0.22), 0.75, true)
	Props.ellipse(c, p + Vector2(12, 16), Vector2(6.5, 8.8), Color("eee1c2"), -0.14, Color("a89b7f"))
	Props.ellipse(c, p + Vector2(11.6, 15.5), Vector2(4.2, 7.1), Color("e3d7b9"), -0.14, Color("d1c3a3"), 0.55)
	timber(c, Rect2(p - Vector2(2, 3), Vector2(6, 35)), Color("946239"))
	for corner in [Vector2(0, -2), Vector2(0, 30), Vector2(61, 1), Vector2(61, 31)]:
		Props.nail(c, p + corner, 0.7)

static func table(c: Node2D, p: Vector2) -> void:
	for offset in [Vector2(3, 4), Vector2(44, 4), Vector2(3, 30), Vector2(44, 30)]:
		timber(c, Rect2(p + offset, Vector2(4, 8)), Color("67452e"), 1.0)
	timber(c, Rect2(p, Vector2(50, 32)), Color("a77a4a"), 4.0)
	for y in [8, 16, 24]:
		c.draw_line(p + Vector2(1, y), p + Vector2(49, y), Color("704c31"), 0.65)
		Props.grain(c, Rect2(p + Vector2(2, y - 7), Vector2(46, 7)), Color("92603c"))
	for x in [3, 47]:
		for y in [3, 28]: Props.nail(c, p + Vector2(x, y), 0.68)
	Props.ellipse(c, p + Vector2(15, 17), Vector2(7.3, 5.9), Color("d6c4a1"), 0.0, Color("73634d"))
	Props.ellipse(c, p + Vector2(15, 17), Vector2(4.8, 3.8), Color("ac9373"), 0.0, Color("ad9d84"), 0.55)
	Props.ellipse(c, p + Vector2(35, 14), Vector2(2.6, 2.0), Color("d4a676"))
	slab(c, Rect2(p + Vector2(30, 13), Vector2(6, 6)), Color("c4a17c"), 1.0)
	Props.ellipse(c, p + Vector2(33, 13), Vector2(3, 2), Color("795843"), 0.0, Color("e5c396"), 0.55)

static func shelf(c: Node2D, p: Vector2, width: float = 58) -> void:
	timber(c, Rect2(p, Vector2(width, 31)), Color("785134"), 4.0)
	c.draw_rect(Rect2(p + Vector2(3, 3), Vector2(width - 6, 25)), Color("543929"))
	for row in range(2):
		for col in range(int((width - 5) / 13)):
			var q := p + Vector2(7 + col * 13, 11 + row * 14)
			match (col + row * 2) % 3:
				0:
					timber(c, Rect2(q - Vector2(1, 6), Vector2(9, 7)), Color("aa8555"), 1)
					c.draw_line(q - Vector2(0, 5), q + Vector2(7, 0), Color("d2ad71"), 0.8, true)
				1:
					Props.ellipse(c, q + Vector2(3, -3), Vector2(3.5, 4.5), Color("9a886a"))
					Props.ellipse(c, q + Vector2(3, -6), Vector2(2.4, 1.2), Color("b9a07d"))
				2:
					c.draw_rect(Rect2(q + Vector2(0, -6), Vector2(8, 7)), Color("838b6e"))
					c.draw_line(q + Vector2(1, -5), q + Vector2(7, -5), Color("b2b397"), 0.7, true)
		timber(c, Rect2(p + Vector2(1, 12 + row * 14), Vector2(width - 2, 3)), Color("b08351"), 1.6)
	for x in [2.0, width - 2.5]:
		for y in [3, 15, 29]: Props.nail(c, p + Vector2(x, y), 0.65)

static func stove(c: Node2D, p: Vector2) -> void:
	slab(c, Rect2(p, Vector2(27, 30)), Color("5e6058"))
	slab(c, Rect2(p + Vector2(4, 12), Vector2(19, 14)), Color("3f433f"), 1.3)
	for side in [7, 20]: Props.nail(c, p + Vector2(side, 16))
	c.draw_line(p + Vector2(10, 20), p + Vector2(18, 20), Color("a28b66"), 1.6, true)
	c.draw_circle(p + Vector2(11, 7), 5.4, Color("373a36"), true, -1, true)
	c.draw_arc(p + Vector2(11, 7), 3.7, 0, TAU, 24, Color("787971"), 0.6, true)
	c.draw_line(p + Vector2(21, 0), p + Vector2(21, -20), Color("3c3d36"), 7, true)
	c.draw_line(p + Vector2(19.5, 0), p + Vector2(19.5, -20), Color("787b6c"), 1.2, true)
	Props.ellipse(c, p + Vector2(21, -20), Vector2(3.8, 1.8), Color("292d2a"), 0.0, Color("77766c"))

static func workbench(c: Node2D, p: Vector2, phase: float = 0.0, logs: int = 0) -> void:
	var metal := Color("596461")
	c.draw_rect(Rect2(p + Vector2(1, 16), Vector2(97, 26)), Color(0, 0, 0, 0.20))
	for x in [7, 84]:
		timber(c, Rect2(p + Vector2(x, 23), Vector2(7, 14)), Color("795436"), 3)
	timber(c, Rect2(p + Vector2(8, 33), Vector2(78, 3)), Color("997046"), 2)
	timber(c, Rect2(p, Vector2(96, 29)), Color("9c7049"), 4.5)
	for y in [4.0, 23.0]:
		slab(c, Rect2(p + Vector2(4, y), Vector2(88, 3.3)), Color("68736e"), 1.2)
		for x in [8.0, 29.0, 70.0, 87.0]:
			Props.nail(c, p + Vector2(x, y + 1.7), 0.7)
	for x in [13.0, 28.0, 43.0, 74.0, 88.0]:
		slab(c, Rect2(p + Vector2(x, 8), Vector2(2.4, 15)), Color("a4aba0"), 0.8)
	slab(c, Rect2(p + Vector2(9, 27), Vector2(20, 11)), metal.darkened(0.19), 1.6)
	for fin in range(4):
		var x := 11.5 + fin * 3.2
		c.draw_line(p + Vector2(x, 29), p + Vector2(x, 35), metal.lightened(0.28), 0.85, true)
	var drive := p + Vector2(27, 34)
	var arbor := p + Vector2(58, 31)
	c.draw_line(drive + Vector2(0, -4), arbor + Vector2(0, -5), Color("352e2a"), 2.8, true)
	c.draw_line(drive + Vector2(0, 4), arbor + Vector2(0, 5), Color("433a30"), 2.8, true)
	for pulley in [drive, arbor]:
		Props.ellipse(c, pulley, Vector2(5.7, 5.1), metal)
		for spoke in range(3):
			c.draw_line(pulley, pulley + Vector2.from_angle(phase + spoke * TAU / 3.0) * 4, Color("b8bdab"), 0.72, true)
		Props.nail(c, pulley, 1.1)

	slab(c, Rect2(p + Vector2(43, 10), Vector2(30, 11)), metal.darkened(0.28), 1.1)
	if logs > 0:
		var feed := sin(phase * 0.35) * 4.0
		Props.log_piece(c, p + Vector2(6 + feed, 15), p + Vector2(55 + feed, 15), 5.0)
	var center := p + Vector2(58, 12)
	var teeth := PackedVector2Array()
	for index in range(64):
		var angle := phase + index * TAU / 64.0
		var radius := 12.4 if index % 4 in [0, 1] else 10.8
		teeth.append(center + Vector2(cos(angle), sin(angle) * 0.66) * radius)
	Props.polygon(c, teeth, Color("b6bfb6"), Color("394441"), 0.66)
	Props.ellipse(c, center, Vector2(7.6, 4.9), Color("9ea99f"), 0.0, Color("6e7b73"), 0.55)
	Props.ellipse(c, center, Vector2(2.8, 1.9), Color("68756d"))
	Props.nail(c, center, 1.0)
	var guard := PackedVector2Array()
	for i in range(13):
		var angle := PI + i * PI / 12.0
		guard.append(center + Vector2(cos(angle) * 14, sin(angle) * 9.5) + Vector2(0, -0.5))
	c.draw_polyline(guard, Color("4a534e"), 3.1, true)
	c.draw_polyline(guard, Color("8b998e"), 1.45, true)
	Props.nail(c, center + Vector2(14, -0.3), 0.9)

## Brick bread oven: domed firebox with a glowing mouth, peel and loaves cooling on the rack.
static func oven(c: Node2D, p: Vector2, phase: float, active: bool, grain: int, loaves: int) -> void:
	c.draw_rect(Rect2(p + Vector2(2, 22), Vector2(94, 24)), Color(0, 0, 0, 0.20))
	slab(c, Rect2(p + Vector2(6, 8), Vector2(50, 30)), Color("8c5b45"), 5.0)
	for row in range(4):
		for col in range(6):
			var offset: float = 4.0 if row % 2 else 0.0
			c.draw_rect(Rect2(p + Vector2(8 + col * 8 + offset, 10 + row * 7), Vector2(7, 5.5)), Color("a56b4f") if (row + col) % 3 else Color("93604a"))
	Props.ellipse(c, p + Vector2(31, 8), Vector2(26, 11), Color("a2674d"), 0.0, INK, 0.9)
	Props.ellipse(c, p + Vector2(31, 26), Vector2(11, 8), Color("26211d"), 0.0, Color("5a4638"))
	var glow: float = (0.6 + 0.4 * sin(phase * 0.8)) if active else 0.22
	Props.ellipse(c, p + Vector2(31, 28), Vector2(8, 5), Color(0.95, 0.5, 0.15, glow))
	Props.ellipse(c, p + Vector2(31, 29), Vector2(4.5, 2.8), Color(1.0, 0.82, 0.35, glow))
	timber(c, Rect2(p + Vector2(60, 16), Vector2(34, 6)), Color("9c7049"), 3.0)
	for i in range(mini(4, ceili(loaves / 4.0))):
		Props.ellipse(c, p + Vector2(66 + i * 7, 13), Vector2(4.5, 3.0), Color("c98f4b"), 0.0, Color("8d5d2e"), 0.7)
	for i in range(mini(3, ceili(grain / 6.0))):
		Props.ellipse(c, p + Vector2(68 + i * 8, 29), Vector2(5, 4), Color("c9b172"), 0.0, Color("8a7646"), 0.6)

## Small smithy: brick forge hearth, anvil on a stump and a quench barrel.
static func forge(c: Node2D, p: Vector2, phase: float, active: bool) -> void:
	c.draw_rect(Rect2(p + Vector2(2, 22), Vector2(94, 24)), Color(0, 0, 0, 0.20))
	slab(c, Rect2(p + Vector2(6, 10), Vector2(44, 28)), Color("6a6a64"), 5.0)
	var glow: float = (0.7 + 0.3 * sin(phase * 1.1)) if active else 0.25
	Props.ellipse(c, p + Vector2(28, 22), Vector2(15, 7), Color(0.9, 0.38, 0.1, glow), 0.0, INK, 0.8)
	Props.ellipse(c, p + Vector2(28, 23), Vector2(8, 3.6), Color(1.0, 0.78, 0.3, glow))
	timber(c, Rect2(p + Vector2(60, 24), Vector2(10, 12)), Color("7a5a3a"), 2.0)
	slab(c, Rect2(p + Vector2(54, 16), Vector2(22, 8)), Color("4b4f53"), 2.0)
	c.draw_line(p + Vector2(76, 19), p + Vector2(84, 21), Color("4b4f53"), 3.0, true)
	Props.ellipse(c, p + Vector2(88, 30), Vector2(7, 9), Color("5d4630"), 0.0, INK, 0.8)

## Sheriff's wall rack: a pegged board holding the shotguns that are actually in the
## rack's stock, plus a box of shells on the shelf below.
static func weapon_rack(c: Node2D, p: Vector2, shotguns: int, shells: int) -> void:
	c.draw_rect(Rect2(p + Vector2(2, 30), Vector2(94, 16)), Color(0, 0, 0, 0.18))
	timber(c, Rect2(p + Vector2(0, -4), Vector2(96, 36)), Color("6f4a2c"), 3.0)
	for y in [8.0, 18.0, 28.0]:
		c.draw_line(p + Vector2(3, y), p + Vector2(93, y), Color("4d3320"), 1.0)
	for slot in range(2):
		var y := 2.0 + slot * 12.0
		timber(c, Rect2(p + Vector2(8, y + 4), Vector2(80, 2.4)), Color("a77a49"), 0.8)
		for x in [14.0, 70.0]:
			Props.nail(c, p + Vector2(x, y + 5.2), 0.95)
		if slot < shotguns:
			var g := p + Vector2(10, y + 1.0)
			# walnut stock, receiver, barrel and magazine tube drawn side-on
			c.draw_colored_polygon(PackedVector2Array([g, g + Vector2(22, 0.5), g + Vector2(22, 4.5), g + Vector2(2, 5.5), g + Vector2(-1, 3)]), Color("8a5a30"))
			c.draw_polyline(PackedVector2Array([g, g + Vector2(22, 0.5), g + Vector2(22, 4.5), g + Vector2(2, 5.5), g + Vector2(-1, 3), g]), INK, 0.8, true)
			slab(c, Rect2(g + Vector2(22, 0.2), Vector2(8, 4.6)), Color("4f5558"), 0.6)
			c.draw_line(g + Vector2(30, 1.6), g + Vector2(74, 1.6), Color("6a7074"), 2.0, true)
			c.draw_line(g + Vector2(30, 4.0), g + Vector2(64, 4.0), Color("5a6064"), 1.4, true)
			timber(c, Rect2(g + Vector2(42, 3.2), Vector2(16, 3.8)), Color("9a6a3a"), 0.6)
	var box := Rect2(p + Vector2(66, 28), Vector2(22, 10))
	slab(c, box, Color("a2332a"), 1.6)
	c.draw_rect(Rect2(box.position + Vector2(2, 2), Vector2(18, 3)), Color("e4d2a0"))
	c.draw_string(ThemeDB.fallback_font, p + Vector2(4, 40), "%d shells" % shells, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f1dfac"))
	c.draw_string(ThemeDB.fallback_font, p + Vector2(4, 28), "RACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("d8c593"))

## Vertical bed (2 cells wide, 3 tall). `head_up` puts the pillow at the top, otherwise the bottom.
static func bed_vertical(c: Node2D, p: Vector2, color: Color, head_up: bool) -> void:
	var w := 33.0
	var h := 64.0
	c.draw_rect(Rect2(p + Vector2(0, 2), Vector2(w, h)), Color(0, 0, 0, 0.16))   # contact only: no sun indoors
	timber(c, Rect2(p, Vector2(w, h)), Color("795332"))
	slab(c, Rect2(p + Vector2(4, 5), Vector2(w - 8, h - 10)), Color("d8cfb2"), 2.0)
	var head_y: float = 6.0 if head_up else h - 26.0
	var blanket_y: float = 24.0 if head_up else 6.0
	slab(c, Rect2(p + Vector2(4, blanket_y), Vector2(w - 8, h - 31.0)), color, 1.7)
	for x in [10.0, 17.0, 24.0]:
		c.draw_polyline(PackedVector2Array([p + Vector2(x, blanket_y + 2), p + Vector2(x + 1, blanket_y + 14), p + Vector2(x, blanket_y + 26), p + Vector2(x + 1, blanket_y + 36)]), color.darkened(0.21), 0.62, true)
	Props.ellipse(c, p + Vector2(w / 2.0, head_y + 9.0), Vector2(11.0, 7.0), Color("eee1c2"), 0.0, Color("a89b7f"))
	Props.ellipse(c, p + Vector2(w / 2.0 - 0.5, head_y + 8.0), Vector2(8.0, 4.6), Color("e3d7b9"), 0.0, Color("d1c3a3"), 0.55)
	var head_board_y: float = -3.0 if head_up else h - 3.0
	timber(c, Rect2(p + Vector2(-2, head_board_y), Vector2(w + 4, 6)), Color("946239"))
	var foot_y: float = h - 1.0 if head_up else -1.0
	timber(c, Rect2(p + Vector2(0, foot_y), Vector2(w, 3)), Color("725034"), 1.5)
