extends SceneTree
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var actions := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var queue := Surface.PresentationQueue.new()
	var old_pose := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, -1.4))
	var old_rect := Rect2(-.6, -.3, 1.2, .8)
	var new_rect := Rect2(-.8, -.7, 1.6, 1.1)
	var first := queue.stage({"rect": old_rect, "pose": old_pose, "layout_revision": 1})
	var second := queue.stage(
		{"rect": new_rect, "pose": old_pose.translated(Vector3.UP), "layout_revision": 2}
	)
	var displayed := queue.take(first)
	check(
		displayed.rect == old_rect,
		"Pending page projection cannot replace the image still on screen"
	)
	check(queue.take(first).is_empty(), "Duplicate GPU acknowledgements cannot rewind presentation")
	check(
		queue.take(second).rect == new_rect, "New projection publishes only after its own GPU copy"
	)
	queue.reset()
	check(
		queue.take(first).is_empty() and queue.take(second).is_empty(),
		"Session reset cannot revive a stale image/pose"
	)
	for i in 20:
		queue.stage({"rect": old_rect})
	check(queue.pending.size() <= 4, "Delayed GPU acknowledgement has bounded metadata storage")
	var menu := Menu.new()
	root.add_child(menu)
	menu.set_process(false)
	menu.visible = true
	menu.layout_revision = 2
	menu.position = Vector3(1, 2, -3)
	check(
		Surface.presented_pose(displayed, menu) == Surface.capture_pose(menu),
		"Persistent toolbar motion remains responsive while its popup awaits capture"
	)
	menu.layout_revision = 1
	check(
		Surface.presented_pose(displayed, menu) == Surface.capture_pose(menu),
		"Rigid motion of an unchanged page remains responsive"
	)
	menu.action_requested.connect(func(_action): actions += 1)
	menu.setting_requested.connect(func(_key, _value): actions += 1)
	var warmer := Warmup.new()
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = menu
	compositor.menus = [menu]
	var metadata := compositor._capture_metadata(Surface.capture_pose(menu))
	check(compositor._matches_capture(metadata), "Current page can publish its captured pixels")
	menu.refresh()
	check(
		compositor._matches_capture(metadata),
		"Refreshing values on the same page must not blank the menu"
	)
	menu._quick_open = "info"
	menu.refresh()
	check(
		not compositor._matches_capture(metadata),
		"A subtitle/page redraw cannot publish the previous page's pixels"
	)
	var library := preload("res://scripts/library_menu.gd").new()
	root.add_child(library)
	library.visible = true
	compositor.menus.append(library)
	metadata = compositor._capture_metadata(Surface.capture_pose(menu))
	library.section = library.Section.SETTINGS
	library.refresh()
	check(
		not compositor._matches_capture(metadata),
		"A secondary browser redraw also invalidates captured pixels"
	)
	metadata = compositor._capture_metadata(Surface.capture_pose(menu))
	library.visible = false
	check(
		not compositor._matches_capture(metadata),
		"Closing the browser invalidates the combined capture"
	)
	compositor.menus = [menu]
	library.free()
	menu.curve_radius = 0
	compositor.layer = OpenXRCompositionLayerQuad.new()
	root.add_child(compositor.layer)
	compositor.native_supported = true
	compositor.surface_rect = old_rect
	compositor.presented = compositor._capture_metadata(Surface.capture_pose(menu))
	compositor._apply_presented_layer()
	check(
		compositor.layer.quad_size == old_rect.size,
		"Acknowledged current pixels reveal the native layer"
	)
	menu.refresh()
	check(
		compositor._matches_capture(compositor.presented),
		"Ordinary redraws retain the current native page while copying"
	)
	menu._quick_open = ""
	menu.refresh()
	compositor._apply_presented_layer()
	check(
		compositor.layer.quad_size == old_rect.size,
		"A page redraw preserves the native window when its projection is unchanged"
	)
	menu.position.x += .2
	compositor._apply_presented_layer()
	check(
		compositor.layer.quad_size == old_rect.size,
		"Toolbar motion cannot blank a popup awaiting acknowledgement"
	)
	check(
		compositor.layer.global_position.is_equal_approx(
			(
				(
					Surface.capture_pose(menu)
					* Transform3D(
						Basis.IDENTITY, Vector3(old_rect.get_center().x, old_rect.get_center().y, 0)
					)
				)
				. origin
			)
		),
		"Retained native toolbar follows its current placement"
	)
	compositor.presented = compositor._capture_metadata(Surface.capture_pose(menu))
	compositor._apply_presented_layer()
	check(
		compositor.layer.quad_size == old_rect.size,
		"Acknowledging the new page reveals its own projection"
	)
	compositor._tag(menu._backdrop)
	compositor._set_native_capture(true)
	compositor._set_native_ready(false)
	check(
		menu._backdrop.layers == Surface.UI_LAYER,
		"Waiting for the native surface never flashes flat scene geometry"
	)
	compositor.layer.free()
	compositor.layer = null
	compositor._set_native_capture(false)
	menu.curve_radius = 1.4
	var ordinary_rect := Rect2()
	for page in Warmup.PAGES:
		warmer.prepare(menu, page)
		if page in ["bar", "screen", "playback", "info"]:
			compositor._update_bounds()
			if ordinary_rect == Rect2():
				ordinary_rect = compositor.surface_rect
			check(
				compositor.surface_rect == ordinary_rect,
				"First ordinary page opens inside a stable capture projection: " + page
			)
		check(not menu._buttons.is_empty(), "Synthetic warmup builds actual controls: " + page)
	warmer.prepare(menu, "screen")
	for i in 12:
		menu.global_transform = Transform3D(
			Basis(Vector3.UP, float(i) * .31) * Basis.from_scale(Menu.PANEL_SCALE),
			Vector3(float(i) * .12, 1.6, -1.4)
		)
		compositor.content_bounds = Rect2()
		compositor._update_bounds()
		check(
			compositor.surface_rect == ordinary_rect,
			"Head-follow floating-point noise cannot grow/recentre a first-open projection"
		)
	check(actions == 0, "Warmup cannot activate controls or change saved settings")
	check(menu._state.source_uri == "warmup://synthetic", "Warmup never opens customer media")
	compositor.free()
	warmer.free()
	menu.free()
	for failure in failures:
		push_error(failure)
	print("UI presentation/warmup checks: ", "passed" if failures.is_empty() else failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
