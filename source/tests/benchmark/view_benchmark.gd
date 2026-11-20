extends SceneTree
## Windowed frame benchmark of the real game at several zoom levels, and with the map open (M).
## For each it records
## frame-time percentiles, render CPU and GPU time, draw calls, and where the script time went
## (the perf probe's sections, per frame). Not headless: rendering is what it measures.
## Run: godot --path . --script res://tests/benchmark/view_benchmark.gd
## SOLO_BENCH_LABEL=<name> also writes docs/validation/view_benchmark_<name>.json.
const SECONDS := 8.0
var main: Node

func _initialize() -> void:
	call_deferred("run")

func _percentile(sorted: Array, fraction: float) -> float:
	return snappedf(sorted[clampi(int((sorted.size() - 1) * fraction), 0, sorted.size() - 1)], 0.01) if not sorted.is_empty() else 0.0

func run() -> void:
	main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	var perf: Control = main.perf
	# SOLO_BENCH_HOUR moves the clock (default 12:00): at night there are no sun shadows to draw.
	var hour := int(OS.get_environment("SOLO_BENCH_HOUR")) if OS.get_environment("SOLO_BENCH_HOUR") != "" else 12
	main.simulation.state.tick = hour * 600
	# SOLO_BENCH_WEATHER (rain, snow or fog) sets that weather in every town, fully set in, with mud.
	var weather_kind: String = OS.get_environment("SOLO_BENCH_WEATHER")
	if weather_kind != "":
		var w: Dictionary = main.simulation.state.weather
		for region in w.get("regions", {}).values():
			region.kind = weather_kind; region.previous = weather_kind; region.since = hour * 600 - 1000
			region.mud = 80 if weather_kind == "rain" else 0
			region.snow = 60 if weather_kind == "snow" else 0
		w.kind = weather_kind; w.previous = weather_kind; w.since = hour * 600 - 1000
	var camera: Camera2D = main.get_node("ObserverCamera")
	for warm in range(90): await process_frame
	var rows: Array = []
	for zoom in [2.0, 1.0, 0.5, 0.2, "map"]:
		if zoom is String:
			camera.zoom = Vector2.ONE * 2.0
			main.toggle_map()
		else:
			camera.zoom = Vector2.ONE * zoom
		for warm in range(45): await process_frame
		perf.cumulative = {}
		perf.cumulative_counts = {}
		perf.cumulative_frames = 0
		var samples: Array[float] = []
		var started := Time.get_ticks_usec()
		var previous := started
		var draw_calls := 0
		var render_cpu := 0.0
		var render_gpu := 0.0
		var reads := 0
		while Time.get_ticks_usec() - started < int(SECONDS * 1000000.0):
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous) / 1000.0)
			previous = now
			if samples.size() % 10 == 0 and perf.stats.has("render_cpu_ms"):
				draw_calls += int(perf.stats.draw_calls)
				render_cpu += float(perf.stats.render_cpu_ms)
				render_gpu += float(perf.stats.render_gpu_ms)
				reads += 1
		perf._take_sections()
		var frames: float = maxf(1.0, float(perf.cumulative_frames))
		var sections: Dictionary = {}
		for key in perf.cumulative:
			sections[key] = snappedf(float(perf.cumulative[key]) / 1000.0 / frames, 0.01)
		var counts: Dictionary = {}
		for key in perf.cumulative_counts:
			counts[key] = snappedf(float(perf.cumulative_counts[key]) / frames, 0.1)
		samples.sort()
		var row := {"zoom": zoom, "frames": samples.size(), "fps": snappedf(float(samples.size()) / SECONDS, 0.1), "p50_ms": _percentile(samples, 0.5), "p95_ms": _percentile(samples, 0.95), "p99_ms": _percentile(samples, 0.99), "max_ms": snappedf(samples[-1], 0.1),
			"draw_calls": draw_calls / maxi(1, reads), "render_cpu_ms": snappedf(render_cpu / maxf(1.0, reads), 0.01), "render_gpu_ms": snappedf(render_gpu / maxf(1.0, reads), 0.01), "ms_per_frame": sections, "per_frame": counts}
		rows.append(row)
		print(JSON.stringify(row))
		if zoom is String: main.toggle_map()
	var label := OS.get_environment("SOLO_BENCH_LABEL")
	if label != "":
		var file := FileAccess.open("res://docs/validation".path_join("view_benchmark_%s.json" % label), FileAccess.WRITE)
		file.store_string(JSON.stringify({"label": label, "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "window": root.size, "rows": rows}, "  "))
		file.close()
	quit(0)
