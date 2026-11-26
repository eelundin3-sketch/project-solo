extends Node2D
## Weather you can see, drawn over the people and under the night: falling rain or snow from one
## pooled GPU particle system that follows the camera (at most 600 drops), and a fog veil.
## The weather shown is that of the town the camera is over (each town has its own weather).
## Nothing falls indoors or at the far map zoom. Reads simulation state only.
const World = preload("res://sim/world/world_db.gd")
const Weather = preload("res://sim/world/weather.gd")
const CELL: float = 24.0
const RAIN_DROPS := 600
const SNOW_FLAKES := 420

var simulation: RefCounted
var particles: GPUParticles2D
var process: ParticleProcessMaterial
var showing: String = ""          # "rain", "snow" or ""
var fog: float = 0.0
var bounds := Rect2()
var rain_texture: ImageTexture
var snow_texture: ImageTexture

func _init() -> void:
	particles = GPUParticles2D.new()
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_rect = Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.gravity = Vector3.ZERO
	process.particle_flag_align_y = true
	particles.process_material = process
	add_child(particles)
	rain_texture = _texture(2, 22, true)
	snow_texture = _texture(5, 5, false)

static func _texture(w: int, h: int, streak: bool) -> ImageTexture:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var a: float = (float(y) / float(h)) if streak else maxf(0.0, 1.0 - Vector2(x - (w - 1) / 2.0, y - (h - 1) / 2.0).length() / (w / 2.0))
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)

## What falls where the camera is: "rain", "snow" or "" (none, or indoors, or zoomed far out).
func falling_at(s: Dictionary, centre: Vector2, far: bool) -> String:
	if far: return ""
	var cell: Array = [roundi(centre.x / CELL), roundi(centre.y / CELL)]
	if World.inside_building(s, cell) != 0: return ""
	var kind: String = Weather.kind_at(s, cell)
	return kind if kind in ["rain", "snow"] else ""

func update(view: Rect2, far: bool, amount: Callable) -> void:
	if simulation == null: return
	var s: Dictionary = simulation.state
	bounds = view
	var centre := view.get_center()
	var cell: Array = [roundi(centre.x / CELL), roundi(centre.y / CELL)]
	var region: Dictionary = Weather.at(s, cell)
	var kind := falling_at(s, centre, far)
	var strength: float = amount.call(region, kind) if kind != "" else 0.0
	if kind != showing:
		showing = kind
		_configure(kind, int(region.get("wind", 25)))
	particles.emitting = kind != "" and strength > 0.05
	particles.position = centre
	process.emission_box_extents = Vector3(view.size.x / 2.0 + 40.0, view.size.y / 2.0 + 40.0, 0.0)
	particles.modulate.a = clampf(strength, 0.0, 1.0)
	var fog_now: float = 0.0 if far else amount.call(region, "fog")
	if absf(fog_now - fog) > 0.01 or (fog_now == 0.0) != (fog == 0.0):
		fog = fog_now
	queue_redraw()

func _configure(kind: String, wind: int) -> void:
	var drift: float = float(wind - 50) / 100.0
	match kind:
		"rain":
			particles.amount = RAIN_DROPS
			particles.lifetime = 0.7
			particles.texture = rain_texture
			process.direction = Vector3(-0.12 + drift * 0.3, 1.0, 0.0)
			process.spread = 2.0
			process.initial_velocity_min = 620.0
			process.initial_velocity_max = 760.0
			process.color = Color(0.80, 0.87, 0.92, 0.85)
			process.scale_min = 0.8
			process.scale_max = 1.2
		"snow":
			particles.amount = SNOW_FLAKES
			particles.lifetime = 5.0
			particles.texture = snow_texture
			process.direction = Vector3(drift * 0.6, 1.0, 0.0)
			process.spread = 25.0
			process.initial_velocity_min = 30.0
			process.initial_velocity_max = 60.0
			process.color = Color(0.96, 0.97, 0.98, 0.85)
			process.scale_min = 0.6
			process.scale_max = 1.3
	particles.restart()

func _draw() -> void:
	if fog > 0.0: draw_rect(bounds, Color(0.74, 0.77, 0.75, fog * 0.46))
