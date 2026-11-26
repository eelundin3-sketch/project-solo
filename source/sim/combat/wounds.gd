extends RefCounted
## What a bullet does to a body. Used for every shot that hits a person (the player's pellets on
## villagers, and a sheriff's shots on the player). Each hit picks a part with a seeded draw:
## legs 30%, arms 25%, torso 35%, head 10%. It leaves blood, and a hit to a leg, the torso or the
## head knocks the person down. Limb damage builds until the limb is disabled (see limbs.gd).
const Limbs = preload("res://sim/combat/limbs.gd")
const BodyHealth = preload("res://sim/combat/body_health.gd")
const Brawl = preload("res://sim/combat/brawl.gd")
const LIMB_WOUND := 22        # limb damage per pellet; three pellets disable a limb
const PELLET_HEALTH := 9
const TORSO_WOUND := 12
const HEAD_WOUND := 22

## {"area": "leg"|"arm"|"torso"|"head", "limb": "left_leg" ...} for a seeded roll. `aim` is where a
## careful shooter tries to hit: "legs" (to bring someone down without killing them) or "gun_arm"
## (the right arm, to make them drop the gun). An aimed shot lands there three times in four.
static func pick(sim: RefCounted, aim: String = "") -> Dictionary:
	if aim != "" and sim.random_int("wounds", 0, 99) < 75:
		if aim == "legs": return {"area": "leg", "limb": ("left" if sim.random_int("wounds", 0, 1) == 0 else "right") + "_leg"}
		if aim == "gun_arm": return {"area": "arm", "limb": "right_arm"}
	var roll: int = sim.random_int("wounds", 0, 99)
	var side: String = "left" if sim.random_int("wounds", 0, 1) == 0 else "right"
	if roll < 30: return {"area": "leg", "limb": side + "_leg"}
	if roll < 55: return {"area": "arm", "limb": side + "_arm"}
	if roll < 90: return {"area": "torso", "limb": ""}
	return {"area": "head", "limb": ""}

## A bullet or pellet hits `target` (a resident id or the player) standing at `cell`.
## `strength` scales the damage (1.0 for a pellet). `direction` is the way it was travelling.
static func shoot(sim: RefCounted, target: int, cell: Array, direction: Array, strength: float = 1.0, lethal: bool = false, aim: String = "") -> Dictionary:
	var s: Dictionary = sim.state
	var hit := pick(sim, "" if lethal else aim)
	if lethal and hit.area in ["arm", "leg"]:
		hit = {"area": "torso", "limb": ""} if sim.random_int("wounds", 0, 99) < 75 else {"area": "head", "limb": ""}
	var limb_amount: int = roundi(LIMB_WOUND * strength)
	var is_player: bool = target == int(s.get("player", -1))
	var health_hit: int = roundi(PELLET_HEALTH * strength)
	Brawl.add_blood(s, cell, direction, 2 if hit.area in ["torso", "head"] else 1)
	Brawl.event(s, "shot_hit", cell, direction)
	if is_player:
		_hit_player(s, hit, limb_amount, strength)
		var control: Dictionary = s.player_control
		control.impact_until = s.tick + 8
		control.impact_kind = "hit"
		if hit.area != "arm" and not Brawl.player_down(s):
			Brawl.knockdown(s, control, cell, "fall", direction)
	else:
		var npc: Dictionary = s.get("residents", {}).get(str(target), {})
		if npc.is_empty(): return hit
		npc.health = maxi(0, int(npc.health) - health_hit)
		if hit.area in ["arm", "leg"]: Limbs.wound_npc(s, target, hit.limb, limb_amount)
		elif hit.area == "head": npc.health = maxi(0, int(npc.health) - health_hit)
		npc.impact_until = s.tick + 8
		npc.impact_kind = "hit"
		if npc.job != 0:
			load("res://sim/jobs/job_board.gd").release(s, npc.job, "SHOT")
		npc.goal = ""
		npc.path = []
		npc.work_path = []
		if hit.area != "arm" and not Brawl.knocked(s, npc):
			Brawl.knockdown(s, npc, cell, "fall", direction)
		if int(npc.health) <= 0:
			Brawl.kill(sim, npc, "shot")
		else:
			load("res://sim/combat/bleeding.gd").open_wound(s, npc)   # it bleeds until it is bandaged
	return hit

static func _hit_player(s: Dictionary, hit: Dictionary, limb_amount: int, strength: float) -> void:
	var part: String
	match hit.area:
		"leg", "arm":
			var parts: Array = Limbs.LIMB_PARTS[hit.limb]
			part = parts[0 if (s.tick % 2 == 0) else 1]   # thigh or shin, upper arm or forearm
			BodyHealth.injure(s, part, limb_amount, "cut")
		"torso":
			BodyHealth.injure(s, "upper_torso" if s.tick % 2 == 0 else "lower_torso", roundi(TORSO_WOUND * strength), "cut")
		_:
			BodyHealth.injure(s, "head", roundi(HEAD_WOUND * strength), "cut")
	Limbs.refresh(s, int(s.player))
