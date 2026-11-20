extends RefCounted
## Four quick-access slots (keys 1-4). A slot names an inventory item; using it readies
## that item: the shotgun is carried, anything else is taken in hand. Using the active
## slot again puts the item away.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Shotgun = preload("res://sim/combat/shotgun.gd")
const PlayerActions = preload("res://sim/player/player_actions.gd")
const SLOTS := 4
const ITEMS: Array[String] = ["rifle", "cartridge", "shotgun", "shell", "tool", "bandage", "antiseptic", "food", "rye", "log", "plank", "ore", "lantern"]

static func initialize(s: Dictionary) -> void:
	if not s.has("player") or not s.has("player_control") or s.has("hotbar"): return
	s.hotbar = {"slots": ["", "", "", ""], "active": 0}

## Weapons that go straight onto the hotbar when picked up, and leave it when they are put away.
const WEAPONS: Array[String] = ["rifle", "shotgun"]

## Called every tick: a newly acquired weapon takes the first free slot, however it was obtained
## (rack, chest, loot, the ground); a weapon you no longer carry frees its slot.
static func update(s: Dictionary) -> void:
	if not s.has("hotbar") or s.tick % 5 != 0: return
	var hotbar: Dictionary = s.hotbar
	var slots: Array = hotbar.slots
	for weapon in WEAPONS:
		var carried: bool = Inventory.amount(s, s.player, weapon) > 0
		var index: int = slots.find(weapon)
		if carried and index < 0:
			var free: int = slots.find("")
			if free >= 0:
				slots[free] = weapon
				s.player_control.notice = "%s placed in hotbar slot %d." % [weapon.capitalize(), free + 1]
			elif not hotbar.get("full_warned", false):
				hotbar.full_warned = true
				s.player_control.notice = "Your hotbar is full: free a slot to carry the %s on it." % weapon
		elif not carried and index >= 0:
			slots[index] = ""
		if carried and index >= 0: hotbar.full_warned = false

static func assign(s: Dictionary, slot: int, item: String) -> String:
	if not s.has("hotbar") or slot < 0 or slot >= SLOTS: return ""
	if item != "" and not ITEMS.has(item): return "That cannot go on the hotbar."
	var slots: Array = s.hotbar.slots
	if item != "":
		# An item lives in one slot at a time.
		for index in range(SLOTS):
			if slots[index] == item: slots[index] = ""
	slots[slot] = item
	return "Slot %d cleared." % (slot + 1) if item == "" else "%s placed in slot %d." % [item.capitalize(), slot + 1]

## Selects a slot (exactly one is always selected, slot 1 to begin with) and puts its item in
## hand: a shotgun is carried, anything else is held, an empty slot means empty hands. Pressing
## the selected slot again keeps it selected; only choosing another slot changes the selection.
static func use(s: Dictionary, slot: int) -> String:
	if not s.has("hotbar") or slot < 0 or slot >= SLOTS: return ""
	var hotbar: Dictionary = s.hotbar
	var item: String = hotbar.slots[slot]
	var pc: Dictionary = s.player_control
	var gun: Dictionary = s.get("shotgun", {})
	hotbar.active = slot
	if not item in WEAPONS and not gun.is_empty() and gun.equipped: Shotgun.toggle(s)   # lower it
	if item.is_empty():
		if pc.held_quantity > 0: PlayerActions.hold(s, "")
		return "Slot %d is empty. Assign an item in your inventory (I)." % (slot + 1)
	if Inventory.amount(s, s.player, item) < 1: return "You do not have any %s." % item
	if item in WEAPONS:
		if pc.held_quantity > 0: PlayerActions.hold(s, "")
		if not gun.is_empty() and gun.equipped and str(gun.get("kind", "")) != item: Shotgun.toggle(s)   # put the other gun away first
		if not gun.is_empty(): gun.kind = item
		return Shotgun.toggle(s) if gun.is_empty() or not gun.equipped else "%s ready." % item.capitalize()
	if pc.held_item != item: PlayerActions.hold(s, item)
	return "%s in hand." % item.capitalize()
