extends SceneTree

const Menu := preload("res://scripts/ray_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var menu := Menu.new()
	root.add_child(menu)
	menu.visible = true
	menu.global_transform = Transform3D(
		Basis(Vector3.UP, .4) * Basis(Vector3.RIGHT, .2), Vector3(1, 1.6, -2)
	)
	menu.scale = Vector3(.75, 2.0 / 3.0, 1)
	menu._button(42, "Action", Vector2.ZERO, Vector2(.12, .12))
	menu._button(43, "Unavailable", Vector2(.3, 0), Vector2(.12, .12), false)
	var disabled: Dictionary = menu._buttons.back()
	var origin := menu.to_global(Vector3(0, 0, 1))
	var blank := menu.to_global(Vector3(.3, .2, 0))
	menu.update_pointer("right_hand", origin, blank - origin, true)
	var pointer: Dictionary = menu._pointers.right_hand
	check(
		pointer.dot.visible and pointer.dot.position.distance_to(Vector3(.3, .2, .008)) < .0001,
		"Transformed/scaled panel blank space shows a surface reticle"
	)
	check(
		(
			menu._hover.right_hand == Menu.NONE
			and not menu.press_pointer("right_hand", origin, blank - origin, true)
		),
		"Panel feedback cannot highlight or activate a button"
	)
	check(
		(
			pointer.line.mesh.get_aabb().end.z < 1.001
			and pointer.line.mesh.get_aabb().position.z >= .005
		),
		"Laser segment ends in front of the panel"
	)
	check(not disabled.node.visible, "Unavailable button is hidden on creation")
	menu.update_pointer("right_hand", origin, menu.to_global(Vector3(.3, 0, 0)) - origin, true)
	check(
		pointer.dot.visible and menu._hover.right_hand == Menu.NONE,
		"Hidden button leaves the panel blocking the ray"
	)
	disabled.enabled = true
	menu._update_highlights()
	check(disabled.node.visible, "Button reappears when it becomes available")
	menu.update_pointer("right_hand", origin, disabled.node.global_position - origin, true)
	check(
		(
			menu._hover.right_hand == 43
			and (
				disabled.node.material_override.get_shader_parameter("surface_color")
				!= disabled.base_color
			)
		),
		"Available button still highlights under the laser"
	)
	disabled.enabled = false
	menu._update_highlights()
	check(not disabled.node.visible, "Live availability change hides the button again")
	disabled["keep_visible"] = true
	menu._update_highlights()
	check(
		(
			disabled.node.visible
			and menu.ray_hit(origin, disabled.node.global_position - origin).is_empty()
		),
		"Informational rows remain visible without accepting input"
	)
	disabled.enabled = true
	disabled["layout_visible"] = false
	menu._update_highlights()
	check(
		not disabled.node.visible,
		"Availability does not unhide rows clipped by the scrolling layout"
	)
	for sample in [
		[Vector3(0, 0, 1), Vector3.UP],
		[Vector3(0, 0, -1), Vector3.BACK],
		[Vector3(2, 0, 1), Vector3.FORWARD],
		[Vector3(0, 0, 6), Vector3.FORWARD],
		[Vector3(NAN, 0, 1), Vector3.FORWARD]
	]:
		check(
			menu.ray_panel_hit(menu.to_global(sample[0]), menu.global_basis * sample[1]).is_empty(),
			"Panel rejects parallel, rear, outside, far and invalid rays"
		)
	menu.cancel_pointer("right_hand")
	check(
		not pointer.line.visible and not pointer.dot.visible, "Tracking loss clears panel feedback"
	)
	# Independent angled side panels and raised popups also block blank-space rays.
	var side := menu._quad(Vector2(.3, .3), Vector3(-1, 0, .1), Menu.PANEL, 10)
	menu.add_child(side)
	menu._decorations.append(side)
	side.rotation.y = .4
	var side_origin := side.to_global(Vector3(0, 0, 1))
	var side_hit: Dictionary = menu.ray_panel_hit(side_origin, -side.global_basis.z)
	check(
		(
			not side_hit.is_empty()
			and menu.to_global(side_hit.point).distance_to(side.global_position) < .0001
		),
		"Angled side panel blocks its blank space"
	)
	var popup := menu._quad(Vector2(.3, .3), Vector3(.4, .3, .028), Menu.PANEL, 30)
	menu.add_child(popup)
	menu._decorations.append(popup)
	var popup_hit: Dictionary = menu.ray_panel_hit(
		popup.to_global(Vector3(0, 0, 1)), -popup.global_basis.z
	)
	check(
		not popup_hit.is_empty() and is_equal_approx(popup_hit.point.z, .028),
		"Raised popup stops the laser before the main backdrop"
	)
	menu._button(44, "Behind popup", Vector2(.4, .3), Vector2(.12, .12))
	var popup_origin := popup.to_global(Vector3(0, 0, 1))
	menu.update_pointer("right_hand", popup_origin, -popup.global_basis.z, true)
	check(
		(
			menu._hover.right_hand == Menu.NONE
			and is_equal_approx(pointer.dot.position.z, .036)
			and not menu.press_pointer("right_hand", popup_origin, -popup.global_basis.z, true)
		),
		"Foreground panel blocks laser, highlight and clicks on buttons behind it"
	)
	# Curved capture keeps physical laser and flat texture coordinates separate.
	menu.global_transform = Transform3D.IDENTITY
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = menu
	compositor.scene_curved = true
	compositor.surface_rect = Rect2(-1.2, -.8, 2.4, 1.6)
	menu.xr_surface = compositor
	menu.curve_radius = 1.6
	origin = Vector3(0, 0, 1)
	var curved := Vector3(sin(.3 / 1.6) * 1.6, .2, (1 - cos(.3 / 1.6)) * 1.6)
	var hit: Dictionary = menu.ray_panel_hit(origin, curved - origin)
	check(
		(
			not hit.is_empty()
			and hit.world_point.distance_to(curved) < .0001
			and hit.point.distance_to(Vector3(.3, .2, 0)) < .0001
		),
		"Curved panel blank space maps physical and texture positions correctly"
	)
	menu.update_pointer("right_hand", origin, curved - origin, true)
	check(
		(
			pointer.dot.visible
			and pointer.dot.position.distance_to(Vector3(.3, .2, .008)) < .0001
			and menu._hover.right_hand == Menu.NONE
		),
		"Curved blank space shows a reticle without highlighting a control"
	)
	menu.xr_surface = null
	compositor.free()
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Panel pointer: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
