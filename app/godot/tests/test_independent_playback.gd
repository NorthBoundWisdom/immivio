extends SceneTree
const Video := preload("res://scripts/mpv_video_display.gd")
const Preference := preload("res://scripts/track_preference.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Palette := preload("res://scripts/caption_palette.gd")
const Base := preload("res://tests/test_player_menu.gd")
var failures: Array[String] = []
class Host extends Base.Host:
	var reject := false
	var serial := 20
	func open_mpv_video(uri: String, start: int, stereo: bool, profile: String, alpha: bool, vulkan: bool, depth: bool = false, tb: bool = false, exact: bool = false) -> int:
		super.open_mpv_video(uri, start, stereo, profile, alpha, vulkan, depth, tb, exact)
		serial += 1; return serial
	func set_mpv_audio(id: int, track: int, volume: float, muted: bool) -> bool:
		if reject: return false
		return super.set_mpv_audio(id, track, volume, muted)
	func set_mpv_subtitle(id: int, track: int) -> bool:
		if reject: return false
		return super.set_mpv_subtitle(id, track)
	func revise_mpv_video(_id: int, _stereo: bool, _alpha: bool, _profile: String, _position: int, _depth: bool = false, _tb: bool = false, _exact: bool = false) -> int:
		serial += 1; return serial

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var rows := [{"id": 2, "language": "zh", "title": "Commentary", "codec": "aac"}]
	var choice := Preference.capture(2, rows)
	check(Preference.resolve(choice, [{"id": 2, "language": "en"}]) == null, "Reused IDs cannot select another language")
	var moved := rows.duplicate(true); moved[0].id = 8
	check(Preference.resolve(choice, moved) == 8, "A unique metadata match survives renumbering")
	moved.append({"id": 9, "language": "zh", "title": "Commentary", "codec": "aac"})
	check(Preference.resolve(choice, moved) == null, "Ambiguous renamed tracks remain unresolved")
	check(not Preference.valid({"id": NAN}) and not Preference.valid({"id": 1.5}), "Invalid serialized IDs are rejected")
	var video := Video.new(); root.add_child(video); video.set_process(false)
	var host := Host.new(); video.platform = host
	video.history_enabled = false
	var folder := ProjectSettings.globalize_path("res://../../build/output/independent-playback-%d" % Time.get_ticks_usec())
	video.mode_memory = Memory.new(folder)
	video.open_local("file:///track-a.mp4", "A")
	var details := {"audio_tracks": rows, "subtitle_tracks": [{"id": 3, "language": "en", "codec": "subrip"}]}
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(video.select_audio_track(2) and video.set_subtitle_track(0), "Explicit audio and subtitle-off choices accepted")
	var saved := video.mode_memory.lookup(video.local_uri)
	check(saved.track_choices.audio.id == 2 and saved.track_choices.subtitle.id == 0, "Choices are stored with existing per-file settings")
	host.reject = true
	check(not video.select_audio_track(-1) and video._track_choices.audio.id == 2, "Rejected audio choice cannot overwrite preferences")
	check(not video.set_subtitle_track(3) and video._track_choices.subtitle.id == 0, "Rejected subtitle choice cannot overwrite preferences")
	host.reject = false
	video.open_local("file:///track-b.mp4", "B")
	check(video._track_choices.is_empty(), "Unrelated video does not inherit track choices")
	video.mode_memory = Memory.new(folder); video.mode_memory.load_saved()
	video.open_local("file:///track-a.mp4", "A")
	var id := video.media.session_id
	video._on_state(id - 1, JSON.stringify({"state": "paused", "details": details}))
	check(video.audio_track_id == -1, "Old-session metadata cannot restore tracks")
	details.audio_tracks[0].id = 8
	video._on_state(id, JSON.stringify({"state": "paused", "details": details}))
	check(video.audio_track_id == 8 and video.subtitles.requested_track == 0 and video._tracks_pending.is_empty(), "Fresh metadata restores renamed audio and explicit subtitle off")
	video._request_revision()
	video._try_revision()
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(video.audio_track_id == 8 and video.subtitles.requested_track == 0, "Processing revisions restore explicit intent")
	video.select_audio_track(-1)
	video.open_local("file:///track-a.mp4", "A")
	video._on_state(video.media.session_id, JSON.stringify({"state": "paused", "details": details}))
	check(video.audio_track_id == -1 and video._track_choices.audio.id == -1, "Automatic audio is an explicit remembered option")
	var audio_calls: Array = host.calls.filter(func(call): return call[0] == "audio")
	check(audio_calls.all(func(call): return call[3] == 100.0 and call[4] == false), "Remembered audio tracks never introduce software volume or mute")
	video.subtitle_palette = 2; video.caption.text = "Sample"; video.caption.visible = true
	video._place_caption()
	check(video.caption.modulate == Palette.INK[2] and video.caption.outline_modulate == Color.BLACK, "Flat captions use selected palette")
	var menu := Menu.new(); root.add_child(menu)
	menu._state = {"source_uri": "file:///a", "has_video": true, "audio_available": true, "geometry": 0, "depth_strength": 0.7}
	check(not menu._shortcut_double_tap(109, 1000) and menu._shortcut_double_tap(109, 1200), "Same-target quick taps form a pair")
	check(not menu._shortcut_double_tap(109, 1250), "Third tap begins a new pair")
	menu._state.source_uri = "file:///b"
	check(not menu._shortcut_double_tap(109, 1300), "Switching videos breaks a tap pair")
	check(not menu._shortcut_double_tap(112, 1350), "Different targets never form a pair")
	var state := {"source_uri": "file:///shortcuts", "has_video": true, "audio_available": true, "geometry": 0, "depth_strength": 0.7, "depth_requested": false, "muted": false}
	menu.state_provider = func(): return state
	menu.action_requested.connect(func(action):
		if action == "mute": state.muted = not state.muted)
	menu.depth_strength_requested.connect(func(strength): state.depth_requested = strength > 0)
	menu.visible = true; menu.refresh()
	check(not menu._buttons.any(func(button): return button.target == 109), "System-volume playback exposes no application volume button")
	menu._activate_hit({"target": 112, "enabled": true})
	menu._activate_hit({"target": 112, "enabled": true})
	check(not state.depth_requested, "A forged old 3D button event cannot enable the removed effect")
	menu._activate_hit({"target": 112, "enabled": true})
	menu._activate_hit({"target": 112, "enabled": true})
	check(not state.depth_requested and is_equal_approx(state.depth_strength, 0.7), "Removed conversion remains unavailable")
	var library := preload("res://scripts/library_menu.gd").new(); root.add_child(library)
	library.visible = true
	var title := "A long media filename with Chinese 字幕 and details ".repeat(5) + ".mp4"
	library._row_button(9001, title, "", "video", Vector2.ZERO, false)
	library._hover.right_hand = 9001; library._update_tooltip()
	check(library._tooltip != null and library._tooltip.get_child(0).text == title, "Filename hover retains full text rather than another ellipsis")
	check(library._tooltip.mesh.size.y > 0.046 and library._tooltip.mesh.size.x <= library.TOOLTIP_MAX_WIDTH, "Long filenames wrap inside the fixed tooltip width")
	library.free()
	menu.free(); video.free()
	for failure in failures: push_error(failure)
	print("Independent playback checks: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
