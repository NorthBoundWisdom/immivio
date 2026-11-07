extends SceneTree
## A real perspective render must place the near/far portions of a beam at different stereo
## disparities. The independent UI capture may change only around the reticle.
const Menu := preload("res://scripts/ray_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Stereo := preload("res://scripts/xr_pointer_compositor.gd")
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


func alpha_near(image: Image, point: Vector2) -> float:
	var alpha := 0.0
	for y in range(roundi(point.y) - 3, roundi(point.y) + 4):
		for x in range(roundi(point.x) - 3, roundi(point.x) + 4):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				alpha = maxf(alpha, image.get_pixel(x, y).a)
	return alpha


func _run() -> void:
	var main := SubViewport.new()
	main.size = Vector2i(640, 640)
	main.own_world_3d = true
	main.transparent_bg = true
	root.add_child(main)
	var head := Camera3D.new()
	main.add_child(head)
	head.position.z = 1.5
	var menu := Menu.new()
	main.add_child(menu)
	menu.position = Vector3.ZERO
	menu.visible = true
	var origin := Vector3(.15, -.2, 1.1)
	var target := Vector3(0, .05, 0)
	menu.update_pointer("right_hand", origin, target - origin, true)
	var pointer: Dictionary = menu._pointers.right_hand
	var surface := Surface.new()
	main.add_child(surface)
	surface.native_supported = true
	surface.active_menu = menu
	surface.menus = [menu]
	surface._tag_tree(menu)
	var stereo := Stereo.new()
	main.add_child(stereo)
	stereo.configure(head)
	var projection := Projection.create_frustum(-.02, .02, -.02, .02, Stereo.NEAR, Stereo.FAR)
	var near_point := origin.lerp(target + Vector3(0, 0, .006), .15)
	var far_point := origin.lerp(target + Vector3(0, 0, .006), .75)
	var near_pixels: Array[Vector2] = []
	var far_pixels: Array[Vector2] = []
	for eye in 2:
		var pose := Transform3D(Basis.IDENTITY, Vector3(-.032 if eye == 0 else .032, 0, 1.5))
		stereo.update_eye(eye, pose, projection)
		near_pixels.append(stereo.cameras[eye].unproject_position(near_point))
		far_pixels.append(stereo.cameras[eye].unproject_position(far_point))
	await frame()
	for eye in 2:
		var image := stereo.views[eye].get_texture().get_image()
		var near_alpha := alpha_near(image, near_pixels[eye])
		var far_alpha := alpha_near(image, far_pixels[eye])
		check(near_alpha > .1, "Eye %d sees the near 3D beam" % eye)
		check(far_alpha > .005, "Eye %d still sees the fading far 3D beam" % eye)
		check(
			near_alpha < .5 and far_alpha < near_alpha * .5,
			"The beam is translucent and fades toward the panel"
		)
	var near_disparity := absf(near_pixels[0].x - near_pixels[1].x)
	var far_disparity := absf(far_pixels[0].x - far_pixels[1].x)
	check(
		near_disparity > far_disparity * 1.5,
		"Near beam has greater stereo disparity than the panel endpoint"
	)
	var ui := SubViewport.new()
	ui.size = Vector2i(640, 640)
	ui.world_3d = head.get_world_3d()
	ui.transparent_bg = true
	ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(ui)
	var camera := Camera3D.new()
	ui.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.5
	camera.position.z = 1.5
	camera.cull_mask = Surface.UI_LAYER
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.TRANSPARENT
	camera.current = true
	pointer.dot.visible = false
	await frame()
	var baseline := ui.get_texture().get_image()
	pointer.dot.visible = true
	await frame()
	var reticle := ui.get_texture().get_image()
	var centre := camera.unproject_position(menu.to_global(pointer.dot.position))
	var changed := 0
	var outside := 0
	for y in reticle.get_height():
		for x in reticle.get_width():
			var before := baseline.get_pixel(x, y)
			var after := reticle.get_pixel(x, y)
			if (
				Vector3(before.r, before.g, before.b).distance_to(
					Vector3(after.r, after.g, after.b)
				)
				> .03
			):
				changed += 1
				if Vector2(x, y).distance_to(centre) > 12:
					outside += 1
	check(
		changed > 4 and outside == 0,
		"The UI capture contains the reticle, without a projected beam"
	)
	print(
		(
			"Stereo GPU: near disparity=%.2f far disparity=%.2f reticle=%d outside=%d"
			% [near_disparity, far_disparity, changed, outside]
		)
	)
	ui.queue_free()
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Stereo pointer GPU: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
