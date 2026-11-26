extends SceneTree
## Bounties, prisoners and a gang that grows back. A bandit who gives up can be tied and led to any
## sheriff's office: the bounty is paid from the town's purse and he's locked up; a dead one carried
## in pays half and is laid to rest; the town thinks better of you. While the camp stands newcomers
## join (up to five) and walk in past a town; a season after it's cleared a new gang camps elsewhere
## and the old camp goes cold. Money is conserved; save and load keep the hash.
const Sim = preload("res://sim/core/simulation.gd")
const Bandits = preload("res://sim/factions/bandits.gd")
const Bounties = preload("res://sim/law/bounties.gd")
const Conversation = preload("res://sim/player/conversation.gd")
const Law = preload("res://sim/law/law.gd")
const World = preload("res://sim/world/world_db.gd")
const Checks = preload("res://sim/diagnostics/invariants.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func beside(s: Dictionary, cell: Array) -> Array:
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1]]:
		var c: Array = [cell[0] + d[0], cell[1] + d[1]]
		if World.walkable(s, c): return c
	return cell

func _initialize() -> void:
	var sim := Sim.new(); sim.start_game(); var s: Dictionary = sim.state
	s.tick = 14400 + 11 * 600
	var bandit: Dictionary = s.residents[str(s.bandits.members[1])]
	bandit.surrendered = true
	var at: Array = s.entities[str(bandit.id)].cell
	s.entities[str(s.player)].cell = beside(s, at)
	check(Bounties.can_tie(s, bandit), "A bandit who gave up can be tied")
	check("tie_up" in load("res://sim/player/context_actions.gd").options(s, int(bandit.id)).map(func(o): return o.id), "...from his menu")
	Bounties.tie(sim, bandit)
	# Lead him off: he follows a step behind.
	var start: Array = s.entities[str(s.player)].cell
	var walked := 0
	for i in range(60):
		var next: Array = [s.entities[str(s.player)].cell[0] + 1, s.entities[str(s.player)].cell[1]]
		if i % 3 == 0 and World.walkable(s, next): s.entities[str(s.player)].cell = next; walked += 1
		sim.step()
	for i in range(20): sim.step()
	var me: Array = s.entities[str(s.player)].cell
	var him: Array = s.entities[str(bandit.id)].cell
	check(walked > 5 and maxi(absi(me[0] - him[0]), absi(me[1] - him[1])) <= 1, "He follows you on the rope (%d steps)" % walked)
	check(Bandits.captive(s) == false and Bounties.prisoners(s).size() == 1, "One prisoner in tow")
	var copy := Sim.new()
	copy.restore(sim.snapshot())
	check(copy.state_hash() == sim.state_hash(), "Save and load with a prisoner in tow keep the same hash")
	# At the sheriff's: the bounty, from the town's purse; he's locked up.
	var sheriff: Dictionary = Law.sheriffs(s, 1)[0]
	var office_at: Array = s.entities[str(sheriff.id)].cell
	s.entities[str(s.player)].cell = beside(s, office_at)
	s.entities[str(bandit.id)].cell = beside(s, s.entities[str(s.player)].cell)
	var treasury: String = str(s.settlements["1"].warehouse)
	var purse: int = int(s.accounts[treasury])
	var coins: int = int(s.accounts[str(s.player)])
	check("c_hand_in" in Conversation.options(s, sheriff).map(func(o): return o.id), "The sheriff takes him off your hands")
	Conversation.perform(sim, sheriff, "c_hand_in")
	var paid: int = int(s.accounts[str(s.player)]) - coins
	check(paid == mini(Bounties.ALIVE, purse) and int(s.accounts[treasury]) == purse - paid, "Paid the bounty from the town's purse (%d)" % paid)
	check(not bandit.get("jailed", {}).is_empty(), "...and he's locked up")
	load("res://sim/factions/reputation.gd").update(s)
	check(load("res://sim/factions/reputation.gd").value(s, 1) > 0, "The town thinks better of you")
	# A dead one carried in pays half.
	var dead: Dictionary = s.residents[str(s.bandits.members[2])]
	load("res://sim/combat/brawl.gd").kill(sim, dead, "shot")
	s.entities[str(dead.id)].cell = beside(s, s.entities[str(s.player)].cell)
	load("res://sim/player/carrying.gd").pick_up(s, int(dead.id))
	coins = int(s.accounts[str(s.player)])
	Conversation.perform(sim, sheriff, "c_hand_in")
	check(int(s.accounts[str(s.player)]) - coins == mini(Bounties.ALIVE * Bounties.DEAD_PERCENT / 100, int(s.accounts[treasury]) + int(s.accounts[str(s.player)]) - coins), "A dead one pays half")
	check(bool(dead.get("buried", false)), "...and is laid to rest")
	check(Checks.validate(s).is_empty(), "Invariants hold: %s" % str(Checks.validate(s)))

	# The gang grows back, up to five; newcomers walk in.
	var sim2 := Sim.new(); sim2.start_game(); var s2: Dictionary = sim2.state
	for i in range(4): Bandits._recruit(sim2)
	check(s2.bandits.members.size() == Bandits.MAX_MEMBERS, "Newcomers join, up to five (%d)" % s2.bandits.members.size())
	var newcomer: Dictionary = s2.residents[str(s2.bandits.members[3])]
	check(str(newcomer.get("errand", {}).get("kind", "")) == "joining", "A newcomer walks in to join")
	check(str(load("res://sim/entities/outfits.gd").worn(s2, int(newcomer.id)).get("mask", "")) != "", "...dressed like the rest")
	var arrived := false
	for i in range(14400):
		sim2.step()
		if newcomer.get("errand", {}).is_empty() or not newcomer.get("jailed", {}).is_empty(): arrived = true; break
	check(arrived, "He reaches the camp (or the law catches him on the way)")
	check(Checks.validate(s2).is_empty(), "Invariants hold after recruiting: %s" % str(Checks.validate(s2)))

	# Cleared: a season later a new gang camps elsewhere; the old camp goes cold.
	var sim3 := Sim.new(); sim3.start_game(); var s3: Dictionary = sim3.state
	var old_cell: Array = s3.bandits.cell.duplicate()
	var old_camp: int = int(s3.bandits.camp)
	for id in s3.bandits.members: s3.residents[str(id)].health = 0
	for i in range(4): sim3.step()
	check(bool(s3.bandits.cleared), "All down: the camp is cleared")
	s3.bandits.since = s3.tick - Bandits.NEW_GANG_AFTER
	for i in range(4): sim3.step()
	check(int(s3.bandits.camp) != old_camp and not bool(s3.bandits.cleared), "A season later a new gang has made camp")
	check(Vector2(s3.bandits.cell[0] - old_cell[0], s3.bandits.cell[1] - old_cell[1]).length() >= Bandits.OLD_CAMP_GAP, "...somewhere else")
	check(bool(s3.entities[str(old_camp)].get("abandoned", false)), "The old camp is left cold")
	check(Checks.validate(s3).is_empty(), "Invariants hold for the new gang: %s" % str(Checks.validate(s3)))
	print("Bandit bounty: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
