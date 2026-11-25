extends RefCounted
## What the conversation window offers for one person. The simulation decides; the window only
## draws these lists and submits the chosen option (as a context action). Later features add more
## talk options here (tone, favours, bribes, hiring); the window needs no change for them.
const Society = preload("res://sim/factions/society.gd")
const Reputation = preload("res://sim/factions/reputation.gd")

## The person behind a target: a resident, or whoever minds a stall.
static func person(s: Dictionary, target: int) -> Dictionary:
	return load("res://sim/economy/stall_service.gd").counterpart(s, target)

## Which tabs the window shows for `target`: "trade" where there is something to trade, "talk"
## whenever someone is there to talk to. Sheriffs and children don't trade.
static func tabs(s: Dictionary, target: int) -> Array:
	var e: Dictionary = s.get("entities", {}).get(str(target), {})
	var npc: Dictionary = person(s, target)
	var result: Array = []
	if e.get("kind", "") == "market_stall" or (not npc.is_empty() and str(npc.get("occupation", "")) not in ["Sheriff", "Child"]):
		result.append("trade")
	if not npc.is_empty(): result.append("talk")
	if result.is_empty(): result.append("trade")
	return result

## The Talk tab: [{id, label, enabled, reason}], each id a context action on the person.
static func options(s: Dictionary, target: int) -> Array:
	var npc: Dictionary = person(s, target)
	if npc.is_empty(): return []
	# A sheriff with his gun on you: talking your way out comes first (talk.gd).
	var Talk = load("res://sim/player/talk.gd")
	var trouble: Array = Talk.trouble_options(s, npc)
	if not trouble.is_empty(): return trouble
	var result: Array = Talk.wanted_options(s, npc) + load("res://sim/player/requests.gd").talk_options(s, npc)
	result += [
		{"id": "ask_work", "label": "What do you do for a living?", "enabled": true, "reason": ""},
		{"id": "ask_family", "label": "How is your family keeping?", "enabled": true, "reason": ""},
		{"id": "ask_news", "label": "Heard any news?", "enabled": true, "reason": ""}]
	return result + Talk.tone_options(s, npc)

## How this person feels about the player, in a word and a colour name for the window.
static func feeling(s: Dictionary, npc: Dictionary) -> Array:
	if npc.is_empty() or not s.has("player"): return ["", "calm"]
	if int(npc.get("anger", 0)) >= 40: return ["Angry", "angry"]
	var value: int = Society.opinion(s, int(npc.id), int(s.player))
	if value <= -50: return ["Hostile", "angry"]
	if value <= -15 or int(npc.get("anger", 0)) >= 15: return ["Wary", "wary"]
	if value >= 50: return ["Warm", "friendly"]
	if value >= 15: return ["Friendly", "friendly"]
	return ["Calm", "calm"]

## "Respected in Reedbank" for the person's own town.
static func standing_line(s: Dictionary, npc: Dictionary) -> String:
	if npc.is_empty(): return ""
	var town: Dictionary = s.get("settlements", {}).get(str(npc.get("settlement", 0)), {})
	if town.is_empty(): return ""
	return "You are %s in %s" % [Reputation.label(Reputation.value(s, int(town.id))), town.name]
