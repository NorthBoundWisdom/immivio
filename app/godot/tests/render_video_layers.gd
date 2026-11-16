extends SceneTree
const Display := preload("res://scripts/xr_display.gd")
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		call_deferred("run")


func settle() -> void:
	for i in 4:
		await RenderingServer.frame_post_draw


func run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	camera.position.y = 1.6
	camera.rotation = Vector3(-0.1, 0.35, 0)
	camera.far = 2000
	view.add_child(camera)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	view.add_child(world)
	var display := Display.new()
	display.attach_video_backdrop(camera)
	display.configure(view, world.environment, null, true)
	var image := Image.create(128, 64, false, Image.FORMAT_RGBF)
	for y in 64:
		for x in 128:
			image.set_pixel(x, y, Color(0.1 + float(x) / 128 * 0.3, 0.1 + float(y) / 64 * 0.3, 0.2))
	var texture := ImageTexture.create_from_image(image)
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = texture
	var night := ShaderMaterial.new()
	night.shader = preload("res://shaders/cached_starry_sky.gdshader")
	night.set_shader_parameter("baked", texture)
	var clouds := ShaderMaterial.new()
	clouds.shader = preload("res://shaders/procedural_sky.gdshader")
	clouds.set_shader_parameter("baked", texture)
	clouds.set_shader_parameter("scene", 2)
	var out := "res://../../artifacts/captures/player-performance"
	DirAccess.make_dir_recursive_absolute(out)
	var index := 0
	for material in [panorama, night, clouds]:
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.sky_material = material
		display.set_video_layer(false)
		display.set_scenery(sky, 20)
		await settle()
		var before: Image = view.get_texture().get_image()
		display.set_video_layer(true)
		await settle()
		var after: Image = view.get_texture().get_image()
		var difference := 0.0
		for y in 256:
			for x in 256:
				var a := before.get_pixel(x, y)
				var b := after.get_pixel(x, y)
				difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		difference /= 256 * 256 * 3
		print("Backdrop scene ", index, " RGB mean difference ", difference)
		check(difference < 0.015, "Scenery stays aligned when video moves to the compositor")
		before.save_png(out.path_join("sky-%d.png" % index))
		after.save_png(out.path_join("backdrop-%d.png" % index))
		index += 1
	var hole := MeshInstance3D.new()
	hole.mesh = QuadMesh.new()
	hole.mesh.size = Vector2(0.6, 0.6)
	hole.material_override = ShaderMaterial.new()
	hole.material_override.shader = preload("res://shaders/video_layer_hole.gdshader")
	hole.material_override.render_priority = -20
	view.add_child(hole)
	hole.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -2))
	await settle()
	var cleared: Image = view.get_texture().get_image()
	check(
		cleared.get_pixel(128, 128).a < 0.01 and cleared.get_pixel(10, 10).a > 0.99,
		"The video footprint clears alpha without erasing scenery"
	)
	var foreground := MeshInstance3D.new()
	foreground.mesh = QuadMesh.new()
	foreground.mesh.size = Vector2(0.1, 0.1)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color.RED
	foreground.material_override = ink
	view.add_child(foreground)
	foreground.global_transform = (
		camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -1))
	)
	await settle()
	var drawn: Image = view.get_texture().get_image()
	check(
		drawn.get_pixel(128, 128).r > 0.95 and drawn.get_pixel(128, 128).a > 0.99,
		"Foreground geometry remains in front of the video hole"
	)
	drawn.save_png(out.path_join("foreground-and-hole.png"))
	display.set_video_layer(false)
	check(display.backdrop_material == null, "Inactive backdrops release copied texture references")
	view.queue_free()
	await process_frame
	for error in failures:
		push_error(error)
	print("Video layer GPU failures: ", failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
