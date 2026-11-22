extends SceneTree

const Catalog := preload("res://scripts/recent_files.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/library_menu.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""
var selections: Array = []


class Host:
	extends RefCounted
	var calls: Array = []
	var request_id := 100
	var next_session := 7
	var revised_session := -1
	var play_requests: Array = []

	func mpv_supported() -> bool:
		return true

	func open_mpv_video(
		uri: String,
		start: int,
		_stereo: bool,
		_vulkan: bool,
		_top_bottom: bool = false,
		_exact: bool = false
	) -> int:
		calls.append(["open", uri, start])
		return next_session

	func close_mpv_video(id: int) -> void:
		calls.append(["close", id])

	func set_mpv_playing(id: int, playing: bool) -> void:
		play_requests.append([id, playing])

	func revise_mpv_video(
		_id: int, _stereo: bool, _position: int, _top_bottom: bool, _exact: bool
	) -> int:
		return revised_session

	func request_local_video_access(uri: String) -> int:
		request_id += 1
		calls.append(["check", uri, request_id])
		return request_id

	func cancel_local_video_access(id: int) -> void:
		calls.append(["cancel", id])

	func pick_local_video() -> int:
		request_id += 1
		calls.append(["pick", request_id])
		return request_id

	func cancel_local_video_pick(id: int) -> void:
		calls.append(["pick_cancel", id])


class Interrupted:
	extends "res://scripts/recent_files.gd"

	func _commit(_staged: String, target: String) -> Error:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		return ERR_CANT_CREATE


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func reload_catalog() -> RefCounted:
	var catalog := Catalog.new(directory)
	catalog.load_saved()
	return catalog


func check_selected_delete() -> void:
	var path := directory.path_join("selected-delete")
	var catalog := Catalog.new(path)
	var a := "file:///recent/first.mp4"
	var b := "file:///recent/keep.mp4"
	var c := "file:///recent/last.mp4"
	for uri in [a, b, c]:
		catalog.opened(uri, uri.get_file(), false)
		catalog.progress(uri, 12345, 60000)
	check(catalog.save(), "Batch deletion fixture saves")
	var interrupted := Interrupted.new(path)
	interrupted.load_saved()
	check(
		not interrupted.forget_selected([a, c]) and interrupted.list_recent().size() == 3,
		"A failed batch commit restores the in-memory catalog"
	)
	check(catalog.forget_selected([a, c]), "Selected recent records commit as one batch")
	var reread := Catalog.new(path)
	reread.load_saved()
	check(
		(
			reread.list_recent().size() == 1
			and reread.lookup(a).is_empty()
			and reread.lookup(c).is_empty()
			and reread.resume_position(b) == 12345
		),
		"Reopening the catalog retains only unselected history and its resume point"
	)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _run() -> void:
	preload("res://scripts/i18n.gd").use("en")  # text checks are written in English
	directory = ProjectSettings.globalize_path(
		"res://../../build/tests/godot/recent-files-host/" + str(Time.get_ticks_usec())
	)
	DirAccess.make_dir_recursive_absolute(directory)
	check_selected_delete()
	var a := "content://local/document/字幕%20A"
	var b := "file:///local/b.mp4"
	var catalog := Catalog.new(directory)
	catalog.load_saved()
	check(catalog.list_recent().is_empty(), "Missing catalog starts empty")
	check(
		not catalog.opened("http://127.0.0.1:4242/token/v.mp4", "proxy", false),
		"Per-run loopback proxy URL rejected"
	)
	check(
		(
			catalog.opened(a, "中文字幕 😀\nA", true)
			and catalog.progress(a, 12345, 60000)
			and catalog.save()
		),
		"First catalog generation commits"
	)
	check(
		(
			reload_catalog().resume_position(a) == 12345
			and reload_catalog().lookup(a).title == "中文字幕 😀 A"
		),
		"Fresh reader restores exact position/Unicode and sanitized label"
	)
	var exposed := catalog.list_recent()
	exposed[0].uri = "altered"
	check(catalog.lookup(a).uri == a, "UI cannot mutate catalog entries through snapshots")
	check(
		catalog.opened(b, "B", false) and catalog.progress(b, 42000, 60000) and catalog.save(),
		"Second file saved with transient grant marker"
	)
	check(
		reload_catalog().list_recent()[0].uri == b and not reload_catalog().lookup(b).persisted,
		"Most recent open wins independently of persistence marker"
	)
	check(
		catalog.progress(a, 25000, 60000) and catalog.save() and catalog.list_recent()[0].uri == b,
		"Progress updates cannot reorder files"
	)
	check(
		catalog.progress(b, 58500, 60000) and catalog.resume_position(b) == 0,
		"Near EOF starts again from beginning"
	)
	check(
		catalog.progress(b, 12000, 60000, true) and catalog.resume_position(b) == 0,
		"Ended playback resets resume point"
	)
	check(
		not catalog.progress(a, -1, 60000) and not catalog.progress("file:///missing", 20, 30),
		"Invalid/unconfirmed progress cannot enter catalog"
	)
	catalog.progress(b, 45000, 60000)
	catalog.save()
	var winning_path: String = catalog._bank_path(catalog.active_bank)
	var intact := FileAccess.get_file_as_string(winning_path)
	for version in [1, 2]:
		var legacy: Dictionary = JSON.parse_string(intact)
		legacy.schema_version = version
		write(winning_path, JSON.stringify(legacy))
		var upgraded := reload_catalog()
		check(
			upgraded.resume_position(b) == 45000 and upgraded.dirty and not upgraded.read_only,
			"Schema %d restores the newer bank with its original resume position" % version
		)
	write(winning_path, intact)
	write(winning_path, '{"truncated":')
	check(
		reload_catalog().lookup(b).position_ms == 42000,
		"Corrupted newest bank falls back to previous generation"
	)
	write(winning_path, intact)
	var future: Dictionary = JSON.parse_string(intact)
	future.schema_version = 9
	write(winning_path, JSON.stringify(future))
	var downgraded := reload_catalog()
	downgraded.opened("file:///future", "future", false)
	check(
		(
			downgraded.read_only
			and not downgraded.save()
			and JSON.parse_string(FileAccess.get_file_as_string(winning_path)).schema_version == 9
		),
		"Downgrade preserves unknown catalog version"
	)
	write(winning_path, intact)
	var interrupted := Interrupted.new(directory)
	interrupted.load_saved()
	interrupted.opened("file:///interrupted", "Interrupted", true)
	check(
		not interrupted.save() and reload_catalog().lookup(b).position_ms == 45000,
		"Older bank deletion during failed replacement preserves winning bank"
	)
	for index in 40:
		catalog.opened("file:///item%d" % index, "Item %d" % index, true)
		check(catalog.save(), "Bounded recent item commits %d" % index)
	check(
		(
			reload_catalog().list_recent().size() == 32
			and reload_catalog().list_recent()[0].uri == "file:///item39"
		),
		"Catalog evicts oldest at 32 entries"
	)
	check(
		(
			catalog.forget("file:///item39")
			and catalog.save()
			and reload_catalog().lookup("file:///item39").is_empty()
		),
		"Forget persists without deleting media"
	)
	for index in 12:
		catalog.opened("content://local/" + "界".repeat(7000) + str(index), "Large URI", true)
	check(
		(
			catalog.save()
			and reload_catalog().lookup("content://local/" + "界".repeat(7000) + "11").uri.ends_with(
				"11"
			)
		),
		"UTF8 byte budget evicts older entries and retains newest opaque URI"
	)
	var invalid := {
		"uri": a, "title": "A", "persisted": true, "position_ms": 0, "duration_ms": 100, "opened": 1
	}
	for mutation in [
		{"position_ms": NAN},
		{"position_ms": -1},
		{"duration_ms": -2},
		{"persisted": "yes"},
		{"opened": 1000},
		{"position_ms": 1.5}
	]:
		var entry := invalid.duplicate(true)
		entry.merge(mutation, true)
		check(not Catalog.valid_entry(entry, 10), "Catalog rejects invalid entry " + str(mutation))
	var host := Host.new()
	var video := Video.new()
	video.mode_memory = Memory.new(directory.path_join("modes"))
	video.recent_files = Catalog.new(directory.path_join("integration"))
	root.add_child(video)
	video.set_process(false)
	video.platform = host
	video.recent_files.opened(a, "Saved A", true)
	video.recent_files.progress(a, 12345, 60000)
	video.recent_files.save()
	video.open_local(b, "Current", 0, false)
	check(
		video.open_recent(a) and video.media.session_id == 7 and host.calls.back()[0] == "check",
		"Preflight leaves current playback running"
	)
	var request: int = video._access_request
	video._on_local_access(
		request - 1, JSON.stringify({"uri": a, "state": "readable", "persisted_permission": true})
	)
	check(
		host.calls.back()[0] == "check" and video.local_uri == b,
		"Old access request cannot replace current media"
	)
	video._on_local_access(
		request, JSON.stringify({"uri": b, "state": "readable", "persisted_permission": true})
	)
	check(video.local_uri == b, "Wrong URI cannot authorize a different file")
	video._on_local_access(
		request,
		JSON.stringify(
			{
				"uri": a,
				"state": "error",
				"error": "LOCAL_DOCUMENT_PERMISSION_LOST",
				"persisted_permission": false
			}
		)
	)
	check(
		video.local_uri == b and video.media.session_id == 7 and not host.calls.has(["close", 7]),
		"Revoked permission preserves playing source"
	)
	video.open_recent(a)
	request = video._access_request
	video._on_local_access(
		request, JSON.stringify({"uri": a, "state": "readable", "persisted_permission": true})
	)
	check(
		host.calls.back() == ["open", a, 12345] and video._file_permission_persisted,
		"Successful preflight restores saved position after current source closes"
	)
	video.media.generation = 2
	video.media.state = "paused"
	video.media.last_pair = {
		"session_id": 7,
		"generation": 2,
		"pts_us": 23000000,
		"source_pts_verified": false,
		"source_ticket_origin": "standard_libmpv_render",
		"source_ticket_valid": true
	}
	video.control.duration_ms = 60000
	video.panel.visible = true
	video.checkpoint_playback()
	check(
		video.recent_files.resume_position(a) == 23000,
		"Resume point follows current bound source PTS"
	)
	video.media.last_pair.generation = 1
	video.media.last_pair.pts_us = 45000000
	video.checkpoint_playback()
	check(
		video.recent_files.resume_position(a) == 23000,
		"Old processing generation cannot overwrite progress"
	)
	video.media.last_pair.generation = 2
	video.open_recent(a, true)
	request = video._access_request
	video.cancel_pending_open()
	video._on_local_access(
		request, JSON.stringify({"uri": a, "state": "readable", "persisted_permission": true})
	)
	check(
		video.local_uri == a and host.calls.back() == ["cancel", request],
		"Cancelled/late preflight cannot reopen source"
	)
	video._file_permission_persisted = true
	video._reopen_after_context_loss(a, "Saved A", 23000, true)
	check(
		(
			video._file_permission_persisted
			and video._remember_file
			and host.calls.back() == ["open", a, 23000]
		),
		"Context recovery retains persisted permission metadata and current resume point"
	)
	var menu := Menu.new()
	menu.catalog = video.recent_files
	menu.chosen.connect(func(uri: String, _title: String): selections.append(uri))
	root.add_child(menu)
	menu.toggle()
	check(
		menu.visible and menu.text_snapshot().contains("Saved A"),
		"Actual menu lists private recent title"
	)
	var row: Dictionary = menu.controls_snapshot().filter(func(button): return button.target == Menu.ROW_BASE)[0]
	var centre: Vector2 = row.rect.get_center()
	var ray_origin := menu.to_global(Vector3(centre.x, centre.y, 1))
	var ray_direction := -menu.global_basis.z
	menu.update_pointer("right_hand", ray_origin, ray_direction, true)
	check(
		menu.hover_snapshot().right_hand == Menu.ROW_BASE and selections.is_empty(),
		"Ray hover targets saved row without opening it"
	)
	check(not menu.has_method("poll_axis"), "Menu has no thumbstick selection entry")
	menu.press_pointer("right_hand", ray_origin, ray_direction, true)
	menu.release_pointer("right_hand", ray_origin, ray_direction, true)
	check(not menu.visible and selections == [a], "Menu activation emits exact selected URI once")
	video.open_local(b, "Current", 0, false)
	video.pick_file()
	var picker: int = video._picker_request
	video._on_selected(JSON.stringify({"state": "checking", "picker_request": picker}))
	check(
		(
			video.local_uri == b
			and video.media.session_id == 7
			and video.picker_error == "Checking file access..."
		),
		"Picker metadata checking preserves current source"
	)
	video.pick_file()
	video._on_selected(JSON.stringify({"state": "selected", "picker_request": picker, "uri": a}))
	check(
		video.local_uri == b and video._picker_request != picker,
		"Old picker result cannot replace newer selection"
	)
	picker = video._picker_request
	video.cancel_pending_open()
	video._on_selected(JSON.stringify({"state": "selected", "picker_request": picker, "uri": a}))
	check(
		video.local_uri == b and video._picker_request == 0,
		"Queued selected result is ignored after local cancellation"
	)
	video.pick_file()
	picker = video._picker_request
	var resume: int = video.recent_files.resume_position(a)
	video._on_selected(
		JSON.stringify(
			{
				"state": "selected",
				"picker_request": picker,
				"uri": a,
				"display_name": "Selected",
				"persisted_permission": true
			}
		)
	)
	check(
		(
			video.local_uri == a
			and video._picker_request == 0
			and video._file_permission_persisted
			and host.calls.back() == ["open", a, resume]
		),
		"Current selected ticket opens with resume and permission metadata"
	)
	video.pick_file()
	video._on_selected(
		JSON.stringify(
			{
				"state": "error",
				"picker_request": video._picker_request,
				"error": "LOCAL_DOCUMENT_TIMEOUT"
			}
		)
	)
	check(
		(
			video.local_uri == a
			and video._picker_request == 0
			and video.picker_error == "LOCAL_DOCUMENT_TIMEOUT"
		),
		"Timed-out picker clears ticket and retains source"
	)
	video.open_local(b, "Surface", 0, true)
	var surface := {
		"surface": true,
		"surface_ready": true,
		"surface_context": {"session_id": 7, "generation": 3, "source_epoch": 1},
		"surface_format": {"width": 1920, "height": 1080, "pixel_aspect": 1.0},
		"details": {"position_seconds": "11.25", "duration_seconds": "60"},
		"state": "playing"
	}
	video._on_state(7, JSON.stringify(surface))
	check(video.recent_files.lookup(b).is_empty(), "Unshown decoder Surface does not enter history")
	video.layer_shown = true
	video._on_state(7, JSON.stringify(surface))
	check(
		video.recent_files.resume_position(b) == 11250 and video.media.last_pair.is_empty(),
		"Shown Surface saves the current playback clock without a frame pair"
	)
	surface.surface_context.session_id = 8
	surface.details.position_seconds = "50"
	video._on_state(7, JSON.stringify(surface))
	video.checkpoint_playback()
	check(video.recent_files.resume_position(b) == 11250, "Mismatched Surface context is ignored")
	surface.surface_context.session_id = 7
	surface.details.position_seconds = "23.5"
	video._on_state(7, JSON.stringify(surface))
	video.history_enabled = false
	video.checkpoint_playback()
	check(video.recent_files.resume_position(b) == 11250, "History-off ignores Surface progress")
	video.history_enabled = true
	video.close_video()
	check(
		video.recent_files.resume_position(b) == 23500,
		"Closing a Surface checkpoints before releasing the layer"
	)
	check(
		video.open_library(b, "Surface") and host.calls.back() == ["open", b, 23500],
		"Opening a recent video restores its saved position"
	)
	video._on_state(7, JSON.stringify(surface))
	check(host.play_requests.back() == [7, true], "The first ready Surface starts recent playback")
	video.seek_absolute(35000)
	var play_count := host.play_requests.size()
	video._on_state(7, JSON.stringify(surface))
	check(
		video.waiting_for_first_frame() and host.play_requests.size() == play_count,
		"A ready status from the old Surface cannot consume a queued seek's first-frame wait"
	)
	host.revised_session = 8
	video._try_revision()
	check(
		video.waiting_for_first_frame() and host.play_requests.back() == [8, false],
		"The accepted seek keeps the new Surface paused until its own first frame"
	)
	surface.surface_context.session_id = 8
	surface.surface_context.generation = 4
	surface.surface_context.source_epoch = 2
	surface.details.position_seconds = "35"
	video._on_state(8, JSON.stringify(surface))
	check(
		not video.waiting_for_first_frame() and host.play_requests.back() == [8, true],
		"The new Surface's ready status resumes playback after the seek"
	)
	var wide := "file:///local/wide.mp4"
	video.recent_files.opened(wide, "Wide", false)
	host.next_session = 9
	host.revised_session = 10
	video.open_library(wide, "Wide")
	surface.surface_context.session_id = 9
	surface.surface_format.width = 3840
	video._on_state(9, JSON.stringify(surface))
	check(
		(
			video.media.session_id == 10
			and video.waiting_for_first_frame()
			and host.play_requests.back() == [10, false]
		),
		"Automatic layout revision during recent playback cannot start on the old ready status"
	)
	surface.surface_context.session_id = 10
	surface.surface_context.generation = 5
	video._on_state(10, JSON.stringify(surface))
	check(
		not video.waiting_for_first_frame() and host.play_requests.back() == [10, true],
		"Recent playback starts after the revised layout has a ready frame"
	)
	check(video.remove_recent_history([wide]), "Deleting the active video's history succeeds")
	video.checkpoint_playback()
	check(
		(
			video.local_uri == wide
			and video.media.session_id == 10
			and video.recent_files.lookup(wide).is_empty()
		),
		"Deleting history leaves playback active without restoring the deleted record on checkpoint"
	)
	video.queue_free()
	menu.queue_free()
	await process_frame
	var report := {
		"state": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"scope":
		"Actual Windows checksummed catalog/files and real Godot menu/player with mocked native preflight; Android provider/grant/lifecycle and XR pixels pending"
	}
	write(directory.path_join("verification.json"), JSON.stringify(report, "\t"))
	print("Recent files host checks: %s (%d), evidence=%s" % [report.state, checks, directory])
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
