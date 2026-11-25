extends Node2D
const Terrain = preload("res://sim/world/terrain.gd")
const MapArt = preload("res://view/world/frontier_map_art.gd")
const CropArt = preload("res://view/world/crop_art.gd")
const MarketArt = preload("res://view/world/market_art.gd")
const Crops = preload("res://sim/farming/crops.gd")
const Planner = preload("res://sim/settlement/planner.gd")
const World = preload("res://sim/world/world_db.gd")
const Orient = preload("res://sim/world/orient.gd")
const FixtureArt = preload("res://view/world/fixture_art.gd")
const Fixtures = preload("res://view/world/fixture_director.gd")
const Director = preload("res://view/actors/animation_director.gd")
const DrawnCharacter = preload("res://view/actors/drawn_character.gd")
const RoadSurface = preload("res://view/world/road_surface.gd")
const LANDSCAPE = preload("res://view/world/landscape.gdshader")
const Probe = preload("res://sim/diagnostics/perf_probe.gd")
const NightLayer = preload("res://view/world/night_layer.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const WeatherLayer = preload("res://view/world/weather_layer.gd")
const Roofs = preload("res://view/world/roofs.gd")
const CELL: float = 24.0
## Characters are drawn at half size so they are in proportion to doors, furniture and trees.
const CHAR_SCALE: float = 0.625
## The static background is painted this far beyond the screen so small camera moves need no repaint.
const BACKGROUND_MARGIN: float = 260.0
var simulation: RefCounted
var selected_id: int = 0
var visible_entities: int = 0
var loaded_chunks: int = 0
var font: Font = ThemeDB.fallback_font
var motion := Director.new()
var fixture_motion := Fixtures.new()
var background: Node2D
var shadows: Node2D
var actor_shadows: Node2D
var speech_was_live: bool = true
var speech_style := StyleBoxFlat.new()   # one bubble style, recoloured per bubble (not a new one each frame)
var speech_layer: Node2D
var sun_overcast: float = 0.0
var roofs: Array[Rect2] = []
var shadow_list: Array = []
## Timber and floor tints per house style (see housing.gd), so every house type looks its own.
const HOUSE_TINTS := {
	"weathered": Color(0.8, 0.82, 0.86), "log": Color(0.76, 0.56, 0.42), "pine": Color(1.28, 1.16, 0.84),
	"adobe": Color(1.36, 1.0, 0.74), "whitewash": Color(1.55, 1.5, 1.4), "redwood": Color(1.16, 0.64, 0.52),
	"grey": Color(0.72, 0.75, 0.82), "stone": Color(1.0, 1.02, 1.1)}
static func house_tint(s: Dictionary, building_id: int) -> Color:
	var building: Dictionary = s.entities.get(str(building_id), {})
	return HOUSE_TINTS.get(str(building.get("house_style", "")), Color.WHITE)
var shadow_list_count: int = -1
var shadow_list_age: int = 0
var landscape: ColorRect
var landscape_region := Rect2()
var landscape_seed: int = -1
var roads := RoadSurface.new()
var road_buildings: int = -1
var refresh_age: float = 0.0
var last_camera: Vector2 = Vector2.INF
var last_zoom: Vector2 = Vector2.ZERO
var daylight: CanvasModulate
var night: Node2D            # darkness with lamp, window and lantern pools (night_layer.gd)
var weather_layer: Node2D    # rain, snow and fog over the people (weather_layer.gd)
var roofs_layer := Roofs.new()  # a roof on every building but the one you're in (roofs.gd)
var label_layer: Node2D        # town names, above the roofs
var building_rects: Array[Rect2i] = []
var building_rects_signature: Array = []
var atmosphere_time: float = 0.0
var character_models: Dictionary = {}
var depth_objects: Dictionary = {}
var depth_frame: int = 0

class Background extends Node2D:
	var projector: Node2D
	func _draw() -> void:
		var t := Time.get_ticks_usec()
		projector.draw_static(self)
		Probe.add("d:background", Time.get_ticks_usec() - t)

## Sun shadows for everything that stands up: drawn above the ground and buildings' floors,
## below trees and people.
class ShadowLayer extends Node2D:
	var projector: Node2D
	var people: bool = false   # false: trees, buildings and rocks (kept); true: people (every frame)
	func _draw() -> void:
		var t := Time.get_ticks_usec()
		if people: projector.draw_actor_shadows(self)
		else: projector.draw_static_shadows(self)
		Probe.add("d:shadows_people" if people else "d:shadows_static", Time.get_ticks_usec() - t)

## Speech bubbles over the speakers' heads, above every character.
class SpeechLayer extends Node2D:
	var projector: Node2D
	func _draw() -> void:
		var t := Time.get_ticks_usec()
		projector.draw_speech(self)
		Probe.add("d:speech", Time.get_ticks_usec() - t)

## Large, slow-changing ground art (the market plaza, one crop plot) is painted once into a
## texture and shown as a sprite. Thousands of small shapes cost real time to submit every
## frame even when cached, so the picture is only re-rendered when the thing it shows changes.
class Painter extends Node2D:
	var decor: Node2D
	func _draw() -> void:
		decor.projector.draw_decor(self, decor)

class Decor extends Node2D:
	const SUPERSAMPLE := 2.0
	var projector: Node2D
	var kind: String = ""
	var key: int = 0
	var area: Rect2 = Rect2()
	var viewport: SubViewport
	var painter: Painter
	var sprite: Sprite2D

	func _ready() -> void:
		viewport = SubViewport.new()
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		painter = Painter.new()
		painter.decor = self
		painter.scale = Vector2.ONE * SUPERSAMPLE
		viewport.add_child(painter)
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.scale = Vector2.ONE / SUPERSAMPLE
		sprite.texture = viewport.get_texture()
		add_child(sprite)
		_apply()

	func set_area(value: Rect2) -> void:
		area = value
		if viewport != null: _apply()

	func _apply() -> void:
		viewport.size = Vector2i(maxi(8, ceili(area.size.x * SUPERSAMPLE)), maxi(8, ceili(area.size.y * SUPERSAMPLE)))
		painter.position = -area.position * SUPERSAMPLE
		sprite.position = area.position
		repaint()

	func repaint() -> void:
		painter.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

class DepthObject extends Node2D:
	var projector: Node2D
	var object_kind: String = ""
	var entity_id: int = 0
	var fixture_index: int = 0
	var furniture_data: Dictionary = {}
	var construction_tile: Dictionary = {}
	var wall_neighbours: Dictionary = {}
	var door_data: Dictionary = {}
	var door_open: float = 0.0
	var paint_signature: int = -2   # what the last paint showed, for redraw-on-change
	func _draw() -> void:
		if projector.simulation == null: return
		var t := Time.get_ticks_usec()
		_paint()
		Probe.add("d:depth_objects", Time.get_ticks_usec() - t)
		Probe.count("depth_redraws")

	func _paint() -> void:
		var s: Dictionary = projector.simulation.state
		if object_kind == "wall":
			MapArt.cutaway_wall(self, wall_neighbours)
		elif object_kind == "door":
			MapArt.door(self, door_data, door_open)
		elif object_kind == "construction_tile":
			MapArt.build_piece(self, construction_tile.kind, construction_tile.progress, construction_tile.cell)
		elif object_kind == "tree":
			var entity: Dictionary = s.entities.get(str(entity_id), {})
			if not entity.is_empty():
				MapArt.tree(self, Vector2.ZERO, s.inventories[str(entity_id)].items.get("log", 0), entity_id, projector.motion.tree_pose(entity_id, position))
		elif object_kind == "fixture":
			var entity: Dictionary = s.entities.get(str(entity_id), {})
			if not entity.is_empty() and s.inventories.has(str(entity_id)):
				draw_set_transform(-position)
				FixtureArt.paint(self, entity, s.inventories[str(entity_id)].items, float(projector.fixture_motion.phases.get(str(entity_id), 0)), projector.fixture_motion.running.get(str(entity_id), false), fixture_index)
				draw_set_transform(Vector2.ZERO)
		elif object_kind == "furniture":
			draw_set_transform(-position)
			MapArt.draw_furnishing(self, furniture_data, -position)
			draw_set_transform(Vector2.ZERO)
		elif object_kind == "rock": MapArt.rock(self, Vector2.ZERO)
		elif object_kind == "caravan": MapArt.cart(self, Vector2.ZERO)
		elif object_kind == "stash":
			var stock: Dictionary = s.inventories.get(str(entity_id), {}).get("items", {})
			var offset: int = 0
			for item in stock:
				FixtureArt.item(self, Vector2(offset, 0), item)
				offset += 12

func _ready() -> void:
	y_sort_enabled = true
	landscape = ColorRect.new()
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landscape.z_index = -2
	var material := ShaderMaterial.new()
	material.shader = LANDSCAPE
	landscape.material = material
	add_child(landscape)
	daylight = CanvasModulate.new()
	add_child(daylight)
	background = Background.new()
	background.projector = self
	background.z_index = -1
	add_child(background)
	shadows = ShadowLayer.new()
	shadows.projector = self
	shadows.z_index = -1
	add_child(shadows)
	actor_shadows = ShadowLayer.new()
	actor_shadows.projector = self
	actor_shadows.people = true
	actor_shadows.z_index = -1
	add_child(actor_shadows)
	speech_layer = SpeechLayer.new()
	speech_layer.projector = self
	speech_layer.z_index = 20
	add_child(speech_layer)
	weather_layer = WeatherLayer.new()
	weather_layer.z_index = 14   # over the people, under the night
	add_child(weather_layer)
	label_layer = LabelLayer.new()
	label_layer.view = self
	label_layer.z_index = 16   # town names over the roofs and the night
	add_child(label_layer)
	night = NightLayer.new()
	night.projector = self
	night.z_index = 15   # over the world and the people, under the speech bubbles
	add_child(night)

func animate(delta: float, paused: bool, speed: int) -> void:
	if simulation == null:
		return
	var t := Time.get_ticks_usec()
	_sync_landscape()
	_sync_ground_weather()
	_sync_season()
	_sync_decor(delta)
	t = _lap("v:landscape+decor", t)
	motion.track_trees = not is_far()
	var tracked := view_bounds().grow(200)
	motion.view_cells = Rect2i(floori(tracked.position.x / CELL), floori(tracked.position.y / CELL), ceili(tracked.size.x / CELL) + 1, ceili(tracked.size.y / CELL) + 1)
	motion.update(simulation.state, delta, paused, speed)
	t = _lap("v:animation_director", t)
	var player_key := str(simulation.state.get("player", 0))
	var player_point: Vector2 = motion.actors.get(player_key, {}).get("position", Vector2.ZERO)
	roofs_layer.sync(self, simulation.state, player_point, is_far())
	if is_far() != decor_far:
		# Zoomed far out, a building is just its roof: its floor image is not drawn.
		decor_far = is_far()
		for decor_key in decor_nodes:
			if str(decor_key).begins_with("building:"): decor_nodes[decor_key].visible = not decor_far
	_sync_characters(0.0 if paused else minf(delta, 0.1) * speed)
	t = _lap("v:characters_sync", t)
	if not paused: atmosphere_time += minf(delta, 0.1) * speed
	fixture_motion.update(simulation.state,delta,paused,speed)
	_sync_depth_objects()
	t = _lap("v:depth_sync", t)
	_update_doors(minf(delta, 0.1))
	t = _lap("v:doors", t)
	# Lighting follows the authoritative 24-hour clock and freezes on pause.
	# The four parts of the day (DayClock): dawn from 04:00, full light 06:00-20:00 with the evening
	# turning golden, dusk 20:00-22:00, dark night 22:00-04:00.
	var day_fraction: float = float(simulation.state.tick % 14400) / 14400.0
	var light: float = DayClock.light_amount(day_fraction)
	var glow: float = DayClock.evening_glow(day_fraction)
	var weather: Dictionary = simulation.state.get("weather", {})
	var overcast: float = _weather_amount(weather, "rain") * 0.17 + _weather_amount(weather, "snow") * 0.10 + _weather_amount(weather, "fog") * 0.13
	# The night layer does the darkening (with light pools cut out); the tint only cools the colours.
	daylight.color = Color("c3cbe0").lerp(Color("fff1d5"), light).lerp(Color("ffd49a"), glow * 0.45 * (1.0 - overcast * 2.0)).darkened(overcast)
	sun_overcast = overcast
	weather_layer.simulation = simulation
	weather_layer.update(view_bounds(), is_far(), _weather_amount)
	night.simulation = simulation
	night.update(minf(delta, 0.1), view_bounds(), overcast, is_far())
	t = _lap("v:night", t)
	_update_shadow_layers()
	# Speech bubbles only while someone is talking (plus one redraw to clear the last one).
	var talking: bool = false
	for line in simulation.state.get("speech", []):
		if int(line.until) >= simulation.state.tick: talking = true; break
	if talking or speech_was_live: speech_layer.queue_redraw()
	speech_was_live = talking
	refresh_age += delta
	var camera := get_viewport().get_camera_2d()
	if camera != null and (camera.position.distance_to(last_camera) > BACKGROUND_MARGIN * 0.4 or camera.zoom != last_zoom or refresh_age > 1.0):
		background.queue_redraw()
		last_camera = camera.position
		last_zoom = camera.zoom
		refresh_age = 0
	queue_redraw()

func _lap(name: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	Probe.add(name, now - since)
	return now

func _sync_landscape() -> void:
	var state: Dictionary = simulation.state
	var limits: Array = state.world.get("bounds", [0, 0, 128, 96])
	var region := Rect2(
		Vector2(limits[0], limits[1]) * CELL,
		Vector2(limits[2] - limits[0], limits[3] - limits[1]) * CELL)
	var seed_value: int = int(state.seed) % 9973
	var completed: int = state.get("completed_buildings", 0)
	var finished_mask := roads.poll()
	if finished_mask != null: landscape.material.set_shader_parameter("road_mask", finished_mask)
	if landscape_region == region and landscape_seed == seed_value and road_buildings == completed: return
	if landscape_region == region and landscape_seed == seed_value and road_buildings >= 0:
		# A building was finished: its new path is drawn in the background (no frame freeze).
		road_buildings = completed
		roads.bake_async(state, region)
		return
	road_buildings = completed
	landscape_region = region
	landscape_seed = seed_value
	landscape.position = region.position
	landscape.size = region.size
	landscape.material.set_shader_parameter("world_origin", region.position)
	landscape.material.set_shader_parameter("terrain_seed", float(seed_value))
	var centres: Dictionary = Terrain.town_centres(state)
	landscape.material.set_shader_parameter("hollow_center", centres[1])
	landscape.material.set_shader_parameter("reedbank_center", centres[2])
	landscape.material.set_shader_parameter("dust_center", centres[3])
	landscape.material.set_shader_parameter("road_mask", roads.bake(state, region))

## The season shown, blended over the first day of each season: landscape colours, trees, grass.
var season_key: Array = []
func _sync_season() -> void:
	var tick: int = int(simulation.state.tick)
	var Weather = load("res://sim/world/weather.gd")
	var season: int = Weather.season_of(tick)
	var season_ticks: int = Weather.DAY * Weather.SEASON_DAYS
	var into: float = clampf(float(tick % season_ticks) / float(Weather.DAY), 0.0, 1.0)
	if tick < Weather.DAY: into = 1.0   # a new game opens in summer: nothing to blend from
	var key := [season, snappedf(into, 0.05)]
	if key == season_key: return
	season_key = key
	MapArt.season = season
	MapArt.previous_season = (season + 3) % 4
	MapArt.season_blend = into
	var weights := [0.0, 0.0, 0.0, 0.0]
	weights[(season + 3) % 4] += 1.0 - into
	weights[season] += into
	landscape.material.set_shader_parameter("season_weights", Vector4(weights[0], weights[1], weights[2], weights[3]))
	background.queue_redraw()
	for node in depth_objects.values():
		if node.object_kind == "tree": node.queue_redraw()

## Wet ground, snow and road mud per town, for the landscape shader (set only when they change).
var weather_uniforms: Array = []
func _sync_ground_weather() -> void:
	var s: Dictionary = simulation.state
	var regions: Dictionary = s.get("weather", {}).get("regions", {})
	var wet := Vector3.ZERO
	var snow := Vector3.ZERO
	var mud := Vector3.ZERO
	for i in range(3):
		var region: Dictionary = regions.get(str(i + 1), s.get("weather", {}) if regions.is_empty() else {})
		if region.is_empty(): continue
		var rain: float = _weather_amount(region, "rain")
		wet[i] = maxf(rain, float(region.get("mud", 0)) / 100.0 * 0.6)
		snow[i] = float(region.get("snow", 0)) / 100.0
		mud[i] = float(region.get("mud", 0)) / 100.0
	var signature := [snappedf(wet.x, 0.02), snappedf(wet.y, 0.02), snappedf(wet.z, 0.02), snappedf(snow.x, 0.02), snappedf(snow.y, 0.02), snappedf(snow.z, 0.02), snappedf(mud.x, 0.02), snappedf(mud.y, 0.02), snappedf(mud.z, 0.02)]
	if signature == weather_uniforms: return
	weather_uniforms = signature
	landscape.material.set_shader_parameter("town_wet", wet)
	landscape.material.set_shader_parameter("town_snow", snow)
	landscape.material.set_shader_parameter("town_mud", mud)

func snap_visuals() -> void:
	road_buildings = -1
	decor_signatures.clear()
	decor_clock = 99.0
	if simulation != null: _sync_decor(1.0)
	motion.reset()
	fixture_motion.reset()
	if simulation != null:
		_sync_landscape()
		motion.update(simulation.state, 0, true, 1)
		_sync_characters()
		fixture_motion.update(simulation.state,0,true,1)
		_sync_depth_objects()
	if background != null:
		background.queue_redraw()
	queue_redraw()

func _sync_characters(delta: float = -1.0) -> void:
	if simulation == null: return
	var bounds := view_bounds().grow(120)
	var keep: Dictionary = {}
	for key in motion.actors:
		var pose: Dictionary = motion.actors[key]
		if not bounds.has_point(pose.position): continue
		var entity: Dictionary = simulation.state.entities.get(key, {})
		if entity.is_empty(): continue
		keep[key] = true
		if not character_models.has(key):
			var character := DrawnCharacter.new()
			character.scale = Vector2.ONE * CHAR_SCALE
			add_child(character)
			character.setup(entity.id, entity.kind == "player", entity.kind == "raider")
			character_models[key] = character
		character_models[key].z_index = 2 if pose.get("action", "") == "rest" and int(pose.get("rest_rot", -1)) >= 0 else 0  # sleepers lie on top of the bed
		# Inside a building with its roof on (not the one you're in): not seen, and not drawn.
		character_models[key].visible = not roofs_layer.covered(simulation.state, key, pose.position)
		# On the map a figure is a few pixels tall: it still moves every frame, but its pose is
		# repainted on one frame in four (staggered), which is not visible at that size.
		var zoom: float = get_viewport().get_camera_2d().zoom.x if get_viewport().get_camera_2d() != null else 1.0
		var drawn: Dictionary = pose
		if float(pose.get("shoulder", 0.0)) != 0.0:   # carried over someone's shoulder (carrying.gd)
			drawn = pose.duplicate()
			drawn.position = pose.position + Vector2(0, float(pose.shoulder))
		if zoom < 0.6 and (depth_frame + entity.id) % 4 != 0 and character_models[key].position.distance_to(drawn.position) < 96.0:
			character_models[key].position = drawn.position
		else:
			character_models[key].set_pose(drawn, delta)
	for key in character_models.keys():
		if not keep.has(key):
			character_models[key].queue_free()
			character_models.erase(key)

func _depth_node(key: String, kind: String, pos: Vector2, entity_id: int = 0) -> DepthObject:
	var item: DepthObject = depth_objects.get(key)
	if item == null:
		item = DepthObject.new()
		item.projector = self
		item.object_kind = kind
		item.entity_id = entity_id
		add_child(item)
		depth_objects[key] = item
		item.position = pos
		item.queue_redraw()
	elif item.position != pos:
		item.position = pos
	return item

## Redraw only what can have changed since it was last painted. Walls, rocks, furniture and doors
## repaint when their data changes (the sync pass and _update_doors handle those).
func _schedule_redraws() -> void:
	var s: Dictionary = simulation.state
	for key in depth_objects:
		var item: DepthObject = depth_objects[key]
		match item.object_kind:
			"tree":
				var id: int = item.entity_id
				var tree: Dictionary = motion.trees.get(str(id), {})
				var logs: int = int(tree.get("logs", 1))
				var felled: bool = bool(tree.get("felled", false))
				var hit_age: float = motion.time - float(tree.get("hit", -10.0))
				var falling: bool = felled and float(tree.get("fall", -1.0)) >= 0.0 and motion.time - float(tree.fall) < 2.2
				var look: int = logs * 4 + (2 if felled else 0) + (1 if tree.get("dead", false) else 0)
				if falling or hit_age < 0.55:
					item.queue_redraw()   # toppling or shaking from an axe blow
				elif logs > 0 and not felled:
					if (depth_frame + id) % 3 == 0: item.queue_redraw()   # slow sway: a third per frame is invisible
				elif item.paint_signature != look:
					item.queue_redraw()   # a stump or a trunk on the ground only changes when its state does
				item.paint_signature = look
			"fixture":
				var running: bool = fixture_motion.running.get(str(item.entity_id), false)
				var stock: int = s.inventories.get(str(item.entity_id), {}).get("items", {}).hash()
				if running or item.paint_signature != stock: item.queue_redraw()
				item.paint_signature = stock if not running else -1
			"stash":
				var stock: int = s.inventories.get(str(item.entity_id), {}).get("items", {}).hash()
				if item.paint_signature != stock: item.queue_redraw()
				item.paint_signature = stock

const DEPTH_CHUNK: int = 16
var depth_index: Dictionary = {}           # "cx,cy" (16-cell chunks) -> Array of [key, kind, position, entity_id]
var depth_index_signature: Array = []
var wall_index: Dictionary = {}            # "cx,cy" -> Array of [key, x, y, owner]
var wall_index_signature: Array = []
var building_items: Array = []             # fixtures, furniture and doors: [key, kind, position, entity_id, data]
var building_items_signature: Array = []
var mover_ids: Array = []                  # stashes and caravans, whose cell is read live
var depth_pass_signature: Array = []

static func _depth_chunk(x: int, y: int) -> String:
	return "%d,%d" % [floori(float(x) / DEPTH_CHUNK), floori(float(y) / DEPTH_CHUNK)]

## Trees, rocks, stashes and caravans, bucketed by 16-cell chunk. Rebuilt only when entities are
## added or removed, rocks change, or a building appears (trees inside a building are not drawn).
func _rebuild_depth_index(s: Dictionary) -> void:
	var occupied_rooms: Array[Rect2i] = []
	for building in s.entities.values():
		if building.has("footprint"): occupied_rooms.append(World.building_rect(building))
	depth_index = {}
	mover_ids = []
	var big_rocks: Array = []
	for entity in s.entities.values():
		if entity.has("rock_rect"): big_rocks.append(entity.rock_rect)
		var kind: String = entity.get("kind", "")
		if kind == "tree":
			var cell := Vector2i(entity.cell[0], entity.cell[1])
			var inside: bool = false
			for room in occupied_rooms:
				if room.has_point(cell): inside = true; break
			if inside: continue
			var bucket := _depth_chunk(cell.x, cell.y)
			if not depth_index.has(bucket): depth_index[bucket] = []
			depth_index[bucket].append(["tree:%d" % entity.id, "tree", Vector2(cell) * CELL, int(entity.id)])
		elif kind in ["stash", "caravan"] and entity.has("cell"):
			mover_ids.append(int(entity.id))
	# The bandit camp's crates and woodpile are blocked cells (cover), drawn by the camp art.
	var camp_props: Dictionary = {}
	if s.has("bandits"):
		var Bandits = load("res://sim/factions/bandits.gd")
		for kind in ["crate", "woodpile"]:
			for offset in Bandits.PROPS[kind]:
				var at: Array = Bandits.at_camp(s.bandits.cell, offset)
				camp_props["%d,%d" % [at[0], at[1]]] = true
	for cell_key in s.world.blocked:
		var comma: int = cell_key.find(",")
		var x: int = int(cell_key.substr(0, comma))
		var y: int = int(cell_key.substr(comma + 1))
		var under_big_rock := false
		for rr in big_rocks:
			if x >= rr[0] and x < rr[0] + rr[2] and y >= rr[1] and y < rr[1] + rr[3]: under_big_rock = true; break
		if under_big_rock: continue  # drawn once as the large boulder
		if camp_props.has(cell_key): continue   # the bandit camp's crates and woodpile have their own art
		var bucket := _depth_chunk(x, y)
		if not depth_index.has(bucket): depth_index[bucket] = []
		depth_index[bucket].append(["rock:" + cell_key, "rock", Vector2(x, y) * CELL, 0])

func _rebuild_wall_index(s: Dictionary) -> void:
	wall_index = {}
	for cell_key in s.world.get("building_walls", {}):
		var comma: int = cell_key.find(",")
		var x: int = int(cell_key.substr(0, comma))
		var y: int = int(cell_key.substr(comma + 1))
		var bucket := _depth_chunk(x, y)
		if not wall_index.has(bucket): wall_index[bucket] = []
		wall_index[bucket].append(["wall:" + cell_key, x, y, int(s.world.building_walls[cell_key])])

## Fixtures, furniture and doors of every building. A few dozen buildings, rebuilt when the
## buildings or their fittings change (fittings always bump the navigation revision).
func _rebuild_building_items(s: Dictionary) -> void:
	building_items = []
	for entity in s.entities.values():
		if not entity.get("fixtures", []).is_empty() and s.inventories.has(str(entity.id)):
			for index in range(entity.fixtures.size()):
				var rect: Array = entity.fixtures[index].rect
				var p := Vector2(rect[0] + rect[2] / 2.0, rect[1] + rect[3]) * CELL - Vector2(0, 12)
				var key := "fixture:%d" % entity.id if index == 0 else "fixture:%d:%d" % [entity.id, index]
				building_items.append([key, "fixture", p, int(entity.id), index])
		if not entity.has("footprint"): continue
		var items := MapArt.furnishings(entity)
		for index in range(items.size()):
			var entry: Dictionary = items[index]
			building_items.append(["furniture:%d:%d" % [entity.id, index], "furniture", entry.point + Vector2(0, entry.bottom), int(entity.id), entry])
		if not entity.has("door"): continue
		# Doors: one in every outside doorway and one in every passage between rooms.
		var doors: Array = []
		var out := Vector2(Orient.outward(int(entity.get("door_side", 2))))
		doors.append({"suffix": "out", "cells": [entity.door], "axis": "h" if absf(out.y) > 0.5 else "v", "inward": -out, "style": "heavy" if entity.kind in ["office", "warehouse", "market", "sawmill", "bakery", "forge", "saloon", "town_hall"] else "plank", "double": false})
		var gap_index := 0
		# The office's inner gap is the jail cell: its iron door is drawn with the building
		# (open or shut with cell_open), so it gets no wooden door that swings for passers-by.
		var inner_gaps: Array = [] if entity.kind == "office" else World.interior_doorways(entity)
		for gap in inner_gaps:
			var inward_dir: Vector2 = Vector2(1, 0) if gap.axis == "v" else Vector2(0, -1)
			doors.append({"suffix": "in%d" % gap_index, "cells": gap.cells, "axis": gap.axis, "inward": inward_dir, "style": "plank", "double": gap.cells.size() >= 3})
			gap_index += 1
		for entry in doors:
			var cells: Array = entry.cells
			var first: Array = cells[0]
			var last: Array = cells[cells.size() - 1]
			var pos := Vector2(first[0] * CELL, first[1] * CELL + CELL / 2)
			var local_first := Vector2(0, -CELL / 2)
			var local_last: Vector2 = Vector2((last[0] - first[0]) * CELL, (last[1] - first[1]) * CELL) + local_first
			var a: Vector2 = local_first - (Vector2(CELL / 2, 0) if entry.axis == "h" else Vector2(0, CELL / 2))
			var b: Vector2 = local_last + (Vector2(CELL / 2, 0) if entry.axis == "h" else Vector2(0, CELL / 2))
			building_items.append(["door:%d:%s" % [entity.id, entry.suffix], "door", pos, int(entity.id), {"a": a, "b": b, "inward": entry.inward, "style": entry.style, "double": entry.double}])

func _sync_depth_objects() -> void:
	if simulation == null: return
	depth_frame += 1
	if is_far():
		# Map view: nothing is individually depth-sorted, so drop the nodes until zoomed back in.
		for key in depth_objects.keys():
			depth_objects[key].queue_free()
			depth_objects.erase(key)
		depth_pass_signature = []
		return
	var s: Dictionary = simulation.state
	var walls: Dictionary = s.world.get("building_walls", {})
	var index_signature := [s.entities.size(), s.world.blocked.size(), s.get("completed_buildings", 0)]
	if index_signature != depth_index_signature:
		_rebuild_depth_index(s)
		depth_index_signature = index_signature
	var wall_signature := [walls.size()]
	if wall_signature != wall_index_signature or not is_same(walls, wall_index.get("__table", walls)):
		_rebuild_wall_index(s)
		wall_index["__table"] = walls
		wall_index_signature = wall_signature
	var items_signature := [s.entities.size(), s.get("completed_buildings", 0), s.world.get("nav_revision", 0)]
	if items_signature != building_items_signature:
		_rebuild_building_items(s)
		building_items_signature = items_signature
	var bounds := view_bounds().grow(130)
	# The keep/create pass runs when the view moves by a cell, on a new tick, or when an index
	# changed; in between, only the animated objects need their redraws scheduled.
	var pass_signature := [floori(bounds.position.x / CELL), floori(bounds.position.y / CELL), floori(bounds.size.x / CELL), floori(bounds.size.y / CELL), s.tick, depth_index_signature, wall_index_signature, building_items_signature]
	if pass_signature == depth_pass_signature:
		_schedule_redraws()
		return
	depth_pass_signature = pass_signature
	var keep: Dictionary = {}
	var low := Vector2i(floori(bounds.position.x / CELL / DEPTH_CHUNK), floori(bounds.position.y / CELL / DEPTH_CHUNK))
	var high := Vector2i(floori(bounds.end.x / CELL / DEPTH_CHUNK), floori((bounds.end.y + CELL) / CELL / DEPTH_CHUNK))
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			var bucket := "%d,%d" % [cx, cy]
			for entry in wall_index.get(bucket, []):
				var x: int = entry[1]
				var y: int = entry[2]
				var p := Vector2(x * CELL, y * CELL + CELL / 2)
				if not bounds.has_point(p): continue
				keep[entry[0]] = true
				var fresh: bool = not depth_objects.has(entry[0])
				var wall: DepthObject = _depth_node(entry[0], "wall", p)
				if fresh or wall.paint_signature != wall_index_signature[0]:
					var owner: int = entry[3]
					var neighbours := {
						"north": walls.get("%d,%d" % [x, y - 1], 0) == owner,
						"south": walls.get("%d,%d" % [x, y + 1], 0) == owner,
						"west": walls.get("%d,%d" % [x - 1, y], 0) == owner,
						"east": walls.get("%d,%d" % [x + 1, y], 0) == owner,
						"northwest": walls.get("%d,%d" % [x - 1, y - 1], 0) == owner,
						"northeast": walls.get("%d,%d" % [x + 1, y - 1], 0) == owner,
						"southwest": walls.get("%d,%d" % [x - 1, y + 1], 0) == owner,
						"southeast": walls.get("%d,%d" % [x + 1, y + 1], 0) == owner,
					}
					wall.modulate = house_tint(s, owner)
					wall.paint_signature = wall_index_signature[0]
					if wall.wall_neighbours != neighbours:
						wall.wall_neighbours = neighbours
						wall.queue_redraw()
			for entry in depth_index.get(bucket, []):
				if not bounds.has_point(entry[2]): continue
				keep[entry[0]] = true
				_depth_node(entry[0], entry[1], entry[2], entry[3])
	for site in s.get("construction", {}).values():
		if site.done or site.get("build_phase", "") != "build": continue
		var piece := Planner.current_tile(site)
		if piece.is_empty() or piece.progress <= 0.0: continue
		var p := Vector2(piece.cell[0], piece.cell[1]) * CELL + Vector2(0, CELL / 2)
		if not bounds.has_point(p): continue
		var key := "construction_tile:%d" % site.id
		keep[key] = true
		var node: DepthObject = _depth_node(key, "construction_tile", p, site.id)
		if node.construction_tile != piece:
			node.construction_tile = piece
			node.queue_redraw()
	for id in mover_ids:
		var entity: Dictionary = s.entities.get(str(id), {})
		if entity.is_empty() or not entity.has("cell"): continue
		var p := Vector2(entity.cell[0], entity.cell[1]) * CELL
		if not bounds.has_point(p): continue
		var key := "%s:%d" % [entity.kind, entity.id]
		keep[key] = true
		_depth_node(key, entity.kind, p, entity.id)
	for entry in building_items:
		if not bounds.has_point(entry[2]): continue
		keep[entry[0]] = true
		var node: DepthObject = _depth_node(entry[0], entry[1], entry[2], entry[3])
		match entry[1]:
			"fixture": node.fixture_index = entry[4]
			"furniture":
				if node.furniture_data != entry[4]:
					node.furniture_data = entry[4]
					node.queue_redraw()
			"door":
				if node.door_data.is_empty(): node.queue_redraw()
				node.door_data = entry[4]
	for key in depth_objects.keys():
		if not keep.has(key):
			depth_objects[key].queue_free()
			depth_objects.erase(key)
	_schedule_redraws()

## Every frame: a door swings open when anyone is near it and shuts about a second after they leave.
## Only art: the doorway stays walkable whatever the door is doing.
func _update_doors(delta: float) -> void:
	var near_sq: float = pow(CELL * 1.7, 2.0)
	var opened_now: Array = []
	for key in depth_objects.keys():
		var node: DepthObject = depth_objects[key]
		if node.object_kind != "door" or node.door_data.is_empty(): continue
		var centre: Vector2 = node.position + (node.door_data.a + node.door_data.b) * 0.5
		var someone: bool = false
		for pose in motion.actors.values():
			if (pose.position - centre).length_squared() < near_sq: someone = true; break
		var hold: float = float(door_hold.get(key, 0.0))
		hold = 1.0 if someone else maxf(0.0, hold - delta)
		door_hold[key] = hold
		var target: float = 1.0 if hold > 0.0 else 0.0
		var before: float = node.door_open
		node.door_open = move_toward(before, target, delta / 0.25)
		if before < 0.04 and node.door_open >= 0.04: opened_now.append(centre)
		if absf(node.door_open - before) > 0.001: node.queue_redraw()
	for centre in opened_now:
		motion.cues.append({"kind": "door", "position": centre})

func view_bounds() -> Rect2:
	var camera := get_viewport().get_camera_2d()
	var center: Vector2 = camera.global_position if camera else Vector2(64, 46) * CELL
	var half := get_viewport_rect().size / (camera.zoom if camera else Vector2.ONE) / 2 + Vector2(60, 60)
	return Rect2(center - half, half * 2)


func draw_static(canvas: Node2D) -> void:
	if simulation == null:
		return
	var s: Dictionary = simulation.state
	var camera := get_viewport().get_camera_2d()
	var center: Vector2 = camera.global_position if camera else Vector2(64, 46) * CELL
	var half := get_viewport_rect().size / (camera.zoom if camera else Vector2.ONE) / 2.0 + Vector2(BACKGROUND_MARGIN, BACKGROUND_MARGIN)
	var bounds := Rect2(center - half, half * 2)
	var world_bounds: Array = s.world.get("bounds", [0, 0, 128, 96])
	var left: int = maxi(world_bounds[0], floori(bounds.position.x / CELL))
	var top: int = maxi(world_bounds[1], floori(bounds.position.y / CELL))
	var right: int = mini(world_bounds[2], ceili(bounds.end.x / CELL))
	var bottom: int = mini(world_bounds[3], ceili(bounds.end.y / CELL))
	loaded_chunks = (right / 64 - left / 64 + 1) * (bottom / 64 - top / 64 + 1)
	for settlement in s.get("settlements", {}).values():
		var store: Dictionary = s.entities[str(settlement.warehouse)]
		MapArt.square(canvas, Vector2(store.cell[0], store.cell[1] + 3) * CELL)
	var garden_exclusions: Array = []
	for settlement in s.get("settlements", {}).values():
		var square_store: Dictionary = s.entities[str(settlement.warehouse)]
		garden_exclusions.append(Rect2(Vector2(square_store.cell[0], square_store.cell[1] + 7) * CELL + Vector2(-300, -78), Vector2(600, 270)))
	for building in s.entities.values():
		if building.has("footprint"):
			var r := World.building_rect(building)
			garden_exclusions.append(Rect2(Vector2(r.position)*CELL,Vector2(r.size)*CELL))
	for plot in s.get("crops", {}).values():
		garden_exclusions.append(plot_area(plot).grow(10))
	if is_far():
		# Map view: canopies as dots instead of thousands of grass tufts and tree nodes.
		for tree in s.entities.values():
			if tree.get("kind", "") == "tree" and bounds.has_point(Vector2(tree.cell[0], tree.cell[1]) * CELL) and s.inventories[str(tree.id)].items.get("log", 0) > 0:
				canvas.draw_circle(Vector2(tree.cell[0], tree.cell[1]) * CELL + Vector2(0, -14), 15.0, Color("0d3322"))
				canvas.draw_circle(Vector2(tree.cell[0], tree.cell[1]) * CELL + Vector2(-2, -17), 11.0, Color("2a6a45"))
	else:
		MapArt.vegetation(canvas, bounds, garden_exclusions, atmosphere_time, motion.wind_strength, roads.coverage, Terrain.town_centres(s)[3] - Vector2(0, 2))
	var weather: Dictionary = s.get("weather", {})
	var snow: float = float(weather.get("snow", 0)) / 100.0
	if snow > 0.0:   # the ground itself turns white in the landscape shader; this pales the grass tufts
		canvas.draw_rect(bounds, Color(0.83, 0.89, 0.88, snow * 0.35))
	for entity in s.entities.values():
		if not entity.has("cell") or entity.kind in ["resident", "player", "raider", "tree", "caravan", "stash"]:
			continue
		var point := Vector2(entity.cell[0], entity.cell[1]) * CELL
		if bounds.grow(200).has_point(point):
			_draw_entity(s, entity, point, canvas)

func _draw() -> void:
	var t := Time.get_ticks_usec()
	_draw_world()
	Probe.add("d:world", Time.get_ticks_usec() - t)

func _draw_world() -> void:
	if simulation == null:
		return
	if motion.previous_tick < 0:
		motion.update(simulation.state, 0, true, 1)
		fixture_motion.update(simulation.state,0,true,1)
	var s: Dictionary = simulation.state
	var bounds := view_bounds().grow(90)
	if building_rects_signature != [s.entities.size(), s.get("completed_buildings", 0)]:
		building_rects_signature = [s.entities.size(), s.get("completed_buildings", 0)]
		building_rects.clear()
		for building in s.entities.values():
			if building.has("footprint"):
				building_rects.append(World.building_rect(building))
	var visible: Array = []
	for key in Director._actor_keys(s):
		var entity: Dictionary = s.entities.get(key, {})
		if entity.is_empty() or not entity.has("cell") or entity.kind not in ["resident", "player", "raider"]:
			continue
		var point := Vector2(entity.cell[0], entity.cell[1]) * CELL
		if motion.actors.has(str(entity.id)):
			point = motion.actors[str(entity.id)].position
		if bounds.has_point(point) and not roofs_layer.covered(s, str(entity.id), point):   # not inside a roofed building
			visible.append({"entity": entity, "point": point})
	visible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.point.y < b.point.y or (a.point.y == b.point.y and a.entity.id < b.entity.id))
	visible_entities = visible.size()
	var t := Time.get_ticks_usec()
	for entry in visible:
		_draw_entity(s, entry.entity, entry.point)
	t = _lap("dw:entities", t)
	fixture_motion.draw_transfers(self)
	t = _lap("dw:transfers", t)
	_draw_combat(s)
	_draw_shotgun(s)
	_draw_brawl(s)
	t = _lap("dw:combat+blood", t)
	# Campfires burn and flicker every frame (the stone ring and logs are in the background).
	if not is_far():
		for camp in World.of_kind(s, "bandit_camp"):
			var fire_at := Vector2(camp.cell[0], camp.cell[1]) * CELL
			if bounds.has_point(fire_at): MapArt.campfire_flames(self, fire_at, atmosphere_time)
	_draw_travel_goal(s)
	label_layer.queue_redraw()
	_lap("dw:labels+weather", t)

## Blood left on the ground by fights (pools and flung drops that darken as they dry), a short
## spray at the moment a blow lands, and the "z z" over someone who is out cold.
func _draw_brawl(s: Dictionary) -> void:
	var brawl: Dictionary = s.get("brawl", {})
	if brawl.is_empty(): return
	for decal in brawl.blood:
		var age: float = float(s.tick - int(decal.tick))
		var dried: float = clampf(age / 9000.0, 0.0, 1.0)
		var fade: float = 1.0 - clampf((age - 18000.0) / 18000.0, 0.0, 1.0) * 0.7
		var color := Color("a3160f").lerp(Color("46100c"), dried)
		color.a = 0.82 * fade
		var base := Vector2(decal.cell[0], decal.cell[1]) * CELL + Vector2(0, 5)
		var seed_value: int = int(decal.seed)
		var direction := Vector2(decal.dir[0], decal.dir[1]).normalized() if (decal.dir[0] != 0 or decal.dir[1] != 0) else Vector2.RIGHT
		for blob in range(2 + int(decal.size) * 2):
			var centre := base + Vector2((CropArt.rand01(seed_value, blob) - 0.5) * 12.0, (CropArt.rand01(blob, seed_value) - 0.5) * 5.0) + direction * 3.0 * blob * 0.5
			var rx: float = 2.2 + CropArt.rand01(seed_value + 3, blob) * 3.2 * (0.7 + 0.4 * float(decal.size))
			var points := PackedVector2Array()
			for step in range(10):
				var angle: float = TAU * float(step) / 10.0
				var wobble: float = 0.8 + 0.4 * CropArt.rand01(seed_value + step, blob)
				points.append(centre + Vector2(cos(angle) * rx * wobble, sin(angle) * rx * 0.55 * wobble))
			# A wobble that twists the blob is drawn as a plain oval (filling it errors every frame).
			if MapArt.Props.fillable(points): draw_colored_polygon(points, color)
			else:
				draw_set_transform(centre, 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, rx, color)
				draw_set_transform(Vector2.ZERO)
		for drop in range(3 + int(decal.size)):
			var distance: float = 7.0 + CropArt.rand01(seed_value + 9, drop) * 12.0
			var sideways: float = (CropArt.rand01(drop, seed_value + 5) - 0.5) * 8.0
			draw_circle(base + direction * distance + direction.orthogonal() * sideways * 0.5, 0.9 + CropArt.rand01(drop, seed_value) * 1.1, color)
	for fight_event in brawl.events:
		if fight_event.kind != "punch_hit": continue
		var age: float = clampf(float(s.tick - int(fight_event.tick)) / 8.0, 0.0, 1.0)
		if age >= 1.0: continue
		var at := Vector2(fight_event.cell[0], fight_event.cell[1]) * CELL + Vector2(0, -18)
		var push := Vector2(fight_event.dir[0], fight_event.dir[1]).normalized() if (fight_event.dir[0] != 0 or fight_event.dir[1] != 0) else Vector2.RIGHT
		for fleck in range(5):
			var angle: float = push.angle() + (CropArt.rand01(int(fight_event.tick), fleck) - 0.5) * 1.6
			draw_circle(at + Vector2.from_angle(angle) * (4.0 + 12.0 * age) + Vector2(0, 8.0 * age * age), 1.5 * (1.0 - age * 0.5), Color(0.6, 0.08, 0.07, 1.0 - age))
	for npc_key in s.get("residents", {}):
		var npc: Dictionary = s.residents[npc_key]
		var entity: Dictionary = s.entities.get(npc_key, {})
		if entity.is_empty(): continue
		var knock: Dictionary = npc.get("knock", {})
		if not knock.is_empty() and knock.kind == "ko" and s.tick >= int(knock.start) + 6 and s.tick < int(knock.down_until):
			var head := Vector2(entity.cell[0], entity.cell[1]) * CELL + Vector2(float(knock.get("side", 1)) * 22.0, -20.0 + sin(float(s.tick) * 0.15) * 2.0)
			draw_string(font, head, "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.95, 0.8, 0.85))

## A pulsing ring on the square the player is walking to after a double right-click.
func _draw_travel_goal(s: Dictionary) -> void:
	var path: Array = s.get("player_path", [])
	var goal: Array = s.get("player_travel_goal", [])
	if path.is_empty() or goal.size() != 2: return
	var at := Vector2(goal[0], goal[1]) * CELL + Vector2(0, 6)
	var pulse: float = 0.5 + 0.5 * sin(atime_for_marker() * 6.0)
	draw_arc(at, 9.0 + 3.0 * pulse, 0.0, TAU, 24, Color(1.0, 0.86, 0.4, 0.9), 2.0, true)
	draw_circle(at, 2.2, Color(1.0, 0.86, 0.4, 0.9))

func atime_for_marker() -> float:
	return atmosphere_time

## Town names sit on a layer of their own so the roofs never cover them.
class LabelLayer extends Node2D:
	var view: Node2D
	func _draw() -> void:
		if view.simulation != null: view._draw_map_labels(self, view.simulation.state)

## On the map view: settlement names and a marker on the player, sized for the screen not the world.
func _draw_map_labels(c: CanvasItem, s: Dictionary) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or camera.zoom.x >= 0.6: return
	var inverse: float = 1.0 / camera.zoom.x
	for town in s.get("settlements", {}).values():
		if overlay_labels: break   # the map overlay draws the town names itself, clear of the hotbar
		var store: Array = s.entities[str(town.warehouse)].cell
		var at := Vector2(store[0], store[1] - 16) * CELL
		var size: Vector2 = font.get_string_size(town.name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * inverse))
		c.draw_rect(Rect2(at + Vector2(-size.x / 2.0 - 8 * inverse, -size.y), size + Vector2(16 * inverse, 6 * inverse)), Color(0.07, 0.06, 0.04, 0.6))
		c.draw_string(font, at + Vector2(-size.x / 2.0, -4 * inverse), town.name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * inverse), Color("f7e3ac"))

func _draw_combat(s: Dictionary) -> void:
	var combat: Dictionary = s.get("local_combat", {})
	for shot in combat.get("projectiles", []):
		var cell: Array = shot.cells[shot.index]
		var p := Vector2(cell[0], cell[1]) * CELL + Vector2(0, -21)
		draw_line(p - Vector2(5, 0), p + Vector2(3, 0), Color("ffe6a2"), 2)
	for effect in combat.get("effects", []):
		var age: int = s.tick - effect.tick
		var p := Vector2(effect.cell[0], effect.cell[1]) * CELL + Vector2(0, -21)
		var color := Color("ffc968") if effect.kind == "muzzle" else Color("ef8b6c")
		color.a = clampf(1.0 - float(age) / 12.0, 0, 1)
		for i in range(4):
			var direction := Vector2.from_angle(float(i) * TAU / 4.0 + 0.3)
			draw_line(p + direction * 4, p + direction * (8 + age), color, 2)

## Shotgun pellets in flight and the effect each surface produces when struck.
func _draw_shotgun(s: Dictionary) -> void:
	var gun: Dictionary = s.get("shotgun", {})
	if gun.is_empty(): return
	for pellet in gun.pellets:
		var p := Vector2(pellet.x, pellet.y) * CELL + Vector2(0, -20)
		var d := Vector2(pellet.dx, pellet.dy)
		draw_line(p - d * 10.0, p, Color(1.0, 0.92, 0.6, 0.9), 1.4)
	for effect in gun.effects:
		if effect.kind == "blast": continue
		var age: float = clampf(float(s.tick - effect.tick) / 14.0, 0.0, 1.0)
		var base := Vector2(effect.cell[0], effect.cell[1]) * CELL + Vector2(0, -11)
		var dir := Vector2(effect.dir[0], effect.dir[1]) / 1000.0
		var seed_value: int = int(effect.tick) * 7 + int(effect.cell[0]) * 31 + int(effect.cell[1])
		match effect.kind:
			"blood":  # a few small dark-red flecks thrown forward, kept deliberately small and non-graphic
				for i in range(6):
					var angle: float = dir.angle() + (CropArt.rand01(seed_value, i) - 0.5) * 1.5
					var pos: Vector2 = base + Vector2.from_angle(angle) * (5.0 + 16.0 * age * (0.5 + CropArt.rand01(i, seed_value))) + Vector2(0, 26.0 * age * age)
					draw_circle(pos, 1.7 * (1.0 - age * 0.5), Color(0.62, 0.1, 0.09, 1.0 - age))
			"ground":  # dust puff and flung grit
				draw_circle(base + Vector2(0, 8), 5.0 + 10.0 * age, Color(0.72, 0.6, 0.42, 0.45 * (1.0 - age)))
				draw_circle(base + Vector2(-5, 4), 3.0 + 7.0 * age, Color(0.66, 0.55, 0.4, 0.35 * (1.0 - age)))
				for i in range(5):
					var pos: Vector2 = base + Vector2(0, 8) + Vector2((CropArt.rand01(seed_value, i) - 0.5) * 30.0 * age, -14.0 * age * (1.0 - age) * 2.0 * CropArt.rand01(i, 3))
					draw_rect(Rect2(pos, Vector2(1.6, 1.6)), Color(0.5, 0.4, 0.28, 1.0 - age))
			"wall":  # pale plaster-and-timber chips with a dust puff
				draw_circle(base, 4.0 + 8.0 * age, Color(0.82, 0.78, 0.68, 0.4 * (1.0 - age)))
				for i in range(7):
					var angle: float = (-dir).angle() + (CropArt.rand01(seed_value, i) - 0.5) * 2.2
					var pos: Vector2 = base + Vector2.from_angle(angle) * (4.0 + 15.0 * age) + Vector2(0, 18.0 * age * age)
					draw_rect(Rect2(pos, Vector2(2.2, 1.6)), Color(0.86, 0.78, 0.6, 1.0 - age))
			"wood":  # long light splinters
				for i in range(6):
					var angle: float = (-dir).angle() + (CropArt.rand01(seed_value, i) - 0.5) * 2.0
					var a: Vector2 = base + Vector2.from_angle(angle) * (3.0 + 13.0 * age)
					draw_line(a, a + Vector2.from_angle(angle + 0.4) * 4.5, Color(0.8, 0.64, 0.4, 1.0 - age), 1.3)
			"bark":  # brown flecks, torn leaves and a pale scar on the trunk
				draw_circle(base, 2.5, Color(0.9, 0.82, 0.62, 0.8 * (1.0 - age)))
				for i in range(7):
					var angle: float = (-dir).angle() + (CropArt.rand01(seed_value, i) - 0.5) * 2.4
					var pos: Vector2 = base + Vector2.from_angle(angle) * (3.0 + 14.0 * age) + Vector2(0, 16.0 * age * age)
					draw_rect(Rect2(pos, Vector2(2, 2)), Color(0.4, 0.27, 0.15, 1.0 - age) if i % 3 else Color(0.35, 0.55, 0.25, 1.0 - age))
			"spark":
				for i in range(6):
					var angle: float = (-dir).angle() + (CropArt.rand01(seed_value, i) - 0.5) * 2.6
					var a: Vector2 = base + Vector2.from_angle(angle) * (2.0 + 12.0 * age)
					draw_line(a, a + Vector2.from_angle(angle) * 3.5, Color(1.0, 0.9, 0.5, 1.0 - age), 1.2)

func _weather_amount(weather: Dictionary, kind: String) -> float:
	if weather.is_empty(): return 0.0
	var blend: float = clampf(float(simulation.state.tick - int(weather.get("since", 0))) / 300.0, 0.0, 1.0)
	return (1.0 - blend if weather.get("previous", "clear") == kind else 0.0) + (blend if weather.get("kind", "clear") == kind else 0.0)

func _draw_entity(s: Dictionary, entity: Dictionary, p: Vector2, canvas: Node2D = null) -> void:
	if canvas == null: canvas = self
	var selected: bool = entity.id == selected_id
	if selected:
		var marker := Rect2(p + Vector2(-11, -11), Vector2(22, 22))
		var mark_color := Color("f4d889")
		for corner in [Vector2(marker.position.x, marker.position.y), Vector2(marker.end.x, marker.position.y), Vector2(marker.position.x, marker.end.y), marker.end]:
			var sx: float = 5 if corner.x == marker.position.x else -5
			var sy: float = 5 if corner.y == marker.position.y else -5
			canvas.draw_line(corner, corner + Vector2(sx, 0), mark_color, 2)
			canvas.draw_line(corner, corner + Vector2(0, sy), mark_color, 2)
	match entity.kind:
		"tree":
			if not tree_inside_building(entity.cell):
				MapArt.tree(canvas, p, s.inventories[str(entity.id)].items.get("log", 0), entity.id, motion.tree_pose(entity.id, p))
		"resident", "raider":
			var npc: Dictionary = s.residents.get(str(entity.id), {})
			var cargo: bool = not s.inventories[str(entity.id)].items.is_empty()
			var fighter: Dictionary = s.get("local_combat", {}).get("fighters", {}).get(str(entity.id), {})
			if not fighter.is_empty():
				canvas.draw_rect(Rect2(p + Vector2(-10, -56), Vector2(20, 3)), Color("382b25"))
				canvas.draw_rect(Rect2(p + Vector2(-10, -56), Vector2(20.0 * fighter.health / 100.0, 3)), Color("b5cd85") if fighter.side == "defender" else Color("df8a6d"))
			if not npc.get("brawl", {}).is_empty():
				canvas.draw_string(font, p + Vector2(-7, -56), "!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e0443a"))
				for bolt in [-1, 1]:
					canvas.draw_line(p + Vector2(bolt * 9, -56), p + Vector2(bolt * 13, -61), Color("e0443a"), 1.5)
			if npc.get("hunger", 0) >= 60:
				canvas.draw_string(font, p + Vector2(-2, -52), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffce75"))
			_name_tag(canvas, p, entity.name, Color("f2ead2") if entity.kind == "resident" else Color("e79b86"))
			if selected and npc.has("path"):
				var previous := p
				for cell in npc.path:
					var next := Vector2(cell[0], cell[1]) * CELL
					canvas.draw_line(previous, next, Color(0.9, 0.8, 0.5, 0.55), 2)
					previous = next
		"player":
			_name_tag(canvas, p, entity.name, Color("ffe9a8"))
		"farm":
			if Crops.plot_for_farm(s, entity.id).is_empty(): MapArt.farm(canvas, p, s.inventories[str(entity.id)].items.get("food", 0))
		"warehouse", "home", "sawmill", "bakery", "forge", "office", "market", "saloon", "town_hall":
			var footprint := World.building_rect(entity)
			var rect := Rect2(Vector2(footprint.position) * CELL - Vector2.ONE * CELL / 2, Vector2(footprint.size) * CELL)
			# Floors and frontage are painted once into a cached texture (see _sync_decor).
			if selected:
				canvas.draw_string(font, Vector2(rect.get_center().x - 25, rect.position.y - 10), entity.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f7e3ac"))
		"construction":
			var site: Dictionary = s.construction.get(str(entity.id), {})
			var definition: Dictionary = s.building_defs.get(site.get("definition", ""), {"kind": "home"})
			var footprint := World.plot_rect(entity, definition.get("kind", "home"))
			var rect := Rect2(Vector2(footprint.position) * CELL - Vector2.ONE * CELL / 2, Vector2(footprint.size) * CELL)
			MapArt.construction(canvas, entity, site, rect)
		"caravan": MapArt.cart(canvas, p)
		"signpost": MapArt.signpost(canvas, p, entity.get("ways", []))
		"street_lamp": MapArt.street_lamp(canvas, p)
		"bandit_camp": MapArt.bandit_camp(canvas, p)
		"ore":
			if entity.get("big", false):
				var rr: Array = entity.rock_rect
				MapArt.big_rock(canvas, Rect2(Vector2(rr[0], rr[1]) * CELL - Vector2(12, 12), Vector2(rr[2], rr[3]) * CELL), int(s.inventories[str(entity.id)].items.get("ore", 0)), int(entity.id))
				return
			MapArt.rock(canvas, p)
			for glint in [Vector2(-6, -9), Vector2(5, -14), Vector2(0, -5)]:
				canvas.draw_circle(p + glint, 1.7, Color("d09a52"))
				canvas.draw_circle(p + glint, 0.8, Color("f2d9a0"))
		"stash":
			var items: Dictionary = s.inventories[str(entity.id)].items
			var offset: int=0
			for item in items:
				FixtureArt.item(canvas,p+Vector2(offset,0),item)
				offset+=12

static func plot_area(plot: Dictionary) -> Rect2:
	return Rect2(Vector2(plot.rect[0], plot.rect[1]) * CELL - Vector2(12, 12), Vector2(plot.rect[2], plot.rect[3]) * CELL)

func draw_decor(node: Node2D, decor: Decor) -> void:
	var s: Dictionary = simulation.state
	if decor.kind == "plot":
		var plot: Dictionary = s.get("crops", {}).get(str(decor.key), {})
		if not plot.is_empty(): CropArt.field(node, plot_area(plot), plot, 0.0)
	elif decor.kind == "building":
		var entity: Dictionary = s.entities.get(str(decor.key), {})
		if entity.is_empty() or not entity.has("footprint"): return
		var footprint := World.building_rect(entity)
		var rect := Rect2(Vector2(footprint.position) * CELL - Vector2.ONE * CELL / 2, Vector2(footprint.size) * CELL)
		MapArt.frontage(node, entity, rect)
		MapArt.building(node, entity)
	elif decor.kind == "plaza":
		var settlement: Dictionary = s.get("settlements", {}).get(str(decor.key), {})
		if settlement.is_empty(): return
		var store: Dictionary = s.entities[str(settlement.warehouse)]
		var stalls: Array = []
		for stall_id in settlement.get("stalls", []):
			if s.entities.has(str(stall_id)): stalls.append(s.entities[str(stall_id)])
		MarketArt.plaza(node, Vector2(store.cell[0], store.cell[1] + 7) * CELL, stalls)

## Below this zoom the view is a map: per-object nodes are dropped and trees are simple canopies.
const FAR_ZOOM: float = 0.35

func draw_speech(canvas: Node2D) -> void:
	if simulation == null or is_far(): return
	var s: Dictionary = simulation.state
	var font: Font = ThemeDB.fallback_font
	var bounds := view_bounds().grow(80)
	for line in s.get("speech", []):
		if int(line.until) < s.tick: continue
		var pose: Dictionary = motion.actors.get(str(line.speaker), {})
		if pose.is_empty() or not bounds.has_point(pose.position): continue
		var fade: float = clampf(float(int(line.until) - s.tick) / 10.0, 0.0, 1.0)
		var wrap := 150.0
		var text: String = line.text
		var measured: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap, 12)
		var box := Rect2(pose.position + Vector2(-measured.x * 0.5 - 8, -68 - measured.y - 12), measured + Vector2(16, 12))
		var anchor: Vector2 = pose.position + Vector2(0, -58)
		var style := speech_style
		style.bg_color = Color(0.98, 0.95, 0.86, 0.96 * fade)
		style.border_color = Color(0.23, 0.17, 0.11, fade)
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.anti_aliasing = true
		style.shadow_color = Color(0, 0, 0, 0.25 * fade)
		style.shadow_size = 4
		canvas.draw_style_box(style, box)
		canvas.draw_colored_polygon(PackedVector2Array([anchor + Vector2(-5, -6), anchor + Vector2(5, -6), anchor]), Color(0.98, 0.95, 0.86, 0.96 * fade))
		canvas.draw_polyline(PackedVector2Array([anchor + Vector2(-5, -6), anchor, anchor + Vector2(5, -6)]), Color(0.23, 0.17, 0.11, fade), 1.0)
		canvas.draw_multiline_string(font, box.position + Vector2(8, 16), text, HORIZONTAL_ALIGNMENT_LEFT, wrap, 12, -1, Color(0.16, 0.11, 0.07, fade))

## The sun's shadow for a point one pixel tall, in screen pixels, and how dark shadows are.
## Morning sun in the east throws long shadows to the left; they shorten and swing north (up the
## screen) towards noon, then lengthen to the right through the afternoon and fade at dusk.
func sun_shadow(tick: int) -> Dictionary:
	var day: float = float(tick % 14400) / 14400.0
	var elevation: float = DayClock.sun_elevation(day)      # 0 at sunrise (05:00) and sunset (21:00), highest at 13:00
	var arc: float = DayClock.sun_arc(day)                  # 05:00 east .. 21:00 west
	var direction := Vector2(-cos(arc * PI), -0.42 * sin(arc * PI))
	var angle: float = asin(clampf(elevation, 0.0, 1.0)) * 1.05
	var length: float = clampf(cos(angle) / maxf(0.05, sin(angle)), 0.35, 3.4)
	var strength: float = 0.30 * smoothstep(0.0, 0.16, elevation) * clampf(1.0 - sun_overcast * 3.2, 0.15, 1.0)
	return {"vector": Vector2(direction.x, direction.y * 0.55) * length, "strength": strength}

## A soft ellipse laid along the shadow direction.
func _shadow_blob(canvas: Node2D, center: Vector2, along: Vector2, length: float, width: float, color: Color) -> void:
	var axis: Vector2 = along.normalized() if along.length() > 0.001 else Vector2.RIGHT
	var normal := axis.orthogonal()
	var points := PackedVector2Array()
	for i in range(18):
		var a := float(i) / 18.0 * TAU
		points.append(center + axis * cos(a) * length + normal * sin(a) * width)
	_shadow_polygon(canvas, points, color)

## Fills a shadow shape, cutting away any part that lies on a building's floor.
func _batch_polygon(polygon: PackedVector2Array, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty(): return
	var base := batch_points.size()
	batch_points.append_array(polygon)
	var shades := PackedColorArray()
	shades.resize(polygon.size())
	shades.fill(color)
	batch_colors.append_array(shades)
	for index in triangles: batch_indices.append(base + index)

func _shadow_polygon(canvas: Node2D, points: PackedVector2Array, color: Color) -> void:
	var pieces: Array = [points]
	var extent := Rect2(points[0], Vector2.ZERO)
	for point in points: extent = extent.expand(point)
	for roof in roofs:
		if not roof.intersects(extent): continue
		var cut := PackedVector2Array([roof.position, Vector2(roof.end.x, roof.position.y), roof.end, Vector2(roof.position.x, roof.end.y)])
		var remaining: Array = []
		for piece in pieces:
			for part in Geometry2D.clip_polygons(piece, cut): remaining.append(part)
		pieces = remaining
	for piece in pieces:
		# Holes come back wound the other way round; skip them.
		if (piece as PackedVector2Array).size() >= 3 and (pieces.size() == 1 or Geometry2D.is_polygon_clockwise(piece) == Geometry2D.is_polygon_clockwise(points)):
			if shadow_batch: _batch_polygon(piece, color)
			else: canvas.draw_colored_polygon(piece, color)

## Every roof in the world (building floors get no sun), rebuilt when buildings change.
var all_roofs: Array[Rect2] = []
var all_roofs_signature: Array = []
## Static shadows (trees, buildings, rocks) are painted for an area larger than the screen and
## kept until the sun, that area or the trees change; people's shadows are redrawn every frame.
var shadow_area := Rect2()
var static_shadow_signature: Array = []
var shadow_batch: bool = false
var batch_points := PackedVector2Array()
var batch_colors := PackedColorArray()
var batch_indices := PackedInt32Array()

func _roofs_for(s: Dictionary, bounds: Rect2) -> void:
	var signature := [s.entities.size(), s.get("completed_buildings", 0)]
	if signature != all_roofs_signature:
		all_roofs_signature = signature
		all_roofs.clear()
		for entity in s.entities.values():
			if entity.has("footprint"):
				var fp := World.building_rect(entity)
				all_roofs.append(Rect2(Vector2(fp.position) * CELL - Vector2.ONE * CELL / 2, Vector2(fp.size) * CELL))
	roofs.clear()
	for area in all_roofs:
		if bounds.intersects(area): roofs.append(area)

## Called every frame: repaints the static shadow layer only when what it shows has changed.
func _update_shadow_layers() -> void:
	actor_shadows.queue_redraw()
	if simulation == null: return
	var s: Dictionary = simulation.state
	var sun := sun_shadow(int(s.tick))
	var vector: Vector2 = sun.vector
	# Quantised so the layer repaints when a crown's shadow (64 px along the sun line) would move
	# by about a third of a pixel, or the shade changes by a quarter of a percent.
	var signature := [roundi(vector.x * 200.0), roundi(vector.y * 200.0), roundi(float(sun.strength) * 400.0), is_far(),
		s.entities.size(), s.get("completed_buildings", 0), motion.tree_serial, depth_index_signature]
	var needed := view_bounds().grow(220)
	if signature != static_shadow_signature or not shadow_area.encloses(needed):
		static_shadow_signature = signature
		shadow_area = view_bounds().grow(560)
		shadows.queue_redraw()

func draw_static_shadows(canvas: Node2D) -> void:
	if simulation == null or is_far(): return
	var s: Dictionary = simulation.state
	var sun := sun_shadow(int(s.tick))
	var strength: float = sun.strength
	if strength < 0.01: return
	var cast: Vector2 = sun.vector
	var tone := Color(0.08, 0.10, 0.14, strength)
	var soft := Color(0.08, 0.10, 0.14, strength * 0.55)
	var bounds := shadow_area
	# Interiors are under a roof: no sunlight, so no sun shadows fall on building floors.
	_roofs_for(s, bounds)
	# Everything goes into one triangle list, one draw call; triangles keep their order, so the
	# overlaps darken exactly as separate shapes did.
	shadow_batch = true
	batch_points.clear()
	batch_colors.clear()
	batch_indices.clear()
	var across := cast.orthogonal().normalized()
	var low := Vector2i(floori(bounds.position.x / CELL / DEPTH_CHUNK), floori(bounds.position.y / CELL / DEPTH_CHUNK))
	var high := Vector2i(floori(bounds.end.x / CELL / DEPTH_CHUNK), floori(bounds.end.y / CELL / DEPTH_CHUNK))
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			for entry in depth_index.get("%d,%d" % [cx, cy], []):
				if entry[1] != "tree" or not bounds.has_point(entry[2]): continue
				var entity: Dictionary = s.entities.get(str(entry[3]), {})
				if entity.is_empty(): continue
				var logs: int = int(s.inventories.get(str(entity.id), {}).get("items", {}).get("log", 0))
				if logs <= 0 or entity.get("felled", false): continue
				var dead: bool = entity.get("dead", false)
				# Trunk, then the crown's shadow thrown out along the sun line.
				var foot: Vector2 = entry[2] + Vector2(0, -2)
				_shadow_polygon(canvas, PackedVector2Array([foot + across * 3.0, foot - across * 3.0, foot + cast * 46.0 - across * 1.6, foot + cast * 46.0 + across * 1.6]), tone)
				var crown := foot + cast * 64.0
				var spread: float = 15.0 if dead else 27.0
				_shadow_blob(canvas, crown, cast, spread + 7.0 * cast.length(), spread * 0.82, tone)
				_shadow_blob(canvas, crown + cast * 6.0, cast, (spread + 7.0 * cast.length()) * 0.7, spread * 0.6, soft)
	if shadow_list_age <= 0 or s.entities.size() != shadow_list_count:
		shadow_list.clear()
		for entity in s.entities.values():
			if entity.has("footprint") or entity.has("rock_rect") or entity.get("kind", "") == "caravan": shadow_list.append(int(entity.id))
		shadow_list_count = s.entities.size()
		shadow_list_age = 90
	shadow_list_age -= 1
	for id in shadow_list:
		var entity: Dictionary = s.entities.get(str(id), {})
		if entity.is_empty() or not entity.has("cell"): continue
		if entity.get("kind", "") == "ore" and entity.has("rock_rect"):
			var r: Array = entity.rock_rect
			_building_shadow(canvas, Rect2(Vector2(r[0], r[1]) * CELL - Vector2(12, 12), Vector2(r[2], r[3]) * CELL), 34.0, cast, tone, bounds)
		if entity.has("footprint"):
			var fp := World.building_rect(entity)
			_building_shadow(canvas, Rect2(Vector2(fp.position) * CELL - Vector2.ONE * CELL / 2, Vector2(fp.size) * CELL), 46.0, cast, tone, bounds)
	shadow_batch = false
	if not batch_indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), batch_indices, batch_points, batch_colors)

## People and moving carts: redrawn every frame, on top of the static shadows.
func draw_actor_shadows(canvas: Node2D) -> void:
	if simulation == null or is_far(): return
	var s: Dictionary = simulation.state
	var sun := sun_shadow(int(s.tick))
	var strength: float = sun.strength
	if strength < 0.01: return
	var cast: Vector2 = sun.vector
	var tone := Color(0.08, 0.10, 0.14, strength)
	var bounds := view_bounds().grow(220)
	_roofs_for(s, bounds)
	for id in shadow_list:
		var entity: Dictionary = s.entities.get(str(id), {})
		if entity.get("kind", "") != "caravan" or not entity.has("cell"): continue
		var p := Vector2(entity.cell[0], entity.cell[1]) * CELL
		if bounds.has_point(p): _shadow_blob(canvas, p + cast * 14.0, cast, 20.0 + 9.0 * cast.length(), 12.0, tone)
	# People: a body-long shadow from the feet, plus a small dark contact patch.
	for key in motion.actors:
		var pose: Dictionary = motion.actors[key]
		var feet: Vector2 = pose.position
		if not bounds.has_point(feet): continue
		var action: String = pose.get("action", "idle")
		var tall: float = 42.0 * (0.45 if action in ["down", "rest"] else (0.7 if action in ["fall", "getup"] else 1.0 - 0.3 * clampf(float(pose.get("sneak", 0.0)), 0.0, 1.0)))
		_shadow_blob(canvas, feet + Vector2(0, 1), Vector2.RIGHT, 7.5, 3.0, Color(0.05, 0.06, 0.08, 0.16 + strength * 0.4))
		_shadow_blob(canvas, feet + cast * tall * 0.5, cast, maxf(5.0, tall * cast.length() * 0.5 + 3.0), 5.5, tone)

## A wall-high block's shadow: the footprint swept along the sun line, minus the footprint itself.
func _building_shadow(canvas: Node2D, rect: Rect2, height: float, cast: Vector2, tone: Color, bounds: Rect2) -> void:
	if not bounds.intersects(rect.grow(height * 3.5)): return
	var offset := cast * height
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var swept := PackedVector2Array()
	for corner in corners:
		swept.append(corner)
		swept.append(corner + offset)
	var hull := Geometry2D.convex_hull(swept)
	for piece in Geometry2D.clip_polygons(hull, corners):
		if piece.size() >= 3: _shadow_polygon(canvas, piece, tone)

func is_far() -> bool:
	var camera := get_viewport().get_camera_2d()
	return camera != null and camera.zoom.x < FAR_ZOOM

var decor_nodes: Dictionary = {}
var decor_far: bool = false
var decor_signatures: Dictionary = {}
var door_hold: Dictionary = {}
var overlay_labels: bool = false      # set by the controller while the map overlay is up
var decor_clock: float = 99.0

## Creates, refreshes and removes the cached ground layers; checked twice a second.
func _sync_decor(delta: float) -> void:
	decor_clock += delta
	if decor_clock < 0.5: return
	decor_clock = 0.0
	var s: Dictionary = simulation.state
	var wanted: Dictionary = {}
	for settlement in s.get("settlements", {}).values():
		var square: Array = s.entities[str(settlement.warehouse)].cell
		wanted["plaza:%d" % settlement.id] = ["plaza", int(settlement.id), str(settlement.get("stalls", [])), Rect2(Vector2(square[0], square[1] + 7) * CELL + Vector2(-520, -110), Vector2(1040, 330))]
	for entity in s.entities.values():
		if entity.has("footprint") and entity.kind in World.BUILDING_KINDS:
			var fp := World.building_rect(entity)
			var rect := Rect2(Vector2(fp.position) * CELL - Vector2.ONE * CELL / 2, Vector2(fp.size) * CELL)
			wanted["building:%d" % entity.id] = ["building", int(entity.id), "%s:%s:%s:%s" % [entity.kind, str(entity.footprint), str(entity.get("door", [])), str(entity.get("cell_open", false))], rect.grow(48)]
	for plot in s.get("crops", {}).values():
		# One redraw per 1% of growth keeps the crop visibly changing without per-frame cost.
		var field_area: Rect2 = plot_area(plot)
		wanted["plot:%d" % plot.id] = ["plot", int(plot.id), "%d:%s:%s" % [Crops.permille(plot) / 10, plot.state, str(plot.rect)], Rect2(field_area.position - Vector2(16, 48), field_area.size + Vector2(32, 64))]
	for key in wanted:
		var entry: Array = wanted[key]
		if not decor_nodes.has(key):
			var node := Decor.new()
			node.projector = self
			node.kind = entry[0]
			node.key = entry[1]
			node.area = entry[3]
			node.z_index = -1
			add_child(node)
			move_child(node, background.get_index())
			decor_nodes[key] = node
			if decor_far and str(key).begins_with("building:"): node.visible = false
		if entry[0] == "building": decor_nodes[key].modulate = house_tint(s, int(entry[1]))
		if decor_signatures.get(key, "") != entry[2]:
			decor_signatures[key] = entry[2]
			decor_nodes[key].set_area(entry[3])
	for key in decor_nodes.keys():
		if not wanted.has(key):
			decor_nodes[key].queue_free()
			decor_nodes.erase(key)
			decor_signatures.erase(key)


## Name plate centred underneath a character; it follows the actor's drawn position.
func _name_tag(canvas: Node2D, p: Vector2, label: String, color: Color) -> void:
	if is_far(): return   # zoomed out to the overview: no name tags
	var size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	var origin: Vector2 = p + Vector2(-size.x / 2.0, 14)
	canvas.draw_rect(Rect2(origin + Vector2(-2, -9), size + Vector2(4, 3)), Color(0.07, 0.06, 0.04, 0.55))
	canvas.draw_string(font, origin + Vector2(0.5, 0.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.8))
	canvas.draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

## The furniture or fixture the last pick() landed on inside a building ("furniture:<i>",
## "fixture:<i>"), or "" when it picked a thing in its own right.
var last_pick_part: String = ""

func pick(world_position: Vector2) -> int:
	last_pick_part = ""
	var best: int = 0
	var distance: float = 26.0
	for entity in simulation.state.entities.values():
		if not entity.has("cell"):
			continue
		var p := Vector2(entity.cell[0], entity.cell[1]) * CELL
		var candidate := (p - Vector2(0, 19) if entity.kind in ["resident", "player", "raider"] else p).distance_to(world_position) - float(entity.get("pick_radius", 0.0))
		if candidate < distance:
			distance = candidate
			best = entity.id
	if best == 0:
		# Inside a building only the furniture and fixtures answer a click; bare floor is nothing.
		return pick_part(world_position)
	return best

## The building whose furniture or fixture is under this point (setting last_pick_part), or 0.
## Tall furniture is drawn reaching up into the cell above, so that cell counts too; a chest
## answers as its own chest.
func pick_part(world_position: Vector2) -> int:
	var s: Dictionary = simulation.state
	var cell := Vector2i(roundi(world_position.x / CELL), roundi(world_position.y / CELL))
	for probe in [cell, cell + Vector2i(0, 1)]:
		var owner_id: int = int(s.world.get("fixture_cells", {}).get("%d,%d" % [probe.x, probe.y], 0))
		var building: Dictionary = s.entities.get(str(owner_id), {})
		if building.is_empty(): continue
		for list_name in ["fixtures", "furniture"]:
			var items: Array = building.get(list_name, [])
			for index in range(items.size()):
				var r: Array = items[index].rect
				if probe.x < r[0] or probe.y < r[1] or probe.x >= r[0] + r[2] or probe.y >= r[1] + r[3]: continue
				if items[index].has("chest_id") and s.entities.has(str(items[index].chest_id)): return int(items[index].chest_id)
				last_pick_part = ("fixture:%d" if list_name == "fixtures" else "furniture:%d") % index
				return owner_id
	return 0

func tree_inside_building(cell: Array) -> bool:
	for rect in building_rects:
		if rect.has_point(Vector2i(cell[0], cell[1])):
			return true
	return false
