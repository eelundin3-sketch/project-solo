extends RefCounted
## Click-to-interact: what the player can do to whatever they click, and the doing of it.
## `options` lists the actions for a menu; `request` performs one, first walking to the target
## if it is out of reach; `update` finishes a pending walk-then-act.
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Actions = preload("res://sim/player/player_actions.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Unarmed = preload("res://sim/combat/unarmed.gd")
const Households = preload("res://sim/entities/households.gd")
const Needs = preload("res://sim/entities/needs.gd")
const Nav = preload("res://sim/movement/navigation.gd")
const Society = preload("res://sim/factions/society.gd")
const Looting = preload("res://sim/player/looting.gd")
const Outfits = preload("res://sim/entities/outfits.gd")
const Sleep = preload("res://sim/player/sleep.gd")
## What a piece of furniture or a fixture is called in the menu, and a line about it.
const PART_NAMES := {"bed": "Bed", "table": "Table", "chair": "Chair", "lamp": "Lamp", "chest": "Chest", "shelf": "Shelves",
	"booking_desk": "Booking desk", "locker": "Locker", "toilet": "Toilet", "weapon_rack": "Weapon rack", "stockpile": "Stockpile",
	"saw": "Saw bench", "oven": "Oven", "forge": "Forge", "workshop_storage": "Material rack", "stall": "Stall"}
const PART_LINES := {"table": "A plain wooden table.", "chair": "A wooden chair.", "lamp": "An oil lamp.", "shelf": "Shelves of odds and ends.",
	"booking_desk": "Where prisoners are booked in and the sheriff does his paperwork.", "locker": "Prisoners' belongings are kept in here.",
	"toilet": "A bucket toilet.", "bed": "A bed.", "stockpile": "The town's goods, stacked.", "workshop_storage": "Materials waiting to be worked."}
const ITEM_NAMES := {"log": "logs", "plank": "planks", "food": "food", "rye": "rye", "bandage": "bandages", "antiseptic": "antiseptic", "shell": "shells", "shotgun": "shotgun", "rifle": "rifle", "cartridge": "cartridges", "tool": "iron tools", "ore": "iron ore", "lantern": "lantern"}

static func _opt(id: String, label: String, icon: String, enabled: bool = true, reason: String = "") -> Dictionary:
	return {"id": id, "label": label, "icon": icon, "enabled": enabled, "reason": reason}

static func _items(s: Dictionary, id: int) -> Dictionary:
	return s.inventories.get(str(id), {}).get("items", {})

## The furniture or fixture a click landed on: part is "furniture:<index>" or "fixture:<index>".
static func part_item(s: Dictionary, id: int, part: String) -> Dictionary:
	var e: Dictionary = s.entities.get(str(id), {})
	var bits := part.split(":")
	if bits.size() != 2 or not bits[0] in ["furniture", "fixture"]: return {}
	var list: Array = e.get("furniture" if bits[0] == "furniture" else "fixtures", [])
	var index := int(bits[1])
	return list[index] if index >= 0 and index < list.size() else {}

static func part_index(part: String) -> int:
	var bits := part.split(":")
	return int(bits[1]) if bits.size() == 2 else -1

## The menu title for a click: the piece of furniture when there is one, else the thing itself.
static func title(s: Dictionary, id: int, part: String = "") -> String:
	var item := part_item(s, id, part)
	if not item.is_empty(): return PART_NAMES.get(item.kind, String(item.kind).capitalize())
	return String(s.entities.get(str(id), {}).get("name", ""))

## Options for one piece of furniture or one fixture inside a building: only what that thing does.
static func _part_options(s: Dictionary, building: Dictionary, part: String) -> Array:
	var result: Array = []
	var item := part_item(s, int(building.id), part)
	if item.is_empty(): return result
	match item.kind:
		"weapon_rack":
			var has_gun: bool = load("res://sim/combat/shotgun.gd").owns(s)
			result.append(_opt("rack", "Return your gun" if has_gun else "Take a rifle", "gun", has_gun or Inventory.amount(s, building.id, "rifle") > 0 or Inventory.amount(s, building.id, "shotgun") > 0, "The rack is empty"))
		"stockpile":
			if building.kind in ["warehouse", "market"]: result.append(_opt("trade", "Trade / take supplies", "talk"))
		"saw", "oven", "forge", "workshop_storage":
			result.append(_opt("operate", "Use / collect", "hand"))
		"bed":
			var reason := Sleep.problem(s, int(building.id), part_index(part))
			result.append(_opt("sleep", "Sleep", "sun", reason.is_empty(), reason))
	result.append(_opt("examine", "Look at", "eye"))
	return result

## Menu entries for a target. `icon` names a pictogram drawn by the menu. Inside a building only
## the furniture or fixture that was clicked has actions (`part`); bare floor has none.
static func options(s: Dictionary, id: int, part: String = "") -> Array:
	var result: Array = []
	if not s.entities.has(str(id)): return result
	var e: Dictionary = s.entities[str(id)]
	if e.has("footprint") and id != s.player: return _part_options(s, e, part)
	if id == s.player:
		result.append(_opt("eat", "Eat", "food", Inventory.amount(s, s.player, "food") > 0, "No food"))
		result.append(_opt("drink", "Drink", "drop", Needs.near_water(s), "Stand by a well"))
		result.append(_opt("wash", "Wash up", "drop", Needs.near_water(s), "Stand by a well"))
		result.append(_opt("shave", "Shave & haircut (3 coins)", "hand"))
		result.append(_opt("wardrobe", "Clothing", "shirt"))
		result.append(_opt("inventory", "Inventory", "bag"))
		result.append(_opt("health", "Check wounds", "heart"))
		return result
	match e.get("kind", ""):
		"resident":
			var npc: Dictionary = s.residents.get(str(id), {})
			var dead: bool = not npc.is_empty() and npc.health <= 0
			var down: bool = (Brawl.knocked(s, npc) or dead) if not npc.is_empty() else false
			var asleep: bool = not npc.get("sleeping", {}).is_empty()
			if down or asleep:
				result.append(_opt("loot", "Search & loot", "hand"))
				var Carrying = load("res://sim/player/carrying.gd")
				if Carrying.carried(s) == int(npc.id): result.append(_opt("put_down", "Put them down", "hand"))
				elif Carrying.can_carry(s, npc): result.append(_opt("carry", "Carry over your shoulder", "hand"))
				if dead: pass
				elif asleep: result.append(_opt("wake", "Wake up", "sun"))
				else:
					if npc.get("knock", {}).get("kind", "") == "fall": result.append(_opt("help_up", "Help up", "hand"))
					else: result.append(_opt("help_up", "Help up", "hand", false, "Unconscious"))
					result.append(_opt("kick", "Kick (1.5× a punch)", "fist"))
			else:
				result.append(_opt("talk", "Talk", "talk"))
				if npc.occupation == "Barkeep":
					var Capital = load("res://sim/settlement/capital.gd")
					result.append(_opt("buy_drink", "Buy a drink (%d c)" % Capital.DRINK_PRICE, "bag", Capital.serving(s, npc), "The bar isn't open"))
				if npc.occupation not in ["Sheriff", "Child"]: result.append(_opt("trade", "Trade", "bag"))
				result.append(_opt("ask_family", "Ask about their family", "talk"))
				result.append(_opt("ask_news", "Ask for news", "talk"))
				result.append(_opt("punch", "Punch", "fist"))
				result.append(_opt("shove", "Shove", "fist"))
				if bool(s.player_control.get("crouching", false)):
					# Sneaking: a silent takedown from behind (takedown.gd); greyed out with the reason
					# when they would see you coming (being next to them is handled by walking up).
					var Takedown = load("res://sim/combat/takedown.gd")
					var aware: String = Takedown.aware_of_player(s, npc)
					result.append(_opt("takedown_ko", "Knock out from behind", "fist", aware.is_empty(), aware))
					result.append(_opt("takedown_kill", "Kill silently", "fist", aware.is_empty(), aware))
			if not npc.is_empty() and int(npc.get("bleeding_until", 0)) > s.tick:
				result.append(_opt("bandage", "Bandage wound", "heart", Inventory.amount(s, s.player, "bandage") > 0, "No bandages"))
			result.append(_opt("examine", "Look at", "eye"))
		"tree":
			var logs: int = int(_items(s, id).get("log", 0))
			if logs == 0: result.append(_opt("examine", "Only a stump", "eye"))
			elif e.get("felled", false):
				result.append(_opt("gather", "Gather wood", "log"))
				result.append(_opt("examine", "Look at", "eye"))
			else:
				result.append(_opt("chop", "Chop down", "axe"))
				result.append(_opt("examine", "Look at", "eye"))
		"farm":
			result.append(_opt("harvest", "Harvest", "hand"))
			result.append(_opt("examine", "Check the crop", "eye"))
		"ore":
			var ore: int = int(_items(s, id).get("ore", 0))
			result.append(_opt("mine", "Mine iron ore", "pick", ore > 0, "Nothing left to mine"))
			result.append(_opt("examine", "Look at", "eye"))
		"chest":
			var stored: int = 0
			for count in _items(s, id).values(): stored += int(count)
			result.append(_opt("loot", "Open chest", "chest"))
			result.append(_opt("examine", "Look at", "eye"))
		"stash":
			var items: Dictionary = _items(s, id)
			result.append(_opt("pickup_all", "Pick up everything", "hand", not items.is_empty(), "Nothing here"))
			for item in items:
				if int(items[item]) > 0: result.append(_opt("pickup:" + item, "Pick up %d %s" % [items[item], ITEM_NAMES.get(item, item)], "hand"))
		"warehouse", "market":
			result.append(_opt("trade", "Trade / take supplies", "talk"))
			result.append(_opt("examine", "Look at", "eye"))
		"market_stall":
			result.append(_opt("trade", "Trade", "talk"))
		"office":
			var has_gun: bool = load("res://sim/combat/shotgun.gd").owns(s)
			result.append(_opt("rack", "Return your gun" if has_gun else "Take a rifle", "gun", has_gun or Inventory.amount(s, id, "rifle") > 0 or Inventory.amount(s, id, "shotgun") > 0, "The rack is empty"))
			result.append(_opt("examine", "Look at", "eye"))
		"sawmill", "bakery", "forge":
			result.append(_opt("operate", "Use / collect", "hand"))
			result.append(_opt("examine", "Look at", "eye"))
		_:
			result.append(_opt("examine", "Look at", "eye"))
	return result

## One short line under the menu title.
static func subtitle(s: Dictionary, id: int) -> String:
	var e: Dictionary = s.entities.get(str(id), {})
	match e.get("kind", ""):
		"resident":
			var npc: Dictionary = s.residents.get(str(id), {})
			var state := ""
			if npc.health <= 0: state = " · dead"
			elif Brawl.knocked(s, npc): state = " · knocked down" if npc.get("knock", {}).get("kind", "") == "fall" else " · unconscious"
			elif not npc.get("sleeping", {}).is_empty(): state = " · asleep"
			elif not npc.get("brawl", {}).is_empty(): state = " · angry"
			return String(npc.get("occupation", "Villager")) + state
		"tree":
			var logs: int = int(_items(s, id).get("log", 0))
			return "Stump" if logs == 0 else ("Fallen · %d logs" % logs if e.get("felled", false) else "Standing tree")
		"ore": return "%d iron ore left" % int(_items(s, id).get("ore", 0))
		"stash": return "Dropped items"
	return ""

static func describe(s: Dictionary, id: int, part: String = "") -> String:
	var e: Dictionary = s.entities.get(str(id), {})
	if e.is_empty(): return ""
	var item := part_item(s, id, part)
	if not item.is_empty():
		if item.kind == "bed" and str(item.get("for", "")) == "prisoner": return "A hard cot in the jail cell."
		if item.kind == "bed" and str(item.get("for", "")) == "sheriff": return "A sheriff's bed."
		if item.kind == "weapon_rack": return "The %s's gun rack: %d rifle%s, %d shotgun%s." % [e.name, Inventory.amount(s, id, "rifle"), "" if Inventory.amount(s, id, "rifle") == 1 else "s", Inventory.amount(s, id, "shotgun"), "" if Inventory.amount(s, id, "shotgun") == 1 else "s"]
		return String(PART_LINES.get(item.kind, "%s in %s." % [title(s, id, part), e.name]))
	match e.get("kind", ""):
		"resident":
			var npc: Dictionary = s.residents.get(str(id), {})
			var mood: String = "calm" if int(npc.get("anger", 0)) < 30 else "angry"
			return "%s, a %s. %s. They look %s. Wearing %s. %s" % [e.name, String(npc.get("occupation", "villager")).to_lower(), npc.get("status", "Resting"), mood, Outfits.describe(s, id), load("res://sim/entities/family_economy.gd").describe(s, npc)]
		"tree":
			var logs: int = int(_items(s, id).get("log", 0))
			return "%s: %s." % [e.name, "only a stump" if logs == 0 else ("fallen, %d logs to gather" % logs if e.get("felled", false) else "standing, about %d logs of timber" % logs)]
		"ore":
			return "%s: %d iron ore left." % [e.name, int(_items(s, id).get("ore", 0))]
		"farm":
			return "%s." % e.name
		"signpost":
			return "A signpost: %s." % e.get("directions", "")
	return String(e.name)

## Adjacent cells from which `e` (or the clicked piece of furniture in it) can be used.
static func _stand_cells(s: Dictionary, e: Dictionary, part: String = "") -> Array:
	var cells: Array = []
	if part.begins_with("furniture:"):
		var item := part_item(s, int(e.id), part)
		if not item.is_empty():
			var r: Array = item.rect
			for y in range(r[1] - 1, r[1] + r[3] + 1):
				for x in range(r[0] - 1, r[0] + r[2] + 1):
					if x < r[0] or x >= r[0] + r[2] or y < r[1] or y >= r[1] + r[3]: cells.append([x, y])
			return cells
	if e.has("rock_rect"):
		var r: Array = e.rock_rect
		for y in range(r[1] - 1, r[1] + r[3] + 1):
			for x in range(r[0] - 1, r[0] + r[2] + 1):
				if x < r[0] or x >= r[0] + r[2] or y < r[1] or y >= r[1] + r[3]: cells.append([x, y])
	elif not e.get("fixtures", []).is_empty():
		cells.append(World.Fixtures.interaction_cell(s, e.id))
	else:
		for offset in [[0, 1], [0, -1], [1, 0], [-1, 0]]: cells.append([e.cell[0] + offset[0], e.cell[1] + offset[1]])
	return cells

## Beside the target: the clicked piece of furniture when there is one, else the thing itself.
static func _within_reach(s: Dictionary, e: Dictionary, part: String) -> bool:
	if part.begins_with("furniture:"):
		var item := part_item(s, int(e.id), part)
		if item.is_empty(): return false
		var p: Array = s.entities[str(s.player)].cell
		var r: Array = item.rect
		return p[0] >= r[0] - 1 and p[0] <= r[0] + r[2] and p[1] >= r[1] - 1 and p[1] <= r[1] + r[3]
	return Actions.near(s, e)

## Perform now when in reach, otherwise walk there and perform on arrival.
static func request(sim: RefCounted, id: int, action: String, part: String = "") -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	if not s.entities.has(str(id)): return
	var e: Dictionary = s.entities[str(id)]
	pc.pending = {}
	var talking_distance: bool = (action in ["ask_family", "ask_news", "ask_work", "talk", "persuade", "ask_help", "accept_request", "hand_over", "turn_in", "pay_fine"] or action.begins_with("say_") or action.begins_with("bribe_")) and Actions.distance(s.entities[str(s.player)].cell, e.cell) <= 4
	if id == s.player or action in ["examine", "inventory", "health", "wardrobe"] or talking_distance or _within_reach(s, e, part):
		perform(sim, id, action, part)
		return
	var from: Array = s.entities[str(s.player)].cell
	var best: Array = []
	var best_distance := 9999
	for cell in _stand_cells(s, e, part):
		if not World.walkable(s, cell): continue
		var distance: int = absi(cell[0] - from[0]) + absi(cell[1] - from[1])
		if distance < best_distance:
			var route := Nav.request_path(s, from, cell)
			if route.ok:
				best = route.path
				best_distance = distance
				s.player_travel_goal = cell.duplicate()
	if best.is_empty() and best_distance == 9999:
		pc.notice = "You cannot reach %s." % e.name
		return
	s.player_path = best
	pc.pending = {"target": id, "action": action, "part": part, "since": s.tick, "repath": s.tick + 12}
	pc.notice = "Walking to the %s…" % title(s, id, part).to_lower() if not part.is_empty() else "Walking to %s…" % e.name

## Finishes a pending walk-then-act, re-aiming at targets that move.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	var pending: Dictionary = s.get("player_control", {}).get("pending", {})
	if pending.is_empty(): return
	var pc: Dictionary = s.player_control
	var id: int = int(pending.target)
	if not s.entities.has(str(id)) or s.tick - int(pending.since) > 900:
		pc.pending = {}
		return
	var e: Dictionary = s.entities[str(id)]
	var part: String = str(pending.get("part", ""))
	if _within_reach(s, e, part):
		s.player_path = []
		pc.pending = {}
		perform(sim, id, str(pending.action), part)
	elif s.player_path.is_empty() or s.tick >= int(pending.repath):
		pending.repath = s.tick + (5 if pc.get("travel_run", false) else 10)
		var from: Array = s.entities[str(s.player)].cell
		var best: Array = []
		var best_distance := 9999
		for cell in _stand_cells(s, e, part):
			if not World.walkable(s, cell): continue
			var distance: int = absi(cell[0] - from[0]) + absi(cell[1] - from[1])
			if distance < best_distance:
				var route := Nav.request_path(s, from, cell)
				if route.ok:
					best = route.path
					best_distance = distance
		if best.is_empty() and s.player_path.is_empty(): pc.pending = {}
		elif not best.is_empty(): s.player_path = best

static func perform(sim: RefCounted, id: int, action: String, part: String = "") -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var e: Dictionary = s.entities.get(str(id), {})
	if e.is_empty(): return
	if action.begins_with("pickup:"):
		var item: String = action.substr(7)
		var moved := Inventory.transfer(s, id, s.player, item, mini(Inventory.amount(s, id, item), Inventory.available(s, s.player)))
		pc.notice = "Picked up the %s." % ITEM_NAMES.get(item, item) if moved.ok else "Your pack is full."
		return
	match action:
		"examine": pc.notice = describe(s, id, part)
		"buy_drink": pc.notice = load("res://sim/settlement/capital.gd").buy_drink(s, s.residents.get(str(id), {}))
		"sleep": Sleep.lie_down(s, id, part_index(part))
		"eat": pc.notice = Needs.eat(s)
		"drink": pc.notice = Needs.drink(s)
		"wash": pc.notice = load("res://sim/player/look.gd").wash(s) if Needs.near_water(s) else "Stand by a well to wash."
		"shave": pc.notice = load("res://sim/player/look.gd").shave(s)
		"inventory", "health": pass   # opened by the interface
		"wardrobe": Looting.open(s, s.player, "wardrobe")
		"pickup_all": _take_everything(sim, id)
		"trade", "chop", "gather", "harvest", "mine", "operate", "rack":
			if action == "trade" and s.residents.has(str(id)): load("res://sim/entities/speech.gd").say(sim, id, "greet_player")
			Actions.interact(sim, id)
		"loot": Looting.open(s, id)
		"carry": load("res://sim/player/carrying.gd").pick_up(s, id)
		"say_friendly", "say_firm", "say_threaten", "persuade", "bribe_10", "bribe_25", "bribe_50", "ask_help", "accept_request", "hand_over":
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty(): return
			_met(s, id)
			var Talk = load("res://sim/player/talk.gd")
			if action.begins_with("say_"): pc.notice = Talk.say(sim, npc, action.substr(4))
			elif action == "persuade": pc.notice = Talk.persuade(sim, npc)
			elif action.begins_with("bribe_"): pc.notice = Talk.bribe(sim, npc, int(action.substr(6)))
			else:
				var answer: String = load("res://sim/player/requests.gd").perform(sim, npc, action)
				if not answer.is_empty(): pc.notice = answer
		"turn_in", "pay_fine":
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty(): return
			_met(s, id)
			var Notoriety = load("res://sim/law/notoriety.gd")
			pc.notice = Notoriety.turn_in(sim, npc) if action == "turn_in" else Notoriety.pay_fine(sim, npc)
		"takedown_ko", "takedown_kill":
			var npc: Dictionary = s.residents.get(str(id), {})
			pc.notice = load("res://sim/combat/takedown.gd").perform(sim, npc, action == "takedown_kill")
		"put_down": load("res://sim/player/carrying.gd").put_down(s)
		"help_up":
			var npc: Dictionary = s.residents.get(str(id), {})
			if not npc.is_empty(): Brawl.help_up(s, npc)
			pc.notice = "You help %s to their feet." % e.name
		"talk":
			# Opens the conversation window on its Talk tab (dialogue.gd lists what can be said).
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty(): return
			load("res://sim/entities/speech.gd").say(sim, id, "greet_player")
			pc.ui_target = id; pc.ui_nonce = int(pc.get("ui_nonce", 0)) + 1; pc.ui_kind = "trade"; pc.ui_tab = "talk"
			_met(s, id)
		"ask_family", "ask_news", "ask_work":
			var npc: Dictionary = s.residents.get(str(id), {})
			if npc.is_empty(): return
			var first: String = String(e.name).split(" ")[0]
			if action == "ask_work":
				var Professions = load("res://sim/settlement/professions.gd")
				var line: String = str(Professions.DESCRIPTIONS.get(npc.occupation, "I do what needs doing."))
				pc.notice = "%s: I'm a %s. %s" % [first, String(npc.occupation).to_lower(), line]
			elif action == "ask_family":
				var Family = load("res://sim/entities/family_economy.gd")
				var household: Dictionary = s.get("households", {}).get(str(npc.get("household", "")), {})
				var line: String = "I'm a %s." % String(npc.occupation).to_lower()
				if not household.is_empty() and household.members.size() > 1:
					line += " There are %d of us in the %s household, and we get by on what we earn." % [household.members.size(), Family.family_name(s, household)]
				else: line += " I keep house on my own."
				pc.notice = "%s: %s" % [first, line]
			else:
				var told: String = load("res://sim/economy/stall_service.gd").news(s, npc)
				pc.notice = "%s: %s" % [first, told]
				# Written in the journal (newest 30).
				var heard: Array = load("res://sim/player/player_status.gd").part(s, "heard", [])
				if heard.is_empty() or str(heard[-1].text) != told: heard.append({"text": told, "tick": int(s.tick), "from": String(e.name)})
				while heard.size() > 30: heard.pop_front()
			_met(s, id)
			load("res://sim/law/law.gd")._say(sim, id, pc.notice.substr(first.length() + 2).left(60))
		"wake":
			var sleeper: Dictionary = s.residents.get(str(id), {})
			if not sleeper.is_empty():
				Households.wake(s, sleeper)
				sleeper.anger = mini(100, int(sleeper.get("anger", 0)) + 6)
			pc.notice = "%s wakes up, grumbling." % e.name
		"bandage":
			var patient: Dictionary = s.residents.get(str(id), {})
			if not patient.is_empty() and int(patient.get("bleeding_until", 0)) > s.tick and Inventory.consume(s, s.player, "bandage", 1):
				load("res://sim/combat/bleeding.gd").stop(patient)
				pc.notice = "You bind %s's wound. The bleeding stops." % e.name
				# They (and their family) won't forget it, and word gets round (society.gd, chronicle).
				var entry: Dictionary = load("res://sim/world/chronicle.gd").record(s, "saved_life", int(patient.settlement), int(s.player), id, e.cell)
				load("res://sim/factions/society.gd").witnessed(s, id, "saved_life", int(s.player), "The stranger bound my wound and saved my life.", entry.witnesses, "helped")
			else: pc.notice = "There is nothing to bandage."
		"punch", "shove", "kick":
			var from: Array = s.entities[str(s.player)].cell
			var direction: Array = [signi(e.cell[0] - from[0]) * 1000, signi(e.cell[1] - from[1]) * 1000]
			if direction == [0, 0]: direction = [1000, 0]
			Unarmed.begin(s, "shove" if action == "kick" else action, direction)   # a shove at someone down becomes a kick

static func _take_everything(sim: RefCounted, id: int) -> void:
	var s: Dictionary = sim.state
	var pc: Dictionary = s.player_control
	var e: Dictionary = s.entities[str(id)]
	var taken: Array = []
	var items: Dictionary = _items(s, id).duplicate()
	for item in items:
		var amount: int = mini(int(items[item]), Inventory.available(s, s.player))
		if amount > 0 and Inventory.transfer(s, id, s.player, item, amount).ok: taken.append("%d %s" % [amount, ITEM_NAMES.get(item, item)])
	var coins: int = int(s.get("accounts", {}).get(str(id), 0))
	if coins > 0 and s.get("accounts", {}).has(str(s.player)):
		s.accounts[str(id)] -= coins
		s.accounts[str(s.player)] += coins
		taken.append("%d coins" % coins)
	if e.get("kind", "") == "resident" and s.has("factions") and not taken.is_empty(): Society.remember(s, id, "robbed", s.player, "The traveller went through my pockets.", -20)
	pc.notice = ("You take " + ", ".join(taken) + ".") if not taken.is_empty() else "There is nothing to take."

## Remembers that the player has met this person (for the journal).
static func _met(s: Dictionary, id: int) -> void:
	var met: Dictionary = load("res://sim/player/player_status.gd").part(s, "met", {})
	if not met.has(str(id)): met[str(id)] = int(s.tick)
