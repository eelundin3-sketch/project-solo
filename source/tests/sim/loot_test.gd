extends SceneTree
const Sim = preload("res://sim/core/simulation.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Invariants = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	# Every town starts with five villagers.
	for town in s.settlements.values():
		var count := 0
		for npc in s.residents.values():
			if npc.settlement == town.id and not npc.get("garrison", false) and npc.occupation not in ["Governor", "Barkeep"]: count += 1   # not the extra office sheriffs, nor the capital's governor and barkeep
		check(count == 5, "%s starts with 5 villagers: %d" % [town.name, count])
	# Chests are real entities with contents.
	var chest: Dictionary = {}
	for e in s.entities.values():
		if e.kind == "chest" and e.settlement == 1 and Inventory.used(s.inventories[str(e.id)]) > 0: chest = e; break
	check(not chest.is_empty(), "Houses have chests with things in them")
	var player: Dictionary = s.entities[str(s.player)]
	var rect: Array = chest.rock_rect
	player.cell = [rect[0] - 1, rect[1]]
	player.cell = player.cell if sim.state.world.blocked.has("%d,%d" % [player.cell[0], player.cell[1]]) == false else player.cell
	sim.submit("context_action", {"target": chest.id, "action": "loot"}); sim.step()
	check(s.player_control.ui_kind == "loot" and s.player_control.ui_target == chest.id, "Opening a chest opens the loot window")
	var contents_before: Dictionary = s.inventories[str(chest.id)].items.duplicate()
	var item: String = contents_before.keys()[0]
	var held_before: int = Inventory.amount(s, s.player, item)
	sim.submit("loot_take", {"target": chest.id, "item": item}); sim.step()
	check(Inventory.amount(s, s.player, item) == held_before + int(contents_before[item]), "Taking from a chest moves it to the player")
	sim.submit("loot_all", {"target": chest.id}); sim.step()
	check(Inventory.used(s.inventories[str(chest.id)]) == 0, "Take everything empties the chest")
	check(Invariants.validate(s).is_empty(), "Invariants hold after chest looting: " + str(Invariants.validate(s)))
	# A conscious villager cannot be searched; a knocked-out one can, clothes and all.
	var victim: Dictionary = s.residents.values()[0]
	var vcell: Array = s.entities[str(victim.id)].cell
	player.cell = [vcell[0] + 1, vcell[1]]
	sim.submit("context_action", {"target": victim.id, "action": "loot"}); sim.step()
	check(s.player_control.notice.contains("not stand"), "A conscious person refuses to be searched")
	vcell = s.entities[str(victim.id)].cell.duplicate()
	player.cell = [vcell[0] + 1, vcell[1]]
	Brawl.knockdown(s, victim, vcell, "ko", [1000, 0])
	var worn_before: Dictionary = Outfits.worn(s, victim.id)
	var coins_before: int = int(s.accounts.get(str(victim.id), 0))
	var my_coins: int = int(s.accounts[str(s.player)])
	sim.submit("loot_strip", {"target": victim.id, "slot": "hat", "wear": false})
	sim.submit("loot_strip", {"target": victim.id, "slot": "vest", "wear": true}); sim.step(); sim.step()
	var hat: String = str(worn_before.hat)
	if not hat.is_empty(): check(Outfits.worn(s, victim.id).hat == "" and Inventory.amount(s, s.player, hat) >= 1, "Stripping their hat puts it in your pack")
	check(Outfits.worn(s, victim.id).vest == "" and Outfits.worn(s, s.player).vest == worn_before.vest, "Taking and wearing their vest dresses you in it")
	sim.submit("loot_coins", {"target": victim.id}); sim.step()
	check(int(s.accounts[str(s.player)]) == my_coins + coins_before, "Their coins come with it")
	check(victim.get("grudge", false), "A robbed person holds a grudge")
	check(Invariants.validate(s).is_empty(), "Invariants hold after stripping: " + str(Invariants.validate(s)))
	# Wearing and taking off your own clothes.
	sim.submit("take_off", {"slot": "shirt"}); sim.step()
	check(Outfits.worn(s, s.player).shirt == "" and Inventory.amount(s, s.player, Outfits.key("shirt", 0)) == 1, "You can take your shirt off")
	sim.submit("wear_item", {"item": Outfits.key("shirt", 0)}); sim.step()
	check(Outfits.worn(s, s.player).shirt == Outfits.key("shirt", 0), "...and put it back on")
	check(Invariants.validate(s).is_empty(), "Invariants hold after dressing: " + str(Invariants.validate(s)))
	# Waking up, the robbed villager goes after the thief.
	var woke := false
	for t in range(Brawl.FALL_TICKS + Brawl.KO_TICKS + Brawl.RISE_TICKS + 40):
		sim.step()
		if not victim.get("brawl", {}).is_empty(): woke = true; break
	check(woke, "The robbed villager comes after the thief when they wake")
	# The sheriff may have caught the thief: let that go so walking can be tested on its own.
	for npc in s.residents.values(): npc.arrest = {}
	s.law = {"wanted": {}}
	s.player_control.restrained = false
	s.player_control.escort = 0
	s.player_control.knock = {}
	player.cell = [60, 60]
	# Double right-click walking: a route is found to a distant square.
	player.cell = [60, 60]
	sim.submit("walk_to", {"cell": [70, 64]}); sim.step()
	check(not s.player_path.is_empty(), "walk_to finds a route")
	for t in range(80): sim.step()
	check(absi(player.cell[0] - 70) + absi(player.cell[1] - 64) <= 1 and s.player_path.is_empty(), "The player walks to the chosen square (or the nearest free one): %s" % str(player.cell))
	if failures == 0: print("Loot, chests and walking: PASS")
	quit(failures)
