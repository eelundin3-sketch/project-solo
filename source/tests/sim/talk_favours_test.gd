extends SceneTree
## Talking with tone, talking your way out, and favours: small talk lands by temper and feeling;
## a threat cows the nervous (cheaper prices) and angers the law; a sheriff with his gun on you
## can be bribed (not for murder) or, for a small thing, talked round; and a family with a bare
## pantry asks for bread, pays when you bring it, and remembers it. The journal lists it all.
const Sim = preload("res://sim/core/simulation.gd")
const Talk = preload("res://sim/player/talk.gd")
const Requests = preload("res://sim/player/requests.gd")
const Dialogue = preload("res://sim/player/dialogue.gd")
const Context = preload("res://sim/player/context_actions.gd")
const Society = preload("res://sim/factions/society.gd")
const Law = preload("res://sim/law/law.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)

func _world() -> Array:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 6000
	for npc in s.residents.values(): npc.sleeping = {}
	return [sim, s]

func _villager(s: Dictionary, temper: String) -> Dictionary:
	for npc in s.residents.values():
		if npc.occupation not in ["Sheriff", "Child", "Trader"] and Talk.temper(npc) == temper: return npc
	for npc in s.residents.values():
		if npc.occupation not in ["Sheriff", "Child", "Trader"]: npc.temper = temper; return npc
	return {}

## A sheriff of town 1 holding the player at gunpoint for `crime`.
func _held(sim: RefCounted, s: Dictionary, crime: String) -> Dictionary:
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	Law.file(s, 1, crime, {}, true)
	sheriff.arrest = {"phase": "standoff", "since": s.tick}
	return sheriff

func _initialize() -> void:
	var made: Array = _world(); var sim = made[0]; var s: Dictionary = made[1]
	# Tone: a warm person takes a friendly word well; asking twice in an hour gets short shrift.
	var warm: Dictionary = _villager(s, "warm")
	Society.remember(s, int(warm.id), "helped", int(s.player), "test")
	var said: String = Talk.say(sim, warm, "friendly")
	check(said.begins_with(String(s.entities[str(warm.id)].name).split(" ")[0] + ":"), "They answer: %s" % said)
	check(Talk.say(sim, warm, "friendly").contains("just talked"), "Twice in an hour: 'We just talked'")
	# A threat cows a nervous person (cheaper prices) but costs their good will.
	var nervous: Dictionary = _villager(s, "nervous")
	var before: int = Society.opinion(s, int(nervous.id), int(s.player))
	var cowed := false
	for attempt in range(6):
		s.tick += 700
		Talk.say(sim, nervous, "threaten")
		if int(s.player_control.get("trade_terms", {}).get("pct", 0)) == -15 and int(s.player_control.trade_terms.target) == int(nervous.id): cowed = true; break
	check(cowed, "Threatening a nervous person can cow them into a discount")
	check(Society.opinion(s, int(nervous.id), int(s.player)) < before, "...but they think less of you")
	# The Talk tab lists favours, questions and the three tones.
	var ids: Array = []
	for page in range(3):   # long lists go over pages ("More…")
		s.player_control.talk_page = page
		ids += Dialogue.options(s, int(warm.id)).map(func(o): return o.id)
	s.player_control.talk_page = 0
	check("ask_help" in ids and "ask_news" in ids and "say_threaten" in ids, "Talk offers help, questions and tones (%s)" % str(ids))
	# Held at gunpoint for a theft: bribe options, and they work on a friendly sheriff.
	var sheriff: Dictionary = _held(sim, s, "theft")
	var options: Array = Dialogue.options(s, int(sheriff.id)).map(func(o): return o.id)
	check("bribe_25" in options and "persuade" in options, "At gunpoint the Talk tab offers bribes and excuses (%s)" % str(options))
	Society.remember(s, int(sheriff.id), "saved_life", int(s.player), "test")
	var coins: int = int(s.accounts[str(s.player)])
	var pocket: int = int(s.accounts.get(str(sheriff.id), 0))
	var bought := false
	for attempt in range(8):
		if Law.wanted_hours(s, 1) == 0: break
		sheriff.arrest = {"phase": "standoff", "since": s.tick}
		Talk.bribe(sim, sheriff, 50)
	bought = Law.wanted_hours(s, 1) == 0 and sheriff.get("arrest", {}).is_empty()
	check(bought, "A big enough bribe makes the charge go away")
	check(int(s.accounts[str(s.player)]) < coins and int(s.accounts[str(sheriff.id)]) > pocket, "...and the coins change hands")
	check(load("res://sim/diagnostics/invariants.gd").validate(s).is_empty(), "Money is conserved")
	# Not for murder.
	var murder := _world(); var ms: Dictionary = murder[1]
	var hard: Dictionary = _held(murder[0], ms, "murder")
	check(not Dialogue.options(ms, int(hard.id)).filter(func(o): return str(o.id).begins_with("bribe_")).any(func(o): return o.enabled), "No bribe for murder")
	# A failed bribe is one more crime.
	var stingy := _world(); var ts: Dictionary = stingy[1]
	var stern: Dictionary = _held(stingy[0], ts, "theft")
	for i in range(3): Society.remember(ts, int(stern.id), "killed_kin", int(ts.player), "test")
	var hours: int = Law.wanted_hours(ts, 1)
	var refused := false
	for attempt in range(6):
		stern.arrest = {"phase": "standoff", "since": ts.tick}
		Talk.bribe(stingy[0], stern, 10)
		if "bribery" in ts.law.wanted.get("1", {}).get("crimes", []): refused = true; break
	check(refused and Law.wanted_hours(ts, 1) > hours, "A refused bribe is another charge")
	# Favours: a bare pantry, a request, bread delivered, paid, remembered.
	var fav := _world(); var fsim = fav[0]; var fs: Dictionary = fav[1]
	var household: Dictionary = {}
	for h in fs.households.values():
		if int(h.settlement) == 1 and not h.members.is_empty(): household = h; break
	for item in ["food", "rye"]: Inventory.consume(fs, int(household.home), item, Inventory.amount(fs, int(household.home), item))
	Requests.daily(fsim)
	var giver: Dictionary = fs.residents[str(household.members[0])]
	var request: Dictionary = Requests.of(fs, int(giver.id))
	check(not request.is_empty() and request.kind == "deliver", "A bare pantry asks for bread")
	fs.entities[str(fs.player)].cell = [fs.entities[str(giver.id)].cell[0] + 1, fs.entities[str(giver.id)].cell[1]]
	Context.perform(fsim, int(giver.id), "ask_help")
	check(str(fs.player_control.notice).contains("pantry"), "Asking if you can help: %s" % fs.player_control.notice)
	Context.perform(fsim, int(giver.id), "accept_request")
	check(request.state == "accepted", "You promise to help")
	Inventory.produce(fs, int(fs.player), "food", 5)
	var purse_before: int = int(fs.accounts[str(fs.player)])
	var opinion_before: int = Society.opinion(fs, int(giver.id), int(fs.player))
	Context.perform(fsim, int(giver.id), "hand_over")
	check(request.state == "done" and int(fs.accounts[str(fs.player)]) > purse_before, "Bread handed over and paid for: %s" % fs.player_control.notice)
	check(Society.opinion(fs, int(giver.id), int(fs.player)) > opinion_before, "...and they think better of you")
	check(load("res://sim/diagnostics/invariants.gd").validate(fs).is_empty(), "Money and goods are conserved")
	# The journal knows who you met, what you heard and what you promised.
	Context.perform(fsim, int(giver.id), "ask_news")
	var Journal = load("res://view/ui/journal_window.gd")
	var book = Journal.new(); book.simulation = fsim
	book.page = "people"; check(book.rows(fs).size() >= 1, "The journal lists people you met")
	book.page = "news"; check(book.rows(fs).size() >= 1, "...news you heard")
	book.page = "favours"; check(book.rows(fs).size() >= 1 and str(book.rows(fs)[0][1]).ends_with("done"), "...and favours done")
	book.page = "you"; check(str(book.rows(fs)[0][1]).begins_with("You are "), "...and your standing")
	book.free()
	var copy := Sim.new(); copy.restore(fsim.snapshot())
	for i in range(120): fsim.step(); copy.step()
	check(fsim.state_hash() == copy.state_hash(), "Save, load and continue gives the same world")
	print("Talk and favours: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)
