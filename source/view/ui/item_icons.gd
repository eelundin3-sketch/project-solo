extends RefCounted
## Small vector pictograms for items, shared by the hotbar and the inventory grid.
static func draw(canvas: CanvasItem, item: String, c: Vector2, alpha: float) -> void:
	var light := Color("efe3c6", alpha)
	var dark := Color("3b2a1d", alpha)
	match item:
		"shotgun":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-22, 2), c + Vector2(-6, -3), c + Vector2(-4, 3), c + Vector2(-18, 8)]), Color("a8743c", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-6, -4), Vector2(11, 7)), Color("5f666a", alpha))
			canvas.draw_line(c + Vector2(4, -1), c + Vector2(23, -1), Color("c9ccc4", alpha), 3.0)
			canvas.draw_line(c + Vector2(2, 3), c + Vector2(16, 3), Color("8a9094", alpha), 2.0)
			canvas.draw_rect(Rect2(c + Vector2(6, 2), Vector2(8, 4)), Color("a8743c", alpha))
		"rifle":   # a long, slim rifle: wooden stock, long barrel, a sight
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-24, 3), c + Vector2(-8, -2), c + Vector2(-5, 3), c + Vector2(-20, 8)]), Color("8e5b2f", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-8, -3), Vector2(10, 5)), Color("5f666a", alpha))
			canvas.draw_line(c + Vector2(1, -1), c + Vector2(26, -1), Color("c9ccc4", alpha), 2.2)
			canvas.draw_rect(Rect2(c + Vector2(2, 0), Vector2(14, 3)), Color("8e5b2f", alpha))
			canvas.draw_line(c + Vector2(-2, -4), c + Vector2(2, -4), Color("3b3f42", alpha), 1.6)
		"cartridge":   # brass cases with lead tips
			for x in [-5.0, 0.0, 5.0]:
				canvas.draw_rect(Rect2(c + Vector2(x - 2, -6), Vector2(4, 13)), Color("d9b45a", alpha))
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(x - 2, -6), c + Vector2(x + 2, -6), c + Vector2(x, -10)]), Color("8a8f93", alpha))
				canvas.draw_rect(Rect2(c + Vector2(x - 2, -6), Vector2(4, 13)), dark, false, 0.8)
		"shell":
			canvas.draw_rect(Rect2(c + Vector2(-5, -9), Vector2(10, 18)), Color("b2392e", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-5, 5), Vector2(10, 4)), Color("d9b45a", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-5, -9), Vector2(10, 18)), dark, false, 1.2)
		"tool":
			canvas.draw_line(c + Vector2(-10, 10), c + Vector2(8, -8), Color("8a5a30", alpha), 4.0)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -14), c + Vector2(14, -6), c + Vector2(10, -1), c + Vector2(-1, -9)]), Color("aab0b4", alpha))
		"bandage":
			canvas.draw_circle(c, 11, light)
			canvas.draw_circle(c, 5, Color("b98c6a", alpha))
			canvas.draw_arc(c, 11, 0, TAU, 20, dark, 1.4)
			canvas.draw_line(c + Vector2(-11, 0), c + Vector2(-17, 7), light, 4.0)
		"antiseptic":
			canvas.draw_rect(Rect2(c + Vector2(-7, -4), Vector2(14, 15)), Color("5a8fb0", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-3, -11), Vector2(6, 8)), Color("d8d2c0", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-7, -4), Vector2(14, 15)), dark, false, 1.2)
		"food":
			canvas.draw_circle(c + Vector2(-5, 2), 8, Color("c98f4b", alpha))
			canvas.draw_circle(c + Vector2(5, 2), 8, Color("c98f4b", alpha))
			canvas.draw_arc(c + Vector2(0, 2), 12, PI, TAU, 14, dark, 1.2)
		"rye":
			for x in [-6, 0, 6]:
				canvas.draw_line(c + Vector2(x, 12), c + Vector2(x, -2), Color("b59a4a", alpha), 2.0)
				canvas.draw_line(c + Vector2(x, -1), c + Vector2(x, -12), Color("e6bf5a", alpha), 4.0)
		"log":
			canvas.draw_rect(Rect2(c + Vector2(-14, -6), Vector2(28, 13)), Color("8a6338", alpha))
			canvas.draw_circle(c + Vector2(14, 0), 6.5, Color("c9a06a", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-14, -6), Vector2(28, 13)), dark, false, 1.2)
		"plank":
			canvas.draw_rect(Rect2(c + Vector2(-15, -4), Vector2(30, 8)), Color("c7a16d", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-15, -4), Vector2(30, 8)), dark, false, 1.2)
		"ore":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-9, -6), c + Vector2(2, -11), c + Vector2(12, -2), c + Vector2(9, 7)]), Color("7d7a6e", alpha))
			canvas.draw_circle(c + Vector2(-2, -3), 2.3, Color("d09a52", alpha))
		"lantern":   # a tin lantern: ring handle, glass with a flame, a base
			canvas.draw_arc(c + Vector2(0, -11), 4.5, PI, TAU, 10, dark, 1.6)
			canvas.draw_rect(Rect2(c + Vector2(-7, -9), Vector2(14, 3)), Color("5f666a", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-6, -6), Vector2(12, 12)), Color("f2c66b", alpha * 0.85))
			canvas.draw_circle(c + Vector2(0, 1), 2.6, Color("fff1c2", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-6, -6), Vector2(12, 12)), dark, false, 1.2)
			canvas.draw_rect(Rect2(c + Vector2(-8, 6), Vector2(16, 4)), Color("5f666a", alpha))
		_:
			canvas.draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 18)), light)

## Clothing pictograms tinted with the garment's colour: hat, vest, shirt, pants and boots.
static func draw_clothing(canvas: CanvasItem, slot: String, tone: Color, c: Vector2, alpha: float) -> void:
	var fill := Color(tone, alpha)
	var shade := Color(tone.darkened(0.35), alpha)
	var ink := Color("3b2a1d", alpha)
	match slot:
		"hat":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-17, 5), c + Vector2(-8, 4), c + Vector2(-7, -8), c + Vector2(7, -8), c + Vector2(8, 4), c + Vector2(17, 5), c + Vector2(12, 9), c + Vector2(-12, 9)]), fill)
			canvas.draw_rect(Rect2(c + Vector2(-8, -1), Vector2(16, 4)), shade)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-17, 5), c + Vector2(-8, 4), c + Vector2(-7, -8), c + Vector2(7, -8), c + Vector2(8, 4), c + Vector2(17, 5), c + Vector2(12, 9), c + Vector2(-12, 9), c + Vector2(-17, 5)]), ink, 1.2, true)
		"vest":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -11), c + Vector2(-4, -11), c + Vector2(0, -4), c + Vector2(4, -11), c + Vector2(11, -11), c + Vector2(12, 11), c + Vector2(-12, 11)]), fill)
			canvas.draw_line(c + Vector2(0, -4), c + Vector2(0, 11), shade, 1.5)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-11, -11), c + Vector2(-4, -11), c + Vector2(0, -4), c + Vector2(4, -11), c + Vector2(11, -11), c + Vector2(12, 11), c + Vector2(-12, 11), c + Vector2(-11, -11)]), ink, 1.2, true)
		"shirt":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11), c + Vector2(-2, -8), c + Vector2(2, -8), c + Vector2(8, -11), c + Vector2(17, -3), c + Vector2(12, 3), c + Vector2(9, 0), c + Vector2(9, 11), c + Vector2(-9, 11), c + Vector2(-9, 0), c + Vector2(-12, 3), c + Vector2(-17, -3)]), fill)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-8, -11), c + Vector2(-2, -8), c + Vector2(2, -8), c + Vector2(8, -11), c + Vector2(17, -3), c + Vector2(12, 3), c + Vector2(9, 0), c + Vector2(9, 11), c + Vector2(-9, 11), c + Vector2(-9, 0), c + Vector2(-12, 3), c + Vector2(-17, -3), c + Vector2(-8, -11)]), ink, 1.2, true)
		"pants":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -11), c + Vector2(10, -11), c + Vector2(12, 12), c + Vector2(3, 12), c + Vector2(0, -2), c + Vector2(-3, 12), c + Vector2(-12, 12)]), fill)
			canvas.draw_line(c + Vector2(-10, -7), c + Vector2(10, -7), shade, 2.0)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-10, -11), c + Vector2(10, -11), c + Vector2(12, 12), c + Vector2(3, 12), c + Vector2(0, -2), c + Vector2(-3, 12), c + Vector2(-12, 12), c + Vector2(-10, -11)]), ink, 1.2, true)
		"pack":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -8), c + Vector2(9, -8), c + Vector2(10, 9), c + Vector2(7, 12), c + Vector2(-7, 12), c + Vector2(-10, 9)]), fill)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-8.5, -8), c + Vector2(8.5, -8), c + Vector2(7.5, 2), c + Vector2(-7.5, 2)]), Color("5a4027", alpha))
			canvas.draw_rect(Rect2(c + Vector2(-9, -13), Vector2(18, 5)), Color("8c8f7e", alpha))
			for x in [-4.0, 4.0]:
				canvas.draw_line(c + Vector2(x, 1), c + Vector2(x, 6), Color("5a4027", alpha), 1.6)
				canvas.draw_rect(Rect2(c + Vector2(x - 1.2, 1), Vector2(2.4, 2)), Color("c9b06a", alpha))
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-9, -8), c + Vector2(9, -8), c + Vector2(10, 9), c + Vector2(7, 12), c + Vector2(-7, 12), c + Vector2(-10, 9), c + Vector2(-9, -8)]), ink, 1.2, true)
		"boots":
			for side in [-1.0, 1.0]:
				var x: float = side * 7.0
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(x - 4, -10), c + Vector2(x + 4, -10), c + Vector2(x + 4, 4), c + Vector2(x + 10, 6), c + Vector2(x + 10, 11), c + Vector2(x - 5, 11)]), fill)
				canvas.draw_rect(Rect2(c + Vector2(x - 5, 8), Vector2(15, 3)), shade)
