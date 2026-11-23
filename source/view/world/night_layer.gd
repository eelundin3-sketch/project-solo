extends Node2D
## The dark of night as one full-view rectangle with a shader, with warm pools cut out of it for
## street lamps, lit windows of homes where someone is awake, and lanterns. One draw call and
## at most 64 lights, nearest the middle of the view first. It sits under the speech bubbles so
## they stay readable. Reads simulation state only; never writes it.
const World = preload("res://sim/world/world_db.gd")
const Light = preload("res://sim/world/light.gd")
const DayClock = preload("res://sim/world/day_clock.gd")
const CELL: float = 24.0
const MAX_LIGHTS := 64
const REFRESH := 0.25      # seconds between rebuilding the slow part of the list (windows, lamps)

const SHADER := """
shader_type canvas_item;
uniform float darkness = 0.0;
uniform vec4 night_color : source_color = vec4(0.03, 0.05, 0.12, 1.0);
uniform vec4 warm : source_color = vec4(1.0, 0.70, 0.32, 1.0);
uniform int light_count = 0;
uniform vec4 lights[64];   // x, y in world pixels; radius in pixels; strength 0..1
varying vec2 world;
void vertex() { world = VERTEX; }
void fragment() {
	float lit = 0.0;
	for (int i = 0; i < 64; i++) {
		if (i >= light_count) break;
		vec4 l = lights[i];
		float d = length((world - l.xy) / vec2(1.0, 0.72));   // pools on the ground: wider than tall
		lit = max(lit, (1.0 - smoothstep(l.z * 0.18, l.z, d)) * l.w);
	}
	float alpha = darkness * (1.0 - lit * 0.88) + darkness * lit * 0.20;
	COLOR = vec4(mix(night_color.rgb, warm.rgb, clamp(lit * 1.4, 0.0, 1.0)), alpha);
}
"""

var simulation: RefCounted
var projector: Node2D            # the world view: bounds, actor positions
var darkness: float = 0.0
var lights: Array = []           # [Vector4] sent to the shader this frame
var slow_lights: Array = []      # lamps and windows, rebuilt every REFRESH seconds
var slow_age: float = 99.0
var slow_center := Vector2.INF
var bounds := Rect2()

func _init() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat

## Darkness from the same light curve the day tint uses (DayClock): none 06:00-20:00, rising
## through dusk to about 0.7 for the night (22:00-04:00), lifting again at dawn.
static func darkness_at(tick: int, overcast: float = 0.0) -> float:
	var day: float = DayClock.light_amount(float(tick % 14400) / 14400.0)
	return clampf((1.0 - day) * 0.72 + overcast * 0.25 * (1.0 - day), 0.0, 0.8)

## `far`: zoomed out to the overview, where light pools are too small to see: the night is only
## darkened, with no per-pixel pools to work out (the darkness pass is then almost free).
func update(delta: float, view: Rect2, overcast: float, far: bool = false) -> void:
	if simulation == null: return
	var s: Dictionary = simulation.state
	darkness = darkness_at(int(s.tick), overcast)
	visible = darkness > 0.01
	if not visible: return
	bounds = view
	if far:
		if not lights.is_empty() or slow_center != Vector2.INF:
			lights = []
			slow_lights = []
			slow_center = Vector2.INF
			material.set_shader_parameter("light_count", 0)
		material.set_shader_parameter("darkness", darkness)
		queue_redraw()
		return
	slow_age += delta
	if slow_age >= REFRESH or view.get_center().distance_to(slow_center) > CELL * 4.0:
		slow_age = 0.0
		slow_center = view.get_center()
		slow_lights = _slow_lights(s, view.grow(CELL * 6))
	lights = slow_lights.duplicate()
	_add_lanterns(s, view.grow(CELL * 4))
	var middle := view.get_center()
	if lights.size() > MAX_LIGHTS:
		lights.sort_custom(func(a: Vector4, b: Vector4) -> bool: return Vector2(a.x, a.y).distance_squared_to(middle) < Vector2(b.x, b.y).distance_squared_to(middle))
		lights.resize(MAX_LIGHTS)
	var packed: Array = lights.duplicate()
	while packed.size() < MAX_LIGHTS: packed.append(Vector4.ZERO)
	material.set_shader_parameter("darkness", darkness)
	material.set_shader_parameter("light_count", lights.size())
	material.set_shader_parameter("lights", packed)
	queue_redraw()

func _draw() -> void:
	if visible: draw_rect(bounds, Color.WHITE)

## Street lamps (while lit) and the windows of homes where someone is up.
func _slow_lights(s: Dictionary, area: Rect2) -> Array:
	var result: Array = []
	if Light.lamps_lit(s):
		for lamp in World.of_kind(s, "street_lamp"):
			var p := Vector2(lamp.cell[0], lamp.cell[1]) * CELL
			if area.has_point(p): result.append(Vector4(p.x, p.y + 6.0, CELL * float(Light.LAMP_REACH), 1.0))
		# The bandits' campfire.
		for camp in World.of_kind(s, "bandit_camp"):
			var f := Vector2(camp.cell[0], camp.cell[1]) * CELL
			if area.has_point(f): result.append(Vector4(f.x, f.y, CELL * 4.5, 1.0))
		# The two lamps drawn on each town square (frontier_map_art.gd square()).
		for town in s.get("settlements", {}).values():
			var store: Array = s.entities[str(town.warehouse)].cell
			var centre := Vector2(store[0], store[1] + 3) * CELL
			for dx in [-75.0, 75.0]:
				var q := centre + Vector2(dx, -20)
				if area.has_point(q): result.append(Vector4(q.x, q.y + 4.0, CELL * 3.5, 0.9))
	if Light.daylight(s) < 100:
		var awake_in: Dictionary = {}
		for npc in s.get("residents", {}).values():
			if not npc.get("sleeping", {}).is_empty() or npc.get("dead", false): continue
			var entity: Dictionary = s.entities.get(str(npc.id), {})
			if entity.is_empty(): continue
			var p := Vector2(entity.cell[0], entity.cell[1]) * CELL
			if not area.has_point(p): continue
			var inside: int = World.inside_building(s, entity.cell)
			if inside != 0: awake_in[inside] = true
		for building_id in awake_in:
			var building: Dictionary = s.entities.get(str(building_id), {})
			if building.is_empty(): continue
			var r := World.building_rect(building)
			var rect := Rect2(Vector2(r.position) * CELL - Vector2.ONE * CELL / 2, Vector2(r.size) * CELL)
			result.append(Vector4(rect.get_center().x, rect.get_center().y, maxf(rect.size.x, rect.size.y) * 0.62, 0.75))
	return result

## The player's lantern (held in hand) and lanterns carried by people out after dark.
func _add_lanterns(s: Dictionary, area: Rect2) -> void:
	var actors: Dictionary = projector.motion.actors if projector != null else {}
	if Light.lantern_on(s) and s.has("player"):
		var p: Vector2 = _actor_point(s, s.player, actors)
		lights.append(Vector4(p.x, p.y, CELL * float(Light.LANTERN_REACH + 1), 0.95))
	if Light.daylight(s) >= 60: return
	for npc in s.get("residents", {}).values():
		if not npc.get("sleeping", {}).is_empty() or npc.get("dead", false): continue
		var entity: Dictionary = s.entities.get(str(npc.id), {})
		if entity.is_empty(): continue
		var p: Vector2 = _actor_point(s, int(npc.id), actors)
		if not area.has_point(p) or World.inside_building(s, entity.cell) != 0: continue
		lights.append(Vector4(p.x, p.y, CELL * 2.6, 0.6))

func _actor_point(s: Dictionary, id: int, actors: Dictionary) -> Vector2:
	if actors.has(str(id)): return actors[str(id)].position
	var cell: Array = s.entities[str(id)].cell
	return Vector2(cell[0], cell[1]) * CELL
