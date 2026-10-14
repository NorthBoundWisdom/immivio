extends SceneTree
const Queue := preload("res://scripts/playback_queue.gd")
const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const HostTest := preload("res://tests/test_player_menu.gd")
const SubtitleState := preload("res://scripts/mpv_subtitle_state.gd")
var checks := 0
var failures: Array[String] = []
var directory := ProjectSettings.globalize_path("res://../../build/output/playback-tools")


class Host:
	extends HostTest.Host
	var reject_sync := false

	func set_mpv_sync(id: int, sub: int, audio: int) -> bool:
		calls.append(["sync", id, sub, audio])
		return not reject_sync

	func pick_local_subtitle() -> int:
		return 91

	func cancel_local_subtitle_pick(_id: int) -> void:
		pass

	func add_mpv_subtitle(id: int, uri: String) -> bool:
		calls.append(["add_subtitle", id, uri])
		return true


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var queue := Queue.new()
	var entries := [
		{"uri": "file:///a.mp4", "title": "A", "metadata": {"basename": "a.mp4"}},
		{"uri": "cloud://b.mp4", "title": "B"},
		{"uri": "smb://c.mp4", "title": "C"}
	]
	queue.replace(entries)
	entries[0].metadata.basename = "changed"
	check(queue.items[0].metadata.basename == "a.mp4", "Queue owns a copy of source metadata")
	queue.append([entries[0], {"uri": "bad://a"}, {"uri": "file:///invalid.mp4", "metadata": 7}])
	check(queue.items.size() == 3, "Queue deduplicates and rejects invalid entries")
	check(
		(
			queue.adjacent("file:///a.mp4", 1).uri == "cloud://b.mp4"
			and queue.adjacent("smb://c.mp4", 1).is_empty()
		),
		"Sequential queue ends without implicit wrapping"
	)
	queue.configure("queue_shuffle", true, "file:///a.mp4")
	var seen := {}
	var uri := "file:///a.mp4"
	while not uri.is_empty():
		seen[uri] = true
		uri = str(queue.adjacent(uri, 1).get("uri", ""))
	check(
		seen.size() == 3,
		"Shuffle starts with the current video, visits each remaining entry and ends"
	)
	queue.configure("queue_shuffle", false)
	queue.move(2, -1)
	check(queue.items[1].uri == "smb://c.mp4", "Move changes sequence")
	queue.remove(1)
	queue.move(-1, 1)
	queue.remove(99)
	check(queue.items.size() == 2, "Remove and invalid edit boundaries are safe")
	queue.clear()
	check(queue.adjacent("file:///a.mp4", 1).is_empty(), "Cleared queue cannot advance")
	queue.anchor = "file:///still-playing.mp4"
	queue.append(entries)
	check(
		queue.adjacent(queue.anchor, 1).uri == "file:///a.mp4",
		"Newly added queue follows a current video outside the list"
	)
	var large: Array = []
	for i in 510:
		large.append({"uri": "file:///queue-%d.mp4" % i, "title": str(i)})
	queue.replace(large)
	check(queue.items.size() == Queue.LIMIT, "Queue limits excessive source lists to 500 entries")
	queue.replace(queue.items)
	check(
		queue.items.size() == Queue.LIMIT,
		"Replacing a queue from its own snapshot preserves entries"
	)
	var config := ConfigFile.new()
	config.set_value("ui", "language", "en")
	config.set_value("appearance", "background", "dark")
	config.set_value("playback", "queue_autoplay", false)
	config.set_value("playback", "queue_repeat", true)
	config.save(directory.path_join("settings.cfg"))
	var main := Main.new()
	main.settings_path = directory.path_join("settings.cfg")
	root.add_child(main)
	main.set_process(false)
	main.video.set_process(false)
	main.photo.set_process(false)
	main.report_timer.stop()
	var host := Host.new()
	main.video.platform = host
	main.video.mode_memory = Memory.new(directory.path_join("modes"))
	main.video.open_local("file:///timing-a.mp4", "A")
	check(
		(
			main.video.set_sync_delay("subtitle_delay_ms", 750)
			and main.video.set_sync_delay("audio_delay_ms", -250)
		),
		"Both timing controls reach native adapter"
	)
	main.video.commit_sync()
	host.reject_sync = true
	check(
		not main.video.set_sync_delay("audio_delay_ms", 400) and main.video.audio_delay_ms == -250,
		"Rejected native timing request leaves current timing intact"
	)
	host.reject_sync = false
	check(
		(
			not main.video.set_sync_delay("subtitle_delay_ms", NAN)
			and not main.video.set_sync_delay("audio_delay_ms", 10001)
		),
		"Timing rejects invalid values"
	)
	main.video.open_local("file:///timing-b.mp4", "B")
	check(
		main.video.subtitle_delay_ms == 0 and main.video.audio_delay_ms == 0,
		"New video does not inherit another video's timing"
	)
	main.video.open_local("file:///timing-a.mp4", "A")
	check(
		main.video.subtitle_delay_ms == 750 and main.video.audio_delay_ms == -250,
		"Reopening video restores both timing offsets"
	)
	main.video.pick_external_subtitle()
	main.video._on_subtitle_selected(
		JSON.stringify({"state": "selected", "picker_request": 90, "uri": "content://wrong"})
	)
	check(
		main.video._pending_external_uri.is_empty(),
		"Stale picker selection cannot attach a subtitle"
	)
	main.video._on_subtitle_selected(
		JSON.stringify(
			{"state": "selected", "picker_request": 91, "uri": "content://subtitles/new.srt"}
		)
	)
	main.video.media.state = "paused"
	main.video._process(0)
	check(
		(
			main.video._subtitle_loading
			and host.calls.any(func(call): return call[0] == "add_subtitle")
		),
		"Manual document selection dispatches import for the current video"
	)
	main.video._on_subtitle_import(
		7, JSON.stringify({"state": "queued", "command": 5, "uri": "content://subtitles/new.srt"})
	)
	check(
		main.video.external_subtitle_uri.is_empty(),
		"Queued import is not saved before MPV confirms it"
	)
	main.video._on_state(
		7,
		JSON.stringify(
			{
				"state": "paused",
				"details": {"subtitle_import_command": 5, "subtitle_import_error": ""}
			}
		)
	)
	check(
		main.video.external_subtitle_uri == "content://subtitles/new.srt",
		"Successful MPV import saves the chosen subtitle per video"
	)
	main.video._subtitle_loading = true
	main.video._subtitle_import_command = 0
	main.video._subtitle_import_floor = 5
	main.video._subtitle_requested_uri = "content://subtitles/revised.srt"
	main.video._on_state(
		7,
		JSON.stringify(
			{
				"state": "paused",
				"details": {"subtitle_import_command": 6, "subtitle_import_error": ""}
			}
		)
	)
	check(
		(
			main.video.external_subtitle_uri == "content://subtitles/revised.srt"
			and not main.video._subtitle_loading
		),
		"Import confirmation survives a lost superseded-generation callback"
	)
	main.video._subtitle_loading = true
	main.video._on_subtitle_import(
		7,
		JSON.stringify({"state": "queued", "command": 7, "uri": "content://subtitles/broken.srt"})
	)
	main.video._on_state(
		7,
		JSON.stringify(
			{
				"state": "paused",
				"details":
				{"subtitle_import_command": 7, "subtitle_import_error": "Invalid subtitle"}
			}
		)
	)
	check(
		(
			main.video.external_subtitle_uri == "content://subtitles/revised.srt"
			and not main.video._subtitle_loading
			and main.video.media.state == "paused"
		),
		"Failed import keeps the previous association and playback session"
	)
	main.video.forget_external_subtitle()
	check(
		main.video.mode_memory.lookup(main.video.local_uri).external_subtitle_uri.is_empty(),
		"Forgetting subtitle clears its saved association"
	)
	var cue_state := SubtitleState.new()
	cue_state.select(-1)
	var pair := {"session_id": 7, "generation": 1, "source_epoch": 2, "mpv_source_handle": 9}
	for delay in [0.75, -0.25]:
		cue_state.clear(true)
		var snapshot := {
			"session_id": 7,
			"sequence": 1,
			"generation": 1,
			"source_epoch": 2,
			"mpv_source_handle": 9,
			"track_id": "3",
			"timeline_valid": true,
			"age_ms": 20,
			"command_id": 4,
			"required_command_id": 4,
			"start_seconds": "1",
			"end_seconds": "2",
			"position_seconds": str(1.5 + delay),
			"subtitle_delay_seconds": str(delay),
			"text": "Synced"
		}
		check(
			cue_state.observe(snapshot, 7, pair) and cue_state.text == "Synced",
			"Cue clock accounts for positive and negative subtitle delay"
		)
		snapshot.sequence = 2
		snapshot.position_seconds = str(2.1 + delay)
		cue_state.observe(snapshot, 7, pair)
		check(cue_state.text.is_empty(), "Shifted cue expires at its adjusted end time")
	main.video_menu._activate(Menu.SYNC_SETTINGS)
	check(
		main.video_menu._quick_open == "sync" and main.video_menu.choices.sliders.size() == 2,
		"Synchronization menu exposes separate timing sliders"
	)
	main.video_menu._activate(Menu.SUBTITLE_DELAY_RESET)
	check(
		main.video.subtitle_delay_ms == 0 and main.video.audio_delay_ms == -250,
		"Subtitle reset leaves audio offset intact"
	)
	main.video_queue = [
		{"uri": "file:///timing-a.mp4", "title": "A"}, {"uri": "file:///next.mp4", "title": "Next"}
	]
	main.video_menu._activate(Menu.QUEUE_SETTINGS)
	check(
		(
			main.video_menu._quick_open == "queue"
			and main.video_menu.queue_menu.actions.values().has("queue_play_1")
		),
		"Queue panel renders editable entries"
	)
	main.video._waiting_first = false
	main.video.media.state = "ended"
	main.video.media.last_pair = {
		"contract_version": 2,
		"session_id": 7,
		"slot_token": 1,
		"source_epoch": 2,
		"frame_id": 8,
		"pts_us": 9000000
	}
	main.video.media.playback = {
		"eof_source_resolved": true,
		"eof_pair_post_draw": false,
		"eof_presented_slot": 1,
		"eof_source_ticket": {"source_epoch": 2, "frame_id": 8, "pts_us": 9000000}
	}
	var before := host.calls.size()
	main._advance_queue(7, "file:///timing-a.mp4")
	check(host.calls.size() == before, "Auto-play waits until final frame has been drawn")
	main.video.media.playback.eof_pair_post_draw = true
	main.video.loop_enabled = true
	main._advance_queue(7, "file:///timing-a.mp4")
	check(
		main.video.local_uri == "file:///timing-a.mp4",
		"Single-video loop takes precedence over queue auto-play"
	)
	main.video.loop_enabled = false
	main._advance_queue(6, "file:///timing-a.mp4")
	check(
		main.video.local_uri == "file:///timing-a.mp4",
		"Stale EOF callback cannot advance a new session"
	)
	main._advance_queue(7, "file:///timing-a.mp4")
	check(
		(
			main.video.local_uri == "file:///next.mp4"
			and host.calls.filter(func(call): return call[0] == "open").back()[2] == 0
		),
		"Confirmed EOF automatically opens next video from zero despite a legacy auto-play-off preference"
	)
	main._on_player_setting("queue_shuffle", true)
	main._queue_action("queue_play_0")
	check(
		main.playback_queue._order.front() == main.video.local_uri,
		"Manual queue selection starts a complete shuffle traversal"
	)
	main._queue_action("queue_remove_0")
	check(main.video_queue.size() == 1, "Queue UI removal edits the live queue")
	main.playback_queue.custom = true
	main._save_queue()
	var restored := ConfigFile.new()
	restored.load(main.settings_path)
	check(
		(
			restored.get_value("playback", "queue").size() == 1
			and restored.get_value("playback", "custom_queue")
		),
		"Edited queue persists separately from playback session"
	)
	var buttons: Array = main.video_menu._buttons.filter(
		func(button): return button.enabled and button.node.visible
	)
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			check(
				not buttons[i].rect.intersects(buttons[j].rect),
				"Queue controls have distinct ray targets"
			)
	main.video.open_local("file:///next.mp4", "Next")
	main.video._waiting_first = false
	main.video.requested_play = true
	main.video.media.state = "ended"
	main.video.media.last_pair = {
		"contract_version": 2,
		"session_id": 7,
		"slot_token": 1,
		"source_epoch": 2,
		"frame_id": 8,
		"pts_us": 9000000
	}
	main.video.media.playback = {
		"eof_source_resolved": true,
		"eof_pair_post_draw": true,
		"eof_presented_slot": 1,
		"eof_source_ticket": {"source_epoch": 2, "frame_id": 8, "pts_us": 9000000}
	}
	main._on_video_changed()
	main._on_video_changed()
	await process_frame
	check(
		(
			main.video.local_uri.is_empty()
			and main.recent_menu.visible
			and not main.video_menu.visible
		),
		"Final queue EOF closes playback and returns to files without repeating"
	)
	var closed := host.calls.filter(func(call): return call[0] == "close").size()
	main._advance_queue(7, "file:///next.mp4")
	check(
		host.calls.filter(func(call): return call[0] == "close").size() == closed,
		"Repeated EOF callback cannot close another session"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Playback tools checks: %d, failures: %d" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
