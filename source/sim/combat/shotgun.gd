extends RefCounted
## The player's long gun: ready/stow, round-by-round reloading, simulated shot and the surface
## each round strikes. The RIFLE is the main gun (you start with one, office racks hold them): one
## accurate, hard-hitting bullet that carries far and is heard far. The pump SHOTGUN (a spread of
## pellets, short range) still works if you have one. `state.shotgun` keeps its name for saves; its
## `kind` says which gun is in your hands. Tick-based and deterministic; the view only reads it.
const World = preload("res://sim/world/world_db.gd")
const Inventory = preload("res://sim/inventory/inventory_store.gd")
const Wounds = preload("res://sim/combat/wounds.gd")
const Spatial = preload("res://sim/world/spatial.gd")
const Cover = preload("res://sim/combat/cover.gd")
const CAPACITY := 5
const PELLETS := 7
const PELLET_DAMAGE := 9
const RANGE_CELLS := 9
const COOLDOWN_TICKS := 18
const RELOAD_TICKS_PER_SHELL := 12
const SPEED_CELLS_PER_TICK := 2
const EFFECT_TICKS := 14
const BLOOM_PER_SHOT := 220       # spread grows with every shot (thousandths) ...
const BLOOM_MAX := 900
const BLOOM_DECAY := 25           # ... and settles by this much each tick
const SPREAD := 0.17
const Brawl = preload("res://sim/combat/brawl.gd")

const HURT_ARM_SPREAD := 1.3   # a hurt arm widens the pattern by this much
## Each gun: shot per trigger pull, spread (radians), range (cells), ticks between shots, ticks per
## round loaded, rounds held, ammunition, how hard each projectile hits, its speed (cells per
## tick), how far the shot is heard (cells), and how much it throws the aim.
const WEAPONS := {
	"rifle": {"name": "Rifle", "pellets": 1, "spread": 0.025, "range": 26, "cooldown": 30, "reload": 20, "capacity": 5, "ammo": "cartridge", "strength": 2.6, "speed": 4, "heard": 60, "bloom": 260},
	"shotgun": {"name": "Shotgun", "pellets": PELLETS, "spread": SPREAD, "range": RANGE_CELLS, "cooldown": COOLDOWN_TICKS, "reload": RELOAD_TICKS_PER_SHELL, "capacity": CAPACITY, "ammo": "shell", "strength": 1.0, "speed": SPEED_CELLS_PER_TICK, "heard": 45, "bloom": BLOOM_PER_SHOT}}
const GUNS := ["rifle", "shotgun"]   # the order a gun is picked up when you ready one

## The gun in use: the one readied last if you still have it, else the first you carry.
static func kind(s: Dictionary) -> String:
	var current: String = str(s.get("shotgun", {}).get("kind", ""))
	if not current.is_empty() and Inventory.amount(s, s.player, current) > 0: return current
	for gun in GUNS:
		if Inventory.amount(s, s.player, gun) > 0: return gun
	return current if not current.is_empty() else "shotgun"

static func spec(s: Dictionary) -> Dictionary:
	return WEAPONS[kind(s)]

## How far a shot from the gun in use is heard.
static func heard_range(s: Dictionary) -> int:
	return int(spec(s).heard)
static func initialize(s: Dictionary) -> void:
	if not s.has("shotgun"):
		s.shotgun = {"kind": "", "equipped": false, "loaded": 0, "reloading": false, "reload_next": 0, "last_shot": -1000, "pellets": [], "effects": [], "kicks": 0, "bloom": 0, "last_dir": [0, 1000]}

static func owns(s: Dictionary) -> bool:
	for gun in GUNS:
		if Inventory.amount(s, s.player, gun) > 0: return true
	return false

## Raise or lower the weapon. Lowered, it hangs on the character's back.
static func toggle(s: Dictionary) -> String:
	if not owns(s): return "You have no gun. The sheriff's office racks keep rifles."
	var gun: String = kind(s)
	if str(s.shotgun.get("kind", gun)) != gun:
		# A different gun now: whatever was loaded goes back in your pocket as ammunition.
		var old: Dictionary = WEAPONS.get(str(s.shotgun.get("kind", "shotgun")), WEAPONS.shotgun)
		if int(s.shotgun.loaded) > 0: Inventory.produce(s, s.player, str(old.ammo), int(s.shotgun.loaded))
		s.shotgun.loaded = 0
	s.shotgun.kind = gun
	s.shotgun.equipped = not s.shotgun.equipped
	if not s.shotgun.equipped: s.shotgun.reloading = false
	var name: String = str(WEAPONS[gun].name)
	return "%s ready. R reloads, aim with the right mouse and click to fire." % name if s.shotgun.equipped else "%s slung on your back." % name

static func start_reload(s: Dictionary) -> String:
	var gun: Dictionary = s.shotgun
	var weapon: Dictionary = spec(s)
	if not gun.equipped: return "Ready your gun first (its hotbar key)."
	if gun.loaded >= int(weapon.capacity): return "The %s is full." % str(weapon.name).to_lower()
	if Inventory.amount(s, s.player, str(weapon.ammo)) < 1: return "You have no %ss." % str(weapon.ammo)
	gun.reloading = true
	gun.reload_next = s.tick + int(weapon.reload)
	return "Loading %ss." % str(weapon.ammo)

static func can_fire(s: Dictionary) -> bool:
	var gun: Dictionary = s.get("shotgun", {})
	return not gun.is_empty() and gun.equipped and gun.loaded > 0 and s.tick - int(gun.last_shot) >= int(spec(s).cooldown)

## Fires one blast. `direction` is a unit vector in thousandths (as the strike command uses).
static func fire(sim: RefCounted, direction: Array) -> bool:
	var s: Dictionary = sim.state
	if not can_fire(s) or direction.size() != 2: return false
	var gun: Dictionary = s.shotgun
	var weapon: Dictionary = spec(s)
	var origin: Array = load("res://sim/combat/cover.gd").eye_cell(s).duplicate()   # leaning out of cover, the shot leaves from the corner
	var base: float = Vector2(direction[0], direction[1]).angle()
	gun.loaded -= 1
	gun.reloading = false  # firing interrupts loading, as with a pump gun
	gun.last_shot = s.tick
	gun.kicks += 1
	gun.bloom = mini(BLOOM_MAX, int(gun.get("bloom", 0)) + int(weapon.bloom))
	gun.last_dir = [int(direction[0]), int(direction[1])]
	Brawl.event(s, "gunshot", origin, gun.last_dir)
	load("res://sim/combat/gunfire.gd").on_player_shot(sim, origin, int(weapon.heard))
	# A hurt (not yet useless) arm can't hold the gun steady: the pattern opens up.
	var Limbs = load("res://sim/combat/limbs.gd")
	var shaky: float = HURT_ARM_SPREAD if Limbs.state(s, int(s.player), "left_arm") == "hurt" or Limbs.state(s, int(s.player), "right_arm") == "hurt" else 1.0
	for index in range(int(weapon.pellets)):
		var spread: float = (float(sim.random_int("shotgun", -1000, 1000)) / 1000.0) * float(weapon.spread) * shaky * (1.0 + 1.5 * float(gun.get("bloom", 0)) / 1000.0)
		var angle: float = base + spread
		var reach: float = float(weapon.range) - float(sim.random_int("shotgun", 0, 200)) / 100.0
		gun.pellets.append({"x": float(origin[0]) + 0.5 * cos(base), "y": float(origin[1]) + 0.5 * sin(base), "dx": cos(angle), "dy": sin(angle), "left": reach, "owner": s.player,
			"strength": float(weapon.strength), "speed": int(weapon.speed)})
	_effect(s, "blast", origin, [roundi(cos(base) * 1000.0), roundi(sin(base) * 1000.0)])
	return true

static func _effect(s: Dictionary, kind: String, cell: Array, dir: Array = [0, 0]) -> void:
	s.shotgun.effects.append({"kind": kind, "cell": cell.duplicate(), "tick": s.tick, "dir": dir.duplicate()})
	if s.shotgun.effects.size() > 80: s.shotgun.effects.pop_front()

## What a pellet strikes at `cell`: "" means open air.
static func surface_at(s: Dictionary, cell: Array, owner: int) -> String:
	var key: String = "%d,%d" % [cell[0], cell[1]]
	# The first person or tree on the cell (lowest id), as a scan of the entity table would find.
	var first: int = -1
	var surface: String = ""
	for id in Spatial.actors_at(s, cell):
		if id != owner:
			first = id
			surface = "body"
			break
	for id in Cover._trees_by_cell(s).get(Vector2i(int(cell[0]), int(cell[1])), []):
		if id != owner and (first < 0 or id < first) and s.entities.get(str(id), {}).get("cell", []) == cell:
			first = id
			surface = "tree"
			break
	if surface != "": return surface
	if s.world.get("building_walls", {}).has(key): return "wall"
	var solid: String = "wood" if s.world.get("fixture_cells", {}).has(key) else ("stone" if s.world.blocked.has(key) else "")
	# A low thing (a bed, a chest, a counter, a small rock) only catches the shot when someone is
	# crouched right behind it; otherwise the pellets fly over.
	if solid != "" and Cover.height(s, cell) == Cover.LOW and not _crouched_beside(s, cell, owner): return ""
	return solid

static func _crouched_beside(s: Dictionary, cell: Array, owner: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			for id in Spatial.actors_at(s, [cell[0] + dx, cell[1] + dy]):
				if id == owner: continue
				if id == int(s.get("player", -1)):
					if Cover.player_low(s): return true
					continue
				var npc: Dictionary = s.get("residents", {}).get(str(id), {})
				if not npc.get("cover_cycle", {}).is_empty() or bool(npc.get("fear", {}).get("arrived", false)) or load("res://sim/combat/brawl.gd").knocked(s, npc): return true
	return false

static func update(sim: RefCounted) -> void:
	var s: Dictionary = sim.state
	if not s.has("shotgun"): return
	var gun: Dictionary = s.shotgun
	if int(gun.get("bloom", 0)) > 0: gun.bloom = maxi(0, int(gun.bloom) - BLOOM_DECAY)
	while not gun.effects.is_empty() and s.tick - int(gun.effects[0].tick) > EFFECT_TICKS: gun.effects.pop_front()
	if gun.reloading and s.tick >= gun.reload_next:
		var weapon: Dictionary = spec(s)
		if gun.loaded < int(weapon.capacity) and Inventory.consume(s, s.player, str(weapon.ammo), 1):
			gun.loaded += 1
			gun.reload_next = s.tick + int(weapon.reload)
		if gun.loaded >= int(weapon.capacity) or Inventory.amount(s, s.player, str(weapon.ammo)) < 1: gun.reloading = false
	var live: Array = []
	for pellet in gun.pellets:
		var alive := true
		for step in range(int(pellet.get("speed", SPEED_CELLS_PER_TICK))):
			if pellet.left <= 0.0: alive = false; break
			pellet.x += pellet.dx * 0.5
			pellet.y += pellet.dy * 0.5
			pellet.left -= 0.5
			var cell: Array = [roundi(pellet.x), roundi(pellet.y)]
			var bounds: Array = s.world.get("bounds", [0, 0, 128, 96])
			if cell[0] < bounds[0] or cell[1] < bounds[1] or cell[0] >= bounds[2] or cell[1] >= bounds[3]: alive = false; break
			var surface := surface_at(s, cell, pellet.owner)
			if surface != "":
				_strike(sim, surface, cell, pellet)
				alive = false
				break
		if alive and pellet.left <= 0.0:
			_effect(s, "ground", [roundi(pellet.x), roundi(pellet.y)], [roundi(pellet.dx * 1000.0), roundi(pellet.dy * 1000.0)])
			alive = false
		if alive: live.append(pellet)
	gun.pellets = live

static func _strike(sim: RefCounted, surface: String, cell: Array, pellet: Dictionary) -> void:
	var s: Dictionary = sim.state
	var dir: Array = [roundi(pellet.dx * 1000.0), roundi(pellet.dy * 1000.0)]
	_effect(s, {"body": "blood", "tree": "bark", "wall": "wall", "wood": "wood", "stone": "spark"}[surface], cell, dir)
	if surface != "body": return
	for id in Spatial.actors_at(s, cell):
		var entity: Dictionary = s.entities[str(id)]
		if true:
			var key := str(entity.id)
			var was_alive: bool = not s.residents.has(key) or s.residents[key].health > 0
			if s.residents.has(key) or entity.kind == "player":
				if pellet.owner == s.player and s.residents.has(key): load("res://sim/combat/gunfire.gd").on_player_hit(sim, s.residents[key])
				Wounds.shoot(sim, int(entity.id), cell, dir, float(pellet.get("strength", 1.0)))
			var fighters: Dictionary = s.get("local_combat", {}).get("fighters", {})
			if fighters.has(key):
				fighters[key].health = maxi(0, int(fighters[key].health) - roundi(PELLET_DAMAGE * float(pellet.get("strength", 1.0))))
				fighters[key].hit_tick = s.tick
			if s.residents.has(key) and was_alive and s.residents[key].health == 0:
				sim.record(entity.name + " was shot and is incapacitated.")
				if pellet.owner == s.player:   # remembered as a killing, by family and witnesses
					var town: int = int(s.residents[key].settlement)
					load("res://sim/law/law.gd").remember_crime(s, town, "murder", int(entity.id))
					var seen: Array = load("res://sim/world/chronicle.gd").witnesses(s, cell, [int(entity.id)])
					if town != 0 and not seen.is_empty():
						# Seen: it is filed as murder, and someone runs to the next town for help.
						load("res://sim/law/law.gd").file(s, town, "murder", load("res://sim/law/witness_reports.gd").description(s), false)
						load("res://sim/law/reinforcements.gd").on_killing(sim, town, cell, seen)
			break
