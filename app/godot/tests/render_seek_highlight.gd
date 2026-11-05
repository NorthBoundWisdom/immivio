extends SceneTree
## Verify fractional edge coverage without relying on MSAA to hide a clipped SDF.
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var samples: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position.z = 1
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	viewport.add_child(camera)
	var menu := Menu.new()
	menu.state_provider = func(): return {"has_video": true, "duration_ms": 60000, "position_ms": 30000}
	viewport.add_child(menu)
	menu.toggle()
	menu._hover.render = Menu.SEEK
	menu._update_highlights()
	var visual: MeshInstance3D
	for button in menu._buttons:
		if button.target == Menu.SEEK:
			visual = button.node.duplicate()
	menu.visible = false
	viewport.add_child(visual)
	visual.position = Vector3.ZERO
	for size in [.06, .12]:
		camera.size = size
		for tilt in [0.0, .45]:
			visual.rotation.y = tilt
			var edge: Vector3 = visual.to_global(Vector3(visual.mesh.size.x / 2, 0, 0))
			var pixel_metres: float = size / viewport.size.y
			camera.position.x = edge.x - pixel_metres * .25
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var boundary := camera.unproject_position(edge)
			var x := ceili(boundary.x - .5)
			var y := roundi(boundary.y)
			var inside := image.get_pixel(x - 1, y).a
			var outside := image.get_pixel(x, y).a
			var clear := image.get_pixel(x + 2, y).a
			samples.append({"view_height": size, "tilt": tilt, "inside": inside, "outside": outside, "clear": clear})
			if inside <= .5 or outside <= .03 or outside >= .6 or clear >= .02:
				failures.append("Highlight edge must retain fractional coverage outside its logical boundary: " + str(samples.back()))
			var output := OS.get_environment("IMMIVIO_HIGHLIGHT_DIR")
			if not output.is_empty():
				DirAccess.make_dir_recursive_absolute(output)
				image.save_png(output.path_join("edge-%s-%s.png" % [size, tilt]))
	print(JSON.stringify({"state": "passed" if failures.is_empty() else "failed", "msaa": "disabled", "samples": samples}))
	for failure in failures:
		push_error(failure)
	viewport.queue_free()
	quit(0 if failures.is_empty() else 1)
