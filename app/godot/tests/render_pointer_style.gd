extends SceneTree
## Check the production beam with MSAA disabled: thin coverage, fractional edge alpha and a
## fading body must survive different pixel densities and angles.
const Ray := preload("res://scripts/pointer_ray.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func alpha(image: Image, point: Vector2) -> float:
	var p := Vector2i(point.floor())
	var f := point - Vector2(p)
	return lerpf(
		lerpf(image.get_pixel(p.x, p.y).a, image.get_pixel(p.x + 1, p.y).a, f.x),
		lerpf(image.get_pixel(p.x, p.y + 1).a, image.get_pixel(p.x + 1, p.y + 1).a, f.x),
		f.y
	)


func peak(image: Image, point: Vector2) -> float:
	var value := 0.0
	for y in range(roundi(point.y) - 2, roundi(point.y) + 3):
		for x in range(roundi(point.x) - 2, roundi(point.x) + 3):
			value = maxf(value, image.get_pixel(x, y).a)
	return value


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 1
	camera.current = true
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.TRANSPARENT
	var line := Ray.create(Color(1, 1, 1, Ray.IDLE_OPACITY), 14)
	viewport.add_child(line)
	line.visible = true
	var output := OS.get_environment("IMMIVIO_RAY_STYLE_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	for size in [640, 1280]:
		viewport.size = Vector2i(size, size)
		for angle in [0.0, .35, .8, 1.3]:
			var extent := Vector3(cos(angle), sin(angle), 0) * .6
			Ray.draw(line, -extent, extent)
			await frame()
			var image := viewport.get_texture().get_image()
			var first := camera.unproject_position(-extent)
			var last := camera.unproject_position(extent)
			var centre := first.lerp(last, .5)
			var along := (last - first).normalized()
			var side := Vector2(-along.y, along.x)
			var body_alpha := Ray.IDLE_OPACITY * (1.0 - smoothstep(.05, 1.0, .5))
			var area := 0.0
			for sample in range(-32, 33):
				area += alpha(image, centre + side * sample * .125) * .125
			var width := area / body_alpha
			var fractional := 0
			for y in range(roundi(centre.y) - 5, roundi(centre.y) + 6):
				for x in range(roundi(centre.x) - 5, roundi(centre.x) + 6):
					var coverage := image.get_pixel(x, y).a / body_alpha
					if coverage > .05 and coverage < .95:
						fractional += 1
			var near_alpha := peak(image, first.lerp(last, .15))
			var far_alpha := peak(image, first.lerp(last, .75))
			var name := "%dpx angle=%.2f" % [size, angle]
			check(width > .25 and width < 1.6, name + ": thin stroke remains visible")
			check(fractional >= 4, name + ": edges contain fractional coverage without MSAA")
			check(
				near_alpha < .5 and near_alpha > far_alpha * 2 and far_alpha > .003,
				name + ": translucent beam fades toward its endpoint"
			)
			print(
				(
					"%s width=%.3f edge_pixels=%d near=%.3f far=%.3f"
					% [name, width, fractional, near_alpha, far_alpha]
				)
			)
			if not output.is_empty():
				image.save_png(
					output.path_join("beam-%d-%03d.png" % [size, roundi(rad_to_deg(angle))])
				)
				viewport.transparent_bg = false
				camera.environment.background_color = Color(.025, .035, .05)
				await frame()
				viewport.get_texture().get_image().save_png(
					output.path_join("preview-%d-%03d.png" % [size, roundi(rad_to_deg(angle))])
				)
				viewport.transparent_bg = true
				camera.environment.background_color = Color.TRANSPARENT
	viewport.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Pointer style GPU: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
