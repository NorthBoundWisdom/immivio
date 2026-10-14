extends SceneTree
const Main := preload("res://scripts/main.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/player_menu.gd")
var checks := 0
var failures: Array[String] = []


class Host:
	extends RefCounted
	var rates: Array = []
	var accept := true

	func set_mpv_speed(id: int, rate: float) -> bool:
		if not accept:
			return false
		rates.append([id, rate])
		return true

	func close_mpv_video(_id: int) -> void:
		pass


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func click(menu: Node3D, target: int) -> bool:
	for button in menu._buttons:
		if button.target == target and button.enabled:
			var point: Vector2 = button.rect.get_center()
			var origin: Vector3 = menu.to_global(Vector3(point.x, point.y, 1))
			menu.press_pointer("right", origin, -menu.global_basis.z, true)
			menu.release_pointer("right", origin, -menu.global_basis.z, true)
			return true
	return false


func drag(menu: Node3D, target: int, fraction: float) -> void:
	var button: Dictionary = menu._buttons.filter(func(row): return row.target == target)[0]
	var point := Vector3(0.03 + 0.6 * fraction, button.rect.get_center().y, 1)
	menu.press_pointer("right", menu.to_global(point), -menu.global_basis.z, true)
	menu.release_pointer("right", menu.to_global(point), -menu.global_basis.z, true)


func button(menu: Node3D, target: int) -> Dictionary:
	return menu._buttons.filter(func(row): return row.target == target)[0]


func reset_shown(menu: Node3D, target: int) -> bool:
	var reset := button(menu, target)
	return reset.enabled and reset.node.visible


func _run() -> void:
	preload("res://scripts/i18n.gd").use("en")
	var main := Main.new()
	main.settings_path = "user://playback-settings-regression.cfg"
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	main.video = video
	var host := Host.new()
	video.platform = host
	video.local_uri = "file:///movie.mp4"
	video.media.begin(7)
	video.media.format = {"width": 1920, "height": 1080}
	video.media.playback = {
		"details":
		{
			"pgs_supported": true,
			"subtitle_tracks":
			[{"id": 1, "codec": "subrip"}, {"id": 2, "codec": "hdmv_pgs_subtitle"}]
		}
	}
	video.flat_pose = Transform3D(Basis(), Vector3(0, 1.6, -2))
	video._apply_geometry()
	video.panel.visible = true
	var menu := Menu.new()
	menu.state_provider = main._menu_state
	menu.adjustment_requested.connect(main._on_playback_adjustment)
	menu.adjustment_committed.connect(main._save_playback_adjustments)
	menu.setting_requested.connect(main._on_player_setting)
	root.add_child(menu)
	menu.set_process(false)
	video.changed.connect(menu.refresh_values)
	main.player_menu = menu
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	root.add_child(camera)
	video.view_camera = camera
	main._place_menu(menu)
	check(
		menu.global_basis.orthonormalized().is_equal_approx(Basis.IDENTITY),
		"Below-eye menu remains upright"
	)
	var top_width := (
		camera.unproject_position(menu.to_global(Vector3(0.5, 1, 0))).x
		- camera.unproject_position(menu.to_global(Vector3(-0.5, 1, 0))).x
	)
	var bottom_width := (
		camera.unproject_position(menu.to_global(Vector3(0.5, 0, 0))).x
		- camera.unproject_position(menu.to_global(Vector3(-0.5, 0, 0))).x
	)
	check(
		is_equal_approx(top_width, bottom_width), "Upper popup rows are not compressed by menu tilt"
	)
	menu.toggle()
	check(
		not menu._buttons.any(func(item): return item.target in [11, 109, 111, 108, 210, 215, 216]),
		"Retired controls have no UI entry"
	)
	var fixed := menu.global_transform
	check(
		click(menu, Menu.QUICK_SPEED) and menu.section == 0 and menu.global_transform == fixed,
		"Speed popup keeps the toolbar fixed"
	)
	for speed in [.25, 3.0, 1.25]:
		var selected: bool = preload("res://tests/test_player_menu.gd").choose_setting(
			menu, "playback_speed", speed
		)
		check(
			(
				selected
				and is_equal_approx(video.playback_speed, speed)
				and host.rates.back()[0] == 7
				and is_equal_approx(host.rates.back()[1], speed)
			),
			"Popup slider sends actual native speed"
		)
	check(
		button(menu, Menu.SPEED_RESET).node.visible,
		"Dragging away from unity reveals the reset immediately"
	)
	check(
		click(menu, Menu.SPEED_RESET) and video.playback_speed == 1.0,
		"Speed reset sends unity rate"
	)
	check(
		not video.set_playback_speed(NAN) and not video.set_playback_speed(0),
		"Invalid native rates are rejected"
	)
	host.accept = false
	check(
		not video.set_playback_speed(2) and video.playback_speed == 1,
		"Rejected native rate leaves state intact"
	)
	host.accept = true
	video.stereo_sbs = true
	menu.refresh()
	check(
		(
			click(menu, Menu.IPD_SETTINGS)
			and menu._quick_open == "ipd"
			and menu.global_transform == fixed
		),
		"IPD replaces speed without moving the toolbar"
	)
	check(
		menu.choices.targets.values().any(
			func(item): return item.get("key") == "stereo_horizontal"
		),
		"Binocular popup exposes native alignment"
	)
	video.stereo_sbs = false
	menu.refresh()
	check(
		not menu._buttons.any(func(item): return item.target == Menu.IPD_SETTINGS),
		"Mono omits unavailable alignment"
	)
	click(menu, 110)
	check(
		(
			menu.choices.sliders.size() == 2
			and menu.text_snapshot().contains("External subtitles must match the video filename.")
		),
		"CC retains size, position and external-file guidance"
	)
	video.subtitles.select(2)
	menu.refresh()
	check(menu.choices.sliders.is_empty(), "PGS preserves source layout and hides text controls")
	video.subtitles.select(1)
	menu.refresh()
	check(menu.choices.sliders.size() == 2, "Text controls return despite PGS also being listed")
	menu.free()
	video.free()
	main.free()
	camera.free()
	for failure in failures:
		push_error(failure)
	print("Playback settings: %s (%d)" % ["passed" if failures.is_empty() else "failed", checks])
	quit(0 if failures.is_empty() else 1)
