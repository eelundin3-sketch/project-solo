extends SceneTree
## Sheriffs who end the fight: from out of range they close in; against a gunman behind cover one
## works round the side; a gunman who stops firing but keeps the gun out is moved in on and taken;
## careful (not lethal) shots go for the legs or the gun arm; nobody stands frozen in a fight.
const Sim = preload("res://sim/core/simulation.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Law = preload("res://sim/law/law.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Wounds = preload("res://sim/combat/wounds.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

## A town-1 fight: the player on the square with a loaded shotgun, one sheriff `away` cells off
## (the others sent far out of earshot). Returns [sim, s, sheriff, player cell].
func setup(away: int) -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 5400
	for npc in s.residents.values():
		npc.sleeping = {}; npc.hunger = 0; npc.thirst = 0; npc.fatigue = 0
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var player: Array = [store[0], store[1] + 9]
	s.entities[str(s.player)].cell = player.duplicate()
	Inventory.produce(s, s.player, "shotgun", 1); Inventory.produce(s, s.player, "shell", 60)
	s.shotgun.kind = "shotgun"; s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	var sheriffs: Array = Law.sheriffs(s, 1)
	var lead: Dictionary = sheriffs[0]
	var spot: Array = []
	for dx in range(away, away + 8):
		for dy in [0, 1, -1, 2, -2]:
			var c: Array = [player[0] + dx, player[1] + dy]
			if spot.is_empty() and World.walkable(s, c): spot = c
	s.entities[str(lead.id)].cell = spot
	var n := 0
	for other in sheriffs.slice(1):
		s.entities[str(other.id)].cell = [store[0] + 70 + n * 2, store[1] - 45]; n += 1
	return [sim, s, lead, player]

func gap(s: Dictionary, id: int, player: Array) -> float:
	var c: Array = s.entities[str(id)].cell
	return Vector2(c[0] - player[0], c[1] - player[1]).length()

## Keeps the fight going: the player fires into the sky (away from the sheriff) now and then, and
## heals, so the fight does not end with the player shot down.
func keep_firing(sim: RefCounted, s: Dictionary, player: Array, i: int, every: int) -> void:
	if i % every == 0:
		s.shotgun.last_shot = -1000; s.shotgun.loaded = 5
		s.entities[str(s.player)].cell = player.duplicate()
		for part in s.player_health.parts.values(): part.damage = 0; part.bleeding = false; part.wound = "none"
		s.player_control.knock = {}
		sim.submit("shotgun_fire", {"direction": [-1000, 0]})

func _initialize() -> void:
	# 1. Out of range: he closes in instead of peeking and missing from afar.
	var a: Array = setup(20)
	var sim: RefCounted = a[0]; var s: Dictionary = a[1]; var lead: Dictionary = a[2]; var player: Array = a[3]
	var start: float = gap(s, int(lead.id), player)
	var closest: float = start
	var frozen := 0
	var longest_frozen := 0
	var last_cell: Array = s.entities[str(lead.id)].cell.duplicate()
	var last_phase := ""
	for i in range(900):
		keep_firing(sim, s, player, i, 90)
		var alert: Dictionary = Gunfire.alert_of(s, 1)
		if not alert.is_empty() and str(alert.phase) in ["arrest", "hold"]: alert.phase = "engage"; alert.last_shot = s.tick
		sim.step()
		closest = minf(closest, gap(s, int(lead.id), player))
		var cell: Array = s.entities[str(lead.id)].cell
		var phase: String = str(lead.get("cover_cycle", {}).get("phase", ""))
		if cell == last_cell and phase == last_phase and str(lead.get("arrest", {}).get("phase", "")) == "engage": frozen += 1
		else: frozen = 0
		longest_frozen = maxi(longest_frozen, frozen)
		last_cell = cell.duplicate(); last_phase = phase
	check(start > Gunfire.SHOOT_RANGE, "He starts out of range (%.1f cells)" % start)
	check(closest <= Gunfire.SHOOT_RANGE, "He closes to shotgun range (%.1f -> %.1f cells)" % [start, closest])
	check(longest_frozen <= 120, "He never stands frozen in the fight (longest still %d ticks)" % longest_frozen)

	# 2. A gunman crouched behind cover: someone works round the side.
	var b: Array = setup(9)
	var sim2: RefCounted = b[0]; var s2: Dictionary = b[1]; var lead2: Dictionary = b[2]; var player2: Array = b[3]
	var cover_cell: Array = []
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c: Array = [player2[0] + dx, player2[1] + dy]
			if cover_cell.is_empty() and Cover.is_cover(s2, c) and World.walkable(s2, c): cover_cell = c
	check(not cover_cell.is_empty(), "There is cover near the square")
	if not cover_cell.is_empty():
		player2 = cover_cell
		s2.entities[str(s2.player)].cell = cover_cell.duplicate()
		s2.player_control.crouching = true
		var flanked := false
		for i in range(900):
			keep_firing(sim2, s2, player2, i, 120)
			s2.player_control.crouching = true
			var alert2: Dictionary = Gunfire.alert_of(s2, 1)
			if not alert2.is_empty() and str(alert2.phase) in ["arrest", "hold"]: alert2.phase = "engage"; alert2.last_shot = s2.tick
			sim2.step()
			if not Cover.player_exposed(s2) and int(Gunfire.alert_of(s2, 1).get("flanker", 0)) != 0: flanked = true
			if flanked: break
		check(flanked, "Against a gunman behind cover, a sheriff works round the side")

	# 3. Stops firing but keeps the gun out: they don't wait for ever, they move in.
	var c3: Array = setup(8)
	var sim3: RefCounted = c3[0]; var s3: Dictionary = c3[1]
	sim3.submit("shotgun_fire", {"direction": [-1000, 0]}); sim3.step()
	var arrested := -1
	for i in range(Gunfire.STOP_TICKS + Gunfire.HOLD_TICKS + 200):
		sim3.step()
		var alert3: Dictionary = Gunfire.alert_of(s3, 1)
		if str(alert3.get("phase", "")) == "arrest" or Law.in_custody(s3) or Law.restrained(s3): arrested = i; break
	check(arrested >= 0, "A gunman who just holds the gun is moved in on and arrested")

	# 4. Careful shots go for the legs (or the gun arm); lethal ones do not.
	var legs := 0
	for i in range(200):
		if str(Wounds.pick(sim3, "legs").area) == "leg": legs += 1
	check(legs >= 140, "Aimed at the legs, most shots hit a leg (%d of 200)" % legs)
	var arm := 0
	for i in range(200):
		if str(Wounds.pick(sim3, "gun_arm").get("limb", "")) == "right_arm": arm += 1
	check(arm >= 140, "Aimed at the gun arm, most shots hit it (%d of 200)" % arm)

	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	print("Gunfire tactics: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
