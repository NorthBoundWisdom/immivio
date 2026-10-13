extends SceneTree
const Main := preload("res://scripts/main.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Store := preload("res://scripts/bookmark_store.gd")
const I18n := preload("res://scripts/i18n.gd")
var checks := 0
var failures: Array[String] = []

class Host extends RefCounted:
	var accepted := true
	var calls: Array = []
	func set_mpv_audio(id: int, track: int, volume: float, muted: bool) -> bool:
		calls.append([id, track, volume, muted]); return accepted
	func close_mpv_video(_id: int) -> void: pass

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)

func button(menu: Node3D, target: int) -> Dictionary:
	for item in menu._buttons:
		if item.target == target: return item
	return {}

func point(menu: Node3D, target: int) -> Vector3:
	var item := button(menu, target)
	return item.node.to_global(Vector3(0, 0, 1)) if not item.is_empty() else Vector3.ZERO

func tap(menu: Node3D, target: int) -> void:
	var origin := point(menu, target)
	menu.press_pointer("left_hand", origin, -menu.global_basis.z, true)
	menu.release_pointer("left_hand", origin, -menu.global_basis.z, true)

func choice(menu: Node3D, value: int) -> int:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.kind == "choose" and int(item.value) == value: return target
	return -1

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	I18n.use("en")
	var directory := ProjectSettings.globalize_path("res://../../build/output/audio-popup-host/" + str(Time.get_ticks_usec()))
	var video := Video.new()
	video.bookmark_store = Store.new(directory.path_join("bookmarks"))
	root.add_child(video); video.set_process(false)
	var host := Host.new(); video.platform = host
	video.local_uri = "file:///movie.mp4"; video.media.begin(7); video.media.state = "playing"
	video.control.duration_ms = 7200000
	video._bookmark_metadata = {"basename": "movie.mp4", "size": 1000000}; video._bookmark_resolve()
	video.media.playback = {"details": {"audio_track_id": "1", "audio_tracks": [
		{"id": 1, "language": "eng"}, {"id": 2, "language": "jpn"}]}}
	var main := Main.new(); main.video = video; main.settings_path = directory.path_join("settings.cfg")
	var menu := Menu.new(); main.player_menu = menu
	menu.state_provider = main._menu_state
	root.add_child(menu); menu.toggle(); menu.set_process(false)
	check(not menu._buttons.any(func(item): return item.target in [109, 111, 160]), "Audio-track and volume UI have no remaining buttons")
	check(not menu.choices.targets.values().any(func(item): return item.get("key") in ["audio_track", "volume", "muted"]), "Retired audio controls cannot create interactive fields")
	video._apply_audio_track(2)
	check(host.calls.back() == [7, 2, 100.0, false], "Retained audio-track restoration uses unity gain and no application mute")
	host.accepted = false
	check(not video.select_audio_track(1) and video.audio_track_id == 2, "Rejected native track request preserves the selection")
	host.accepted = true
	video.media.playback.details.audio_tracks.append({"id": 4, "external": true, "title": "Clone voice"})
	check(video.select_audio_track(4) and video.prefer_clone_voice and host.calls.back() == [7, 4, 100.0, false], "Automatic dubbing can retain its native track without application volume")
	I18n.use("zh")
	check(main._audio_option_label({"id": 4, "external": true, "title": "Clone voice"}) == "配音", "Clone voice title is localized without changing native identity")
	check(main._audio_option_label({"id": 1, "language": "eng"}) == "音轨 1 · 英语", "Audio labels localize language and track number")
	I18n.use("en"); menu.free(); video.free(); main.free()
	print("Audio popup checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
