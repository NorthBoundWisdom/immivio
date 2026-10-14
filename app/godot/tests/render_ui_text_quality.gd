extends SceneTree
## Generated glyphs only. Compare scalable UI text against a large raster reference.
## Images exist only in memory for numeric comparison and are never saved.
const Menu := preload("res://scripts/ray_menu.gd")


func sample_alpha(image: Image, box: Rect2i, uv: Vector2) -> float:
	var point := Vector2(box.position) + uv * Vector2(box.size - Vector2i.ONE)
	var low := Vector2i(point.floor())
	var high := (low + Vector2i.ONE).min(image.get_size() - Vector2i.ONE)
	var part := point - Vector2(low)
	return lerpf(
		lerpf(image.get_pixel(low.x, low.y).a, image.get_pixel(high.x, low.y).a, part.x),
		lerpf(image.get_pixel(low.x, high.y).a, image.get_pixel(high.x, high.y).a, part.x),
		part.y
	)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .065
	camera.position.z = 1
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	viewport.add_child(camera)
	var legacy := SystemFont.new()
	legacy.font_names = Menu.ui_font().font_names
	legacy.fallbacks = [ThemeDB.fallback_font]
	var reference := SystemFont.new()
	reference.font_names = legacy.font_names
	reference.generate_mipmaps = true
	reference.hinting = TextServer.HINTING_NONE
	var label := Label3D.new()
	label.text = "播"
	label.outline_size = 0
	label.font_size = 20
	label.pixel_size = .0012
	viewport.add_child(label)
	var images: Array[Image] = []
	for mode in 3:
		label.font = [legacy, Menu.ui_font(), reference][mode]
		label.font_size = 160 if mode == 2 else 20
		label.pixel_size = .00015 if mode == 2 else .0012
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
	var errors := [0.0, 0.0]
	var coverage := [0.0, 0.0, 0.0]
	var bounds: Array[Rect2i] = []
	for image in images:
		var lo := Vector2i(256, 256)
		var hi := Vector2i.ZERO
		for y in 256:
			for x in 256:
				if image.get_pixel(x, y).a > .5:
					lo = lo.min(Vector2i(x, y))
					hi = hi.max(Vector2i(x, y))
		bounds.append(Rect2i(lo, hi - lo + Vector2i.ONE))
	# MSDF and hinted raster glyphs have different line metrics. Register their
	# ink bounds before comparing outline fidelity, not their line-box offsets.
	for y in 128:
		for x in 128:
			var uv := Vector2(x, y) / 127.0
			var values := [
				sample_alpha(images[0], bounds[0], uv),
				sample_alpha(images[1], bounds[1], uv),
				sample_alpha(images[2], bounds[2], uv)
			]
			for mode in 3:
				coverage[mode] += values[mode]
			for mode in 2:
				errors[mode] += absf(values[mode] - values[2])
	var passed: bool = coverage.min() > 100 and errors[1] < errors[0]
	var report := {
		"state": "passed" if passed else "failed",
		"source": "generated CJK glyph",
		"images_saved": false,
		"legacy_error": errors[0],
		"msdf_error": errors[1],
		"coverage": coverage
	}
	var output := OS.get_environment("THRU3D_TEXT_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	viewport.queue_free()
	if not passed:
		push_error("Scalable glyph did not improve reference fidelity")
	quit(0 if passed else 1)
