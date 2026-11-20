extends RefCounted
## Seeded weather is simulation state; rendering only reads this record.
##
## Each town has its own weather (`s.weather.regions[town]`), rolled on its own stream from its
## own climate: Reedbank is wet, Dustvale is dry. The roads and wilds take the nearest town's
## weather (Region.of). The top-level record (`kind`, `previous`, `since`, `wind`, `snow`) is
## the weather where the player is, so everything that read the old single record still works;
## it is refreshed at each roll and whenever the player walks into another town's weather.
## A world with no towns yet (a bare village test) keeps the old single roll.
const Region = preload("res://sim/world/region.gd")
const BLOCK_TICKS: int = 3600
const TRANSITION_TICKS: int = 300
const DAY: int = 14400
const SEASON_DAYS: int = 15
const SEASON_OFFSET: int = 1   # the first day of a game is the first day of summer
const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3
const SEASON_NAMES: Array[String] = ["spring", "summer", "autumn", "winter"]
## Chance in percent, per 6-hour block, of rain (snow in winter) and of fog, by town name.
const CLIMATE := {
	"Reedbank": {"rain": 45, "fog": 15},
	"Alder Hollow": {"rain": 35, "fog": 15},
	"Dustvale": {"rain": 15, "fog": 8},
}
const DEFAULT_CLIMATE := {"rain": 35, "fog": 15}
const MIRRORED := ["kind", "previous", "since", "wind", "snow"]

static func season(s: Dictionary) -> int:
	return season_of(int(s.tick))

static func season_of(tick: int) -> int:
	return (tick / (DAY * SEASON_DAYS) + SEASON_OFFSET) % 4

## 0 on the first day of a season, up to 14.
static func day_of_season(s: Dictionary) -> int:
	return (int(s.tick) / DAY) % SEASON_DAYS

## True on the very first tick of `season` (midnight starting its first day).
static func is_season_start(s: Dictionary, which: int) -> bool:
	return int(s.tick) % (DAY * SEASON_DAYS) == 0 and season(s) == which

## The first tick of the `nth` time `which` season comes round (n = 0 is the first; summer
## begins at tick 0).
static func season_start_tick(which: int, nth: int = 0) -> int:
	var index: int = posmod(which - SEASON_OFFSET, 4) + nth * 4
	return index * DAY * SEASON_DAYS

static func climate(s: Dictionary, town: int) -> Dictionary:
	var settlement: Dictionary = s.get("settlements", {}).get(str(town), {})
	return CLIMATE.get(str(settlement.get("name", "")), DEFAULT_CLIMATE)

static func initialize(s: Dictionary) -> void:
	if not s.has("weather"):
		s.weather = {"kind": "clear", "previous": "clear", "since": s.tick, "wind": 25, "snow": 0}
	ensure_regions(s)

## One weather record per town. Old saves (and worlds whose towns came later) start each town
## with a copy of the single weather they had.
static func ensure_regions(s: Dictionary) -> void:
	if not s.has("weather"): return
	var towns: Dictionary = s.get("settlements", {})
	if towns.is_empty(): return
	var w: Dictionary = s.weather
	if not w.has("regions"): w.regions = {}
	for key in towns:
		if w.regions.has(str(key)): continue
		var region := {"dry_days": 0, "wet_today": false, "mud": 0}
		for field in MIRRORED: region[field] = w.get(field, "clear" if field in ["kind", "previous"] else 0)
		w.regions[str(key)] = region

## The weather record for the town a cell belongs to (the single record when there are no towns).
static func at(s: Dictionary, cell: Array) -> Dictionary:
	return of_town(s, Region.of(s, cell))

static func of_town(s: Dictionary, town: int) -> Dictionary:
	var w: Dictionary = s.get("weather", {})
	return w.get("regions", {}).get(str(town), w)

static func kind_at(s: Dictionary, cell: Array) -> String:
	return str(at(s, cell).get("kind", "clear"))

## A short line about a town's weather, for "Ask for news" ("" when there is nothing to say).
static func news_line(s: Dictionary, town: int) -> String:
	var region: Dictionary = of_town(s, town)
	var dry: int = int(region.get("dry_days", 0))
	if int(region.get("relief_until", 0)) > int(s.tick): return "The rain's come back, thank heaven."
	if dry >= 9: return "No rain in %d days. The harvest will be poor." % dry
	if dry >= 5: return "It hasn't rained in %d days; the farmers are worried." % dry
	if int(region.get("mud", 0)) > 50: return "The roads are thick with mud after all this rain."
	return ""

## How far people can see at `cell`, in percent of a clear day: fog cuts sight by 40%.
## Used by witnesses (chronicle), fear, who sees a shot, and sheriffs spotting the player.
static func sight_scale(s: Dictionary, cell: Array) -> int:
	return 60 if kind_at(s, cell) == "fog" else 100

## A sight range scaled for fog at `cell`.
static func sight(s: Dictionary, cell: Array, full: float) -> float:
	return full * float(sight_scale(s, cell)) / 100.0

## Mud on the roads of the town a cell belongs to, 0 to 100.
static func mud_at(s: Dictionary, cell: Array) -> int:
	return int(at(s, cell).get("mud", 0))

static func wet(kind: String) -> bool:
	return kind == "rain" or kind == "snow"

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("weather"): initialize(s)
	if not s.weather.has("regions") or s.weather.regions.size() != s.get("settlements", {}).size(): ensure_regions(s)
	var regions: Dictionary = s.weather.get("regions", {})
	if regions.is_empty():
		_single(sim)
		return
	var keys: Array = regions.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	if s.tick % DAY == 0:
		for key in keys:
			var region: Dictionary = regions[key]
			region.dry_days = 0 if region.get("wet_today", false) else int(region.get("dry_days", 0)) + 1
			region.wet_today = wet(str(region.kind))
	var rolled := false
	if s.tick % BLOCK_TICKS == 0:
		rolled = true
		for key in keys:
			var region: Dictionary = regions[key]
			var chance: Dictionary = climate(s, int(key))
			region.previous = region.kind
			var roll: int = sim.random_int("weather:kind:%s" % key, 0, 99)
			region.kind = ("snow" if season(s) == WINTER else "rain") if roll < int(chance.rain) else ("fog" if roll < int(chance.rain) + int(chance.fog) else "clear")
			region.wind = sim.random_int("weather:wind:%s" % key, 15, 85)
			region.since = s.tick
			if wet(str(region.kind)):
				if int(region.get("dry_days", 0)) >= 5 and not region.get("wet_today", false): region.relief_until = s.tick + DAY
				region.wet_today = true
	if s.tick % 100 == 0:
		for key in keys:
			var region: Dictionary = regions[key]
			if region.kind == "snow": region.snow = mini(100, int(region.snow) + 1)
			elif int(region.snow) > 0 and season(s) != WINTER: region.snow = maxi(0, int(region.snow) - 1)
	if s.tick % 600 == 0:
		for key in keys:
			var region: Dictionary = regions[key]
			# Roads turn to mud after rain (5 an hour) and dry slowly (2 an hour).
			region.mud = clampi(int(region.get("mud", 0)) + (5 if region.kind == "rain" else -2), 0, 100)
	# The top-level record follows the player's town: refreshed at each roll, each 100 ticks for
	# snow, and when the player walks into another town's weather.
	var here: int = Region.of_player(s)
	if here == 0 or not regions.has(str(here)): return
	if rolled or here != int(s.weather.get("region", 0)) or s.tick % 100 == 0:
		var region: Dictionary = regions[str(here)]
		var changed_region: bool = here != int(s.weather.get("region", 0))
		if rolled or changed_region:
			for field in MIRRORED: s.weather[field] = region[field]
		else:
			s.weather.snow = region.snow
		s.weather.region = here

## The old single weather, for a world without towns.
static func _single(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if s.tick % BLOCK_TICKS == 0:
		var weather: Dictionary = s.weather
		weather.previous = weather.kind
		var roll: int = sim.random_int("weather:kind", 0, 99)
		weather.kind = ("snow" if season(s) == WINTER else "rain") if roll < 35 else ("fog" if roll < 50 else "clear")
		weather.wind = sim.random_int("weather:wind", 15, 85)
		weather.since = s.tick
	if s.tick % 100 == 0:
		var w: Dictionary = s.weather
		if w.kind == "snow": w.snow = mini(100, w.snow + 1)
		elif w.snow > 0 and season(s) != WINTER: w.snow = maxi(0, w.snow - 1)
