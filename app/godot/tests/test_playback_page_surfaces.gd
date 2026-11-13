extends SceneTree
const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func button_point(menu: Node3D, target: int) -> Vector3:
	for button in menu.controls_snapshot():
		if button.target == target:
			return button.node.global_position
	return Vector3(INF, INF, INF)


func bent_ray(host: Node3D, flat: Vector3) -> Array:
	var surface: Node3D = host.menu_compositor
	var pose := Surface.capture_pose(surface.active_menu)
	var local: Vector3 = pose.affine_inverse() * flat
	var centre: Vector2 = surface.surface_rect.get_center()
	var radius: float = surface.active_menu.curve_radius
	if radius <= 0:
		return [host.eye(), (flat - host.eye()).normalized()]
	var angle: float = (local.x - centre.x) / radius
	var point: Vector3 = (
		pose * Vector3(centre.x + sin(angle) * radius, local.y, (1 - cos(angle)) * radius)
	)
	var origin: Vector3 = host.eye() + Vector3(.18, -.06, .08)
	return [origin, (point - origin).normalized()]


func tap(host: Node3D, target: int) -> bool:
	host.menu_compositor.test_step(0)
	var menu: Node3D = host.player_menu
	var flat := button_point(menu, target)
	if not flat.is_finite():
		return false
	var ray := bent_ray(host, flat)
	var handled: bool = menu.press_pointer("right_hand", ray[0], ray[1], true)
	menu.release_pointer("right_hand", ray[0], ray[1], true)
	host.menu_compositor.test_step(0)
	return handled


func check_first_browser_open(host: Node3D, geometry: int, follow: bool) -> void:
	host.view_follow.enabled = follow
	host.video.geometry = geometry
	host.video.test_apply_geometry()
	host.test_show_player_menu()
	var menu: Node3D = host.player_menu
	menu.refresh()
	var surface: Node3D = host.menu_compositor
	surface.test_step(0)
	var original_rect: Rect2 = surface.surface_rect
	var original_pose: Transform3D = menu.global_transform
	var original_progress: int = menu._progress.get_instance_id()
	var previous: Dictionary = surface._capture_metadata(Surface.capture_pose(menu))
	check(tap(host, Menu.BROWSE), "First browser open accepts a toolbar ray click")
	check(
		surface.surface_rect == original_rect,
		"First browser open preserves the original capture projection: %d" % geometry
	)
	check(
		surface._can_display_capture(previous),
		"First browser open retains the preceding toolbar image: %d" % geometry
	)
	check(
		(
			menu.global_transform.is_equal_approx(original_pose)
			and menu._progress.get_instance_id() == original_progress
		),
		"First browser open preserves timeline geometry and nodes"
	)
	var eye_before: Vector3 = host.xr_camera.global_position
	host.xr_camera.global_position += Vector3(.012, .004, .009)
	host._update_view_follow()
	host._update_player_menu_anchor()
	if geometry != 0:
		check(
			menu.global_position.is_equal_approx(original_pose.origin + Vector3(.012, .004, .009)),
			"Immersive toolbar follows translation while the browser is open"
		)
	check(
		host.library_menu.global_transform.is_equal_approx(Menu.switcher_pose(menu)),
		"Browser remains attached to the toolbar with follow=%s" % follow
	)
	var before_return: Transform3D = menu.global_transform
	host.library_menu.test_activate(host.library_menu.PLAYER)
	surface.test_step(0)
	check(
		menu.global_transform.is_equal_approx(before_return),
		"Returning from Library to Playback cannot reanchor the timeline: %d" % geometry
	)
	check(
		surface.surface_rect == original_rect,
		"Returning from Library keeps the original capture projection"
	)
	host.xr_camera.global_position = eye_before


func _run() -> void:
	var host := Main.new()
	host.settings_path = "user://playback-surfaces.cfg"
	root.add_child(host)
	host.set_process(false)
	host.menu_compositor.set_process(false)
	host.video.set_process(false)
	host.player_menu.set_process(false)
	host.report_timer.stop()
	host.video.media.begin(1)
	host.video.local_uri = "file:///pages-SBS.mp4"
	host.video.media.frame_counter = 1
	host.video.media.state = "paused"
	host.video.test_set_waiting_for_frame(false)
	host.video.stereo_sbs = true
	host.video.media.format = {"width": 3840, "height": 1080}
	host.video.control.duration_ms = 60000
	host.video.test_apply_geometry()
	host.video.panel.visible = true
	host.test_show_player_menu()
	var menu: Node3D = host.player_menu
	menu.state_provider = func():
		var state: Dictionary = host._menu_state()
		state.merge(
			{
				"bookmarks": [{"id": "sample", "position_ms": 12000}],
				"bookmark_scope": "synthetic",
				"bookmark_ready": true,
				"bookmark_seekable": true
			},
			true
		)
		return state
	for follow in [false, true]:
		for geometry in [0, 1, 3]:
			check_first_browser_open(host, geometry, follow)
	host.view_follow.enabled = false
	host.video.geometry = 0
	host.video.test_apply_geometry()
	host.test_show_player_menu()
	for target in [
		Menu.QUICK_SCREEN,
		Menu.MODE,
		110,
		Menu.QUICK_SPEED,
		Menu.QUICK_COLOR,
		Menu.IPD_SETTINGS,
		Menu.SYNC_SETTINGS,
		Menu.QUEUE_SETTINGS,
		12
	]:
		host.test_show_library_menu()
		host.library_menu.compact = true
		host.test_place_menu(host.library_menu)
		check(
			(
				host.library_menu.visible
				and menu.popup_snapshot().quick_open.is_empty()
				and not menu._mode_open
				and not menu._subtitle_open
			),
			"Browsing replaces the previous playback page"
		)
		host.menu_compositor.test_step(0)
		var original_pose: Transform3D = menu.global_transform
		var original_rect: Rect2 = host.menu_compositor.surface_rect
		var original_title: int = menu._title.get_instance_id()
		check(
			host.menu_compositor.active_menu == menu,
			"Compact browser retains playback capture anchor"
		)
		check(
			tap(host, target),
			"Toolbar page remains ray-selectable beside the compact browser: %d" % target
		)
		check(
			menu._popup_is_open(Menu.POPUP_TARGETS[target]) and not host.library_menu.visible,
			"Browser and playback page are mutually exclusive: %d" % target
		)
		check(
			menu.global_transform.is_equal_approx(original_pose),
			"Opening a popup beside the browser preserves toolbar placement"
		)
		check(
			host.menu_compositor.surface_rect == original_rect,
			"Replacing compact browser retains capture bounds"
		)
		check(
			menu._title.get_instance_id() == original_title,
			"Replacing compact browser retains transport nodes"
		)
		check(
			menu.curve_radius > 0 and host.menu_compositor.scene_curved,
			"Playback page uses the same curved renderer: %d" % target
		)
		var centre: Vector2 = menu.capture_envelope().get_center()
		var distance := menu.to_global(Vector3(centre.x, centre.y, 0)).distance_to(host.eye())
		check(
			is_equal_approx(menu.curve_radius, distance),
			"Playback curvature matches its placed viewing distance"
		)
	host.test_show_library_menu()
	check(tap(host, Menu.BookmarkMenu.LIST), "Bookmark list remains selectable beside the browser")
	check(
		menu.bookmarks.opened and not host.library_menu.visible,
		"Bookmark list also replaces the browser"
	)
	host.test_show_library_menu()
	check(not menu.bookmarks.opened, "Browsing closes bookmark pages")
	# Bending the timeline must not move a stationary drag's preview.
	host.test_show_player_menu()
	menu._reset_navigation()
	menu.refresh()
	menu.curve_radius = 1.4
	host.menu_compositor.test_step(0)
	var flat := menu.to_global(Vector3(Menu.BAR_SEEK * .3, Menu.BAR_SEEK_Y, 0))
	var ray := bent_ray(host, flat)
	check(menu.press_pointer("left_hand", ray[0], ray[1], true), "Curved timeline starts a seek")
	var at_press: int = menu._seek_preview
	var held_radius: float = menu.curve_radius
	var eye_before: Vector3 = host.xr_camera.global_position
	host.xr_camera.global_position += Vector3(.12, .02, .1)
	host.menu_compositor.test_step(0)
	check(
		is_equal_approx(menu.curve_radius, held_radius),
		"Pointer capture freezes the playback curve"
	)
	host.xr_camera.global_position = eye_before
	menu.update_pointer("left_hand", ray[0], ray[1], true)
	check(
		absi(menu._seek_preview - at_press) <= 1,
		"Stationary curved timeline drag cannot shift the seek position"
	)
	menu.release_pointer("left_hand", ray[0], ray[1], false)
	host.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Playback page surfaces checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
