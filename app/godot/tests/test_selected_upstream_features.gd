extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Memory := preload("res://scripts/directory_browse_memory.gd")
const Main := preload("res://scripts/main.gd")
const Presets := preload("res://scripts/screen_presets.gd")
var failures: Array[String] = []


class TestInputSource:
	extends "res://scripts/input_source.gd"
	var ray_override: Variant = null

	func ray(_hand: String) -> Variant:
		return ray_override


func check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	_run.call_deferred()


func _run() -> void:
	var memory := Memory.new()
	memory.path = "user://memory.cfg"
	memory.remember("local/a/video", {"index": 12, "anchor": "a"})
	memory.flush()
	var restored := Memory.new()
	restored.path = memory.path
	restored.load_file()
	check(restored.lookup("local/a/video").index == 12, "Directory positions survive restart")
	check(restored.lookup("local/a/images").is_empty(), "Media filters do not share positions")
	memory.configure(true, false)
	memory.remember("network/private", {"index": 20})
	memory.configure(true, true)
	memory.flush()
	restored.load_file()
	check(
		restored.lookup("network/private").is_empty(),
		"Re-enabling history does not publish private session positions"
	)
	memory.clear()
	restored = Memory.new()
	restored.path = memory.path
	restored.load_file()
	check(
		restored.lookup("local/a/video").is_empty(), "Clearing history clears persistent navigation"
	)
	var library := Library.new()
	root.add_child(library)
	library.set_process(false)
	library.section = Library.Section.LOCAL
	library.sources.local_stack = [{"id": "/a", "title": "A"}]
	var entries: Array = []
	for i in 40:
		entries.append(
			{"title": "Video %02d.mp4" % i, "uri": "file:///a/%02d.mp4" % i, "size": 1048576}
		)
	library.sources.local_entries = entries
	library.visible = true
	library.refresh()
	library._set_scroll(4)
	library.remember_browse()
	library._activate(Library.VIEW_MODE)
	check(
		library.list_view and library._first_line() == 16,
		"Icon-to-list switch retains the first visible file"
	)
	library.sources.local_stack = [{"id": "/b", "title": "B"}]
	library.scroll = 0
	library.sources.local_entries = []
	library.status = "Loading…"
	library.refresh()
	library.sources.local_stack = [{"id": "/a", "title": "A"}]
	library.refresh()
	library.status = ""
	library.sources.local_entries = entries
	library.refresh()
	check(library._first_line() == 16, "Async directory completion restores the saved item")
	library.file_actions.choose_order("name_desc")
	var saved_scope := library.file_actions.scope()
	library.sources.local_stack = [{"id": "/b", "title": "B"}]
	library.refresh()
	check(
		(
			library.file_actions.order() == "name_asc"
			and library.file_actions.orders[saved_scope] == "name_desc"
		),
		"Sort order is independent per directory"
	)
	library.queue_free()
	await process_frame
	var main := Main.new()
	main.input_source = TestInputSource.new(main)
	root.add_child(main)
	main.set_process(false)
	main.video.local_uri = "file:///synthetic.mp4"
	main.video.media.begin(7)
	main.video.media.state = "playing"
	main.video.media.format = {"width": 1920, "height": 1080, "pixel_aspect": 1.0}
	main.video._waiting_first = false
	main.video.panel.visible = true
	main.video._apply_geometry()
	main.library_menu.dismiss()
	main._show_player_menu()
	check(
		not main.video_menu._buttons.any(func(button): return button.target == 224),
		"The control bar has no spatial lock; follow mode owns placement"
	)
	main._on_playback_adjustment("screen_preset", "giant22")
	check(
		is_equal_approx(main.video.screen_distance, 18) and main.video._flat.size.x <= 22.001,
		"Cinema preset fits the original aspect within its envelope"
	)
	check(
		main.video._flat.size.x / main.video._flat.size.y > 1.7,
		"Preset does not stretch 16:9 content"
	)
	main._on_playback_adjustment("screen_fixed", true)
	var fixed_distance: float = main.video.screen_distance
	main._on_playback_adjustment("screen_distance", 8.0)
	main._save_playback_adjustments()
	check(
		is_equal_approx(float(main.settings.get_value("screen", "distance")), fixed_distance),
		"Temporary adjustments cannot overwrite fixed viewing defaults"
	)
	main.screen_layout.restore()
	check(
		is_equal_approx(main.video.screen_distance, fixed_distance), "Fixed layout can be restored"
	)
	main._on_playback_adjustment("controls_opacity", 0.25)
	check(
		is_equal_approx(main.video_menu.controls_opacity, 0.25),
		"Opacity updates the active control bar"
	)
	main.library_menu.section = main.library_menu.Section.SETTINGS
	main._show_library_menu(true)
	var browser: Node3D = main.library_menu
	var bar: Node3D = main.video_menu
	check(main.video_menu.visible and browser.visible, "Browsing retains playback controls")
	check(
		(
			browser.playback_browser
			and browser.compact
			and browser.section == browser.Section.RECENT
			and not browser.nav_order().has(browser.Section.SETTINGS)
			and not browser._buttons.any(
				func(button): return button.target == browser.NAV_BASE + browser.Section.SETTINGS
			)
		),
		"The playback browser is a video switcher without Settings"
	)
	var scale := browser.global_basis.get_scale()
	var panel_left := browser.to_global(
		Vector3(browser.PANEL_CENTRE.x - browser.PANEL_SIZE.x * .5, 0, 0)
	)
	var panel_right := browser.to_global(
		Vector3(browser.PANEL_CENTRE.x + browser.PANEL_SIZE.x * .5, 0, 0)
	)
	var bar_left := bar.to_global(Vector3(-bar.BAR_WIDTH * .5, 0, 0))
	var bar_right := bar.to_global(Vector3(bar.BAR_WIDTH * .5, 0, 0))
	var panel_bottom := browser.to_local(bar.to_global(Vector3(0, bar.HEADER_Y, 0))).y
	check(
		(
			is_equal_approx(scale.x, scale.y)
			and absf(panel_left.x - bar_left.x) < 0.005
			and absf(panel_right.x - bar_right.x) < 0.005
			and panel_bottom < -browser.PANEL_SIZE.y * .5
		),
		"The playback browser is uniformly scaled, as wide as the bar and above it"
	)
	var reserved: Rect2 = bar.capture_envelope()
	var inverse: Transform3D = bar.global_transform.affine_inverse()
	var corners := [
		browser.to_global(Vector3(-1.0, -browser.PANEL_SIZE.y * .5, 0)),
		browser.to_global(
			Vector3(
				browser.PANEL_CENTRE.x + browser.PANEL_SIZE.x * .5, browser.PANEL_SIZE.y * .5, 0
			)
		)
	]
	check(
		corners.all(
			func(point):
				var local: Vector3 = inverse * point
				return reserved.grow(0.001).has_point(Vector2(local.x, local.y)),
		),
		"The bar's capture already reserves the switcher, so opening it cannot resize the layer"
	)
	var speed: Dictionary = bar._buttons.filter(func(button): return button.target == bar.QUICK_SPEED)[0]
	var centre: Vector2 = speed.rect.get_center()
	main.input_source.ray_override = [
		bar.to_global(Vector3(centre.x, centre.y, 0.2)), -bar.global_basis.z.normalized()
	]
	main._update_menu_pointer("right_hand", true)
	check(bar._quick_open == "speed", "The control bar accepts ray input while the browser is open")
	bar._toggle_popup("")
	main._show_library_menu(true)
	main._on_menu_action("stop")
	check(
		(
			browser.visible
			and not bar.visible
			and not browser.playback_browser
			and not browser.compact
			and is_equal_approx(browser.global_basis.get_scale().x, 1.0)
			and browser.nav_order().has(browser.Section.SETTINGS)
		),
		"Closing the video from the switcher returns to the full library, not a small window"
	)
	# Resume the synthetic video for the remaining checks.
	main.video.local_uri = "file:///synthetic.mp4"
	main.video.media.begin(8)
	main.video.media.state = "playing"
	main.video.media.format = {"width": 1920, "height": 1080, "pixel_aspect": 1.0}
	main.video._waiting_first = false
	main.video.panel.visible = true
	main.video._apply_geometry()
	main.library_menu.dismiss()
	main._show_player_menu()
	main.video_menu._toggle_popup("screen")
	check(
		main.video_menu.choices.targets.values().any(
			func(item): return item.key == "screen_distance"
		),
		"Screen layout exposes distance control"
	)
	for target in main.video_menu.choices.sliders:
		if main.video_menu.choices.targets[target].key != "screen_distance":
			continue
		var slider: Dictionary = main.video_menu.choices.sliders[target]
		var point: Vector3 = slider.node.to_global(
			Vector3(slider.left + slider.width * 0.5, slider.knob.position.y, 0.01)
		)
		var direction: Vector3 = -slider.node.global_basis.z.normalized()
		main.video_menu.press_pointer("left_hand", point - direction * 0.2, direction, true)
		main.video_menu.release_pointer("left_hand", point - direction * 0.2, direction, true)
		check(
			absf(main.video.screen_distance - 2.25) < 0.1,
			"Pointer midpoint matches the logarithmic distance rail"
		)
		break
	var probe := preload("res://scripts/selected_features_device_probe.gd").new()
	main._on_playback_adjustment("screen_fixed", false)
	check(
		await probe.choose(main.video_menu, "screen_preset", "home150"),
		"Ray selects the cinema preset dropdown"
	)
	check(
		is_equal_approx(main.video.screen_distance, 4.6),
		"Preset choice routes into the screen adjustment handler"
	)
	check(
		await probe.choose(main.video_menu, "screen_fixed", true),
		"Ray selects fixed viewing defaults"
	)
	check(main.screen_layout.fixed(), "Fixed-default choice routes into persistent preferences")
	main.video.media.playback = {
		"details": {"paused_for_cache": "yes", "read_bytes_per_second": "2097152"}
	}
	main.video_menu.dismiss()
	main.library_menu.dismiss()
	main.playback_feedback.tick()
	check(
		(
			main.playback_feedback.visible
			and main.playback_feedback.message.contains("2.0 MB/s")
			and not main.video_menu.visible
		),
		"Buffering feedback reports measured speed without reopening controls"
	)
	main.video.media.state = "failed"
	main.video.media.error = "STRM_EMPTY"
	main.playback_feedback.tick()
	check(
		main.video_menu.visible and main.video_menu._quick_open == "info",
		"Playback failures automatically expose their reason"
	)
	main.video.local_uri = ""
	main.video.media.session_id = 0
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Selected upstream feature failures: ", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
