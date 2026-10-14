extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
const Menu := preload("res://scripts/photo_menu.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
var viewport: SubViewport
var photo: Node3D
var camera: Camera3D
var checks := 0
var failures: Array[String] = []
var output := ProjectSettings.globalize_path("res://../../build/output/photo-layouts/render")
var entries: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func frame(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.save_png(output.path_join(name + ".png"))
	return result


func previews() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		photo.gallery._process(0.02)
		if photo.gallery.cards.keys().all(
			func(index): return photo.gallery.previews.texture(str(entries[index].uri)) != null
		):
			break
		await create_timer(0.01).timeout
	check(
		photo.gallery.cards.keys().all(
			func(index): return photo.gallery.previews.texture(str(entries[index].uri)) != null
		),
		"Rendered layouts have actual preview content"
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for i in 64:
		var size := (
			Vector2i(320, 180)
			if i % 3 == 0
			else (Vector2i(150, 230) if i % 3 == 1 else Vector2i(220, 220))
		)
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
		image.fill(Color.from_hsv(i / 64.0, 0.65, 0.8))
		image.fill_rect(Rect2i(0, 0, size.x / 4, size.y), Color(0.9, 0.15, 0.1))
		image.fill_rect(Rect2i(size.x * 3 / 4, 0, size.x / 4, size.y), Color(0.1, 0.3, 0.9))
		image.fill_rect(
			Rect2i(size.x / 3, size.y / 3, size.x / 3, size.y / 3), Color(0.9, 0.9, 0.8)
		)
		var path := output.path_join("source-%02d.png" % i)
		image.save_png(path)
		entries.append({"uri": "file://" + path, "title": "%02d.png" % i, "kind": "image"})
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.012, 0.025, 0.035)
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = 70
	viewport.add_child(camera)
	photo = Photo.new()
	photo.history_enabled = false
	photo.mode_memory = Memory.new("user://layout_render_modes")
	viewport.add_child(photo)
	photo.view_camera = camera
	photo.flat_pose.origin = Vector3(0, 1.6, -3)
	photo.open_image(str(entries[0].uri), "00.png", entries)
	var deadline := Time.get_ticks_msec() + 5000
	while photo.loading and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(
		photo.error.is_empty() and not photo.loading,
		"Render fixture loads through production photo path"
	)
	photo.finish_transition()
	photo.gallery.set_process(false)
	var single: Image = await frame("01-single")
	check(single.get_pixel(640, 360).r > 0.5, "Single photo remains visible")
	photo.set_target_feedback(1)
	var target_single: Image = await frame("01b-single-targeted")
	check(
		target_single.get_data() != single.get_data(), "Full photo has a clear edge when targeted"
	)
	photo.set_target_feedback(0)
	photo.set_layout_mode(1)
	await previews()
	var sides: Image = await frame("02-sides")
	check(
		sides.get_data() != single.get_data(),
		"Side layout draws previews around the same central photo"
	)
	photo.set_screen_scale(3)
	await previews()
	var enlarged: Image = await frame("02b-sides-enlarged")
	check(
		photo.gallery.cards.values().all(func(card): return card.node.visible),
		"Enlarged hero retains all rendered thumbnails"
	)
	photo.set_screen_scale(1)
	photo.set_layout_mode(2)
	await previews()
	var wall: Image = await frame("03-wall")
	check(wall.get_data() != sides.get_data(), "Wall is visually distinct from side previews")
	photo.gallery.set_view_scale(1.6)
	await previews()
	await frame("04-wall-large")
	photo.gallery.set_view_scale(1)
	photo.set_layout_mode(3)
	await previews()
	var memories: Image = await frame("05-fragments")
	check(
		memories.get_data() != wall.get_data(),
		"Memory view renders different silhouettes and upper-space positions"
	)
	var first: Dictionary = photo.gallery.cards[0]
	var ray_origin := camera.global_position + Vector3(-0.2, -0.25, 0)
	photo.gallery.update_pointer(
		"left_hand", ray_origin, (first.pose.origin - ray_origin).normalized()
	)
	var pointed: Image = await frame("05b-fragment-targeted")
	check(
		pointed.get_data() != memories.get_data() and photo.gallery._pointers.left_hand.dot.visible,
		"Targeted fragment renders a traced rim and pointer endpoint"
	)
	photo.gallery.cancel_pointer("left_hand")
	photo.gallery._refresh_visibility()
	var polygon := PackedVector2Array(first.shape)
	var corner := Vector2.ZERO
	for point in [
		Vector2(-0.48, 0.48), Vector2(0.48, 0.48), Vector2(0.48, -0.48), Vector2(-0.48, -0.48)
	]:
		if not Geometry2D.is_point_in_polygon(point, polygon):
			corner = point
			break
	check(corner != Vector2.ZERO, "Fixture probes an actual missing corner of the fragment")
	# Isolate the silhouette probe so another randomized background memory cannot cover it.
	for index in photo.gallery.cards:
		if index == 0:
			continue
		var card: Dictionary = photo.gallery.cards[index]
		card.node.visible = false
		card.rim.visible = false
		card.echo.visible = false
	var isolated: Image = await frame("05c-fragment-silhouette")
	var pixel: Vector2 = camera.unproject_position(
		first.pose * Vector3(corner.x * first.size.x, corner.y * first.size.y, 0)
	)
	if Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(pixel):
		var color := isolated.get_pixelv(Vector2i(pixel))
		check(
			maxf(color.r, maxf(color.g, color.b)) < 0.25,
			"Fragment mesh leaves its clipped corner as background"
		)
	photo.gallery._refresh_visibility()
	photo.gallery.activate(0)
	photo.gallery._process(0.17)
	await frame("06-fragment-opening")
	photo.gallery._process(1.0)
	var opened: Image = await frame("07-fragment-complete")
	check(
		photo.panel.visible and opened.get_pixel(640, 360).r > 0.5,
		"Open fragment exposes the full photo at eye height"
	)
	photo.gallery.return_focus()
	photo.gallery._process(0.17)
	await frame("08-fragment-returning")
	photo.gallery._process(1.0)
	var returned: Image = await frame("09-fragments-restored")
	check(
		returned.get_data() == memories.get_data(),
		"Return restores the exact rendered scene, including crop and other fragments"
	)
	check(photo.gallery.shuffle_fragments(), "Rendered memory batch can be exchanged")
	photo.gallery._process(0.11)
	var fading: Image = await frame("09b-fragments-fading")
	check(
		fading.get_data() != returned.get_data(),
		"Memory swap has a visible disappearance transition"
	)
	photo.gallery._process(0.12)
	await previews()
	photo.gallery._process(0.15)
	await frame("09c-fragments-appearing")
	photo.gallery._process(1)
	await frame("09d-fragments-new-batch")
	camera.rotation.y = PI
	await frame("10-fragments-rear")
	camera.rotation.y = 0
	var menu := Menu.new()
	menu.state_provider = photo.snapshot
	menu.queue_provider = func(): return photo.queue
	viewport.add_child(menu)
	menu.global_position = Vector3(0, 1.15, -1.5)
	menu.toggle()
	menu._activate(menu.PHOTO_LAYOUT)
	await frame("11-layout-menu")
	photo.queue_free()
	menu.queue_free()
	await process_frame
	viewport.queue_free()
	for failure in failures:
		push_error(failure)
	print("Photo layout render: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
