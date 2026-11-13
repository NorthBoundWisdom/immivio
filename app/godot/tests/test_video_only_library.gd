extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Main := preload("res://scripts/main.gd")
const Recent := preload("res://scripts/recent_files.gd")
const Queue := preload("res://scripts/playback_queue.gd")
var failures: Array[String] = []
var checks := 0
var selections := 0


class Catalog:
	extends RefCounted

	func list_recent() -> Array:
		return [
			{"uri": "file:///clip.mp4", "title": "Clip.mp4", "position_ms": 1000},
			{"uri": "file:///old.jpg", "title": "Old.jpg", "kind": "image", "position_ms": 0}
		]


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var menu := Library.new()
	menu.catalog = Catalog.new()
	root.add_child(menu)
	menu.set_process(false)
	menu.visible = true
	menu.chosen.connect(func(_uri, _title): selections += 1)
	var mixed := [
		{"id": "folder", "title": "Folder", "container": true},
		{"uri": "file:///clip.mp4", "title": "Clip.mp4", "kind": "video"},
		{"uri": "file:///old.jpg", "title": "Old.jpg", "kind": "image"},
		{"uri": "file:///old.heic", "title": "Old.heic", "kind": "image"},
		{"uri": "file:///wrong.png", "title": "Wrong.png", "kind": "video"}
	]
	for section in [Library.Section.LOCAL, Library.Section.SMB, Library.Section.DLNA]:
		menu.section = section
		menu.sources.local_entries = mixed
		menu.sources.smb_server = "saved"
		menu.sources.smb_entries = mixed
		menu.sources.dlna_server = "saved"
		menu.sources.dlna_entries = mixed
		menu.refresh()
		check(
			menu.rows.map(func(row): return row.title) == ["Folder", "Clip.mp4"],
			"Every file source retains folders and videos while excluding still images"
		)
		check(
			not menu._buttons.any(func(button): return button.target in [70, 71, 72]),
			"The retired All/Video/Images filter has no visible or clickable targets"
		)
		check(menu.video_queue().size() == 1, "File-source playback queues contain videos only")
	menu.section = Library.Section.RECENT
	menu.refresh()
	check(
		menu.rows.size() == 1 and menu.rows[0].title == "Clip.mp4",
		"Legacy still-image history is excluded from Recent"
	)
	menu._choose(mixed[2])
	check(selections == 0, "A stale image selection cannot emit a playback request")
	menu._choose(mixed[1])
	check(selections == 1, "Ordinary video selection still works")
	menu.free()
	var history := Recent.new("user://video-only-history")
	check(history.opened("file:///clip.mp4", "Clip.mp4", false), "Video history can be recorded")
	check(
		not history.opened("file:///still.heif", "Still.heif", false),
		"New still-image history cannot be recorded"
	)
	history.entries[history.key_for("file:///old.jpg")] = {
		"uri": "file:///old.jpg",
		"title": "Old.jpg",
		"kind": "image",
		"persisted": false,
		"opened": 1,
		"position_ms": 0,
		"duration_ms": -1
	}
	check(history.save(), "A signed legacy mixed-history fixture can be saved")
	var restored := Recent.new("user://video-only-history")
	restored.load_saved()
	check(restored.list_recent().size() == 1, "Reloading a legacy catalog retains its videos only")
	var queue := Queue.new()
	queue.append(mixed.slice(1))
	check(
		queue.items.size() == 1 and queue.items[0].uri == "file:///clip.mp4",
		"Restoring an old mixed queue cannot reopen still images"
	)
	var original := "user://original.jpg"
	FileAccess.open(original, FileAccess.WRITE).store_string("original media bytes")
	var settings := ConfigFile.new()
	settings.set_value("photo", "mode_lock", {"geometry": 3})
	settings.set_value("photo_screen", "scale", 2.0)
	settings.set_value("photo_gallery", "rows", 3)
	settings.set_value("appearance", "background", "dark")
	settings.set_value("video", "sharpness", .4)
	settings.save("user://video-only-settings.cfg")
	var main := Main.new()
	main.settings_path = "user://video-only-settings.cfg"
	root.add_child(main)
	main.set_process(false)
	main.video.set_process(false)
	main.report_timer.stop()
	check(
		(
			not main.settings.has_section("photo")
			and not main.settings.has_section("photo_screen")
			and not main.settings.has_section("photo_gallery")
		),
		"Upgrade retires all still-image preferences"
	)
	check(
		main.settings.get_value("video", "sharpness") == .4, "Upgrade preserves video preferences"
	)
	check(
		main.get_node_or_null("PhotoDisplay") == null and main.menu_compositor.menus.size() == 2,
		"The application creates only the library and video controls"
	)
	main._on_library_chosen("file://" + ProjectSettings.globalize_path(original), "Original.jpg")
	check(
		main.video.local_uri.is_empty(),
		"Direct stale selection cannot route a still image into playback"
	)
	check(
		FileAccess.get_file_as_string(original) == "original media bytes",
		"Retiring the feature does not modify or delete original media"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Video-only library: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
