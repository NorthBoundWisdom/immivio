extends SceneTree
## The panel texture owns only a reticle. The beam keeps the controller-to-hit segment in 3D.
const Menu := preload("res://scripts/ray_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
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
	var pointer: Dictionary = menu.pointer_snapshot().right_hand
	check(not pointer.has("panel_line"), "There is no flattened copy of the beam")
	check(pointer.dot.visible, "The panel still shows its hit reticle")
	var start: Vector3 = pointer.local_start
	var end: Vector3 = pointer.local_end
	check(pointer.world_start.distance_to(origin) < .0001, "The 3D beam starts at the hand")
	check(
		pointer.world_end.distance_to(target + Vector3(0, 0, .006)) < .0001,
		"The 3D beam ends just in front of the hit"
	)
	check(start.z - end.z > 1.0, "The beam retains depth instead of lying on the panel")
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = menu
	compositor.menus = [menu]
	compositor.native_supported = true
	compositor._tag_tree(menu)
	pointer = menu.pointer_snapshot().right_hand
	check(pointer.line.layers == 1, "The native menu's beam remains in the main stereo projection")
	check(pointer.dot.layers == Surface.UI_LAYER, "Only the reticle enters the UI capture")
	compositor._set_native_ready(false)
	pointer = menu.pointer_snapshot().right_hand
	check(pointer.line.layers == 1, "Scene fallback restores the original 3D beam layer")
	menu.cancel_pointer("right_hand")
	pointer = menu.pointer_snapshot().right_hand
	check(
		not pointer.line.visible and not pointer.dot.visible,
		"Tracking loss clears beam and reticle"
	)
	compositor.free()
	menu.xr_surface = null
	mapping.free()
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Stereo pointer: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
