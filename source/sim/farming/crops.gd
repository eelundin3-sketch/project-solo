extends RefCounted
## Rye crop growth for professional fields and household gardens. Growth is an
## integer count of ticks so saves, hashes and replays stay exact.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Weather = preload("res://sim/world/weather.gd")
const CYCLE_TICKS: int = 43200          # three game days from sowing to harvest-ready
const RIPE_WAIT_TICKS: int = 1200       # a ripe field waits about two hours for the harvest
const YIELD_PER_CELL: int = 3
## Growth fraction (permille) at which each of the six visual stages begins.
const STAGE_START: Array[int] = [0, 100, 300, 550, 800, 1000]
const STAGE_NAMES: Array[String] = ["Newly sown", "Early growth", "Intermediate growth", "Ripening", "Fully grown", "Ready to harvest"]

static func initialize(s: Dictionary) -> void:
	if not s.has("crops"): s.crops = {}

static func permille(plot: Dictionary) -> int:
	return clampi(int(plot.grown) * 1000 / CYCLE_TICKS, 0, 1000)

static func stage(plot: Dictionary) -> int:
	if plot.get("state", "growing") == "fallow": return -1
	var value := permille(plot)
	var result := 0
	for index in range(STAGE_START.size()):
		if value >= STAGE_START[index]: result = index
	return result

static func stage_name(plot: Dictionary) -> String:
	var index := stage(plot)
	return "Fallow soil" if index < 0 else STAGE_NAMES[index]

static func cells(plot: Dictionary) -> int:
	return int(plot.rect[2]) * int(plot.rect[3])

## Drought takes `yield_loss` off each cell's yield, but every cell still gives at least 1.
static func expected_yield(plot: Dictionary) -> int:
	return cells(plot) * maxi(1, YIELD_PER_CELL - int(plot.get("yield_loss", 0)))

## How dry the plot's town has been: normal growth up to 4 dry days, half speed from 5, none from 9.
static func dry_days(s: Dictionary, plot: Dictionary) -> int:
	return int(Weather.of_town(s, int(plot.settlement)).get("dry_days", 0))

## Growth per 10 ticks (normally 10), slowed by drought.
## Seasons: crops grow 20% faster in summer and not at all in winter.
static func growth_step(s: Dictionary, plot: Dictionary) -> int:
	var season: int = Weather.season(s)
	if season == Weather.WINTER: return 0
	var dry: int = dry_days(s, plot)
	var step: int = 0 if dry >= 9 else (5 if dry >= 5 else 10)
	return step * 12 / 10 if season == Weather.SUMMER else step

## Sowing is done in spring and summer only.
static func sowing_season(s: Dictionary) -> bool:
	return Weather.season(s) in [Weather.SPRING, Weather.SUMMER]

## The tick a season begins (spring, summer, autumn or winter of the current year).
static func season_start(s: Dictionary, season: int) -> bool:
	return Weather.is_season_start(s, season)

## Registers a plot; `grown` lets the starting scenario begin mid-season.
static func add_plot(s: Dictionary, kind: String, rect: Array, settlement: int, farm: int = 0, home: int = 0, grown: int = 0) -> String:
	initialize(s)
	var key := str(s.crops.size() + 1)
	while s.crops.has(key): key = str(int(key) + 1)
	s.crops[key] = {"id": int(key), "kind": kind, "crop": "rye", "rect": rect.duplicate(), "settlement": settlement, "farm": farm, "home": home,
		"grown": grown, "state": "growing", "ripe_since": 0, "harvests": 0, "tended": 0}
	return key

static func plot_for_farm(s: Dictionary, farm: int) -> Dictionary:
	for plot in s.get("crops", {}).values():
		if plot.farm == farm: return plot
	return {}

static func plots_for_home(s: Dictionary, home: int) -> Array:
	var found: Array = []
	for plot in s.get("crops", {}).values():
		if plot.home == home: found.append(plot)
	return found

static func update(s: Dictionary) -> void:
	if not s.has("crops") or s.tick % 10 != 0: return
	if s.tick % Weather.DAY == 0: _daily_drought(s)
	if season_start(s, Weather.WINTER): _frost(s)
	elif season_start(s, Weather.SPRING): _spring_sowing(s)
	for plot in s.crops.values():
		if plot.state != "growing": continue
		if plot.grown < CYCLE_TICKS:
			var step: int = growth_step(s, plot)
			if step <= 0: continue
			plot.grown = mini(CYCLE_TICKS, int(plot.grown) + step)
			if plot.grown >= CYCLE_TICKS: plot.ripe_since = s.tick
		elif plot.kind == "field" and s.tick - int(plot.ripe_since) >= RIPE_WAIT_TICKS:
			# A professional field is harvested by its settlement's farm crew.
			if crew_available(s, plot): harvest(s, plot)

static func crew_available(s: Dictionary, plot: Dictionary) -> bool:
	for npc in s.get("residents", {}).values():
		if npc.settlement == plot.settlement and npc.occupation in ["Farmer", "Gatherer"] and npc.health > 0 and npc.get("migration", {}).is_empty(): return true
	return false

## Moves the crop into the owner's store (farm entity or home pantry) and resows.
static func harvest(s: Dictionary, plot: Dictionary) -> int:
	if stage(plot) != 5: return 0
	var owner: int = plot.farm if plot.kind == "field" else plot.home
	if owner == 0 or not s.inventories.has(str(owner)): return 0
	var full: int = cells(plot) * YIELD_PER_CELL
	var amount: int = mini(expected_yield(plot), Inventory.available(s, owner))
	if amount > 0: Inventory.produce(s, owner, "rye", amount)
	plot.harvests += 1
	plot.last_harvest = {"tick": s.tick, "percent": expected_yield(plot) * 100 / maxi(1, full)}
	plot.yield_loss = 0
	plot.grown = 0
	plot.ripe_since = 0
	if not sowing_season(s): plot.state = "fallow"   # after the autumn harvest the field lies bare until spring
	return amount

## After 9 dry days a growing crop withers: one less per cell for every 2 dry days from then on.
static func _daily_drought(s: Dictionary) -> void:
	for plot in s.crops.values():
		if plot.state != "growing" or int(plot.grown) >= CYCLE_TICKS: continue
		var dry: int = dry_days(s, plot)
		if dry >= 9 and (dry - 9) % 2 == 0:
			plot.yield_loss = mini(YIELD_PER_CELL - 1, int(plot.get("yield_loss", 0)) + 1)

## The first frost: whatever is still in the fields (ripe or not) is lost, and they lie bare.
static func _frost(s: Dictionary) -> void:
	for plot in s.crops.values():
		if plot.state != "growing": continue
		plot.spoiled = int(plot.get("spoiled", 0)) + 1
		plot.state = "fallow"
		plot.grown = 0
		plot.ripe_since = 0
		plot.yield_loss = 0

## Spring: the farmers sow every bare field.
static func _spring_sowing(s: Dictionary) -> void:
	for plot in s.crops.values():
		if plot.kind == "field" and plot.state == "fallow": sow(plot)

## A town whose last field harvest (within a day) came in at half or less.
static func poor_harvest(s: Dictionary, town: int) -> bool:
	for plot in s.get("crops", {}).values():
		if plot.kind != "field" or int(plot.settlement) != town: continue
		var last: Dictionary = plot.get("last_harvest", {})
		if not last.is_empty() and s.tick - int(last.tick) <= Weather.DAY and int(last.percent) <= 50: return true
	return false

static func sow(plot: Dictionary) -> void:
	plot.state = "growing"
	plot.grown = 0

## Garden work by a household member: sow fallow soil, harvest ripe rye, or tend a growing crop.
static func tend(s: Dictionary, plot: Dictionary) -> String:
	if plot.state == "fallow":
		if not sowing_season(s): return "stalled"
		sow(plot); return "sowed"
	if stage(plot) == 5:
		return "harvested" if harvest(s, plot) > 0 else "stalled"
	plot.tended += 1
	# Tending (weeding, watering) gives a small growth bonus, at most a few percent per visit.
	plot.grown = mini(CYCLE_TICKS, int(plot.grown) + 120)
	return "tended"

## A fallow plot only needs sowing in spring and summer (pass `s` to know the season).
static func needs_attention(plot: Dictionary, s: Dictionary = {}) -> bool:
	if plot.state == "fallow": return s.is_empty() or sowing_season(s)
	return stage(plot) == 5 or (plot.kind == "garden" and stage(plot) in [1, 2, 3] and int(plot.tended) < 2 + int(plot.harvests))
