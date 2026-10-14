extends SceneTree
## Generated solid geometry only. Numeric edge coverage, no media or saved images.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	camera.position.z = 2
	viewport.add_child(camera)
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(1.4, .8)
	quad.rotation.z = .037
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	quad.material_override = material
	viewport.add_child(quad)
	var cases := []
	for mode in [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]:
		viewport.msaa_3d = mode
		var coverage: Array[float] = []
		var partial := 0
		for step in 8:
			quad.position.x = float(step) / 8.0 / 96.0
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var area := 0.0
			for y in image.get_height():
				for x in image.get_width():
					var value := image.get_pixel(x, y).r
					area += value
					if value > .01 and value < .99:
						partial += 1
			coverage.append(area)
		cases.append(
			{
				"msaa": mode,
				"partial_edge_samples": partial,
				"area_variation": coverage.max() - coverage.min()
			}
		)
	var passed := true
	for index in [1, 2]:
		passed = (
			passed
			and cases[index].partial_edge_samples > cases[0].partial_edge_samples
			and cases[index].area_variation < cases[0].area_variation
		)
	var report := {
		"state": "passed" if passed else "failed",
		"source": "generated solid quad",
		"images_saved": false,
		"cases": cases
	}
	var output := OS.get_environment("THRU3D_MSAA_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	viewport.queue_free()
	if not passed:
		push_error("MSAA did not improve generated geometry edge coverage/stability")
	quit(0 if passed else 1)
