extends SceneTree
## The lifts are drawn as real motions: at the bottom of a squat the hips are low and the bar is on
## the shoulders; at the bottom of a bench rep the bar is on the chest, at the top the arms are long;
## a deadlift starts with the bar at the floor and ends at the thighs; at the top of a pull-up the head
## is up at the bar; the fridge puts a bottle in your hand. The bar is drawn in your hands only while
## it's off the rack.
const DrawnCharacter = preload("res://view/actors/drawn_character.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var body := DrawnCharacter.new()
	body.forward = Vector2.DOWN
	body.across = Vector2(1, 0)
	var top: Dictionary = body._home_pose("squat", "rep", 0.0, true)
	var bottom: Dictionary = body._home_pose("squat", "rep", 0.5, true)
	check(bottom.hip.y > top.hip.y + 6.0, "Squat: the hips go down (%.1f -> %.1f)" % [top.hip.y, bottom.hip.y])
	check(bottom.barbell.size() == 2 and absf(bottom.barbell[0].y - bottom.chest.y) < 6.0, "Squat: the bar rides on the shoulders")
	check(body._home_pose("squat", "setup", 0.2, false).barbell.is_empty(), "Squat: no bar in hand before it's unracked")
	var press_top: Dictionary = body._home_pose("bench", "rep", 0.0, true)
	var press_low: Dictionary = body._home_pose("bench", "rep", 0.5, true)
	var top_y: float = press_top.barbell[0].lerp(press_top.barbell[1], 0.5).y
	var low_y: float = press_low.barbell[0].lerp(press_low.barbell[1], 0.5).y
	# Lying on the back, the bar's height is drawn up the screen: lowered to the chest it sits lower.
	check(low_y > top_y + 4.0, "Bench: the bar comes down to the chest and is pressed away (%.1f vs %.1f)" % [low_y, top_y])
	var floor_pull: Dictionary = body._home_pose("deadlift", "rep", 0.0, true)
	var lockout: Dictionary = body._home_pose("deadlift", "rep", 0.5, true)
	check(floor_pull.barbell[0].y > lockout.barbell[0].y + 8.0, "Deadlift: from the floor up to the thighs (%.1f -> %.1f)" % [floor_pull.barbell[0].y, lockout.barbell[0].y])
	check(floor_pull.chest.y > lockout.chest.y + 6.0, "Deadlift: bent over at the floor, upright at the top")
	var hang: Dictionary = body._home_pose("pullup", "rep", 0.0, false)
	var chin_up: Dictionary = body._home_pose("pullup", "rep", 0.45, false)
	check(chin_up.head.y < hang.head.y - 4.0, "Pull-up: the head rises to the bar")
	check(body._home_pose("fridge", "drink", 0.5, false).bottle != Vector2.INF, "Fridge: a bottle in hand to drink")
	body.free()
	print("Home poses: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
