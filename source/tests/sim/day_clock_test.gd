extends SceneTree
## The four parts of the day and the calendar: morning 04-10, day 10-16, evening 16-22, night
## 22-04; everyone's own bedtime (21-22) and waking time (06-07); 15-day seasons; a new game
## opens on the first day of summer at 07:00. The sun rises in the east and sets in the west.
const Sim = preload("res://sim/core/simulation.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const Weather = preload("res://sim/world/weather.gd")
const Light = preload("res://sim/world/light.gd")
const NightLayer = preload("res://view/world/night_layer.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func asleep(s: Dictionary) -> Array:
	var count := 0
	var adults := 0
	for npc in s.residents.values():
		if npc.get("dead", false) or npc.occupation in ["Sheriff", "Barkeep", "Bandit"]: continue   # the barkeep keeps later hours; bandits sleep at their camp
		adults += 1
		if not npc.get("sleeping", {}).is_empty(): count += 1
	return [count, adults]

func _initialize() -> void:
	# The parts of the day.
	var expect := {0: "night", 239: "night", 240: "morning", 599: "morning", 600: "day", 959: "day", 960: "evening", 1319: "evening", 1320: "night", 1439: "night"}
	for m in expect: check(DayClock.phase_at(m) == expect[m], "%02d:%02d is %s" % [m / 60, m % 60, expect[m]])
	check(DayClock.daylight_at(12 * 60) == 100 and DayClock.daylight_at(1 * 60) == 10, "Full light at noon, dark at 01:00")
	check(DayClock.daylight_at(5 * 60) > 10 and DayClock.daylight_at(5 * 60) < 100, "Dawn at 05:00")
	check(DayClock.daylight_at(21 * 60) > 10 and DayClock.daylight_at(21 * 60) < 100, "Dusk at 21:00")
	check(DayClock.sun_elevation(5.0 / 24.0) < 0.01 and DayClock.sun_elevation(21.0 / 24.0) < 0.01, "The sun rises at 05:00 and sets at 21:00")
	check(DayClock.sun_elevation(13.0 / 24.0) > 0.99, "The sun is highest at 13:00")
	check(DayClock.sun_elevation(1.0 / 24.0) < 0.0, "The sun is down at night")
	check(DayClock.sun_arc(6.0 / 24.0) < 0.2 and DayClock.sun_arc(20.0 / 24.0) > 0.8, "The sun crosses from east to west")
	check(NightLayer.darkness_at(12 * 600) == 0.0 and NightLayer.darkness_at(23 * 600) > 0.6, "No darkness by day, dark at 23:00")

	# Everyone has their own bed and waking time in the hour asked for.
	for id in range(1, 200):
		var person := {"id": id}
		check(DayClock.bedtime(person) >= 21 * 60 and DayClock.bedtime(person) < 22 * 60, "Bedtime between 21:00 and 22:00")
		check(DayClock.wake_time(person) >= 6 * 60 and DayClock.wake_time(person) < 7 * 60, "Waking between 06:00 and 07:00")

	# A new game: the first day of summer, at 07:00 in the morning.
	var sim := Sim.new()
	sim.start_game()
	var s: Dictionary = sim.state
	check(s.tick / 14400 + 1 == 1 and DayClock.minute(s) == 7 * 60, "A new game starts on day 1 at 07:00")
	check(Weather.season(s) == Weather.SUMMER and Weather.day_of_season(s) == 0, "A new game starts on the first day of summer")
	check(DayClock.phase(s) == "morning", "It is morning")
	check(Weather.season_of(15 * 14400) == Weather.AUTUMN and Weather.season_of(30 * 14400) == Weather.WINTER and Weather.season_of(45 * 14400) == Weather.SPRING and Weather.season_of(60 * 14400) == Weather.SUMMER, "15 days a season: summer, autumn, winter, spring")
	check(Weather.season_of(15 * 14400 - 1) == Weather.SUMMER, "Day 15 is still summer")
	check(Weather.season_start_tick(Weather.WINTER) == 30 * 14400, "Winter begins on day 31")

	# A day in town: nobody in bed at noon, most asleep at 23:30, everyone up by 07:15.
	var at_noon: Array = []
	var late: Array = []
	var morning: Array = []
	while s.tick < 14400 + 4500:   # to 07:30 on day 2
		sim.step()
		if s.tick == 12 * 600: at_noon = asleep(s)
		if s.tick == 23 * 600 + 300: late = asleep(s)
		if s.tick == 14400 + 7 * 600 + 150: morning = asleep(s)
	check(at_noon[0] == 0, "Nobody is in bed at noon (%d)" % at_noon[0])
	check(late[0] * 2 > late[1], "Most people are asleep at 23:30 (%d of %d)" % late)
	check(morning[0] == 0, "Everyone is up by 07:15 (%d still in bed)" % morning[0])
	check(Light.lamps_lit(s) == false, "Street lamps are out in the morning")

	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load keep the same hash")
	print("Day clock: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
