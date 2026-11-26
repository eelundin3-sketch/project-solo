extends RefCounted
## The things in your house and on its terrace: the plank deck and its railing, the kitchen counter,
## the fridge (its door swings open when you take a drink), the sofa, the fireplace, and the workout
## gear: the squat rack, the bench press, the deadlift platform, the pull-up bar and the plate
## tree. A bar in your hands is drawn with you (drawn_character.gd uses `barbell` too), so the rack
## or platform then shows empty. `p` is the piece's top-left corner in pixels, `size` its size.
const STEEL := Color("8e9296")
const STEEL_DARK := Color("4e5155")
const PLATE := Color("26282b")
const PLATE_RIM := Color("54575b")
const WOOD := Color("9c7246")
const WOOD_DARK := Color("6b4b2c")

## A loaded barbell from `a` to `b` (its two ends, where the plates sit), seen slightly from above.
static func barbell(c: CanvasItem, a: Vector2, b: Vector2, plates: int = 2, size: float = 1.0) -> void:
	var along: Vector2 = (b - a).normalized() if a.distance_to(b) > 0.5 else Vector2.RIGHT
	c.draw_line(a - along * 4.0 * size, b + along * 4.0 * size, STEEL_DARK, 3.0 * size, true)
	c.draw_line(a - along * 4.0 * size, b + along * 4.0 * size, STEEL, 1.6 * size, true)
	for end in [a, b]:
		for k in range(plates):
			var at: Vector2 = end + along * (float(k) * 2.4 * size * (-1.0 if end == a else 1.0))
			var ring := Vector2(2.2, 9.0 - float(k) * 1.5) * size
			var pts := PackedVector2Array()
			for i in range(14):
				var ang: float = float(i) / 14.0 * TAU
				pts.append(at + Vector2(cos(ang) * ring.x, sin(ang) * ring.y).rotated(along.angle()))
			c.draw_colored_polygon(pts, PLATE)
			pts.append(pts[0])
			c.draw_polyline(pts, PLATE_RIM, 0.8, true)

static func deck(c: CanvasItem, p: Vector2, size: Vector2) -> void:
	c.draw_rect(Rect2(p + Vector2(-12, -12), size), Color("b28a5a"))
	var y: float = p.y - 12.0
	var row := 0
	while y < p.y - 12.0 + size.y:
		c.draw_line(Vector2(p.x - 12, y), Vector2(p.x - 12 + size.x, y), Color("8d6a42"), 1.0)
		# Board ends, staggered row to row.
		var x: float = p.x - 12.0 + (24.0 if row % 2 == 0 else 60.0)
		while x < p.x - 12.0 + size.x:
			c.draw_line(Vector2(x, y), Vector2(x, y + 8), Color("8d6a42"), 0.8)
			x += 96.0
		y += 8.0
		row += 1
	# A low railing round the open sides (north, east, west), posts every couple of cells.
	var r := Rect2(p + Vector2(-12, -12), size)
	for edge in [[r.position, Vector2(r.end.x, r.position.y)], [r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]:
		c.draw_line(edge[0] + Vector2(0, -6), edge[1] + Vector2(0, -6), WOOD_DARK, 2.0)
		var length: float = edge[0].distance_to(edge[1])
		var steps: int = maxi(1, int(length / 40.0))
		for i in range(steps + 1):
			var post: Vector2 = edge[0].lerp(edge[1], float(i) / float(steps))
			c.draw_line(post, post + Vector2(0, -8), WOOD_DARK, 2.5)

static func counter(c: CanvasItem, p: Vector2, size: Vector2) -> void:
	var r := Rect2(p + Vector2(-10, -8), Vector2(size.x - 4, 20))
	c.draw_rect(r, Color("7b5634"))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), Color("c9b48c"))     # the worktop
	for i in range(int(r.size.x / 20.0)):
		var d := Rect2(r.position + Vector2(3 + i * 20, 9), Vector2(16, 9))
		c.draw_rect(d, Color("8a6340")); c.draw_rect(d, WOOD_DARK, false, 0.8)
		c.draw_circle(d.get_center(), 1.0, Color("d6c08a"))
	c.draw_circle(r.position + Vector2(14, 2), 2.5, Color("e8e0cf"))          # a mug
	c.draw_rect(Rect2(r.position + Vector2(30, -1), Vector2(10, 4)), Color("a0a8ad"))   # a basin

static func fridge(c: CanvasItem, p: Vector2, open: float) -> void:
	var body := Rect2(p + Vector2(-10, -22), Vector2(20, 32))
	c.draw_rect(body, Color("dfe0d6"))
	c.draw_rect(body, Color("9a9b92"), false, 1.0)
	if open <= 0.02:
		c.draw_line(body.position + Vector2(0, 12), Vector2(body.end.x, body.position.y + 12), Color("a9aaa0"), 1.0)
		c.draw_line(body.position + Vector2(16, 4), body.position + Vector2(16, 10), Color("6f706a"), 1.6)
		c.draw_line(body.position + Vector2(16, 15), body.position + Vector2(16, 24), Color("6f706a"), 1.6)
		return
	# Open: lit inside, shelves of bottles, the door swung out to the left.
	var inside := body.grow(-2.0)
	c.draw_rect(inside, Color("fbf6d8"))
	for row in range(3):
		var y: float = inside.position.y + 6.0 + float(row) * 9.0
		c.draw_line(Vector2(inside.position.x, y + 3), Vector2(inside.end.x, y + 3), Color("c2c3b8"), 0.8)
		for k in range(3):
			c.draw_rect(Rect2(Vector2(inside.position.x + 2 + k * 5, y - 3), Vector2(3, 6)), [Color("6b3a22"), Color("3d6b40"), Color("c88a3f")][(k + row) % 3])
	var swing: float = open * 18.0
	if swing >= 1.5: c.draw_colored_polygon(PackedVector2Array([body.position, body.position + Vector2(-swing, 3), Vector2(body.position.x - swing, body.end.y - 3), Vector2(body.position.x, body.end.y)]), Color("cfd0c6"))

static func sofa(c: CanvasItem, p: Vector2, size: Vector2) -> void:
	var r := Rect2(p + Vector2(-10, -6), Vector2(size.x - 4, 20))
	c.draw_rect(r, Color("6e3b2e"))
	c.draw_rect(Rect2(r.position + Vector2(0, 12), Vector2(r.size.x, 8)), Color("552b22"))    # the back, toward you (it faces the fire)
	for i in range(3):
		var cushion := Rect2(r.position + Vector2(4 + i * (r.size.x - 8) / 3.0, 2), Vector2((r.size.x - 8) / 3.0 - 2, 10))
		c.draw_rect(cushion, Color("834a3a"))
	c.draw_rect(Rect2(r.position + Vector2(-2, 0), Vector2(5, 20)), Color("5f3227"))
	c.draw_rect(Rect2(Vector2(r.end.x - 3, r.position.y), Vector2(5, 20)), Color("5f3227"))

static func fireplace(c: CanvasItem, p: Vector2, size: Vector2, time: float) -> void:
	var r := Rect2(p + Vector2(-10, -20), Vector2(size.x - 4, 30))
	c.draw_rect(r, Color("8b8378"))
	for y in range(int(r.position.y) + 4, int(r.end.y), 7):
		c.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("6d665d"), 0.8)
	var mouth := Rect2(r.position + Vector2(8, 10), Vector2(r.size.x - 16, 16))
	c.draw_rect(mouth, Color("1e1612"))
	for k in range(3):
		var flick: float = sin(time * 9.0 + float(k) * 2.1) * 2.0
		var base := Vector2(mouth.position.x + 6 + k * (mouth.size.x - 12) / 2.0, mouth.end.y - 2)
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-4, 0), base + Vector2(0, -10 - flick), base + Vector2(4, 0)]), Color("f09a35"))
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-2, 0), base + Vector2(0, -6 - flick * 0.5), base + Vector2(2, 0)]), Color("ffd772"))
	c.draw_rect(Rect2(r.position + Vector2(-3, 6), Vector2(r.size.x + 6, 4)), Color("6b5a49"))   # the mantel

## Uprights and J-hooks; the bar sits on the hooks unless it's in your hands. Lined up with the
## lifter under the bar (drawn_character.gd `_home_pose`): bar centre 24 px right of and 9 px below
## the first cell's centre, plates 25 px out each side; the uprights stand on the floor where your
## feet are when you're under it.
static func squat_rack(c: CanvasItem, p: Vector2, size: Vector2, bar_out: bool) -> void:
	var cx: float = p.x - 12.0 + size.x * 0.5
	var hooks: float = p.y + 9.0
	var floor_y: float = p.y + 40.0
	for x in [cx - 31.0, cx + 31.0]:
		c.draw_rect(Rect2(Vector2(x - 3, floor_y - 64), Vector2(6, 64)), STEEL_DARK)
		c.draw_rect(Rect2(Vector2(x - 2, floor_y - 64), Vector2(2, 64)), STEEL)
		for y in range(-58, -4, 7): c.draw_circle(Vector2(x, floor_y + y), 0.8, Color("2a2c2f"))
		var hook_dir: float = 1.0 if x < cx else -1.0
		c.draw_rect(Rect2(Vector2(x - 3 + hook_dir * 3.0, hooks - 1), Vector2(7, 3)), Color("2f3134"))       # the J-hooks
		c.draw_rect(Rect2(Vector2(x - 3 + hook_dir * 3.0, floor_y - 24), Vector2(9, 3)), Color("2f3134"))    # the safety arms
	c.draw_rect(Rect2(Vector2(cx - 37, floor_y - 3), Vector2(74, 4)), STEEL_DARK)   # the base
	if not bar_out: barbell(c, Vector2(cx - 25, hooks), Vector2(cx + 25, hooks))

static func bench_press(c: CanvasItem, p: Vector2, size: Vector2, bar_out: bool) -> void:
	var cx: float = p.x - 12.0 + size.x * 0.5
	var top: float = p.y - 12.0
	# The bench, lengthwise.
	c.draw_rect(Rect2(Vector2(cx - 7, top + 18), Vector2(14, size.y - 22)), Color("2d2b2a"))
	c.draw_rect(Rect2(Vector2(cx - 6, top + 18), Vector2(12, size.y - 24)), Color("5a1f1c"))
	c.draw_line(Vector2(cx - 5, top + size.y - 4), Vector2(cx - 5, top + size.y + 2), STEEL_DARK, 2.0)
	c.draw_line(Vector2(cx + 5, top + size.y - 4), Vector2(cx + 5, top + size.y + 2), STEEL_DARK, 2.0)
	# Uprights at the head end, the bar across them.
	for x in [cx - 30.0, cx + 30.0]:
		c.draw_rect(Rect2(Vector2(x - 2, top - 8), Vector2(4, 28)), STEEL_DARK)
		c.draw_rect(Rect2(Vector2(x - 4 + (3.0 if x < cx else -3.0), top + 1), Vector2(8, 3)), Color("2f3134"))
	if not bar_out: barbell(c, Vector2(cx - 25, top + 2), Vector2(cx + 25, top + 2))   # where the lifter takes it from (lined up)

static func deadlift_platform(c: CanvasItem, p: Vector2, size: Vector2, bar_out: bool) -> void:
	var r := Rect2(p + Vector2(-12, -12), size)
	c.draw_rect(r, Color("1f2022"))                                       # rubber sides
	c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.3, 0), Vector2(r.size.x * 0.4, r.size.y)), Color("a8814f"))   # the wooden middle
	for x in [r.position.x + r.size.x * 0.3, r.position.x + r.size.x * 0.7]:
		c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("0e0f10"), 1.0)
	if not bar_out: barbell(c, Vector2(r.get_center().x - 25, r.get_center().y + 6), Vector2(r.get_center().x + 25, r.get_center().y + 6))   # where the lifter's hands meet it

static func pullup_bar(c: CanvasItem, p: Vector2, size: Vector2) -> void:
	var left: float = p.x - 10.0
	var right: float = p.x - 12.0 + size.x - 2.0
	# About a head and a half taller than a person (the bar at reach of raised hands).
	for x in [left, right]:
		c.draw_rect(Rect2(Vector2(x - 3, p.y - 50), Vector2(6, 56)), WOOD_DARK)
		c.draw_rect(Rect2(Vector2(x - 2, p.y - 50), Vector2(2, 56)), WOOD)
	c.draw_line(Vector2(left - 2, p.y - 46), Vector2(right + 2, p.y - 46), STEEL_DARK, 3.5, true)
	c.draw_line(Vector2(left - 2, p.y - 46), Vector2(right + 2, p.y - 46), STEEL, 1.8, true)

static func plate_tree(c: CanvasItem, p: Vector2) -> void:
	c.draw_rect(Rect2(p + Vector2(-2, -26), Vector2(4, 32)), STEEL_DARK)
	c.draw_rect(Rect2(p + Vector2(-9, 4), Vector2(18, 4)), STEEL_DARK)
	for k in range(4):
		var at: Vector2 = p + Vector2(-5 if k % 2 == 0 else 5, -20 + k * 6)
		c.draw_circle(at, 6.0 - float(k) * 0.6, PLATE)
		c.draw_arc(at, 6.0 - float(k) * 0.6, 0, TAU, 14, PLATE_RIM, 0.8, true)
