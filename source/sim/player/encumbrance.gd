extends RefCounted
## How heavy the player's pack is, and what that does to them. Weights are kept in tenths so a
## shell or a bandage can weigh less than a log without fractions; everything is integer maths.
## The load is worked out from the inventory when it is needed (a dozen entries), never stored.
const Outfits = preload("res://sim/entities/outfits.gd")

## Tenths of a weight unit per item. Anything not listed (and every clothing piece) weighs 0.5.
const WEIGHT_TENTHS := {"food": 5, "rye": 5, "bandage": 2, "antiseptic": 3, "shell": 1, "tool": 30,
	"plank": 30, "ore": 40, "log": 60, "shotgun": 40, "rifle": 45, "cartridge": 1, "lantern": 10}
const DEFAULT_TENTHS := 5
const BASE_LIMIT := 400          # 40.0: what you carry in your hands and pockets
const PACK_BONUS := 150          # a backpack adds 15.0
## Bands by load (percent of the limit): light, heavy, overloaded, crushing.
const HEAVY_AT := 75
const OVERLOADED_AT := 100
const CRUSHING_AT := 150
## How much longer each step takes in each band (percent).
const SLOWER := [0, 10, 30, 60]
const NAMES := ["Light", "Heavy", "Overloaded", "Crushing"]

static func item_tenths(item: String) -> int:
	return int(WEIGHT_TENTHS.get(item, DEFAULT_TENTHS))

static func load_tenths(s: Dictionary, id: int) -> int:
	var total := 0
	var items: Dictionary = s.get("inventories", {}).get(str(id), {}).get("items", {})
	for item in items:
		total += int(items[item]) * item_tenths(str(item))
	if id == int(s.get("player", -1)) and int(s.get("player_control", {}).get("carrying", {}).get("id", 0)) != 0:
		total += 250   # a person over your shoulder (carrying.gd)
	return total

static func limit_tenths(s: Dictionary, id: int) -> int:
	var worn: Dictionary = Outfits.worn(s, id) if s.has("entities") and s.entities.has(str(id)) else {}
	var fit: int = load("res://sim/player/activities.gd").carry_bonus(s) if id == int(s.get("player", -1)) else 0   # training at home
	return BASE_LIMIT + (PACK_BONUS if not str(worn.get("pack", "")).is_empty() else 0) + fit

## 0 light, 1 heavy, 2 overloaded (no running), 3 crushing.
static func band(s: Dictionary, id: int = -1) -> int:
	if id < 0: id = int(s.get("player", -1))
	if id < 0: return 0
	var percent: int = load_tenths(s, id) * 100 / maxi(1, limit_tenths(s, id))
	if id == int(s.get("player", -1)) and int(s.get("player_control", {}).get("carrying", {}).get("id", 0)) != 0:
		percent = maxi(percent, OVERLOADED_AT + 1)   # a body is always an overload: slow, and no running
	if percent > CRUSHING_AT: return 3
	if percent > OVERLOADED_AT: return 2
	if percent > HEAVY_AT: return 1
	return 0

static func slower_percent(s: Dictionary) -> int:
	return SLOWER[band(s)]

static func can_run(s: Dictionary) -> bool:
	return band(s) < 2

## "12.5 / 55" for the inventory header.
static func describe(s: Dictionary, id: int) -> String:
	var used: int = load_tenths(s, id)
	var cap: int = limit_tenths(s, id)
	return "Load %d.%d / %d" % [used / 10, used % 10, cap / 10]
