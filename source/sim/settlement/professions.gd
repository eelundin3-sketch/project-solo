extends RefCounted
## Resource-driven profession demand. A settlement does not receive a fixed roster:
## each trade's demand is derived from what the land around it offers and how many
## people it must feed and protect. Farmers and a sheriff emerge from the food and
## safety terms in the same way a miner emerges from nearby ore.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const World = preload("res://sim/world/world_db.gd")
const DerivedCache = preload("res://sim/core/derived_cache.gd")
const GATHERERS: Array[String] = ["Gatherer", "Woodsman", "Farmer", "Miner"]
const WORKSHOP_TRADES: Array[String] = ["Sawyer", "Baker", "Blacksmith"]
## Which resource entity kinds each gathering profession works.
## When several trades are equally short, the more essential one is filled first.
const PRIORITY: Array[String] = ["Farmer", "Sheriff", "Woodsman", "Sawyer", "Trader", "Miner", "Baker", "Blacksmith"]
const TARGETS: Dictionary = {"Woodsman": ["tree"], "Farmer": ["farm"], "Miner": ["ore"], "Gatherer": ["tree", "farm", "ore"]}
const DESCRIPTIONS: Dictionary = {
	"Farmer": "Grows and harvests rye for the settlement's food supply.",
	"Woodsman": "Fells trees and hauls logs to the storehouse.",
	"Sawyer": "Plank maker: saws logs into planks at the timber workshop.",
	"Miner": "Digs iron ore from nearby deposits.",
	"Blacksmith": "Forge worker: smelts ore into iron tools.",
	"Baker": "Bakes rye into bread for the provisions stall and storehouse.",
	"Builder": "Raises homes and workshops from planks.",
	"Sheriff": "Keeps the peace, patrols the square and guards the road.",
	"Trader": "Walks between the markets, buying where goods are cheap and selling where they are dear.",
	"Carpenter": "Craftsman: joinery and furniture for new homes.",
	"Child": "Too young to work; helps in the household garden."}

## Trees and ore near a town and its fields: they change only when entities are added or removed,
## so the counts are kept (derived, never saved) until the entity list changes. Counting ~6,300
## trees for each town every day was the bulk of the midday update.
static var _land_cache: Array = []
static func _land(s: Dictionary, settlement: int, center: Array) -> Dictionary:
	var cache: Dictionary = DerivedCache.slot(_land_cache, s.entities)
	var signature := [s.entities.size(), World.entity_serial, settlement, center[0], center[1]]
	var key := str(settlement)
	if cache.has(key) and cache[key].signature == signature: return cache[key]
	var land := {"trees": 0, "ore": 0, "fields": 0, "signature": signature}
	for kind in ["tree", "ore"]:
		for entity in World.of_kind(s, kind):
			if not entity.has("cell"): continue
			if absi(entity.cell[0] - center[0]) <= 62 and absi(entity.cell[1] - center[1]) <= 40:
				land[("trees" if kind == "tree" else "ore")] += 1
	for entity in World.of_kind(s, "farm"):
		if int(entity.settlement) == settlement: land.fields += 1
	cache[key] = land
	return land

static func settlement_resources(s: Dictionary, settlement: int) -> Dictionary:
	var town: Dictionary = s.settlements[str(settlement)]
	var center: Array = s.entities[str(town.warehouse)].cell
	var result := {"trees": 0, "ore": 0, "fields": 0, "population": 0, "danger": 0, "workshops": {}}
	var land: Dictionary = _land(s, settlement, center)
	result.trees = int(land.trees)
	result.ore = int(land.ore)
	result.fields = int(land.fields)
	for npc in s.residents.values():
		if npc.settlement == settlement and npc.health > 0 and npc.occupation != "Child" and not npc.get("garrison", false): result.population += 1   # the extra office sheriffs are not part of the trades economy
	for workshop in s.get("workshops", {}).values():
		if workshop.settlement == settlement: result.workshops[workshop.get("kind", "sawmill")] = true
	result.danger = int(s.get("routes", {}).get("1", {}).get("risk", 0))
	return result

## Percent of a town's people who farm, from its climate (used by demand and by tests).
static func farm_share(s: Dictionary, settlement: int) -> int:
	var rain: int = int(load("res://sim/world/weather.gd").climate(s, settlement).rain)
	return 20 * (50 if rain < 20 else (130 if rain > 40 else 100)) / 100

## Desired head-count per profession, derived from resources and needs.
static func demand(s: Dictionary, settlement: int) -> Dictionary:
	var r: Dictionary = settlement_resources(s, settlement)
	var pop: int = r.population
	var want: Dictionary = {}
	# Climate: a dry town (rain under 20%) farms half as much and mines half as much again; a wet
	# one (over 40%) farms more. The shares are percent of the population.
	var rain: int = int(load("res://sim/world/weather.gd").climate(s, settlement).rain)
	var farming: int = farm_share(s, settlement)
	var mine_share: int = 15 * (150 if rain < 20 else 100) / 100
	# Winter: the fields lie bare, so nobody is wanted as a farmer (they cut wood or mine instead).
	if r.fields > 0 and not winter(s): want.Farmer = maxi(1, ceili(pop * farming / 100.0))
	# Timber needs two pairs of hands in a small town, because one of them is borrowed whenever a house is built.
	if r.trees >= 20: want.Woodsman = maxi(1, ceili(pop * 0.4))
	if want.get("Woodsman", 0) > 0 and r.workshops.has("sawmill"): want.Sawyer = 1
	# Households bake their own rye; a dedicated baker only pays for itself once there are six or more people.
	if r.fields > 0 and r.workshops.has("bakery") and pop >= 6: want.Baker = 1
	if r.ore >= 1: want.Miner = maxi(1, ceili(pop * mine_share / 100.0))
	if want.get("Miner", 0) > 0 and r.workshops.has("forge"): want.Blacksmith = 1
	# Safety: a settlement large enough to have something worth stealing, or one beside a dangerous road.
	if pop >= 3 or r.danger > 0: want.Sheriff = 1 + pop / 18
	# A trader only while the price difference between markets pays for the walk.
	if pop >= 4 and load("res://sim/economy/traders.gd").wanted(s, settlement) > 0: want.Trader = 1
	return want

static func count(s: Dictionary, settlement: int, occupation: String) -> int:
	var total := 0
	for npc in s.residents.values():
		if npc.settlement == settlement and npc.occupation == occupation and npc.health > 0: total += 1
	return total

## Fills unmet demand from residents without a trade. Deterministic: lowest id first,
## and the trade with the largest shortfall ratio is filled first.
static func assign(s: Dictionary, settlement: int) -> void:
	var want: Dictionary = demand(s, settlement)
	var free: Array = []
	for npc in s.residents.values():
		if npc.settlement == settlement and npc.occupation == "Gatherer" and npc.health > 0 and npc.job == 0 and npc.get("migration", {}).is_empty(): free.append(npc.id)
	free.sort()
	while not free.is_empty():
		var best := "~"   # sorts after every real trade
		var ratio := 0.0
		for key in want:
			var trade: String = str(key)
			var have: int = count(s, settlement, trade)
			var shortfall: float = float(want[trade] - have) / float(want[trade])
			if want[trade] > have and (shortfall > ratio or (shortfall == ratio and PRIORITY.find(trade) < PRIORITY.find(best))):
				best = trade
				ratio = shortfall
		if best == "~": break
		s.residents[str(free.pop_front())].occupation = best
	if s.has("settlements"):
		load("res://sim/law/sheriff.gd").dress(s)
		load("res://sim/economy/traders.gd").ensure(s)

static func winter(s: Dictionary) -> bool:
	return load("res://sim/world/weather.gd").season(s) == 3

## On the first day of winter the farmers put down their tools and take whatever work there is
## (wood, ore); on the first day of spring they go back to the fields. Runs from Households.daily.
static func seasonal_work(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var Weather = load("res://sim/world/weather.gd")
	if Weather.day_of_season(s) != 0: return
	var season: int = Weather.season(s)
	if season != Weather.WINTER and season != Weather.SPRING: return
	var Jobs = load("res://sim/jobs/job_board.gd")
	var keys: Array = s.residents.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.get("dead", false) or npc.health <= 0: continue
		if season == Weather.WINTER and npc.occupation == "Farmer":
			if npc.job != 0: Jobs.release(s, npc.job, "WINTER")
			npc.seasonal = "Farmer"
			npc.occupation = "Gatherer"
		elif season == Weather.SPRING and str(npc.get("seasonal", "")) == "Farmer":
			if npc.job != 0: Jobs.release(s, npc.job, "SPRING")
			npc.occupation = "Farmer"
			npc.erase("seasonal")
	if season == Weather.WINTER: sim.record("Winter: the fields lie bare and the farmers turn to wood and ore.")
	else: sim.record("Spring: the farmers go back to their fields to sow.")

static func gathers(npc: Dictionary, target_kind: String) -> bool:
	return TARGETS.get(npc.occupation, []).has(target_kind)
