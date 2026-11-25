extends RefCounted
## Villagers' open wounds. A gunshot opens a wound that bleeds until it is bandaged: every
## BLEED_EVERY ticks the villager loses a point of health for each open wound, and enough of that
## kills. Binding a wound takes BANDAGE_TICKS with a bandage in hand:
##   - a sheriff in a gunfight does it behind cover, between shots (gunfire.gd);
##   - anyone else with a bandage on them does it where they stand once they are not running;
##   - a villager without one walks to their home pantry or the storehouse to get one (residents.gd
##     goal "bandage").
## Plain data on the resident: `bleed_wounds` (open wounds), `bandaging` {since, until}. The older
## `bleeding_until` field is kept in step, for the blood drops and the player's Bandage option.
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const Limbs = preload("res://sim/combat/limbs.gd")
const BLEED_EVERY := 45        # ticks per point of health, per open wound
const BANDAGE_TICKS := 40
const MAX_WOUNDS := 3
const OPEN := 1 << 30          # bleeding_until while a wound is open (it has no natural end)

static func bleeding(npc: Dictionary) -> bool:
	return int(npc.get("bleed_wounds", 0)) > 0

static func open_wound(s: Dictionary, npc: Dictionary) -> void:
	npc.bleed_wounds = mini(MAX_WOUNDS, int(npc.get("bleed_wounds", 0)) + 1)
	npc.bleeding_until = OPEN

## All open wounds bound (by the villager, a sheriff, or the player's bandage).
static func stop(npc: Dictionary) -> void:
	npc.bleed_wounds = 0
	npc.bleeding_until = 0
	npc.bandaging = {}

## Hands that can tie a bandage, and nothing more pressing on.
static func can_bandage(s: Dictionary, npc: Dictionary) -> bool:
	return int(npc.health) > 0 and not Brawl.knocked(s, npc) and Limbs.arms_ok(s, int(npc.id)) >= 1 and s.tick >= int(npc.get("impact_until", 0))

## Starts binding the wounds with a bandage the villager carries.
static func begin(s: Dictionary, npc: Dictionary) -> bool:
	if Inventory.amount(s, int(npc.id), "bandage") <= 0 or not can_bandage(s, npc): return false
	npc.bandaging = {"since": s.tick, "until": s.tick + BANDAGE_TICKS}
	npc.path = []
	npc.status = "Bandaging a wound"
	return true

## Every tick: wounds bleed; bandaging finishes; the wounded see to it.
static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	for key in s.get("residents", {}):
		var npc: Dictionary = s.residents[key]
		if int(npc.health) <= 0 or not bleeding(npc):
			if not npc.get("bandaging", {}).is_empty(): npc.bandaging = {}
			continue
		if (s.tick + int(npc.id)) % BLEED_EVERY == 0:
			npc.health = maxi(0, int(npc.health) - int(npc.bleed_wounds))
			if int(npc.health) <= 0:
				Brawl.kill(sim, npc, "bled to death")
				continue
		var binding: Dictionary = npc.get("bandaging", {})
		if not binding.is_empty():
			if not can_bandage(s, npc):
				npc.bandaging = {}   # knocked down or hit again: start over later
			elif s.tick >= int(binding.until):
				Inventory.consume(s, int(npc.id), "bandage", 1)
				stop(npc)
				npc.status = "Bound the wound"
			continue
		# A sheriff in a gunfight binds his wounds behind cover (gunfire.gd); someone running for
		# cover waits until they get there.
		if str(npc.get("arrest", {}).get("phase", "")) == "engage": continue
		if not npc.get("cover_cycle", {}).is_empty() or not npc.get("collar", {}).is_empty(): continue   # mid-fight (bandits, a shootout with an outlaw)
		if not npc.get("fear", {}).is_empty() and not bool(npc.fear.get("arrived", false)): continue
		if Inventory.amount(s, int(npc.id), "bandage") > 0:
			begin(s, npc)
		elif int(npc.get("settlement", 0)) != 0 and npc.get("goal", "") != "bandage" and npc.get("fear", {}).is_empty() and npc.get("arrest", {}).is_empty() and can_bandage(s, npc) and s.tick >= int(npc.get("retry_at", 0)):
			load("res://sim/entities/residents.gd").set_goal(s, npc, "bandage")
