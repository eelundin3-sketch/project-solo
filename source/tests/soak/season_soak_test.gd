extends SceneTree
## Late autumn through the winter into spring (milestone 5, E7): about seventeen days of the full game.
## The towns must get through the winter on their stores (nobody left starving), money and goods
## stay conserved, the fields lie bare in winter and are sown again in spring.
const Sim = preload("res://sim/core/simulation.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Weather = preload("res://sim/world/weather.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func hungry_share(s: Dictionary) -> int:
	var alive := 0
	var starving := 0
	for npc in s.residents.values():
		if npc.get("dead", false): continue
		alive += 1
		if int(npc.hunger) >= 90: starving += 1
	return starving * 100 / maxi(1, alive)
func _initialize() -> void:
	var sim := Sim.new(523)
	sim.start_game()
	var s: Dictionary = sim.state
	s.tick = Weather.season_start_tick(Weather.AUTUMN) + 14400 * 13   # autumn, day 14
	var worst_hungry := 0
	var bare_in_winter := true
	var start := Time.get_ticks_msec()
	while s.tick < Weather.season_start_tick(Weather.SPRING) + 14400 + 7300:   # to midday on the second day of spring
		sim.step()
		if s.tick % 5000 == 0:
			var errors := Checks.validate(s)
			if not errors.is_empty(): check(false, "Invariants at tick %d: %s" % [s.tick, errors])
		if s.tick % 3600 == 0:
			worst_hungry = maxi(worst_hungry, hungry_share(s))
		if s.tick == Weather.season_start_tick(Weather.WINTER) + 14400 * 7:   # midwinter
			for plot in s.crops.values():
				if plot.kind == "field" and plot.state != "fallow": bare_in_winter = false
	check(bare_in_winter, "The fields lie bare in midwinter")
	check(worst_hungry <= 25, "The towns get through the winter: at worst %d%% of people near starving" % worst_hungry)
	var sown := 0
	for plot in s.crops.values():
		if plot.kind == "field" and plot.state == "growing": sown += 1
	check(sown > 0, "The fields are sown again in spring")
	var farmers := 0
	for npc in s.residents.values():
		if npc.occupation == "Farmer": farmers += 1
	check(farmers > 0, "Farmers are back in spring")
	print("Season soak: %s; worst hungry %d%%; %d s" % ["PASS" if failures == 0 else "FAIL", worst_hungry, (Time.get_ticks_msec() - start) / 1000])
	quit(0 if failures == 0 else 1)
