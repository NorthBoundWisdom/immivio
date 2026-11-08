extends SceneTree
## Exercise the rounded thumbnail/cover material with independently known RGBA pixels.
const Menu := preload("res://scripts/library_menu.gd")
var failures: Array[String] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(256, 256)
	target.own_world_3d = true
	target.transparent_bg = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	camera.position.z = 1
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	target.add_child(camera)
	camera.current = true
	var menu := Menu.new()
	target.add_child(menu)
	menu.set_process(false)
	menu.visible = false
	var pixels := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(1, 1, 1, 0))
	pixels.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)
	pixels.fill_rect(Rect2i(16, 0, 16, 16), Color.GREEN)
	pixels.fill_rect(Rect2i(0, 16, 16, 16), Color.BLUE)
	var area := menu._quad(Vector2(.8, .8), Vector3.ZERO, Color.WHITE, 12)
	area.material_override.set_shader_parameter("corner_radius", .12)
	menu._show_picture(area, ImageTexture.create_from_image(pixels))
	target.add_child(area)
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture := target.get_texture().get_image()
	if (
		picture.get_pixel(80, 80).r < .9
		or picture.get_pixel(176, 80).g < .9
		or picture.get_pixel(80, 176).b < .9
	):
		failures.append(
			"Picture colours and vertical orientation must survive the rounded material"
		)
	if picture.get_pixel(176, 176).a > .01:
		failures.append("A transparent image region must remain transparent")
	if picture.get_pixel(30, 30).a > .01:
		failures.append("The rounded corner must clip an opaque image region")
	for failure in failures:
		push_error(failure)
	print("Rounded menu pictures: %d failures" % failures.size())
	target.queue_free()
	await process_frame
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
