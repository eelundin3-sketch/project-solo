extends SceneTree
## New poses and the arrest from the ground: people in chairs sit, a captive of the bandits sits
## roped on the ground, a backpedalling walker's knees bend the way the body faces with a shorter
## stride, and a prisoner taken on the ground is held down, then hauled up, before the walk.
const Sim = preload("res://sim/core/simulation.gd")
const Director = preload("res://view/actors/animation_director.gd")
const DrawnCharacter = preload("res://view/actors/drawn_character.gd")
const Law = preload("res://sim/law/law.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	# Sitting and tied.
	var npc: Dictionary = s.residents.values()[0]
	npc.sitting = {"chair": s.entities[str(npc.id)].cell.duplicate(), "approach": s.entities[str(npc.id)].cell.duplicate(), "face": [1, 0], "since": s.tick}
	check(str(Director.action_for(s, s.entities[str(npc.id)]).action) == "sit", "Someone in a chair sits")
	npc.erase("sitting")
	s.player_control.captive = {"since": s.tick}
	check(str(Director.action_for(s, s.entities[str(s.player)]).action) == "tied", "A captive of the bandits is drawn tied up")
	s.player_control.captive = {}

	# Guns on you: a sheriff walking up aims, and so does a bandit holding you up.
	var lawman: Dictionary = Law.sheriffs(s, 1)[0]
	lawman.arrest = {"phase": "approach", "since": s.tick}
	var lawman_action: Dictionary = Director.action_for(s, s.entities[str(lawman.id)])
	check(str(lawman_action.action) == "aim" and int(lawman_action.target) == int(s.player), "A sheriff walking up to you points his gun at you")
	lawman.erase("arrest")
	var bandit: Dictionary = s.residents[str(s.bandits.members[1])]
	load("res://sim/factions/bandits.gd")._wake_all(s, [bandit])
	var bandit_action: Dictionary = Director.action_for(s, s.entities[str(bandit.id)])
	check(str(bandit_action.action) == "aim" and int(bandit_action.target) == int(s.player), "A bandit holding you up aims at you")
	bandit.cover_cycle = {"phase": "fire", "since": s.tick, "ammo": 3}
	check(str(Director.action_for(s, s.entities[str(bandit.id)]).action) == "shoot", "A fighting bandit shoots from cover with the gun in his hands")
	bandit.erase("cover_cycle")
	bandit.erase("gun_out")
	var Outfits = load("res://sim/entities/outfits.gd")
	check(str(Outfits.worn(s, int(bandit.id)).get("mask", "")) != "" and str(Outfits.worn(s, int(bandit.id)).vest) in Outfits.LONG_COATS, "Bandits wear a bandana and a duster")

	# Backpedalling: knees bend the way the body faces, and the steps are shorter.
	var body := DrawnCharacter.new()
	body.forward = Vector2.RIGHT
	body.across = Vector2(0, -1)
	body.pose = {"move_direction": Vector2.LEFT, "sneak": 0.0}
	var back_knees := 0.0
	var back_stride := 0.0
	var ahead_stride := 0.0
	for i in range(16):
		var gait: float = TAU * float(i) / 16.0
		var leg: PackedVector2Array = body._walk_leg(1, Vector2(0, -DrawnCharacter.HIP_HEIGHT), gait, true)
		back_knees += leg[1].x - (leg[0].x + leg[2].x) / 2.0
		back_stride = maxf(back_stride, absf(leg[2].x))
	body.pose = {"move_direction": Vector2.RIGHT, "sneak": 0.0}
	for i in range(16):
		var leg2: PackedVector2Array = body._walk_leg(1, Vector2(0, -DrawnCharacter.HIP_HEIGHT), TAU * float(i) / 16.0, true)
		ahead_stride = maxf(ahead_stride, absf(leg2[2].x))
	check(back_knees > 0.0, "Walking backwards, the knees bend forward of the legs (the way the body faces)")
	check(back_stride < ahead_stride, "Walking backwards, the steps are shorter (%.1f vs %.1f)" % [back_stride, ahead_stride])
	body.free()

	# The arrest from the ground: held down, then hauled up, then walked.
	s.tick = 14400 + 5400
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	var at: Array = s.entities[str(sheriff.id)].cell
	var spot: Array = [at[0] + 1, at[1]]
	if not load("res://sim/world/world_db.gd").walkable(s, spot): spot = [at[0], at[1] + 1]
	s.entities[str(s.player)].cell = spot
	load("res://sim/law/law.gd").file(s, 1, "theft", {}, true)
	Brawl.knockdown(s, s.player_control, spot, "fall", [1, 0])
	sheriff.arrest = {"phase": "pursue", "since": s.tick, "path_tick": -100}
	var seen := []
	var down_while_pinned := true
	var standing_at_escort := false
	for i in range(400):
		sim.step()
		var phase: String = str(sheriff.get("arrest", {}).get("phase", ""))
		if phase != "" and (seen.is_empty() or seen[-1] != phase): seen.append(phase)
		if phase == "cuff" and bool(sheriff.arrest.get("pinned", false)) and not Brawl.player_down(s): down_while_pinned = false
		if phase == "escort": standing_at_escort = not Brawl.player_down(s); break
	check("cuff" in seen and "lift" in seen and "escort" in seen, "Taken on the ground: cuffed, lifted, then walked (%s)" % str(seen))
	check(seen.find("lift") < seen.find("escort"), "Hauled up before the walk")
	check(down_while_pinned, "Held down on the ground while the cuffs go on")
	check(standing_at_escort, "On their feet when the walk starts")
	print("Poses: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
