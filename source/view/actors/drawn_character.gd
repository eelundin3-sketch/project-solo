extends Node2D
## A vector cutout puppet. Direction changes the silhouette, linework and layer
## order; each piece is drawn directly in the same canvas as the world.
const Props = preload("res://view/world/prop_art.gd")
const Director = preload("res://view/actors/animation_director.gd")
const BuildMotion = preload("res://view/actors/build_motion.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const Probe = preload("res://sim/diagnostics/perf_probe.gd")
const INK := Color("30271f")
## Presentation proportions in canvas pixels; feet remain on the same world anchor.
const HIP_HEIGHT := 29.0
const CHEST_HEIGHT := 49.0
const HEAD_HEIGHT := 60.5
const PANTS := Color("b58c54")
const BOOT := Color("694722")
const HAIR := Color("543824")
## Hair colours chosen by id: chestnut, dark brown, auburn, fair, grey.
const HAIRS := [Color("6a4630"), Color("3b2c25"), Color("8a4f2c"), Color("b98d4e"), Color("8c857a")]
const EYES := [Color("4f7b74"), Color("5b6f8c"), Color("6b4d33"), Color("55684a")]
const CLOTH := [Color("d7d0ad"), Color("c8b086"), Color("a5ab8c"), Color("d5bc91")]
const VESTS := [Color("968057"), Color("887b57"), Color("a07551"), Color("8c9371")]

## How a body lies after a fall. Per style: hand, knee and foot offsets (left, right) in the
## upright figure's own pixels (x across, y down), measured from shoulder or hip, plus the head
## and chest shift and an extra twist of the whole body. Arms are flung well away from the torso.
const LYING_STYLES := {
	"back": {"hands": [Vector2(-18, -4), Vector2(12, -19)], "knees": [Vector2(-4, 11), Vector2(4, 11)], "feet": [Vector2(-9, 22), Vector2(8, 22)], "head": Vector2(0, 0), "chest": Vector2(0, 0), "twist": 0.0},
	"front": {"hands": [Vector2(-11, -20), Vector2(15, -12)], "knees": [Vector2(-2, 11), Vector2(3, 11)], "feet": [Vector2(-3, 22), Vector2(7, 21)], "head": Vector2(0, 1), "chest": Vector2(0, 0), "twist": 0.0},
	"side": {"hands": [Vector2(-6, -18), Vector2(15, 6)], "knees": [Vector2(-8, 8), Vector2(5, 11)], "feet": [Vector2(-3, 16), Vector2(-1, 21)], "head": Vector2(-2, 3), "chest": Vector2(-1, 1), "twist": -0.1},
	"sprawl": {"hands": [Vector2(-21, -10), Vector2(21, -8)], "knees": [Vector2(-9, 10), Vector2(9, 10)], "feet": [Vector2(-16, 20), Vector2(16, 19)], "head": Vector2(2, 0), "chest": Vector2(0, 0), "twist": 0.22},
	"curled": {"hands": [Vector2(-3, 8), Vector2(5, 9)], "knees": [Vector2(-8, 8), Vector2(8, 9)], "feet": [Vector2(-3, 14), Vector2(4, 15)], "head": Vector2(0, 6), "chest": Vector2(0, 3), "twist": 0.12},
	"slump": {"hands": [Vector2(-13, 12), Vector2(11, -3)], "knees": [Vector2(-3, 10), Vector2(7, 8)], "feet": [Vector2(-9, 19), Vector2(12, 15)], "head": Vector2(3, 5), "chest": Vector2(1, 2), "twist": -0.18},
	"rest": {"hands": [Vector2(-8, 12), Vector2(8, 12)], "knees": [Vector2(-3, 11), Vector2(3, 11)], "feet": [Vector2(-3, 22), Vector2(3, 22)], "head": Vector2(0, 0), "chest": Vector2(0, 0), "twist": 0.0}}

## Falling forward and getting back up, authored as 3D keyframes in the faller's own space:
## x across (right +), y forward along the fall, z height above the ground. The same keys play in
## any of the eight directions; they are projected with the fall direction at draw time.
## Joints: hip, chest, head, then elbow/hand and knee/foot for the right side (R) and the left (L).
## The lying pose is anchored so the body ends centred on its cell and gets up on the same spot.
const FALL_KEYS: Array = [
	[0.00, {"hip": Vector3(0, 0, 29), "chest": Vector3(0, 0, 49), "head": Vector3(0, 0, 60.5),
		"R_elbow": Vector3(12.4, 0, 38.5), "R_hand": Vector3(13, 0.6, 30), "L_elbow": Vector3(-12.4, 0, 38.5), "L_hand": Vector3(-13, 0.6, 30),
		"R_knee": Vector3(5.3, 0, 16), "R_foot": Vector3(5.3, 0, 3), "L_knee": Vector3(-5.3, 0, 16), "L_foot": Vector3(-5.3, 0, 3)}],
	# The blow lands: the trunk is knocked forward and the arms start to come up.
	[0.12, {"hip": Vector3(0, 2, 28.5), "chest": Vector3(0, 5.5, 48), "head": Vector3(0, 8, 59),
		"R_elbow": Vector3(12, 4, 38), "R_hand": Vector3(11, 10, 34), "L_elbow": Vector3(-12, 3, 38), "L_hand": Vector3(-11.5, 9, 33),
		"R_knee": Vector3(5.3, 3, 16), "R_foot": Vector3(5.3, 0, 3), "L_knee": Vector3(-5.3, 3, 16), "L_foot": Vector3(-5.3, 0, 3)}],
	# A stumbling step to catch the balance; the arms reach out in front.
	[0.28, {"hip": Vector3(0, 6, 27.5), "chest": Vector3(0, 14, 45.5), "head": Vector3(0, 19, 56),
		"R_elbow": Vector3(11, 15, 42), "R_hand": Vector3(9.5, 23, 45), "L_elbow": Vector3(-11, 14, 41), "L_hand": Vector3(-9.5, 22, 44),
		"R_knee": Vector3(5.3, 13, 18), "R_foot": Vector3(5.3, 11, 5.5), "L_knee": Vector3(-5.3, 4, 15.5), "L_foot": Vector3(-5.3, -1, 3.5)}],
	# The step lands but the knees give way; the arms go up over the head.
	[0.42, {"hip": Vector3(0, 7, 21.5), "chest": Vector3(0, 21, 36), "head": Vector3(0, 28.5, 44.5),
		"R_elbow": Vector3(10.5, 30, 46), "R_hand": Vector3(8.5, 39, 50), "L_elbow": Vector3(-10.5, 29, 45), "L_hand": Vector3(-8.5, 38, 49),
		"R_knee": Vector3(5.3, 16, 12.5), "R_foot": Vector3(5.3, 12, 3), "L_knee": Vector3(-5.3, 2, 9), "L_foot": Vector3(-5.5, -8, 5)}],
	# Pitching over: the legs leave the ground behind, the hands stretch for the ground.
	[0.58, {"hip": Vector3(0, 8, 14), "chest": Vector3(0, 25, 22.5), "head": Vector3(0, 35.5, 27),
		"R_elbow": Vector3(10.5, 38, 26), "R_hand": Vector3(9, 47.5, 17), "L_elbow": Vector3(-10.5, 37.5, 25), "L_hand": Vector3(-9, 47, 16),
		"R_knee": Vector3(5.5, 3, 9), "R_foot": Vector3(5.5, -8, 8), "L_knee": Vector3(-5.5, -1, 7), "L_foot": Vector3(-5.5, -13, 7)}],
	# Hands hit the ground first and the elbows give.
	[0.72, {"hip": Vector3(0, 8, 9), "chest": Vector3(0, 27, 12), "head": Vector3(0, 38, 15),
		"R_elbow": Vector3(11, 41, 9), "R_hand": Vector3(9, 50, 2.5), "L_elbow": Vector3(-11, 40.5, 9), "L_hand": Vector3(-9, 50, 2.5),
		"R_knee": Vector3(5.5, -4, 5), "R_foot": Vector3(5.5, -16, 7), "L_knee": Vector3(-5.5, -4.5, 4.5), "L_foot": Vector3(-5.5, -16.5, 6)}],
	# The chest slams down.
	[0.85, {"hip": Vector3(0, 8, 4.5), "chest": Vector3(0, 28, 4.5), "head": Vector3(0, 39.5, 5.5),
		"R_elbow": Vector3(11, 38.5, 3.5), "R_hand": Vector3(9, 50, 2.5), "L_elbow": Vector3(-11, 38.5, 3.5), "L_hand": Vector3(-9, 50, 2.5),
		"R_knee": Vector3(5.4, -5, 4), "R_foot": Vector3(5.6, -18, 3.5), "L_knee": Vector3(-5.4, -5, 4), "L_foot": Vector3(-5.6, -18, 3.5)}],
	# A small rebound before settling.
	[0.93, {"hip": Vector3(0, 8, 6.5), "chest": Vector3(0, 28, 7.5), "head": Vector3(0, 39.5, 9),
		"R_elbow": Vector3(11, 38, 4.5), "R_hand": Vector3(9, 50, 2.5), "L_elbow": Vector3(-11, 38, 4.5), "L_hand": Vector3(-9, 50, 2.5),
		"R_knee": Vector3(5.5, -5, 4), "R_foot": Vector3(5.5, -18, 7), "L_knee": Vector3(-5.5, -5, 4), "L_foot": Vector3(-5.5, -18, 6.5)}],
]
## Face down, arms stretched out over the head, legs straight behind.
const LYING_FORWARD := {"hip": Vector3(0, 8, 5), "chest": Vector3(0, 28, 6), "head": Vector3(0, 39.5, 6.5),
	"R_elbow": Vector3(11, 38, 3.5), "R_hand": Vector3(9, 50, 2.5), "L_elbow": Vector3(-11, 38, 3.5), "L_hand": Vector3(-9, 50, 2.5),
	"R_knee": Vector3(5.4, -5, 4), "R_foot": Vector3(5.6, -18, 3.5), "L_knee": Vector3(-5.4, -5, 4), "L_foot": Vector3(-5.6, -18, 3.5)}
const GETUP_KEYS: Array = [
	# Hands come in under the shoulders, elbows up.
	[0.14, {"hip": Vector3(0, 8, 5), "chest": Vector3(0, 28, 7), "head": Vector3(0, 39, 9),
		"R_elbow": Vector3(14, 26, 10), "R_hand": Vector3(12, 30, 1.5), "L_elbow": Vector3(-14, 26, 10), "L_hand": Vector3(-12, 30, 1.5),
		"R_knee": Vector3(5.4, -5, 4), "R_foot": Vector3(5.6, -18, 3.5), "L_knee": Vector3(-5.4, -5, 4), "L_foot": Vector3(-5.6, -18, 3.5)}],
	# A push-up: the arms straighten and lift the chest off the ground.
	[0.30, {"hip": Vector3(0, 8, 9), "chest": Vector3(0, 27, 19), "head": Vector3(0, 37, 24),
		"R_elbow": Vector3(12.5, 28.5, 10.5), "R_hand": Vector3(12, 30, 1.5), "L_elbow": Vector3(-12.5, 28.5, 10.5), "L_hand": Vector3(-12, 30, 1.5),
		"R_knee": Vector3(5.4, -5, 4), "R_foot": Vector3(5.6, -18, 3.5), "L_knee": Vector3(-5.4, -5, 4), "L_foot": Vector3(-5.6, -18, 3.5)}],
	# Knees are drawn up under the hips: on hands and knees.
	[0.46, {"hip": Vector3(0, 4, 17), "chest": Vector3(0, 22, 23), "head": Vector3(0, 32, 28),
		"R_elbow": Vector3(12.5, 27, 12), "R_hand": Vector3(12, 30, 1.5), "L_elbow": Vector3(-12.5, 27, 12), "L_hand": Vector3(-12, 30, 1.5),
		"R_knee": Vector3(5.5, 5, 2), "R_foot": Vector3(5.5, -9, 4), "L_knee": Vector3(-5.5, 5, 2), "L_foot": Vector3(-5.5, -9, 4)}],
	# Sitting back onto the knees and straightening the back.
	[0.60, {"hip": Vector3(0, 2, 21), "chest": Vector3(0, 9, 40), "head": Vector3(0, 12, 51),
		"R_elbow": Vector3(13, 5, 32), "R_hand": Vector3(11, 10, 24), "L_elbow": Vector3(-13, 5, 32), "L_hand": Vector3(-11, 10, 24),
		"R_knee": Vector3(5.5, 6, 2), "R_foot": Vector3(5.5, -8, 3), "L_knee": Vector3(-5.5, 6, 2), "L_foot": Vector3(-5.5, -8, 3)}],
	# One foot comes forward and is planted: kneeling on one knee, a hand on the raised knee.
	[0.74, {"hip": Vector3(0, 2, 22), "chest": Vector3(0, 6, 42), "head": Vector3(0, 8, 53),
		"R_elbow": Vector3(12, 7, 30), "R_hand": Vector3(8, 11, 18.5), "L_elbow": Vector3(-12.5, 3, 36), "L_hand": Vector3(-12, 4, 27),
		"R_knee": Vector3(5.6, 11, 15), "R_foot": Vector3(5.4, 9, 3), "L_knee": Vector3(-5.5, 4, 2), "L_foot": Vector3(-5.5, -8, 3)}],
	# Pushing up off the front knee.
	[0.88, {"hip": Vector3(0, 3, 26.5), "chest": Vector3(0, 8, 46), "head": Vector3(0, 10.5, 57),
		"R_elbow": Vector3(12, 6, 32), "R_hand": Vector3(8.5, 8, 21), "L_elbow": Vector3(-12.4, 2, 37), "L_hand": Vector3(-12.5, 2.5, 29),
		"R_knee": Vector3(5.4, 6, 16), "R_foot": Vector3(5.3, 4, 3), "L_knee": Vector3(-5.3, 3, 11), "L_foot": Vector3(-5.3, -4, 4)}],
	[1.00, {"hip": Vector3(0, 0, 29), "chest": Vector3(0, 0, 49), "head": Vector3(0, 0, 60.5),
		"R_elbow": Vector3(12.4, 0, 38.5), "R_hand": Vector3(13, 0.6, 30), "L_elbow": Vector3(-12.4, 0, 38.5), "L_hand": Vector3(-13, 0.6, 30),
		"R_knee": Vector3(5.3, 0, 16), "R_foot": Vector3(5.3, 0, 3), "L_knee": Vector3(-5.3, 0, 16), "L_foot": Vector3(-5.3, 0, 3)}],
]

## Colours for the legs and feet, and the hat item, set each draw from what the person wears.
var pants_color: Color = PANTS
var boot_color: Color = BOOT
var hat_item: String = "<legacy>"
var long_coat := false        # a duster or long coat hangs to the knees
var mask_item := ""           # a bandana over the lower face ("bandana:N")
var wears_badge := false
## Underwear only: no shirt shows bare arms (and chest, without a vest); no trousers shows bare legs and boxers.
var bare_arms := false
var bare_legs := false
var has_boots := true
var has_vest := true
var has_shirt := true

var actor_id: int
var is_player: bool
var is_raider: bool
var heading := PI / 2.0
var forward := Vector2.DOWN
var across := Vector2.RIGHT
var pose: Dictionary = {}
var frame: Dictionary = {}
var blend_from: Dictionary = {}
var blend_elapsed := 0.0
var blend_duration := 0.0

func setup(id: int, player: bool, raider: bool) -> void:
	actor_id = id
	is_player = player
	is_raider = raider

var drawn_beard := -1   # the beard stage last painted (player only)

func set_pose(value: Dictionary, delta: float = -1.0) -> void:
	if is_player:
		# Dust and blood on you show as a tint over the whole figure (look.gd).
		var look: Dictionary = value.get("look", {})
		var tint: Color = Color.WHITE.lerp(Color(0.80, 0.72, 0.62), clampf(float(look.get("dirt", 0)) / 100.0, 0.0, 1.0) * 0.7)
		tint = tint.lerp(Color(0.88, 0.55, 0.5), clampf(float(look.get("blood", 0)) / 100.0, 0.0, 1.0) * 0.6)
		if not self_modulate.is_equal_approx(tint): self_modulate = tint
		var stubble: int = (1 if int(look.get("beard", 0)) >= 20 else 0) + (1 if int(look.get("beard", 0)) >= 55 else 0)
		if stubble != drawn_beard:   # a new stage of beard: repaint even standing still
			drawn_beard = stubble
			queue_redraw()
	var next_position: Vector2 = value.get("position", Vector2.ZERO)
	var snap := delta < 0.0 or frame.is_empty() or position.distance_to(next_position) > 96.0
	var changed: bool = pose.get("action") != value.get("action") or pose.get("ready", false) != value.get("ready", false)
	if not snap and not changed and blend_from.is_empty() and pose == value: return
	if snap:
		blend_from.clear()
	elif changed:
		blend_from = frame.duplicate(true)
		blend_elapsed = 0.0
		var action: String = value.get("action", "idle")
		blend_duration = 0.18 if action in ["rest", "down", "idle"] else 0.13
		if action in ["hit", "stagger"]: blend_duration = 0.08
		if action == "shoot": blend_duration = 0.045
	else:
		blend_elapsed += maxf(0.0, delta)
	position = next_position
	# Characters face one of eight directions: up, down, left, right and the four diagonals.
	heading = snappedf(float(value.get("heading", PI / 2.0)), PI / 4.0)
	forward = Vector2.from_angle(heading)
	across = Vector2(forward.y, -forward.x)
	# Lying bodies show their face to the viewer, or the back of the head when they fell face-down.
	var lying_action: String = value.get("action", "idle")
	if lying_action == "rest" and int(value.get("rest_rot", -1)) >= 0:
		forward = Vector2.DOWN
		across = Vector2(forward.y, -forward.x)
	pose = value.duplicate()
	frame = _build_frame()
	# Face down on the ground the viewer sees the person's back, whichever way they fell.
	if frame.get("face_down", false) and forward.y > 0.05:
		forward = Vector2(forward.x, -forward.y)
		across = Vector2(forward.y, -forward.x)
	if not blend_from.is_empty():
		var weight := smoothstep(0.0, blend_duration, blend_elapsed)
		if weight >= 1.0: blend_from.clear()
		else: _blend_frame(weight)
	queue_redraw()

func _blend_frame(weight: float) -> void:
	for part in ["hip", "chest", "head", "origin"]:
		frame[part] = (blend_from[part] as Vector2).lerp(frame[part], weight)
	for part in ["left_arm", "right_arm", "left_leg", "right_leg"]:
		var start: PackedVector2Array = blend_from[part]
		var target: PackedVector2Array = frame[part]
		for joint in range(target.size()):
			target[joint] = start[joint].lerp(target[joint], weight)
		frame[part] = target
	if frame.has("pack_center") and blend_from.has("pack_center"):
		frame.pack_center = (blend_from.pack_center as Vector2).lerp(frame.pack_center, weight)
	if frame.carrying and blend_from.carrying:
		frame.cargo = (blend_from.cargo as Vector2).lerp(frame.cargo, weight)
	if frame.armed:
		if blend_from.armed:
			frame.stock = (blend_from.stock as Vector2).lerp(frame.stock, weight)
			frame.muzzle = (blend_from.muzzle as Vector2).lerp(frame.muzzle, weight)
		else:
			var grip: Vector2 = (frame.left_arm[2] + frame.right_arm[2]) * 0.5
			var barrel: Vector2 = frame.muzzle - frame.stock
			frame.stock = grip - barrel * 0.475
			frame.muzzle = frame.stock + barrel
	for part in ["left_foot_pitch", "right_foot_pitch"]:
		frame[part] = lerpf(blend_from[part], frame[part], weight)
	frame.tilt = lerp_angle(blend_from.tilt, frame.tilt, weight)
	frame.impact = lerpf(blend_from.impact, frame.impact, weight)

func _joint(width: float, reach: float, height: float) -> Vector2:
	var ground := across * width + forward * reach
	return Vector2(ground.x, ground.y * 0.48 - height)

## Cartoon outline weight: every shape is inked this much heavier than its nominal width.
const OUTLINE := 0.68

func _shape(points: PackedVector2Array, color: Color, width: float = 1.45) -> void:
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, INK, width * OUTLINE, true)

func _ellipse(center: Vector2, radius: Vector2, angle: float, count: int = 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(count):
		points.append(center + (Vector2.from_angle(TAU * i / float(count)) * radius).rotated(angle))
	return points

## Flat cel shading keeps surfaces drawn, without glossy circular highlights.
func _oval(center: Vector2, radius: Vector2, color: Color, angle: float = 0.0, edge: float = 1.35) -> void:
	var points := _ellipse(center, radius, angle, 28)
	if edge <= 0:
		draw_colored_polygon(points, color)
		return
	_shape(points, color, edge)

## Round selected contour corners with quadratic curves. This keeps a hand-drawn
## silhouette instead of rectangular limb pieces, without adding raster assets.
func _rounded(points: PackedVector2Array, rounding: float = 0.24) -> PackedVector2Array:
	var contour := PackedVector2Array()
	for i in range(points.size()):
		var corner := points[i]
		var start := corner.lerp(points[posmod(i - 1, points.size())], rounding)
		var end := corner.lerp(points[(i + 1) % points.size()], rounding)
		for step in range(5):
			var t := float(step) / 4.0
			contour.append(start.lerp(corner, t).lerp(corner.lerp(end, t), t))
	return contour

## Each bone is a convex cloth panel. Union their silhouettes for the ink outline:
## a tightly folded elbow or a foreshortened arm must not make a self-crossing polygon.
func limb_panels(joints: PackedVector2Array, widths: Vector3) -> Array[PackedVector2Array]:
	var panels: Array[PackedVector2Array] = []
	for index in range(2):
		var a := joints[index]
		var b := joints[index + 1]
		var axis := (b - a).normalized()
		if axis.is_zero_approx(): axis = Vector2.DOWN
		var normal := axis.orthogonal()
		var upper: float = widths[index]
		var lower: float = widths[index + 1]
		panels.append(_rounded(PackedVector2Array([a - axis * upper * 0.5, a + normal * upper,
			b + normal * lower, b + axis * lower * 0.5, b - normal * lower, a - normal * upper]), 0.36))
	return panels

func _limb_chain(joints: PackedVector2Array, widths: Vector3, color: Color) -> void:
	var panels := limb_panels(joints, widths)
	for index in range(2):
		draw_colored_polygon(panels[index], color)
		var axis := (joints[index + 1] - joints[index]).normalized()
		if joints[index].distance_to(joints[index + 1]) < 1.0: continue
		var normal := axis.orthogonal()
		var a := joints[index].lerp(joints[index + 1], 0.1)
		var b := joints[index].lerp(joints[index + 1], 0.9)
		var upper: float = lerpf(widths[index], widths[index + 1], 0.1)
		var lower: float = lerpf(widths[index], widths[index + 1], 0.9)
		draw_colored_polygon(PackedVector2Array([a - normal * upper * 0.88, b - normal * lower * 0.88,
			b - normal * lower * 0.43, a - normal * upper * 0.43]), color.darkened(0.18))
		draw_line(a + normal * upper * 0.58, b + normal * lower * 0.58, color.lightened(0.13), 0.55, true)
	for contour in Geometry2D.merge_polygons(panels[0], panels[1]):
		contour.append(contour[0])
		draw_polyline(contour, INK, 0.92, true)

func _segment(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var delta := b - a
	_oval(a.lerp(b, 0.5), Vector2(width, delta.length() * 0.5 + width * 0.6), color, delta.angle() - PI / 2.0)

func _build_frame() -> Dictionary:
	var action: String = pose.get("action", "idle")
	var phase: float = pose.get("phase", 0.0)
	if action in ["fall", "down", "getup", "crawl"]: return _fall_frame(action, phase)
	var gait: float = float(pose.get("gait_phase", 0.0)) * TAU
	var moving: bool = pose.get("moving", false)
	# 0 = walking pace .. 1 = full sprint. It ramps up when sprinting starts and back down after
	# shift is released, so the gait, lean and arms all ease in and out instead of switching.
	var run_amount: float = clampf(float(pose.get("run_blend", 0.0)), 0.0, 1.0)
	var run_w: float = smoothstep(0.0, 1.0, run_amount)
	var trend: float = float(pose.get("run_trend", 0.0))
	var run := run_amount > 0.5 and moving
	var work := sin(phase * TAU)
	var impact := smoothstep(0.17, 0.45, phase) * (1.0 - smoothstep(0.53, 0.93, phase))
	var build := BuildMotion.build_cycle(phase) if action == "build" else {"carry": 0.0, "raise": 0.0, "hit": 0.0, "check": 0.0}
	if action == "build": impact = build.hit
	var crouch := 0.0
	if action in ["pickup", "drop", "harvest"]:
		var reach_phase := 1.0 - phase if action == "drop" else phase
		crouch = smoothstep(0.02, 0.36, reach_phase) * (1.0 - smoothstep(0.44, 0.96, reach_phase))
	var bob := 0.0
	if moving and not pose.get("reduced_motion", false):
		# Running has two flight phases per stride: the body rises mid-flight and drops at footfall.
		bob = lerpf(pow(sin(gait), 2.0) * 1.15, pow(sin(gait - TAU * 0.09), 2.0) * 3.6, run_w)
		bob -= 2.2 * maxf(trend, 0.0) * (1.0 - run_w)  # dip into the first push-off stride
	elif not moving and run_w > 0.0:
		bob = -3.0 * run_w  # sink onto the braking leg
	var fold := 9.0 * run_w + crouch * 12.0
	fold += 3.0 * trend * run_w if moving else 0.0  # lean harder while accelerating, ease back while slowing
	if not moving: fold = -5.0 * run_w  # skid to a stop: lean back against the momentum
	# A blow snaps the trunk and head back, the knees give a little and the feet stay planted.
	var flinch := 0.0
	if action in ["stagger", "hit"]:
		flinch = smoothstep(0.0, 0.2, phase) * (1.0 - smoothstep(0.32, 1.0, phase))
		fold = -(7.5 if action == "stagger" else 5.5) * flinch
		crouch = maxf(crouch, 0.24 * flinch)
	# Treating a wound: bend down to a leg, otherwise hold the hurt part up in front of the body.
	var treat_part: String = str(pose.get("treat_part", "")) if action == "treat" else ""
	var treat_reach: float = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.92, 1.0, phase)) if action == "treat" else 0.0
	if treat_part.contains("thigh") or treat_part.contains("shin") or treat_part.contains("foot") or treat_part == "groin":
		crouch = maxf(crouch, 0.85 * treat_reach)
		fold += 7.0 * treat_reach
	elif action == "treat":
		fold += 2.0 * treat_reach
	# Into bed and out of it: first sit down on the edge (knees bent, hips low), then lie back.
	var rest_blend: float = clampf(float(pose.get("rest_blend", 1.0)), 0.0, 1.0) if action == "rest" else 0.0
	if action == "rest":
		var sitting: float = smoothstep(0.0, 0.42, rest_blend) * (1.0 - smoothstep(0.55, 0.95, rest_blend))
		crouch = maxf(crouch, 0.85 * sitting)
		fold -= 3.0 * sitting
	if action in ["chop", "mine", "punch", "shove"]: fold += impact * 5.0
	if action == "punch":
		var punch_style: String = str(pose.get("punch_style", "straight"))
		if punch_style == "haymaker": fold += 8.0 * smoothstep(0.5, 0.68, phase) * (1.0 - smoothstep(0.8, 1.0, phase)) - 5.0 * smoothstep(0.0, 0.5, phase) * (1.0 - smoothstep(0.5, 0.68, phase))
		elif punch_style == "uppercut": crouch = maxf(crouch, 0.45 * smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.5, 0.9, phase)))
		elif punch_style == "hook": fold += 2.5 * impact
	if action == "kick": fold -= impact * 4.0   # lean back onto the standing leg
	if action == "surrender": fold -= 1.5        # hands up, leaning away from the gun
	if action == "cuffed": fold += 2.5           # head bowed
	if action == "cuff": fold += 4.0             # leaning in to fit the cuffs
	if action == "search": fold += 3.5           # bending to pat the prisoner down
	if action == "build": fold += build.hit * 5.0 + build.raise * 1.5 - build.check * 1.5  # lean into each blow
	if action == "shoot": fold -= (4.0 + 3.0 * float(pose.get("bloom", 0)) / 900.0) * smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.1, 0.55, phase))
	if action == "build" and pose.get("build_kind", "") == "floor":
		crouch = 0.55 + impact * 0.32
		fold += 7.0
	# Stamina: breathing hard (winded) after a long run, and a labouring gait while running on empty.
	var breath: float = float(pose.get("breath", 0.0))
	var tired: float = float(pose.get("fatigue", 0.0))
	var heave: float = sin(float(pose.get("age", 0.0)) * 8.5)
	var winded_idle: bool = breath > 0.0 and not moving and action in ["idle", "ready", "combat_idle"]
	if winded_idle:
		fold += 12.0 * breath                  # bent over, hands on knees
		crouch = maxf(crouch, 0.55 * breath)
		bob += heave * 0.9 * breath
	elif breath > 0.0 and moving and run_w < 0.5:
		fold += 4.0 * breath                   # a slouching, weary walk
	if tired > 0.0 and moving: fold += 4.5 * tired
	if flinch > 0.0: bob -= 0.8 * flinch
	# Standing still is never frozen: slow breathing lifts the chest and shoulders, and the weight
	# drifts from one foot to the other. Each person breathes on their own rhythm.
	var idle_breath := 0.0
	var idle_sway := 0.0
	if not moving and action in ["idle", "ready", "combat_idle", "gun_carry", "aim"] and breath <= 0.0:
		var clock_s: float = float(pose.get("age", 0.0)) + float(posmod(actor_id, 17)) * 0.73
		idle_breath = sin(clock_s * TAU / 3.4)
		idle_sway = sin(clock_s * TAU / 7.3) * (1.0 - clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0))
	# Inventory: kneel on one knee, swing the backpack round onto the ground, open it and dig through
	# it; packing up reverses that. `pack_move` 0 = on the back .. 1 = on the ground in front.
	var kneel := 0.0
	var pack_move := 0.0
	var pack_open := 0.0
	var dig := 0.0
	if action == "rummage":
		var seconds: float = float(pose.get("rummage_t", 0.0))
		kneel = smoothstep(0.0, 0.55, seconds)
		pack_move = smoothstep(0.35, 1.0, seconds)
		pack_open = smoothstep(0.95, 1.25, seconds)
		dig = sin(maxf(0.0, seconds - 1.15) * TAU * 0.85)
	elif action == "pack_up":
		var p: float = clampf(float(pose.get("pack_up_phase", 1.0)), 0.0, 1.0)
		pack_open = 1.0 - smoothstep(0.0, 0.15, p)
		pack_move = 1.0 - smoothstep(0.05, 0.6, p)
		kneel = 1.0 - smoothstep(0.5, 1.0, p)
	if kneel > 0.0: fold += 7.0 * kneel
	# Crouching / sneaking: hips sink, the trunk leans in, the head stays up to look ahead.
	var sneak: float = clampf(float(pose.get("sneak", 0.0)), 0.0, 1.15)
	if action == "rest":
		# Sitting on the edge of the bed uses the same bent-knee lowering as a crouch.
		var settle: float = clampf(float(pose.get("rest_blend", 1.0)), 0.0, 1.0)
		sneak = maxf(sneak, 1.1 * smoothstep(0.0, 0.4, settle) * (1.0 - smoothstep(0.5, 0.9, settle)))
	if sneak > 0.0:
		fold += 8.5 * sneak
		if moving: bob *= 0.55
	var hip := _joint(0.7 * idle_sway, -1.5 * flinch, HIP_HEIGHT + bob - crouch * 5 - sneak * 10.0 - kneel * 12.5)
	var chest := _joint(0.35 * idle_sway, fold, CHEST_HEIGHT + bob - crouch * 14 - sneak * 14.5 - kneel * 13.0 + 0.75 * idle_breath + (heave * 2.4 * breath if winded_idle else 0.0))
	var head := _joint(1.2 * flinch + 0.25 * idle_sway, fold * 1.22 - 2.6 * flinch - 3.5 * sneak + 1.5 * kneel, HEAD_HEIGHT + bob - crouch * 18 - sneak * 15.5 - kneel * 14.5 + 0.5 * idle_breath + (heave * 1.0 * breath if winded_idle else 0.0) - tired * 2.0 * (1.0 if moving else 0.0))
	var item: String = pose.get("cargo_item", "")
	var quantity: int = pose.get("cargo_quantity", 0)
	if quantity == 0 and action == "pickup":
		item = pose.get("expected_item", "")
		quantity = pose.get("expected_quantity", 0)
	if quantity == 0 and action == "drop":
		item = pose.get("last_item", "")
		quantity = pose.get("last_quantity", 0)
	var carrying := quantity > 0 and action not in ["build", "hit", "down", "rest", "punch", "shove", "kick", "stagger", "surrender", "cuffed", "cuff", "search"]
	var lift := 1.0
	if action == "pickup": lift = smoothstep(0.33, 0.91, phase)
	elif action == "drop": lift = smoothstep(0.33, 0.91, 1.0 - phase)
	var cargo_center := _joint(0, 9 + fold * 0.5, 5 + 24 * lift)
	var show_cargo := carrying
	if action == "pickup" and pose.get("cargo_quantity", 0) == 0: show_cargo = carrying and phase >= 0.33
	if action == "drop" and pose.get("cargo_quantity", 0) == 0: show_cargo = carrying and phase < 0.67
	var armed := action in ["gun_carry", "aim", "shoot", "reload"]
	var recoil := (7.0 + 4.0 * float(pose.get("bloom", 0)) / 900.0) * smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.1, 0.55, phase)) if action == "shoot" else 0.0
	# The barrel follows the cursor between the drawn body's eight directions.
	var sight := Vector2.from_angle(float(pose.get("heading", heading))) if pose.get("aiming", false) else forward
	var projected_sight := Vector2(sight.x, sight.y * 0.48)
	var stock := head + _joint(0, 3, -8) - projected_sight * recoil
	var muzzle := stock + projected_sight * (56.0 * GUN_LENGTH_SCALE)
	var pump := 0.0
	if action == "gun_carry":
		# Low ready: the stock tucked against the right side of the chest, the barrel angled down
		# across the front of the body towards the left knee, both hands on the gun.
		stock = chest + _joint(-8.5, 7.0, -9.0)
		muzzle = stock + _joint(30, 13, -25) * (56.0 * GUN_LENGTH_SCALE / Vector3(30, 13, 25).length())
	elif action == "reload":
		# Hold the stock near the ribs and the muzzle down across the body.
		stock = chest + _joint(12, 5, -8)
		muzzle = stock + _joint(-34, 16, -21) * (56.0 * GUN_LENGTH_SCALE / Vector3(34, 16, 21).length())
		if action == "reload": pump = absf(sin(phase * TAU))
	elif action == "shoot":
		muzzle.y -= recoil * (9.0 / 7.0)
		pump = smoothstep(0.55, 0.75, phase) * (1.0 - smoothstep(0.8, 1.0, phase))
	var arms: Dictionary = {}
	for side in [-1, 1]:
		var limb_cycle := gait + (PI if side > 0 else 0.0)
		var bounce := -cos(limb_cycle) if moving else 0.0
		var shoulder := chest + _joint(side * 9.4, 0, 0)
		var elbow := shoulder + _joint(side * 2.8, bounce * 4.5, -9)
		var hand := elbow + _joint(side * 0.8, bounce * 5.0, -9)
		if not moving:
			elbow = shoulder + _joint(side * 3.0, 0.0, -10.5)
			hand = hip + _joint(side * 13.0, 0.6, 1.0)
		if sneak > 0.001 and action in ["idle", "walk", "ready", "combat_idle"] and not carrying and not armed:
			# Guarded, quiet arms: elbows bent, hands low and forward, swinging only a little.
			var sneak_elbow := shoulder + _joint(side * 5.0, 4.0 + bounce * 2.0, -8.0)
			var sneak_hand := sneak_elbow + _joint(side * 1.0, 6.5 + bounce * 2.5, -4.5)
			var weight: float = minf(1.0, sneak)
			elbow = elbow.lerp(sneak_elbow, weight)
			hand = hand.lerp(sneak_hand, weight)
			if winded_idle:
				var brace: float = minf(1.0, breath * 1.6)
				hand = hand.lerp(hip + _joint(side * 9.0, 3.0, -8.5), brace)
				elbow = elbow.lerp(shoulder.lerp(hand, 0.5) + _joint(side * 4.5, 1.5, 0.0), brace)
		if carrying and not armed:
			var grip_weight := 1.0
			if action == "pickup": grip_weight = smoothstep(0.0, 0.33, phase)
			elif action == "drop": grip_weight = 1.0 - smoothstep(0.67, 1.0, phase)
			elbow = elbow.lerp(shoulder + _joint(side * 3, 4, -11), grip_weight)
			hand = hand.lerp(cargo_center + _joint(side * 9, 0, -2), grip_weight)
		elif armed:
			hand = stock.lerp(muzzle, 0.31 if side > 0 else 0.64 - 0.17 * pump)
			if action == "gun_carry": hand = stock.lerp(muzzle, 0.13 if side < 0 else 0.58)
			if action == "reload" and side > 0: hand = stock.lerp(muzzle, 0.42) + Vector2(0, 5.0 + 4.0 * sin(phase * TAU * 2.0))
			elbow = shoulder.lerp(hand, 0.45) + _joint(side * 2, -1, -7)
		elif action in ["hit", "stagger"]:
			# Flinch: both arms fling outward and up as the body recoils.
			var flare := flinch
			hand = shoulder + _joint(side * (5.0 + 8.0 * flare), 1.0 - 4.0 * flare, -8.0 + 13.0 * flare)
			elbow = shoulder.lerp(hand, 0.5) + _joint(side * 2.5, 0, -4)
		elif action == "surrender":
			# Hands up, palms out, trembling a little.
			var shake := sin(float(pose.get("age", 0.0)) * 9.0) * 0.45
			elbow = shoulder + _joint(side * 8.5, 0.5, 7.5)
			hand = shoulder + _joint(side * 6.0, 1.0, 17.5 + shake)
		elif action == "cuffed":
			# Wrists cuffed together behind the back.
			elbow = shoulder + _joint(side * 5.5, -3.5, -8.5)
			hand = hip + _joint(side * 1.6, -4.5, 3.5)
		elif action == "cuff":
			# Both hands low and forward, working the cuffs onto the prisoner's wrists.
			var fiddle := sin(phase * TAU * 4.0) * 1.2
			elbow = shoulder + _joint(side * 6.0, 6.0, -7.0)
			hand = chest + _joint(side * 2.5, 11.5, -13.0 + fiddle)
		elif action == "search":
			# Patting the prisoner down: both hands low in front, sweeping across the body.
			var sweep := sin(phase * TAU * 3.0 + (0.0 if side > 0 else PI))
			elbow = shoulder + _joint(side * 6.5, 5.5, -7.0)
			hand = chest + _joint(side * (2.0 + 3.5 * sweep), 11.0, -11.0 + 2.5 * sweep)
		elif action == "escort" and side > 0:
			# A firm grip on the prisoner's arm, a step behind.
			elbow = shoulder + _joint(side * 8.0, -3.0, -8.0)
			hand = shoulder + _joint(side * 9.5, -7.5, -14.0)
		elif action == "kick":
			# Arms out for balance while the leg swings.
			hand = shoulder + _joint(side * (9.0 + 5.0 * impact), 1.0, -7.0 + 4.0 * impact)
			elbow = shoulder.lerp(hand, 0.5) + _joint(side * 2.0, 0, -3)
		elif action == "punch" and str(pose.get("punch_style", "straight")) != "straight":
			# The chain: cross (rear hand), hook (a wide side swing), uppercut (from low), haymaker (big overhand).
			var style_name: String = str(pose.punch_style)
			var striker: int = -1 if style_name == "cross" else 1
			var wind := smoothstep(0.0, 0.5, phase)
			var swing := smoothstep(0.5, 0.68, phase) * (1.0 - smoothstep(0.8, 1.0, phase))
			if side != striker:
				hand = chest + _joint(side * 5, 8, 3)                       # the other hand guards the chin
				elbow = shoulder.lerp(hand, 0.5) + _joint(side * 3, 0, -8)
			else:
				match style_name:
					"cross":
						hand = chest + _joint(side * 4, 9 + impact * 25, 1.5 - impact * 3)
						elbow = shoulder.lerp(hand, 0.5) + _joint(side * 2.5, 0, -7)
					"hook":
						var arc: float = impact
						hand = chest + _joint(side * (7.0 + 13.0 * sin(arc * PI * 0.9)), 5.0 + 9.0 * arc, 2.0)
						elbow = shoulder + _joint(side * (9.0 + 5.0 * arc), 2.0 + 3.0 * arc, -2.0)
					"uppercut":
						hand = chest + _joint(side * 3.0, 6.0 + 10.0 * impact, -11.0 + 21.0 * impact)
						elbow = shoulder + _joint(side * 5.0, 5.0 + 4.0 * impact, -9.0 + 5.0 * impact)
					_:
						# Haymaker: the fist goes back and up, then swings over and down through the target.
						var back := _joint(side * 7.0, -5.0, 9.0)
						var through := _joint(side * 4.0, 15.0, -3.0)
						hand = chest + back.lerp(through, swing) * (1.0 if phase > 0.45 else wind) + _joint(0, 0, 4.0 * (1.0 - swing) * wind)
						elbow = shoulder + _joint(side * 8.0, -3.0 + 8.0 * swing, 3.0 - 7.0 * swing)
		elif action in ["punch", "shove", "melee", "ready", "combat_idle"] or pose.get("ready", false):
			var extension := impact if side > 0 or action == "shove" else 0.0
			hand = chest + _joint(side * 5, 9 + extension * 23, 1 - extension * 3)
			elbow = shoulder.lerp(hand, 0.50) + _joint(side * 3, 0, -8)
		elif action in ["chop", "mine", "build", "saw", "eat", "harvest"]:
			hand = _work_hand(side, action, chest, work, impact)
			elbow = shoulder.lerp(hand, 0.45) + _joint(side * 4, -2, -7)
		elif run_amount > 0.001 and action in ["walk", "run", "idle"]:
			# Running arms: opposite to the legs (the arm swings forward as the other leg drives
			# forward), elbows bent near 90 degrees, hands travelling from hip to chest.
			var opposite := fposmod(gait / TAU + (0.5 if -side > 0 else 0.0), 1.0)
			var swing := cos(TAU * opposite)
			var upper := 0.95 * swing * (1.0 - 0.35 * tired)
			var forearm := upper + 1.55 + 0.35 * swing
			var run_elbow := shoulder + _joint(side * 2.6, sin(upper) * 9.5, -cos(upper) * 9.5)
			var run_hand := run_elbow + _joint(side * -1.2, sin(forearm) * 9.0, -cos(forearm) * 9.0)
			if not moving:
				# Braking: arms spread out and down for balance.
				run_elbow = shoulder + _joint(side * 7.0, 2.0, -7.5)
				run_hand = shoulder + _joint(side * 11.5, 5.0, -4.5)
			elbow = elbow.lerp(run_elbow, run_w)
			hand = hand.lerp(run_hand, run_w)
		arms[side] = PackedVector2Array([shoulder, elbow, hand])
	var treat_center := Vector2.ZERO
	var treat_hand := Vector2.ZERO
	if action == "treat":
		var treated := _treat_arms(arms, chest, hip, head, phase, treat_part, str(pose.get("treat_kind", "bandage")), treat_reach, crouch)
		arms = treated.arms
		treat_center = treated.center
		treat_hand = treated.hand
	var tilt := 0.0
	var origin := Vector2.ZERO
	# 0 standing .. 1 lying, for the fall, the time on the ground and the climb back up.
	var lying := 0.0
	if action == "rest": lying = smoothstep(0.4, 1.0, rest_blend)   # lying in bed; falls are built by _fall_frame
	var lie_scale := 1.0
	var leg_run: float = run_amount * (1.0 - 0.3 * tired)
	var left_leg := leg_joints(-1, hip, gait, moving, leg_run, HIP_HEIGHT + bob - crouch * 5.0 - sneak * 10.0 - kneel * 12.5)
	var right_leg := leg_joints(1, hip, gait, moving, leg_run, HIP_HEIGHT + bob - crouch * 5.0 - sneak * 10.0 - kneel * 12.5)
	if action == "kick":
		# The right leg swings forward and down through the downed person; the left takes the weight.
		var kick_foot := hip + _joint(5.3, 4.0 + 13.0 * impact, 5.0 + 4.0 * impact * (1.0 - impact))
		var kick_knee := hip.lerp(kick_foot, 0.5) + _joint(0, 3.0 * impact, -2.0)
		right_leg = PackedVector2Array([right_leg[0], right_leg[1].lerp(kick_knee, impact), right_leg[2].lerp(kick_foot, impact)])
	var pack_center := Vector2.ZERO
	if kneel > 0.0:
		# Down on the right knee, left foot planted ahead.
		var travel := Vector2(forward.x, forward.y * 0.48)
		var planted := left_leg[2].lerp(_joint(-5.3, 8.0, 3.0), kneel)
		var reach_now := left_leg[0].distance_to(planted)
		var bend := sqrt(maxf(0.0, 13.4 * 13.4 - reach_now * reach_now * 0.25))
		left_leg = PackedVector2Array([left_leg[0], left_leg[1].lerp(left_leg[0].lerp(planted, 0.5) + travel * bend, kneel), planted])
		right_leg = PackedVector2Array([right_leg[0], right_leg[1].lerp(_joint(5.3, 2.0, 2.5), kneel), right_leg[2].lerp(_joint(5.3, -11.0, 3.0), kneel)])
	if _wears_pack():
		var worn := chest.lerp(hip, 0.42) + _joint(0, -6.5, 0)
		var ground := _joint(0, 15.0, 6.0)
		pack_center = worn.bezier_interpolate(worn + _joint(13, 3, 3), ground + _joint(11, 2, 9), ground, pack_move)
		if action in ["rummage", "pack_up"]:
			for side in [-1, 1]:
				var joints: PackedVector2Array = arms[side]
				var target_hand: Vector2
				if pack_move > 0.03 and pack_move < 0.97:
					target_hand = pack_center + _joint(side * 5.5, 0.0, 2.0)     # carrying the pack round
				elif pack_open > 0.4:
					target_hand = pack_center + (_joint(1.5 + 1.5 * dig, -1.0, 3.0 + 3.5 * dig) if side > 0 else _joint(-6.0, -1.0, 6.5))
				elif kneel > 0.05:
					target_hand = left_leg[1] + _joint(side * 2.5, 1.0, 2.0)       # a hand on the raised knee
				else:
					continue
				var weight: float = clampf(kneel * 1.6, 0.0, 1.0)
				var hand := joints[2].lerp(target_hand, weight)
				var elbow := joints[1].lerp(joints[0].lerp(hand, 0.5) + _joint(side * 3.5, 1.0, -2.0), weight)
				arms[side] = PackedVector2Array([joints[0], elbow, hand])
	if lying > 0.001:
		var style: String = "rest"
		var data: Dictionary = LYING_STYLES.get(style, LYING_STYLES.back)
		var lie_side: float = float(pose.get("fall_side", 1))
		var rest_rot: int = int(pose.get("rest_rot", -1)) if action == "rest" else -1
		if rest_rot == 1: lie_side = 1.0
		elif rest_rot == 3: lie_side = -1.0
		# Arms are thrown out past their final spot while falling and brace against the ground getting up.
		var flail := 0.0
		for arm_side in [-1, 1]:
			var index: int = 0 if arm_side < 0 else 1
			var joints: PackedVector2Array = arms[arm_side]
			var target_hand: Vector2 = joints[0] + (data.hands[index] as Vector2) * (1.0 + 0.3 * flail)
			var target_elbow: Vector2 = joints[0].lerp(target_hand, 0.5) + Vector2(arm_side * 2.5, 2.5)
			joints[1] = joints[1].lerp(target_elbow, lying)
			joints[2] = joints[2].lerp(target_hand, lying)
			arms[arm_side] = joints
		for leg_side in [-1, 1]:
			var index: int = 0 if leg_side < 0 else 1
			var leg: PackedVector2Array = left_leg if leg_side < 0 else right_leg
			leg[1] = leg[1].lerp(leg[0] + (data.knees[index] as Vector2), lying)
			leg[2] = leg[2].lerp(leg[0] + (data.feet[index] as Vector2), lying)
			if leg_side < 0: left_leg = leg
			else: right_leg = leg
		head += (data.head as Vector2) * lying
		chest += (data.chest as Vector2) * lying
		tilt = lie_side * lying * (PI / 2.0 + float(data.twist))
		origin = Vector2(-30.0 * lie_side, 1.0) * lying
		if rest_rot == 0 or rest_rot == 2:
			# A bed running up and down the screen: lie along it, head up or head down, foreshortened.
			tilt = 0.0 if rest_rot == 0 else PI
			origin = Vector2(0.0, 24.0 if rest_rot == 0 else -24.0) * lying
			lie_scale = lerpf(1.0, 0.74, lying)
	elif action in ["stagger", "hit"]:
		# The rear foot slides back a little to catch the weight; the body never pivots as a whole.
		var slide: float = (6.0 if action == "stagger" else 3.0) * flinch
		right_leg[2] += _joint(0, -slide, 0)
		right_leg[1] += _joint(0, -slide * 0.55, 0)
	# Leaning out past a corner: the body shifts towards the corner and the head goes furthest.
	var lean_v: Vector2 = pose.get("peek_lean", Vector2.ZERO)
	if lean_v.length() > 0.01:
		var lean_screen := Vector2(lean_v.x, lean_v.y * 0.48)
		chest += lean_screen * 5.0
		head += lean_screen * 10.0
		for side in [-1, 1]:
			arms[side] = PackedVector2Array([arms[side][0] + lean_screen * 5.0, arms[side][1] + lean_screen * 7.0, arms[side][2] + lean_screen * 9.0])
	# A limp: the bad leg drags, the body bobs down on it. An arm that does not work just hangs.
	if bool(pose.get("limp", false)):
		var bad_side: int = int(pose.get("limp_side", 1))
		var bad_leg: PackedVector2Array = left_leg if bad_side < 0 else right_leg
		bad_leg[2] = bad_leg[0].lerp(bad_leg[2], 0.88)
		bad_leg[1] = bad_leg[0].lerp(bad_leg[1], 0.9)
		var dip: float = 1.6 * absf(sin(gait)) if moving else 0.0
		hip += _joint(0, 0, -dip)
		chest += _joint(0, 0, -dip) + _joint(float(bad_side) * 1.0, 0, 0)
		head += _joint(0, 0, -dip)
	# Sitting: in a chair (hips at seat height, thighs forward, shins down, hands in the lap) or on
	# the ground (knees up). Tied: on the ground, arms bound behind the back.
	if action in ["sit", "tied", "cook"]:
		var ground: bool = action in ["tied", "cook"] or bool(pose.get("sit_ground", false))
		var seat: float = 4.0 if ground else 13.0
		var breathe: float = sin((float(pose.get("age", 0.0)) + float(posmod(actor_id, 17)) * 0.7) * TAU / 3.6) * 0.6
		hip = _joint(0, -1.0, seat)
		chest = _joint(0, 1.5 + (2.0 if action == "tied" else 0.0), seat + (CHEST_HEIGHT - HIP_HEIGHT) - 1.0 + breathe)
		head = _joint(0, 3.0 + (2.5 if action == "tied" else 0.0), seat + (HEAD_HEIGHT - HIP_HEIGHT) - 2.0 + breathe * 0.6)
		for side in [-1, 1]:
			var knee_at: Vector2 = _joint(side * 5.6, 10.0, seat + (8.5 if ground else 0.5))
			var foot_at: Vector2 = _joint(side * 5.0, 16.0 if ground else 11.5, 1.5)
			var leg := PackedVector2Array([hip + _joint(side * 5.3, 0, 0), knee_at, foot_at])
			if side < 0: left_leg = leg
			else: right_leg = leg
			var shoulder: Vector2 = chest + _joint(side * 9.4, 0, 0)
			var elbow: Vector2
			var hand: Vector2
			if action == "tied":
				elbow = shoulder + _joint(side * 5.0, -3.5, -8.0)
				hand = hip + _joint(side * 1.4, -5.0, 5.0)
			elif action == "cook" and side > 0:
				# Stirring the pot: the right hand reaches forward and circles.
				var stir: float = float(pose.get("age", 0.0)) * TAU * 0.7
				hand = chest + _joint(4.0 + cos(stir) * 2.5, 15.0 + sin(stir) * 2.5, -16.0)
				elbow = shoulder.lerp(hand, 0.5) + _joint(side * 3.0, 0, -4.0)
			else:
				elbow = shoulder + _joint(side * 4.5, 3.5, -8.5)
				hand = knee_at.lerp(hip, 0.45) + _joint(side * -1.0, 0, 3.0)
			arms[side] = PackedVector2Array([shoulder, elbow, hand])
		tilt = 0.0
		origin = Vector2.ZERO
	# Holding a prisoner down: kneeling over them, both hands pressing at their back and wrists.
	if action == "pin":
		var press: float = sin(phase * TAU * 3.0) * 0.8
		hip = _joint(0, 1.5, HIP_HEIGHT - 13.0)
		chest = _joint(0, 9.0, CHEST_HEIGHT - 18.0)
		head = _joint(0, 12.5, HEAD_HEIGHT - 19.0)
		left_leg = PackedVector2Array([hip + _joint(-5.3, 0, 0), _joint(-5.6, 10.0, 6.0), _joint(-5.0, 9.0, 1.0)])   # left foot planted
		right_leg = PackedVector2Array([hip + _joint(5.3, 0, 0), _joint(5.4, 3.0, 2.0), _joint(5.3, -9.0, 2.0)])     # right knee on the ground
		for side in [-1, 1]:
			var shoulder: Vector2 = chest + _joint(side * 9.0, 0, 0)
			var hand: Vector2 = _joint(side * 3.0, 17.0 + press, 4.5)
			arms[side] = PackedVector2Array([shoulder, shoulder.lerp(hand, 0.5) + _joint(side * 2.5, 0, 2.0), hand])
	# Hauling a prisoner up: legs braced, leaning back, hands gripping their arm and pulling.
	if action == "lift":
		var heave_up: float = smoothstep(0.0, 0.85, phase)
		var lean: float = -4.0 * heave_up + 6.0 * (1.0 - heave_up)
		chest += _joint(0, lean, -6.0 * (1.0 - heave_up))
		head += _joint(0, lean * 1.2, -7.0 * (1.0 - heave_up))
		for side in [-1, 1]:
			var shoulder: Vector2 = chest + _joint(side * 9.0, 0, 0)
			var grip: Vector2 = _joint(side * 2.5, 13.0, lerpf(9.0, 30.0, heave_up))
			arms[side] = PackedVector2Array([shoulder, shoulder.lerp(grip, 0.5) + _joint(side * 3.0, -1.0, -2.0), grip])
	for dead_side in pose.get("dead_arms", []):
		var limp_arm: PackedVector2Array = arms[int(dead_side)]
		var dangling_elbow: Vector2 = limp_arm[0] + _joint(float(dead_side) * 2.6, 0.5, -8.5)
		arms[int(dead_side)] = PackedVector2Array([limp_arm[0], dangling_elbow, dangling_elbow + _joint(float(dead_side) * 1.0, 0.8, -8.0)])
	return {
		"hip": hip, "chest": chest, "head": head, "cargo": cargo_center, "stock": stock, "muzzle": muzzle,
		"left_arm": arms[-1], "right_arm": arms[1],
		"left_leg": left_leg, "right_leg": right_leg, "lie_scale": lie_scale,
		"left_foot_pitch": walking_foot_pitch(-1, gait) * (1.0 - run_w) if moving else 0.0,
		"right_foot_pitch": walking_foot_pitch(1, gait) * (1.0 - run_w) if moving else 0.0,
		"origin": origin, "tilt": tilt, "item": item, "quantity": quantity, "carrying": carrying,
		"rest_lying": lying if action == "rest" else 0.0,
		"pack_center": pack_center, "pack_move": pack_move, "pack_open": pack_open, "backpack": _wears_pack(),
		"treat_center": treat_center, "treat_hand": treat_hand, "treat_reach": treat_reach,
		"armed": armed, "impact": impact, "show_cargo": show_cargo and not armed, "build_raise": build.raise, "build_carry": build.carry, "build_check": build.check, "pump": pump, "slung": (bool(pose.get("slung", false)) or bool(pose.get("gun_equipped", false))) and not armed,
	}

## The keyframed pose at `phase` of a key list: centripetal-free Catmull-Rom in time, so the body
## moves through every key without stopping at it.
func _sample_keys(keys: Array, phase: float) -> Dictionary:
	var count: int = keys.size()
	if phase <= float(keys[0][0]): return keys[0][1]
	if phase >= float(keys[count - 1][0]): return keys[count - 1][1]
	var index := 0
	while index < count - 2 and phase > float(keys[index + 1][0]): index += 1
	var a: Array = keys[index]
	var b: Array = keys[index + 1]
	var before: Array = keys[maxi(0, index - 1)]
	var after: Array = keys[mini(count - 1, index + 2)]
	var span: float = float(b[0]) - float(a[0])
	var weight: float = clampf((phase - float(a[0])) / span, 0.0, 1.0)
	var pre_t: float = minf(-0.001, float(before[0]) - float(a[0])) if index > 0 else -span
	var post_t: float = maxf(span + 0.001, float(after[0]) - float(a[0])) if index + 2 < count else span * 2.0
	var result: Dictionary = {}
	for joint in a[1]:
		var p0: Vector3 = before[1][joint] if index > 0 else a[1][joint]
		var p3: Vector3 = after[1][joint] if index + 2 < count else b[1][joint]
		result[joint] = (a[1][joint] as Vector3).cubic_interpolate_in_time(b[1][joint], p0, p3, weight, span, pre_t, post_t)
	return result

## Falling forward, lying face down and getting back up, in any of the eight directions.
## Joints are placed in 3D and projected along the fall direction; the drawn shapes (head, coat,
## boots) turn with the trunk through `tilt` so they stay solid instead of being squashed flat.
func _fall_frame(action: String, phase: float) -> Dictionary:
	var joints: Dictionary
	if action == "fall": joints = _sample_keys(FALL_KEYS + [[1.0, LYING_FORWARD]], phase)
	elif action == "getup": joints = _sample_keys([[0.0, LYING_FORWARD]] + GETUP_KEYS, phase)
	elif action == "crawl":
		# Propped on the forearms, the hands reaching one after the other, the legs dragged behind.
		joints = LYING_FORWARD.duplicate()
		var g: float = float(pose.get("gait_phase", 0.0)) * TAU
		var moving_now: bool = bool(pose.get("moving", false))
		var pull: float = sin(g) if moving_now else sin(float(pose.get("age", 0.0)) * 1.6) * 0.25
		joints.hip = Vector3(0, 8, 6)
		joints.chest = Vector3(0, 27, 13.5)
		joints.head = Vector3(0, 37.5, 21)
		joints.R_elbow = Vector3(10, 33, 6 + 2.0 * maxf(0.0, pull))
		joints.L_elbow = Vector3(-10, 33, 6 + 2.0 * maxf(0.0, -pull))
		joints.R_hand = Vector3(8.5, 44 + 7.0 * pull, 2.5 + 4.0 * maxf(0.0, pull))
		joints.L_hand = Vector3(-8.5, 44 - 7.0 * pull, 2.5 + 4.0 * maxf(0.0, -pull))
		joints.R_knee = Vector3(5.4, -4 + 2.0 * pull, 4.5)
		joints.L_knee = Vector3(-5.4, -4 - 2.0 * pull, 4.5)
		joints.R_foot = Vector3(5.6, -17 - 2.5 * pull, 3.5)
		joints.L_foot = Vector3(-5.6, -17 + 2.5 * pull, 3.5)
	else:
		joints = LYING_FORWARD.duplicate()
		# Slow breathing while lying there.
		var breath := sin(float(pose.get("age", 0.0)) * 2.4) * 0.45
		joints.chest = (joints.chest as Vector3) + Vector3(0, 0, breath)
		joints.head = (joints.head as Vector3) + Vector3(0, 0, breath * 0.6)
	# Nobody falls dead straight toward or away from the viewer: lean the line a little to one side,
	# which also keeps the trunk readable while it points at the camera.
	var lean: float = 0.55 * (1.0 - absf(forward.x)) * float(pose.get("fall_side", 1))
	var fall_forward := (forward + across * lean).normalized()
	var fall_across := Vector2(fall_forward.y, -fall_forward.x)
	var project := func(p: Vector3) -> Vector2:
		var ground := fall_across * p.x + fall_forward * p.y
		return Vector2(ground.x, ground.y * 0.48 - p.z)
	var hip_s: Vector2 = project.call(joints.hip)
	var chest_s: Vector2 = project.call(joints.chest)
	var axis := chest_s - hip_s
	var tilt := Vector2.UP.angle_to(axis) if axis.length() > 0.5 else 0.0
	var to_local := func(p: Vector2) -> Vector2: return (p - hip_s).rotated(-tilt)
	var trunk: Vector3 = (joints.chest as Vector3) - (joints.hip as Vector3)
	var pitch := atan2(trunk.y, trunk.z)
	# Gear stays on through the whole fall: the pack sits on the back, which faces up once face down.
	var back3 := Vector3(0, -trunk.z, trunk.y).normalized() if trunk.length() > 0.01 else Vector3(0, -1, 0)
	var pack3: Vector3 = (joints.hip as Vector3).lerp(joints.chest, 0.58) + back3 * 6.5
	var arms := {}
	var legs := {}
	for side in [-1, 1]:
		var tag := "R_" if side > 0 else "L_"
		var shoulder: Vector3 = (joints.chest as Vector3) + Vector3(side * 9.4, 0, 0)
		var top: Vector3 = (joints.hip as Vector3) + Vector3(side * 5.3, 0, 0)
		arms[side] = PackedVector2Array([to_local.call(project.call(shoulder)), to_local.call(project.call(joints[tag + "elbow"])), to_local.call(project.call(joints[tag + "hand"]))])
		legs[side] = PackedVector2Array([to_local.call(project.call(top)), to_local.call(project.call(joints[tag + "knee"])), to_local.call(project.call(joints[tag + "foot"]))])
	return {
		"hip": Vector2.ZERO, "chest": to_local.call(chest_s), "head": to_local.call(project.call(joints.head)),
		"cargo": Vector2.ZERO, "stock": Vector2.ZERO, "muzzle": Vector2.ZERO,
		"left_arm": arms[-1], "right_arm": arms[1], "left_leg": legs[-1], "right_leg": legs[1], "lie_scale": 1.0,
		"left_foot_pitch": 0.0, "right_foot_pitch": 0.0, "origin": hip_s, "tilt": tilt,
		"item": "", "quantity": 0, "carrying": false, "armed": false, "impact": 0.0, "show_cargo": false,
		"build_raise": 0.0, "build_carry": 0.0, "build_check": 0.0, "pump": 0.0,
		"slung": bool(pose.get("slung", false)) or bool(pose.get("gun_equipped", false)),
		"backpack": _wears_pack(), "pack_center": to_local.call(project.call(pack3)), "pack_move": 0.0, "pack_open": 0.0,
		# Face down, the back (and whatever is on it) is the side towards the viewer.
		"pack_front": pitch > deg_to_rad(40.0),
		"face_down": pitch > deg_to_rad(58.0),
	}

## A backpack is drawn whenever one is worn: the outfit decides; review sheets without an outfit
## can ask for one with `backpack`.
func _wears_pack() -> bool:
	var outfit: Dictionary = pose.get("outfit", {})
	if outfit.has("pack"): return not str(outfit.pack).is_empty()
	return bool(pose.get("backpack", false))

## Self-treatment. The hurt arm is held up across the body (or the body bends to the hurt leg, or
## the hands go to the head or ribs) and the other hand works around the wound: winding a bandage
## round and round, dabbing with antiseptic, or unwinding an old dressing.
## Body-part names follow the health screen: "right_*" is the figure's side -1.
func _treat_arms(arms: Dictionary, chest: Vector2, hip: Vector2, head: Vector2, phase: float, part: String, kind: String, reach: float, crouch: float) -> Dictionary:
	var hurt_side := -1 if part.begins_with("right") else 1
	var worker := -hurt_side
	var turns := 5.0 if kind == "bandage" else (6.0 if kind == "disinfect" else 3.0)
	var angle := phase * TAU * turns * (-1.0 if kind == "remove" else 1.0)
	var center: Vector2
	var holder_hand: Vector2
	var holder_elbow: Vector2
	var holding := arms[hurt_side] as PackedVector2Array
	var shoulder: Vector2 = holding[0]
	var radius := Vector2(3.6, 2.4)
	if part.contains("arm") or part.contains("hand"):
		# Raise the hurt forearm across the chest, palm in.
		holder_elbow = shoulder + _joint(hurt_side * 4.5, 6.5, -9.0)
		holder_hand = chest + _joint(hurt_side * 0.5, 12.5, -9.5)
		if part.contains("hand"): center = holder_hand
		elif part.contains("upper"):
			holder_elbow = shoulder + _joint(hurt_side * 3.0, 2.0, -10.0)
			holder_hand = holder_elbow + _joint(-hurt_side * 1.0, 8.5, 1.0)
			center = shoulder.lerp(holder_elbow, 0.5)
		else: center = holder_elbow.lerp(holder_hand, 0.55)
	elif part.contains("thigh") or part.contains("shin") or part.contains("foot"):
		var height: float = 8.0 if part.contains("thigh") else (16.0 if part.contains("shin") else 24.0)
		center = hip + _joint(hurt_side * 5.3, 5.0 * crouch, -height * (1.0 - 0.35 * crouch))
		holder_hand = center + _joint(-hurt_side * 1.5, 3.0, 2.5)
		holder_elbow = shoulder.lerp(holder_hand, 0.5) + _joint(hurt_side * 4.0, 2.0, 0.0)
		radius = Vector2(4.2, 2.6)
	elif part == "head" or part == "neck":
		center = head + _joint(0, 1.5, -1.0 if part == "head" else -7.5)
		holder_hand = center + _joint(hurt_side * 7.5, 1.0, 0.5)
		holder_elbow = shoulder + _joint(hurt_side * 8.0, 4.0, 3.0)
		radius = Vector2(7.5, 3.0)
	else:
		var along: float = {"upper_torso": 0.25, "lower_torso": 0.65, "groin": 1.0}.get(part, 0.4)
		center = chest.lerp(hip, along) + _joint(0, 6.0, 0)
		holder_hand = center + _joint(hurt_side * 7.0, 1.0, 1.0)
		holder_elbow = shoulder + _joint(hurt_side * 6.0, 3.0, -9.0)
		radius = Vector2(8.5, 3.0)
	var circling := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
	if kind == "disinfect": circling = center + _joint(worker * 1.5, 3.0 + 2.0 * absf(sin(angle)), 0.5)
	var working := arms[worker] as PackedVector2Array
	var work_elbow: Vector2 = working[0].lerp(circling, 0.5) + _joint(worker * 4.5, 1.0, -3.0)
	var result := arms.duplicate()
	result[hurt_side] = PackedVector2Array([shoulder, holding[1].lerp(holder_elbow, reach), holding[2].lerp(holder_hand, reach)])
	result[worker] = PackedVector2Array([working[0], working[1].lerp(work_elbow, reach), working[2].lerp(circling, reach)])
	return {"arms": result, "center": center, "hand": result[worker][2]}

func _draw() -> void:
	var t := Time.get_ticks_usec()
	_paint()
	Probe.add("d:characters", Time.get_ticks_usec() - t)
	Probe.count("character_redraws")

func _paint() -> void:
	if frame.is_empty(): return
	var action: String = pose.get("action", "idle")
	var gait: float = float(pose.get("gait_phase", 0.0)) * TAU
	var moving: bool = pose.get("moving", false)
	var front := forward.y
	var width := lerpf(7.1, 10.7, absf(front))
	var complexion := [Color("efdb9f"), Color("d9b27c"), Color("b9885e")]
	var skin: Color = complexion[posmod(actor_id, complexion.size())]
	var shirt: Color = Color("d6bf89") if is_player else CLOTH[posmod(actor_id, CLOTH.size())]
	var vest: Color = Color("b49a63") if is_player else VESTS[posmod(actor_id, VESTS.size())]
	if is_raider: vest = Color("8b5944")
	# What is actually worn: a missing shirt or trousers shows pale underclothes, missing boots show
	# bare feet, a missing vest leaves the shirt showing, and a missing hat shows the hair.
	var outfit: Dictionary = pose.get("outfit", {})
	pants_color = PANTS
	boot_color = BOOT
	hat_item = "<legacy>"
	has_boots = not str(outfit.get("boots", "legacy")).is_empty()
	has_vest = not str(outfit.get("vest", "legacy")).is_empty()
	has_shirt = not str(outfit.get("shirt", "legacy")).is_empty()
	bare_arms = not outfit.is_empty() and str(outfit.get("shirt", "")).is_empty()
	bare_legs = not outfit.is_empty() and str(outfit.get("pants", "")).is_empty()
	if not outfit.is_empty():
		shirt = Outfits.color(str(outfit.get("shirt", "")), skin)
		vest = Outfits.color(str(outfit.get("vest", "")), shirt)
		pants_color = Outfits.color(str(outfit.get("pants", "")), skin)
		boot_color = Outfits.color(str(outfit.get("boots", "")), skin.darkened(0.08))
		hat_item = str(outfit.get("hat", ""))
	wears_badge = str(outfit.get("vest", "")) == "vest:4"
	long_coat = str(outfit.get("vest", "")) in Outfits.LONG_COATS
	mask_item = str(outfit.get("mask", ""))
	var near_side := -1 if across.y < 0 else 1
	var arms: Dictionary = {-1: frame.left_arm, 1: frame.right_arm}
	var legs: Dictionary = {-1: frame.left_leg, 1: frame.right_leg}
	var body_transform := Transform2D(frame.tilt, Vector2(1.0, float(frame.get("lie_scale", 1.0))), 0.0, frame.origin)
	draw_set_transform_matrix(body_transform)

	var leading := near_side
	if moving:
		var stride_direction: Vector2 = pose.get("move_direction", forward)
		var first_stride := sin(gait) * stride_direction.y - across.y * 5.0
		leading = -1 if first_stride > 0.0 else 1
	_draw_leg(-leading, legs[-leading], body_transform)
	_draw_leg(leading, legs[leading], body_transform)

	var object_behind := front < -0.08
	# The backpack: behind the body while worn and seen from the front or side, over the back when
	# seen from behind; on the ground in front of a kneeling player it is nearer or further than them.
	var pack_drawn := false
	var pack_in_front: bool = (forward.y >= 0.0) if float(frame.get("pack_move", 0.0)) > 0.5 else (front < -0.08 or bool(frame.get("pack_front", false)))
	if frame.get("backpack", false) and not pack_in_front:
		_draw_pack(frame.pack_center, float(frame.pack_open), float(frame.pack_move))
		pack_drawn = true
	var far_arm_in_front := front > 0.52
	var both_arms_behind := front < -0.72
	if not far_arm_in_front:
		_draw_arm(arms[-near_side], shirt.darkened(0.10), skin)
	if both_arms_behind:
		_draw_arm(arms[near_side], shirt, skin)
	if object_behind:
		if frame.show_cargo: _draw_cargo(frame.item, frame.quantity, frame.cargo)
		if frame.armed: _draw_rifle(frame.stock, frame.muzzle, frame.pump)
	var slung_on_top: bool = front < -0.08 or bool(frame.get("pack_front", false))
	if frame.slung and not slung_on_top: _draw_slung(frame.chest, frame.hip, front)
	_draw_coat(frame.chest, frame.hip, width, vest, shirt)
	if frame.slung and slung_on_top: _draw_slung(frame.chest, frame.hip, front)
	if frame.get("backpack", false) and float(frame.pack_move) < 0.5 and front > -0.08:
		# Shoulder straps over the front of the shirt.
		for strap_side in [-1.0, 1.0]:
			var top: Vector2 = frame.chest + Vector2(strap_side * width * 0.55, -2.0)
			draw_line(top, frame.chest.lerp(frame.hip, 0.45) + Vector2(strap_side * width * 0.62, 0), Color("5a4027"), 1.6, true)
	_draw_head(frame.head, skin)
	if action == "rest" and int(pose.get("rest_rot", -1)) >= 0 and float(frame.get("rest_lying", 0.0)) > 0.05:
		_draw_blanket(frame.chest, float(frame.rest_lying))
	if not object_behind:
		if frame.show_cargo: _draw_cargo(frame.item, frame.quantity, frame.cargo)
		if frame.armed: _draw_rifle(frame.stock, frame.muzzle, frame.pump)
	elif frame.armed and action == "reload":
		# Seen from behind the tilted gun would vanish behind the body, so it is drawn over it.
		_draw_rifle(frame.stock, frame.muzzle, frame.pump)
	if action == "build" and float(frame.build_carry) > 0.03:
		# The board being carried to its place, held at both ends.
		var held: Vector2 = arms[1][2] - arms[-1][2]
		var along: Vector2 = held.normalized() if held.length() > 0.5 else Vector2.RIGHT
		Props.plank(self, arms[-1][2] - along * 5.0, arms[1][2] + along * 6.0, 2.6, Color("c6a16b"))
	if action in ["chop", "mine", "build", "saw"] and not pose.get("machine_work", false) and not (action == "build" and float(frame.build_carry) > 0.5):
		_draw_tool(action, arms[1][2], frame.impact, float(frame.build_raise))
	if frame.get("backpack", false) and not pack_drawn and float(frame.pack_move) >= 0.5:
		_draw_pack(frame.pack_center, float(frame.pack_open), float(frame.pack_move))
		pack_drawn = true
	if far_arm_in_front:
		_draw_arm(arms[-near_side], shirt, skin)
	if not both_arms_behind:
		_draw_arm(arms[near_side], shirt, skin)
	if frame.get("backpack", false) and not pack_drawn:
		_draw_pack(frame.pack_center, float(frame.pack_open), float(frame.pack_move))
	if action == "cuffed":
		# Iron cuffs on the crossed wrists.
		var left_hand: Vector2 = arms[-1][2]
		var right_hand: Vector2 = arms[1][2]
		draw_line(left_hand, right_hand, Color("3a3b3e"), 1.4, true)
		for wrist in [left_hand, right_hand]:
			draw_arc(wrist, 2.2, 0.0, TAU, 12, Color("9a9ca0"), 1.2, true)
	if action == "tied":
		# Rope: turns round the chest and arms, a knot, and the wrists lashed behind the back.
		var rope := Color("b89a62")
		var rope_dark := Color("7d6440")
		var chest_at: Vector2 = frame.chest
		for turn in range(3):
			var y: float = 3.0 + float(turn) * 4.0
			var a: Vector2 = chest_at + _joint(-11.0, 0, -y)
			var b: Vector2 = chest_at + _joint(11.0, 0, -y)
			draw_line(a, b, rope_dark, 2.6, true)
			draw_line(a, b, rope, 1.6, true)
		draw_circle(chest_at + _joint(2.0, 1.5, -7.0), 2.0, rope)
		var left_wrist: Vector2 = arms[-1][2]
		var right_wrist: Vector2 = arms[1][2]
		draw_line(left_wrist, right_wrist, rope, 1.8, true)
		for wrist in [left_wrist, right_wrist]:
			draw_arc(wrist, 2.4, 0.0, TAU, 10, rope_dark, 1.4, true)
	if action == "treat" and float(frame.get("treat_reach", 0.0)) > 0.3:
		var roll: Vector2 = frame.treat_hand
		var wound: Vector2 = frame.treat_center
		if pose.get("treat_kind", "bandage") == "disinfect":
			_oval(roll + Vector2(0, -1.5), Vector2(1.6, 2.4), Color("e9e4d6"), 0.0, 0.7)
		else:
			# The dressing wound so far, and the strip still running to the roll.
			var wraps: float = float(pose.get("phase", 0.0)) if pose.get("treat_kind", "bandage") == "bandage" else 1.0 - float(pose.get("phase", 0.0))
			_oval(wound, Vector2(2.6 + 2.2 * wraps, 1.6 + 1.0 * wraps), Color("efeadb"), 0.0, 0.8)
			draw_line(wound, roll, Color("f3efe2"), 1.5, true)
			_oval(roll, Vector2(2.0, 2.0), Color("f7f3e8"), 0.0, 0.8)
	draw_set_transform(Vector2.ZERO)

## Leg chain for one side. `run` is a 0-1 blend (a bool still works): 0 is the walking
## cycle, 1 the running cycle, and when not moving a non-zero value is the braking stance.
func leg_joints(side: int, hip: Vector2, gait: float, moving: bool, run: Variant = 0.0, hip_height: float = HIP_HEIGHT) -> PackedVector2Array:
	var amount: float = clampf(float(run), 0.0, 1.0)
	var walk := _walk_leg(side, hip, gait, moving)
	if amount <= 0.001: return walk
	var fast := _run_leg(side, hip, hip_height, gait, moving)
	var weight: float = smoothstep(0.0, 1.0, amount)
	return PackedVector2Array([walk[0].lerp(fast[0], weight), walk[1].lerp(fast[1], weight), walk[2].lerp(fast[2], weight)])

const WALK_STANCE := 0.60

## Negative pitch raises the toes for heel contact; positive pitch rolls the
## heel up over the toes. The foot clears the ground before levelling in swing.
func walking_foot_pitch(side: int, gait: float) -> float:
	var cycle := fposmod(gait / TAU + (0.5 if side > 0 else 0.0), 1.0)
	var heel := -0.32 * (1.0 - smoothstep(0.0, 0.14, cycle))
	var push := 0.58 * smoothstep(0.39, WALK_STANCE, cycle) * (1.0 - smoothstep(WALK_STANCE, 0.84, cycle))
	var landing := -0.32 * smoothstep(0.85, 1.0, cycle)
	return heel + push + landing

## The roll is relative to the ankle. Wide side views show the rotation;
## front/back views show the shorter or taller projected boot instead.
func boot_roll(pitch: float) -> Transform2D:
	return Transform2D(pitch * forward.x, Vector2(1.0, 1.0 + sin(pitch) * forward.y * 0.28), 0.0, Vector2.ZERO)

func boot_contact(pitch: float) -> Vector2:
	var edge := 1.0 if pitch >= 0.0 else -1.0
	var radius := 3.3 + absf(forward.x) * 0.6
	return _joint(0, 1.8, 0) + Vector2(forward.x * (2.6 + edge * (radius - 0.5)), 3.5)

func _walk_leg(side: int, hip: Vector2, gait: float, moving: bool) -> PackedVector2Array:
	var cycle := fposmod(gait / TAU + (0.5 if side > 0 else 0.0), 1.0)
	var top := hip + _joint(side * 5.3, 0, 0)
	var foot := _joint(side * 5.3, 0, 3.0)
	var direction: Vector2 = pose.get("move_direction", forward) if moving else forward
	var travel := Vector2(direction.x, direction.y * 0.48)
	# Stepping against the way the body faces (backing off while aiming) or sideways (strafing):
	# the feet still go the way of travel, but knees only bend the way the body faces, the steps
	# are shorter, and a backward step lands toe first.
	var along: float = direction.normalized().dot(forward.normalized()) if moving and direction.length() > 0.01 else 1.0
	var backing: float = clampf(-along * 1.6, 0.0, 1.0)                  # 0 forwards .. 1 straight back
	var sideways: float = clampf(1.0 - absf(along) * 1.6, 0.0, 1.0)      # 0 along the facing .. 1 straight across
	var knee_way := Vector2(forward.x, forward.y * 0.48) if backing > 0.0 or sideways > 0.0 else travel
	# Keep the standing leg vertical. Only a lowered hip needs knee bend.
	var flex := maxf(0.0, HIP_HEIGHT + hip.y) * 0.5
	if moving:
		var cycle_distance := Director.CELL * Director.WALK_CYCLE_METERS * (1.0 - 0.35 * clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0)) * (1.0 - 0.3 * backing - 0.2 * sideways)
		# Land just ahead of the hips. The body travels farther past the planted
		# foot before push-off than it travels to meet it after contact.
		var front := cycle_distance * WALK_STANCE * 0.375
		var rear := front - cycle_distance * WALK_STANCE
		var stride: float
		var lift: float
		if cycle < WALK_STANCE:
			stride = front - cycle * cycle_distance
			lift = 0.0
			flex = 1.0 + 2.7 * sin(PI * cycle / WALK_STANCE)
		else:
			var swing := (cycle - WALK_STANCE) / (1.0 - WALK_STANCE)
			# Match the contact velocity at either end of the swing so the foot
			# briefly trails at toe-off and slows smoothly into the next step.
			var tangent := cycle_distance * (1.0 - WALK_STANCE) / 3.0
			stride = bezier_interpolate(rear, rear - tangent, front + tangent, front, swing)
			var recovery := pow(sin(PI * swing), 1.6)
			lift = 5.0 * recovery * (1.0 - 0.4 * clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0))
			flex = 1.0 + 5.0 * recovery
		foot = _joint(side * 5.4, 0, 3.0 + lift) + travel * stride
		var pitch := walking_foot_pitch(side, gait) * (1.0 - 1.7 * backing)   # backing off: toe first, heel down
		if sideways > 0.0: foot += _joint(side * 1.2 * sideways * sin(PI * clampf(cycle, 0.0, 1.0)), 0, 0)   # a side-step opens the feet
		var contact := boot_contact(pitch)
		foot += contact - boot_roll(pitch) * contact
	var sneak: float = clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0)
	if sneak > 0.001 and not moving:
		# A crouched stance: one foot a little ahead of the other.
		foot += _joint(side * 0.8 * sneak, side * 2.5 * sneak, 0.0)
	var knee := top.lerp(foot, 0.52) + knee_way * flex
	if sneak > 0.001:
		# Two-bone knee: the closer the hip comes to the foot, the further the knee folds forward.
		var reach_now := top.distance_to(foot)
		var bend := sqrt(maxf(0.0, 13.4 * 13.4 - reach_now * reach_now * 0.25))
		knee = top.lerp(foot, 0.5) + knee_way * maxf(flex, bend)
	return PackedVector2Array([top, knee, foot])

## Running cycle, solved as a two-bone leg so the knee always bends forwards: a short stance
## with the foot landing under the hip, a high heel recovery behind the body, then the knee
## drives forward again. Both feet leave the ground for part of each stride.
func _run_leg(side: int, hip: Vector2, hip_height: float, gait: float, moving: bool) -> PackedVector2Array:
	const THIGH := 16.5
	var foot_reach: float
	var foot_lift: float
	if moving:
		var cycle := fposmod(gait / TAU + (0.5 if side > 0 else 0.0), 1.0)
		var stance := 0.36
		# Stance reach is exactly the ground covered, so planted feet do not slide.
		var reach := Director.CELL * Director.RUN_CYCLE_METERS * stance * 0.5
		if cycle < stance:
			foot_reach = lerpf(reach, -reach, cycle / stance)
			foot_lift = 0.0
		else:
			var swing := (cycle - stance) / (1.0 - stance)
			# Continue behind the hip after toe-off before folding the heel up.
			# Tangents match the planted foot at both ends, including the cycle wrap.
			var recovery := 0.28
			var back := -reach - 8.0
			var travel := Director.CELL * Director.RUN_CYCLE_METERS * (1.0 - stance)
			if swing < recovery:
				foot_reach = bezier_interpolate(-reach, -reach - travel * recovery / 3.0, back, back, swing / recovery)
			else:
				var t := (swing - recovery) / (1.0 - recovery)
				foot_reach = bezier_interpolate(back, back, reach + travel * (1.0 - recovery) / 3.0, reach, t)
			foot_lift = 21.0 * pow(sin(PI * swing), 1.35)
	else:
		# Braking stance: one foot planted well ahead, the other trailing.
		var lead := -1 if fposmod(gait / TAU, 1.0) < 0.5 else 1
		foot_reach = 9.0 if side == lead else -3.0
		foot_lift = 0.0
	var span := Vector2(foot_reach, 3.0 + foot_lift - hip_height)
	var length := span.length()
	var limit := THIGH * 2.0 - 0.2
	if length > limit:
		span *= limit / length
		length = limit
	var bend := sqrt(maxf(0.0, THIGH * THIGH - length * length * 0.25))
	var knee_offset := span * 0.5 + Vector2(-span.y, span.x) / maxf(length, 0.001) * bend
	var top := hip + _joint(side * 5.3, 0, 0)
	var direction: Vector2 = pose.get("move_direction", forward) if moving else forward
	var travel := Vector2(direction.x, direction.y * 0.48)
	var knee := _joint(side * 5.3, 0, hip_height + knee_offset.y) + travel * knee_offset.x
	var foot := _joint(side * 5.4, 0, hip_height + span.y) + travel * (1.5 + span.x)
	return PackedVector2Array([top, knee, foot])

func _draw_leg(side: int, points: PackedVector2Array, body_transform: Transform2D) -> void:
	var top := points[0]
	var knee := points[1]
	var foot := points[2]
	var tone := pants_color.darkened(0.11) if across.y * side < -0.02 else pants_color
	var pitch: float = frame.left_foot_pitch if side < 0 else frame.right_foot_pitch
	var shoe_transform := boot_roll(pitch)
	var cuff := shoe_transform * Vector2(0, -4)
	_limb_chain(PackedVector2Array([top, knee, foot + cuff]), Vector3(3.9, 3.0, 2.4) if bare_legs else Vector3(4.2, 3.4, 2.7), tone)
	var shin := (foot - knee).normalized()
	var cross := shin.orthogonal()
	if bare_legs:
		# Boxer shorts over the top of the thigh.
		var thigh := (knee - top).normalized()
		var side_of := thigh.orthogonal()
		var hem := top.lerp(knee, 0.42)
		var shorts := PackedVector2Array([top - side_of * 4.9 - thigh * 1.5, top + side_of * 4.9 - thigh * 1.5, hem + side_of * 4.7, hem - side_of * 4.7])
		_shape(shorts, Color("ece6d8"), 0.9)
		draw_line(hem + side_of * 4.4 - thigh * 0.8, hem - side_of * 4.4 - thigh * 0.8, Color("c9c0ad"), 0.6, true)
	else:
		# Small fabric folds, not round kneecaps.
		draw_line(knee - cross * 2.5 + shin, knee + cross * 0.7 + shin * 1.8, tone.darkened(0.3), 0.65, true)
		draw_line(knee + cross * 0.4 + shin * 3.1, knee + cross * 2.0 + shin * 2.5, tone.darkened(0.21), 0.5, true)
	shoe_transform.origin = foot
	draw_set_transform_matrix(body_transform * shoe_transform)
	var shoe := _joint(0, 1.8, 0)
	var side_view := absf(forward.x)
	var toe := Vector2(forward.x * 2.6, 0.8)
	var r := 3.3 + side_view * 0.6
	if not has_boots:
		_oval(shoe + toe * 0.5, Vector2(r, 2.5), boot_color, forward.x * 0.15, 1.0)
		for finger in range(3):
			var at := shoe + toe * 0.5 + Vector2(-1.5 + finger * 1.2, 1.4)
			draw_line(at, at + Vector2(0.15, -0.8), boot_color.darkened(0.25), 0.4, true)
		draw_set_transform_matrix(body_transform)
		return
	# An ankle shaft, rounded toe and separate sole give the boot a silhouette.
	var boot := PackedVector2Array([
		Vector2(-2.6, -5.5), Vector2(2.6, -5.5),
		shoe + Vector2(2.9, -1.8), shoe + toe + Vector2(r, -0.6),
		shoe + toe + Vector2(r + 0.3, 1.5), shoe + toe + Vector2(r - 1, 2.7),
		shoe + toe + Vector2(-r + 0.3, 2.7), shoe + toe + Vector2(-r - 0.3, 1.3),
		shoe + Vector2(-2.9, -1.8)])
	_shape(_rounded(boot, 0.3), boot_color, 1.45)
	draw_polyline(PackedVector2Array([shoe + toe + Vector2(-r, 1.8), shoe + toe + Vector2(0, 2.1), shoe + toe + Vector2(r, 1.4)]), boot_color.darkened(0.5), 1.1, true)
	draw_line(Vector2(-2.5, -4.8), Vector2(2.4, -4.8), boot_color.lightened(0.26), 0.7, true)
	for lace in range(2):
		var at := shoe + Vector2(forward.x * 0.6, -3.0 + lace * 1.2)
		draw_line(at + Vector2(-1, 0), at + Vector2(1.1, -0.3), Color("b5a17c"), 0.45, true)

	draw_set_transform_matrix(body_transform)

func _draw_arm(joints: PackedVector2Array, color: Color, skin: Color) -> void:
	if bare_arms:
		# A bare arm: skin all the way down, slimmer than a sleeve, no cuff.
		_limb_chain(joints, Vector3(3.3, 2.7, 2.0), skin if color.v >= skin.v * 0.95 else skin.darkened(0.08))
		var down := (joints[2] - joints[1]).normalized()
		_oval(joints[2] + down * 0.7, Vector2(2.25, 2.7), skin, down.angle() - PI / 2.0, 1.15)
		return
	_limb_chain(joints, Vector3(3.8, 3.1, 2.2), color)
	var fore := (joints[2] - joints[1]).normalized()
	var cross := fore.orthogonal()
	# Tailored cuff and elbow crease. The hand is smaller than the sleeve.
	draw_line(joints[1] + cross * 2.1, joints[1] - cross * 0.8 + fore * 1.3, color.darkened(0.28), 0.65, true)
	var cuff := joints[2] - fore * 2.4
	_shape(PackedVector2Array([cuff + cross * 2.5 - fore, cuff - cross * 2.5 - fore,
		cuff - cross * 2.4 + fore, cuff + cross * 2.4 + fore]), color.lightened(0.18), 0.8)
	draw_circle(cuff - cross * 1.2, 0.45, INK, true, -1, true)
	_oval(joints[2] + fore * 0.7, Vector2(2.25, 2.7), skin, fore.angle() - PI / 2.0, 1.15)
	_oval(joints[2] + cross * 1.8, Vector2(0.9, 1.5), skin.darkened(0.06), fore.angle() - PI / 2.0, 0.7)
	draw_line(joints[2] + fore * 1.5 - cross, joints[2] + fore * 1.8 + cross * 0.7, skin.darkened(0.23), 0.45, true)

func _draw_coat(chest: Vector2, hip: Vector2, width: float, vest: Color, shirt: Color) -> void:
	var center := chest.lerp(hip, 0.55)
	var body := PackedVector2Array([
		chest + Vector2(-width * 0.52, -2.9), chest + Vector2(width * 0.52, -2.9),
		chest + Vector2(width * 0.91, 0.1), chest + Vector2(width * 0.89, 5),
		center + Vector2(width * 0.71, 1), hip + Vector2(width * 0.74, -0.4),
		hip + Vector2(width * 0.38, 2.1), hip + Vector2(0, 0.7),
		hip + Vector2(-width * 0.38, 2.1), hip + Vector2(-width * 0.74, -0.4),
		center + Vector2(-width * 0.71, 1), chest + Vector2(-width * 0.89, 5),
		chest + Vector2(-width * 0.91, 0.1)])
	if long_coat and has_vest:
		# Duster tails: open at the front, hanging from the waist to the knees, split up the back.
		var hem: float = 6.0 if str(pose.get("action", "")) in ["sit", "cook", "tied"] else 13.0
		for tail_side in [-1.0, 1.0]:
			_shape(PackedVector2Array([hip + Vector2(tail_side * width * 0.78, -1.0), hip + Vector2(tail_side * 1.2, 0.5),
				hip + Vector2(tail_side * 1.6, hem), hip + Vector2(tail_side * width * 0.98, hem - 1.0)]), vest.darkened(0.08), 1.2)
			draw_line(hip + Vector2(tail_side * width * 0.5, 1.0), hip + Vector2(tail_side * width * 0.62, hem - 1.5), vest.darkened(0.3), 0.6, true)
	_shape(_rounded(body, 0.18), vest, 1.6)
	# A single side shadow follows the tailored waist. No inset plastic panel.
	draw_colored_polygon(PackedVector2Array([chest + Vector2(width * 0.57, -0.5), chest + Vector2(width * 0.88, 0.2),
		center + Vector2(width * 0.70, 1), hip + Vector2(width * 0.72, -0.5),
		hip + Vector2(width * 0.40, 1.1), center + Vector2(width * 0.45, 0)]), vest.darkened(0.18))
	draw_line(chest + Vector2(-width * 0.65, 1), center + Vector2(-width * 0.55, -1), vest.lightened(0.18), 0.75, true)
	if wears_badge and forward.y > -0.3:
		# The sheriff's star, pinned on the left breast.
		var star_at := chest + Vector2(width * 0.42 + forward.x * 1.2, 5.2)
		var points := PackedVector2Array()
		for i in range(10):
			var r: float = 2.6 if i % 2 == 0 else 1.15
			points.append(star_at + Vector2.from_angle(-PI / 2.0 + float(i) * PI / 5.0) * r)
		draw_colored_polygon(points, Color("f0c955"))
		points.append(points[0])
		draw_polyline(points, Color("7a5a1c"), 0.45, true)
		draw_circle(star_at, 0.55, Color("fff0b0"))
	if bare_legs:
		# The shorts' waistband sits at the hips, over the bottom of the shirt or the bare belly.
		_shape(PackedVector2Array([hip + Vector2(-width * 0.76, -2.6), hip + Vector2(width * 0.76, -2.6), hip + Vector2(width * 0.74, 2.4), hip + Vector2(-width * 0.74, 2.4)]), Color("ece6d8"), 0.9)
		draw_line(hip + Vector2(-width * 0.7, -1.4), hip + Vector2(width * 0.7, -1.4), Color("bdb39e"), 0.6, true)
	if not has_shirt and not has_vest:
		if forward.y > -0.3:
			# A bare chest: collarbones, a little shading and the navel.
			draw_polyline(PackedVector2Array([chest + Vector2(-width * 0.5, 0.5), chest + Vector2(-1.0, 1.6), chest + Vector2(1.0, 1.6), chest + Vector2(width * 0.5, 0.5)]), vest.darkened(0.22), 0.6, true)
			draw_line(chest + Vector2(forward.x * 2.0, 3.5), chest.lerp(hip, 0.45) + Vector2(forward.x * 2.0, 0), vest.darkened(0.15), 0.5, true)
			draw_circle(chest.lerp(hip, 0.72) + Vector2(forward.x * 2.0, 0), 0.6, vest.darkened(0.3), true, -1, true)
		return
	var front := maxf(0.0, forward.y)
	var seam_top := chest + Vector2(forward.x * width * 0.58, 1)
	var seam_low := hip + Vector2(forward.x * width * 0.47, 0)
	if forward.y >= -0.08:
		var collar := chest + Vector2(forward.x * 2.2, -2.5)
		_shape(PackedVector2Array([collar + Vector2(-3.9, -1.0), collar + Vector2(3.9, -1.0), collar + Vector2(1, 6.2), collar + Vector2(-1, 6.2)]), shirt.lightened(0.12), 0.8)
		for side in [-1, 1]:
			var lapel := maxf(3.8, front * width * 0.63)
			_shape(PackedVector2Array([collar + Vector2(side * 2.8, -1), collar + Vector2(side * lapel, 0.3),
				collar + Vector2(side * lapel * 0.55, 5.3), collar + Vector2(side * 0.8, 3.1)]), shirt, 0.85)
		draw_line(seam_top + Vector2(0, 5), seam_low, INK.lightened(0.16), 0.65, true)
		for t in [0.44, 0.65, 0.85]:
			var button := seam_top.lerp(seam_low, t) + Vector2(-1.65 * maxf(0.25, front), 0)
			draw_circle(button, 0.65, INK, true, -1, true)
			draw_circle(button + Vector2(-0.15, -0.18), 0.2, Color("e0c585"), true, -1, true)
		# Welt pockets follow the turning torso; they disappear at the profile.
		if front > 0.3 and has_vest:
			for side in [-1, 1]:
				var pocket := center.lerp(hip, 0.35) + Vector2(side * width * 0.45 + forward.x * 2, 0)
				draw_line(pocket + Vector2(-2.0 * front, -0.5), pocket + Vector2(2.0 * front, -0.8), INK, 0.65, true)
				draw_line(pocket + Vector2(-1.9 * front, 0.3), pocket + Vector2(1.9 * front, 0), vest.lightened(0.22), 0.5, true)
	else:
		var back := Vector2(-forward.x * 2.0, 0)
		draw_line(chest + back + Vector2(0, 2), hip + back, vest.darkened(0.25), 0.6, true)
		if not has_vest: return
		var strap := hip + Vector2(0, -4.7)
		draw_line(strap + Vector2(-width * 0.52, 0), strap + Vector2(width * 0.52, 0), vest.darkened(0.3), 1.3, true)
		_shape(PackedVector2Array([strap + Vector2(-1.2, -1), strap + Vector2(1.2, -1), strap + Vector2(1.2, 1), strap + Vector2(-1.2, 1)]), Color("b9a06a"), 0.55)

## A canvas backpack with a leather flap, buckled straps and a bedroll on top. `open` lifts the flap.
func _draw_pack(center: Vector2, open: float, move: float) -> void:
	var canvas := Color("8a6d47")
	var leather := Color("5a4027")
	var body := PackedVector2Array([center + Vector2(-6.5, -6.5), center + Vector2(6.5, -6.5), center + Vector2(7.2, 6.0), center + Vector2(5.5, 7.5), center + Vector2(-5.5, 7.5), center + Vector2(-7.2, 6.0)])
	_shape(_rounded(body, 0.25), canvas, 1.1)
	draw_line(center + Vector2(-6.0, 2.5), center + Vector2(6.0, 2.5), canvas.darkened(0.2), 0.6, true)
	if move < 0.95 or open < 0.5:
		# Bedroll strapped along the top.
		_oval(center + Vector2(0, -7.6), Vector2(7.6, 2.3), Color("8c8f7e"), 0.0, 0.9)
		draw_line(center + Vector2(-3.5, -9.6), center + Vector2(-3.5, -5.6), leather, 0.9, true)
		draw_line(center + Vector2(3.5, -9.6), center + Vector2(3.5, -5.6), leather, 0.9, true)
	var flap_lift: float = 6.0 * open
	var flap := PackedVector2Array([center + Vector2(-6.2, -6.0 - flap_lift), center + Vector2(6.2, -6.0 - flap_lift), center + Vector2(5.4, 1.0 - flap_lift * 1.6), center + Vector2(-5.4, 1.0 - flap_lift * 1.6)])
	if open > 0.3:
		# The open mouth of the bag, with a few things showing.
		_oval(center + Vector2(0, -5.6), Vector2(5.6, 2.0), Color("2e2318"), 0.0, 0.6)
		_oval(center + Vector2(-2.0, -6.1), Vector2(1.8, 1.1), Color("c9b48a"), 0.3, 0.4)
		_oval(center + Vector2(2.4, -6.2), Vector2(1.4, 1.0), Color("b07a4b"), 0.0, 0.4)
	_shape(_rounded(flap, 0.2), leather, 1.0)
	if open < 0.3:
		for x in [-3.2, 3.2]:
			draw_line(center + Vector2(x, 0.5), center + Vector2(x, 4.0), leather, 1.1, true)
			draw_rect(Rect2(center + Vector2(x - 0.9, 0.3), Vector2(1.8, 1.4)), Color("c9b06a"))

## The bed's blanket pulled up to the chest, drawn in the body's own (lying) frame.
func _draw_blanket(chest: Vector2, amount: float) -> void:
	# Pulled up from the feet as the sleeper settles.
	var cloth := Color("9fa7a5")
	var pull: float = smoothstep(0.35, 1.0, amount)
	if pull <= 0.01: return
	amount = 1.0
	var top: float = lerpf(-4.0, chest.y + 3.0, pull)
	var middle: float = (top + 2.0) * 0.5
	var shape := PackedVector2Array([Vector2(-13, top), Vector2(13, top + 0.5), Vector2(14.5, middle), Vector2(13.5, 2), Vector2(-13.5, 2), Vector2(-14.5, middle)])
	draw_colored_polygon(_rounded(shape, 0.2), cloth)
	draw_line(Vector2(-12.5, top + 1.2), Vector2(12.5, top + 1.6), Color(0.93, 0.9, 0.82, amount), 2.2, true)
	for x in [-6.0, 1.0, 8.0]:
		draw_line(Vector2(x, top + 4), Vector2(x + 1.0, 0.0), Color(cloth.darkened(0.2), amount * 0.7), 0.6, true)
	var outline := _rounded(shape, 0.2)
	outline.append(outline[0])
	draw_polyline(outline, Color(INK, amount * 0.8), 0.7, true)

func _draw_head(head: Vector2, skin: Color) -> void:
	var hair: Color = HAIRS[0] if is_player else HAIRS[posmod(actor_id * 7 + 3, HAIRS.size())]
	var iris: Color = EYES[posmod(actor_id * 5 + 1, EYES.size())]
	var face := head + Vector2(forward.x * 2.2, 0)
	# A visible neck separates the jaw and shirt collar.
	_shape(PackedVector2Array([head + Vector2(-2.6, 5.5), head + Vector2(2.6, 5.5),
		head + Vector2(2.7, 9.5), head + Vector2(0, 10.2), head + Vector2(-2.7, 9.5)]), skin.darkened(0.12), 0.8)
	var back := head + Vector2(-forward.x * 1.3, -2.8)
	_shape(_rounded(PackedVector2Array([back + Vector2(-7.3, -3.3), back + Vector2(-4.7, -7.4),
		back + Vector2(3.4, -7.8), back + Vector2(7.6, -3.7), back + Vector2(7.0, 4.2),
		back + Vector2(4.2, 7.5), back + Vector2(2.0, 6.9), back + Vector2(0, 8.2),
		back + Vector2(-2.6, 6.8), back + Vector2(-5.2, 7.0), back + Vector2(-7.4, 2.5)]), 0.25), hair, 1.25)
	if forward.y < -0.5:
		for lock in range(3):
			var at := back + Vector2(-4.5 + lock * 3.4, 0.8)
			draw_line(at, at + Vector2(0.5, 3.6), hair.lightened(0.14), 0.55, true)
	var visible := forward.y > -0.6
	if visible:
		var side := signf(forward.x)
		var profile := absf(forward.x) > 0.92
		var outline: PackedVector2Array
		if profile:
			outline = PackedVector2Array([face + Vector2(-side * 4.6, -7), face + Vector2(side * 4.8, -6.3),
				face + Vector2(side * 5.2, -1.5), face + Vector2(side * 6.4, 0.8), face + Vector2(side * 5.1, 2.3),
				face + Vector2(side * 4.8, 5.2), face + Vector2(side * 1.5, 8.0),
				face + Vector2(-side * 2.1, 7), face + Vector2(-side * 5.4, 2)])
		else:
			outline = PackedVector2Array([face + Vector2(-6.1, -6.9), face + Vector2(6.1, -6.9),
				face + Vector2(6.5, -0.5), face + Vector2(5.1, 4.7), face + Vector2(2.0, 8.0),
				face + Vector2(-1.9, 8.0), face + Vector2(-5.1, 4.6), face + Vector2(-6.6, -0.5)])
		_shape(_rounded(outline, 0.24), skin, 1.15)
		if not profile:
			draw_colored_polygon(PackedVector2Array([face + Vector2(5.5, -4), face + Vector2(6.1, -0.6),
				face + Vector2(4.7, 4.5), face + Vector2(1.9, 7.5), face + Vector2(-0.7, 7.5),
				face + Vector2(3.1, 3.8)]), skin.darkened(0.13))
		# Far eye narrows in a three-quarter view. Almond-shaped lids replace round goggles.
		for eye_side in [-1, 1]:
			if profile and eye_side != int(side): continue
			var eye_width := 1.9 if profile else lerpf(1.45, 2.05, clampf(0.6 + eye_side * forward.x, 0, 1))
			var eye := face + Vector2(side * 3.35 if profile else eye_side * 2.9 + forward.x * 0.45, -0.6)
			var eye_shape := PackedVector2Array([eye + Vector2(-eye_width, 0), eye + Vector2(-eye_width * 0.5, -0.9),
				eye + Vector2(eye_width * 0.55, -0.85), eye + Vector2(eye_width, -0.1),
				eye + Vector2(eye_width * 0.5, 0.9), eye + Vector2(-eye_width * 0.55, 0.85)])
			draw_colored_polygon(eye_shape, Color("fff3d9"))
			_oval(eye + Vector2(forward.x * 0.35, 0.05), Vector2(0.78, 0.91), iris, 0, 0)
			_oval(eye + Vector2(forward.x * 0.35, 0.08), Vector2(0.34, 0.66), INK, 0, 0)
			draw_circle(eye + Vector2(-0.15, -0.3), 0.23, Color.WHITE, true, -1, true)
			draw_polyline(PackedVector2Array([eye_shape[0], eye_shape[1], eye_shape[2], eye_shape[3]]), INK, 0.65, true)
			draw_line(eye + Vector2(-eye_width, -2.0), eye + Vector2(eye_width * 0.9, -2.2), hair.darkened(0.25), 0.8, true)
		var nose := face + Vector2(forward.x * 2.7, 1.5)
		draw_polyline(PackedVector2Array([nose + Vector2(0, -0.2), nose + Vector2(0.7, 1.3), nose + Vector2(-0.4, 1.6)]), skin.darkened(0.33), 0.55, true)
		var mouth := face + Vector2(forward.x * 2.8, 5.1)
		draw_polyline(PackedVector2Array([mouth + Vector2(-1.6, -0.2), mouth + Vector2(0.1, 0.1), mouth + Vector2(1.5, -0.3)]), INK, 0.65, true)
		# The player's beard grows by the day (look.gd): stubble, then a full beard round the jaw.
		var beard: int = int(pose.get("look", {}).get("beard", 0)) if is_player else 0
		if beard >= 55:
			draw_colored_polygon(PackedVector2Array([face + Vector2(-5.4, 2.0), face + Vector2(-2.4, 4.0), mouth + Vector2(-1.9, 0.9),
				mouth + Vector2(1.9, 0.9), face + Vector2(2.6, 4.0), face + Vector2(5.4, 2.0), face + Vector2(4.6, 5.6),
				face + Vector2(1.9, 9.0 + beard / 40.0), face + Vector2(-1.9, 9.0 + beard / 40.0), face + Vector2(-4.8, 5.6)]), Color(hair, 0.92))
			draw_polyline(PackedVector2Array([mouth + Vector2(-1.6, -0.2), mouth + Vector2(0.1, 0.1), mouth + Vector2(1.5, -0.3)]), INK, 0.65, true)
		elif beard >= 20:
			for dot in range(9):
				var along: float = float(dot) / 8.0
				draw_circle(face + Vector2(lerpf(-4.8, 4.8, along), 5.2 + sin(along * PI) * 2.6), 0.42, Color(hair, 0.55), true, -1, true)
		if not mask_item.is_empty():
			# A bandana pulled up over the nose and mouth, tied behind the head.
			var cloth: Color = Outfits.BANDANAS[int(mask_item.get_slice(":", 1)) % Outfits.BANDANAS.size()]
			var low: PackedVector2Array
			if profile:
				low = PackedVector2Array([face + Vector2(-side * 5.4, 0.6), face + Vector2(side * 6.8, 0.4), face + Vector2(side * 5.6, 4.6),
					face + Vector2(side * 2.0, 9.6), face + Vector2(-side * 2.4, 7.4), face + Vector2(-side * 5.6, 2.6)])
			else:
				low = PackedVector2Array([face + Vector2(-6.7, 0.6), face + Vector2(6.7, 0.6), face + Vector2(5.4, 4.8),
					face + Vector2(forward.x * 2.0, 10.6), face + Vector2(-5.4, 4.8)])
			_shape(low, cloth, 0.9)
			draw_line(face + Vector2(-4.5, 3.0), face + Vector2(4.5, 3.0), cloth.darkened(0.25), 0.6, true)
			for dot in range(3):
				draw_circle(face + Vector2(-3.0 + dot * 3.0 + forward.x * 1.5, 5.6), 0.5, cloth.lightened(0.35), true, -1, true)
		# One visible ear and a shaped sideburn, away from the eyes.
		var ear_side := -side if side != 0 else -1.0
		var ear := face + Vector2(ear_side * 6.4, 1.6)
		_oval(ear, Vector2(1.25, 2.0), skin, 0, 0.8)
		draw_line(ear + Vector2(0.1, -0.6), ear + Vector2(-0.2, 0.7), skin.darkened(0.3), 0.45, true)
		var fringe := face + Vector2(0, -6.7)
		_shape(PackedVector2Array([fringe + Vector2(-6.3, -1.4), fringe + Vector2(5.8, -1.7),
			fringe + Vector2(5.6, 2.4), fringe + Vector2(3.2, 1.0), fringe + Vector2(1, 2.5),
			fringe + Vector2(-0.9, 0.7), fringe + Vector2(-3.7, 2.1), fringe + Vector2(-5.7, 4.4)]), hair, 0.65)
	var hatless: bool = (hat_item == "") if hat_item != "<legacy>" else (not is_player and posmod(actor_id, 4) == 1)
	if hatless:
		var top := head + Vector2(-forward.x * 1.3, -6.6)
		_shape(PackedVector2Array([top + Vector2(-7.7, 3), top + Vector2(-8.0, -1.5), top + Vector2(-5.2, -4.1),
			top + Vector2(-1.8, -5.7), top + Vector2(-2.7, -3.7), top + Vector2(3.5, -4.9),
			top + Vector2(7.6, -1.7), top + Vector2(7.2, 3.3), top + Vector2(3.0, 1.3),
			top + Vector2(-0.5, 2.6), top + Vector2(-3.9, 1.7)]), hair, 1.0)
		for lock in range(3):
			var at := top + Vector2(-4.7 + lock * 3.5, -2.1)
			draw_line(at, at + Vector2(2.3, 2.3), hair.lightened(0.2), 0.6, true)
		return
	var hat: Color = Outfits.color(hat_item, Color("bf9558")) if hat_item != "<legacy>" else (Color("d3a35a") if is_player else Color("bf9558"))
	var brim := head + Vector2(forward.x * 0.6, -7.8)
	if hat_item == "hat:3":
		# The sheriff's cattleman: a broad brim curled up at the sides, a tall creased crown and a
		# silver band with a small concho.
		_oval(brim + Vector2(0, 0.9), Vector2(15.6, 4.4), hat.darkened(0.25), -forward.x * 0.06, 1.3)
		_oval(brim + Vector2(0, -0.1), Vector2(15.2, 3.9), hat, -forward.x * 0.06, 1.2)
		for curl in [-1.0, 1.0]:
			_oval(brim + Vector2(curl * 12.8, -1.6), Vector2(3.2, 2.1), hat.lightened(0.08), curl * 0.5, 0.9)
		var tall := brim + Vector2(-forward.x * 0.7, -5.4)
		_shape(PackedVector2Array([tall + Vector2(-7.0, 4.6), tall + Vector2(-6.4, -2.6), tall + Vector2(-3.6, -4.0),
			tall + Vector2(0.0, -2.6), tall + Vector2(3.6, -4.0), tall + Vector2(6.4, -2.6),
			tall + Vector2(7.0, 4.6), tall + Vector2(3.0, 5.6), tall + Vector2(-3.4, 5.4)]), hat, 1.25)
		draw_line(tall + Vector2(0, -2.4), tall + Vector2(0, 1.5), hat.darkened(0.35), 0.8, true)
		draw_polyline(PackedVector2Array([tall + Vector2(-6.2, 3.0), tall + Vector2(0, 3.9), tall + Vector2(6.2, 3.0)]), Color("b9b4a6"), 1.6, true)
		draw_circle(tall + Vector2(forward.x * 3.0, 3.6), 0.9, Color("e8e3d4"))
		return
	# Wide, gently curved brim with a clean stitched rim; a pinched felt crown.
	_oval(brim + Vector2(0, 0.7), Vector2(13.5, 4.1), hat.darkened(0.23), -forward.x * 0.06, 1.3)
	_oval(brim + Vector2(0, -0.1), Vector2(13.3, 3.7), hat, -forward.x * 0.06, 1.2)
	draw_polyline(_ellipse(brim, Vector2(11.9, 2.7), -forward.x * 0.06, 32), hat.lightened(0.22), 0.45, true)
	var crown := brim + Vector2(-forward.x * 0.7, -4.4)
	_shape(PackedVector2Array([crown + Vector2(-6.7, 3.7), crown + Vector2(-6.0, -2.1), crown + Vector2(-3.8, -2.8),
		crown + Vector2(-0.5, -2.4), crown + Vector2(3.5, -3.0), crown + Vector2(6.0, -1.9),
		crown + Vector2(6.6, 3.6), crown + Vector2(3.0, 4.7), crown + Vector2(-3.4, 4.5)]), hat, 1.25)
	draw_colored_polygon(PackedVector2Array([crown + Vector2(3.5, -2.5), crown + Vector2(5.6, -1.7),
		crown + Vector2(6.0, 3.3), crown + Vector2(2.6, 4.1)]), hat.darkened(0.15))
	draw_polyline(PackedVector2Array([crown + Vector2(-5.7, 2.2), crown + Vector2(0, 3.1), crown + Vector2(5.8, 2.2)]), Color("654329"), 1.7, true)
	draw_line(crown + Vector2(-4.5, -1.5), crown + Vector2(-0.8, -1), hat.lightened(0.29), 0.7, true)

func _work_hand(side: int, action: String, chest: Vector2, wave: float, impact: float) -> Vector2:
	match action:
		"build":
			var b := BuildMotion.build_cycle(float(pose.get("phase", 0.0)))
			# Working height by the part being built: floor boards low, walls at the chest, roof overhead.
			var base: float = {"floor": -9.0, "roof": 13.0}.get(pose.get("build_kind", ""), 3.0)
			if side > 0:
				var height: float = base + 13.0 * b.raise - 5.0 * b.hit
				var reach: float = 8.0 + 9.0 * b.hit
				height = lerpf(height, base - 1.0, b.carry)
				reach = lerpf(reach, 17.0, b.carry)
				height = lerpf(height, -7.0, b.check)
				reach = lerpf(reach, 5.0, b.check)
				return chest + _joint(4, reach, height)
			var steady: float = base - 2.0 - 1.6 * b.hit
			steady = lerpf(steady, base - 1.0, b.carry)
			steady = lerpf(steady, -8.0, b.check)
			return chest + _joint(-4, lerpf(lerpf(12.5, 5.0, b.check), 6.0, b.carry), steady)
		"chop", "mine":
			return chest + _joint(side * 3, 5 + impact * 16, (12.0 if side > 0 else 5.0) - impact * 23)
		"saw":
			return chest + _joint(side * 6, 10.0 + wave * 5, -8)
		"eat":
			return chest + _joint(side * (4 if side > 0 else 8), 7, 1 + wave * 3 if side > 0 else -13)
		_:
			return chest + _joint(side * 6, 11, -15)

func _draw_tool(action: String, hand: Vector2, impact: float, raise: float = 0.0) -> void:
	if action == "saw":
		var tip := hand + _joint(0, 23, 0)
		var normal := hand.direction_to(tip).orthogonal()
		var blade := PackedVector2Array([hand - normal * 2.1, tip - normal * 1.5, tip + normal * 0.5])
		for i in range(7, 0, -1):
			var edge := hand.lerp(tip, i / 8.0)
			blade.append(edge + normal * 1.6)
			blade.append(edge + normal * 0.65 - hand.direction_to(tip))
		blade.append(hand + normal * 2.1)
		Props.polygon(self, blade, Color("c4c5b5"))
		_oval(hand, Vector2(2.3, 3.2), Color("82593b"), (tip - hand).angle(), 0.8)
		return
	var tip := hand + _joint(0, 3 + impact * 13, 15 - impact * 21)
	if action == "build":
		# Hammer: resting forward and down, cocked up and back for the wind-up, swung out on the blow.
		var resting := hand + _joint(0, 8, -9)
		var cocked := hand + _joint(0, -3, 15)
		var struck := hand + _joint(0, 13, -5)
		tip = resting.lerp(cocked, raise).lerp(struck, impact)
	var axis := hand.direction_to(tip)
	if axis.is_zero_approx(): axis = Vector2.UP
	var side := axis.orthogonal()
	_segment(hand, tip, 1.65, Color("966740"))
	draw_line(hand.lerp(tip, 0.20) - side * 0.45, tip - side * 0.45, Color("c09460"), 0.55, true)
	if action == "mine":
		# Pickaxe: a long double-pointed head across the top of the haft.
		for sign in [-1.0, 1.0]:
			Props.polygon(self, PackedVector2Array([tip - axis * 1.2 + side * sign * 1.0, tip + side * sign * 6.4 - axis * 3.0, tip + side * sign * 7.2 - axis * 1.6, tip + axis * 1.2 + side * sign * 1.0]), Color("9aa3a0"))
		draw_line(tip - side * 1.5, tip + side * 1.5, Color("5a625f"), 1.4, true)
	elif action == "chop":
		Props.polygon(self, PackedVector2Array([tip - side * 2.7 - axis * 1.5,
			tip + side * 2.9 - axis * 3.4, tip + side * 5.2 - axis * 2.9,
			tip + side * 5.2 + axis * 3.5, tip + side * 2.9 + axis * 3.8,
			tip - side * 2.7 + axis * 1.7]), Color("909c94"))
		draw_line(tip + side * 4.2 - axis * 2.5, tip + side * 4.2 + axis * 3.0, Color("d1d3bc"), 0.72, true)
	else:
		Props.polygon(self, PackedVector2Array([tip - side * 4 - axis * 1.6,
			tip + side * 4.4 - axis * 1.6, tip + side * 4.4 + axis * 1.8,
			tip - side * 4 + axis * 1.8]), Color("8b9691"))
		draw_line(tip - side * 3.4 + axis * 0.9, tip + side * 3.8 + axis * 0.9, Color("bfc7b7"), 0.6, true)

## Pump-action shotgun: walnut stock, blued barrel with a magazine tube beneath it,
## a sliding forend and a muzzle flash while the shot is leaving the barrel.
func _draw_rifle(stock: Vector2, muzzle: Vector2, pump: float = 0.0) -> void:
	var axis := (muzzle - stock).normalized()
	var normal := axis.orthogonal()
	var grip := stock.lerp(muzzle, 0.40)
	var receiver := stock.lerp(muzzle, 0.34)
	# Stock with a drop at the comb and a brass butt plate.
	_shape(PackedVector2Array([
		stock - normal * 2.6, receiver - normal * 1.4,
		receiver + normal * 1.9, stock + axis * 4 + normal * 3.8,
		stock + normal * 3.4,
	]), Color("8a5a30"), 1.1)
	draw_line(stock - normal * 2.8, stock + normal * 3.6, Color("c79a52"), 1.2, true)
	draw_line(stock + axis * 3 - normal * 1.4, receiver - axis * 2 - normal * 0.6, Color("b17c46"), 0.5, true)
	# Receiver, barrel and the shorter magazine tube beneath.
	_shape(PackedVector2Array([receiver - normal * 1.5, receiver + axis * 5 - normal * 1.5, receiver + axis * 5 + normal * 2.2, receiver + normal * 2.2]), Color("4f5558"), 1.0)
	_shape(PackedVector2Array([receiver + axis * 5 - normal * 0.9, muzzle - normal * 0.9, muzzle + normal * 0.9, receiver + axis * 5 + normal * 0.9]), Color("5f666a"), 0.95)
	draw_line(receiver + axis * 5 - normal * 0.4, muzzle - normal * 0.4, Color("a6adaa"), 0.5, true)
	var tube_end := stock.lerp(muzzle, 0.84)
	draw_line(receiver + axis * 6 + normal * 2.0, tube_end + normal * 2.0, INK, 2.0, true)
	draw_line(receiver + axis * 6 + normal * 2.0, tube_end + normal * 2.0, Color("737a7c"), 1.0, true)
	# Forend slides back along the tube when pumped.
	var fore_start := stock.lerp(muzzle, 0.52 - 0.14 * pump)
	var fore_end := stock.lerp(muzzle, 0.74 - 0.14 * pump)
	_shape(PackedVector2Array([fore_start + normal * 1.0, fore_end + normal * 1.0, fore_end + normal * 3.5, fore_start + normal * 3.5]), Color("9a6a3a"), 0.95)
	for groove in range(3):
		var g := fore_start.lerp(fore_end, 0.25 + groove * 0.25)
		draw_line(g + normal * 1.2, g + normal * 3.3, Color("5f3f23"), 0.5, true)
	# Trigger guard and loading port.
	draw_arc(grip + normal * 3.0, 2.0, 0.0, PI, 8, INK, 0.8, true)
	draw_line(receiver + axis * 2 + normal * 2.4, receiver + axis * 3.5 + normal * 3.6, Color("c9c0a0"), 0.6, true)
	Props.nail(self, receiver + axis * 3, 0.6)
	draw_line(muzzle - axis * 1.6 - normal, muzzle - axis * 1.6 - normal * 2.2, INK, 0.9, true)
	if pose.get("action", "") == "shoot" and float(pose.get("phase", 1.0)) < 0.2:
		# Blast: a hot core, an orange cone and drifting smoke.
		var burst := 1.0 - float(pose.get("phase", 0.0)) / 0.2
		var cone := PackedVector2Array([muzzle, muzzle + axis * (10 + 8 * burst) + normal * (5 + 3 * burst), muzzle + axis * (19 + 12 * burst), muzzle + axis * (10 + 8 * burst) - normal * (5 + 3 * burst)])
		draw_colored_polygon(cone, Color(1.0, 0.62, 0.18, 0.85 * burst))
		draw_colored_polygon(PackedVector2Array([muzzle, muzzle + axis * (6 + 5 * burst) + normal * 2.4, muzzle + axis * (12 + 7 * burst), muzzle + axis * (6 + 5 * burst) - normal * 2.4]), Color(1.0, 0.92, 0.55, burst))
		for puff in range(3):
			var drift := muzzle + axis * (12.0 + puff * 7.0) + Vector2(0, -3.0 - puff * 3.0)
			draw_circle(drift, 2.2 + puff * 1.6, Color(0.82, 0.82, 0.78, 0.28 * burst))

## Stowed shotgun: a gun slung over the character's right shoulder, barrel up past the shoulder
## and stock down by the opposite hip. Its on-screen length and thickness are fixed, so it looks the
## same size whichever way the character faces; only the anchor and draw order follow the facing.
const GUN_LENGTH_SCALE := 0.75
const SLUNG_LENGTH := 80.0 * GUN_LENGTH_SCALE
func _draw_slung(chest: Vector2, hip: Vector2, front: float) -> void:
	var shoulder := chest + _joint(9.0, -2.0, 7.0)             # the character's right shoulder, slightly behind
	var top := shoulder + Vector2(0.0, -22.0)                    # barrel clears the shoulder
	var hip_side := hip + _joint(-8.0, -3.0, -2.0)
	var axis := (top - hip_side).normalized()
	if axis.length() < 0.5: axis = Vector2.UP
	var bottom := top - axis * SLUNG_LENGTH
	var normal := axis.orthogonal()
	var shade: float = 0.0 if front < -0.08 else 0.12          # a little darker when it hangs behind the body
	var wood := Color("8a5a30").darkened(shade)
	var metal := Color("5f666a").darkened(shade)
	# Stock: wide at the butt, narrowing to the receiver.
	var receiver := bottom.lerp(top, 0.36)
	_shape(PackedVector2Array([bottom - normal * 5.51, receiver - normal * 2.90, receiver + normal * 3.77, bottom + normal * 6.67]), wood, 1.1)
	draw_line(bottom - normal * 5.65, bottom + normal * 6.82, Color("c79a52").darkened(shade), 1.6, true)
	# Receiver, long barrel and magazine tube, with the pump forend on the tube.
	_shape(PackedVector2Array([receiver - normal * 3.19, receiver.lerp(top, 0.14) - normal * 3.19, receiver.lerp(top, 0.14) + normal * 3.77, receiver + normal * 3.77]), Color("4f5558").darkened(shade), 1.0)
	draw_line(receiver.lerp(top, 0.1), top, metal, 4.8, true)
	draw_line(receiver.lerp(top, 0.1), top, Color("aab1ae").darkened(shade), 1.4, true)
	var tube_end := bottom.lerp(top, 0.84)
	draw_line(receiver.lerp(top, 0.12) + normal * 4.35, tube_end + normal * 4.35, metal.darkened(0.15), 3.2, true)
	_shape(PackedVector2Array([bottom.lerp(top, 0.52) + normal * 2.17, bottom.lerp(top, 0.74) + normal * 2.17, bottom.lerp(top, 0.74) + normal * 7.25, bottom.lerp(top, 0.52) + normal * 7.25]), Color("9a6a3a").darkened(shade), 1.0)
	# Sling strap from the muzzle end over the shoulder and across the chest.
	draw_line(bottom.lerp(top, 0.34), chest + Vector2(-3.0, 4.0), Color("5b4330"), 1.2, true)
	draw_line(top.lerp(bottom, 0.12), chest + Vector2(5.0, -1.0), Color("5b4330"), 1.2, true)

func _draw_cargo(item: String, quantity: int, center: Vector2) -> void:
	if item not in ["log", "plank"]:
		Props.supply(self, center + Vector2(0, 3), item, 0.83)
		return
	var span := _joint(12, 4.5, 0)
	if across.y < 0: span = -span
	for index in range(mini(3, quantity)):
		var strip := center - Vector2(0, index * 3.35)
		if item == "log": Props.log_piece(self, strip - span, strip + span, 2.8)
		else: Props.plank(self, strip - span, strip + span, 2.3)
