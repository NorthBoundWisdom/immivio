extends SceneTree
## Real GPU checks of subtitle compositing and the rectified stereo probe.
const Canvas := preload("res://scripts/flat_subtitle_canvas.gd")
const Focus := preload("res://scripts/stereo_focus.gd")
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		call_deferred("run")


func run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(512, 256)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.5
	camera.position.z = 2.0
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	view.add_child(camera)
	var owner := Node3D.new()
	view.add_child(owner)
	var label := Label3D.new()
	label.text = "Subtitle fill\n双语字幕"
	label.font_size = 48
	label.outline_size = 10
	label.width = 550
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	owner.add_child(label)
	var canvas := Canvas.new()
	owner.add_child(canvas)
	for i in 8:
		canvas.request(label)
		await RenderingServer.frame_post_draw
	var opaque: Image = canvas.viewport.get_texture().get_image()
	label.modulate.a = 0.5
	label.outline_modulate.a = 0.5
	for i in 8:
		canvas.request(label)
		await RenderingServer.frame_post_draw
	var faded: Image = canvas.viewport.get_texture().get_image()
	var pixels := 0
	var wrong := 0
	check(opaque.get_size() == faded.get_size(), "Opacity preserves caption raster geometry")
	for y in opaque.get_height():
		for x in opaque.get_width():
			var a := opaque.get_pixel(x, y)
			if a.a > 0.9:
				pixels += 1
				var b := faded.get_pixel(x, y)
				if absf(b.a - a.a * 0.5) > 0.015:
					wrong += 1
	check(pixels > 1000 and wrong == 0, "Fill and outline fade together after compositing")
	var folder := "res://../../artifacts/captures/upstream-playback"
	DirAccess.make_dir_recursive_absolute(folder)
	opaque.save_png(folder.path_join("caption-opaque.png"))
	faded.save_png(folder.path_join("caption-half.png"))
	# The production eye-buffer quad must compile with premultiplied blending.
	var quad := preload("res://scripts/faded_caption.gd").new()
	label.add_child(quad)
	check(quad.show_caption(label, canvas), "Faded world-space caption is ready")
	label.layers = 0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var drawn: Image = view.get_texture().get_image()
	var solid := 0
	for y in drawn.get_height():
		for x in drawn.get_width():
			if drawn.get_pixel(x, y).a > 0.49 and drawn.get_pixel(x, y).a < 0.52:
				solid += 1
	check(solid > 500, "Production world-space caption shader draws half-opacity glyphs")

	for geometry in [1, 3]:
		var eye := Image.create(512, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 512:
				var value := (
					0.5
					+ 0.16 * sin(x * 0.31 + y * 0.25)
					+ 0.17 * sin(x * 0.63 - y * 0.17)
					+ 0.12 * sin(x * 0.53 + y * 0.77)
				)
				eye.set_pixel(x, y, Color(value, value, value))
		var shift := 8 if geometry == 1 else 4
		for stacked in [false, true]:
			var packed := Image.create(
				512 if stacked else 1024, 512 if stacked else 256, false, Image.FORMAT_RGB8
			)
			packed.blit_rect(eye, Rect2i(0, 0, 512, 256), Vector2i.ZERO)
			for y in 256:
				for x in 512:
					packed.set_pixel(
						x if stacked else x + 512,
						y + 256 if stacked else y,
						eye.get_pixel((x + shift) % 512, y)
					)
			var texture := ImageTexture.create_from_image(packed)
			var sample: Image = await Focus.capture(
				owner,
				texture.get_rid(),
				{
					"source_size": Vector2(packed.get_size()),
					"geometry": geometry,
					"top_bottom": stacked,
					"gaze": Vector2.ZERO
				}
			)
			var measured := Focus.measure(sample)
			print("GPU focus geometry=", geometry, " stacked=", stacked, " ", measured)
			check(
				measured.valid and absf(measured.degrees - 2.8125) < 0.4,
				"Rectified GPU probe retains stereo disparity for both packings"
			)
			sample.save_png(folder.path_join("focus-%d-%s.png" % [geometry, str(stacked)]))
	for half in [false, true]:
		var width := 256 if half else 512
		for stacked in [false, true]:
			var packed := Image.create(
				width if stacked else width * 2, 1024 if stacked else 512, false, Image.FORMAT_RGB8
			)
			for eye_index in 2:
				for y in 512:
					for x in width:
						var axis := (
							Vector2((float(x) + 0.5) / width - 0.5, (float(y) + 0.5) / 512 - 0.5)
							* 2.0
						)
						var theta := axis.length() * PI * 0.5
						var direction := Vector3(
							axis.normalized().x * sin(theta),
							-axis.normalized().y * sin(theta),
							-cos(theta)
						)
						var longitude := (
							atan2(direction.x, -direction.z) + deg_to_rad(2.8125) * eye_index
						)
						var latitude := asin(clampf(direction.y, -1, 1))
						var value := (
							0.5
							+ 0.16 * sin(longitude * 50 + latitude * 32)
							+ 0.17 * sin(longitude * 102 - latitude * 28)
							+ 0.12 * sin(longitude * 85 + latitude * 125)
						)
						packed.set_pixel(
							x if stacked else x + width * eye_index,
							y + 512 * eye_index if stacked else y,
							Color(value, value, value)
						)
			var texture := ImageTexture.create_from_image(packed)
			var sample: Image = await Focus.capture(
				owner,
				texture.get_rid(),
				{
					"source_size": Vector2(packed.get_size()),
					"geometry": 2,
					"top_bottom": stacked,
					"stereo_half": half,
					"gaze": Vector2(0.2, 0.1)
				}
			)
			var measured := Focus.measure(sample)
			print("GPU fisheye half=", half, " stacked=", stacked, " ", measured)
			check(
				measured.valid and absf(measured.degrees - 2.8125) < 0.4,
				"GPU fisheye rectification preserves disparity in full/half SBS/TB"
			)
	view.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Upstream GPU failures: ", failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
