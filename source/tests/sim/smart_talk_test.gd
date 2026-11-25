extends SceneTree
## Conversations that know what has happened: real news told once, with follow-ups; people bring up
## what you did to them; introductions; the barkeep's rumour for a drink marks the bandit camp; the
## Governor's pardon; talking at a hold-up; talking to the watch while tied up; making amends with
## someone you hit; long option lists go over pages. Money is conserved.
const Sim = preload("res://sim/core/simulation.gd")
const Conversation = preload("res://sim/player/conversation.gd")
const Dialogue = preload("res://sim/player/dialogue.gd")
const Chronicle = preload("res://sim/world/chronicle.gd")
const Society = preload("res://sim/factions/society.gd")
const Law = preload("res://sim/law/law.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func townsperson(s: Dictionary, town: int, occupation: String = "") -> Dictionary:
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != town or int(npc.health) <= 0: continue
		if occupation != "" and npc.occupation == occupation: return npc
		if occupation == "" and npc.occupation not in ["Sheriff", "Child", "Trader", "Governor", "Barkeep"]: return npc
	return {}

func ids(s: Dictionary, npc: Dictionary) -> Array:
	var all: Array = []
	for page in range(4):
		s.player_control.talk_page = page
		all += Dialogue.options(s, int(npc.id)).map(func(o): return o.id)
	s.player_control.talk_page = 0
	return all

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var npc: Dictionary = townsperson(s, 1)
	# Real news, told once, with follow-ups.
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	Chronicle.record(s, "outlaw_jailed", 1, int(sheriff.id), int(s.bandits.members[1]), s.entities[str(sheriff.id)].cell)
	var first: String = Conversation.news(s, npc)
	check(first.contains("locked up"), "News tells a real recent event (%s)" % first)
	check(Conversation.news(s, npc) != first, "...and doesn't tell it twice")
	Chronicle.record(s, "outlaw_jailed", 1, int(sheriff.id), int(s.bandits.members[2]), s.entities[str(sheriff.id)].cell)
	Conversation.news(s, npc)
	var opts: Array = ids(s, npc)
	check("c_where" in opts and "c_who" in opts, "After news you can ask where and who (%s)" % str(opts))
	var where: String = Conversation.perform(sim, npc, "c_where")
	check(where.contains("Right here in") or where.contains("Out in the wilds"), "Where was that? (%s)" % where)

	# They bring up what you did; introductions.
	var victim: Dictionary = townsperson(s, 2)
	Society.remember(s, int(victim.id), "robbed", int(s.player), "The stranger robbed me.")
	check(Conversation.answer(s, victim, "Hello.").begins_with("You robbed me"), "Someone you robbed brings it up")
	Conversation.perform(sim, npc, "c_introduce")
	check(bool(npc.get("knows_name", false)) and Conversation.opener(s, npc).contains(String(s.entities[str(s.player)].name).split(" ")[0]), "Introduced, they use your name")

	# The barkeep's rumour for the price of a drink marks the camp; money is conserved.
	var barkeep: Dictionary = townsperson(s, 3, "Barkeep")
	check(not barkeep.is_empty(), "Found the barkeep")
	check(Conversation.perform(sim, barkeep, "c_drink").contains("shut"), "Before the bar opens there's no drink (and no rumour)")
	while s.tick < 14400 + 15 * 600 or not load("res://sim/settlement/capital.gd").serving(s, barkeep):   # the afternoon, the bar open
		sim.step()
		if s.tick > 14400 * 2: break
	var coins: int = int(s.accounts[str(s.player)])
	var said: String = Conversation.perform(sim, barkeep, "c_drink")
	check(int(s.accounts[str(s.player)]) == coins - Conversation.DRINK, "The drink costs %d" % Conversation.DRINK)
	check(bool(s.player_status.known_places.get("bandit_camp", false)), "...and the rumour marks the bandit camp (%s)" % said)

	# The Governor pardons you (for a price).
	var governor: Dictionary = townsperson(s, 3, "Governor")
	Law.file(s, 2, "theft", {}, true)
	var treasury: String = str(s.settlements[str(governor.settlement)].warehouse)
	var topup: int = Conversation.PARDON - int(s.accounts[str(s.player)])
	if topup > 0:
		s.accounts[str(s.player)] = int(s.accounts[str(s.player)]) + topup
		s.accounts[treasury] = int(s.accounts[treasury]) - topup
	check("c_pardon" in ids(s, governor), "The Governor hears a plea for a pardon")
	Conversation.perform(sim, governor, "c_pardon")
	check(s.law.wanted.is_empty(), "Pardoned: wanted nowhere")

	# Making amends with someone you hit.
	var hit: Dictionary = {}
	for key in s.residents.keys():
		var r: Dictionary = s.residents[key]
		if int(r.settlement) == 1 and Brawl.temperament(r) == "confront" and r.occupation not in ["Sheriff", "Child", "Trader"]: hit = r; break
	var me: Array = s.entities[str(hit.id)].cell
	s.entities[str(s.player)].cell = [me[0] + 1, me[1]]
	Brawl.on_player_hit(sim, hit, s.entities[str(hit.id)], "punch", [-1, 0])
	check("c_amends" in ids(s, hit), "You can offer to make it right")
	Conversation.perform(sim, hit, "c_amends")
	check(hit.get("reporting", {}).is_empty() or str(hit.reporting.get("kind", "")) not in ["assault"], "Made right: they don't go to the sheriff")

	# Long lists go over pages.
	s.player_control.talk_page = 0
	var page0: Array = Dialogue.options(s, int(sheriff.id)).map(func(o): return o.id)
	check(page0.size() <= 7, "The window never lists more than seven (%d)" % page0.size())

	# At a hold-up and tied up.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	s2.tick = 14400 + 11 * 600
	var leader: Dictionary = s2.residents[str(s2.bandits.leader)]
	Bandits._start_demand(sim2, Bandits._members(s2))
	check("c_bluff" in Dialogue.options(s2, int(leader.id)).map(func(o): return o.id), "At a hold-up you can talk: bluff, coins only, stare them down")
	Bandits._home(sim2, "idle")
	var guard: Dictionary = s2.residents[str(s2.bandits.members[1])]
	s2.entities[str(s2.player)].cell = Bandits.post(s2)
	s2.player_control.captive = {"since": s2.tick, "stage": "tied", "progress": 0, "working": false}
	var post: Array = Bandits.post(s2)
	s2.entities[str(guard.id)].cell = [post[0] + 2, post[1]]
	check("c_gang_talk" in Dialogue.options(s2, int(guard.id)).map(func(o): return o.id), "Tied up, you can talk to the watch")
	check(sim2._captive_talk({"kind": "context_action", "payload": {"target": int(guard.id), "action": "c_gang_talk"}}), "...even though you can't otherwise act")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))
	print("Smart talk: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
