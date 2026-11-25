extends RefCounted
## News travels. Whoever saw something knows it first; neighbours pass the newest thing the other
## hasn't heard when they stop to chat (sometimes making it bigger), families share everything
## over the day, and traders carry the latest news from one town's market to the next. Once a
## third of a town's grown-ups have heard of something, the town "knows" it (the chronicle entry
## gets the town in `heard_in`, which reputation reads). Asking someone for news gets real gossip.
const Chronicle = preload("res://sim/world/chronicle.gd")
const MAX_RUMOURS := 8
const STALE_DAYS := 14
const DAY := 14400
const SHARE_CHANCE := 50     # percent, when two people chat
const GROW_CHANCE := 15      # percent that the story gets bigger in the telling
const CARRY := 3             # how many pieces of news a trader takes along
const NEWS_KINDS := ["theft", "murder", "shooting", "assault", "assault_sheriff", "kick", "discharge", "death", "birth", "migration",
	"body_found", "outlaw_jailed", "outlaw_killed", "robbed_by_bandits", "bandits_cleared", "bandit_camp"]

static func knows(npc: Dictionary, event_id: int) -> bool:
	for rumour in npc.get("rumours", []):
		if int(rumour.event) == event_id: return true
	return false

## `npc_id` hears of chronicle entry `event_id`, told at exaggeration `level` (0-2).
static func learn(s: Dictionary, npc_id: int, event_id: int, level: int = 0) -> bool:
	var npc: Dictionary = s.get("residents", {}).get(str(npc_id), {})
	if npc.is_empty() or int(npc.get("health", 0)) <= 0 or knows(npc, event_id): return false
	if not npc.has("rumours"): npc.rumours = []
	npc.rumours.append({"event": event_id, "level": clampi(level, 0, 2), "heard": int(s.tick)})
	while npc.rumours.size() > MAX_RUMOURS: npc.rumours.pop_front()
	return true

## Called by the chronicle: everyone who saw it (and a living victim) knows it at once.
static func witnessed(s: Dictionary, entry: Dictionary) -> void:
	if not str(entry.kind) in NEWS_KINDS: return
	for id in entry.get("witnesses", []): learn(s, int(id), int(entry.id))
	if int(entry.get("victim", 0)) != 0: learn(s, int(entry.victim), int(entry.id))

## The newest thing `from` knows that `to` hasn't heard; {} when there's nothing new.
static func newest_unknown(s: Dictionary, from: Dictionary, to: Dictionary) -> Dictionary:
	var rumours: Array = from.get("rumours", [])
	for index in range(rumours.size() - 1, -1, -1):
		if not knows(to, int(rumours[index].event)) and not Chronicle.find(s, int(rumours[index].event)).is_empty(): return rumours[index]
	return {}

## Two neighbours chatting (speech.gd): each may pass on their newest news.
static func chat(sim: RefCounted, a: Dictionary, b: Dictionary) -> void:
	var s: Dictionary = sim.state
	for pair in [[a, b], [b, a]]:
		var told: Dictionary = newest_unknown(s, pair[0], pair[1])
		if told.is_empty() or sim.random_int("gossip", 0, 99) >= SHARE_CHANCE: continue
		var level: int = int(told.level) + (1 if sim.random_int("gossip", 0, 99) < GROW_CHANCE else 0)
		learn(s, int(pair[1].id), int(told.event), level)

## A trader setting out takes the newest news of the town they leave...
static func pack(s: Dictionary, trader: Dictionary, town: int) -> void:
	var newest: Array = []
	for entry in Chronicle.entries(s):
		if int(entry.town) == town and str(entry.kind) in NEWS_KINDS and int(s.tick) - int(entry.tick) < STALE_DAYS * DAY: newest.append(entry)
	for index in range(maxi(0, newest.size() - CARRY), newest.size()):
		learn(s, int(trader.id), int(newest[index].id), 1)   # second-hand already

## ...and tells it to the first few people at the next market.
static func unpack(s: Dictionary, trader: Dictionary, town: int) -> void:
	var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
	var listeners: Array = []
	for npc in s.residents.values():
		if int(npc.settlement) != town or int(npc.id) == int(trader.id) or int(npc.health) <= 0 or npc.occupation == "Child": continue
		var cell: Array = s.entities[str(npc.id)].cell
		listeners.append([absi(cell[0] - store[0]) + absi(cell[1] - store[1]), int(npc.id)])
	listeners.sort()
	for pair in listeners.slice(0, 3):
		for rumour in trader.get("rumours", []): learn(s, int(pair[1]), int(rumour.event), int(rumour.level))

## Once a day: families share what they heard, stale news is forgotten, and each town's news is
## marked as known there once a third of its grown-ups have heard it.
static func daily(s: Dictionary) -> void:
	if not s.has("residents"): return
	for household in s.get("households", {}).values():
		var members: Array = household.members.filter(func(id): return s.residents.has(str(id)))
		for a in members:
			for rumour in s.residents[str(a)].get("rumours", []).duplicate():
				for b in members:
					if b != a: learn(s, int(b), int(rumour.event), int(rumour.level))
	var adults: Dictionary = {}
	var heard: Dictionary = {}
	for npc in s.residents.values():
		npc.rumours = npc.get("rumours", []).filter(func(r): return int(s.tick) - int(r.heard) < STALE_DAYS * DAY and not Chronicle.find(s, int(r.event)).is_empty())
		if int(npc.get("health", 0)) <= 0 or npc.occupation == "Child": continue
		var town: String = str(npc.settlement)
		adults[town] = int(adults.get(town, 0)) + 1
		for rumour in npc.rumours:
			var key := "%s:%d" % [town, int(rumour.event)]
			heard[key] = int(heard.get(key, 0)) + 1
	for entry in Chronicle.entries(s):
		for town in adults:
			var count: int = int(heard.get("%s:%d" % [town, int(entry.id)], 0))
			if count * 3 >= int(adults[town]) and count > 0:
				if not entry.has("heard_in"): entry.heard_in = []
				if not int(town) in entry.heard_in: entry.heard_in.append(int(town))

## How `npc` tells the news, from their newest rumour: "" when they've heard nothing lately.
static func tell(s: Dictionary, npc: Dictionary) -> String:
	var rumours: Array = npc.get("rumours", [])
	for index in range(rumours.size() - 1, -1, -1):
		var entry: Dictionary = Chronicle.find(s, int(rumours[index].event))
		if entry.is_empty() or int(s.tick) - int(entry.tick) >= STALE_DAYS * DAY: continue
		var line: String = describe(s, entry, int(rumours[index].level))
		if not line.is_empty(): return line
	return ""

static func describe(s: Dictionary, entry: Dictionary, level: int) -> String:
	var victim: String = String(s.entities.get(str(entry.victim), {}).get("name", "someone"))
	var actor: String = String(s.entities.get(str(entry.actor), {}).get("name", "someone"))
	var town: String = String(s.get("settlements", {}).get(str(entry.town), {}).get("name", "town"))
	var by_player: bool = int(entry.actor) == int(s.get("player", -1))
	var who: String = "the stranger" if by_player else actor
	var lines: Dictionary = {
		"theft": ["%s robbed %s." % [who.capitalize(), victim], "They say %s robbed %s blind." % [who, victim], "I heard %s has been robbing folk all over %s!" % [who, town]],
		"murder": ["%s was killed, and %s did it." % [victim, who], "%s murdered %s in cold blood." % [who.capitalize(), victim], "They say %s killed %s and two others besides!" % [who, victim]],
		"shooting": ["%s shot at %s in %s." % [who.capitalize(), victim, town], "%s opened fire on %s!" % [who.capitalize(), victim], "A gunfight in %s! %s nearly killed half the town!" % [town, who.capitalize()]],
		"assault": ["%s hit %s." % [who.capitalize(), victim], "%s beat %s badly." % [who.capitalize(), victim], "%s nearly beat %s to death!" % [who.capitalize(), victim]],
		"discharge": ["Someone fired a gun in %s." % town, "There was shooting in %s!" % town, "Bullets flying all over %s, I heard!" % town],
		"death": ["%s has passed away." % victim, "%s has passed away, God rest them." % victim, "%s has passed away, God rest them." % victim],
		"birth": ["There's a new baby in %s: %s." % [town, victim], "A new baby in %s, a healthy one." % town, "A new baby in %s, a healthy one." % town],
		"migration": ["%s has packed up and left %s." % [actor, town], "%s left %s for good." % [actor, town], "%s left %s in a hurry, I heard." % [actor, town]]}
	var kind: String = str(entry.kind)
	if kind in ["assault_sheriff", "kick"]: kind = "assault"
	if not lines.has(kind): return ""
	return str(lines[kind][clampi(level, 0, 2)])
