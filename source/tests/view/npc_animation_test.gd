extends SceneTree
## NPCs animated as fully as the player: a bandit or sheriff firing points the gun exactly at you
## (not one of eight directions) and kicks with the recoil; reloading plays your reload motion; a
## sheriff's tackle plays as a shove; moving up between covers they go low.
const Sim = preload("res://sim/core/simulation.gd")
const Director = preload("res://view/actors/animation_director.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(director, s: Dictionary, count: int) -> void:
	for i in range(count):
		if i % 6 == 0: s.tick += 1
		director.update(s, 1.0 / 60.0, false, 1)

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	var bandit: Dictionary = s.residents[str(s.bandits.members[0])]
	var at: Array = s.entities[str(bandit.id)].cell
	s.entities[str(s.player)].cell = [at[0] + 7, at[1] + 3]   # an angle that isn't one of the eight
	bandit.gun_out = true
	bandit.aim_at = int(s.player)
	bandit.cover_cycle = {"phase": "fire", "since": s.tick, "ammo": 3}
	var director = Director.new()
	frames(director, s, 20)
	var pose: Dictionary = director.actors[str(bandit.id)]
	var exact: float = Vector2(7, 3).angle()
	check(str(pose.action) == "shoot", "A bandit firing shoots (%s)" % str(pose.action))
	check(bool(pose.aiming), "...aiming like you do")
	check(absf(angle_difference(float(pose.heading), exact)) < deg_to_rad(2.0), "...right at you (%.1f° off)" % rad_to_deg(absf(angle_difference(float(pose.heading), exact))))
	check(int(pose.bloom) > 0, "...with recoil")
	# Reloading: your reload motion, moving.
	bandit.cover_cycle = {"phase": "hide", "since": s.tick, "ammo": 0}
	frames(director, s, 12)
	var phase_a: float = float(director.actors[str(bandit.id)].phase)
	frames(director, s, 18)
	check(str(director.actors[str(bandit.id)].action) == "reload", "Out of rounds, he reloads")
	check(absf(float(director.actors[str(bandit.id)].phase) - phase_a) > 0.05, "...and the reload moves")
	# Moving up between covers, low.
	bandit.cover_cycle = {"phase": "advance", "since": s.tick, "ammo": 3, "target": [at[0] + 2, at[1]]}
	for i in range(8):
		s.entities[str(bandit.id)].cell = [at[0] + (1 if i % 2 == 0 else 0), at[1]]
		frames(director, s, 18)
	check(float(director.actors[str(bandit.id)].sneak) > 0.5, "Moving up between covers he goes low (%.2f)" % float(director.actors[str(bandit.id)].sneak))
	# A sheriff's tackle plays as a shove.
	var sheriff: Dictionary = load("res://sim/law/law.gd").sheriffs(s, 1)[0]
	sheriff.tackle = {"start": s.tick, "end": s.tick + 10}
	check(str(Director.action_for(s, s.entities[str(sheriff.id)]).action) == "shove", "A sheriff's tackle is a shove")
	print("NPC animation: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
