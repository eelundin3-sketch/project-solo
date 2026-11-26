extends SceneTree
## Down in a gunfight, they take you alive. Once you're knocked down (even after it came to shooting
## to kill), the nearest sheriff sprints in and the others run to your sides, guns on you; you're
## cuffed, not finished off. Firing again calls the rush off. Bandits do the same: one rushes in and
## shoves you back down if you're getting up, the others cover you, and you end up tied at the post.
const Sim = preload("res://sim/core/simulation.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Law = preload("res://sim/law/law.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func fire(sim, s: Dictionary) -> void:
	s.shotgun.last_shot = -1000; s.shotgun.loaded = maxi(2, int(s.shotgun.loaded))
	sim.submit("shotgun_fire", {"direction": [1000, 0]}); sim.step()

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 5400
	for npc in s.residents.values():
		npc.sleeping = {}; npc.goal = ""; npc.path = []
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	s.entities[str(s.player)].cell = [store[0], store[1] + 9]
	Inventory.produce(s, s.player, "shotgun", 1); Inventory.produce(s, s.player, "shell", 20)
	s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	for npc in Sheriff.roster(s, 1).map(func(id): return s.residents[str(id)]):
		s.entities[str(npc.id)].cell = [store[0] - 8 + int(npc.id) % 3 * 6, store[1] + 2]
	fire(sim, s)
	var alert: Dictionary = Gunfire.alert_of(s, 1)
	alert.phase = "lethal"; alert.lethal = true
	for i in range(10): sim.step()
	# Brought down.
	var me: Array = s.entities[str(s.player)].cell
	Brawl.knockdown(s, s.player_control, me, "fall", [1, 0])
	var rusher: Dictionary = {}
	var start := {}
	for id in Sheriff.roster(s, 1): start[id] = s.entities[str(id)].cell.duplicate()
	var flank_seen := false
	var fastest := 0
	var taken := false
	for i in range(300):
		if not Law.restrained(s) and not Brawl.player_down(s): Brawl.knockdown(s, s.player_control, s.entities[str(s.player)].cell, "fall", [1, 0])   # stays down for this part
		sim.step()
		for id in Sheriff.roster(s, 1):
			var npc: Dictionary = s.residents[str(id)]
			if bool(npc.get("arrest", {}).get("rush", false)): rusher = npc
			if not npc.get("arrest", {}).get("flank_spot", []).is_empty(): flank_seen = true
		if not rusher.is_empty() and i == 6:
			var a: Array = start[int(rusher.id)]
			var b: Array = s.entities[str(rusher.id)].cell
			fastest = maxi(absi(a[0] - b[0]), absi(a[1] - b[1]))
		if Law.restrained(s) or str(rusher.get("arrest", {}).get("phase", "")) in ["cuff", "lift", "escort"]: taken = true; break
	check(not rusher.is_empty(), "Down, even in a deadly fight: a sheriff rushes in")
	check(fastest >= 4, "...flat out (%d cells in the first moments)" % fastest)
	check(flank_seen, "The others run to your sides")
	check(taken, "You're taken alive")
	check(not bool(s.player_control.get("dead", false)), "...not finished off")

	# Firing again calls the rush off.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 5400
	var store2: Array = s2.entities[str(s2.settlements["1"].warehouse)].cell
	s2.entities[str(s2.player)].cell = [store2[0], store2[1] + 9]
	Inventory.produce(s2, s2.player, "shotgun", 1); Inventory.produce(s2, s2.player, "shell", 20)
	s2.shotgun.equipped = true; s2.shotgun.loaded = 5; s2.shotgun.last_shot = -1000
	fire(sim2, s2)
	var alert2: Dictionary = Gunfire.alert_of(s2, 1)
	alert2.phase = "arrest"; alert2.rush = true
	fire(sim2, s2)
	check(not bool(Gunfire.alert_of(s2, 1).get("rush", false)) and str(Gunfire.alert_of(s2, 1).phase) == "lethal", "Shooting as they rush in calls it off")

	# Bandits: rushed, shoved back down, covered, tied at the post.
	var sim3 := Sim.new(); sim3.start_game(); var s3: Dictionary = sim3.state
	s3.tick = 14400 + 11 * 600
	var camp: Array = s3.bandits.cell
	for dx in range(10, 16):
		var c: Array = [camp[0] + dx, camp[1] + 4]
		if World.walkable(s3, c): s3.entities[str(s3.player)].cell = c; break
	s3.shotgun.equipped = true; s3.shotgun.loaded = 5; s3.shotgun.last_shot = -1000
	sim3.submit("shotgun_fire", {"direction": [0, 1000]})
	for i in range(30): sim3.step()
	Brawl.knockdown(s3, s3.player_control, s3.entities[str(s3.player)].cell, "fall", [1, 0])
	var covered := false
	var running := false
	var tied := false
	for i in range(1500):
		sim3.step()
		for id in s3.bandits.members:
			var npc: Dictionary = s3.residents[str(id)]
			if npc.has("cover_spot") and bool(npc.get("gun_out", false)): covered = true
			if npc.has("captor") and int(npc.get("running_tick", -100)) >= s3.tick - 1: running = true
		if str(s3.player_control.get("captive", {}).get("stage", "")) == "tied": tied = true; break
	check(running, "A bandit rushes in to take you")
	check(covered, "...the others cover you, guns out")
	check(tied, "...and you end up tied at the post")
	print("Capture rush: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
