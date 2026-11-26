extends RefCounted
## Shared vector art for materials wherever they appear. Detail follows the
## item's own axis, including when a worker carries it at an angle.
const INK := Color("38291f")

static func polygon(c: Node2D, points: PackedVector2Array, fill: Color, stroke: Color = INK, width: float = 0.85) -> void:
	# A shape too thin or twisted to fill (a log seen end-on, a squashed ellipse) is only outlined:
	# filling it makes the renderer log "Invalid polygon data" on every redraw.
	if fillable(points): c.draw_colored_polygon(points, fill)
	if width <= 0: return
	points.append(points[0])
	c.draw_polyline(points, stroke, width, true)

## True if the renderer can fill this outline (it splits into triangles).
static func fillable(points: PackedVector2Array) -> bool:
	return points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty()

static func ellipse(c: Node2D, center: Vector2, radius: Vector2, fill: Color, angle: float = 0.0, stroke: Color = INK, width: float = 0.85) -> void:
	var outline := PackedVector2Array()
	for side in range(24):
		outline.append(center + (Vector2.from_angle(side * TAU / 24.0) * radius).rotated(angle))
	polygon(c, outline, fill, stroke, width)

static func grain(c: Node2D, rect: Rect2, stain: Color) -> void:
	for row in range(4):
		var y := rect.position.y + rect.size.y * (0.18 + row * 0.20)
		var left := rect.position.x + rect.size.x * (0.045 + row % 2 * 0.09)
		var right := rect.end.x - rect.size.x * (0.06 + row % 3 * 0.11)
		c.draw_polyline(PackedVector2Array([
			Vector2(left, y), Vector2(lerpf(left, right, 0.29), y - 0.40),
			Vector2(lerpf(left, right, 0.57), y + 0.35), Vector2(right, y - 0.1),
		]), stain, 0.55, true)

static func nail(c: Node2D, point: Vector2, radius: float = 0.8) -> void:
	c.draw_circle(point, radius, Color("4a4137"), true, -1, true)
	c.draw_line(point + Vector2(-radius * 0.5, -0.35), point + Vector2(0.15, -0.35), Color("c2b2a3"), 0.45, true)

static func log_piece(c: Node2D, start: Vector2, end: Vector2, radius: float = 3.65) -> void:
	var axis := start.direction_to(end)
	if axis.is_zero_approx(): axis = Vector2.RIGHT
	var cross := axis.orthogonal()
	var rim := cross * radius
	polygon(c, PackedVector2Array([start - rim * 0.82, end - rim, end + rim, start + rim * 0.88,
		start - axis * radius * 0.45 + rim * 0.40, start - axis * radius * 0.50 - rim * 0.42]), Color("79533a"))
	for band in range(4):
		var shift := -0.65 + band * 0.39
		var mid := start.lerp(end, 0.43 + (band % 2) * 0.12)
		c.draw_polyline(PackedVector2Array([start + rim * shift, mid + rim * (shift - 0.08),
			end + rim * (shift + 0.04)]), Color("b08458") if band % 2 == 0 else Color("523c2e"), 0.55, true)
	var knot := start.lerp(end, 0.56) - rim * 0.23
	ellipse(c, knot, Vector2(radius * 0.57, radius * 0.27), Color("5b3e2d"), axis.angle(), Color("96734f"), 0.5)
	ellipse(c, end, Vector2(radius * 0.57, radius), Color("d1ac76"), axis.angle(), Color("4e3828"))
	ellipse(c, end - axis * radius * 0.03, Vector2(radius * 0.37, radius * 0.72), Color("deb986"), axis.angle(), Color("ae8056"), 0.5)
	ellipse(c, end + rim * 0.05, Vector2(radius * 0.18, radius * 0.37), Color("d2a36e"), axis.angle(), Color("a57952"), 0.45)
	c.draw_line(end - rim * 0.15, end + rim * 0.85 - axis * radius * 0.16, Color("9f7550"), 0.48, true)

static func plank(c: Node2D, start: Vector2, end: Vector2, width: float = 3.0, shade: Color = Color("c6a16b")) -> void:
	var axis := start.direction_to(end)
	if axis.is_zero_approx(): axis = Vector2.RIGHT
	var cross := axis.orthogonal()
	var rim := cross * width
	var depth := axis * 0.8 + cross * (2.1 if cross.y >= 0.0 else -2.1)
	polygon(c, PackedVector2Array([start + rim, end + rim, end + rim + depth, start + rim + depth]), shade.darkened(0.33))
	polygon(c, PackedVector2Array([end - rim, end + rim, end + rim + depth, end - rim + depth]),
		shade.darkened(0.22), INK, 0)
	c.draw_polyline(PackedVector2Array([end - rim, end - rim + depth, end + rim + depth]), INK, 0.65, true)
	polygon(c, PackedVector2Array([start - rim, end - rim, end + rim, start + rim]), shade)
	for row in range(3):
		var push := rim * (-0.62 + row * 0.56)
		c.draw_line(start.lerp(end, 0.07 + row * 0.02) + push, end.lerp(start, 0.08) + push * 0.83,
			shade.darkened(0.22) if row == 1 else shade.lightened(0.19), 0.55, true)

static func supply(c: Node2D, p: Vector2, kind: String, scale: float = 1.0) -> void:
	match kind:
		"food":
			ellipse(c, p + Vector2(0, 0.7) * scale, Vector2(8.1, 4.4) * scale, Color("9b6d43"))
			for y in [0, 2]:
				c.draw_line(p + Vector2(-6, y) * scale, p + Vector2(6, y) * scale, Color("694a35"), 0.5, true)
			ellipse(c, p - Vector2(0, 2.0) * scale, Vector2(8, 3.2) * scale, Color("755139"), 0.0, Color("cfab75"))
			ellipse(c, p + Vector2(-3.3, -3.1) * scale, Vector2(3.3, 2.8) * scale, Color("7c8e54"), -0.3, Color("3c533b"), 0.58)
			ellipse(c, p + Vector2(0.2, -3.9) * scale, Vector2(2.8, 2.3) * scale, Color("9ea56c"), 0.22, Color("516841"), 0.55)
			ellipse(c, p + Vector2(3.4, -1.9) * scale, Vector2(3.9, 1.4) * scale, Color("c48c50"), 0.46, Color("845d35"), 0.55)
			c.draw_line(p + Vector2(0.8, -3.4) * scale, p + Vector2(-0.2, -5.9) * scale, Color("4b663b"), 0.8, true)
		"bandage":
			ellipse(c, p, Vector2(6.8, 3.5) * scale, Color("c9c6b5"))
			ellipse(c, p - Vector2(0, 2.9) * scale, Vector2(6.7, 3.5) * scale, Color("ebe5cf"))
			ellipse(c, p - Vector2(0, 2.9) * scale, Vector2(3.5, 1.9) * scale, Color("d6d1bd"), 0.0, Color("9c9887"), 0.5)
			ellipse(c, p - Vector2(0, 2.9) * scale, Vector2(1.2, 0.8) * scale, Color("716657"), 0.0, INK, 0.0)
			c.draw_line(p + Vector2(-5.8, -0.9) * scale, p + Vector2(4.7, 1.5) * scale, Color("f3ebd1"), 0.55, true)
		"antiseptic":
			var points := PackedVector2Array()
			for v in [Vector2(-4, 1), Vector2(-5, -1), Vector2(-5, -6), Vector2(-2.4, -8.3),
				Vector2(-2.4, -11), Vector2(2.4, -11), Vector2(2.4, -8.3), Vector2(5, -6), Vector2(5, -1), Vector2(4, 1)]:
				points.append(p + v * scale)
			polygon(c, points, Color("526d60"))
			c.draw_rect(Rect2(p + Vector2(-4.2, -5.8) * scale, Vector2(8.4, 4.1) * scale), Color("c9be9a"))
			c.draw_line(p + Vector2(-3.2, -4) * scale, p + Vector2(2.6, -4) * scale, Color("8b7961"), 0.48, true)
			c.draw_line(p + Vector2(-3, -7) * scale, p + Vector2(-3.5, -1) * scale, Color("a9bfaf"), 0.6, true)
			ellipse(c, p - Vector2(0, 10.8) * scale, Vector2(2.8, 1.25) * scale, Color("b9986d"))
