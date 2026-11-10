extends SceneTree
## Compare production scenery with an expanded, pre-change sky shader supplied
## through IMMIVIO_SKY_REFERENCE. Both variants share the identical baked base.
const Background := preload("res://scripts/app_background.gd")
const OUTPUT := "res://../../artifacts/reports/background-optimization"
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var environments: Array[Environment] = []
var output: String
var results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func use_sky(sky: Sky) -> void:
	for environment in environments:
		environment.sky = sky


func draw_frame() -> void:
	await process_frame
	# Explicit offscreen draws keep the probe running when macOS occludes its
	# window. Automatic rendering is disabled to avoid measuring two draws.
	RenderingServer.force_draw(false)


func measure(label: String, sky: Sky) -> void:
	use_sky(sky)
	for frame in 60:
		await draw_frame()
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 180:
		await draw_frame()
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	samples.sort()
	var result := {
		"case": label,
		"eye_size": views[0].size.x,
		"pitch_degrees": rad_to_deg(cameras[0].rotation.x),
		"frame_ms_median": samples[90],
		"frame_ms_p95": samples[171],
	}
	results.append(result)
	print(JSON.stringify(result))


func _run() -> void:
	var reference_path := OS.get_environment("IMMIVIO_SKY_REFERENCE")
	if DisplayServer.get_name() == "headless" or not FileAccess.file_exists(reference_path):
		push_error("A real GPU and IMMIVIO_SKY_REFERENCE expanded shader file are required.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.render_loop_enabled = false
	root.size = Vector2i(640, 360)
	output = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output)
	for eye in 2:
		var view := SubViewport.new()
		view.size = Vector2i(1024, 1024)
		view.own_world_3d = true
		view.msaa_3d = Viewport.MSAA_2X
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_SKY
		view.add_child(world)
		environments.append(world.environment)
		var camera := Camera3D.new()
		camera.fov = 100
		view.add_child(camera)
		cameras.append(camera)
	var background := Background.new()
	root.add_child(background)
	while background.loading:
		await draw_frame()
	var reference_material := ShaderMaterial.new()
	reference_material.shader = Shader.new()
	reference_material.shader.code = FileAccess.get_file_as_string(reference_path)
	reference_material.set_shader_parameter("scene", 0)
	reference_material.set_shader_parameter("baked", background._bake.get_texture())
	var reference := Sky.new()
	reference.radiance_size = Sky.RADIANCE_SIZE_32
	reference.sky_material = reference_material
	for size in [1024, 2048]:
		for view in views:
			view.size = Vector2i(size, size)
		for pitch in [45, 0, -45]:
			for camera in cameras:
				camera.rotation_degrees = Vector3(pitch, 0, 0)
			await measure("original", reference)
			await measure("optimized", background.sky)
			await measure("original_repeat", reference)
		# Include the horizon, poles, seam, subpixel head motion, yaw and dimming.
		for angle in [
			Vector3(45, 0, 0),
			Vector3.ZERO,
			Vector3(-45, 0, 0),
			Vector3(89, 180, 0),
			Vector3(.037, 179.93, 0),
			Vector3(25.013, 45.017, 0)
		]:
			for camera in cameras:
				camera.rotation_degrees = angle
			var energy := .75 if is_equal_approx(angle.y, 45.017) else 1.0
			reference_material.set_shader_parameter("energy", energy)
			background.set_brightness(energy)
			environments[0].sky = reference
			environments[1].sky = background.sky
			await draw_frame()
			await draw_frame()
			var name := "%d-%s" % [size, str(angle).replace(" ", "")]
			for eye in 2:
				views[eye].get_texture().get_image().save_png(
					output.path_join(name + ("-original.png" if eye == 0 else "-optimized.png"))
				)
		reference_material.set_shader_parameter("energy", 1.0)
		background.set_brightness(1.0)
	var report := {
		"adapter": RenderingServer.get_video_adapter_name(),
		"reference_sha256": FileAccess.get_sha256(reference_path),
		"vsync_actual": DisplayServer.window_get_vsync_mode(),
		"scope": "Two mono viewports; no video/UI/OpenXR compositor; 2x MSAA.",
		"draw_mode": "Explicit offscreen draws without buffer swap; automatic rendering disabled.",
		"results": results,
	}
	var file := FileAccess.open(output.path_join("comparison.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for view in views:
		view.queue_free()
	background.queue_free()
	quit()
