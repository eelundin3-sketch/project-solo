extends RefCounted
## Which town a cell belongs to: the town whose storehouse is nearest, with no distance limit, so
## the roads and wilds between towns belong to the nearest one (its weather, its mud). One shared
## answer instead of each system measuring its own way. Integer maths, so it is deterministic.

## The id of the nearest town to `cell`, or 0 when there are no towns.
static func of(s: Dictionary, cell: Array) -> int:
	var best := 0
	var best_gap := 1 << 60
	var towns: Array = s.get("settlements", {}).keys()
	towns.sort()
	for key in towns:
		var town: Dictionary = s.settlements[key]
		var store: Array = s.entities[str(town.warehouse)].cell
		var dx: int = int(store[0]) - int(cell[0])
		var dy: int = int(store[1]) - int(cell[1])
		var gap: int = dx * dx + dy * dy
		if gap < best_gap:
			best_gap = gap
			best = int(town.id)
	return best

## The squared distance from `cell` to a town's storehouse.
static func gap_squared(s: Dictionary, town: int, cell: Array) -> int:
	var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
	var dx: int = int(store[0]) - int(cell[0])
	var dy: int = int(store[1]) - int(cell[1])
	return dx * dx + dy * dy

## The town the player is in or nearest to.
static func of_player(s: Dictionary) -> int:
	if not s.has("player") or not s.entities.has(str(s.player)): return 0
	return of(s, s.entities[str(s.player)].cell)
