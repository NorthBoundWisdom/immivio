extends SceneTree
const Detection := preload("res://scripts/stereo_detection.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


static func eye(seed_value: int) -> Image:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var image := Image.create(96, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 96:
			var value := .1 + .8 * random.randf()
			image.set_pixel(x, y, Color(value, value * .9, value * .8))
	return image


static func packed(stacked: bool, unrelated: bool = false) -> Image:
	var left := eye(73)
	var right := eye(972) if unrelated else left.duplicate() as Image
	if not unrelated:
		for y in 128:
			for x in 96:
				var offset := 2 if y < 64 else 4
				var colour := left.get_pixel(clampi(x + offset, 0, 95), y)
				right.set_pixel(x, y, colour * .9 + Color(.025, .025, .025, 0))
	var image := Image.create(
		96 if stacked else 192, 256 if stacked else 128, false, Image.FORMAT_RGB8
	)
	image.blit_rect(left, Rect2i(0, 0, 96, 128), Vector2i.ZERO)
	image.blit_rect(right, Rect2i(0, 0, 96, 128), Vector2i(0, 128) if stacked else Vector2i(96, 0))
	image.resize(192, 108, Image.INTERPOLATE_BILINEAR)
	return image


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var side := Detection.classify(packed(false))
	var stacked := Detection.classify(packed(true))
	check(
		side.layout == "sbs", "Unmarked SBS is recognized from correlated eye images with disparity"
	)
	check(stacked.layout == "tb", "Unmarked top-bottom is recognized independently of frame shape")
	check(
		Detection.classify(packed(false, true)).layout.is_empty(),
		"Unrelated left/right content is not stereo"
	)
	check(
		Detection.classify(packed(true, true)).layout.is_empty(),
		"Unrelated top/bottom content is not stereo"
	)
	var blank := Image.create(192, 108, false, Image.FORMAT_RGB8)
	blank.fill(Color.BLACK)
	check(not Detection.classify(blank).usable, "Black opening frames are inconclusive")
	for y in 108:
		for x in 192:
			var value := float(y) / 108.0
			blank.set_pixel(x, y, Color(value, value, value))
	check(
		Detection.classify(blank).layout.is_empty(),
		"A smooth shared gradient cannot create a false stereo match"
	)
	var detector := Detection.new()
	detector.begin(true)
	var token := detector.started(1)
	check(detector.accept(token, side).is_empty(), "One sample cannot change the layout")
	detector.started(2)
	check(
		detector.accept(token, side) == "sbs" and not detector.pending,
		"Two consistent samples resolve SBS once"
	)
	detector.begin(true)
	token = detector.started(2)
	detector.accept(token, side)
	detector.due_ms = 0
	check(
		not detector.wants(2) and detector.wants(2, true),
		"A paused frame can be rechecked without starting playback"
	)
	detector.started(2)
	check(
		detector.accept(token, side) == "sbs", "Still-frame re-detection reaches a bounded decision"
	)
	detector.begin(true)
	token = detector.started(3)
	detector.cancel()
	check(
		detector.accept(token, side).is_empty(), "A cancelled or previous-file result cannot apply"
	)
	detector.begin(true)
	token = detector.started(4)
	detector.accept(token, {})
	check(
		detector.pending and detector.samples == 0,
		"Black frames do not consume the informative sample budget"
	)
	for frame_id in range(5, 16):
		detector.started(frame_id)
		detector.accept(token, {})
	check(not detector.pending, "Repeated inconclusive captures stop at the bounded budget")
	var worker := Thread.new()
	check(
		worker.start(Detection.classify.bind(packed(false))) == OK,
		"Frame matching can run outside the render thread"
	)
	var threaded: Dictionary = worker.wait_to_finish()
	check(threaded.layout == "sbs", "The worker uses the same content classifier")
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	video.platform = preload("res://tests/test_file_mode_memory.gd").Host.new()
	video.mode_memory.directory = "user://auto_stereo"
	video.mode_memory.entries.clear()
	check(
		video.open_local("file:///unmarked.mp4", "unmarked.mp4"),
		"Fresh unmarked video opens normally"
	)
	video.media.format = {"width": 4096, "height": 2048}
	video._complete_layout()
	check(
		not video.stereo_sbs and video._auto_stereo,
		"Ambiguous dimensions await content instead of asserting stereo"
	)
	token = video._stereo_detection.started(1)
	video._accept_stereo_detection(token, side)
	video._stereo_detection.started(2)
	video._accept_stereo_detection(token, side)
	check(
		video.stereo_sbs and not video.top_bottom and video.geometry == 0,
		"Content detection enables SBS without guessing an immersive projection"
	)
	check(
		video.mode_memory.lookup(video.local_uri).layout_auto,
		"Automatic modes retain their provenance in per-file memory"
	)
	video.open_local("file:///another.mp4", "another.mp4")
	video.media.format = {"width": 1920, "height": 1080}
	video._complete_layout()
	token = video._stereo_detection.started(3)
	video._accept_stereo_detection(token, side)
	video.set_stereo_layout(0)
	video._accept_stereo_detection(token, side)
	check(
		not video.stereo_sbs and not video._auto_stereo,
		"An explicit 2D choice cancels pending detection even when already in 2D"
	)
	video.open_local("file:///another.mp4", "another.mp4")
	check(not video._auto_stereo, "Remembered manual 2D survives reopening")
	video.enable_auto_stereo()
	check(video._auto_stereo, "Auto detect explicitly re-enables analysis for a remembered file")
	video.set_projection(1)
	video.enable_auto_stereo()
	check(video.geometry == 1, "Re-detecting the stereo layout preserves the selected projection")
	video.media.format = {"width": 1920, "height": 1080}
	video.swap_eyes = true
	token = video._stereo_detection.started(10)
	video._accept_stereo_detection(token, stacked)
	video._stereo_detection.started(11)
	video._accept_stereo_detection(token, stacked)
	check(
		video.stereo_sbs and video.top_bottom and video.geometry == 1,
		"Re-detection can correct an already-stereo fallback axis without changing projection"
	)
	check(video.swap_eyes, "Content matching does not invent or reset the user's eye order")
	video.open_local("file:///ordinary_2D.mp4", "ordinary_2D.mp4")
	video.media.format = {"width": 4096, "height": 2048}
	video._complete_layout()
	check(
		not video.stereo_sbs and not video._stereo_detection_busy,
		"Explicit 2D filenames remain mono"
	)
	video.open_local("file:///wide_unmarked.mp4", "wide_unmarked.mp4")
	video.set_stereo_layout(0)
	video.media.format = {"width": 3840, "height": 1080}
	video._complete_layout()
	check(
		not video.stereo_sbs and video._layout_pending == null,
		"Manual 2D before the first frame defeats both shape and content inference"
	)
	video.open_local("file:///old_session.mp4", "old_session.mp4")
	token = video._stereo_detection.started(1)
	video._accept_stereo_detection(token, side)
	video.open_local("file:///new_session.mp4", "new_session.mp4")
	video._accept_stereo_detection(token, side)
	check(not video.stereo_sbs, "A previous file's delayed result cannot change a new file")
	video.open_local("file:///locked_before_frame.mp4", "locked_before_frame.mp4")
	video.toggle_mode_lock()
	video.media.format = {"width": 3840, "height": 1080}
	video._complete_layout()
	check(
		not video.stereo_sbs and not video._auto_stereo,
		"Locking the current 2D tile before the first frame prevents automatic overrides"
	)
	var menu := preload("res://scripts/player_menu.gd").new()
	root.add_child(menu)
	menu.visible = true
	menu._mode_open = true
	menu.refresh()
	var actions: Array = []
	menu.action_requested.connect(func(action): actions.append(action))
	var buttons: Array = menu.controls_snapshot().filter(
		func(button): return button.target == menu.MODE_STEREO + 7
	)
	check(buttons.size() == 1, "The video-mode popup exposes Auto detect")
	if not buttons.is_empty():
		var button: Dictionary = buttons[0]
		var origin: Vector3 = button.node.global_position + button.node.global_basis.z
		var direction: Vector3 = -button.node.global_basis.z
		menu.press_pointer("right_hand", origin, direction, true)
		menu.release_pointer("right_hand", origin, direction, true)
		check(
			actions == ["stereo_auto"],
			"A real ray click requests re-detection rather than a mode lock"
		)
	menu.free()
	video.free()
	for failure in failures:
		push_error(failure)
	print("Stereo detection: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
