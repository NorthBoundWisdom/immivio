extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func find_target(menu: Node3D, kind: String, key: String, value: Variant = null) -> int:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if (
			item.get("kind") == kind
			and item.get("key") == key
			and (kind == "open" or menu.choices.same(item.get("value"), value))
		):
			return target
	return -1


func acknowledge(surface: Node3D, menu: Node3D) -> void:
	surface._update_bounds()
	surface.presented = {
		"visible": true,
		"menu_id": menu.get_instance_id(),
		"layout_revision": menu.layout_revision,
		"menu_revisions": surface._capture_revisions(),
		"pose": Surface.capture_pose(menu),
		"rect": surface.surface_rect,
		"curve_radius": menu.curve_radius
	}


func ray_for(menu: Node3D, surface: Node3D, target: int) -> Array:
	for button in menu._buttons:
		if button.target != target:
			continue
		var pose := Surface.capture_pose(menu)
		var local: Vector3 = pose.affine_inverse() * button.node.global_position
		var centre: Vector2 = surface.surface_rect.get_center()
		var angle: float = (local.x - centre.x) / menu.curve_radius
		var world := (
			pose
			* Vector3(
				centre.x + sin(angle) * menu.curve_radius,
				local.y,
				menu.curve_radius * (1 - cos(angle))
			)
		)
		var origin := pose * Vector3(-0.25, -0.45, 1.5)
		return [origin, (world - origin).normalized()]
	return []


func held_tap(menu: Node3D, surface: Node3D, target: int) -> bool:
	var ray := ray_for(menu, surface, target)
	if ray.is_empty():
		return false
	check(
		menu.ray_hit(ray[0], ray[1]).get("target", -1) == target,
		"Presented curved ray hits the requested control"
	)
	if not menu.press_pointer("left_hand", ray[0], ray[1], true):
		return false
	# A real trigger remains held across pointer updates, unlike an immediate tap.
	for frame in 3:
		menu.update_pointer("left_hand", ray[0], ray[1], true)
	print("Stationary capture: ", menu.choices.capture)
	check(
		not menu.choices.capture.get("moved", false), "Stationary XR pointer must not become a drag"
	)
	menu.release_pointer("left_hand", ray[0], ray[1], true)
	return true


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	for native in [false, true]:
		var state := {"language": "en", "history": true}
		var events: Array = []
		var menu := Library.new()
		menu.section = Library.Section.SETTINGS
		menu.tab = Library.GENERAL_TAB
		menu.settings_provider = func(): return state
		menu.setting_changed.connect(
			func(key, value):
				events.append([key, value])
				state[key] = value
		)
		root.add_child(menu)
		menu.set_process(false)
		menu.toggle()
		menu.global_transform = Transform3D(Basis(Vector3.UP, 0.25), Vector3(0, 1.5, -2))
		var surface := Surface.new()
		root.add_child(surface)
		surface.set_process(false)
		surface.active_menu = menu
		surface.menus = [menu]
		surface.native_supported = native
		surface.scene_curved = not native
		menu.xr_surface = surface
		acknowledge(surface, menu)
		check(
			held_tap(menu, surface, find_target(menu, "open", "language")),
			"Press/release curved dropdown"
		)
		check(
			menu.choices.opened == "language" and not menu.choices.popup.is_empty(),
			"Curved dropdown actually opens with intervening updates"
		)
		if menu.choices.opened == "language":
			acknowledge(surface, menu)
			check(
				held_tap(menu, surface, find_target(menu, "choose", "language", "ja")),
				"Press/release an option"
			)
			check(
				events == [["language", "ja"]] and menu.choices.opened.is_empty(),
				"Curved option commits once on release"
			)
		acknowledge(surface, menu)
		held_tap(menu, surface, find_target(menu, "open", "language"))
		if menu.choices.opened == "language":
			acknowledge(surface, menu)
			var ray := ray_for(menu, surface, find_target(menu, "choose", "language", "en"))
			menu.press_pointer("left_hand", ray[0], ray[1], true)
			menu.update_pointer("left_hand", ray[0] + menu.global_basis.y * 0.09, ray[1], true)
			check(
				menu.choices.capture.get("moved", false),
				"Real curved pointer movement is still a drag"
			)
			menu.release_pointer("left_hand", ray[0], ray[1], true)
			check(events.size() == 1, "Dragging cannot choose an option")
		menu.choices.reset()
		menu.tab = menu.DISPLAY_TAB
		menu.refresh()
		acknowledge(surface, menu)
		var slider_target := -1
		for target in menu.choices.sliders:
			if menu.choices.targets[target].key == "controls_opacity":
				slider_target = target
		var slider_ray := ray_for(menu, surface, slider_target)
		menu.press_pointer("left_hand", slider_ray[0], slider_ray[1], true)
		var pressed_value: float = menu.choices.capture.value
		for frame in 3:
			menu.update_pointer("left_hand", slider_ray[0], slider_ray[1], true)
		check(
			is_equal_approx(menu.choices.capture.value, pressed_value),
			"Stationary curved slider does not jump between press and update"
		)
		menu.release_pointer("left_hand", slider_ray[0], slider_ray[1], true)
		menu.xr_surface = null
		menu.free()
		surface.free()
	for failure in failures:
		push_error(failure)
	print("XR choice checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
