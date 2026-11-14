extends SceneTree
const Main := preload("res://scripts/main.gd")
const Host := preload("res://tests/test_file_mode_memory.gd").Host
var failures: Array[String] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func toggle(menu: Node3D) -> void:
	menu.visible = true
	menu.refresh()
	var buttons: Array = menu.controls_snapshot().filter(func(item): return item.target == 104)
	check(buttons.size() == 1 and buttons[0].enabled, "Force switch remains clickable")
	if buttons.size() != 1 or not buttons[0].enabled:
		return
	var point: Vector2 = buttons[0].rect.get_center()
	var origin: Vector3 = menu.to_global(Vector3(point.x, point.y, 1))
	check(
		menu.press_pointer("right_hand", origin, -menu.global_basis.z, true),
		"Ray presses force switch"
	)
	menu.release_pointer("right_hand", origin, -menu.global_basis.z, true)
	menu.refresh()


func _run() -> void:
	var main := Main.new()
	root.add_child(main)
	main.set_process(false)
	main.report_timer.stop()
	main.menu_compositor.set_process(false)
	main.library_menu.dismiss()
	var video: Node3D = main.video
	video.set_process(false)
	video.platform = Host.new()
	video.history_enabled = false
	var menu: Node3D = main.video_menu
	menu.set_process(false)
	check(
		video.open_local("http://127.0.0.1/dlna/scene/1", "Generated scene title", 0, false),
		"Open generated DLNA-style title without alpha tags"
	)
	check(not video.packed_file and not video.alpha_wanted(), "Untagged scene starts opaque")
	# Exercise the real menu/coordinator before frame metadata exists, rather than
	# supplying known-good compatibility fields before the user can press anything.
	toggle(menu)
	check(
		video.alpha_wanted() and video.packed_alpha_forced,
		"Menu accepts Force On with inconclusive detection"
	)
	check(
		menu._status_text() == menu.I18n.t("Packed alpha: waiting for a decoded frame"),
		"Waiting reason is visible"
	)
	video._layout_pending = null
	video.media.state = "paused"
	video.media.last_pair = {"fixture": true}
	video.media.format = {"width": 8192, "height": 4096}
	video._apply_packed()
	menu.refresh()
	check(
		menu._status_text() == menu.I18n.t("Packed alpha: select Fisheye"),
		"Projection blocker is visible"
	)
	video.set_projection(2)
	menu.refresh()
	check(
		menu._status_text() == menu.I18n.t("Packed alpha: select full SBS"),
		"Stereo blocker is visible"
	)
	video.set_stereo_layout(1)
	check(
		video.alpha_ready() and video.material.get_shader_parameter("packed_alpha"),
		"Pending Force On engages on current paused frame after correcting layout"
	)
	check(not video.alpha_available(), "Automatic detector is still inconclusive without metadata")
	toggle(menu)
	check(not video.alpha_wanted() and not video.alpha_ready(), "Force Off clears current mask")
	# Force is intentionally independent of conservative automatic metadata gates.
	for metadata in [
		{},
		{"pixel_aspect": 1.2},
		{"unapplied_rotation_degrees": 90},
		{"width": 4096, "height": 4096}
	]:
		video.media.format = {"width": 8192, "height": 4096}
		video.media.format.merge(metadata, true)
		toggle(menu)
		check(
			video.alpha_ready(),
			"Force On bypasses inconclusive automatic metadata: " + str(metadata)
		)
		toggle(menu)
		check(not video.alpha_wanted(), "Force Off always remains available")
	video.media.format = {"width": 0, "height": 0}
	toggle(menu)
	check(
		video.alpha_wanted() and not video.alpha_ready(),
		"Invalid frame retains intent without applying mask"
	)
	menu.refresh()
	check(
		menu._status_text() == menu.I18n.t("Packed alpha: decoded frame is too small"),
		"Frame-size blocker is visible"
	)
	toggle(menu)
	check(not video.alpha_wanted(), "Force Off works even when renderer cannot apply the mask")
	check(
		video.open_local(
			"file:///tagged_fisheye190_alpha.mp4", "tagged_fisheye190_alpha.mp4", 0, false
		),
		"Open tagged file"
	)
	check(
		video.packed_file and video.alpha_wanted() and not video.packed_alpha_forced,
		"Filename auto default remains distinct from manual force"
	)
	check(
		video.open_local("http://127.0.0.1/dlna/scene/2", "Next scene", 0, false),
		"Open next generated scene"
	)
	check(
		not video.alpha_wanted() and not video.packed_alpha_forced,
		"Force does not leak into next video"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Manual packed alpha failures: ", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
