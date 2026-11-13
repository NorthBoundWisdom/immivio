extends SceneTree
## Real GPU regression: neither switching menus nor expanding a page may expose
## the preceding texture on the new curved surface. Synthetic solid colours only.
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Menu := preload("res://scripts/ray_menu.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func pixels(image: Image, channel: int) -> int:
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var colour := image.get_pixel(x, y)
			if (
				colour[channel] > .5
				and colour[(channel + 1) % 3] < .2
				and colour[(channel + 2) % 3] < .2
			):
				count += 1
	return count


func _run() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(480, 360)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var head := Camera3D.new()
	target.add_child(head)
	head.current = true
	head.environment = Environment.new()
	head.environment.background_mode = Environment.BG_COLOR
	head.environment.background_color = Color.BLACK
	var first := Menu.new()
	var second := Menu.new()
	for menu in [first, second]:
		target.add_child(menu)
		menu.position = Vector3(0, 0, -1.6)
		menu.curve_radius = 1.6
	first.backdrop_snapshot().material_override.set_shader_parameter("surface_color", Color.RED)
	second._set_backdrop(Vector2(.8, .7))
	second.backdrop_snapshot().material_override.set_shader_parameter("surface_color", Color.GREEN)
	first.visible = true
	var surface := Surface.new()
	target.add_child(surface)
	surface.configure([first, second], head, false)
	surface.set_process(false)
	for i in 4:
		surface.test_step(0)
		await process_frame
		await RenderingServer.frame_post_draw
	var initial := target.get_texture().get_image()
	if pixels(initial, 0) < 100:
		failures.append("Initial curved menu must actually render red pixels")
	first.visible = false
	second.visible = true
	second.position.x = .2
	surface.test_step(0)
	if surface.curved_mesh.visible:
		failures.append("Switching to the library must hide the preceding capture")
	await RenderingServer.frame_post_draw
	var switched := target.get_texture().get_image()
	if pixels(switched, 0) > 0:
		failures.append("First library frame exposed the previous red page")
	for i in 3:
		surface.test_step(0)
		await process_frame
		await RenderingServer.frame_post_draw
	if pixels(target.get_texture().get_image(), 1) < 100:
		failures.append("New library page must reveal its own green capture")
	second._clear_layout()
	second._set_backdrop(Vector2(1.4, 1.1))
	second.backdrop_snapshot().material_override.set_shader_parameter("surface_color", Color.BLUE)
	surface.test_step(0)
	if surface.curved_mesh.visible:
		failures.append("Expanding subtitles must hide the previous capture")
	await RenderingServer.frame_post_draw
	var expanded := target.get_texture().get_image()
	if pixels(expanded, 1) > 0:
		failures.append("First expanded frame exposed the previous green page")
	for i in 3:
		surface.test_step(0)
		await process_frame
		await RenderingServer.frame_post_draw
	if pixels(target.get_texture().get_image(), 2) < 100:
		failures.append("Expanded subtitle page must reveal its own blue capture")
	var output := OS.get_environment("IMMIVIO_TRANSITIONS_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		initial.save_png(output.path_join("initial.png"))
		switched.save_png(output.path_join("first-library-frame.png"))
		expanded.save_png(output.path_join("first-subtitle-frame.png"))
		target.get_texture().get_image().save_png(output.path_join("subtitles.png"))
	print(
		JSON.stringify(
			{
				"state": "passed" if failures.is_empty() else "failed",
				"failures": failures,
				"scope":
				"GPU curved UI capture transitions; synthetic pixels; no native headset layer"
			}
		)
	)
	target.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
