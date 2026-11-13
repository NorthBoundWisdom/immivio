extends SceneTree
## First-open and repeated page transitions through the production host and compositor.
const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var differences: Array[int] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


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
	var host := Main.new()
	host.settings_path = "user://playback-page-render.cfg"
	target.add_child(host)
	for node in [host, host.video, host.player_menu, host.library_menu, host.menu_compositor]:
		node.set_process(false)
	host.report_timer.stop()
	var head: Camera3D = host.xr_camera
	head.current = true
	head.environment = Environment.new()
	head.environment.background_mode = Environment.BG_COLOR
	head.environment.background_color = Color.BLACK
	host.video.media.begin(1)
	host.video.local_uri = "file:///synthetic-SBS.mp4"
	host.video.media.frame_counter = 1
	host.video.media.state = "paused"
	host.video.test_set_waiting_for_frame(false)
	host.video.stereo_sbs = true
	host.video.geometry = 1
	host.video.media.format = {"width": 3840, "height": 1920}
	host.video.control.duration_ms = 60000
	host.video.control.observed_position_ms = 12000
	host.video.test_apply_geometry()
	host.video.panel.visible = true
	host.video.panel.layers = 0
	host.test_show_player_menu()
	var menu: Node3D = host.player_menu
	menu.device_status.clock_provider = func(): return {"hour": 12, "minute": 34}
	menu.device_status.refresh(true)
	menu.refresh()
	var surface: Node3D = host.menu_compositor
	for frame in 5:
		surface.test_step(0)
		await process_frame
		await RenderingServer.frame_post_draw
	var first := head.unproject_position(menu.to_global(Vector3(-.56, -.045, 0)))
	var last := head.unproject_position(menu.to_global(Vector3(.56, -.125, 0)))
	var region := Rect2i(Vector2i(first), Vector2i(last - first))
	var baseline := target.get_texture().get_image()
	var visible := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var colour := baseline.get_pixel(x, y)
			if maxf(colour.r, maxf(colour.g, colour.b)) > .1:
				visible += 1
	if visible < 200:
		failures.append("Initial timeline and time labels must actually render")
	var rect: Rect2 = surface.surface_rect
	var output := OS.get_environment("IMMIVIO_PLAYBACK_PAGES_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		baseline.save_png(output.path_join("initial.png"))
	# The first Library open happens before any browser capture has existed.
	for destination in ["library", "playback", "info", "library", "info", "library", "playback"]:
		match destination:
			"library":
				menu.test_activate(Menu.BROWSE)
			"playback":
				host.library_menu.test_activate(host.library_menu.PLAYER)
			"info":
				menu.test_activate(12)
		surface._bounds_due = 0
		surface.test_step(0)
		if surface.surface_rect != rect or not surface.curved_mesh.visible:
			failures.append("Page %s resized or hid the playback projection" % destination)
		for frame in 3:
			await process_frame
			await RenderingServer.frame_post_draw
			var picture := target.get_texture().get_image()
			var changed := changed_pixels(baseline, picture, region)
			differences.append(changed)
			if changed > 0:
				failures.append(
					"Page %s changed %d timeline pixels in frame %d" % [destination, changed, frame]
				)
			if not output.is_empty():
				picture.save_png(output.path_join("frame-%02d.png" % differences.size()))
			surface._bounds_due = 0
			surface.test_step(0)
	print(
		(
			JSON
			. stringify(
				{
					"state": "passed" if failures.is_empty() else "failed",
					"failures": failures,
					"timeline_pixels": visible,
					"frame_timeline_differences": differences,
				}
			)
		)
	)
	host.queue_free()
	await process_frame
	target.queue_free()
	await process_frame
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
