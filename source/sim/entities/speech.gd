extends RefCounted
## What villagers say. Lines are chosen deterministically from the "speech" random stream and kept
## in `state.speech` (a short rolling list) for the view to draw as speech bubbles.
## Ambient chatter: idle neighbours make small talk, and now and then someone greets the player.
const Brawl = preload("res://sim/combat/brawl.gd")
const LIFETIME := 45          # ticks a bubble stays up
const MAX_LINES := 30

const LINES: Dictionary = {
	"angry_first": ["Hey! What was that for?!", "Watch it, stranger!", "You'll regret that!", "Right, that's it!", "Oi! Keep your hands to yourself!"],
	"angry_beat": ["I warned you!", "You've done it now!", "That's twice! Come here!", "Enough! I'll teach you a lesson!", "You never learn, do you?!"],
	"give_up": ["Forget it, not worth it!", "Ah, to hell with you!", "I'm not chasing you all the way out here!", "Damn it all... Keep running, then!", "Bah! Not worth the walk back."],
	"knocked_down": ["Ugh...", "My head...", "Argh!", "Ow, my ribs..."],
	"got_up": ["You'll pay for that.", "I'm alright... no thanks to you.", "Uh... what happened?", "Phew..."],
	"robbed": ["Thief!", "Where's my stuff?!", "You went through my pockets!", "Give that back!"],
	"woke_caught": ["Hey! Get your hands off that!", "Thief! Thief!", "I saw that! Stop right there!"],
	"sheriff_warn": ["That's enough! Break it up!", "Stop that right now!", "Not in my town, stranger.", "I'm watching you."],
	"greet_scruffy": ["You look like you've been dragged through a hedge.", "Good grief, have a wash, stranger.", "Is that blood on you?", "Keep your distance, you're filthy.", "There's a well by the storehouse, you know."],
	"greet_cold": ["You've got a nerve, showing your face here.", "Hmph.", "Keep walking.", "We know what you did.", "Don't you come near my family."],
	"greet_warm": ["Good to see you again, friend!", "There you are! How have you been?", "Ah, a friendly face.", "Come by for supper some time.", "Always welcome here."],
	"greet_player": ["Hello there.", "Good to see a new face.", "Keep your boots dry, friend."],
	"greet_morning": ["Morning, traveller.", "Good morning.", "Early start, is it?", "Morning. Sleep well?"],
	"greet_day": ["Afternoon.", "Good day to you.", "Quiet day, isn't it?", "Warm one today."],
	"greet_evening": ["Evening, stranger.", "Good evening.", "Getting late, isn't it?", "Evening. Long day?"],
	"greet_night": ["You're up late.", "Bit late to be wandering about.", "Shouldn't you be abed?"],
	"smalltalk": ["Looks like rain later.", "The rye's coming along nicely.", "Prices at the market are odd today.", "Did you hear? A trader's been walking the road.", "I could do with a rest.", "Timber's going quickly this week.", "My back aches from the work.", "Have you seen the sheriff about?", "The days are getting shorter.", "Bread's ready soon, I think.", "That new house is coming along.", "Strange folk, these travellers."],
	"reply": ["Aye, I'd say so.", "Hah, you're not wrong.", "So I've heard.", "Don't get me started.", "Hmm, fair enough.", "Mm. Take care now.", "Tell me about it."],
	"scared": ["Gunshots! Get down!", "Somebody is shooting!", "Take cover!", "Run for it!", "Oh no, oh no..."],
	"drought": ["No rain in days. The rye's burning up.", "If it doesn't rain soon, there'll be nothing to cut.", "Dust and more dust. The fields are cracking.", "I've never seen the ground this dry."],
	"rain_relief": ["Rain at last! The fields needed that.", "Smell that? Rain on dry ground.", "That rain came just in time.", "The rye will pick up now, thank heaven."],
	"trader_pitch": ["Cheap planks, going east!", "Fine timber, fair prices!", "Best food on the Moss Road!"],
}

## A greeting for the part of the day, now and then a plain one.
static func _greeting(sim: RefCounted) -> String:
	if sim.random_int("speech", 0, 3) == 0: return "greet_player"
	return "greet_" + str(load("res://sim/world/day_clock.gd").phase(sim.state))

## Farmers talk about the weather when it matters: drought after 5 dry days, relief when it breaks.
static func weather_topic(s: Dictionary, npc: Dictionary) -> String:
	if str(npc.get("occupation", "")) != "Farmer": return "smalltalk"
	var region: Dictionary = load("res://sim/world/weather.gd").of_town(s, int(npc.settlement))
	if int(region.get("relief_until", 0)) > int(s.tick): return "rain_relief"
	if int(region.get("dry_days", 0)) >= 5: return "drought"
	return "smalltalk"

static func say(sim: RefCounted, speaker: int, topic: String, extra: String = "") -> void:
	var s: Dictionary = sim.state
	if not LINES.has(topic) or not s.entities.has(str(speaker)): return
	if not s.has("speech"): s.speech = []
	var options: Array = LINES[topic]
	var text: String = options[sim.random_int("speech", 0, options.size() - 1)]
	if not extra.is_empty(): text += " " + extra
	# One bubble per speaker at a time.
	for index in range(s.speech.size() - 1, -1, -1):
		if int(s.speech[index].speaker) == speaker: s.speech.remove_at(index)
	s.speech.append({"speaker": speaker, "text": text, "tick": s.tick, "until": s.tick + LIFETIME})
	while s.speech.size() > MAX_LINES: s.speech.pop_front()

static func _idle(s: Dictionary, npc: Dictionary) -> bool:
	return npc.health > 0 and npc.get("knock", {}).is_empty() and npc.get("brawl", {}).is_empty() and npc.get("attack", {}).is_empty() \
		and npc.get("sleeping", {}).is_empty() and npc.get("migration", {}).is_empty() and s.tick >= int(npc.get("talk_until", 0)) and npc.occupation not in ["Trader", "Bandit"] \
		and npc.get("cover_cycle", {}).is_empty() and npc.get("fear", {}).is_empty() and npc.get("arrest", {}).is_empty() and npc.get("reporting", {}).is_empty() and npc.get("collar", {}).is_empty()   # nobody chats about the weather mid-gunfight

## Every 120 ticks: expire old bubbles, let two idle neighbours chat, and greet the player.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("residents") or s.tick % 120 != 0: return
	if s.has("speech"):
		for index in range(s.speech.size() - 1, -1, -1):
			if int(s.speech[index].until) < s.tick: s.speech.remove_at(index)
	var keys: Array = s.residents.keys()
	keys.sort()
	var talkers: Array = []
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if _idle(s, npc): talkers.append(npc)
	# One conversation per town per cycle, with a chance of staying quiet.
	var spoke_in: Dictionary = {}
	for a in talkers:
		if spoke_in.has(a.settlement) or sim.random_int("speech", 0, 99) >= 45: continue
		var cell_a: Array = s.entities[str(a.id)].cell
		for b in talkers:
			if b.id <= a.id or b.settlement != a.settlement: continue
			var cell_b: Array = s.entities[str(b.id)].cell
			if absi(cell_a[0] - cell_b[0]) > 4 or absi(cell_a[1] - cell_b[1]) > 4: continue
			say(sim, a.id, weather_topic(s, a))
			say(sim, b.id, "reply")
			load("res://sim/entities/gossip.gd").chat(sim, a, b)   # and they pass on the news
			a.talk_until = s.tick + 900
			b.talk_until = s.tick + 900
			spoke_in[a.settlement] = true
			break
	var player: Array = s.entities[str(s.player)].cell
	for npc in talkers:
		if npc.occupation == "Bandit": continue   # bandits have their own words for you (bandits.gd)
		if npc.occupation == "Sheriff" and sim.random_int("speech", 0, 99) < 40: continue
		var cell: Array = s.entities[str(npc.id)].cell
		if absi(cell[0] - player[0]) <= 3 and absi(cell[1] - player[1]) <= 3 and s.tick >= int(npc.get("greeted_tick", 0)):
			if Brawl.player_down(s) or sim.random_int("speech", 0, 99) >= 60: continue
			# What they remember of you colours the greeting (society.gd: opinion).
			var feeling: int = load("res://sim/factions/society.gd").opinion(s, int(npc.id), int(s.player))
			var scruffy: bool = load("res://sim/player/look.gd").score(s) <= -40   # filthy or bloodied (look.gd)
			say(sim, npc.id, "greet_cold" if feeling <= -30 else ("greet_warm" if feeling >= 40 else ("sheriff_warn" if scruffy and npc.occupation == "Sheriff" else ("greet_scruffy" if scruffy else _greeting(sim)))))
			npc.greeted_tick = s.tick + 3000
			npc.talk_until = s.tick + 300
			break
