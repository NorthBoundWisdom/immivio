extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Memory := preload("res://scripts/directory_browse_memory.gd")
const Main := preload("res://scripts/main.gd")
const Presets := preload("res://scripts/screen_presets.gd")
var failures: Array[String] = []


class PreviewMain:
	extends "res://scripts/main.gd"
	var ray_override: Variant = null

	func _ray(_hand: String) -> Variant:
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
	library._local_stack = [{"id": "/a", "title": "A"}]
	var entries: Array = []
	for i in 40:
		entries.append(
			{"title": "Video %02d.mp4" % i, "uri": "file:///a/%02d.mp4" % i, "size": 1048576}
		)
	library._local_entries = entries
	library.visible = true
	library.refresh()
	library._set_scroll(4)
	library.remember_browse()
	library._activate(Library.VIEW_MODE)
	check(
		library.list_view and library._first_line() == 16,
		"Icon-to-list switch retains the first visible file"
	)
	library._local_stack = [{"id": "/b", "title": "B"}]
	library.scroll = 0
	library._local_entries = []
	library.status = "Loading…"
	library.refresh()
	library._local_stack = [{"id": "/a", "title": "A"}]
	library.refresh()
	library.status = ""
	library._local_entries = entries
	library.refresh()
	check(library._first_line() == 16, "Async directory completion restores the saved item")
	library.file_actions.choose_order("name_desc")
	var saved_scope := library.file_actions.scope()
	library._local_stack = [{"id": "/b", "title": "B"}]
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
	var main := PreviewMain.new()
	root.add_child(main)
	main.set_process(false)
	main.video.local_uri = "file:///synthetic.mp4"
	main.video.media.begin(7)
	main.video.media.state = "playing"
	main.video.media.format = {"width": 1920, "height": 1080, "pixel_aspect": 1.0}
	main.video._waiting_first = false
	main.video.panel.visible = true
	main.video._apply_geometry()
	main.recent_menu.dismiss()
	main._show_player_menu()
	main.video_menu._activate(main.video_menu.SPACE_LOCK)
	var pose: Transform3D = main.video_menu.global_transform
	main.video.set_flat_world_pose(Transform3D(Basis.IDENTITY, Vector3(4, 2, -5)))
	main._place_menu(main.video_menu)
	check(
		main.video_menu.global_transform.is_equal_approx(pose),
		"Spatial lock survives independent video movement"
	)
	main.video_menu.dismiss()
	main._show_player_menu()
	check(
		main.video_menu.global_transform.is_equal_approx(pose), "Spatial lock survives hide/reopen"
	)
	main.video_menu._activate(main.video_menu.SPACE_LOCK)
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
	main.recent_menu.compact = true
	main._show_recent_menu(true)
	check(
		main.video_menu.visible and main.recent_menu.visible, "Browsing retains playback controls"
	)
	var lock_button: Dictionary = main.video_menu._buttons.filter(func(button): return button.target == main.video_menu.SPACE_LOCK)[0]
	var centre: Vector2 = lock_button.rect.get_center()
	main.ray_override = [
		main.video_menu.to_global(Vector3(centre.x, centre.y, 0.2)),
		-main.video_menu.global_basis.z.normalized()
	]
	var was_locked: bool = main.video_menu.space_locked
	main._update_menu_pointer("right_hand", true)
	check(
		main.video_menu.space_locked != was_locked,
		"The control bar accepts ray input while the library is open"
	)
	main.video_menu._toggle_popup("screen")
	check(
		main.video_menu.choices.targets.values().any(
			func(item): return item.key == "screen_distance"
		),
		"Screen layout exposes distance control"
	)
	for target in main.video_menu.choices.sliders:
		if main.video_menu.choices.targets[target].key != "screen_distance": continue
		var slider: Dictionary = main.video_menu.choices.sliders[target]
		var point: Vector3 = slider.node.to_global(Vector3(slider.left + slider.width * 0.5, slider.knob.position.y, 0.01))
		var direction: Vector3 = -slider.node.global_basis.z.normalized()
		main.video_menu.press_pointer("left_hand", point - direction * 0.2, direction, true)
		main.video_menu.release_pointer("left_hand", point - direction * 0.2, direction, true)
		check(absf(main.video.screen_distance - 7.05) < 0.1, "Pointer midpoint matches the logarithmic distance rail")
		break
	var probe := preload("res://scripts/selected_features_device_probe.gd").new()
	main._on_playback_adjustment("screen_fixed", false)
	check(await probe.choose(main.video_menu, "screen_preset", "home150"), "Ray selects the cinema preset dropdown")
	check(is_equal_approx(main.video.screen_distance, 4.6), "Preset choice routes into the screen adjustment handler")
	check(await probe.choose(main.video_menu, "screen_fixed", true), "Ray selects fixed viewing defaults")
	check(main.screen_layout.fixed(), "Fixed-default choice routes into persistent preferences")
	main.video.media.playback = {
		"details": {"paused_for_cache": "yes", "read_bytes_per_second": "2097152"}
	}
	main.video_menu.dismiss()
	main.recent_menu.dismiss()
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
