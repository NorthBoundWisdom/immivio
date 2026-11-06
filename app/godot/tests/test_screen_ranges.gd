extends SceneTree
const Presets := preload("res://scripts/screen_presets.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var video := preload("res://scripts/mpv_video_display.gd").new()
	root.add_child(video)
	video.set_screen_distance(0.01)
	video.set_screen_scale(0.01)
	assert(
		is_equal_approx(video.screen_distance, 0.1) and is_equal_approx(video.screen_scale, 0.05)
	)
	video.set_screen_distance(3.05)
	video.set_screen_scale(0.4)
	assert(video.screen_distance == 3.05 and video.screen_scale == 0.4)
	var span := Vector3(0.1, 50, 0.05)
	for value in [0.1, 1.0, 3.05, 24.0, 50.0]:
		assert(
			is_equal_approx(Presets.slider_value(Presets.slider_fraction(value, span), span), value)
		)
	var settings := ConfigFile.new()
	settings.set_value("ui", "library_distance", 9.0)
	settings.set_value("screen", "fixed", true)
	settings.set_value("screen", "distance", 3.05)
	settings.set_value("screen", "scale", 0.4)
	assert(preload("res://scripts/player_settings_migration.gd").apply(settings))
	assert(settings.get_value("ui", "library_distance") == 4.0)
	assert(
		(
			settings.get_value("screen", "distance") == 3.05
			and settings.get_value("screen", "scale") == 0.4
		)
	)
	assert(not preload("res://scripts/player_settings_migration.gd").apply(settings))
	video.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
