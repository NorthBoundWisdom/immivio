extends SceneTree
## The panel texture owns only a reticle. The beam keeps the controller-to-hit segment in 3D.
const Menu := preload("res://scripts/ray_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Stereo := preload("res://scripts/xr_pointer_compositor.gd")
var checks := 0
var failures: Array[String] = []


class Mapping:
	extends Node
	var native_supported := true
	var scene_curved := false
	var active_menu: Node3D

	func captures_menu(menu: Node3D) -> bool:
		return menu == active_menu

	func map_ray(menu: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
		return Surface.project_ray(menu.global_transform, Vector2(2, 2), origin, direction)

	func invalidate() -> void:
		pass


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var menu := Menu.new()
	root.add_child(menu)
	menu.position = Vector3.ZERO
	menu.visible = true
	var mapping := Mapping.new()
	mapping.active_menu = menu
	menu.xr_surface = mapping
	var origin := Vector3(.1, -.15, 1.1)
	var target := Vector3(-.1, .1, 0)
	menu.update_pointer("right_hand", origin, target - origin, true)
	var pointer: Dictionary = menu._pointers.right_hand
	check(not pointer.has("panel_line"), "There is no flattened copy of the beam")
	check(pointer.dot.visible, "The panel still shows its hit reticle")
	var start: Vector3 = pointer.line.material_override.get_shader_parameter("ray_start")
	var end: Vector3 = pointer.line.material_override.get_shader_parameter("ray_end")
	check(
		pointer.line.to_global(start).distance_to(origin) < .0001, "The 3D beam starts at the hand"
	)
	check(
		pointer.line.to_global(end).distance_to(target + Vector3(0, 0, .006)) < .0001,
		"The 3D beam ends just in front of the hit"
	)
	check(start.z - end.z > 1.0, "The beam retains depth instead of lying on the panel")
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = menu
	compositor.menus = [menu]
	compositor.native_supported = true
	compositor._tag_tree(menu)
	check(
		pointer.line.layers == Stereo.RAY_LAYER, "The native beam has its own stereo render channel"
	)
	check(pointer.dot.layers == Surface.UI_LAYER, "Only the reticle enters the UI capture")
	compositor._set_native_ready(false)
	check(pointer.line.layers == 1, "Scene fallback restores the original 3D beam layer")
	menu.cancel_pointer("right_hand")
	check(
		not pointer.line.visible and not pointer.dot.visible,
		"Tracking loss clears beam and reticle"
	)
	var camera := Camera3D.new()
	root.add_child(camera)
	var stereo := Stereo.new()
	root.add_child(stereo)
	stereo.configure(camera)
	var projection := Projection.create_frustum(-.018, .022, -.02, .02, Stereo.NEAR, Stereo.FAR)
	for eye in 2:
		var pose := Transform3D(Basis.IDENTITY, Vector3(-.032 if eye == 0 else .032, 0, 1.5))
		stereo.update_eye(eye, pose, projection)
		var actual := stereo.cameras[eye].get_camera_projection()
		check(
			(
				absf(actual.x.x - projection.x.x) < .002
				and absf(actual.y.y - projection.y.y) < .002
				and absf(actual.z.x - projection.z.x) < .002
			),
			"The perspective camera preserves the asymmetric eye frustum"
		)
		check(stereo.cameras[eye].global_transform == pose, "Each camera retains its own eye pose")
		check(
			stereo.layers[eye].sort_order > 5, "Stereo beams composite in front of the native menu"
		)
		check(
			stereo.cameras[eye].cull_mask == Stereo.RAY_LAYER,
			"Eye images contain only world-space beams"
		)
	check(
		stereo.layers[0].eye_visibility != stereo.layers[1].eye_visibility,
		"The two eye images cannot become one monocular panel image"
	)
	stereo.hide_beams()
	check(
		(
			not stereo.active
			and stereo.layers.all(func(layer): return is_equal_approx(layer.quad_size.x, .001))
		),
		"Inactive beams hide both eye layers"
	)
	stereo.free()
	camera.free()
	compositor.free()
	menu.xr_surface = null
	mapping.free()
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Stereo pointer: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
