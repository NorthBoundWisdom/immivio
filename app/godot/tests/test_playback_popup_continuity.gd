extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func transport_ids(menu: Node3D) -> Array:
	var seek: Dictionary = menu._buttons.filter(func(button): return button.target == Menu.SEEK)[0]
	var play: Dictionary = menu._buttons.filter(func(button): return button.target == 102)[0]
	return [
		menu._title_pill.get_instance_id(),
		menu._title.get_instance_id(),
		menu._progress.get_instance_id(),
		menu._thumb.get_instance_id(),
		menu._elapsed.get_instance_id(),
		menu._duration.get_instance_id(),
		seek.node.get_instance_id(),
		play.node.get_instance_id()
	]


func _run() -> void:
	var state := {
		"has_video": true,
		"playing": false,
		"playback_state": "paused",
		"audio_available": true,
		"source_uri": "file:///popup-continuity.mp4",
		"title": "Popup continuity",
		"geometry": 0,
		"stereo": true,
		"duration_ms": 60000,
		"position_ms": 10000,
		"subtitle_options":
		[
			{"id": 1, "title": "English"},
			{"id": 2, "title": "中文"},
			{"id": 3, "title": "日本語"},
			{"id": 4, "title": "Commentary"}
		],
		"subtitle_encoding_row":
		{
			"key": "subtitle_encoding",
			"value": "auto",
			"choices": [{"value": "auto", "label": "Auto"}]
		},
		"bookmark_scope": "synthetic",
		"bookmarks": [{"id": "sample", "position_ms": 10000}],
		"bookmark_ready": true,
		"bookmark_seekable": true
	}
	var menu := Menu.new()
	menu.state_provider = func(): return state
	root.add_child(menu)
	menu.visible = true
	menu.set_process(false)
	var surface := Surface.new()
	root.add_child(surface)
	surface.active_menu = menu
	surface.menus = [menu]
	surface.layer = OpenXRCompositionLayerQuad.new()
	surface.add_child(surface.layer)
	surface.cylinder_layer = OpenXRCompositionLayerCylinder.new()
	surface.add_child(surface.cylinder_layer)
	for geometry in [0, 1, 3]:
		state.geometry = geometry
		menu.curve_radius = 0.0 if geometry == 0 else 1.6
		menu._reset_navigation()
		menu.refresh()
		var original := transport_ids(menu)
		state.position_ms = 10000
		surface.content_bounds = Rect2()
		surface._update_bounds()
		var rect: Rect2 = surface.surface_rect
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
			if target == Menu.QUICK_SCREEN and geometry != 0:
				continue
			var metadata: Dictionary = surface._capture_metadata(Surface.capture_pose(menu))
			menu._activate(target)
			menu.position.x += .0007
			check(
				transport_ids(menu) == original,
				"Opening a popup retains transport/header nodes for target %d" % target
			)
			surface._update_bounds()
			check(
				surface.surface_rect == rect,
				"Popup target %d keeps the first transport capture projection" % target
			)
			check(
				surface._can_display_capture(metadata),
				"Popup keeps the acknowledged toolbar visible until replacement pixels arrive"
			)
			surface.presented = metadata
			surface.native_supported = true
			check(
				not surface.is_layout_presented(menu),
				"New popup cannot consume input before its own capture acknowledgement"
			)
			menu.xr_surface = surface
			menu._hover["right_hand"] = 110
			menu.update_pointer("right_hand", Vector3(0, 0, 1), Vector3.FORWARD, true)
			check(
				menu._hover.get("right_hand") == 110,
				"Acknowledgement wait keeps persistent toolbar hover from pulsing"
			)
			check(
				menu.ray_hit(Vector3(0, 0, 1), Vector3.FORWARD).is_empty(),
				"Retained hover cannot bypass input acknowledgement"
			)
			menu.update_pointer("right_hand", Vector3.ZERO, Vector3.ZERO, false)
			check(
				menu._hover.get("right_hand") == menu.NONE,
				"Tracking loss still clears retained hover"
			)
			menu.xr_surface = null
			check(
				Surface.presented_pose(metadata, menu).is_equal_approx(Surface.capture_pose(menu)),
				"Pending popup cannot freeze native toolbar placement"
			)
			surface._apply_presented_layer()
			check(
				(
					surface.layer.quad_size == rect.size
					if menu.curve_radius == 0
					else surface.cylinder_layer.central_angle > .001
				),
				"Native quad/cylinder retains the moving toolbar during popup redraw"
			)
			var radius: float = menu.curve_radius
			menu.curve_radius += .1
			check(
				not surface._can_display_capture(metadata),
				"A changed curve still requires its own capture"
			)
			menu.curve_radius = radius
			surface.surface_rect = rect.grow(.1)
			check(
				not surface._can_display_capture(metadata),
				"A changed projection still requires its own capture"
			)
			surface.surface_rect = rect
			surface.native_supported = false
			menu._activate(Menu.QUICK_CLOSE)
			check(transport_ids(menu) == original, "Closing a popup retains the transport nodes")
		menu._activate(110)
		var subtitle_count: int = menu._buttons.size()
		menu._activate(menu.SUBTITLE_DOWN)
		check(
			menu._buttons.size() == subtitle_count and transport_ids(menu) == original,
			"Subtitle scrolling replaces popup rows without accumulating nodes"
		)
		menu._activate(menu.QUICK_CLOSE)
		menu.bookmarks._activate(menu.BookmarkMenu.LIST, {}, "synthetic")
		check(
			transport_ids(menu) == original and menu.bookmarks.opened,
			"Bookmark list uses the same persistent transport"
		)
		menu.bookmarks._activate(menu.BookmarkMenu.CLOSE, {}, "synthetic")
		check(transport_ids(menu) == original, "Closing bookmarks retains transport nodes")
		state.position_ms = 20000
		menu.refresh_values()
		check(
			transport_ids(menu) == original and menu._elapsed.text == "00:20",
			"Live playback values update existing transport nodes"
		)
	var previous := transport_ids(menu)
	state.source_uri = "file:///replacement.mp4"
	menu.refresh_values()
	check(
		transport_ids(menu) != previous and not menu.bookmarks.opened,
		"Replacing a source still rebuilds the correct transport"
	)
	menu.free()
	surface.free()
	for failure in failures:
		push_error(failure)
	print("Playback popup continuity: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
