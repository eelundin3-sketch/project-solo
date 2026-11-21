extends RefCounted
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Recipes = preload("res://sim/production/recipe_system.gd")
const Market = preload("res://sim/economy/market.gd")
const Health = preload("res://sim/combat/body_health.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Looting = preload("res://sim/player/looting.gd")
static func initialize(s: Dictionary) -> void:
	if s.has("player_control") or not s.has("player"): return
	s.player_control={"held_item":"","held_quantity":0,"work":{},"notice":"WASD move · I inventory · F interact · H health","ui_target":0,"ui_nonce":0,"next_move":0,"running_tick":0,"pending":{},"ui_kind":"trade"}
	# Personal trade uses actual resident goods and a transfer from the town treasury.
	for npc in s.get("residents",{}).values():
		if s.get("accounts",{}).has(str(npc.id)): continue
		var town: Dictionary=s.get("settlements",{}).get(str(npc.settlement),{})
		if town.is_empty(): continue
		var store: String=str(town.warehouse)
		var funds: int=mini(100,int(s.accounts.get(store,0)))
		s.accounts[store]-=funds; s.accounts[str(npc.id)]=funds
static func distance(a: Array,b: Array) -> int: return absi(a[0]-b[0])+absi(a[1]-b[1])
static func near(s: Dictionary,e: Dictionary) -> bool:
	var p: Array=s.entities[str(s.player)].cell
	if e.has("rock_rect"):
		# A big rock: anywhere in the ring of cells around it counts as beside it.
		var r: Array=e.rock_rect
		return p[0]>=r[0]-1 and p[0]<=r[0]+r[2] and p[1]>=r[1]-1 and p[1]<=r[1]+r[3]
	if e.kind == "market_stall":
		var stance := World.Fixtures.interaction_cell(s, e.id)
		return p[1] >= stance[1] and distance(p, stance) <= 1
	return distance(p,World.Fixtures.interaction_cell(s,e.id))<=1 or (e.kind in ["warehouse","market"] and distance(p,e.cell)<=2) or (e.kind in ["resident","tree","farm","stash"] and distance(p,e.cell)<=1)
static func target(s: Dictionary, preferred: int = 0) -> int:
	if preferred!=s.player and s.entities.has(str(preferred)) and near(s,s.entities[str(preferred)]): return preferred
	var found: int=0
	var score: int=10000
	for id in nearby_ids(s, s.entities[str(s.player)].cell, 24):
		var e: Dictionary=s.entities.get(str(id),{})
		if e.is_empty() or not e.has("cell"): continue
		if e.get("kind","")=="stash" and Inventory.used(s.inventories.get(str(e.id),{"items":{},"capacity":1,"reserved":{}}))==0: continue
		if e.id==s.player or e.get("kind","") not in ["sawmill","bakery","forge","office","warehouse","market","saloon","town_hall","market_stall","construction","stash","resident","tree","farm","ore","chest"] or not near(s,e): continue
		var candidate: int=distance(s.entities[str(s.player)].cell,World.Fixtures.interaction_cell(s,e.id))*10
		candidate+=0 if e.kind in ["sawmill","warehouse","market","market_stall","stash"] else (3 if e.kind=="resident" else 5)
		if candidate<score: score=candidate; found=e.id
	return found
## Ids of everything that could be within reach of a cell, in ascending id order (the order of
## the entity table, so "first best" choices are unchanged): the chunk lists around the cell,
## which hold every entity that never walks, plus the residents, who do.
static func nearby_ids(s: Dictionary, cell: Array, reach: int) -> Array:
	var seen: Dictionary = {}
	var low: Vector2i = World.chunk_coord(cell[0] - reach, cell[1] - reach)
	var high: Vector2i = World.chunk_coord(cell[0] + reach, cell[1] + reach)
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			for id in s.world.chunks.get("%d,%d" % [cx, cy], {}).get("entities", []):
				seen[int(id)] = true
	for key in s.get("residents", {}): seen[int(key)] = true
	var ids: Array = seen.keys()
	ids.sort()
	return ids

static func hold(s: Dictionary,item: String) -> void:
	var pc: Dictionary=s.player_control
	if not pc.work.is_empty(): pc.notice="Finish or cancel work before changing what you hold."; return
	pc.held_item=item if Inventory.amount(s,s.player,item)>0 else ""
	pc.held_quantity=mini(5,Inventory.amount(s,s.player,item)) if not pc.held_item.is_empty() else 0
	pc.notice="Holding %d %s. F puts it down." % [pc.held_quantity,item] if pc.held_quantity>0 else "Hands empty."
static func reconcile(s: Dictionary) -> void:
	var pc: Dictionary=s.player_control
	pc.held_quantity=mini(pc.held_quantity,Inventory.amount(s,s.player,pc.held_item))
	if pc.held_quantity<=0: pc.held_item=""; pc.held_quantity=0
static func stop(s: Dictionary) -> void:
	var pc: Dictionary=s.player_control
	if not pc.work.is_empty() and pc.work.kind=="saw":
		var ws: Dictionary=s.workshops.get(str(pc.work.target),{})
		if not ws.is_empty(): ws.player_operator=0; ws.status="Player stopped; batch retained"
	pc.work={}
static func interact(sim: RefCounted, preferred: int = 0) -> void:
	var s: Dictionary=sim.state
	var pc: Dictionary=s.player_control
	if not pc.work.is_empty(): stop(s); pc.notice="Stopped working."; return
	if int(pc.get("carrying", {}).get("id", 0)) != 0: load("res://sim/player/carrying.gd").put_down(s); return   # F puts a carried body down
	if not s.player_health.treatment.is_empty(): pc.notice="Finish treatment first, or move to cancel it."; return
	if Health.incapacitated(s): pc.notice="Too injured to work. Press H to treat your injuries."; return
	reconcile(s)
	var id: int=target(s,preferred)
	var e: Dictionary=s.entities.get(str(id),{})
	if e.get("kind", "") == "market_stall":
		load("res://sim/economy/stall_service.gd").request(sim, id)   # trade once the keeper is behind the counter
		return
	if pc.held_quantity>0:
		var destination: int=0
		if not e.is_empty() and e.kind in ["warehouse","market","sawmill","construction","stash"] and s.inventories.has(str(id)): destination=id
		if destination==0:
			var cell: Array=s.entities[str(s.player)].cell
			for existing in s.entities.values():
				if existing.kind=="stash" and existing.cell==cell: destination=existing.id; break
			if destination==0:
				destination=World.add_entity(sim,"stash","Dropped supplies",cell)
				Inventory.create(s,destination,1000)
		var moved := Inventory.transfer(s,s.player,destination,pc.held_item,pc.held_quantity)
		pc.notice="Put down %d %s." % [pc.held_quantity,pc.held_item] if moved.ok else "Cannot put down: "+moved.error_code
		if moved.ok: pc.held_item=""; pc.held_quantity=0
		return
	if e.is_empty(): pc.notice="Move next to an object or person, then press F."; return
	if e.kind in ["resident","warehouse","market"]:
		pc.ui_target=id; pc.ui_nonce+=1; pc.ui_kind="trade"; pc.ui_tab="trade"; pc.notice="Interacting with "+e.name
	elif e.kind=="stash": take(s,id,first_item(s,id))
	elif e.kind=="office":
		# The weapon rack: return the gun you carry (and its ammunition), or take one (a rifle first).
		var Guns = load("res://sim/combat/shotgun.gd")
		var mine: String = ""
		for gun in Guns.GUNS:
			if mine.is_empty() and Inventory.amount(s,s.player,gun)>0: mine = gun
		if not mine.is_empty():
			var ammo: String = str(Guns.WEAPONS[mine].ammo)
			var rounds: int=Inventory.amount(s,s.player,ammo)
			Inventory.transfer(s,s.player,id,mine,1)
			if rounds>0: Inventory.transfer(s,s.player,id,ammo,rounds)
			if s.has("shotgun"): s.shotgun.equipped=false; s.shotgun.reloading=false; s.shotgun.loaded=0
			pc.notice="You return the %s and its %ss to the rack." % [mine, ammo]
		else:
			var taken: String = ""
			for gun in Guns.GUNS:
				if taken.is_empty() and Inventory.amount(s,id,gun)>0: taken = gun
			if taken.is_empty(): pc.notice="The rack is empty."
			else:
				var ammo: String = str(Guns.WEAPONS[taken].ammo)
				Inventory.transfer(s,id,s.player,taken,1)
				Inventory.transfer(s,id,s.player,ammo,mini(10,Inventory.amount(s,id,ammo)))
				pc.notice="You take a %s and %ss. X readies it, R reloads." % [taken, ammo]
	elif e.kind=="chest":
		Looting.open(s,id)
	elif e.kind=="ore":
		if Inventory.amount(s,id,"ore")==0: pc.notice="The rock has been mined out."; return
		pc.work={"kind":"mine","target":id,"item":"ore","progress":0,"ticks":40,"cell":s.entities[str(s.player)].cell.duplicate()}
		pc.notice="Mining iron ore. F stops; moving cancels."
	elif e.kind in ["tree","farm"]:
		var item: String="log" if e.kind=="tree" else ("food" if Inventory.amount(s,id,"food")>0 else "rye")
		for job in s.jobs.values():
			if job.target==id and job.owner!=0: pc.notice="A villager is already working here."; return
		if e.kind=="farm" and Inventory.amount(s,id,item)==0:
			var field: Dictionary=Crops.plot_for_farm(s,id)
			if not field.is_empty() and Crops.stage(field)==5: Crops.harvest(s,field)
			elif not field.is_empty(): pc.notice="The rye is still growing: %s." % Crops.stage_name(field); return
		if e.kind=="tree" and Inventory.amount(s,id,item)==0: pc.notice="Only a stump is left here."; return
		if Inventory.amount(s,id,item)==0: pc.notice="Nothing left to gather."; return
		# A standing tree is chopped down first; once it lies on the ground its wood can be gathered.
		var kind: String="harvest"
		var ticks: int=20
		if e.kind=="tree":
			kind="gather" if e.get("felled",false) else "chop"
			ticks=12 if kind=="gather" else 34
		pc.work={"kind":kind,"target":id,"item":item,"progress":0,"ticks":ticks,"cell":s.entities[str(s.player)].cell.duplicate()}
		pc.notice="Chopping the tree down. F stops; moving cancels." if kind=="chop" else "Working. F stops; moving cancels."
	elif e.kind=="sawmill":
		var ws: Dictionary=s.workshops[str(id)]
		var recipe: Dictionary=ws.get("batch_recipe",s.recipes[ws.recipe])
		if ws.active and ws.get("player_operator",0)==0: pc.notice="The sawyer has an active batch. Try after it finishes."; return
		if Inventory.amount(s,id,recipe.output)>0: take(s,id,recipe.output); return
		if not ws.enabled: pc.notice="This machine is disabled."; return
		if Inventory.amount(s,id,recipe.input)<recipe.input_quantity: pc.notice="Bring %d %s, hold it in I, and press F here to load the machine." % [recipe.input_quantity,recipe.input]; return
		if s.entities[str(s.player)].cell!=World.Fixtures.interaction_cell(s,id): pc.notice="Stand at the operator position below the bench."; return
		for npc in s.residents.values():
			if s.entities[str(npc.id)].cell == s.entities[str(s.player)].cell:
				pc.notice="The sawyer is at the controls. Use the machine when the position is free."; return
		ws.batch_recipe=recipe.duplicate(true); ws.batch_local=true; ws.batch+=1; ws.progress=0; ws.active=true; ws.work_ticks=recipe.work_ticks; ws.player_operator=s.player
		pc.work={"kind":"saw","target":id,"progress":0,"ticks":recipe.work_ticks,"cell":s.entities[str(s.player)].cell.duplicate()}
		pc.notice="Operating the saw. F stops; moving cancels."
	else: pc.notice="No available interaction."
static func first_item(s: Dictionary,id: int) -> String:
	for item in ["log","plank","food","bandage","antiseptic"]:
		if Inventory.amount(s,id,item)>0: return item
	return ""
static func take(s: Dictionary,id: int,item: String) -> void:
	var pc: Dictionary=s.player_control
	if not s.entities.has(str(id)) or not near(s,s.entities[str(id)]) or s.entities[str(id)].kind not in ["stash","sawmill"]: pc.notice="Move closer to collect goods."; return
	if pc.held_quantity>0: pc.notice="Put down or stow what you are holding first."; return
	if s.entities[str(id)].kind=="sawmill":
		var ws: Dictionary=s.workshops[str(id)]
		if ws.active and item==ws.get("batch_recipe",s.recipes[ws.recipe]).input: pc.notice="These inputs belong to an active batch."; return
	var quantity: int=mini(5,mini(Inventory.amount(s,id,item),Inventory.available(s,s.player)))
	var result := Inventory.transfer(s,id,s.player,item,quantity)
	if result.ok: pc.held_item=item; pc.held_quantity=quantity; pc.notice="Picked up %d %s." % [quantity,item]
	else: pc.notice="Cannot pick up: "+result.error_code
static func trade(sim: RefCounted,payload: Dictionary) -> void:
	var s: Dictionary=sim.state
	var pc: Dictionary=s.player_control
	var id: int=int(payload.get("target",0))
	if not s.entities.has(str(id)) or not near(s,s.entities[str(id)]): pc.notice="Move closer to trade."; return
	var e: Dictionary=s.entities[str(id)]
	if e.kind not in ["resident","warehouse","market","market_stall"]: return
	if e.kind=="resident":
		var npc: Dictionary=s.residents[str(id)]
		if npc.job!=0 or npc.get("work_cargo",false) or npc.get("production_delivery",false): pc.notice="They are carrying work supplies and cannot trade right now."; return
	var item: String=payload.get("item","")
	if e.kind == "market_stall" and item not in e.sale_items:
		pc.notice = "This stall does not trade that item."
		return
	var Stalls = load("res://sim/economy/stall_service.gd")
	if e.kind == "market_stall" and not Stalls.staffed(s, e):
		pc.notice = "Wait for someone to come to the counter."
		return
	var buy: bool=payload.get("buy",true)
	var price: int=Stalls.price(s,int(e.settlement),item,buy,id)
	# How many: the number asked for (or everything, -1), as far as stock, coins and room allow.
	var seller: int = id if buy else s.player
	var buyer: int = s.player if buy else id
	var wanted: int = int(payload.get("quantity", 1))
	var quantity: int = Inventory.amount(s, seller, item) if wanted < 0 else mini(wanted, Inventory.amount(s, seller, item))
	quantity = mini(quantity, mini(int(s.accounts.get(str(buyer), 0)) / maxi(1, price), Inventory.available(s, buyer)))
	if quantity <= 0:
		pc.notice = "Nothing to trade: " + ("they have none, or you cannot pay or carry it." if buy else "you have none, or they cannot pay for it.")
		return
	var result := Market.transact(s,seller,buyer,item,quantity,price,e.settlement)
	pc.notice=("You %s %d %s for %d coins." % ["buy" if buy else "sell", quantity, item, quantity * price]) if result.ok else "Trade failed: "+result.error_code
	# Honest business is remembered kindly (a small, quickly fading memory: society.gd).
	var keeper: Dictionary = Stalls.counterpart(s, id)
	if result.ok and not keeper.is_empty() and s.has("factions"):
		load("res://sim/factions/society.gd").remember(s, int(keeper.id), "paid_well", int(s.player), "The stranger traded fairly with me.")
	reconcile(s)
static func update(sim: RefCounted) -> void:
	var s: Dictionary=sim.state
	if not s.has("player_control"): return
	var pc: Dictionary=s.player_control
	reconcile(s)
	if pc.work.is_empty(): return
	var work: Dictionary=pc.work
	if s.entities[str(s.player)].cell!=work.cell or Health.incapacitated(s): stop(s); pc.notice="Work cancelled."; return
	var arms: int=0
	for part in ["left_hand","right_hand","left_forearm","right_forearm"]: arms+=s.player_health.parts[part].damage
	if arms>=40 and s.tick%2!=0: return
	if work.kind=="saw":
		var ws: Dictionary=s.workshops.get(str(work.target),{})
		if ws.is_empty() or not ws.enabled: stop(s); pc.notice="Machine unavailable."; return
		ws.progress+=1; work.progress=ws.progress; ws.status="Player operating saw"
		if Recipes.finish(s,ws):
			if sim.random_int("player:work_accident",0,7)==0:
				var part: String=["left_hand","right_hand","left_forearm","right_forearm"][sim.random_int("player:work_accident",0,3)]
				Health.injure(s,part,24,"cut")
			stop(s); pc.notice="Batch complete. F collects the output."
	else:
		work.progress+=1
		if work.progress>=work.ticks and work.kind=="chop":
			# The tree comes down; the logs stay with the fallen trunk until they are gathered.
			var tree: Dictionary=s.entities[str(work.target)]
			tree.felled=true; tree.felled_tick=s.tick
			if sim.random_int("player:work_accident",0,11)==0:
				var hurt: String=["right_hand","left_hand","right_forearm","left_forearm"][sim.random_int("player:work_accident",0,3)]
				Health.injure(s,hurt,18,"cut")
			pc.work={}; pc.notice="Timber! The tree falls. Press F at it to gather the wood."
		elif work.progress>=work.ticks:
			var quantity: int=mini(5,mini(Inventory.amount(s,work.target,work.item),Inventory.available(s,s.player)))
			var result := Inventory.transfer(s,work.target,s.player,work.item,quantity)
			if result.ok: pc.held_item=work.item; pc.held_quantity=quantity
			pc.work={}; pc.notice="Gathered supplies." if result.ok else "Could not gather: "+result.error_code

static func prompt(s: Dictionary,preferred: int = 0) -> String:
	if not s.has("player_control"): return ""
	var pc: Dictionary=s.player_control
	for npc in s.get("residents",{}).values():
		if npc.get("arrest",{}).get("phase","")=="standoff" and not pc.get("surrender",false): return "F: SURRENDER (raise your hands) · or run"
	if pc.get("restrained",false): return "You are under arrest."
	if pc.get("escorted",false): return "The sheriff is seeing you out."
	var warning: String=""
	for part in s.player_health.parts.values():
		if part.bleeding: warning="BLEEDING · Press H.  "; break
	if not pc.work.is_empty(): return warning+"F: stop %s · %d/%d" % [pc.work.kind,pc.work.progress,pc.work.ticks]
	if pc.held_quantity>0: return warning+"F: put down %d %s · I: stow" % [pc.held_quantity,pc.held_item]
	var id: int=target(s,preferred)
	return warning+("F: interact with "+s.entities[str(id)].name if id!=0 else pc.notice)

static func validate(s: Dictionary) -> String:
	if not s.has("player_control"): return ""
	var pc: Variant=s.player_control
	if not pc is Dictionary or not pc.get("held_item") is String or not pc.get("held_quantity") is int or not pc.get("work") is Dictionary or not pc.get("notice") is String: return "Invalid player controls"
	if pc.held_quantity<0 or pc.held_quantity>Inventory.amount(s,s.player,pc.held_item): return "Invalid held quantity"
	for field in ["ui_target","ui_nonce","next_move"]:
		if not pc.get(field) is int or pc[field]<0: return "Invalid player control value"
	var work: Dictionary=pc.work
	if not work.is_empty():
		if work.get("kind","") not in ["chop","gather","harvest","mine","saw"] or not work.get("target") is int or not s.entities.has(str(work.target)): return "Invalid player work target"
		if not work.get("progress") is int or not work.get("ticks") is int or work.progress<0 or work.ticks<1 or not work.get("cell") is Array or work.cell.size()!=2: return "Invalid player work progress"
	return ""
