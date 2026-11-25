extends RefCounted
## Talking with tone, and talking your way out of trouble. Small talk comes in three tones,
## friendly, firm and threatening, and how it lands depends on who you're talking to: their
## temper (fixed per person), how they feel about you, and a little luck. Facing a sheriff with his
## gun on you, you can offer him coins to look the other way or try to talk your way out of a
## minor charge; get it wrong and it's one more crime. All deterministic (seeded streams).
const Society = preload("res://sim/factions/society.gd")
const Reputation = preload("res://sim/factions/reputation.gd")
const TEMPERS := ["calm", "warm", "gruff", "nervous", "proud"]
const AGAIN_TICKS := 600     # the same small talk within an hour gets "We just talked."
## How well each tone suits each temper (added to the roll).
const FIT := {
	"friendly": {"calm": 5, "warm": 15, "gruff": -10, "nervous": 10, "proud": 0},
	"firm": {"calm": 10, "warm": 0, "gruff": 10, "nervous": -10, "proud": -5},
	"threaten": {"calm": -20, "warm": -25, "gruff": -30, "nervous": 25, "proud": -40}}
const LINES := {
	"friendly": "You look like good people. How's life treating you?",
	"firm": "I'm new here. Tell me straight: how do things stand?",
	"threaten": "You'd do well to be friendly to me, friend."}
const REPLIES := {
	"friendly": [["Can't complain, stranger. Kind of you to ask.", "Not bad at all! You're welcome round here."], ["Hm. Busy, is how.", "Life's life."], ["Save the sweet talk.", "Do I know you?"]],
	"firm": [["Fair enough. Folk here work hard and mind their business; do the same and you'll be fine.", "Straight talk, I like that. Things are quiet, mostly."], ["Things stand as they stand.", "Ask the sheriff."], ["Who are you to ask?", "That's none of your affair."]],
	"threaten": [["A-all right, all right! No need for that.", "Easy now... what do you want?"], ["I'm not looking for trouble.", "Mind your tone."], ["Is that a threat? Get out of my sight.", "Try it, stranger. See what happens."]]}
const BRIBES := [10, 25, 50]

static func temper(npc: Dictionary) -> String:
	if npc.has("temper"): return str(npc.temper)
	if str(npc.get("occupation", "")) == "Sheriff": return "proud"
	return TEMPERS[posmod(int(npc.id) * 7 + 3, TEMPERS.size())]   # stable from the id, nothing to save

## The small-talk options for the Talk tab.
static func tone_options(s: Dictionary, npc: Dictionary) -> Array:
	var result: Array = []
	for tone in ["friendly", "firm", "threaten"]:
		result.append({"id": "say_" + tone, "label": LINES[tone], "enabled": true, "reason": ""})
	return result

## Says it; returns their answer as the notice ("First: ..."). Tone shifts how they feel.
static func say(sim: RefCounted, npc: Dictionary, tone: String) -> String:
	var s: Dictionary = sim.state
	var first: String = String(s.entities[str(npc.id)].name).split(" ")[0]
	var key := "talked_" + tone
	if s.tick < int(npc.get(key, -AGAIN_TICKS)) + AGAIN_TICKS: return "%s: We just talked, didn't we?" % first
	npc[key] = int(s.tick)
	var feeling: int = Society.opinion(s, int(npc.id), int(s.player))
	var mood: String = temper(npc)
	var score: int = feeling / 2 + int(FIT[tone].get(mood, 0)) + sim.random_int("talk", 0, 30) - 10
	var band: int = 0 if score >= 15 else (1 if score >= -5 else 2)
	var options: Array = REPLIES[tone][band]
	var reply: String = options[sim.random_int("talk", 0, options.size() - 1)]
	var player: int = int(s.player)
	match tone:
		"friendly":
			if band == 0: Society.remember(s, int(npc.id), "pleasant", player, "The stranger was friendly.")
			elif band == 2: Society.remember(s, int(npc.id), "insulted", player, "The stranger pestered me.")
		"firm":
			if band == 0: Society.remember(s, int(npc.id), "pleasant", player, "The stranger spoke plainly.")
		"threaten":
			Society.remember(s, int(npc.id), "threatened", player, "The stranger threatened me.")
			if band == 0:
				# Cowed: they'll give you a better price, for now.
				s.player_control.trade_terms = {"target": int(npc.id), "pct": -15, "haggled": true}
			elif npc.occupation == "Sheriff" or band == 2:
				npc.anger = mini(100, int(npc.get("anger", 0)) + 30)
	load("res://sim/law/law.gd")._say(sim, int(npc.id), reply)
	return "%s: %s" % [first, reply]

# --- talking your way out ------------------------------------------------------------------------

## The sheriff holding you (standoff or walking up to cuff you), or {}.
static func arresting_sheriff(s: Dictionary, npc: Dictionary) -> bool:
	return npc.get("occupation", "") == "Sheriff" and str(npc.get("arrest", {}).get("phase", "")) in ["standoff", "approach", "pursue"]

## Wanted in his town and talking to a sheriff (not at gunpoint): turn yourself in, or pay a fine.
static func wanted_options(s: Dictionary, npc: Dictionary) -> Array:
	if npc.get("occupation", "") != "Sheriff" or arresting_sheriff(s, npc): return []
	var Law = load("res://sim/law/law.gd")
	if Law.wanted_hours(s, int(npc.settlement)) <= 0: return []
	var Notoriety = load("res://sim/law/notoriety.gd")
	var fine: int = Notoriety.fine(s, int(npc.settlement))
	var coins: int = int(s.get("accounts", {}).get(str(s.player), 0))
	return [{"id": "turn_in", "label": "I'd like to turn myself in.", "enabled": true, "reason": ""},
		{"id": "pay_fine", "label": "I'll pay the fine." if fine <= 0 else "I'll pay the fine (%d coins)." % fine, "enabled": fine > 0 and coins >= fine,
			"reason": "Too serious for a fine" if fine <= 0 else ("You haven't got %d" % fine if coins < fine else "")}]

static func trouble_options(s: Dictionary, npc: Dictionary) -> Array:
	if not arresting_sheriff(s, npc): return []
	var record: Dictionary = s.get("law", {}).get("wanted", {}).get(str(npc.settlement), {})
	var murder: bool = "murder" in record.get("crimes", [])
	var coins: int = int(s.get("accounts", {}).get(str(s.player), 0))
	var result: Array = []
	for amount in BRIBES:
		result.append({"id": "bribe_%d" % amount, "label": "Here's %d coins. You never saw me." % amount,
			"enabled": coins >= amount and not murder, "reason": "Not for murder" if murder else ("You haven't got %d" % amount if coins < amount else "")})
	var minor: bool = int(record.get("hours", 0)) <= 3
	result.append({"id": "persuade", "label": "It was a misunderstanding, Sheriff. It won't happen again.", "enabled": minor, "reason": "" if minor else "Too serious to talk away"})
	return result

## The chance (percent) a bribe of `amount` works on this sheriff.
static func bribe_chance(s: Dictionary, npc: Dictionary, amount: int) -> int:
	var feeling: int = Society.opinion(s, int(npc.id), int(s.player))
	var loyalty: int = int(s.settlements.get(str(npc.settlement), {}).get("mood", {}).get("loyalty", 50))
	return clampi(20 + amount / 2 + (50 - loyalty) / 2 + feeling / 4, 5, 90)

static func bribe(sim: RefCounted, npc: Dictionary, amount: int) -> String:
	var s: Dictionary = sim.state
	var Law = load("res://sim/law/law.gd")
	var first: String = String(s.entities[str(npc.id)].name).split(" ")[0]
	var town: int = int(npc.settlement)
	if not arresting_sheriff(s, npc): return "%s isn't after you." % first
	if "murder" in s.get("law", {}).get("wanted", {}).get(str(town), {}).get("crimes", []): return "%s: Not for murder. Hands up." % first
	if int(s.accounts.get(str(s.player), 0)) < amount: return "You haven't got %d coins." % amount
	if sim.random_int("bribe", 0, 99) < bribe_chance(s, npc, amount):
		s.accounts[str(s.player)] -= amount
		s.accounts[str(npc.id)] = int(s.accounts.get(str(npc.id), 0)) + amount
		_let_go(s, town)
		Society.remember(s, int(npc.id), "bribed", int(s.player), "The stranger paid me to look away.")
		Law._say(sim, int(npc.id), "I didn't see anything. Move along.")
		return "%s pockets the %d coins and looks the other way." % [first, amount]
	Law._say(sim, int(npc.id), "Trying to buy the law? That's another charge.")
	Law.crime(s, town, "bribery", int(npc.id))
	return "%s won't be bought. Now it's bribery too." % first

static func persuade(sim: RefCounted, npc: Dictionary) -> String:
	var s: Dictionary = sim.state
	var Law = load("res://sim/law/law.gd")
	var first: String = String(s.entities[str(npc.id)].name).split(" ")[0]
	var town: int = int(npc.settlement)
	if not arresting_sheriff(s, npc): return "%s isn't after you." % first
	if int(s.law.wanted.get(str(town), {}).get("hours", 0)) > 3: return "%s: Too serious to talk away." % first
	var chance: int = clampi(30 + Society.opinion(s, int(npc.id), int(s.player)) / 2 + Reputation.value(s, town) / 4, 5, 85)
	if sim.random_int("bribe", 0, 99) < chance:
		_let_go(s, town)
		Law._say(sim, int(npc.id), "Fine. Once. Don't make me regret it.")
		return "%s lowers his gun: \"Once. Don't make me regret it.\"" % first
	Law._say(sim, int(npc.id), "Save it for the judge.")
	return "%s isn't having it." % first

## The town's sheriffs stand down and the slate there is wiped.
static func _let_go(s: Dictionary, town: int) -> void:
	var Law = load("res://sim/law/law.gd")
	for sheriff in Law.sheriffs(s, town):
		if str(sheriff.get("arrest", {}).get("phase", "")) in ["standoff", "approach", "pursue", "backup", "assist"]:
			sheriff.arrest = {}
			sheriff.status = ""
	s.law.wanted.erase(str(town))
	var pc: Dictionary = s.player_control
	pc.surrender = false
