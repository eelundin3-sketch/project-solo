extends RefCounted
const Furniture = preload("res://view/world/interior_art.gd")
const Props = preload("res://view/world/prop_art.gd")
const INK := Color("392b1e")
static func item(c: Node2D, p: Vector2, kind: String) -> void:
	match kind:
		"log": Props.log_piece(c, p + Vector2(-11, 0), p + Vector2(10, -2))
		"plank": Props.plank(c, p + Vector2(-13, 0), p + Vector2(13, -1))
		_: Props.supply(c, p, kind)

## The flue of an oven or forge: an iron pipe from the top of the stove up through the building's
## back wall, with a capped stack outside. While the stove is working, smoke rises from the stack,
## outside the wall, drifting and fading. `base` is where the pipe leaves the stove.
static func flue(c: Node2D, entity: Dictionary, base: Vector2, phase: float, active: bool, heaviness: float) -> void:
	var rect: Rect2i = load("res://sim/world/world_db.gd").building_rect(entity)
	var wall_outer: float = float(rect.position.y) * 24.0 - 12.0           # the outer face of the back wall
	var top: float = minf(base.y - 20.0, wall_outer - 18.0)                 # the stack stands clear of the wall
	var pipe := Color("3f3c36")
	var shine := Color("6f6c63")
	c.draw_line(base, Vector2(base.x, top), pipe, 6.0, true)
	c.draw_line(base + Vector2(-1.5, 0), Vector2(base.x - 1.5, top), shine, 1.2, true)
	# A collar where the pipe passes through the wall, and the stack's cap outside.
	c.draw_rect(Rect2(Vector2(base.x - 6, wall_outer - 4), Vector2(12, 5)), Color("2e2b27"))
	c.draw_rect(Rect2(Vector2(base.x - 7, top - 5), Vector2(14, 4)), pipe)
	c.draw_rect(Rect2(Vector2(base.x - 5, top - 9), Vector2(10, 4)), Color("2e2b27"))
	if not active: return
	# Smoke: puffs leave the stack, rise, swell, drift with the wind side and thin out.
	var puffs: int = 7
	for i in range(puffs):
		var age: float = fmod(phase * 0.035 + float(i) / float(puffs), 1.0)
		var rise: float = age * 70.0 * heaviness
		var drift: float = sin(age * 3.0 + float(i)) * 4.0 + age * 14.0
		var radius: float = 3.5 + age * 11.0 * heaviness
		var alpha: float = (1.0 - age) * 0.42 * heaviness
		var grey: float = 0.55 + age * 0.25
		c.draw_circle(Vector2(base.x + drift, top - 10.0 - rise), radius, Color(grey, grey, grey * 0.98, alpha))

## The three goods a workshop's storage rack labels, by trade.
static func stock_kinds(entity: Dictionary) -> Array:
	match entity.get("kind", ""):
		"bakery": return ["rye", "food", "plank"]
		"forge": return ["ore", "tool", "log"]
	return ["log", "plank", "food"]

static func slot(entity: Dictionary, kind: String) -> Vector2:
	var slot_index := 1 if entity.fixtures.size() > 1 else 0
	var data: Array = entity.fixtures[slot_index].rect
	if entity.fixtures[slot_index].kind == "stall":
		var index: int = maxi(0, entity.sale_items.find(kind))
		return Vector2(data[0], data[1]) * 24 + Vector2(3 + index * 26, 3)
	if entity.fixtures[slot_index].kind in ["oven", "forge"]:
		return Vector2(data[0], data[1]) * 24 - Vector2(12, 12) + (Vector2(70, 34) if kind in ["food", "tool"] else Vector2(14, 20))
	if entity.fixtures[slot_index].kind == "saw":
		return Vector2(data[0],data[1])*24-Vector2(12,12)+(Vector2(82,35) if kind=="plank" else Vector2(15,12))
	var index: int = maxi(0,stock_kinds(entity).find(kind))
	return Vector2(data[0],data[1])*24 + Vector2(3+index*30,15)
static func paint(c: Node2D, entity: Dictionary, stock: Dictionary, phase: float, active: bool, fixture_index: int = 0) -> void:
	var fixture: Dictionary = entity.fixtures[fixture_index]
	var data: Array = fixture.rect
	var p := Vector2(data[0],data[1])*24-Vector2(12,12)
	if fixture.kind == "saw":
		var has_rack: bool = entity.fixtures.size() > 1
		Furniture.workbench(c, p, phase, int(stock.get("log", 0)) if active or not has_rack else 0)
		if not has_rack:
			for i in range(mini(5, int(stock.get("plank", 0)))):
				item(c, p+Vector2(82, 35-i*4), "plank")
		if active:
			for i in range(4):
				var t: float = fmod(phase*0.15+i*0.23,1.0)
				c.draw_line(p+Vector2(58+t*18,20+t*15),p+Vector2(61+t*18,22+t*15),Color("dcb77a"),1.5)
	elif fixture.kind == "weapon_rack":
		Furniture.weapon_rack(c, p, int(stock.get("rifle", 0)) + int(stock.get("shotgun", 0)), int(stock.get("cartridge", 0)) + int(stock.get("shell", 0)))
	elif fixture.kind == "oven":
		Furniture.oven(c, p, phase, active, int(stock.get("rye", 0)), int(stock.get("food", 0)))
		flue(c, entity, p + Vector2(46, 4), phase, active, 0.8)
	elif fixture.kind == "forge":
		Furniture.forge(c, p, phase, active)
		flue(c, entity, p + Vector2(42, 8), phase, active, 1.0)
	elif fixture.kind == "stall":
		draw_stall(c, entity, p, stock)
	elif entity.kind == "construction":
		# A stack on timber bearers, drawn directly from the site's real inventory.
		var center := slot(entity, "plank")
		var quantity: int = stock.get("plank", 0)
		for side in [-1, 1]:
			var bearer := Rect2(center + Vector2(side * 15 - 2, 3), Vector2(5, 14))
			Furniture.slab(c, bearer, Color("725032"))
		var layers := mini(10, ceili(quantity / 3.0))
		for layer in range(layers):
			var width := 34.0 + (layer % 3) * 3.0
			var board := center + Vector2(0, 7 - layer * 2.8)
			Props.plank(c, board - Vector2(width * 0.5, 0), board + Vector2(width * 0.5, 0), 3.3,
				Color("b68e59") if layer % 2 == 0 else Color("c7a16d"))
		c.draw_string(ThemeDB.fallback_font, center + Vector2(-8, 28), str(quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e9d5a8"))
	else:
		Furniture.slab(c,Rect2(p,Vector2(96,48)),Color("775735"))
		for index in range(3):
			var kind: String = stock_kinds(entity)[index]
			var quantity: int = int(stock.get(kind,0))
			for i in range(mini(6,ceili(quantity/5.0))):
				item(c,slot(entity,kind)+Vector2(0,-i*4),kind)
			c.draw_string(ThemeDB.fallback_font,p+Vector2(3+index*31,44),str(quantity),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("f1dfac"))

static func draw_stall(c: Node2D, entity: Dictionary, p: Vector2, stock: Dictionary) -> void:
	var timber: bool = "plank" in entity.sale_items
	var cloth := Color("957358") if timber else Color("6e8677")
	if entity.has("keeper"):
		# Each keeper's tent has its own colour of canvas.
		cloth = [Color("9a5b47"), Color("5f7f9b"), Color("8f8a4e"), Color("7a5f8c"), Color("4f7d6b"), Color("a0773e")][posmod(int(entity.keeper), 6)]
	Furniture.timber(c, Rect2(p + Vector2(0, 3), Vector2(96, 18)), Color("a37a53"), 4)
	for x in [3, 91]:
		c.draw_line(p + Vector2(x, -27), p + Vector2(x, 25), INK, 3.3, true)
		c.draw_line(p + Vector2(x, -26), p + Vector2(x, 23), Color("b08a62"), 1.5, true)
	for kind in entity.sale_items:
		for i in range(mini(3, ceili(stock.get(kind, 0) / 4.0))):
			item(c, slot(entity, kind) + Vector2(0, i * 3 - 5), kind)
	var edge := PackedVector2Array([p + Vector2(-3, -29), p + Vector2(99, -29), p + Vector2(96, -10), p + Vector2(0, -10)])
	Props.polygon(c, edge, cloth)
	for stripe in range(6):
		var x := 2 + stripe * 16
		c.draw_rect(Rect2(p + Vector2(x, -28), Vector2(7, 17)), cloth.lightened(0.24))
	c.draw_line(p + Vector2(0, -11), p + Vector2(96, -11), cloth.darkened(0.25), 2)
	c.draw_string(ThemeDB.fallback_font, p + Vector2(10, 34), str(entity.get("label", "TIMBER" if timber else "PROVISIONS")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f0debb"))
