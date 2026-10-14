extends SceneTree
const Quality := preload("res://scripts/display_quality.gd")
const Main := preload("res://scripts/main.gd")


class HostProbe:
	extends RefCounted
	var requests: Array[bool] = []

	func finish_app(restart: bool) -> void:
		requests.append(restart)


var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings := ConfigFile.new()
	check(Quality.load_quality(settings) == Quality.AUTO, "Default quality is auto")
	check(
		(
			Quality.render_scale(Quality.AUTO, false) == 1.1
			and Quality.render_scale(Quality.AUTO, true) == 1.0
		),
		"Auto quality: Enhanced, or Standard on low end"
	)
	check(Quality.render_scale(2, true) == 1.25, "Explicit quality is respected on low end")
	check(Quality.load_sharpness(settings) == 0.2, "Default sharpness is gentle")
	for adapter in ["Adreno (TM) 650", "Adreno (TM) 540"]:
		check(Quality.is_low_end_gpu(adapter), "XR2 Gen1 class is low end: " + adapter)
	for adapter in ["Adreno (TM) 740", "Adreno (TM) 830", "NVIDIA GeForce RTX 3060", ""]:
		check(not Quality.is_low_end_gpu(adapter), "Not low end: " + adapter)
	check(Quality.load_sharpness(settings, true) == 0.0, "Low-end devices default to no sharpening")
	check(
		Quality.load_output_choice(settings) == Quality.AUTO_OUTPUT, "Output width defaults to auto"
	)
	check(
		(
			Quality.output_width(Quality.AUTO_OUTPUT, true) == 4096
			and Quality.output_width(Quality.AUTO_OUTPUT, false) == 0
		),
		"Auto output follows tier"
	)
	check(
		Quality.output_width(0, true) == 0 and Quality.output_width(5760, true) == 5760,
		"Explicit output width is respected"
	)
	var explicit := ConfigFile.new()
	explicit.set_value("video", "output_width", 0)
	explicit.set_value("video", "sharpness", 0.4)
	check(
		Quality.load_output_choice(explicit) == 0 and Quality.load_sharpness(explicit, true) == 0.4,
		"Saved choices override tier defaults"
	)
	explicit.set_value("video", "output_width", 1234)
	check(
		Quality.load_output_choice(explicit) == Quality.AUTO_OUTPUT,
		"Unknown output width falls back to auto"
	)
	var path := "user://quality_test_%d.cfg" % Time.get_ticks_usec()
	settings.set_value("appearance", "background", "dark")
	settings.save(path)
	var main := Main.new()
	main.settings_path = path
	root.add_child(main)
	check(
		(
			main.get_viewport().msaa_3d == Viewport.MSAA_2X
			and main.display.capabilities().viewport_msaa_3d == Viewport.MSAA_2X
		),
		"Default eye-buffer geometry uses 2x MSAA and reports the active viewport setting"
	)
	main.display.set_flat_surface_visible(true)
	check(
		main.get_viewport().msaa_3d == Viewport.MSAA_4X,
		"Enhanced flat screens use 4x MSAA for rectangular edges"
	)
	main.display.set_flat_surface_visible(false)
	check(
		main.get_viewport().msaa_3d == Viewport.MSAA_2X,
		"Immersive playback restores the lighter default MSAA"
	)
	main.recent_menu.section = main.recent_menu.Section.SETTINGS
	main.recent_menu.tab = main.recent_menu.DISPLAY_TAB
	main.recent_menu.refresh()
	check(
		(
			main.recent_menu.rows.size() == 3
			and main.recent_menu.rows[0].choices.size() == 4
			and main.recent_menu.rows[0].choices[0].value == Quality.AUTO
			and main.recent_menu.rows[1].choices.size() == 4
			and main.recent_menu.rows[2].key == "show_fps"
		),
		"Quality and sharpness each occupy one field with all their choices, followed by the FPS display"
	)
	main._on_setting_changed("display_quality", 2)
	main._on_setting_changed("sharpness", 0.4)
	check(
		not bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/dynamic_resolution", true)),
		"Runtime cannot silently lower chosen video/menu render quality"
	)
	check(
		(
			main.display.capabilities().meta_dynamic_resolution_enabled == false
			and main.display.capabilities().render_target_size_scope == "allocated_eye_buffer"
		),
		"Diagnostics distinguish allocated buffers from dynamic render regions"
	)
	check(main.display.render_scale == 1.1, "Quality keeps current XR targets until restart")
	check(main.get_viewport().msaa_3d == Viewport.MSAA_2X, "MSAA quality also waits for restart")
	check(main._library_settings().display_quality_pending, "Pending quality is visible")
	check(
		main.video.sharpness == 0.4 and main.photo.sharpness == 0.4,
		"Sharpness applies to both media types"
	)
	check(
		main.photo._detail_material.get_shader_parameter("sharpness") == 0.4,
		"Photo magnifier matches"
	)
	settings.load(path)
	check(
		Quality.load_quality(settings) == 2 and Quality.load_sharpness(settings) == 0.4,
		"Settings persist"
	)
	main._on_setting_changed("sharpness", 0.0)
	check(
		main.video.material.get_shader_parameter("sharpness") == 0.0, "Off restores neutral shader"
	)
	var host := HostProbe.new()
	main.platform_plugin = host
	main.recent_menu._activate(main.recent_menu.RESTART_APP)
	main.recent_menu._activate(main.recent_menu.RESTART_APP)
	check(host.requests == [true], "Restart button calls Android once and saves settings")
	main.platform_plugin = null
	main.queue_free()
	await process_frame
	main = Main.new()
	main.settings_path = path
	root.add_child(main)
	check(main.display.render_scale == 1.25, "Restart applies saved quality globally")
	check(
		main.get_viewport().msaa_3d == Viewport.MSAA_4X,
		"High quality applies 4x geometry MSAA after restart"
	)
	check(not main._library_settings().display_quality_pending, "Restart clears pending label")
	check(
		not main.low_end_gpu and main.video.sharpness == 0.0,
		"Desktop renderer is not low end and keeps the saved sharpness"
	)
	main.platform_plugin = host
	main.recent_menu._activate(main.recent_menu.QUIT_APP)
	check(host.requests == [true, false], "Close button requests actual application exit")
	main.platform_plugin = null
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	var fresh_path := "user://quality_low_end_%d.cfg" % Time.get_ticks_usec()
	var fresh := ConfigFile.new()
	fresh.set_value("appearance", "background", "dark")
	fresh.save(fresh_path)
	main = Main.new()
	main.settings_path = fresh_path
	main.gpu_adapter = "Adreno (TM) 650"
	root.add_child(main)
	check(
		(
			main.display.render_scale == 1.0
			and main._library_settings().display_quality == Quality.AUTO
			and not main._library_settings().display_quality_pending
		),
		"Low-end tier starts at Standard through auto quality"
	)
	check(
		main.low_end_gpu and main.video.sharpness == 0.0 and main.photo.sharpness == 0.0,
		"Low-end tier starts without sharpening"
	)
	check(
		(
			main._library_settings().output_width == Quality.AUTO_OUTPUT
			and main._library_settings().sharpness == 0.0
		),
		"Menu shows auto output and sharpness off"
	)
	main.recent_menu.section = main.recent_menu.Section.SETTINGS
	main.recent_menu.tab = main.recent_menu.VIDEO_TAB
	main.recent_menu.refresh()
	var resolution: Array = main.recent_menu.rows.filter(
		func(row): return row.get("key", "") == "output_width"
	)
	check(
		(
			resolution.size() == 1
			and resolution[0].value == Quality.AUTO_OUTPUT
			and resolution[0].choices[0].value == Quality.AUTO_OUTPUT
		),
		"Resolution offers auto first"
	)
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(fresh_path)
	for failure in failures:
		push_error(failure)
	print("Global display quality: ", "passed" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
