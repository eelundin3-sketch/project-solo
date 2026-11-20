extends RefCounted
## Someone has to mind the stall. When the player comes to a tent or stall with nobody behind the
## counter, its keeper (a tent's own keeper, or for the town's stalls the nearest free grown-up)
## sees them and hurries over at a run, and trading starts when they reach the counter. The keeper
## stays while the customer is there and goes back to work after they leave. A keeper who is
## asleep, away on the road or in trouble cannot come, and the player is told why.
##
## Trading terms: the player may haggle once a visit. It can get a discount, or annoy the seller
## into charging more. Plain data: `npc.serving` {stall, since, state, last_seen, path_tick},
## `player_control.awaiting` {stall, keeper, since}, `player_control.trade_terms` {target, pct, haggled}.
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Market = preload("res://sim/economy/market.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const LEAVE_RANGE := 7          # the customer is still "at the stall" within this many cells
const LEAVE_AFTER := 60         # ticks after the customer leaves before the keeper goes back to work
const GIVE_UP := 2400           # nobody minds a tent for ever
const REPATH := 10

static func _law() -> GDScript:
	return load("res://sim/law/law.gd")

## Where the keeper stands: behind the counter, or beside it if that is blocked.
static func counter_cell(s: Dictionary, stall: Dictionary) -> Array:
	var x: int = int(stall.cell[0])
	var y: int = int(stall.cell[1])
	for cell in [[x, y - 1], [x + 1, y - 1], [x - 1, y - 1], [x + 2, y - 1], [x - 2, y], [x + 3, y]]:
		if World.walkable(s, cell): return cell
	return World.Fixtures.interaction_cell(s, int(stall.id))

static func _cells_apart(a: Array, b: Array) -> int:
	return maxi(absi(a[0] - b[0]), absi(a[1] - b[1]))

## The person who minds this stall: the tent's keeper, or for a town stall the nearest free grown-up.
static func keeper_for(s: Dictionary, stall: Dictionary) -> Dictionary:
	if stall.has("keeper"): return s.get("residents", {}).get(str(stall.keeper), {})
	for npc in s.get("residents", {}).values():
		if not npc.get("serving", {}).is_empty() and int(npc.serving.stall) == int(stall.id): return npc
	var best: Dictionary = {}
	var best_distance := 1 << 30
	var keys: Array = s.residents.keys()
	keys.sort()
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if int(npc.settlement) != int(stall.settlement) or npc.occupation in ["Child", "Sheriff", "Trader"]: continue
		if not unavailable(s, npc).is_empty() or not npc.get("serving", {}).is_empty(): continue
		var cell: Array = s.entities[key].cell
		var d: int = absi(cell[0] - stall.cell[0]) + absi(cell[1] - stall.cell[1])
		if d < best_distance:
			best_distance = d
			best = npc
	return best

## Why this person cannot come to the stall ("" when they can).
static func unavailable(s: Dictionary, npc: Dictionary) -> String:
	if npc.is_empty() or int(npc.health) <= 0: return "Nobody minds this stall any more."
	var first: String = String(s.entities[str(npc.id)].name).split(" ")[0]
	if not npc.get("sleeping", {}).is_empty(): return "%s is asleep at home. Come back in the morning." % first
	if npc.occupation == "Trader" and load("res://sim/economy/traders.gd").away(s, npc): return "%s is away on the road." % first
	if Brawl.knocked(s, npc) or not npc.get("arrest", {}).is_empty() or not npc.get("fear", {}).is_empty() or not npc.get("migration", {}).is_empty():
		return "%s cannot come right now." % first
	return ""

## True when someone is behind the counter to trade with.
static func staffed(s: Dictionary, stall: Dictionary) -> bool:
	var keeper: Dictionary = keeper_for(s, stall)
	if keeper.is_empty(): return false
	var serving: Dictionary = keeper.get("serving", {})
	return not serving.is_empty() and int(serving.stall) == int(stall.id) and str(serving.state) == "serving"

## The player asks to trade at a stall: trade at once if the keeper is there, else call them over.
static func request(sim: RefCounted, stall_id: int) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var stall: Dictionary = s.entities.get(str(stall_id), {})
	if stall.is_empty(): return
	var keeper: Dictionary = keeper_for(s, stall)
	var reason: String = unavailable(s, keeper)
	if not reason.is_empty():
		pc.notice = reason
		return
	var first: String = String(s.entities[str(keeper.id)].name).split(" ")[0]
	if staffed(s, stall) and _cells_apart(s.entities[str(keeper.id)].cell, counter_cell(s, stall)) <= 1:
		_open(sim, stall, keeper)
		return
	if keeper.get("serving", {}).is_empty() or int(keeper.serving.stall) != stall_id:
		if int(keeper.get("job", 0)) != 0: load("res://sim/jobs/job_board.gd").release(s, int(keeper.job), "SERVING")
		if keeper.has("sitting"): load("res://sim/law/sheriff.gd").stand_up(s, keeper)
		keeper.goal = ""
		keeper.path = []
		keeper.serving = {"stall": stall_id, "since": s.tick, "state": "coming", "last_seen": s.tick, "path_tick": -100}
	pc.awaiting = {"stall": stall_id, "keeper": int(keeper.id), "since": s.tick}
	pc.notice = "%s sees you at the %s and hurries over…" % [first, String(stall.name).to_lower()]
	_law()._say(sim, int(keeper.id), "Coming! Just a moment!")

static func _open(sim: RefCounted, stall: Dictionary, keeper: Dictionary) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	pc.awaiting = {}
	pc.ui_target = int(stall.id)
	pc.ui_nonce = int(pc.get("ui_nonce", 0)) + 1
	pc.ui_kind = "trade"
	pc.ui_tab = "trade"
	if int(pc.get("trade_terms", {}).get("target", 0)) != int(stall.id): pc.trade_terms = {"target": int(stall.id), "pct": 0, "haggled": false}
	var first: String = String(s.entities[str(keeper.id)].name).split(" ")[0]
	pc.notice = "%s: What can I get you?" % first
	_law()._say(sim, int(keeper.id), "What can I get you?")

static func _end(s: Dictionary, npc: Dictionary, status: String) -> void:
	npc.serving = {}
	npc.path = []
	npc.status = status
	npc.work_pause_until = s.tick + 10

## Every tick: keepers hurry to their counters and mind them; the waiting customer is served.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("player_control") or not s.has("residents"): return
	var pc: Dictionary = s.player_control
	var player: Array = s.entities[str(s.player)].cell
	var awaiting: Dictionary = pc.get("awaiting", {})
	if not awaiting.is_empty():
		var waited_at: Dictionary = s.entities.get(str(awaiting.stall), {})
		if waited_at.is_empty() or _cells_apart(player, waited_at.cell) > LEAVE_RANGE:
			pc.awaiting = {}
			pc.notice = "You walk away from the stall."
	for key in s.residents:
		var npc: Dictionary = s.residents[key]
		var serving: Dictionary = npc.get("serving", {})
		if serving.is_empty(): continue
		var stall: Dictionary = s.entities.get(str(serving.stall), {})
		if stall.is_empty() or int(npc.health) <= 0 or Brawl.knocked(s, npc) or not npc.get("fear", {}).is_empty() or not npc.get("arrest", {}).is_empty():
			npc.serving = {}
			continue
		var cell: Array = s.entities[key].cell
		var counter := counter_cell(s, stall)
		if _cells_apart(player, stall.cell) <= LEAVE_RANGE: serving.last_seen = s.tick
		if s.tick - int(serving.last_seen) > LEAVE_AFTER or s.tick - int(serving.since) > GIVE_UP:
			_end(s, npc, "Back to work")
			continue
		if cell != counter:
			# Hastily: a step every tick, at a run.
			if npc.path.is_empty() or s.tick - int(serving.path_tick) >= REPATH:
				var route := Nav.request_path(s, cell, counter)
				serving.path_tick = s.tick
				npc.path = route.path if route.ok else []
			if not npc.path.is_empty():
				var next: Array = npc.path.pop_front()
				if World.walkable(s, next):
					s.entities[key].cell = next
					npc.running_tick = s.tick
			npc.status = "Hurrying to the %s" % String(stall.name).to_lower()
			if s.entities[key].cell != counter: continue
		if str(serving.state) != "serving":
			serving.state = "serving"
			npc.path = []
			if int(pc.get("awaiting", {}).get("keeper", 0)) == int(npc.id): _open(sim, stall, npc)
		npc.status = "Minding the %s" % String(stall.name).to_lower()

# --- prices, haggling and talk ------------------------------------------------------------------

## The price the player pays (buying) or gets (selling) with whoever they are trading with.
static func price(s: Dictionary, town_id: int, item: String, buying: bool, target: int) -> int:
	var base: int = Market.quote(s, town_id, item, buying)
	var terms: Dictionary = s.get("player_control", {}).get("trade_terms", {})
	var pct: int = int(terms.get("pct", 0)) if int(terms.get("target", 0)) == target else 0
	pct += feeling_pct(s, target) + load("res://sim/player/look.gd").price_pct(s)   # how they feel, and how you look
	var adjusted: int = roundi(float(base) * float(100 + pct) / 100.0) if buying else roundi(float(base) * float(100 - pct) / 100.0)
	return clampi(adjusted, 1, 100)

## How the person you trade with feels about you moves the price: someone who holds a grudge
## (opinion -50 or worse) charges 15% more, a friend (50 or better) 10% less.
static func feeling_pct(s: Dictionary, target: int) -> int:
	var npc: Dictionary = counterpart(s, target)
	if npc.is_empty() or not s.has("player"): return 0
	var feeling: int = load("res://sim/factions/society.gd").opinion(s, int(npc.id), int(s.player))
	return 15 if feeling <= -50 else (-10 if feeling >= 50 else 0)

## The person on the other side of a trade: the resident, or whoever minds the stall.
static func counterpart(s: Dictionary, target: int) -> Dictionary:
	var e: Dictionary = s.entities.get(str(target), {})
	if e.get("kind", "") == "market_stall": return keeper_for(s, e)
	return s.get("residents", {}).get(str(target), {})

## Once a visit: ask for a better price. Friendly sellers give a little; cross ones charge more.
static func haggle(sim: RefCounted, target: int) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var npc: Dictionary = counterpart(s, target)
	if npc.is_empty(): return
	var terms: Dictionary = pc.get("trade_terms", {})
	if int(terms.get("target", 0)) != target: terms = {"target": target, "pct": 0, "haggled": false}
	var first: String = String(s.entities[str(npc.id)].name).split(" ")[0]
	if bool(terms.get("haggled", false)):
		pc.notice = "%s: I've given you my price." % first
		pc.trade_terms = terms
		return
	terms.haggled = true
	var liking: int = load("res://sim/factions/society.gd").opinion(s, int(npc.id), int(s.player))
	var tidy: int = 5 if load("res://sim/player/look.gd").score(s) >= 30 else 0   # a clean, well-dressed customer
	var chance: int = clampi(50 - int(npc.get("anger", 0)) / 2 + liking / 4 + tidy, 10, 85)
	if sim.random_int("haggle", 0, 99) < chance:
		terms.pct = -sim.random_int("haggle", 10, 20)
		pc.notice = "%s: Fine, %d%% off, for you." % [first, -int(terms.pct)]
		_law()._say(sim, int(npc.id), "Fine. For you.")
	else:
		terms.pct = 10
		npc.anger = mini(100, int(npc.get("anger", 0)) + 4)
		pc.notice = "%s: Prices are prices. Keep that up and it costs you more." % first
		_law()._say(sim, int(npc.id), "Prices are prices.")
	pc.trade_terms = terms

## What a villager says when asked for news: where goods sell dear, and any trouble about.
static func news(s: Dictionary, npc: Dictionary) -> String:
	var heard: String = load("res://sim/entities/gossip.gd").tell(s, npc)   # real gossip first
	if not heard.is_empty(): return heard
	var here: int = int(npc.settlement)
	var best: String = ""
	var best_gap := 2
	for item in ["plank", "log", "food", "ore", "tool", "rye"]:
		for town in s.get("settlements", {}).values():
			if int(town.id) == here: continue
			var gap: int = Market.quote(s, int(town.id), item, false) - Market.quote(s, here, item, true)
			if gap > best_gap:
				best_gap = gap
				best = "%s sell for %d in %s, and you can buy them here for %d." % [item.capitalize() + ("" if item.ends_with("s") else "s"), Market.quote(s, int(town.id), item, false), town.name, Market.quote(s, here, item, true)]
	var wanted: Dictionary = s.get("law", {}).get("wanted", {}).get(str(here), {})
	var trouble: String = " The sheriff is looking for you, mind." if not wanted.is_empty() else ""
	if best.is_empty(): best = "Prices are much the same everywhere just now."
	var weather: String = load("res://sim/world/weather.gd").news_line(s, here)
	if not weather.is_empty(): best = weather + " " + best
	return best + trouble
