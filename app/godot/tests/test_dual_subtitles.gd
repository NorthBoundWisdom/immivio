extends SceneTree
const Video := preload("res://scripts/mpv_video_display.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Base := preload("res://tests/test_independent_playback.gd")
var failures: Array[String] = []
var checks := 0

class Host:
	extends Base.Host
	var snapshot := ""
	func set_mpv_secondary_subtitle(id: int, track: int) -> bool:
		if reject:
			return false
		calls.append(["secondary", id, track])
		return true
	func get_mpv_subtitles(_id: int, _after: int) -> String:
		return snapshot

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()

func _run() -> void:
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	var host := Host.new()
	video.platform = host
	video.mode_memory = Memory.new("user://dual-memory")
	video.open_local("file:///dual-a.mp4", "A")
	var tracks := [{"id": 2, "codec": "subrip", "language": "en"},
		{"id": 8, "codec": "ass", "language": "zh", "external": true, "encoding_key": "a".repeat(64)},
		{"id": 5, "codec": "hdmv_pgs_subtitle"}]
	var details := {"subtitle_tracks": tracks, "subtitle": {"track_id": "2"}}
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(not video.dual_subtitles.enabled, "Dual subtitles default off")
	check(video.set_subtitle_track(2), "Select primary")
	check(not video.dual_subtitles.select(2) and not video.dual_subtitles.select(5) and not video.dual_subtitles.select(-1), "Reject same, bitmap and auto secondary")
	check(video.dual_subtitles.set_enabled(true) and video.dual_subtitles.select(8), "External text shares the secondary list")
	check(video.subtitle_encoding_row(true).get("value", {}).get("track_key", "") == "a".repeat(64), "Secondary encoding uses the same per-track override")
	var pair := {"session_id": video.media.session_id, "generation": video.media.generation, "source_epoch": 2, "mpv_source_handle": 55}
	video.media.last_pair = pair
	video._waiting_first = false
	video.panel.visible = true
	var sample := {"session_id": video.media.session_id, "generation": video.media.generation,
		"source_epoch": 2, "mpv_source_handle": 55, "sequence": 10,
		"command_id": 4, "required_command_id": 4, "track_id": "2", "timeline_valid": true,
		"age_ms": 20, "start_seconds": "1", "end_seconds": "3", "position_seconds": "2",
		"subtitle_delay_seconds": "0.5", "text": "Primary",
		"required_secondary_command_id": 7, "secondary": {"sequence": 10, "command_id": 7,
		"track_id": "8", "text": "第二字幕", "start_seconds": "1", "end_seconds": "3", "subtitle_delay_seconds": "0.5"}}
	host.snapshot = JSON.stringify(sample)
	video._subtitle_poll_ms = 0
	video._poll_subtitles()
	check(video.caption.text == "Primary\n第二字幕" and video.caption.visible, "Production polling composes primary above secondary")
	for mutation in [{"session_id": -1}, {"source_epoch": 1}, {"age_ms": 1001}, {"timeline_valid": false}, {"generation": -1}]:
		video.dual_subtitles.state.clear(true)
		var stale := sample.duplicate(true)
		stale.merge(mutation, true)
		video.dual_subtitles.observe(stale)
		check(video.dual_subtitles.state.text.is_empty(), "Stale secondary cleared: " + str(mutation))
	video.dual_subtitles.state.clear(true)
	var old_command := sample.duplicate(true)
	old_command.secondary.command_id = 6
	video.dual_subtitles.observe(old_command)
	check(video.dual_subtitles.state.text.is_empty(), "Independent secondary command fence")
	video.dual_subtitles.state.clear(true)
	var delayed := sample.duplicate(true)
	delayed.secondary.subtitle_delay_seconds = "2"
	video.dual_subtitles.observe(delayed)
	check(video.dual_subtitles.state.text.is_empty(), "Secondary validates the shared delay against playback time")
	video.dual_subtitles.state.text = "old"
	host.snapshot = ""
	video._subtitle_received_ms = Time.get_ticks_msec() - 1001
	video._poll_subtitles()
	check(video.dual_subtitles.state.text.is_empty() and video.caption.text.is_empty(), "One-second silence clears both channels")
	video.subtitles.text = "First"
	video.dual_subtitles.state.text = "Second"
	check(video.set_subtitle_track(0) and video.dual_subtitles.compose().is_empty() and video.dual_subtitles.state.requested_track == 8, "Primary off hides secondary but retains selection")
	video.set_subtitle_track(2)
	video.subtitles.text = "First"
	video.dual_subtitles.state.text = "Second"
	check(video.dual_subtitles.compose() == "First\nSecond", "Primary on restores composition")
	check(video.set_subtitle_track(8) and video.dual_subtitles.state.requested_track == 0, "Primary wins a collision and turns secondary off")
	check(video.mode_memory.lookup(video.local_uri).track_choices.secondary_subtitle.id == 0, "Collision persists secondary off")
	video.set_subtitle_track(2)
	video.dual_subtitles.select(8)
	check(video.mode_memory.lookup(video.local_uri).track_choices.secondary_subtitle.id == 8, "Secondary saved in the existing mode record")
	video.open_local("file:///dual-b.mp4", "B")
	check(not video.dual_subtitles.enabled and video.dual_subtitles.state.requested_track == 0, "Another file never inherits secondary")
	video.mode_memory = Memory.new("user://dual-memory")
	video.mode_memory.load_saved()
	video.open_local("file:///dual-a.mp4", "A")
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(video.subtitles.requested_track == 2 and video.dual_subtitles.state.requested_track == 8, "Reload restores both channels after tracks arrive")
	details.subtitle_tracks = [{"id": 2, "codec": "subrip", "language": "en"}, {"id": 8, "codec": "ass", "language": "ja"}]
	video.open_local("file:///dual-a.mp4", "A")
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(video.dual_subtitles.state.requested_track == 0, "A reused numeric ID cannot restore the wrong language")
	check(video.mode_memory.relocate("file:///dual-a.mp4", "file:///dual-moved.mp4"), "Move existing mode record")
	check(video.mode_memory.lookup("file:///dual-moved.mp4").track_choices.secondary_subtitle.id == 8, "Secondary preference migrates with rename/move")
	video.history_enabled = false
	video.open_local("file:///dual-private.mp4", "Private")
	details.subtitle_tracks = tracks
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	video.set_subtitle_track(2, false)
	var serial := video.mode_memory.sequence
	video.dual_subtitles.select(8)
	check(video.mode_memory.sequence == serial and video.mode_memory.lookup(video.local_uri).is_empty(), "History-off secondary selection writes nothing")
	video.history_enabled = true
	video._remember_file = false
	video.dual_subtitles.select(8)
	check(video.mode_memory.sequence == serial, "Per-file memory disabled writes nothing")
	# Actual measured multi-line bounds must fit, rather than just clamping the measurement.
	video.caption.visible = true
	video.caption.text = "A long English sentence with wrapping. ".repeat(30) + "\n" + "中英字數差很多".repeat(8)
	video.subtitle_size = 2
	video.geometry = 0
	video._place_caption()
	check(video.caption.get_aabb().size.y <= video._flat.size.y, "Both flat text blocks fit inside the screen")
	video.geometry = 1
	video._place_caption()
	var label: Label = video.projected_subtitles.label
	check(label.get_minimum_size().y * label.scale.y <= video.projected_subtitles.PATCH_SIZE - 80, "Actual projected label layout fits the patch")
	for text in ["A".repeat(4000) + "\n第二字幕".repeat(20), "Line\n".repeat(1000)]:
		video.caption.text = text
		video._place_caption()
		var rendered := label.get_minimum_size() * label.scale
		var outline := label.get_theme_constant("outline_size") * label.scale.y
		check(rendered.y + 2 * outline <= video.projected_subtitles.PATCH_SIZE - 80 + 0.001, "Unbroken and extreme multiline text uses actual Label bounds")
		check(label.position.y >= outline and label.position.y + rendered.y + outline <= video.projected_subtitles.PATCH_SIZE, "Second block cannot grow the canvas beyond the texture")

	var state := {"has_video": true, "source_uri": "file:///ui.mp4", "subtitle_track": 2,
		"primary_subtitle_id": 2, "dual_subtitles": true, "dual_subtitles_available": true,
		"secondary_subtitle_track": 8, "subtitle_options": tracks}
	var menu := Menu.new()
	menu.state_provider = func(): return state
	var selected: Array = []
	menu.secondary_subtitle_requested.connect(func(id): selected.append(id))
	root.add_child(menu)
	menu.toggle()
	menu._activate(110)
	menu._on_choice_changed("subtitle_target", true)
	var primary_row := -1
	var second_row := -1
	for target in menu._subtitle_ids:
		if menu._subtitle_ids[target] == 2:
			primary_row = target
		if menu._subtitle_ids[target] == 8:
			second_row = target
	check(menu._buttons.any(func(button): return button.target == primary_row and not button.enabled), "Primary row disabled for secondary target")
	menu._activate(primary_row)
	check(selected.is_empty(), "Disabled row cannot dispatch even through direct activation")
	menu._activate(second_row)
	check(selected == [8], "Target switch dispatches the secondary channel")
	menu.free()
	video.free()
	for failure in failures:
		push_error(failure)
	print("Dual subtitle checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
