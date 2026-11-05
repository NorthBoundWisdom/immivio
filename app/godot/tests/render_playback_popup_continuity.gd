extends SceneTree
## Real GPU frames from production playback controls; no media or native XR required.
const Menu := preload("res://scripts/player_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var coverage: Array[int] = []
var differences: Array[int] = []


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


func tap(menu: Node3D, surface: Node3D, target: int) -> Dictionary:
	for button in menu._buttons:
		if button.target != target or not button.enabled:
			continue
		var pose: Transform3D = Surface.capture_pose(menu)
		var local: Vector3 = pose.affine_inverse() * button.node.global_position
		var centre: Vector2 = surface.surface_rect.get_center()
		var radius: float = menu.curve_radius
		var angle := (local.x - centre.x) / radius
		var point: Vector3 = pose * Vector3(centre.x + sin(angle) * radius, local.y, (1 - cos(angle)) * radius)
		var normal: Vector3 = pose.basis * Vector3(-sin(angle), 0, cos(angle))
		var origin := point + normal * .5
		menu.update_pointer("right_hand", origin, -normal, true)
		surface._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
		surface._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
		var before: Image = menu.get_viewport().get_texture().get_image()
		var pressed: bool = menu.press_pointer("right_hand", origin, -normal, true)
		menu.release_pointer("right_hand", origin, -normal, true)
		return {"pressed": pressed, "image": before}
	return {}


func changed_pixels(before: Image, after: Image, region: Rect2i) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > .008:
				count += 1
	return count


func _run() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(1920, 1440)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var head := Camera3D.new()
	target.add_child(head)
	head.current = true
	head.environment = Environment.new()
	head.environment.background_mode = Environment.BG_COLOR
	head.environment.background_color = Color.BLACK
	Menu.I18n.language = "zh"
	var menu := Menu.new()
	menu.state_provider = func(): return {
		"has_video": true, "source_uri": "file:///synthetic-SBS.mp4", "title": "Playback controls",
		"stereo": true, "duration_ms": 60000, "position_ms": 12000, "playback_state": "paused",
		"subtitle_options": [{"id": 1, "title": "A very long external subtitle filename · 简体中文字幕 · 日本語字幕 · director commentary extended edition · translation credits · language metadata · UTF-8 · SRT"}, {"id": 2, "title": "中文"}, {"id": 3, "title": "日本語"}, {"id": 4, "title": "Commentary"}],
		"bookmarks": [{"id": "sample", "position_ms": 10000}], "bookmark_scope": "synthetic", "bookmark_seekable": true
	}
	target.add_child(menu)
	menu.position = Vector3(0, -.5, -1.6)
	menu.scale = Menu.PANEL_SCALE
	menu.curve_radius = 2
	menu.visible = true
	menu.set_process(false)
	menu.refresh()
	menu.device_status.clock_provider = func(): return {"hour": 12, "minute": 34}
	menu.device_status.refresh(true)
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
	var title_first := head.unproject_position(menu.to_global(Vector3(-.52, .18, 0)))
	var title_last := head.unproject_position(menu.to_global(Vector3(.52, .08, 0)))
	var title_region := Rect2i(Vector2i(title_first), Vector2i(title_last - title_first))
	var time_first := head.unproject_position(menu.to_global(Vector3(-.54, -.07, 0)))
	var time_last := head.unproject_position(menu.to_global(Vector3(.54, -.11, 0)))
	var time_region := Rect2i(Vector2i(time_first), Vector2i(time_last - time_first))
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
			var click := await tap(menu, surface, destination)
			if not click.get("pressed", false):
				failures.append("Ray click failed for popup %d" % destination)
			var opened: bool = menu.bookmarks.opened if destination == Menu.BookmarkMenu.LIST else menu._popup_is_open(menu.POPUP_TARGETS[destination])
			if opened != opening:
				failures.append("Popup %d did not reach its requested open/closed state" % destination)
			var before: Image = click.get("image", initial)
			# Immersive/head-follow controls translate with the viewer while a click
			# waits for GPU acknowledgement. Static-camera coverage misses this gap.
			menu.position.x += .0007
			head.position.x += .0007
			surface._process(0)
			if surface.surface_rect != rect or not surface.curved_mesh.visible:
				failures.append("Popup %d changed or hid the transport projection" % destination)
			for frame in 3:
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := target.get_texture().get_image()
				var pixels := bar_pixels(picture, region)
				coverage.append(pixels)
				var changed := changed_pixels(before, picture, title_region) + changed_pixels(before, picture, time_region)
				differences.append(changed)
				if changed > 0:
					failures.append("Popup %d changed %d title/timeline pixels in frame %d" % [destination, changed, frame])
				if pixels < baseline * .90:
					failures.append("Popup %d blanked the transport in frame %d: %d/%d" % [destination, frame, pixels, baseline])
				if not output.is_empty():
					picture.save_png(output.path_join("frame-%02d.png" % coverage.size()))
				surface._bounds_due = 0
				surface._process(0)
	print(JSON.stringify({"state": "passed" if failures.is_empty() else "failed", "failures": failures,
		"baseline_transport_pixels": baseline, "transport_pixel_differences": differences, "frame_transport_pixels": coverage,
		"scope": "Production curved playback UI, ten popups opened/closed, moving viewer, ray clicks, three GPU frames per transition"}))
	target.queue_free()
	await process_frame
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
