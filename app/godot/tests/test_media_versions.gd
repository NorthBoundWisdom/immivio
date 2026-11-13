extends SceneTree


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var menu := preload("res://scripts/library_menu.gd").new()
	root.add_child(menu)
	var browser: RefCounted = menu.server_browser
	var legacy := "medialib://srv/scene/movie"
	var selected := legacy + "?source=b"
	browser.view = "detail"
	browser.detail = {
		"id": "movie",
		"title": "Film",
		"uri": legacy,
		"position_ms": 1000,
		"versions":
		[
			{
				"id": "movie",
				"source_id": "b",
				"uri": selected,
				"version_name": "4K",
				"title": "Film · 4K"
			}
		]
	}
	var rows: Array = browser.rows()
	var version: Dictionary = rows.filter(func(row): return row.get("play_scene", {}).has("source_id"))[0]
	browser.choose(version)
	assert(browser.selection.uri == selected and browser.selection.start_ms == -1)
	var memory := preload("res://scripts/file_mode_memory.gd").new()
	var mode := {
		"geometry": 0,
		"stereo_sbs": false,
		"swap_eyes": false,
		"track_choices": {"audio": {"id": 2}}
	}
	assert(memory.remember(legacy, mode))
	assert(memory.lookup(selected).is_empty())
	assert(memory.remember(selected, mode.merged({"geometry": 1}, true)))
	assert(memory.lookup(legacy).geometry == 0 and memory.lookup(selected).geometry == 1)
	var recent := preload("res://scripts/recent_files.gd").new()
	assert(recent.opened(legacy, "Film", false))
	recent.progress(legacy, 12000, 120000, false)
	assert(recent.resume_position(selected) == 0)
	assert(recent.resume_position(legacy) == 12000)
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
