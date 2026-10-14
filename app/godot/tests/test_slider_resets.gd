extends SceneTree
const Main := preload("res://scripts/main.gd")
const Grade := preload("res://scripts/color_grade.gd")
const Menu := preload("res://scripts/player_menu.gd")
const PhotoMenu := preload("res://scripts/photo_menu.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
var checks := 0
var failures: Array[String] = []
var commits := 0

class Host extends "res://tests/test_player_menu.gd".Host:
	func set_mpv_sync(_id: int, _subtitle: int, _audio: int) -> bool: return true

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: _run.call_deferred()

func button(menu: Node3D, target: int) -> Dictionary:
	for item in menu._buttons:
		if item.target == target: return item
	return {}

func reset_target(menu: Node3D, key: String) -> int:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.kind == "reset" and item.key == key: return target
	return -1

func tap(menu: Node3D, target: int) -> void:
	var item := button(menu, target)
	check(not item.is_empty() and item.get("enabled", false), "Reset target is available: %d" % target)
	if item.is_empty() or not item.enabled: return
	var origin: Vector3 = item.node.to_global(Vector3(0, 0, 1))
	check(menu.ray_hit(origin, -menu.global_basis.z).get("target", -1) == target, "Reset has a separate ray target")
	menu.press_pointer("right", origin, -menu.global_basis.z, true)
	menu.release_pointer("right", origin, -menu.global_basis.z, true)

func _run() -> void:
	check(Grade.PRESETS == ["Original", "Warm", "Cool", "Custom"], "Only four distinct color presets remain")
	var legacy := Grade.new()
	legacy.restore({"preset": "Daylight", "custom": {"exposure": 0.75, "red_gain": 1.2}})
	check(legacy.preset == "Original" and legacy.values() == Grade.DEFAULTS, "Legacy Daylight becomes the Original bypass")
	var saved := legacy.snapshot()
	var config := ConfigFile.new(); config.set_value("video", "color_grade", saved)
	var restored := ConfigFile.new(); restored.parse(config.encode_to_text())
	legacy.restore(restored.get_value("video", "color_grade")); legacy.select("Custom")
	check(legacy.custom.exposure == 0.75 and is_equal_approx(legacy.custom.red_gain, 1.2), "Daylight migration retains custom parameters through save and reload")
	var before := legacy.snapshot()
	check(not legacy.reset_fields(["exposure", "unknown"]) and legacy.snapshot() == before, "Invalid reset requests cannot partially modify grading")

	var directory := ProjectSettings.globalize_path("res://../../build/output/slider-resets/%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var main := Main.new(); main.settings_path = directory.path_join("settings.cfg"); root.add_child(main)
	main.set_process(false); main.report_timer.stop(); main.photo.set_process(false); main.video.set_process(false)
	main.recent_menu.dismiss()
	var video: Node3D = main.video
	video.platform = Host.new(); video.mode_memory = Memory.new(directory.path_join("modes"))
	video.recent_files = preload("res://scripts/recent_files.gd").new(directory.path_join("recent"))
	video.open_local("file:///slider-reset_SBS.mp4", "slider-reset_SBS.mp4")
	video.stereo_sbs = true; video._apply_geometry()
	main._show_player_menu()
	var menu: Node3D = main.player_menu; menu.set_process(false)
	menu.adjustment_committed.connect(func(): commits += 1)
	menu._activate(Menu.QUICK_COLOR)
	for page in menu.PlaybackPopups.GRADE_PAGES.size():
		for key in Grade.DEFAULTS:
			var span := Grade.limits(key)
			video.color_grade.adjust(key, span.y)
		menu._grade_page = page; menu.refresh()
		var expected: Dictionary = video.color_grade.values()
		for key in menu.PlaybackPopups.GRADE_PAGES[page]: expected[key] = Grade.DEFAULTS[key]
		var saves := commits
		tap(menu, menu.PlaybackPopups.GRADE_PAGE_RESET)
		check(video.color_grade.values() == expected and commits == saves + 1, "Reset page affects only the three visible fields and commits once: %d" % page)
		var stored := ConfigFile.new(); stored.load(main.settings_path)
		check(stored.get_value("video", "color_grade").custom == expected, "Page reset persists the displayed result")
		check(not button(menu, menu.PlaybackPopups.GRADE_PAGE_RESET).enabled, "An already-default page cannot reset again")
	video.color_grade.adjust("red_offset", 0.1)
	menu._grade_page = 0; menu.refresh()
	var exposure_reset := reset_target(menu, "exposure")
	tap(menu, exposure_reset)
	check(video.color_grade.values().exposure == 0.0 and is_equal_approx(video.color_grade.values().red_offset, 0.1), "A color slider reset preserves the other pages")
	tap(menu, 440)
	check(video.color_grade.values() == Grade.DEFAULTS, "Reset custom still resets the complete custom look")
	video.color_grade.adjust("exposure", 1.0); menu.refresh_values()
	check(button(menu, reset_target(menu, "exposure")).enabled and button(menu, menu.PlaybackPopups.GRADE_PAGE_RESET).node.visible, "Live changes enable resets without reopening the popup")
	# Choice resets obey the same release ownership as presets, without previewing on press.
	var item := button(menu, reset_target(menu, "exposure"))
	var origin: Vector3 = item.node.to_global(Vector3(0, 0, 1))
	menu.press_pointer("right", origin, -menu.global_basis.z, true)
	menu.release_pointer("left", origin, -menu.global_basis.z, true)
	check(video.color_grade.values().exposure == 1.0, "Another hand cannot release a pending reset")
	menu.cancel_pointer("right")
	menu.release_pointer("right", origin, -menu.global_basis.z, true)
	check(video.color_grade.values().exposure == 1.0, "Cancelled reset leaves the value intact")

	video.set_stereo_alignment("stereo_horizontal", 1.25); video.set_stereo_alignment("stereo_vertical", -0.5)
	video.swap_eyes = true; menu._activate(Menu.IPD_SETTINGS)
	tap(menu, reset_target(menu, "stereo_horizontal"))
	check(video.stereo_horizontal == 0 and video.stereo_vertical == -0.5 and video.swap_eyes and video.viewing_eye == 0, "Horizontal reset preserves vertical correction and viewing choices")
	check(video.mode_memory.lookup(video.local_uri).stereo_horizontal == 0, "Individual alignment reset is saved for this video")
	video.set_sync_delay("audio_delay_ms", 500); video.set_sync_delay("subtitle_delay_ms", -250)
	menu._activate(Menu.SYNC_SETTINGS)
	tap(menu, reset_target(menu, "audio_delay_ms"))
	check(video.audio_delay_ms == 0 and video.subtitle_delay_ms == -250, "Timing reset changes only the selected delay")
	video.subtitle_size = 1.5; video.subtitle_flat_position = 0.25
	menu._activate(110)
	tap(menu, reset_target(menu, "subtitle_size"))
	check(video.subtitle_size == 1.0 and video.subtitle_flat_position == 0.25, "Flat caption size resets independently of its position")
	video.geometry = 1; video.subtitle_distance = 8; video.subtitle_position = 20; menu.refresh()
	tap(menu, reset_target(menu, "subtitle_distance"))
	check(video.subtitle_distance == 5 and video.subtitle_position == 20, "Projected caption distance resets without moving its angle")
	menu.dismiss()
	main.recent_menu.section = main.recent_menu.Section.SETTINGS; main.recent_menu.tab = main.recent_menu.SUBTITLES_TAB
	main.recent_menu.toggle()
	tap(main.recent_menu, reset_target(main.recent_menu, "subtitle_position"))
	check(video.subtitle_position == 0, "Library subtitle settings use the same independent reset")
	main.recent_menu.dismiss()

	main.photo_active = true; main.player_menu = main.photo_menu
	var photo: Node3D = main.photo
	var image := Image.create(128, 64, false, Image.FORMAT_RGB8); image.fill(Color.WHITE)
	photo._texture = ImageTexture.create_from_image(image); photo._size = Vector2(128, 64)
	photo.material.set_shader_parameter("photo_texture", photo._texture)
	photo._apply_geometry(); photo.panel.visible = true; main._place_screen()
	photo.set_screen_scale(2); photo.set_inspect_magnification(4)
	menu = main.photo_menu; menu.set_process(false); menu.toggle(); menu._activate(PhotoMenu.PHOTO_ADJUST)
	tap(menu, Menu.SLIDER_RESET_BASE + 451)
	check(photo.screen_scale == 1 and photo.inspect_magnification == 4 and not photo.inspect, "Photo size reset preserves magnification and does not open an effect")
	var photo_stored := ConfigFile.new(); photo_stored.load(main.settings_path)
	check(photo_stored.get_value("photo_screen", "scale") == 1.0, "Photo reset persists immediately")
	photo.set_projection(3); menu.refresh_values()
	var pose: Transform3D = photo.panel.global_transform
	menu._activate(Menu.SLIDER_RESET_BASE + 450)
	check(not button(menu, Menu.SLIDER_RESET_BASE + 450).enabled and photo.panel.global_transform == pose, "Disabled panorama distance reset cannot move the image")
	tap(menu, Menu.SLIDER_RESET_BASE + 452)
	check(photo.inspect_magnification == 2 and not photo.inspect, "Magnification reset does not enable the magnifier")
	check(not video.depth_requested and not photo.depth_requested and not video.auto_depth and not photo.auto_depth, "All resets leave retired 3D effects off")
	var gallery_state := {"has_image": true, "count": 5, "layout": 2, "gallery_focus": -1,
		"gallery_scale": 1.5, "gallery_distance": 7.0, "wall_rows": 3}
	var gallery_menu := PhotoMenu.new(); gallery_menu.state_provider = func(): return gallery_state
	gallery_menu.adjustment_requested.connect(func(key, value): gallery_state[key] = value)
	root.add_child(gallery_menu); gallery_menu.set_process(false); gallery_menu.toggle(); gallery_menu._activate(PhotoMenu.PHOTO_ADJUST)
	tap(gallery_menu, Menu.SLIDER_RESET_BASE + 451)
	check(gallery_state.gallery_distance == 4.0 and gallery_state.gallery_scale == 1.5 and gallery_state.wall_rows == 3, "Photo wall resets to its own 4m default without changing scale or rows")
	tap(gallery_menu, Menu.SLIDER_RESET_BASE + 452)
	check(gallery_state.wall_rows == 1, "Wall rows restore independently to one row")
	gallery_state.layout = 3; gallery_state.gallery_distance = 7.0; gallery_menu.refresh()
	tap(gallery_menu, Menu.SLIDER_RESET_BASE + 451)
	check(is_equal_approx(gallery_state.gallery_distance, 3.6), "Memory fragments use their distinct 3.6m default")
	gallery_state.count = 0; gallery_menu.refresh()
	check(not button(gallery_menu, Menu.SLIDER_RESET_BASE + 450).enabled, "Empty galleries disable their reset actions")
	gallery_menu.queue_free()
	main.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("Slider reset regression: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
