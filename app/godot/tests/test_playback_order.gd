extends SceneTree


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var menu := preload("res://scripts/player_menu.gd").new()
	root.add_child(menu)
	var host := preload("res://scripts/main.gd").new()
	host.video = preload("res://scripts/mpv_video_display.gd").new()
	host.playback_queue = preload("res://scripts/playback_queue.gd").new()
	host.playback_queue.replace(
		[{"uri": "file:///a.mp4", "title": "A"}, {"uri": "file:///b.mp4", "title": "B"}]
	)
	host.video.local_uri = "file:///a.mp4"
	menu.setting_requested.connect(host._on_player_setting)
	menu._state = {"has_video": true, "queue_shuffle": false}
	menu._activate(menu.PLAYBACK_ORDER)
	assert(host.playback_queue.shuffle)
	assert(host.settings.get_value("playback", "queue_shuffle"))
	menu._state.queue_shuffle = true
	menu._activate(menu.PLAYBACK_ORDER)
	assert(not host.playback_queue.shuffle)
	assert(host.playback_queue.adjacent("file:///b.mp4", 1).is_empty())
	var migration := preload("res://scripts/player_settings_migration.gd")
	host.settings.set_value("playback", "queue_shuffle", "obsolete")
	assert(migration.apply(host.settings))
	assert(not host.settings.get_value("playback", "queue_shuffle"))
	host.video.free()
	host.video = null
	host.free()
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
