extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var menu := Menu.new()
	root.add_child(menu)
	var host := preload("res://scripts/main.gd").new()
	host.video = preload("res://scripts/mpv_video_display.gd").new()
	host.playback_queue = preload("res://scripts/playback_queue.gd").new()
	host.playback_queue.replace(
		[{"uri": "file:///a.mp4", "title": "A"}, {"uri": "file:///b.mp4", "title": "B"}]
	)
	host.video.local_uri = "file:///a.mp4"
	menu.setting_requested.connect(host._on_player_setting)
	menu.state_provider = func():
		return {"has_video": true, "queue_shuffle": host.playback_queue.shuffle}
	menu.toggle()
	assert(
		not menu.controls_snapshot().any(func(button): return button.target == Menu.SUBTITLE_LOAD)
	)
	menu.test_activate(Menu.QUEUE_SETTINGS)
	assert(menu.popup_snapshot().quick_open == "queue")
	choose_order(menu, true)
	assert(host.playback_queue.shuffle)
	assert(host.settings.get_value("playback", "queue_shuffle"))
	choose_order(menu, false)
	assert(not host.playback_queue.shuffle)
	assert(not host.settings.get_value("playback", "queue_shuffle"))
	assert(host.playback_queue.adjacent("file:///b.mp4", 1).is_empty())
	var actions: Array[String] = []
	menu.action_requested.connect(func(operation: String): actions.append(operation))
	menu.test_activate(Menu.SYNC_SETTINGS)
	assert(menu.controls_snapshot().any(func(button): return button.target == Menu.SUBTITLE_LOAD))
	menu.test_activate(Menu.SUBTITLE_LOAD)
	assert(actions == ["load_subtitle"] and not host.playback_queue.shuffle)
	var migration := preload("res://scripts/player_settings_migration.gd")
	host.settings.set_value("playback", "queue_shuffle", "obsolete")
	assert(migration.apply(host.settings))
	assert(not host.settings.get_value("playback", "queue_shuffle"))
	host.video.free()
	host.video = null
	host.free()
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)


func choose_order(menu: Node3D, shuffle: bool) -> void:
	for target in menu.choices.targets:
		var choice: Dictionary = menu.choices.targets[target]
		if choice.get("key") == "queue_shuffle" and choice.get("value") == shuffle:
			menu.test_activate(target)
			return
	assert(false, "Playback order is available inside the queue menu")
