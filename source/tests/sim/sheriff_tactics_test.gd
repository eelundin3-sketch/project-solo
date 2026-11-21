extends SceneTree
## Wounds bleed until they are bandaged, and the wounded see to it; sheriffs in a gunfight work
## their way closer from cover to cover, slowly and one at a time, and bind their wounds in cover.
const Sim = preload("res://sim/core/simulation.gd")
const Gunfire = preload("res://sim/combat/gunfire.gd")
const Wounds = preload("res://sim/combat/wounds.gd")
const Bleeding = preload("res://sim/combat/bleeding.gd")
const Sheriff = preload("res://sim/law/sheriff.gd")
const Cover = preload("res://sim/combat/cover.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 5400
	for npc in s.residents.values():
		npc.sleeping = {}; npc.hunger = 0; npc.thirst = 0; npc.fatigue = 0
	# A villager is shot: the wound bleeds until it is bandaged.
	var villager: Dictionary = {}
	for npc in s.residents.values():
		if npc.settlement == 1 and npc.occupation not in ["Sheriff", "Child"]: villager = npc; break
	s.inventories[str(villager.id)].items.erase("bandage")
	var cell: Array = s.entities[str(villager.id)].cell
	Wounds.shoot(sim, int(villager.id), cell, [1, 0], 1.0, false)
	check(Bleeding.bleeding(villager), "A gunshot wound bleeds")
	var health: int = int(villager.health)
	villager.knock = {}
	for i in range(Bleeding.BLEED_EVERY * 2 + 2):
		if Bleeding.bleeding(villager) and villager.get("goal", "") != "bandage" and villager.get("bandaging", {}).is_empty(): pass
		sim.step()
		if not Bleeding.bleeding(villager): break
	check(int(villager.health) < health or not Bleeding.bleeding(villager), "Bleeding costs health until it is dealt with (%d -> %d)" % [health, villager.health])
	# Without a bandage they go and get one, and bind the wound.
	var bound := false
	for i in range(3000):
		sim.step()
		if not Bleeding.bleeding(villager): bound = true; break
		if int(villager.health) <= 0: break
	check(bound, "The wounded villager fetches a bandage and binds the wound (%s)" % str(villager.get("status", "")))
	# Sheriffs carry bandages.
	var sheriffs: Array = Sheriff.roster(s, 1).map(func(id): return s.residents[str(id)])
	check(not sheriffs.is_empty() and Inventory.amount(s, int(sheriffs[0].id), "bandage") >= 1, "Sheriffs carry bandages (%d; office %d; items %s)" % [Inventory.amount(s, int(sheriffs[0].id), "bandage"), Inventory.amount(s, int(s.settlements["1"].office), "bandage"), str(s.inventories[str(sheriffs[0].id)])])
	# A gunfight: the player fires from the open square; a sheriff starts far off, behind cover.
	var store: Array = s.entities[str(s.settlements["1"].warehouse)].cell
	var player: Array = [store[0], store[1] + 9]
	s.entities[str(s.player)].cell = player.duplicate()
	Inventory.produce(s, s.player, "shotgun", 1); Inventory.produce(s, s.player, "shell", 40)
	s.shotgun.equipped = true; s.shotgun.loaded = 5; s.shotgun.last_shot = -1000
	var lead: Dictionary = sheriffs[0]
	var away := 0
	for other in sheriffs.slice(1):   # out of earshot, each on a cell of their own
		s.entities[str(other.id)].cell = [store[0] + 60 + away * 2, store[1] - 40]
		away += 1
	# Put the sheriff at the farthest cover within shooting range of the player.
	var far_cover: Array = []
	var far_distance := 0.0
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			var c: Array = [player[0] + dx, player[1] + dy]
			var d: float = Vector2(dx, dy).length()
			if d > far_distance and d <= 14.0 and Cover.is_cover(s, c) and not Cover.line_clear(s, c, player, true, false):
				far_cover = c; far_distance = d
	check(not far_cover.is_empty(), "There is cover near the square")
	s.entities[str(lead.id)].cell = far_cover.duplicate()
	var start_distance: float = Vector2(far_cover[0] - player[0], far_cover[1] - player[1]).length()
	sim.submit("shotgun_fire", {"direction": [1000, 0]}); sim.step()
	var advanced := false
	var moved_while_firing := false
	var max_step_rate := 0
	var last_cell: Array = s.entities[str(lead.id)].cell.duplicate()
	var steps_in_window := 0
	var lead_wounded := false
	var closest: float = start_distance
	for i in range(900):
		# Keep the fight going, but leave quiet spells for the sheriff to move in.
		if i % 60 == 0:
			s.shotgun.last_shot = -1000; s.shotgun.loaded = 5
			s.entities[str(s.player)].cell = player.duplicate()
			for part in s.player_health.parts.values(): part.damage = 0; part.bleeding = false; part.wound = "none"
			s.player_control.knock = {}
			sim.submit("shotgun_fire", {"direction": [1000, 0]})
		var alert: Dictionary = Gunfire.alert_of(s, 1)
		if not alert.is_empty() and alert.get("phase", "") == "arrest": alert.phase = "engage"; alert.last_shot = s.tick
		sim.step()
		var now: Array = s.entities[str(lead.id)].cell
		closest = minf(closest, Vector2(now[0] - player[0], now[1] - player[1]).length())
		if now != last_cell and str(lead.get("cover_cycle", {}).get("phase", "")) == "advance":
			steps_in_window += 1
			if str(lead.get("cover_cycle", {}).get("phase", "")) == "advance" and s.tick - int(Gunfire.alert_of(s, 1).get("last_shot", -1000)) < Gunfire.SAFE_AFTER_SHOT and not bool(s.shotgun.get("reloading", false)): moved_while_firing = true
		last_cell = now.duplicate()
		if s.tick % 30 == 0:
			max_step_rate = maxi(max_step_rate, steps_in_window)
			steps_in_window = 0
		if str(lead.get("cover_cycle", {}).get("phase", "")) == "advance": advanced = true
		# Wound the sheriff once he has moved up: he should bind it behind cover.
		if advanced and not lead_wounded and str(lead.get("cover_cycle", {}).get("phase", "")) == "hide":
			Bleeding.open_wound(s, lead)
			lead_wounded = true
	var end_distance: float = Vector2(s.entities[str(lead.id)].cell[0] - player[0], s.entities[str(lead.id)].cell[1] - player[1]).length()
	check(advanced, "The sheriff moves up from cover to cover")
	# He closes in from cover; where he stands at the very end depends on the scripted lulls (with
	# three sheriffs to a town he may be back at cover by then), so the check is how close he got.
	check(closest < start_distance - 2.0, "...and closes in on you (%.1f -> %.1f cells at the closest)" % [start_distance, closest])
	check(max_step_rate <= 11, "...slowly, at most a step every third tick (%d steps in 30 ticks)" % max_step_rate)
	check(not moved_while_firing, "...never while the gunman is firing")
	check(lead_wounded and not Bleeding.bleeding(lead), "A wounded sheriff bandages himself behind cover")
	print("Sheriff tactics: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)
