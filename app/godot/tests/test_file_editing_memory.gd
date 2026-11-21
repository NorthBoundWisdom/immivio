extends SceneTree
var checks := 0
var failures: Array[String] = []


class Reader:
	extends Node3D
	var local_uri := ""
	var queue: Array[Dictionary] = []
	var closes := 0
	var bookmark_store: RefCounted
	var mode_memory: RefCounted
	var recent_files: RefCounted

	func close_video() -> void:
		closes += 1
		local_uri = ""

	func close_image() -> void:
		closes += 1
		local_uri = ""
		queue.clear()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var directory := ProjectSettings.globalize_path(
		"res://../../build/tests/godot/file-editing-memory/" + str(Time.get_ticks_usec())
	)
	var old := "file:///storage/test/old.mp4"
	var new := "file:///storage/test/new.mp4"
	var recent := preload("res://scripts/recent_files.gd").new(directory)
	recent.opened(old, "old.mp4", false)
	recent.progress(old, 5000, 100000)
	check(
		(
			recent.relocate(old, new, "new.mp4")
			and recent.lookup(old).is_empty()
			and recent.resume_position(new) == 5000
		),
		"Rename keeps progress under new URI"
	)
	check(recent.save(), "Renamed history persists")
	var reloaded := preload("res://scripts/recent_files.gd").new(directory)
	reloaded.load_saved()
	check(
		reloaded.lookup(new).title == "new.mp4" and reloaded.lookup(old).is_empty(),
		"History survives restart with renamed title and identity"
	)
	var modes := preload("res://scripts/file_mode_memory.gd").new(directory)
	(
		modes
		. remember(
			old,
			{
				"geometry": 1,
				"stereo_sbs": true,
				"swap_eyes": false,
			}
		)
	)
	check(
		modes.relocate(old, new) and modes.lookup(new).stereo_sbs and modes.lookup(old).is_empty(),
		"Rename keeps viewing mode"
	)
	check(
		(
			reloaded.relocate(new, new, "Retitled.mp4")
			and reloaded.lookup(new).title == "Retitled.mp4"
			and reloaded.resume_position(new) == 5000
			and modes.relocate(new, new)
			and modes.lookup(new).stereo_sbs
		),
		"Rename that keeps the document URI retains history and viewing mode"
	)
	var thumbnails := preload("res://scripts/thumbnail_cache.gd")
	var picture := Image.create_empty(320, 180, false, Image.FORMAT_RGB8)
	picture.fill(Color.GREEN)
	check(thumbnails.store(new, picture), "Thumbnail fixture is saved")
	thumbnails.relocate(new, new)
	check(thumbnails.has(new), "Rename that keeps the document URI retains its thumbnail")
	thumbnails.forget(new)
	var store := preload("res://scripts/bookmark_store.gd").new(directory.path_join("bookmarks"))
	store.add(old, "old.mp4", 5000, 10000)
	check(
		store.relocate(old, new, "new.mp4", 5000), "Rename migrates bookmark fingerprint and alias"
	)
	check(
		store.list_markers(store.resolve(new, "new.mp4", 5000)).size() == 1,
		"Renamed movie retains timestamp"
	)
	var before_same_uri := store.revision
	check(
		(
			store.relocate(new, new, "ignored.mp4", 5000)
			and store.revision == before_same_uri
			and store.list_markers(store.resolve(new, "new.mp4", 5000)).size() == 1
		),
		"An unchanged URI performs no bookmark write even with a different label"
	)
	check(
		store.list_markers(store.resolve(old, "old.mp4", 5000)).is_empty(),
		"A replacement at old URI does not inherit renamed bookmarks"
	)
	var cold := preload("res://scripts/bookmark_store.gd").new(directory.path_join("bookmarks"))
	check(
		cold.list_markers(cold.resolve(new, "new.mp4", 5000)).size() == 1,
		"Renamed bookmarks survive restart"
	)
	var shared := preload("res://scripts/bookmark_store.gd").new(
		directory.path_join("shared-bookmarks")
	)
	var copy := "smb://other/share/old.mp4"
	shared.add(old, "old.mp4", 5000, 10000)
	shared.add(copy, "old.mp4", 5000, 20000)
	check(
		shared.relocate(old, new, "new.mp4", 5000),
		"Rename can separate one URI from a shared bookmark record"
	)
	check(
		(
			shared.list_markers(shared.resolve(new, "new.mp4", 5000)).size() == 2
			and shared.list_markers(shared.resolve(copy, "old.mp4", 5000)).size() == 2
		),
		"Renaming one copy preserves both copies' bookmarks"
	)
	var undo_store := preload("res://scripts/bookmark_store.gd").new(
		directory.path_join("undo-bookmarks")
	)
	var marker := undo_store.add(old, "old.mp4", 5000, 10000)
	undo_store.remove(undo_store.resolve(old, "old.mp4", 5000), marker.id)
	check(
		undo_store.relocate(old, new, "new.mp4", 5000) and undo_store.restore(),
		"A recent bookmark undo follows a renamed video"
	)
	check(
		(
			undo_store.list_markers(undo_store.resolve(new, "new.mp4", 5000)).size() == 1
			and undo_store.list_markers(undo_store.resolve(old, "old.mp4", 5000)).is_empty()
		),
		"Undo cannot revive renamed markers at the old URI"
	)
	var app := preload("res://scripts/main.gd").new()
	app.video = Reader.new()
	app.settings_path = directory.path_join("app.cfg")
	var connected_store := preload("res://scripts/bookmark_store.gd").new(
		directory.path_join("connected-bookmarks")
	)
	app.video.bookmark_store = connected_store
	app.video.mode_memory = modes
	app.video.recent_files = reloaded
	connected_store.add(old, "old.mp4", 5000, 10000)
	var other_video := "file:///storage/test/other.mp4"
	var moved_subtitle := "file:///storage/test/old.zh%20CN.srt"
	var unrelated_subtitle := "file:///storage/elsewhere/old.zh%20CN.srt"
	var mode := modes.lookup(new)
	mode.external_subtitle_uri = moved_subtitle
	modes.remember(old, mode)
	modes.remember(other_video, mode)
	mode.external_subtitle_uri = unrelated_subtitle
	modes.remember("file:///storage/test/third.mp4", mode)
	var moves := [
		{"from": "old.mp4", "to": "new.mp4"}, {"from": "old.zh CN.srt", "to": "new.zh CN.srt"}
	]
	app._on_file_renamed(old, new, "new.mp4", 5000, moves)
	check(
		connected_store.list_markers(connected_store.resolve(new, "new.mp4", 5000)).size() == 1,
		"The production rename handler moves bookmarks"
	)
	check(
		(
			modes.lookup(new).external_subtitle_uri == "file:///storage/test/new.zh%20CN.srt"
			and (
				modes.lookup(other_video).external_subtitle_uri
				== modes.lookup(new).external_subtitle_uri
			)
			and (
				modes.lookup("file:///storage/test/third.mp4").external_subtitle_uri
				== unrelated_subtitle
			)
		),
		"Confirmed sidecar moves update saved references in the matching folder only"
	)
	var discarded := connected_store.add(old, "old.mp4", 5000, 20000)
	connected_store.remove(connected_store.resolve(old, "old.mp4", 5000), discarded.id)
	connected_store.add(old, "old.mp4", 5000, 25000)
	check(connected_store.can_undo(), "Conflict fixture retains an undo at the old URI")
	app._on_file_renamed(old, new, "new.mp4", 5000, moves)
	var destination := connected_store.list_markers(connected_store.resolve(new, "new.mp4", 5000))
	check(
		(
			destination.size() == 1
			and destination[0].position_ms == 10000
			and (
				connected_store
				. list_markers(connected_store.resolve(old, "old.mp4", 5000))
				. is_empty()
			)
			and not connected_store.can_undo()
			and FileAccess.get_file_as_string("user://diagnostics/events.jsonl").contains(
				"bookmark_rename_conflict"
			)
		),
		"A destination conflict preserves the destination, retires the source and logs the event"
	)
	app.video.local_uri = "file:///storage/test/folder/movie.mp4"
	app._prepare_file_delete("file:///storage/test/folder")
	check(
		app.video.closes == 1, "Folder deletion releases descendant video readers before mutation"
	)
	app.video.local_uri = "smb://other/share/movie.mp4"
	app._prepare_file_delete("file:///storage/test/folder")
	check(app.video.closes == 1, "Deleting a folder leaves unrelated readers running")
	app.video.free()
	app.free()
	print("file editing memory checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
