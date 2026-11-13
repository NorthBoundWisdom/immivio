extends SceneTree
const Log := preload("res://scripts/diagnostic_log.gd")


class ReportPlatform:
	extends RefCounted
	signal mpv_debug_command(id: int, payload: String)
	signal mpv_pixel_mask(id: int, payload: String)
	var reports: Array[Dictionary] = []

	func save_mpv_player_report(id: int, payload: String) -> void:
		reports.append({"id": id, "data": JSON.parse_string(payload)})


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	_check_report_provider()
	_check_without_diagnostics()
	_check_shutdown_guard()
	var cleaned: Dictionary = Log.clean(
		{
			"username": "person",
			"nested": {"token": "secret", "url": "https://user:pass@host/video?signature=bad"}
		}
	)
	var encoded := JSON.stringify(cleaned)
	for secret in ["person", "secret", "signature=bad", "user:pass"]:
		assert(not encoded.contains(secret))
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	var seeded := FileAccess.open(Log.EVENT_PATH, FileAccess.WRITE)
	seeded.store_line(
		JSON.stringify({"event": "legacy", "details": "x".repeat(Log.MAX_BYTES - 100)})
	)
	seeded.close()
	Log.record("synthetic", {"text": "x".repeat(2048)})
	assert(
		not Log.safe_text('{"Cookie":"session=hidden","password":"hello world"}').contains("hidden")
	)
	assert(FileAccess.file_exists("user://diagnostics/events.1.jsonl"))
	var file := FileAccess.open(Log.EVENT_PATH, FileAccess.READ)
	assert(file.get_length() <= Log.MAX_BYTES)
	file.close()
	var menu := preload("res://scripts/library_menu.gd").new()
	root.add_child(menu)
	var actions: Array = []
	menu.setting_changed.connect(func(key, value): actions.append([key, value]))
	menu.test_choose({"save_diagnostic_log": true})
	assert(menu.diagnostic_confirmation and actions.is_empty())
	menu.test_choose({"cancel_diagnostic_save": true})
	assert(not menu.diagnostic_confirmation and actions.is_empty())
	menu.test_choose({"confirm_diagnostic_save": true})
	assert(actions.is_empty())
	menu.test_choose({"save_diagnostic_log": true})
	menu.test_choose({"confirm_diagnostic_save": true})
	assert(actions == [["save_diagnostic_log", true]])
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)


func _check_report_provider() -> void:
	var video := preload("res://scripts/mpv_video_display.gd").new()
	root.add_child(video)
	video.set_process(false)
	var platform := ReportPlatform.new()
	video.platform = platform
	video.diagnostics.connect_platform(platform)
	video.diagnostics.request = 42
	video.diagnostics.write_report()
	assert(platform.reports.back().data.canvas_controls.is_empty())
	var menu := preload("res://scripts/player_menu.gd").new()
	menu.state_provider = func(): return {"position_ms": 12000, "duration_ms": 60000}
	root.add_child(menu)
	menu.visible = true
	menu.refresh()
	var host := preload("res://scripts/main.gd").new()
	host.video = video
	host.player_menu = menu
	host.selected_features_probe_result = {"state": "fixture"}
	video.diagnostic_ui_provider = host.presentation_coordinator.diagnostic_ui_snapshot
	video.diagnostics.write_report()
	var report: Dictionary = platform.reports.back().data
	assert(report.player_menu_progress.position_ms == 12000)
	assert(report.player_menu_progress.duration_ms == 60000)
	assert(report.selected_features_ui == {"state": "fixture"})
	assert(report.canvas_controls.has("timeline_centre"))
	report.selected_features_ui.state = "changed"
	assert(host.selected_features_probe_result.state == "fixture")
	menu.visible = false
	assert(menu.progress_snapshot().is_empty())
	host.free()
	video.diagnostics.write_report()
	assert(platform.reports.back().data.canvas_controls.is_empty())
	platform.mpv_debug_command.emit(43, '{"operation":"observe"}')
	assert(platform.reports.back().id == 43)
	menu.free()
	video.free()
	assert(platform.get_signal_connection_list("mpv_debug_command").is_empty())
	assert(platform.get_signal_connection_list("mpv_pixel_mask").is_empty())


func _check_shutdown_guard() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var queried: Array = []
	var coordinator := preload("res://scripts/playback_coordinator.gd").new(
		host,
		func():
			queried.append(true)
			return true
	)
	coordinator._on_video_changed()
	assert(queried == [true])
	host.free()
	coordinator._on_video_changed()
	assert(queried == [true])


func _check_without_diagnostics() -> void:
	var video := preload("res://scripts/mpv_video_display.gd").new(false)
	root.add_child(video)
	video.set_process(false)
	assert(video.diagnostics == null)
	video.platform = preload("res://tests/test_file_mode_memory.gd").Host.new()
	assert(video.open_local("file:///diagnostic-disabled.mp4", "Disabled", 0, false))
	video.close_video()
	assert(video.media.state == "closed")
	video.free()
