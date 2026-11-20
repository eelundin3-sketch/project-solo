extends RefCounted
## Families keep house together. Each household shares a surname, a home and a purse:
##   - its working members earn for the family: the town pays a wage for every job they finish
##     (WAGE coins a delivery, paid each evening from the storehouse's treasury), a sheriff draws a
##     daily wage, and a market tent's takings above its float go home to the keeper's family;
##   - each morning a family whose pantry is running low sends one grown-up to the storehouse to buy
##     food with the family purse, and they carry it home to the pantry;
##   - the family eats from its pantry; a meal taken from the town's stores instead is paid for
##     from the purse when it can be.
## The purse is an ordinary account ("household:<key>" in s.accounts), so every coin is still
## accounted for (invariants.gd).
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Market = preload("res://sim/economy/market.gd")
const WAGE := 5                 # coins a finished job (a delivery, a batch) earns the worker's family
const SHERIFF_WAGE := 30        # a sheriff's daily pay
const START_PURSE := 60
const POCKET_MONEY := 15        # what each grown-up keeps in their own pocket when the purse is set up
const FOOD_PER_HEAD := 2        # a pantry below this many loaves per person needs shopping
const CARRY := 8                # what one shopper can carry home
const SHOPPING_TICK := 4500     # 07:30, once everyone is up
const DAY := 14400

static func purse_key(household_key: String) -> String:
	return "household:" + household_key

static func purse(s: Dictionary, household_key: String) -> int:
	return int(s.get("accounts", {}).get(purse_key(household_key), 0))

static func _move(s: Dictionary, from: String, to: String, amount: int) -> int:
	var paid: int = mini(amount, int(s.accounts.get(from, 0)))
	if paid <= 0: return 0
	s.accounts[from] = int(s.accounts[from]) - paid
	s.accounts[to] = int(s.accounts.get(to, 0)) + paid
	return paid

## Sets up every household's purse and shared surname (new games, and saves from before purses).
static func ensure(s: Dictionary) -> void:
	if not s.has("households") or not s.has("accounts"): return
	var keys: Array = s.households.keys()
	keys.sort()
	for key in keys:
		var household: Dictionary = s.households[key]
		_share_surname(s, household)
		var pkey := purse_key(key)
		if s.accounts.has(pkey): continue
		s.accounts[pkey] = 0
		var town: Dictionary = s.settlements.get(str(household.settlement), {})
		for id in household.members:
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty() or npc.occupation == "Trader": continue   # a trader's coins are his trading stake
			_move(s, str(id), pkey, int(s.accounts.get(str(id), 0)) - POCKET_MONEY)
		if purse(s, key) < START_PURSE and not town.is_empty():
			_move(s, str(town.warehouse), pkey, START_PURSE - purse(s, key))
	# Purses of households that have broken up go to the town.
	for account in s.accounts.keys():
		if String(account).begins_with("household:") and not s.households.has(String(account).substr(10)):
			var leftover: int = int(s.accounts[account])
			var town_key: String = String(account).substr(10).split(":")[0]
			var town: Dictionary = s.settlements.get(town_key, {})
			if town.is_empty():
				# Keys like "migrant:12" do not start with a town: use the member's town, else the first.
				var member: Dictionary = s.residents.get(String(account).get_slice(":", 2), {})
				town = s.settlements.get(str(member.get("settlement", 0)), {})
				if town.is_empty() and not s.settlements.is_empty():
					var towns: Array = s.settlements.keys()
					towns.sort()
					town = s.settlements[towns[0]]
			if leftover > 0 and not town.is_empty(): s.accounts[str(town.warehouse)] = int(s.accounts.get(str(town.warehouse), 0)) + leftover
			s.accounts.erase(account)

## A family goes by one name: the first member's surname, taken by a partner and the children.
static func _share_surname(s: Dictionary, household: Dictionary) -> void:
	if household.members.size() < 2: return
	var head: Dictionary = s.entities.get(str(household.members[0]), {})
	if head.is_empty(): return
	var family: String = String(head.name).split(" ")[-1]
	for id in household.members:
		var entity: Dictionary = s.entities.get(str(id), {})
		if entity.is_empty() or entity.kind != "resident": continue
		var parts: PackedStringArray = String(entity.name).split(" ")
		var renamed: String = "%s %s" % [parts[0], family]
		if parts[-1] != family and not _name_taken(s, renamed):
			entity.name = renamed   # names stay unique
			if s.has("names_used"): s.names_used[renamed] = true

static func _name_taken(s: Dictionary, name: String) -> bool:
	if s.get("names_used", {}).has(name): return true
	for entity in s.entities.values():
		if entity.get("kind", "") in ["resident", "player"] and String(entity.name) == name: return true
	return false

static func family_name(s: Dictionary, household: Dictionary) -> String:
	if household.get("members", []).is_empty(): return ""
	return String(s.entities.get(str(household.members[0]), {}).get("name", "")).split(" ")[-1]

## Evening pay: wages for the day's finished jobs, a sheriff's pay, and a tent's takings.
static func payday(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("households") or not s.has("accounts"): return
	ensure(s)
	var keys: Array = s.households.keys()
	keys.sort()
	for key in keys:
		var household: Dictionary = s.households[key]
		var town: Dictionary = s.settlements.get(str(household.settlement), {})
		if town.is_empty(): continue
		var treasury: String = str(town.warehouse)
		var earned := 0
		for id in household.members:
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty() or int(npc.health) <= 0: continue
			var owed: int = int(npc.get("work_done", 0)) * WAGE
			if npc.occupation == "Sheriff": owed += SHERIFF_WAGE
			npc.work_done = 0
			earned += _move(s, treasury, purse_key(key), owed)
			var tent: int = int(npc.get("tent", 0))
			if tent != 0 and s.accounts.has(str(tent)):
				earned += _move(s, str(tent), purse_key(key), int(s.accounts[str(tent)]) - Market.TENT_FUNDS)
		household.last_earned = earned
	# Sheriffs who live at the office (no household) are paid into their own pockets.
	for npc in s.residents.values():
		if npc.occupation == "Sheriff" and str(npc.get("household", "")).is_empty() and int(npc.health) > 0:
			var town: Dictionary = s.settlements.get(str(npc.settlement), {})
			if not town.is_empty(): _move(s, str(town.warehouse), str(npc.id), SHERIFF_WAGE)

## Every tick (cheap): in the morning, families short of food send someone shopping.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("households") or s.tick % DAY != SHOPPING_TICK: return
	ensure(s)
	var keys: Array = s.households.keys()
	keys.sort()
	for key in keys:
		var household: Dictionary = s.households[key]
		var home: int = int(household.get("home", 0))
		if home == 0 or not s.inventories.has(str(home)): continue
		var wanted: int = household.members.size() * FOOD_PER_HEAD
		if Inventory.amount(s, home, "food") >= wanted: continue
		var price: int = Market.quote(s, int(household.settlement), "food", true)
		if purse(s, key) < price: continue
		var shopper: Dictionary = _shopper(s, household)
		if shopper.is_empty(): continue
		shopper.shopping_for = key
		load("res://sim/entities/residents.gd").set_goal(s, shopper, "shop")

## The grown-up who goes: the first free, able member (lowest id first).
static func _shopper(s: Dictionary, household: Dictionary) -> Dictionary:
	var ids: Array = household.members.duplicate()
	ids.sort()
	for id in ids:
		var npc: Dictionary = s.residents.get(str(id), {})
		if npc.is_empty() or int(npc.health) <= 0 or npc.occupation in ["Child", "Sheriff", "Trader"]: continue
		if not npc.get("sleeping", {}).is_empty() or not npc.get("arrest", {}).is_empty() or not npc.get("fear", {}).is_empty(): continue
		if not npc.get("serving", {}).is_empty() or npc.get("goal", "") != "": continue
		if not npc.get("migration", {}).is_empty(): continue   # on the way to another town
		return npc
	return {}

## At the storehouse: buy what the family needs and can afford, then carry it home.
static func buy_food(sim: RefCounted, npc: Dictionary) -> void:
	var s: Dictionary = sim.state
	var key: String = str(npc.get("shopping_for", npc.get("household", "")))
	var household: Dictionary = s.households.get(key, {})
	npc.erase("shopping_for")
	if household.is_empty(): return
	var town_id: int = int(household.settlement)
	var store: int = int(s.settlements[str(town_id)].warehouse)
	var price: int = Market.quote(s, town_id, "food", true)
	var home: int = int(household.home)
	var wanted: int = household.members.size() * FOOD_PER_HEAD * 2 - Inventory.amount(s, home, "food")
	var quantity: int = mini(mini(wanted, CARRY), mini(purse(s, key) / maxi(1, price), Inventory.amount(s, store, "food")))
	quantity = mini(quantity, Inventory.available(s, int(npc.id)))
	if quantity <= 0:
		npc.status = "Nothing the family can afford at the storehouse"
		return
	# The purse pays: hand the coins to the shopper for the purchase, so the market records the trade.
	var pocket_before: int = int(s.accounts.get(str(npc.id), 0))
	if not s.accounts.has(str(npc.id)): s.accounts[str(npc.id)] = 0
	_move(s, purse_key(key), str(npc.id), quantity * price)
	var bought := Market.transact(s, store, int(npc.id), "food", quantity, price, town_id)
	_move(s, str(npc.id), purse_key(key), int(s.accounts[str(npc.id)]) - pocket_before)   # change back to the purse
	if not bought.ok:
		npc.status = "Could not buy food"
		return
	npc.status = "Bought %d loaves for the %s family" % [quantity, family_name(s, household)]
	load("res://sim/entities/residents.gd").set_goal(s, npc, "stock_pantry")

## Home again: the shopping goes into the pantry.
static func stock_pantry(s: Dictionary, npc: Dictionary) -> void:
	var household: Dictionary = s.get("households", {}).get(str(npc.get("household", "")), {})
	if household.is_empty() or not s.inventories.has(str(household.home)): return
	var carried: int = Inventory.amount(s, int(npc.id), "food")
	var room: int = Inventory.available(s, int(household.home))
	if carried > 0 and room > 0: Inventory.transfer(s, int(npc.id), int(household.home), "food", mini(carried, room))
	npc.status = "Put the shopping in the pantry"

## A meal from the town's stores is paid for from the family purse when it can be.
static func pay_for_meal(s: Dictionary, npc: Dictionary, store: int) -> void:
	var key: String = str(npc.get("household", ""))
	if key.is_empty() or not s.has("accounts") or not s.accounts.has(purse_key(key)): return
	var town_id: int = int(npc.settlement)
	if not s.get("markets", {}).has(str(town_id)): return
	_move(s, purse_key(key), str(store), Market.quote(s, town_id, "food", true))

## A line about someone's family and work, for Look at and Ask about family.
static func describe(s: Dictionary, npc: Dictionary) -> String:
	var household: Dictionary = s.get("households", {}).get(str(npc.get("household", "")), {})
	if household.is_empty(): return "They live on their own."
	var others: Array = []
	for id in household.members:
		if int(id) != int(npc.id) and s.entities.has(str(id)): others.append(String(s.entities[str(id)].name).split(" ")[0])
	var family: String = family_name(s, household)
	var pantry: int = Inventory.amount(s, int(household.home), "food") if s.inventories.has(str(household.home)) else 0
	var with_whom: String = ("with " + ", ".join(others)) if not others.is_empty() else "alone"
	return "The %s household: lives %s; %d coins in the family purse, %d loaves in the pantry." % [family, with_whom, purse(s, str(npc.household)), pantry]
