extends SceneTree

const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var checks := 0


class Host:
	extends RefCounted
	var speeds := []

	func ai_enabled() -> bool:
		return false

	func close_mpv_video(_id: int) -> void:
		pass

	func set_mpv_speed(id: int, speed: float) -> bool:
		speeds.append([id, speed])
		return true

	func set_mpv_playing(_id: int, _playing: bool) -> bool:
		return true


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func button(menu: Node3D, target: int) -> Dictionary:
	for item in menu.controls_snapshot():
		if item.target == target:
			return item
	return {}


func click(menu: Node3D, target: int) -> bool:
	var item := button(menu, target)
	if item.is_empty():
		return false
	var origin: Vector3 = item.node.global_position + menu.global_basis.z * .5
	var ray: Vector3 = -menu.global_basis.z
	var result: bool = menu.press_pointer("right_hand", origin, ray, true)
	menu.release_pointer("right_hand", origin, ray, true)
	return result


func choose(menu: Node3D, key: String, value: Variant) -> bool:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.kind == "choose" and item.key == key and menu.choices.same(item.value, value):
			return click(menu, target)
	return false


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var folder := ProjectSettings.globalize_path(
		"res://../../build/tests/godot/quick-playback-settings"
	)
	DirAccess.make_dir_recursive_absolute(folder)
	var main := Main.new()
	main.settings_path = folder.path_join("settings-%d.cfg" % Time.get_ticks_usec())
	root.add_child(main)
	main.set_process(false)
	main.report_timer.stop()
	main.menu_compositor.set_process(false)
	main.video.set_process(false)
	main.library_menu.dismiss()
	var host := Host.new()
	main.video.platform = host
	main.video.local_uri = "file:///quick-settings-synthetic.mp4"
	main.video.media.begin(1)
	main.video.media.state = "playing"
	main.video.control.duration_ms = 60000
	main.video.test_set_waiting_for_frame(false)
	main.video.requested_play = true
	var menu: Node3D = main.video_menu
	menu.set_process(false)
	menu.toggle()
	check(
		button(menu, 104).is_empty() and button(menu, Menu.TEMP_PASSTHROUGH).is_empty(),
		"The toolbar omits the packed-alpha override and temporary scene passthrough"
	)
	var sides := {
		-1: [12, Menu.SYNC_SETTINGS, Menu.QUEUE_SETTINGS, Menu.BROWSE, Menu.QUICK_SPEED],
		1: [110, Menu.MODE, Menu.QUICK_COLOR]
	}
	for side in sides:
		var targets: Array = sides[side]
		for target in targets:
			var item := button(menu, target)
			check(
				(
					not item.is_empty()
					and item.node.visible
					and is_equal_approx(item.rect.get_center().y, .025)
					and signf(item.rect.get_center().x) == side
					and item.rect.position.x > -.58
					and item.rect.end.x < .58
				),
				"Quick controls stay on their assigned side: %d" % target
			)
		for index in targets.size() - 1:
			check(
				not button(menu, targets[index]).rect.intersects(
					button(menu, targets[index + 1]).rect
				),
				"Adjacent toolbar controls do not overlap"
			)
	check(
		(
			click(menu, Menu.QUICK_SPEED)
			and menu.section == 0
			and menu.popup_snapshot().quick_open == "speed"
			and not menu.allows_playback_sticks()
		),
		"Speed opens a small popup on the playback page and suspends stick shortcuts"
	)
	menu.test_set_hover("", menu.NONE)
	main.menu_touched_ms = Time.get_ticks_msec() - main.CONTROLS_HIDE_MS - 1
	main._update_controls_visibility(menu)
	check(menu.visible, "Quick settings remain visible after the ordinary playback idle timeout")
	check(
		(
			choose(menu, "playback_speed", 1.5)
			and is_equal_approx(main.video.playback_speed, 1.5)
			and host.speeds.back() == [1, 1.5]
		),
		"Speed preset sends a real playback command"
	)
	var commits := []
	menu.adjustment_committed.connect(func(): commits.append(true))
	var slider_target := -1
	for target in menu.choices.targets:
		if menu.choices.targets[target].kind == "slider":
			slider_target = target
			break
	var slider: Dictionary = menu.choices.sliders[slider_target]
	var x: float = (
		slider.node.position.x + slider.left + slider.width * inverse_lerp(.25, 3.0, 1.25)
	)
	var origin: Vector3 = menu.to_global(Vector3(x, slider.node.position.y, .5))
	var ray: Vector3 = -menu.global_basis.z
	check(
		(
			menu.press_pointer("left_hand", origin, ray, true)
			and menu.has_pointer_capture()
			and is_equal_approx(main.video.playback_speed, 1.25)
		),
		"Ray slider previews speed and captures its hand"
	)
	check(
		menu.choices.sliders[slider_target].label.text == "1.25×",
		"Speed readout preserves the slider's precision"
	)
	menu.release_pointer("right_hand", origin, ray, true)
	check(menu.has_pointer_capture(), "Other hand cannot release the speed slider")
	menu.release_pointer("left_hand", origin, ray, true)
	check(
		not menu.has_pointer_capture() and commits.size() == 1,
		"Speed slider release commits preferences once"
	)
	check(
		is_equal_approx(float(menu._state.playback_speed), 1.25),
		"Quick speed matches the actual playback state after release"
	)
	check(
		(
			click(menu, Menu.QUICK_COLOR)
			and menu.popup_snapshot().quick_open == "color"
			and menu.section == 0
		),
		"Color popup replaces speed without switching pages"
	)
	check(
		click(menu, Menu.QUEUE_SETTINGS) and menu.popup_snapshot().quick_open == "queue",
		"Queue replaces color in the same toolbar plane"
	)
	check(
		(
			not menu._tips.values().has("Loop")
			and not menu.choices.targets.values().any(func(item): return item.get("key") == "loop")
		),
		"Playback exposes no loop control"
	)
	check(
		click(menu, Menu.MODE) and menu.popup_snapshot().quick_open.is_empty() and menu._mode_open,
		"Mode picker replaces quick settings"
	)
	check(
		(
			click(menu, Menu.QUICK_SPEED)
			and not menu._mode_open
			and menu.popup_snapshot().quick_open == "speed"
		),
		"Quick settings replace the mode picker"
	)
	check(
		(
			click(menu, Menu.QUICK_CLOSE)
			and menu.popup_snapshot().quick_open.is_empty()
			and menu.visible
			and menu.allows_playback_sticks()
		),
		"Popup close returns to playback and restores stick shortcuts"
	)
	click(menu, Menu.QUICK_SPEED)
	click(menu, 102)
	check(
		(
			menu.popup_snapshot().quick_open.is_empty()
			and not main.video.requested_play
			and menu.choices.targets.is_empty()
		),
		"Play/pause closes the popup and removes its old controls"
	)
	main.video.geometry = 1
	menu.refresh()
	check(
		(
			not menu.controls_snapshot().any(func(item): return item.target == 210)
			and not button(menu, Menu.QUICK_SPEED).is_empty()
		),
		"Immersive playback hides flat-screen settings and retains speed"
	)
	click(menu, Menu.QUICK_SPEED)
	menu.dismiss()
	menu.toggle()
	check(
		menu.popup_snapshot().quick_open.is_empty(),
		"Reopening playback never retains a stale popup"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Quick playback settings: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
