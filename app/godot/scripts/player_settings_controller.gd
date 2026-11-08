extends RefCounted
## Owns preference migration, persistence and setting dispatch.

var _host_ref: WeakRef
const Log := preload("res://scripts/diagnostic_log.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const Quality := preload("res://scripts/display_quality.gd")
const I18n := preload("res://scripts/i18n.gd")
const Background := preload("res://scripts/app_background.gd")
const PlatformMethods := preload("res://scripts/platform_methods.gd")

var settings := ConfigFile.new()
var settings_path := "user://player_settings.cfg"


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func load_preferences() -> void:
	var loaded := settings.load(settings_path)
	if loaded != OK:
		# Seed the fresh default now so any later settings save preserves it.
		settings.set_value(
			"controls", "pinch_hand", preload("res://scripts/hand_preferences.gd").DEFAULT
		)
	if preload("res://scripts/player_settings_migration.gd").apply(settings, loaded == OK):
		settings.save(settings_path)


func _restore_seek_settings() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.video.seek_mode = host.video.SeekPolicy.DEFAULT
	host.video.bookmark_seek_mode = host.video.SeekPolicy.GLOBAL


func _library_settings() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	return {
		"output_width": Quality.load_output_choice(host.settings),
		"show_fps": host.fps_overlay != null and host.fps_overlay.visible,
		"display_quality": host.display_quality,
		"refresh_rate":
		host.display.closest_refresh_rate(
			host.display.available_refresh_rates(), host.display.preferred_refresh_rate
		),
		"refresh_rates": host.display.available_refresh_rates(),
		"display_quality_pending":
		not is_equal_approx(
			host.display.render_scale, Quality.render_scale(host.display_quality, host.low_end_gpu)
		),
		"sharpness": Quality.load_sharpness(host.settings, host.low_end_gpu),
		"history": host.video.history_enabled,
		"pinch_hand": host.pinch_hand,
		"diagnostic_previous":
		(
			PlatformMethods.supports(host.video.platform, "diagnostic_previous_available")
			and host.video.platform.diagnostic_previous_available()
		),
		"reuse_last_mode": host.video.reuse_last_mode,
		"browse_memory": bool(host.settings.get_value("library", "browse_memory", true)),
		"controls_opacity": float(host.settings.get_value("ui", "controls_opacity", 0.86)),
		"window_height": host._presentation.window_height * 100.0,
		"reclining_mode": host.reclining_mode,
		"subtitle_distance": host.video.subtitle_distance,
		"subtitle_position": host.video.subtitle_position,
		"subtitle_direction": host.video.subtitle_direction,
		"background": host.background.choice if host.background else Background.DEFAULT_CHOICE,
		"background_yaw": host.background.yaw if host.background else 0.0,
		"background_brightness": host.background.brightness if host.background else 1.0,
		"background_loading": host.background.loading if host.background else false,
		"background_error": host.background.error if host.background else "",
		"version": str(ProjectSettings.get_setting("application/config/version", ""))
	}


func _on_setting_changed(key: String, value: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	match key:
		"window_height":
			if not (value is int or value is float) or not is_finite(float(value)):
				return
			host._presentation.set_window_height(float(value) / 100.0)
			host.settings.set_value("ui", "window_height", host._presentation.window_height)
			host.settings.save(host.settings_path)
		"save_diagnostic_log":
			if (
				value is bool
				and value
				and PlatformMethods.supports(host.video.platform, "save_diagnostic_log")
			):
				host.video.platform.save_diagnostic_log()
			else:
				host.recent_menu.status = "Diagnostic log could not be saved"
		"pinch_hand":
			if (
				not value is String
				or value not in preload("res://scripts/hand_preferences.gd").CHOICES
			):
				return
			host.pinch_hand = value
			for hand in host.hand_pointers:
				host.hand_pointers[hand].update({}, 0)
				host._cancel_pointer(hand)
			host.settings.set_value("controls", "pinch_hand", value)
			host.settings.save(host.settings_path)
		"controls_opacity":
			_on_playback_adjustment(key, value)
		"browse_memory":
			host.recent_menu.browse_memory.configure(bool(value), host.video.history_enabled)
			host.recent_menu._browse_restore = {}
			host.settings.set_value("library", "browse_memory", bool(value))
			host.settings.save(host.settings_path)
		"library_list_view":
			host.settings.set_value("library", "list_view", bool(value))
			host.settings.save(host.settings_path)
		"reclining_mode":
			host._set_reclining_mode(bool(value))
			host.settings.set_value("ui", "reclining_mode", host.reclining_mode)
			host.settings.save(host.settings_path)
		"file_editing":
			host.recent_menu.file_actions.set_enabled(bool(value))
			host.settings.set_value("library", "file_editing", bool(value))
			host.settings.save(host.settings_path)
		"library_orders":
			host.settings.set_value("library", "orders", value)
			host.settings.save(host.settings_path)
		"refresh_rate":
			if (
				not (value is int or value is float)
				or not host.display.set_refresh_preference(float(value))
			):
				return
			host.settings.set_value("display", "refresh_rate", host.display.preferred_refresh_rate)
			host.settings.save(host.settings_path)
			host.recent_menu.refresh()
		"display_quality":
			host.display_quality = clampi(int(value), Quality.AUTO, Quality.SCALES.size() - 1)
			# Apply at next startup: live OpenXR resizing fails to free GLES3 targets on Quest.
			host.settings.set_value("video", "display_quality", host.display_quality)
			host.settings.save(host.settings_path)
		"sharpness":
			host.video.sharpness = float(value)
			host.settings.set_value("video", "sharpness", host.video.sharpness)
			host.settings.save(host.settings_path)
		"background":
			if host.background.select(str(value)):
				host._save_background()
		"background_yaw":
			if value is bool:
				host.background.rotate_sky()
			else:
				host.background.set_yaw(float(value))
			host._save_background()
		"background_brightness":
			if value is bool:
				host.background.cycle_brightness()
			else:
				host.background.set_brightness(float(value))
			host._save_background()
		"show_fps":
			if host.fps_overlay:
				host.fps_overlay.set_shown(bool(value))
			host.settings.set_value("ui", "show_fps", bool(value))
			host.settings.save(host.settings_path)
			if host.player_menu and host.player_menu.visible:
				host.player_menu.refresh()
		"output_width":
			host.settings.set_value("video", "output_width", int(value))
			host.settings.save(host.settings_path)
			if host.platform_plugin:
				host.platform_plugin.set_mpv_output_width(
					Quality.output_width(
						Quality.load_output_choice(host.settings), host.low_end_gpu
					)
				)
		"reuse_last_mode":
			if not value is bool:
				return
			host.video.reuse_last_mode = value
			host.settings.set_value("video", "reuse_last_mode", value)
			host._capture_last_video_mode()
			host.settings.save(host.settings_path)
		"history":
			host.recent_menu.remember_browse()
			host.recent_menu.browse_memory.configure(
				host.recent_menu.browse_memory.enabled, bool(value)
			)
			host.video.history_enabled = bool(value)
			host.settings.set_value("library", "history", bool(value))
			host.settings.save(host.settings_path)
		"clear_history":
			host.recent_menu.browse_memory.clear()
			host.video.clear_history()
		"language":
			host.settings.set_value("ui", "language", str(value))
			host.settings.save(host.settings_path)
			I18n.use(str(value))
			if PlatformMethods.supports(host.platform_plugin, "set_ui_language"):
				host.platform_plugin.set_ui_language(I18n.choice)
			for menu in [host.recent_menu, host.player_menu]:
				if menu.visible:
					menu.refresh()
		"subtitle_distance":
			host.video.subtitle_distance = float(value)
			host.settings.set_value("subtitles", "distance", host.video.subtitle_distance)
			host.settings.save(host.settings_path)
		"subtitle_direction":
			host.video.subtitle_direction = int(value)
			host.settings.set_value("subtitles", "direction", host.video.subtitle_direction)
			host.settings.save(host.settings_path)
		"subtitle_position":
			host.video.subtitle_position = float(value)
			host.settings.set_value("subtitles", "elevation_degrees", host.video.subtitle_position)
			host.settings.save(host.settings_path)
	Log.record("setting_changed", {"key": key, "value": value})


func _on_mode_lock_changed(lock: Dictionary, media_kind: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.settings.set_value(media_kind, "mode_lock", lock)
	host.settings.save(host.settings_path)


func _save_background() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.settings.set_value("appearance", "background", host.background.choice)
	host.settings.set_value("appearance", "background_yaw", host.background.yaw)
	host.settings.set_value("appearance", "background_brightness", host.background.brightness)
	host.settings.save(host.settings_path)


func _on_playback_adjustment(key: String, value: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if key == "window_height":
		return  # Keep the slider stationary during its preview; commit on release.
	if key == "controls_opacity":
		host.video_menu.controls_opacity = clampf(float(value), 0, 1)
		host.settings.set_value("ui", "controls_opacity", host.video_menu.controls_opacity)
		host.settings.save(host.settings_path)
		if host.video_menu.visible:
			host.video_menu.refresh()
		return
	if host.screen_layout.adjust(key, value):
		return
	if key in ["subtitle_delay_ms", "audio_delay_ms"]:
		host.video.set_sync_delay(key, float(value))
		return
	if key in ["stereo_horizontal", "stereo_vertical"]:
		host.video.set_stereo_alignment(key, float(value))
		return
	elif key == "stereo_reset":
		host.video.reset_stereo_alignment()
		return
	elif key == "screen_distance":
		if host.video.geometry != Geometry.Geometry.FLAT or not is_finite(float(value)):
			return
		host._push_screen(
			(
				clampf(float(value), host.video.DISTANCE_LIMITS.x, host.video.DISTANCE_LIMITS.y)
				- host.video.panel.global_position.distance_to(host._eye())
			)
		)
		return
	elif key == "screen_scale":
		if host.video.geometry != Geometry.Geometry.FLAT or not is_finite(float(value)):
			return
		host.video.set_screen_scale(float(value) / 100.0)
		return
	elif key == "screen_rotation":
		host.video.set_screen_rotation(float(value))
		return
	elif key == "playback_speed":
		host.video.set_playback_speed(float(value))
		return
	elif key == "subtitle_encoding":
		host.video.set_subtitle_encoding(value)
		return
	elif key == "subtitle_palette":
		host.video.subtitle_palette = host.video.CaptionPalette.index(value)
	elif key == "subtitle_size":
		if not is_finite(float(value)):
			return
		host.video.subtitle_size = clampf(float(value) / 100.0, 0.5, 2.0)
	elif key == "subtitle_flat_position":
		if not is_finite(float(value)):
			return
		host.video.subtitle_flat_position = clampf(float(value) / 100.0, 0.0, 1.0)
	elif key == "subtitle_distance":
		host.video.subtitle_distance = float(value)
	elif key == "subtitle_position":
		host.video.subtitle_position = float(value)
	elif key == "grade_preset":
		host.video.color_grade.select(str(value))
	elif key == "grade_reset":
		host.video.color_grade.reset_custom()
	elif key == "grade_reset_fields":
		if not value is Array or not host.video.color_grade.reset_fields(value):
			return
	else:
		host.video.color_grade.adjust(key, value)
	host.video.color_grade.apply(host.video.material)


func _save_playback_adjustments() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.video.commit_sync()
	host.video.commit_stereo_view()
	host.screen_layout.save()
	host.settings.set_value("subtitles", "palette", host.video.subtitle_palette)
	host.settings.set_value("subtitles", "size", host.video.subtitle_size)
	host.settings.set_value("subtitles", "flat_position", host.video.subtitle_flat_position)
	host.settings.set_value("subtitles", "distance", host.video.subtitle_distance)
	host.settings.set_value("subtitles", "elevation_degrees", host.video.subtitle_position)
	host.settings.set_value("subtitles", "direction", host.video.subtitle_direction)
	host.settings.set_value("video", "color_grade", host.video.color_grade.snapshot())
	host.settings.save(host.settings_path)
