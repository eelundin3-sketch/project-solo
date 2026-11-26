extends RefCounted
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const BASE: Dictionary = {"log": 12, "food": 8, "plank": 7, "bandage": 6, "antiseptic": 12, "rye": 5, "ore": 9, "tool": 24}
const TARGET: Dictionary = {"log": 100, "food": 100, "plank": 100, "bandage": 30, "antiseptic": 12, "rye": 80, "ore": 60, "tool": 20}
## What each trade sells from its own tent at the market.
const SELLER_GOODS: Dictionary = {"Farmer": ["food", "rye"], "Woodsman": ["log"], "Sawyer": ["plank"], "Baker": ["food"],
	"Miner": ["ore"], "Blacksmith": ["tool"], "Trader": ["food", "log", "plank"]}
const TENT_STOCK := 8
const TENT_FUNDS := 150

static func initialize(s: Dictionary) -> void:
	s.accounts = {str(s.player): 1000}
	s.markets = {}
	s.money_initial = 1000
	s.trades = []
	for town in s.settlements.values():
		add_market(s, town.id)

static func add_market(s: Dictionary, town_id: int) -> void:
	var town: Dictionary = s.settlements[str(town_id)]
	s.accounts[str(town.warehouse)] = 10000
	s.money_initial += 10000
	s.markets[str(town_id)] = {"settlement": town_id, "store": town.warehouse, "last": {}, "history": [], "orders": []}

static func install_stalls(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("routes") or not s.has("markets") or s.world.get("stall_version", 0) >= 1: return
	for town in s.settlements.values():
		town.stalls = []
		var store: Dictionary = s.entities[str(town.warehouse)]
		for spec in [
			{"name": "Timber stall", "items": ["plank", "log"], "stock": {"log": 6}, "side": -1},
			{"name": "Provisions stall", "items": ["food", "bandage", "antiseptic"], "stock": {"food": 18, "bandage": 5, "antiseptic": 3}, "side": 1},
		]:
			var cell := _stall_cell(s, store.cell, spec.side)
			if cell.is_empty(): continue
			var id := World.add_entity(sim, "market_stall", spec.name, cell, town.id)
			var stall: Dictionary = s.entities[str(id)]
			stall.sale_items = spec.items.duplicate()
			town.stalls.append(id)
			Inventory.create(s, id, 120)
			var funds: int = mini(700, s.accounts.get(str(town.warehouse), 0))
			s.accounts[str(town.warehouse)] -= funds
			s.accounts[str(id)] = funds
			for item in spec.stock:
				var quantity: int = mini(spec.stock[item], Inventory.amount(s, town.warehouse, item))
				if quantity > 0: Inventory.transfer(s, town.warehouse, id, item, quantity)
	s.world.stall_version = 1

## Every villager whose trade sells something keeps their own tent at the town's market, stocked
## from the storehouse with what they make; a tent is packed away when its keeper changes trade.
## Called at the start of a game and every few in-game minutes.
static func ensure_tents(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("markets") or not s.has("residents"): return
	var keys: Array = s.residents.keys()
	keys.sort()
	for town in s.settlements.values():
		if not town.has("stalls"): town.stalls = []
	# Pack away tents whose keeper no longer sells (or has gone).
	for town in s.settlements.values():
		for stall_id in town.stalls.duplicate():
			var stall: Dictionary = s.entities.get(str(stall_id), {})
			if stall.is_empty() or not stall.has("keeper"): continue
			var keeper: Dictionary = s.residents.get(str(stall.keeper), {})
			if keeper.is_empty() or keeper.health <= 0 or not SELLER_GOODS.has(keeper.occupation) or keeper.settlement != town.id:
				_pack_tent(s, town, stall)
			elif stall.sale_items != SELLER_GOODS[keeper.occupation]:
				# A keeper who changed trade sells their new goods: the old stock goes back to the store.
				for item in s.inventories[str(stall.id)].items.keys():
					var quantity: int = Inventory.amount(s, stall.id, item)
					if quantity > 0 and not SELLER_GOODS[keeper.occupation].has(item): Inventory.transfer(s, stall.id, town.warehouse, item, quantity)
				stall.sale_items = SELLER_GOODS[keeper.occupation].duplicate()
				stall.name = "%s's %s tent" % [String(s.entities[str(keeper.id)].name).split(" ")[0], String(keeper.occupation).to_lower()]
	for key in keys:
		var npc: Dictionary = s.residents[key]
		if npc.health <= 0 or not SELLER_GOODS.has(npc.occupation) or npc.get("tent", 0) != 0 and s.entities.has(str(npc.tent)): continue
		var town: Dictionary = s.settlements.get(str(npc.settlement), {})
		if town.is_empty(): continue
		var store: Array = s.entities[str(town.warehouse)].cell
		var cell := _tent_cell(s, store)
		if cell.is_empty(): continue
		var goods: Array = SELLER_GOODS[npc.occupation]
		var first: String = String(s.entities[key].name).split(" ")[0]
		var id := World.add_entity(sim, "market_stall", "%s's %s tent" % [first, String(npc.occupation).to_lower()], cell, town.id)
		var tent: Dictionary = s.entities[str(id)]
		tent.sale_items = goods.duplicate()
		tent.keeper = npc.id
		tent.label = first.to_upper()
		npc.tent = id
		town.stalls.append(id)
		Inventory.create(s, id, 120)
		var funds: int = mini(TENT_FUNDS, int(s.accounts.get(str(town.warehouse), 0)))
		s.accounts[str(town.warehouse)] -= funds
		s.accounts[str(id)] = funds
	restock_tents(s)

## Keeps each tent's shelves from running bare, out of the storehouse's stock.
static func restock_tents(s: Dictionary) -> void:
	for town in s.settlements.values():
		for stall_id in town.get("stalls", []):
			var tent: Dictionary = s.entities.get(str(stall_id), {})
			if tent.is_empty() or not tent.has("keeper"): continue
			for item in tent.sale_items:
				var short: int = TENT_STOCK - Inventory.amount(s, tent.id, item)
				var moving: int = mini(short, mini(Inventory.amount(s, town.warehouse, item) / 4, Inventory.available(s, tent.id)))
				if moving > 0: Inventory.transfer(s, town.warehouse, tent.id, item, moving)

static func _pack_tent(s: Dictionary, town: Dictionary, tent: Dictionary) -> void:
	for item in s.inventories[str(tent.id)].items.keys():
		var quantity: int = Inventory.amount(s, tent.id, item)
		if quantity > 0: Inventory.transfer(s, tent.id, town.warehouse, item, quantity)
	s.accounts[str(town.warehouse)] += int(s.accounts.get(str(tent.id), 0))
	s.accounts.erase(str(tent.id))
	var keeper: Dictionary = s.residents.get(str(tent.get("keeper", 0)), {})
	if not keeper.is_empty(): keeper.tent = 0
	town.stalls.erase(tent.id)
	World.remove_entity(s, tent.id)

## A free 4x2 spot for a tent around the market square, away from other stalls and the well.
static func _tent_cell(s: Dictionary, store: Array) -> Array:
	for y_offset in [13, 16, 10, 19, 22]:
		for x_offset in [-20, 20, -14, 14, -26, 26, -8, 8, -32, 32]:
			var x: int = store[0] + x_offset
			var y: int = store[1] + y_offset
			var clear := true
			for cy in range(y - 1, y + 3):
				for cx in range(x - 3, x + 5):
					if not World.walkable(s, [cx, cy]): clear = false
			if not clear: continue
			for entity in World.of_kind(s, "market_stall") + World.of_kind(s, "farm") + World.of_kind(s, "construction"):
				if Vector2(entity.cell[0] - x, entity.cell[1] - y).length() < 7.0: clear = false; break
			for entity in World.buildings(s):
				if not clear: break
				if World.building_rect(entity).grow(2).intersects(Rect2i(x - 1, y, 4, 2)): clear = false
			for plot in s.get("crops", {}).values():
				if Rect2i(plot.rect[0], plot.rect[1], plot.rect[2], plot.rect[3]).grow(2).intersects(Rect2i(x - 1, y, 4, 2)): clear = false
			if clear: return [x, y]
	return []

static func _stall_cell(s: Dictionary, store: Array, side: int) -> Array:
	for y_offset in [4, 5, 7, 9, 11]:
		for width in [7, 10, 13, 17]:
			var x: int = store[0] + side * width
			var y: int = store[1] + y_offset
			var rect := Rect2i(x - 1, y, 4, 2)
			var clear := true
			for cy in range(y, y + 2):
				for cx in range(x - 1, x + 3):
					if not World.walkable(s, [cx, cy]): clear = false
			for entity in s.entities.values():
				if entity.kind in ["tree", "farm"] and rect.has_point(Vector2i(entity.cell[0], entity.cell[1])): clear = false
				if entity.kind == "construction":
					var site: Dictionary = s.construction.get(str(entity.id), {})
					var definition: Dictionary = s.building_defs.get(site.get("definition", ""), {})
					if rect.intersects(World.plot_rect(entity, definition.get("kind", "home"))): clear = false
			if clear: return [x, y]
	return []

static func quote(s: Dictionary, town_id: int, item: String, buying: bool) -> int:
	if not BASE.has(item) or not s.markets.has(str(town_id)):
		return 0
	var stock: int = Inventory.amount(s, s.markets[str(town_id)].store, item)
	var estimate: int = clampi(int(BASE[item]) * int(TARGET[item]) / maxi(10, stock + int(TARGET[item]) / 2), 2, 100)
	return clampi(estimate + (1 if buying else -1), 1, 100)

## Price trends: once a day each market keeps the day's quotes, so the trade window can show
## whether a price rose or fell since yesterday. Prices themselves only ever follow stock.
static func snapshot_trend(s: Dictionary) -> void:
	if not s.has("markets"): return
	for key in s.markets:
		var trend := {}
		for item in BASE: trend[item] = quote(s, int(key), item, true)
		s.markets[key].trend = trend

## +1 if the buying price rose since yesterday's snapshot, -1 if it fell, 0 if unchanged or unknown.
static func trend(s: Dictionary, town_id: int, item: String) -> int:
	var before: int = int(s.get("markets", {}).get(str(town_id), {}).get("trend", {}).get(item, 0))
	if before == 0: return 0
	return signi(quote(s, town_id, item, true) - before)

const KNOWN_REACH := 30      # within this many cells of a town's storehouse you see its prices
const KNOWN_FRESH := 14400 * 3   # older known prices are shown greyed

## The player remembers the prices of a town they are in (refreshed every hour while there).
static func note_prices(s: Dictionary) -> void:
	if not s.has("markets") or not s.has("player") or not s.has("settlements"): return
	var Region = load("res://sim/world/region.gd")
	var town: int = Region.of_player(s)
	if town == 0 or not s.markets.has(str(town)): return
	if Region.gap_squared(s, town, s.entities[str(s.player)].cell) > KNOWN_REACH * KNOWN_REACH: return
	var known: Dictionary = load("res://sim/player/player_status.gd").part(s, "known_prices", {})
	var prices := {}
	for item in BASE: prices[item] = {"buy": quote(s, town, item, true), "sell": quote(s, town, item, false)}
	known[str(town)] = {"tick": s.tick, "prices": prices}

## The best price the player knows in another town for `item`, if it beats `here_price` by 3
## or more: cheaper to buy (buying) or dearer to sell. {} when none.
static func better_elsewhere(s: Dictionary, town_id: int, item: String, buying: bool, here_price: int) -> Dictionary:
	var known: Dictionary = s.get("player_status", {}).get("known_prices", {})
	var best := {}
	var keys: Array = known.keys()
	keys.sort()
	for key in keys:
		if int(key) == town_id or not s.settlements.has(str(key)): continue
		var entry: Dictionary = known[key]
		var price: int = int(entry.prices.get(item, {}).get("buy" if buying else "sell", 0))
		if price <= 0: continue
		var gain: int = (here_price - price) if buying else (price - here_price)
		if gain >= 3 and (best.is_empty() or gain > int(best.gain)):
			best = {"town": int(key), "name": s.settlements[str(key)].name, "price": price, "gain": gain, "stale": s.tick - int(entry.tick) > KNOWN_FRESH}
	return best

static func transact(s: Dictionary, seller: int, buyer: int, item: String, quantity: int, price: int, town_id: int) -> Dictionary:
	if quantity <= 0 or price < 1 or price > 100 or seller == buyer or not BASE.has(item):
		return Inventory.result(false, "INVALID_ORDER")
	if not s.accounts.has(str(seller)) or not s.accounts.has(str(buyer)):
		return Inventory.result(false, "MISSING_ACCOUNT")
	var cost: int = quantity * price
	if int(s.accounts[str(buyer)]) < cost:
		return Inventory.result(false, "INSUFFICIENT_MONEY")
	var transfer := Inventory.transfer(s, seller, buyer, item, quantity)
	if not transfer.ok:
		return transfer
	s.accounts[str(buyer)] -= cost
	s.accounts[str(seller)] += cost
	var trade := {"tick": s.tick, "seller": seller, "buyer": buyer, "item": item, "quantity": quantity, "price": price, "settlement": town_id}
	s.trades.append(trade)
	if s.trades.size() > 64:
		s.trades.pop_front()
	var market: Dictionary = s.markets[str(town_id)]
	market.last[item] = price
	market.history.append(trade)
	if market.history.size() > 32:
		market.history.pop_front()
	return Inventory.result(true, "", [seller, buyer])

static func player_trade(sim: RefCounted, payload: Dictionary) -> Dictionary:
	var s: Dictionary = sim.state
	var town_id: int = int(payload.get("town", 1))
	var item: String = payload.get("item", "log")
	var buying: bool = payload.get("buy", false)
	var quantity: int = int(payload.get("quantity", 1))
	if not s.markets.has(str(town_id)) or not BASE.has(item):
		return Inventory.result(false, "UNKNOWN_MARKET_OR_ITEM")
	var store: int = s.markets[str(town_id)].store
	var cell: Array = s.entities[str(s.player)].cell
	var target: Array = s.entities[str(store)].cell
	if absi(cell[0] - target[0]) + absi(cell[1] - target[1]) > 6:
		return Inventory.result(false, "WALK_TO_STORE_TO_TRADE")
	var seller: int = store if buying else s.player
	var buyer: int = s.player if buying else store
	var result := transact(s, seller, buyer, item, quantity, quote(s, town_id, item, buying), town_id)
	if result.ok:
		sim.record("You %s %d %s at %d coins/unit" % ["bought" if buying else "sold", quantity, item, s.markets[str(town_id)].last[item]])
	return result

static func place_order(s: Dictionary, town_id: int, owner: int, item: String, quantity: int, limit_price: int, buy: bool, id: int) -> bool:
	if not s.markets.has(str(town_id)) or quantity <= 0 or limit_price < 1 or limit_price > 100 or not BASE.has(item):
		return false
	s.markets[str(town_id)].orders.append({"id": id, "owner": owner, "item": item, "quantity": quantity, "limit": limit_price, "buy": buy})
	return true

static func clear_market(s: Dictionary, town_id: int) -> int:
	var market: Dictionary = s.markets[str(town_id)]
	var bids: Array = market.orders.filter(func(o: Dictionary) -> bool: return o.buy)
	var asks: Array = market.orders.filter(func(o: Dictionary) -> bool: return not o.buy)
	bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.limit > b.limit or (a.limit == b.limit and a.id < b.id))
	asks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.limit < b.limit or (a.limit == b.limit and a.id < b.id))
	var count: int = 0
	for bid in bids:
		for ask in asks:
			if bid.item != ask.item or bid.owner == ask.owner or bid.limit < ask.limit or bid.quantity <= 0 or ask.quantity <= 0:
				continue
			var quantity: int = mini(bid.quantity, ask.quantity)
			if transact(s, ask.owner, bid.owner, bid.item, quantity, ask.limit, town_id).ok:
				bid.quantity -= quantity
				ask.quantity -= quantity
				count += 1
	# Orders are good-for-session; an unfunded order never reserves fictional goods.
	market.orders = []
	return count
