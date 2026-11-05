extends SceneTree
## Real GPU frames from production playback controls; no media or native XR required.
const Menu := preload("res://scripts/player_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var coverage: Array[int] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func bar_pixels(picture: Image, region: Rect2i) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y, 2):
		for x in range(region.position.x, region.end.x, 2):
			var colour := picture.get_pixel(x, y)
			if maxf(colour.r, maxf(colour.g, colour.b)) > .03:
				count += 1
	return count


func _run() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(960, 720)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var head := Camera3D.new()
	target.add_child(head)
	head.current = true
	head.environment = Environment.new()
	head.environment.background_mode = Environment.BG_COLOR
	head.environment.background_color = Color.BLACK
	var menu := Menu.new()
	menu.state_provider = func(): return {
		"has_video": true, "source_uri": "file:///synthetic-SBS.mp4", "title": "Playback controls",
		"stereo": true, "duration_ms": 60000, "position_ms": 12000, "playback_state": "paused",
		"subtitle_options": [{"id": 1, "title": "English"}, {"id": 2, "title": "中文"}, {"id": 3, "title": "日本語"}, {"id": 4, "title": "Commentary"}],
		"bookmarks": [{"id": "sample", "position_ms": 10000}], "bookmark_scope": "synthetic", "bookmark_seekable": true
	}
	target.add_child(menu)
	menu.position = Vector3(0, -.5, -2)
	menu.curve_radius = 2
	menu.visible = true
	menu.set_process(false)
	menu.refresh()
	var surface := Surface.new()
	target.add_child(surface)
	surface.configure([menu], head, false)
	surface.set_process(false)
	for i in 5:
		surface._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
	var first := head.unproject_position(menu.to_global(Vector3(-.54, .22, 0)))
	var last := head.unproject_position(menu.to_global(Vector3(.54, -.18, 0)))
	var region := Rect2i(Vector2i(first), Vector2i(last - first))
	var initial := target.get_texture().get_image()
	var baseline := bar_pixels(initial, region)
	if baseline < 1000:
		failures.append("Initial transport must actually render")
	var rect: Rect2 = surface.surface_rect
	var output := OS.get_environment("IMMIVIO_POPUP_FRAMES_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		initial.save_png(output.path_join("toolbar.png"))
	for destination in [Menu.QUICK_SCREEN, Menu.MODE, 110, Menu.QUICK_SPEED, Menu.QUICK_COLOR, Menu.IPD_SETTINGS, Menu.SYNC_SETTINGS, Menu.QUEUE_SETTINGS, Menu.BookmarkMenu.LIST, 12]:
		for opening in [true, false]:
			if destination == Menu.BookmarkMenu.LIST:
				menu.bookmarks._activate(destination if opening else Menu.BookmarkMenu.CLOSE, {}, "synthetic")
			else:
				menu._activate(destination if opening else Menu.QUICK_CLOSE)
			surface._process(0)
			if surface.surface_rect != rect or not surface.curved_mesh.visible:
				failures.append("Popup %d changed or hid the transport projection" % destination)
			for frame in 3:
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := target.get_texture().get_image()
				var pixels := bar_pixels(picture, region)
				coverage.append(pixels)
				if pixels < baseline * .90:
					failures.append("Popup %d blanked the transport in frame %d: %d/%d" % [destination, frame, pixels, baseline])
				if not output.is_empty():
					picture.save_png(output.path_join("frame-%02d.png" % coverage.size()))
				surface._process(0)
	print(JSON.stringify({"state": "passed" if failures.is_empty() else "failed", "failures": failures,
		"baseline_transport_pixels": baseline, "frame_transport_pixels": coverage,
		"scope": "Production curved playback UI, ten popups opened/closed, three GPU frames per transition"}))
	target.queue_free()
	await process_frame
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
