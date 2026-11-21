extends RefCounted
## The player's standing in each town, -100..100. Not scored by hand: every morning it is worked
## out from the chronicle, from what that town knows the player did. A town knows what happened in
## it with someone watching, and whatever news has reached it (gossip adds the town to the entry's
## `heard_in`). Old deeds fade over four weeks; a killing fades over twelve.
const Chronicle = preload("res://sim/world/chronicle.gd")
const DAY := 14400
const WEIGHT := {"murder": -40, "shooting": -15, "kick": -10, "theft": -10, "assault": -8, "assault_sheriff": -12,
	"discharge": -4, "trespass": -3, "escape": -10, "bribery": -6, "helped": 6, "favour": 8, "saved_life": 20, "bounty": 10, "bandits_cleared": 25}
const FADE_DAYS := 28
const MURDER_FADE_DAYS := 84
const LABELS := [[-60, "Feared"], [-25, "Distrusted"], [25, "a Stranger"], [50, "Known"], [75, "Respected"], [101, "Beloved"]]

static func known_in(entry: Dictionary, town: int) -> bool:
	if int(entry.get("town", 0)) == town and (not entry.get("witnesses", []).is_empty() or int(entry.get("victim", 0)) != 0): return true
	return town in entry.get("heard_in", [])

## Works out today's standing in every town (called each morning) and stores it in s.reputation.
static func update(s: Dictionary) -> void:
	if not s.has("settlements") or not s.has("player"): return
	var standing: Dictionary = {}
	for key in s.settlements: standing[key] = 0
	for entry in Chronicle.entries(s):
		if int(entry.get("actor", 0)) != int(s.player) or not WEIGHT.has(str(entry.kind)): continue
		var days: int = MURDER_FADE_DAYS if entry.kind == "murder" else FADE_DAYS
		var age: int = int(s.tick) - int(entry.tick)
		if age >= days * DAY: continue
		var weight: int = int(WEIGHT[entry.kind]) * (days * DAY - age) / (days * DAY)
		for key in standing:
			if known_in(entry, int(key)): standing[key] += weight
	for key in standing: standing[key] = clampi(int(standing[key]), -100, 100)
	s.reputation = standing

static func value(s: Dictionary, town: int) -> int:
	return int(s.get("reputation", {}).get(str(town), 0))

## "Feared", "Distrusted", "a Stranger", "Known", "Respected" or "Beloved".
static func label(standing: int) -> String:
	for step in LABELS:
		if standing < int(step[0]): return str(step[1])
	return "Beloved"

## "Respected in Alder Hollow · Distrusted in Reedbank · a Stranger in Dustvale".
static func summary(s: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = s.get("settlements", {}).keys()
	keys.sort()
	for key in keys: parts.append("%s in %s" % [label(value(s, int(key))), s.settlements[key].name])
	return " · ".join(parts)
