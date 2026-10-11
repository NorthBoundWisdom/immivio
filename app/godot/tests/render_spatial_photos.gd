extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var output := ProjectSettings.globalize_path("res://../../build/output/spatial-photos/render")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: call_deferred("_run")

func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func white_centre(image: Image) -> float:
	var total := 0.0; var count := 0
	for x in image.get_width():
		var pixel := image.get_pixel(x,250)
		if minf(pixel.r,minf(pixel.g,pixel.b)) > .8: total += x; count += 1
	return total / maxi(1,count)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new(); viewport.size = Vector2i(800,500)
	viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color.BLUE; viewport.add_child(world)
	var camera := Camera3D.new(); camera.position = Vector3(0,1.6,0); camera.fov = 70; viewport.add_child(camera)
	var photo := Photo.new(); viewport.add_child(photo); photo.set_process(false)
	photo.view_camera = camera; photo.flat_pose = Transform3D(Basis.IDENTITY,Vector3(0,1.6,-2))
	photo.screen_curve = 0; photo.screen_scale = .6
	photo.queue.assign([{"uri":"file://native.heic","title":"native.heic"}])
	var pair := Image.create(400,100,false,Image.FORMAT_RGBA8)
	pair.fill(Color.RED); pair.fill_rect(Rect2i(200,0,200,100),Color.GREEN)
	photo._accept({"image":pair,"thumbnail":pair,"info":{"native_stereo":true,"spatial_disparity":0}}, {"id":1,"index":0})
	photo.finish_transition()
	for eye in 2:
		photo.material.set_shader_parameter("test_eye",eye)
		var rendered: Image = await frame(); rendered.save_png(output.path_join("native-eye-%d.png" % eye))
		var colour := rendered.get_pixel(400,250)
		check(colour.r > .95 if eye == 0 else colour.g > .95, "Each native eye receives its matching view")
	photo.toggle_eye_order()
	for eye in 2:
		photo.material.set_shader_parameter("test_eye",eye)
		var rendered: Image = await frame(); var colour := rendered.get_pixel(400,250)
		check(colour.g > .95 if eye == 0 else colour.r > .95, "Native eye swap reverses the displayed views")
	photo.toggle_eye_order()
	pair.fill(Color.BLACK)
	pair.fill_rect(Rect2i(94,0,12,100),Color.WHITE); pair.fill_rect(Rect2i(294,0,12,100),Color.WHITE)
	photo._texture.update(pair)
	var neutral: Array[float] = []
	for eye in 2:
		photo.material.set_shader_parameter("test_eye",eye); neutral.append(white_centre(await frame()))
	photo._metadata["spatial_disparity"] = .04; photo._apply_geometry()
	for eye in 2:
		photo.material.set_shader_parameter("test_eye",eye)
		var rendered: Image = await frame(); rendered.save_png(output.path_join("disparity-eye-%d.png" % eye))
		var centre := white_centre(rendered)
		check(centre < neutral[eye]-5 if eye == 0 else centre > neutral[eye]+5,
			"Positive Apple disparity shifts left content left and right content right")
	photo.free(); viewport.free()
	for failure in failures: push_error(failure)
	print("Spatial photo render: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
