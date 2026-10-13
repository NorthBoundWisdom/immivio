extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")
const Main := preload("res://scripts/main.gd")
const Player := preload("res://scripts/player_menu.gd")
const Library := preload("res://scripts/library_menu.gd")
const Policy := preload("res://scripts/seek_policy.gd")
const Store := preload("res://scripts/bookmark_store.gd")
var checks := 0
var failures: Array[String] = []

class BindingProbe extends "res://scripts/pair_texture_binding.gd":
	func bind(target: ShaderMaterial, pair: Dictionary) -> bool:
		material = target; ticket = pair.duplicate(true); return true

class Host extends RefCounted:
	var opens: Array = []
	var revisions: Array = []
	var pair: Dictionary = {}
	func mpv_supported() -> bool: return true
	func open_mpv_video(uri: String, start: int, _stereo: bool, _profile: String, _alpha: bool, _vulkan: bool,
		_depth: bool, _tb: bool, exact: bool) -> int:
		opens.append([uri, start, exact]); return 7
	func revise_mpv_video(id: int, _stereo: bool, _alpha: bool, _profile: String, target: int,
		_depth: bool, _tb: bool, exact: bool) -> int:
		revisions.append([id, target, exact]); return 0 # Keep the request queued to exercise busy retries.
	func set_mpv_playing(_id: int, _playing: bool) -> void: pass
	func close_mpv_video(_id: int) -> void: pass
	func claim_mpv_pair(_id: int, _token: int) -> String: return JSON.stringify(pair)
	func acknowledge_mpv_pair(_id: int, _token: int) -> bool: return true
	func detach_mpv_pair(_id: int, _token: int) -> bool: return true

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func origin(menu: Node3D, target: int) -> Vector3:
	for button in menu._buttons:
		if button.target == target:
			return menu.to_global(Vector3(button.rect.get_center().x, button.rect.get_center().y, 1))
	return Vector3.ZERO

func tap(menu: Node3D, target: int) -> void:
	var point := origin(menu, target)
	menu.press_pointer("left_hand", point, -menu.global_basis.z, true)
	menu.release_pointer("left_hand", point, -menu.global_basis.z, true)

func clear_pending(video: Node3D) -> void:
	video.control.reject(); video._pending_revision.clear(); video._waiting_first = false

func drag_timeline(menu: Node3D, video: Node3D, bridge: Host, exact: bool) -> void:
	video.control.observe(5000, 60000)
	menu.refresh_values()
	var before := bridge.revisions.size()
	var direction: Vector3 = -menu.global_basis.z
	var start: Vector3 = menu.to_global(Vector3(-menu.BAR_SEEK / 4, menu.BAR_SEEK_Y, 1))
	var end: Vector3 = menu.to_global(Vector3(menu.BAR_SEEK / 4, menu.BAR_SEEK_Y, 1))
	check(menu.press_pointer("left_hand", start, direction, true), "Timeline trigger begins a drag")
	menu.update_pointer("left_hand", end, direction, true)
	check(bridge.revisions.size() == before and menu._seek_preview == 45000, "Dragging previews the final time without decoding intermediate positions")
	menu.release_pointer("left_hand", end, direction, true)
	check(bridge.revisions.size() == before + 1 and bridge.revisions.back() == [7, 45000, exact],
		"Timeline release uses %s policy" % ("exact" if exact else "default fast"))
	clear_pending(video)

func labels(menu: Node) -> String:
	return "\n".join(menu.find_children("*", "Label3D", true, false).map(func(label): return label.text))

func choose(menu: Node3D, key: String, value: Variant) -> void:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.get("kind") == "open" and item.get("key") == key:
			tap(menu, int(target)); break
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.get("kind") == "choose" and item.get("key") == key and menu.choices.same(item.value, value):
			tap(menu, int(target)); return

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	preload("res://scripts/i18n.gd").use("zh")
	var directory := ProjectSettings.globalize_path("res://../../build/output/seek-policy-host/" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	var bridge := Host.new()
	var video := Video.new()
	root.add_child(video); video.set_process(false)
	video.platform = bridge; video.bookmark_store = Store.new(directory.path_join("bookmarks"))
	video._binding = BindingProbe.new()
	var main := Main.new()
	main.video = video; main.settings_path = directory.path_join("settings.cfg")
	main._restore_seek_settings()
	check(Policy.DEFAULT == Policy.SPEED and video.seek_mode == Policy.DEFAULT and video.bookmark_seek_mode == Policy.GLOBAL,
		"New and existing empty settings default to fast seek and inherited bookmark mode")
	check(Policy.normalize(null) == Policy.SPEED and Policy.normalize(17) == Policy.SPEED and Policy.normalize("bad") == Policy.SPEED,
		"Invalid stored global settings fall back to speed")
	check(Policy.bookmark_override("bad") == Policy.GLOBAL, "Invalid bookmark override inherits global")
	var uri := "https://fixture.example/mock.mp4"
	video.open_local(uri, "Movie", 12000, false)
	check(bridge.opens.back() == [uri, 12000, false], "Initial and resumed opening propagate keyframe mode to Android")
	var timeline := Player.new()
	timeline.state_provider = func(): return {"has_video": true, "duration_ms": 60000, "position_ms": video.control.display_position_ms()}
	timeline.seek_requested.connect(main._on_menu_seek)
	root.add_child(timeline); timeline.toggle(); timeline.set_process(false)
	drag_timeline(timeline, video, bridge, false)
	main.settings.set_value("video", "seek_mode", Policy.EXACT)
	main.settings.set_value("video", "bookmark_seek_mode", Policy.EXACT)
	main._restore_seek_settings()
	check(video.seek_mode == Policy.DEFAULT and video.bookmark_seek_mode == Policy.GLOBAL, "Retired saved precision choices cannot change the default seek behavior")
	main._on_setting_changed("seek_mode", Policy.EXACT)
	check(video.seek_mode == Policy.DEFAULT and not main._library_settings().has("seek_mode"), "Stale UI precision commands have no effect")
	video.control.duration_ms = 60000; video.media.state = "paused"
	video.media.playback = {"details": {"seekable": "yes", "partially_seekable": "no"}}
	video._bookmark_metadata = {"basename": "mock.mp4", "size": 123456}; video._bookmark_resolve()
	var marker := video.bookmark_store.add(uri, "mock.mp4", 123456, 23456)
	clear_pending(video)
	video.bookmark_action("seek", str(marker.id), video.bookmark_scope())
	check(bridge.revisions.back() == [7, 23456, false], "Stored bookmarks use the ordinary default seek path")
	var library := Library.new(); root.add_child(library); library.section = Library.Section.SETTINGS; library.tab = Library.VIDEO_TAB; library.refresh()
	check(not library.rows.any(func(row): return row.get("key") == "seek_mode"), "Library exposes no precision selector")
	library.free(); timeline.free(); video.free(); main.free()
	for failure in failures: push_error(failure)
	print("Seek policy: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
