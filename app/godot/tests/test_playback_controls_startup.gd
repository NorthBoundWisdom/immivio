extends SceneTree

const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
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

func opening(host: Node3D, id: int) -> void:
	host.recent_menu.dismiss()
	host.player_menu.dismiss()
	host.video.media.begin(id)
	host.video.local_uri = "file:///startup-%d.mp4" % id
	host.video._waiting_first = true
	host.video.panel.visible = false
	host.video.geometry = Geometry.Geometry.FLAT

func ready(host: Node3D, projection: int) -> void:
	host.video.geometry = projection
	host.video.media.format = {"width": 3840, "height": 1920}
	host.video.stereo_sbs = true
	host.video.media.frame_counter = 1
	host.video.media.state = "playing"
	host.video._waiting_first = false
	host.video.reset_view()
	host.video._apply_geometry()
	host.video.panel.visible = true
	host._place_screen()
	host._update_player_menu_anchor()

func _run() -> void:
	var host := Main.new()
	host.settings_path = "user://controls-startup.cfg"
	root.add_child(host)
	host.set_process(false)
	host.menu_compositor.set_process(false)
	host.video.set_process(false)
	host.player_menu.set_process(false)
	host.report_timer.stop()
	for projection in [Geometry.Geometry.FLAT, Geometry.Geometry.FISHEYE]:
		opening(host, projection + 1)
		host.player_menu.section = 1  # A previous expanded page cannot choose the startup pose.
		host._show_player_menu()
		var initial_visible: bool = host.player_menu.visible
		var initial_timeline: Vector3 = host.player_menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0))
		check(not initial_visible, "Unresolved layout must not expose a provisional timeline: %d" % projection)
		host.playback_feedback.tick()
		check(host.playback_feedback.visible and not host.playback_feedback.message.is_empty(), "Loading keeps status feedback without a provisional control bar")
		host._menu_touched_ms = Time.get_ticks_msec() - host.CONTROLS_HIDE_MS - 100
		ready(host, projection)
		host._update_controls_visibility(host.player_menu)
		check(host.player_menu.visible, "First frame reveals the requested controls: %d" % projection)
		var final_pose: Transform3D = host.player_menu.global_transform
		host._place_menu(host.player_menu)
		check(host.player_menu.global_transform.is_equal_approx(final_pose), "First visible pose already equals the resolved content anchor")
		print("startup projection=", projection, " provisional_visible=", initial_visible, " timeline_shift_metres=", initial_timeline.distance_to(host.player_menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0))))
		# A seek after presentation keeps useful controls visible.
		host.video._waiting_first = true
		host._show_player_menu()
		check(host.player_menu.visible, "Seeking an existing presentation cannot hide controls")
	# Queue/manual-next opens can replace a file while its toolbar is already visible.
	host.video.media.begin(19)
	host.video.local_uri = "file:///next.mp4"
	host.video._waiting_first = true
	host.video.panel.visible = false
	host._on_video_changed()
	check(not host.player_menu.visible, "Changing files defers an already-visible toolbar")
	ready(host, Geometry.Geometry.FISHEYE)
	check(host.player_menu.visible, "The replacement file reveals controls at its own first frame")
	opening(host, 20)
	host._show_player_menu()
	host._show_recent_menu()
	ready(host, Geometry.Geometry.FISHEYE)
	check(host.recent_menu.visible and not host.player_menu.visible, "Returning to the library cancels the pending control reveal")
	opening(host, 21)
	host._show_player_menu()
	host._toggle_player_menu()
	ready(host, Geometry.Geometry.FISHEYE)
	check(not host.player_menu.visible, "Menu toggle can cancel a requested startup reveal")
	opening(host, 22)
	host._show_player_menu()
	host.video.media.begin(23)
	host.video.local_uri = "file:///replacement.mp4"
	ready(host, Geometry.Geometry.FISHEYE)
	check(not host.player_menu.visible, "A late first frame cannot reveal controls for a different session")
	opening(host, 25)
	host._show_player_menu()
	host.video.close_video()
	host._update_player_menu_anchor()
	check(not host.player_menu.visible, "Closing a loading video cancels its pending reveal")
	opening(host, 26)
	host._show_player_menu()
	host.display.preview = false
	ready(host, Geometry.Geometry.FISHEYE)
	check(not host.player_menu.visible, "First frame waits for tracking before exposing a menu pose")
	host.display.preview = true
	host._update_player_menu_anchor()
	check(host.player_menu.visible, "Tracking recovery reveals the controls at the resolved pose")
	opening(host, 24)
	host._show_player_menu()
	host.video.media.state = "failed"
	host.video.media.error = "MPV_TEST_LOAD_FAILED"
	host.playback_feedback.tick()
	check(host.player_menu.visible and host.player_menu._quick_open == "info", "Failed loading still opens the actionable error panel")
	host.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Playback controls startup checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
