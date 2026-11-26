extends RefCounted
## Walking is a little quicker on a road: a town street saves about one step in seven, the roads
## between the towns about one in four. Steps are whole ticks, so the saving is kept as a carried
## fraction (hundredths of a tick) and the average pace comes out exact; integer maths only, so the
## simulation stays deterministic.
const TownLayout = preload("res://sim/world/town_layout.gd")
const BONUS := [0, 15, 30]
const MUDDY := 50          # road mud above this slows walkers...
const MUD_SLOWER := 15     # ...by this many percent   # percent faster: off the roads, a town street, a road between towns

static func bonus(s: Dictionary, cell: Array) -> int:
	return BONUS[TownLayout.road_kind(s, cell)]

## Ticks until the next step for a walk that takes `base` ticks per cell off the roads, stepping
## onto `cell`. The fraction left over is carried in record[key].
## `slower` (percent) lengthens each step, for a heavy load (encumbrance.gd).
static func delay(s: Dictionary, cell: Array, base: int, record: Dictionary, key: String = "stride_carry", slower: int = 0) -> int:
	var extra: int = bonus(s, cell)
	if extra > 0 and load("res://sim/world/weather.gd").mud_at(s, cell) > MUDDY: slower += MUD_SLOWER   # a muddy road
	if extra == 0 and slower == 0:
		record[key] = 0
		return base
	var total: int = base * 100 * (100 + slower) / (100 + extra) + int(record.get(key, 0))   # hundredths of a tick
	var ticks: int = maxi(1, total / 100)
	record[key] = total - ticks * 100
	return ticks

## The arrival tick (from the start) at every cell of a path walked at `base` ticks per cell.
static func schedule(s: Dictionary, path: Array, base: int) -> Array:
	var times: Array = [0]
	var carry := {}
	for index in range(1, path.size()):
		times.append(int(times[index - 1]) + delay(s, path[index], base, carry))
	return times
