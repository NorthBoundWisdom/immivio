extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var output := ProjectSettings.globalize_path("res://../../build/output/photo-portrait/render")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("_run")
func frame(name: String) -> Image:
	await process_frame; await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image(); result.save_png(output.path_join(name+".png")); return result
func centre(image: Image,eye: int) -> float:
	var sum := 0.0; var count := 0
	for x in image.get_width():
		var pixel := image.get_pixel(x,150)
		if (pixel.r > 0.8 if eye == 0 else pixel.g > 0.8): sum += x; count += 1
	return sum/maxi(1,count)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new(); viewport.size = Vector2i(600,300); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world := WorldEnvironment.new(); world.environment = Environment.new(); world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLUE; viewport.add_child(world)
	var camera := Camera3D.new(); camera.position = Vector3(0,1.6,0); camera.fov = 70; viewport.add_child(camera)
	var photo := Photo.new(); viewport.add_child(photo); photo.set_process(false); photo.gallery.set_process(false)
	photo.flat_pose.origin = Vector3(0,1.6,-2); photo.screen_curve = 0; photo.screen_scale = 0.5
	var color := Image.create(256,128,false,Image.FORMAT_RGBA8); color.fill(Color.RED)
	var pair := Image.create(512,128,false,Image.FORMAT_RGBA8); pair.fill(Color.RED); pair.fill_rect(Rect2i(256,0,256,128),Color.GREEN)
	var near := Image.create(518,518,false,Image.FORMAT_RF); near.fill(Color(0.8,0,0))
	photo.auto_depth = true; photo.queue.assign([{"uri":"file://portrait.png","title":"portrait.png"}])
	photo._accept({"image":color,"thumbnail":color,"info":{},"depth_data":{"image":near,"rect":Vector4(0,0,1,1),"stereo_image":pair}}, {"id":1,"index":0})
	photo.finish_transition()
	var mask := Image.create(512,128,false,Image.FORMAT_R8); mask.fill(Color.BLACK)
	mask.fill_rect(Rect2i(72,16,88,112),Color.WHITE); mask.fill_rect(Rect2i(256+96,16,88,112),Color.WHITE)
	photo._portrait_texture = ImageTexture.create_from_image(mask); photo.portrait_enabled = true; photo._apply_geometry()
	var positions := []
	for eye in 2:
		photo.material.set_shader_parameter("test_eye",eye)
		var rendered: Image = await frame("portrait-eye-%d" % eye)
		check(rendered.get_pixel(230,150).b > 0.8, "Cutout reveals the environment outside the subject")
		positions.append(centre(rendered,eye))
		check(positions.back()>230 and positions.back()<380, "Each eye keeps its own coloured foreground")
	check(positions[1] > positions[0]+15, "Per-eye mask disparity is preserved instead of sharing one flat silhouette")
	photo.material.set_shader_parameter("target_state",2)
	var targeted: Image = await frame("portrait-targeted")
	check(targeted.get_pixel(230,150).b > 0.8, "Selection feedback cannot add an opaque photo rectangle around a portrait")
	photo.portrait_enabled = false; photo._apply_geometry(); photo.material.set_shader_parameter("target_state",0)
	var restored: Image = await frame("portrait-off")
	check(restored.get_pixel(230,150).g > 0.8, "Turning portrait off restores complete stereo colour")
	photo.free(); viewport.free()
	for failure in failures: push_error(failure)
	print("Photo portrait render: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
