extends RefCounted
## Conversations that know what has happened. People open with what they remember of you (memories,
## wanted, reputation); "Heard any news?" tells real events from the chronicle and gossip, each
## once, with follow-ups ("Where was that?", "Who did it?"); you can introduce yourself so they use
## your name; and particular people have particular things to talk about: the sheriff (the bandit
## camp, bounties), the barkeep (rumours for the price of a drink), the Governor (a pardon), the
## bandits at a hold-up (hand over only the coins, bluff, stare them down), the night watch while
## you're tied up, a jailed bandit, and someone you've just hit (apologise and make it right).
## All in the simulation and deterministic (stream "talk"); the window only lists these options.
const Society = preload("res://sim/factions/society.gd")
const Chronicle = preload("res://sim/world/chronicle.gd")
const NEWS_DAYS := 3
const DAY := 14400
const DRINK := 3            # coins for the barkeep's drink (and a rumour)
const PARDON := 200         # coins for the Governor's pardon (free once you've cleared the bandits)
const AMENDS := 10          # coins to make it right with someone you hit
const NEWS_KINDS := ["theft", "murder", "shooting", "assault", "discharge", "death", "birth", "migration", "body_found",
	"outlaw_jailed", "outlaw_killed", "robbed_by_bandits", "bandits_cleared", "bandit_camp", "fine_paid"]

static func _first(s: Dictionary, id: int) -> String:
	return String(s.entities.get(str(id), {}).get("name", "Someone")).split(" ")[0]

static func _player_name(s: Dictionary) -> String:
	return String(s.entities[str(s.player)].name).split(" ")[0]

static func _status(s: Dictionary, key: String, fallback):
	return load("res://sim/player/player_status.gd").part(s, key, fallback)

# --- what they open with ---------------------------------------------------------------------------

## A word about you before they answer, from what they remember (or "" for nothing in particular).
static func opener(s: Dictionary, npc: Dictionary) -> String:
	var strongest: Dictionary = {}
	var weight := 0
	for memory in npc.get("memories", []):
		if int(memory.subject) != int(s.player): continue
		var w: int = Society.current_weight(s, memory)
		if absi(w) > absi(weight): weight = w; strongest = memory
	var name: String = _player_name(s) if bool(npc.get("knows_name", false)) else ""
	var you: String = name if name != "" else "stranger"
	if not strongest.is_empty() and absi(weight) >= 8:
		match str(strongest.kind):
			"killed_kin": return "You've got some nerve, talking to me after what you did."
			"assaulted": return "You hit me, %s. I haven't forgotten." % you
			"robbed": return "You robbed me. Don't think I don't know it."
			"shot_at": return "You shot at me. Keep your distance."
			"saw_murder": return "I saw what you did. I'll keep this short."
			"saw_crime": return "I saw what you did the other day."
			"threatened": return "After your threats? Make it quick."
			"saved_life": return "%s! I owe you my life." % you.capitalize()
			"helped", "gift", "delivered_goods": return "Good to see you, %s." % you
	if load("res://sim/law/notoriety.gd").known(s, int(npc.settlement)): return "I know who you are. Say your piece and go."
	for entry in s.get("chronicle", []):
		if str(entry.kind) == "bandits_cleared" and int(entry.actor) == int(s.player): return "You're the one who cleared out the bandits! Good to meet you, %s." % you
	if name != "": return "Hello again, %s." % name
	return ""

## Prefixes an answer with their opener.
static func answer(s: Dictionary, npc: Dictionary, line: String) -> String:
	var open: String = opener(s, npc)
	return line if open.is_empty() else open + " " + line

# --- news ------------------------------------------------------------------------------------------

## Real news: a recent event this person knows (gossip, or something in their town), not yet told
## to you by them. Each piece once; then "nothing new".
static func news(s: Dictionary, npc: Dictionary) -> String:
	var told: Array = npc.get("told_you", [])
	var Gossip = load("res://sim/entities/gossip.gd")
	var candidates: Array = []
	for rumour in npc.get("rumours", []):
		var entry: Dictionary = Chronicle.find(s, int(rumour.event))
		if not entry.is_empty(): candidates.append([entry, int(rumour.level)])
	for entry in Chronicle.recent(s, int(s.tick) - NEWS_DAYS * DAY, int(npc.settlement), NEWS_KINDS):
		candidates.append([entry, 0])
	for entry in Chronicle.recent(s, int(s.tick) - NEWS_DAYS * DAY, 0, ["bandits_cleared", "bandit_camp", "outlaw_jailed", "robbed_by_bandits"]):
		candidates.append([entry, 0])
	candidates.sort_custom(func(a, b) -> bool: return int(a[0].tick) > int(b[0].tick))
	for pair in candidates:
		var entry: Dictionary = pair[0]
		if int(entry.id) in told: continue
		if int(s.tick) - int(entry.tick) >= 14 * DAY: continue
		var line: String = describe(s, entry, int(pair[1]))
		if line.is_empty(): line = Gossip.describe(s, entry, int(pair[1]))
		if line.is_empty(): continue
		told.append(int(entry.id))
		while told.size() > 24: told.pop_front()
		npc.told_you = told
		s.player_control.last_news = {"npc": int(npc.id), "event": int(entry.id)}
		return line
	if not told.is_empty(): return "Nothing new since we last talked. " + load("res://sim/economy/stall_service.gd").news(s, npc)
	return load("res://sim/economy/stall_service.gd").news(s, npc)

## Lines for the kinds gossip.gd doesn't tell.
static func describe(s: Dictionary, entry: Dictionary, _level: int) -> String:
	var victim: String = String(s.entities.get(str(entry.victim), {}).get("name", "someone"))
	var actor: String = String(s.entities.get(str(entry.actor), {}).get("name", "someone"))
	var town: String = String(s.get("settlements", {}).get(str(entry.town), {}).get("name", "town"))
	var by_you: bool = int(entry.actor) == int(s.player)
	match str(entry.kind):
		"body_found": return "They found %s dead. The sheriff's looking into it." % victim
		"outlaw_jailed": return "%s locked up one of those bandits in %s. Caught him bold as brass in the street." % [actor, town]
		"outlaw_killed": return "One of the bandits was shot dead in a fight with the law."
		"robbed_by_bandits": return "The bandits out in the wilds robbed %s." % ("you, I hear" if int(entry.victim) == int(s.player) else victim)
		"bandits_cleared": return ("You drove the bandits out! The whole valley's talking about it." if by_you else "Somebody drove the bandits out of their camp.")
		"bandit_camp": return "There's a new gang camped out in the wilds. Stay on the roads."
		"fine_paid": return "%s paid a fine to the sheriff here." % ("You" if by_you else actor)
	return ""

# --- the options -----------------------------------------------------------------------------------

static func _opt(id: String, label: String, enabled: bool = true, reason: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "reason": reason}

## Situational options for this person, most pressing first.
static func options(s: Dictionary, npc: Dictionary) -> Array:
	var result: Array = []
	var pc: Dictionary = s.player_control
	var coins: int = int(s.get("accounts", {}).get(str(s.player), 0))
	var Bandits = load("res://sim/factions/bandits.gd")
	var is_bandit: bool = int(npc.get("bandit", 0)) != 0
	# The bandits' hold-up: talk instead of fight.
	if is_bandit and str(s.get("bandits", {}).get("phase", "")) == "demand" and int(npc.id) == int(s.bandits.leader):
		result.append(_opt("c_coins_only", "Here, take the coins. Leave me the gun."))
		result.append(_opt("c_bluff", "The sheriff's right behind me. Think it over."))
		result.append(_opt("c_stare", "Back off, or you'll regret it."))
		result.append(_opt("c_join", "Let me ride with you."))
		return result
	# Tied up: the watch.
	if is_bandit and Bandits.captive(s):
		result.append(_opt("c_loosen", "These ropes are cutting me in half. Loosen them, friend."))
		result.append(_opt("c_promise", "Let me go and there's money in it for you."))
		result.append(_opt("c_gang_talk", "Quiet night. How long have you lot been out here?"))
		return result
	# A bandit in the cells.
	if is_bandit and not npc.get("jailed", {}).is_empty():
		result.append(_opt("c_where_camp", "Where's your camp?"))
		result.append(_opt("c_how_many", "How many of you are out there?"))
		return result
	# Someone you just hit and who is standing up to you, or who remembers it.
	if not is_bandit and (npc.get("reporting", {}).has("hold_until") or _hurt_by_you(s, npc)) and not bool(npc.get("amends", false)):
		result.append(_opt("c_amends", "I'm sorry. Let me make it right (%d coins)." % AMENDS, coins >= AMENDS, "" if coins >= AMENDS else "You haven't got %d" % AMENDS))
	# Follow-ups on what they just told you.
	var last: Dictionary = pc.get("last_news", {})
	if int(last.get("npc", 0)) == int(npc.id):
		var entry: Dictionary = Chronicle.find(s, int(last.get("event", 0)))
		if not entry.is_empty():
			result.append(_opt("c_where", "Where was that?"))
			if int(entry.actor) != 0: result.append(_opt("c_who", "Who did it?"))
	if not bool(npc.get("knows_name", false)) and not is_bandit:
		result.append(_opt("c_introduce", "I'm %s, by the way." % _player_name(s)))
	match str(npc.get("occupation", "")):
		"Sheriff":
			if not load("res://sim/law/investigation.gd").suspect_case(s, npc).is_empty():
				result.push_front(_opt("c_confess", "...All right. It was me."))
				result.push_front(_opt("c_deny", "I had nothing to do with it."))
			if s.has("bandits") and not bool(s.bandits.get("cleared", false)) and not _knows_camp(s):
				result.append(_opt("c_camp", "Any trouble out in the wilds?"))
		"Barkeep":
			result.append(_opt("c_drink", "A drink, and whatever you're hearing (%d coins)." % DRINK, coins >= DRINK, "" if coins >= DRINK else "You haven't got %d" % DRINK))
		"Governor":
			var wanted: bool = not s.get("law", {}).get("wanted", {}).is_empty()
			if wanted:
				var free: bool = _cleared_bandits(s)
				var cost: int = 0 if free else PARDON
				result.append(_opt("c_pardon", "I'm asking for a pardon, Governor." if free else "I'm asking for a pardon (%d coins)." % PARDON, coins >= cost, "" if coins >= cost else "You haven't got %d" % cost))
			result.append(_opt("c_business", "How's the town doing, Governor?"))
	return result

static func _hurt_by_you(s: Dictionary, npc: Dictionary) -> bool:
	for memory in npc.get("memories", []):
		if int(memory.subject) == int(s.player) and str(memory.kind) == "assaulted" and Society.current_weight(s, memory) <= -8: return true
	return false

static func _knows_camp(s: Dictionary) -> bool:
	return bool(s.get("player_status", {}).get("known_places", {}).get("bandit_camp", false))   # read only (the window asks)

static func mark_camp(s: Dictionary) -> void:
	var places: Dictionary = _status(s, "known_places", {})
	places.bandit_camp = true

static func _cleared_bandits(s: Dictionary) -> bool:
	for entry in s.get("chronicle", []):
		if str(entry.kind) == "bandits_cleared" and int(entry.actor) == int(s.player): return true
	return false

# --- what happens --------------------------------------------------------------------------------

static func perform(sim: RefCounted, npc: Dictionary, id: String) -> String:
	var s: Dictionary = sim.state
	var first: String = _first(s, int(npc.id))
	var line: String = _reply(sim, npc, id)
	if line.is_empty(): return ""
	load("res://sim/law/law.gd")._say(sim, int(npc.id), line.left(70))
	return "%s: %s" % [first, line]

static func _reply(sim: RefCounted, npc: Dictionary, id: String) -> String:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var Bandits = load("res://sim/factions/bandits.gd")
	match id:
		"c_deny", "c_confess":
			return load("res://sim/law/investigation.gd").answer(sim, npc, id == "c_confess")
		"c_introduce":
			npc.knows_name = true
			Society.remember(s, int(npc.id), "pleasant", int(s.player), "We were introduced.")
			return "Pleased to meet you, %s. I'm %s." % [_player_name(s), String(s.entities[str(npc.id)].name)]
		"c_where":
			var entry: Dictionary = Chronicle.find(s, int(pc.get("last_news", {}).get("event", 0)))
			if entry.is_empty(): return "I don't rightly know."
			var town: String = str(s.get("settlements", {}).get(str(entry.town), {}).get("name", ""))
			var Gunfire = load("res://sim/combat/gunfire.gd")
			var near: int = Gunfire.town_of(s, entry.cell)
			if near != 0: return "Right here in %s, near the %s." % [s.settlements[str(near)].name, _landmark(s, entry.cell)]
			return "Out in the wilds, %s of %s." % [_direction(s, entry.cell, int(entry.town) if int(entry.town) != 0 else 1), town if town != "" else "town"]
		"c_who":
			var entry: Dictionary = Chronicle.find(s, int(pc.get("last_news", {}).get("event", 0)))
			if entry.is_empty() or int(entry.actor) == 0: return "Nobody knows."
			if int(entry.actor) == int(s.player):
				var saw: bool = int(npc.id) in entry.get("witnesses", [])
				return "Funny you should ask. It was you, wasn't it?" if saw else "Some stranger, they say. Dressed a lot like you, come to think of it."
			return "%s, so they say." % String(s.entities.get(str(entry.actor), {}).get("name", "someone"))
		"c_camp":
			mark_camp(s)
			return "There's a gang camped out in the wilds, far from any town. I've marked it on your map. Steer clear, or bring them in if you're brave."
		"c_drink":
			var poured: String = load("res://sim/settlement/capital.gd").buy_drink(s, npc)   # pays the barkeep, quenches your thirst
			if not poured.begins_with("You buy"): return poured.replace("The bar isn't open just now.", "Bar's shut. Come back this afternoon.")
			return _rumour(sim, npc)
		"c_pardon":
			var cost: int = 0 if _cleared_bandits(s) else PARDON
			if cost > 0 and not _pay(s, int(npc.id), cost, true): return "A pardon isn't free."
			var law: Dictionary = load("res://sim/law/law.gd")._law(s)
			law.wanted = {}
			load("res://sim/world/chronicle.gd").record(s, "pardoned", int(npc.settlement), int(npc.id), int(s.player), s.entities[str(s.player)].cell, {"coins": cost})
			return "For what you did with those bandits, the slate's clean. Don't make me regret it." if cost == 0 else "Very well. Your record is wiped, in every town. Don't make me regret it."
		"c_business":
			var town: Dictionary = s.settlements[str(npc.settlement)]
			var people: int = s.residents.values().filter(func(n: Dictionary) -> bool: return int(n.settlement) == int(town.id) and int(n.health) > 0).size()
			var purse: int = int(s.accounts.get(str(town.warehouse), 0))
			return "%d souls in %s, and %d coins in the town purse. %s" % [people, town.name, purse, "The bandits are the worry." if s.has("bandits") and not bool(s.bandits.get("cleared", false)) else "Quiet, thank the Lord."]
		"c_amends":
			if not _pay(s, int(npc.id), AMENDS): return "Words are cheap."
			npc.amends = true
			var report: Dictionary = npc.get("reporting", {})
			if not report.is_empty() and str(report.get("kind", "")) in ["assault", "kick"]:
				npc.reporting = {}
				npc.path = []
				npc.status = "Mollified"
			Society.remember(s, int(npc.id), "gift", int(s.player), "The stranger paid to make it right.")
			return "...Fine. We'll say no more about it. Keep your hands to yourself."
		# --- the bandits ---
		"c_coins_only":
			var leader: Dictionary = npc
			if sim.random_int("talk", 0, 99) < 55:
				var coins: int = int(s.accounts.get(str(s.player), 0))
				s.accounts[str(s.player)] = 0
				s.accounts[str(leader.id)] = int(s.accounts.get(str(leader.id), 0)) + coins
				Bandits._home(sim, "idle")
				s.bandits.cooldown_until = s.tick + Bandits.COOLDOWN
				return "Coins'll do. Now get lost before I change my mind."
			s.bandits.since = s.tick - Bandits.DEMAND_WAIT + 20   # the countdown runs short
			return "Did I ask for half? The gun too. Now."
		"c_bluff":
			var odds: int = 25 + (20 if load("res://sim/factions/reputation.gd").value(s, 1) >= 30 else 0)
			if sim.random_int("talk", 0, 99) < odds:
				Bandits._home(sim, "idle")
				s.bandits.cooldown_until = s.tick + Bandits.COOLDOWN / 2
				return "...Lawmen? Not worth it. Go on, then. Get."
			Bandits._start_fight(sim, Bandits._members(s).filter(func(n): return Bandits._able(s, n)), false)
			return "Nice try. Light him up, boys!"
		"c_stare":
			var feared: bool = _cleared_bandits(s) or _bandits_you_killed(s) >= 2
			if feared and sim.random_int("talk", 0, 99) < 70:
				Bandits._home(sim, "idle")
				s.bandits.cooldown_until = s.tick + Bandits.COOLDOWN
				return "...Easy. Easy. We know who you are. No trouble here."
			Bandits._start_fight(sim, Bandits._members(s).filter(func(n): return Bandits._able(s, n)), false)
			return "You and whose army?"
		"c_join":
			return "Ha! Ride with us? Prove yourself first. Hand over your gun and we'll talk."
		"c_loosen":
			var c: Dictionary = pc.get("captive", {})
			if c.is_empty(): return ""
			if load("res://sim/player/talk.gd").temper(npc) in ["warm", "nervous"] and sim.random_int("talk", 0, 99) < 35:
				c.progress = int(c.get("progress", 0)) + 150
				return "...Fine. Don't make me regret it."
			return "Cutting you in half's the idea."
		"c_promise":
			var c2: Dictionary = pc.get("captive", {})
			if c2.is_empty(): return ""
			if sim.random_int("talk", 0, 99) < 20:
				c2.progress = int(c2.get("progress", 0)) + 200
				npc.promised = true
				return "How much money? ...Keep talking. And keep quiet."
			return "And what money would that be? We've got all of yours."
		"c_gang_talk":
			var n: int = Bandits._members(s).filter(func(m): return Bandits._able(s, m)).size()
			return "Long enough. %d of us now. I walk the round every couple of hours; the rest sleep like the dead." % n
		"c_where_camp":
			mark_camp(s)
			return "...Out past the far woods, away from the roads. You'll find it on your map. Won't do you any good."
		"c_how_many":
			var n2: int = Bandits._members(s).filter(func(m): return Bandits._able(s, m) and not load("res://sim/law/outlaw_arrest.gd").away(m)).size()
			return "%d, last I saw. And one always on watch at night." % n2
	return ""

static func _bandits_you_killed(s: Dictionary) -> int:
	var count := 0
	for id in s.get("bandits", {}).get("members", []):
		var npc: Dictionary = s.residents.get(str(id), {})
		if not npc.is_empty() and int(npc.health) <= 0: count += 1
	return count

## The player pays `amount` to `to` (or to the town purse). False if they can't.
static func _pay(s: Dictionary, to: int, amount: int, to_town: bool = false) -> bool:
	var coins: int = int(s.accounts.get(str(s.player), 0))
	if coins < amount: return false
	var key: String = str(to)
	if to_town:
		var npc: Dictionary = s.residents.get(str(to), {})
		key = str(s.settlements[str(npc.settlement)].warehouse)
	s.accounts[str(s.player)] = coins - amount
	s.accounts[key] = int(s.accounts.get(key, 0)) + amount
	return true

## The barkeep's rumour: where the camp is (first time), then the freshest real news, then talk.
static func _rumour(sim: RefCounted, npc: Dictionary) -> String:
	var s: Dictionary = sim.state
	if s.has("bandits") and not bool(s.bandits.get("cleared", false)) and not _knows_camp(s):
		mark_camp(s)
		return "Here's one for you: there's a gang camped out in the wilds. I've seen the smoke. Marked it on your map."
	var told: String = news(s, npc)
	return "On the house, the gossip: " + told

static func _landmark(s: Dictionary, cell: Array) -> String:
	var World = load("res://sim/world/world_db.gd")
	var building: int = World.inside_building(s, cell)
	if building != 0: return String(s.entities[str(building)].get("name", "houses")).to_lower()
	return "square" if load("res://sim/world/town_layout.gd").on_road(s, cell) else "edge of town"

static func _direction(s: Dictionary, cell: Array, town: int) -> String:
	var store: Array = s.entities[str(s.settlements[str(town)].warehouse)].cell
	var d := Vector2(cell[0] - store[0], cell[1] - store[1])
	if absf(d.x) > absf(d.y): return "east" if d.x > 0 else "west"
	return "south" if d.y > 0 else "north"
