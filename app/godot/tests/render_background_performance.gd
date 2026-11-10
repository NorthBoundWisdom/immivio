extends SceneTree
## Real GPU scenery probe. Two independent views approximate stereo pixel load,
## without claiming to emulate a headset GPU, multiview or its compositor.
const Background := preload("res://scripts/app_background.gd")
const OUTPUT := "res://../../artifacts/reports/background-performance"
var views: Array[SubViewport] = []
var environments: Array[Environment] = []
var cameras: Array[Camera3D] = []
var background: Node
var results: Array[Dictionary] = []
var output: String


func _initialize() -> void:
	call_deferred("_run")


func stats(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median": values[values.size() / 2], "p95": values[int(values.size() * .95)]}


func measure(label: String, sky: Sky) -> void:
	for environment in environments:
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY if sky else Environment.BG_COLOR
	for frame in 60:
		await RenderingServer.frame_post_draw
	var wall: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 180:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append((now - previous) / 1000.0)
		previous = now
		var gpu_ms := 0.0
		var cpu_ms := 0.0
		for view in views:
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
			cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid())
		gpu.append(gpu_ms)
		cpu.append(cpu_ms)
	var result := {
		"case": label,
		"eye_size": [views[0].size.x, views[0].size.y],
		"view_count": views.size(),
		"frame_ms": stats(wall),
		"views_gpu_ms": stats(gpu),
		"views_cpu_ms": stats(cpu),
	}
	results.append(result)
	print(JSON.stringify(result))
	if label == "starry_night":
		var screenshot := output.path_join("starry-%d.png" % views[0].size.x)
		views[0].get_texture().get_image().save_png(screenshot)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This probe requires a real GPU; do not run headless.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	output = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(640, 360)
	for eye in 2:
		var view := SubViewport.new()
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_2X
		root.add_child(view)
		views.append(view)
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_color = Color.BLACK
		view.add_child(world)
		environments.append(world.environment)
		var camera := Camera3D.new()
		camera.fov = 100
		camera.rotation.x = deg_to_rad(25)
		view.add_child(camera)
		cameras.append(camera)
	background = Background.new()
	root.add_child(background)
	while background.loading:
		await RenderingServer.frame_post_draw
	var reference_base := preload("res://tests/support/background_reference.gd").create(root)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	# Keep the ridge and all other runtime math to isolate the three star layers.
	var shared := FileAccess.get_file_as_string("res://shaders/procedural_scenery.gdshaderinc")
	var start := shared.find("  vec3 stars =")
	var end := shared.find(";", start)
	if start < 0 or end < 0:
		push_error("Star layer source changed; update the diagnostic variant before measuring.")
		quit(1)
		return
	shared = shared.substr(0, start) + "  vec3 stars = vec3(0.0)" + shared.substr(end)
	var no_stars_material := ShaderMaterial.new()
	no_stars_material.shader = Shader.new()
	var sky_code := FileAccess.get_file_as_string("res://shaders/procedural_sky.gdshader")
	no_stars_material.shader.code = sky_code.replace(
		'#include "res://shaders/procedural_scenery.gdshaderinc"', shared
	)
	no_stars_material.set_shader_parameter("scene", 0)
	no_stars_material.set_shader_parameter("baked", reference_base.get_texture())
	var no_stars := Sky.new()
	no_stars.radiance_size = Sky.RADIANCE_SIZE_32
	no_stars.sky_material = no_stars_material
	# Same baked texture and mapping, with only runtime stars/ridge removed.
	var lookup := ShaderMaterial.new()
	lookup.shader = Shader.new()
	lookup.shader.code = """shader_type sky;
uniform sampler2D baked : filter_linear, repeat_enable;
void sky() {
 vec3 dir = normalize(EYEDIR);
 vec2 uv = vec2(atan(dir.x, dir.z) / 6.2831853 + 0.5, acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265);
 COLOR = pow(texture(baked, uv).rgb, vec3(2.2));
}"""
	lookup.set_shader_parameter("baked", reference_base.get_texture())
	var lookup_sky := Sky.new()
	lookup_sky.radiance_size = Sky.RADIANCE_SIZE_32
	lookup_sky.sky_material = lookup
	for size in [1440, 2048]:
		for view in views:
			view.size = Vector2i(size, size)
		await measure("dark", null)
		await measure("starry_night", background.sky)
		# Rule out a live ViewportTexture/radiance dependency as the steady-state cost.
		var static_material: ShaderMaterial = background.sky.sky_material.duplicate()
		static_material.set_shader_parameter(
			"baked", ImageTexture.create_from_image(background._cached_night.get_image())
		)
		var static_sky := Sky.new()
		static_sky.radiance_size = Sky.RADIANCE_SIZE_32
		static_sky.sky_material = static_material
		await measure("starry_static_base_texture", static_sky)
		await measure("no_star_layers", no_stars)
		await measure("baked_lookup_only", lookup_sky)
		await measure("starry_night_repeat", background.sky)
		for camera in cameras:
			camera.rotation.x = deg_to_rad(-45)
		await measure("starry_night_looking_down", background.sky)
		for camera in cameras:
			camera.rotation.x = deg_to_rad(25)
	var report := {
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"scope": "Two mono viewports; no video/UI/XR compositor. Zero GPU times mean unavailable.",
		"warmup_frames": 60,
		"sample_frames": 180,
		"vsync_requested": DisplayServer.VSYNC_DISABLED,
		"vsync_actual": DisplayServer.window_get_vsync_mode(),
		"msaa": "2x",
		"results": results,
	}
	var file := FileAccess.open(output.path_join("host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for view in views:
		view.queue_free()
	background.queue_free()
	quit()
