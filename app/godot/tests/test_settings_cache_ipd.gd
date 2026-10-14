extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
const Main := preload("res://scripts/main.gd")
const Host := preload("res://tests/test_player_menu.gd").Host
const Memory := preload("res://scripts/file_mode_memory.gd")
var checks := 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var directory := ProjectSettings.globalize_path(
		"res://../../build/output/settings-cache-ipd-test/%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(directory)
	var state: Dictionary = Warmup.STATE.duplicate(true)
	var menu := Menu.new()
	root.add_child(menu)
	menu.set_process(false)
	menu.visible = true
	menu.state_provider = func(): return state
	menu.refresh()
	var plane := menu.global_transform
	for target in [
		Menu.QUICK_SPEED,
		Menu.QUICK_COLOR,
		Menu.SYNC_SETTINGS,
		Menu.QUEUE_SETTINGS,
		12,
		Menu.IPD_SETTINGS
	]:
		menu._activate(target)
		check(
			menu.section == 0 and menu.global_transform.is_equal_approx(plane),
			"Popup switches preserve the toolbar plane"
		)
		check(
			menu._adjustment.is_empty() and not menu._quick_open.is_empty(),
			"One popup replaces the standalone settings page"
		)
	menu._activate(Menu.QUICK_CLOSE)
	state.stereo = false
	menu.refresh()
	check(
		not menu._buttons.any(func(button): return button.target == Menu.IPD_SETTINGS),
		"Unavailable mono IPD button is omitted"
	)
	menu.free()
	var main := Main.new()
	main.settings_path = directory.path_join("settings.cfg")
	var settings := ConfigFile.new()
	settings.set_value("appearance", "background", "dark")
	settings.save(main.settings_path)
	root.add_child(main)
	main.set_process(false)
	main.report_timer.stop()
	main.menu_compositor.set_process(false)
	main.video.set_process(false)
	main.photo.set_process(false)
	var video: Node3D = main.video
	var host := Host.new()
	video.platform = host
	video.mode_memory = Memory.new(directory.path_join("modes"))
	video.recent_files = preload("res://scripts/recent_files.gd").new(directory.path_join("recent"))
	video.open_local("file:///synthetic180_SBS_180.mp4", "synthetic180_SBS_180.mp4")
	video.stereo_sbs = true
	video.geometry = 1
	video.media.format = {"width": 3840, "height": 1920}
	video._apply_geometry()
	main._show_player_menu()
	main.player_menu._activate(main.player_menu.IPD_SETTINGS)
	var before := host.calls.size()
	var session: int = video.media.session_id
	main._on_playback_adjustment("stereo_horizontal", 1.25)
	main._on_playback_adjustment("stereo_vertical", -.15)
	main._save_playback_adjustments()
	check(
		video.media.session_id == session and host.calls.size() == before,
		"IPD calibration never reopens decoder or inference"
	)
	check(
		video.material.get_shader_parameter("stereo_offset").is_equal_approx(
			Vector2(.0125, -.0015)
		),
		"IPD controls reach the displayed per-eye coordinates"
	)
	video.open_local("file:///other_SBS_180.mp4", "other_SBS_180.mp4")
	check(
		video.stereo_horizontal == 0 and video.stereo_vertical == 0,
		"A different video never inherits another video's compensation"
	)
	video.open_local("file:///synthetic180_SBS_180.mp4", "synthetic180_SBS_180.mp4")
	check(
		(
			is_equal_approx(video.stereo_horizontal, 1.25)
			and is_equal_approx(video.stereo_vertical, -.15)
		),
		"Reopening restores that video's IPD compensation"
	)
	main._on_playback_adjustment("stereo_reset", true)
	check(
		video.stereo_horizontal == 0 and video.stereo_vertical == 0,
		"IPD reset restores neutral stereo"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Settings cache and IPD: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
