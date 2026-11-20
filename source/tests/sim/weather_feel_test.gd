extends SceneTree
## Weather you can feel (milestone 5, W1): mud builds in rain and slows walking on the roads, fog
## shortens how far people see, and rain or snow falls outdoors but not indoors (view layer).
const Sim = preload("res://sim/core/simulation.gd")
const Weather = preload("res://sim/world/weather.gd")
const Pace = preload("res://sim/movement/pace.gd")
const TownLayout = preload("res://sim/world/town_layout.gd")
const Chronicle = preload("res://sim/world/chronicle.gd")
const Region = preload("res://sim/world/region.gd")
const World = preload("res://sim/world/world_db.gd")
const WeatherLayer = preload("res://view/world/weather_layer.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	var town: int = Region.of_player(s)
	var region: Dictionary = Weather.of_town(s, town)

	# Mud rises 5 an hour in rain and dries 2 an hour.
	region.kind = "rain"
	region.mud = 0
	var hour0: int = (s.tick / 600 + 1) * 600
	for hour in range(12):
		s.tick = hour0 + hour * 600
		if s.tick % Weather.BLOCK_TICKS == 0: s.tick += 600   # keep the roll from changing the weather
		region.kind = "rain"
		Weather.update(sim)
	check(int(region.mud) >= 50, "Twelve hours of rain make the roads muddy (%d)" % int(region.mud))
	var muddy: int = int(region.mud)
	region.kind = "clear"
	s.tick = (s.tick / 600 + 1) * 600
	if s.tick % Weather.BLOCK_TICKS == 0: s.tick += 600
	Weather.update(sim)
	check(int(region.mud) == muddy - 2, "Mud dries 2 an hour")

	# Mud slows walking on a road (and not off it).
	var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
	var road_cell: Array = []
	for dy in range(0, 12):
		for dx in range(-20, 21):
			var c: Array = [store[0] + dx, store[1] + dy]
			if TownLayout.road_kind(s, c) > 0 and Region.of(s, c) == town: road_cell = c; break
		if not road_cell.is_empty(): break
	check(not road_cell.is_empty(), "Found a street cell")
	region.mud = 0
	var dry_total := 0
	var carry := {}
	for i in range(20): dry_total += Pace.delay(s, road_cell, 20, carry)
	region.mud = 80
	var mud_total := 0
	carry = {}
	for i in range(20): mud_total += Pace.delay(s, road_cell, 20, carry)
	check(mud_total > dry_total, "Walking a muddy road is slower (%d vs %d ticks)" % [mud_total, dry_total])
	check(mud_total * 100 <= dry_total * 120, "But only by about 15%")
	region.mud = 0

	# Fog shortens how far people see.
	region.kind = "clear"
	check(Weather.sight_scale(s, store) == 100, "Clear weather: full sight")
	region.kind = "fog"
	check(Weather.sight_scale(s, store) == 60, "Fog cuts sight by 40%")
	var watcher: Dictionary = {}
	for npc in s.residents.values():
		if int(npc.settlement) == town and npc.get("sleeping", {}).is_empty() and npc.health > 0: watcher = npc; break
	check(not watcher.is_empty(), "Found someone awake to watch")
	var at: Array = s.entities[str(watcher.id)].cell
	var spot: Array = []
	for dx in [12, -12]:
		var c: Array = [at[0] + dx, at[1]]
		if load("res://sim/combat/cover.gd").line_clear(s, at, c): spot = c; break
	check(not spot.is_empty(), "Found a clear line of sight 12 cells long")
	if not spot.is_empty():
		region.kind = "clear"
		check(int(watcher.id) in Chronicle.witnesses(s, spot), "On a clear day someone 12 cells away sees it")
		region.kind = "fog"
		check(not int(watcher.id) in Chronicle.witnesses(s, spot), "In fog the same person 12 cells away does not")
	region.kind = "clear"

	# Rain falls outdoors and not indoors (the view's particle layer).
	var layer := WeatherLayer.new()
	region.kind = "rain"
	check(layer.falling_at(s, Vector2(store[0], store[1] + 4) * 24.0, false) == "rain", "Rain falls in the street")
	check(layer.falling_at(s, Vector2(store[0], store[1] + 4) * 24.0, true) == "", "No particles at the far map zoom")
	var house: Dictionary = {}
	for building in World.buildings(s):
		if int(building.get("settlement", 0)) == town: house = building; break
	var inside: Vector2 = Vector2(World.building_rect(house).get_center()) * 24.0
	check(World.inside_building(s, [roundi(inside.x / 24.0), roundi(inside.y / 24.0)]) != 0, "The test spot is inside a building")
	check(layer.falling_at(s, inside, false) == "", "No rain indoors")
	layer.free()

	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	print("Weather feel: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
