extends SceneTree

const Menu := preload("res://scripts/library_menu.gd")
const Main := preload("res://scripts/main.gd")
var checks := 0
var failures: Array[String] = []
var selected: Array[String] = []
var player_returns := 0


class Catalog:
	extends RefCounted

	func list_recent() -> Array[Dictionary]:
		var entries: Array[Dictionary] = []
		for index in 32:
			entries.append(
				{
					"uri": "content://pointer/%d.mp4" % index,
					"title": "File %d" % index,
					"position_ms": 1000
				}
			)
		return entries


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func target_origin(menu: Node3D, x: float, y: float, z: float = 1.0) -> Vector3:
	return menu.to_global(Vector3(x, y, z))


func button_origin(menu: Node3D, target: int) -> Vector3:
	var button: Dictionary = menu._buttons.filter(func(item): return item.target == target)[0]
	var centre: Vector2 = button.rect.get_center()
	return target_origin(menu, centre.x, centre.y)


func check_row_geometry(menu: Node3D) -> void:
	for list_mode in [false, true]:
		menu.list_view = list_mode
		menu.refresh()
		var first: Dictionary = menu._buttons.filter(func(b): return b.target == Menu.ROW_BASE)[0]
		var second: Dictionary = menu._buttons.filter(func(b): return b.target == Menu.ROW_BASE + 1)[0]
		var a: Rect2 = first.rect
		var b: Rect2 = second.rect
		var gap: Variant = null
		if a.end.x < b.position.x:
			gap = Vector2((a.end.x + b.position.x) * .5, a.get_center().y)
		elif b.end.y < a.position.y:
			gap = Vector2(a.get_center().x, (b.end.y + a.position.y) * .5)
		check(gap != null, "Adjacent production rows retain a gap")
		if gap != null:
			var origin := menu.to_global(Vector3(gap.x, gap.y, 1))
			check(
				menu.ray_hit(origin, -menu.global_basis.z).is_empty(),
				"Adjacent production rows reject gap rays"
			)
		var half: Vector2 = a.size * .5
		var corner: Vector3 = first.node.to_global(Vector3(half.x - .001, half.y - .001, 1))
		var direction: Vector3 = -first.node.global_basis.z
		check(
			menu.ray_hit(corner, direction).is_empty(),
			"Transparent production row corner rejects the ray"
		)
		var selections := selected.size()
		menu.press_pointer("right_hand", corner, direction, true)
		menu.release_pointer("right_hand", corner, direction, true)
		check(
			menu.visible and selected.size() == selections,
			"Transparent rounded corner cannot activate a file"
		)
	menu.list_view = false
	menu.refresh()


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _run() -> void:
	preload("res://scripts/i18n.gd").use("en")  # text checks are written in English
	var menu := Menu.new()
	menu.catalog = Catalog.new()
	menu.chosen.connect(func(uri: String, _title: String): selected.append(uri))
	menu.player_requested.connect(func(): player_returns += 1)
	root.add_child(menu)
	menu.toggle()
	check_row_geometry(menu)
	var direction := -menu.global_basis.z
	var row := button_origin(menu, Menu.ROW_BASE)
	check(menu.ray_hit(row, direction).target == Menu.ROW_BASE, "Ray selects actual row geometry")
	menu.update_pointer("left_hand", row, direction, true)
	check(
		(
			selected.is_empty()
			and menu._hover.left_hand == Menu.ROW_BASE
			and menu._pointers.left_hand.dot.visible
		),
		"Hover displays dot without activating"
	)
	check(
		not menu.press_pointer("right_hand", target_origin(menu, 10, 0), direction, true),
		"Other hand miss cannot activate left hover"
	)
	check(
		not menu.press_pointer("left_hand", target_origin(menu, 10, 0), direction, true),
		"Trigger recomputes moved ray instead of stale hover"
	)
	menu.update_pointer("left_hand", row, direction, false)
	check(
		(
			menu._hover.left_hand == Menu.NONE
			and not menu._pointers.left_hand.line.visible
			and not menu._pointers.left_hand.dot.visible
		),
		"Tracking loss clears hover and visuals"
	)
	check(
		not menu.press_pointer("left_hand", row, direction, false),
		"Untracked controller cannot click"
	)
	for sample in [
		[row, Vector3.ZERO],
		[row, Vector3(INF, 0, -1)],
		[Vector3(NAN, 0, 0), direction],
		[row, menu.global_basis.x],
		[row, -direction],
		[menu.to_global(menu.to_local(row) * Vector3(1, 1, -1)), -direction],
		[row + menu.global_basis.z * 5, direction],
		[button_origin(menu, Menu.RECENT_PREVIOUS), direction]
	]:
		check(
			menu.ray_hit(sample[0], sample[1]).is_empty(),
			"Invalid/parallel/rear/far/disabled button rejects ray"
		)
	menu.rotation = Vector3(0.2, 0.7, -0.1)
	menu.position = Vector3(2, 3, -4)
	direction = -menu.global_basis.z
	row = button_origin(menu, Menu.ROW_BASE)
	check(
		menu.ray_hit(row, direction).target == Menu.ROW_BASE,
		"World transformed menu keeps correct hit"
	)
	menu.press_pointer("left_hand", row, direction, true)
	menu.release_pointer("left_hand", row, direction, true)
	check(
		selected == ["content://pointer/0.mp4"] and not menu.visible,
		"Correct hand emits exact URI on release and closes once"
	)
	menu.press_pointer("left_hand", row, direction, true)
	menu.release_pointer("left_hand", row, direction, true)
	check(selected.size() == 1, "Closed menu rejects repeated activation")
	menu.toggle()
	for expected in range(1, menu._recent_page_count()):
		check(
			(
				menu.press_pointer(
					"right_hand", button_origin(menu, Menu.RECENT_NEXT), direction, true
				)
				and menu._recent_page == expected
			),
			"Point-and-trigger next reaches page %d" % expected
		)
	check(
		menu.ray_hit(button_origin(menu, Menu.RECENT_NEXT), direction).is_empty(),
		"Last page disables next"
	)
	check(
		(
			menu.press_pointer(
				"left_hand", button_origin(menu, Menu.RECENT_PREVIOUS), direction, true
			)
			and menu._recent_page == 1
		),
		"Previous is selected by pointer"
	)
	menu._recent_page = 2
	menu.refresh()
	var last_row := button_origin(menu, Menu.ROW_BASE + 6)
	menu.press_pointer("right_hand", last_row, direction, true)
	menu.release_pointer("right_hand", last_row, direction, true)
	check(
		selected.back() == "content://pointer/30.mp4", "Last page row maps to exact catalog entry"
	)
	menu.playback_browser = true
	menu.toggle()
	var close_origin := button_origin(menu, Menu.PLAYER)
	var selections_before_close := selected.size()
	check(
		menu.press_pointer("right_hand", close_origin, direction, true),
		"Playback library has a pointer close button"
	)
	check(
		not menu.visible and player_returns == 1 and selected.size() == selections_before_close,
		"Closing the library returns to playback without opening a file"
	)
	menu.playback_browser = false
	# Use real XRController3D and registered Godot trackers with synthetic poses.
	# This validates engine/Main dispatch, not physical Quest tracking.
	menu.rotation = Vector3.ZERO
	menu.position = Vector3(0, -0.03, -1.55)
	menu.toggle()
	var main := Main.new()  # Keep outside tree to avoid starting the actual player.
	main.library_menu = menu
	var origin := XROrigin3D.new()
	root.add_child(origin)
	var trackers: Array[XRControllerTracker] = []
	for hand in ["left_hand", "right_hand"]:
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = hand
		tracker.set_pose(
			"aim",
			Transform3D(Basis.IDENTITY, button_origin(menu, Menu.ROW_BASE)),
			Vector3.ZERO,
			Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH
		)
		tracker.set_input("primary", Vector2(0, -1))
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		var controller := XRController3D.new()
		controller.tracker = hand
		controller.pose = "aim"
		controller.button_pressed.connect(main._on_controller_button.bind(hand))
		controller.button_released.connect(main._on_controller_release.bind(hand))
		origin.add_child(controller)
		if hand == "left_hand":
			main.left_controller = controller
		else:
			main.right_controller = controller
	await process_frame
	for tracker in trackers:
		tracker.set_pose(
			"aim",
			tracker.get_pose("aim").transform,
			Vector3.ZERO,
			Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH
		)
	for _frame in 100:
		main._process(1.0 / 72.0)
	check(
		(
			menu._recent_page == 0
			and menu.scroll == 0
			and menu._hover.left_hand == Menu.ROW_BASE
			and menu._hover.right_hand == Menu.ROW_BASE
		),
		"Held real tracker axes never navigate menu; both rays hover independently"
	)
	trackers[0].set_input("ax_button", true)
	check(menu.visible and selected.size() == 2, "A/X cannot select menu focus")
	trackers[0].invalidate_pose("aim")
	trackers[0].set_input("trigger_click", true)
	check(
		menu.visible and selected.size() == 2, "Actual tracking loss blocks Main trigger dispatch"
	)
	trackers[1].set_input("trigger_click", true)
	trackers[1].set_input("trigger_click", false)
	check(
		not menu.visible and selected.size() == 3 and selected.back() == "content://pointer/0.mp4",
		"Tracked other controller button signal selects its ray"
	)
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	origin.free()
	main.free()
	menu.free()
	var output := ProjectSettings.globalize_path(
		"res://../../build/tests/godot/recent-pointer-host"
	)
	DirAccess.make_dir_recursive_absolute(output)
	(
		FileAccess
		. open(output.path_join("verification.json"), FileAccess.WRITE)
		. store_string(
			(
				JSON
				. stringify(
					{
						"state": "passed" if failures.is_empty() else "failed",
						"checks": checks,
						"failures": failures,
						"scope":
						"Production menu geometry/render state and real Godot XRController3D/Main dispatch using synthetic trackers; physical Quest pointing unverified"
					},
					"\t"
				)
			)
		)
	)
	for failure in failures:
		push_error(failure)
	print(
		(
			"Recent pointer host checks: %s (%d)"
			% ["passed" if failures.is_empty() else "failed", checks]
		)
	)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
