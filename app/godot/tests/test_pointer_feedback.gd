extends SceneTree
const UiSurface := preload("res://scripts/xr_menu_compositor.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var menu := preload("res://scripts/ray_menu.gd").new()
	root.add_child(menu)
	menu.visible = true
	menu.position = Vector3(0, 0, -2)
	menu._button(42, "Action", Vector2.ZERO, Vector2(0.2, 0.2))
	menu.update_pointer("right_hand", Vector3.ZERO, Vector3.FORWARD, true)
	assert(menu._hover.right_hand == 42)
	var pointer: Dictionary = menu._pointers.right_hand
	assert(pointer.dot.scale.x > 1.0)
	assert(pointer.line.mesh.get_surface_count() == 1)
	assert(
		pointer.line.material_override.get_shader_parameter("ray_start").is_equal_approx(
			pointer.line.to_local(Vector3.ZERO)
		)
	)
	var blank := menu.to_global(Vector3(0.4, 0.2, 0))
	menu.update_pointer("right_hand", Vector3.ZERO, blank, true)
	assert(
		(
			menu._hover.right_hand == menu.NONE
			and pointer.dot.visible
			and pointer.dot.scale == Vector3.ONE
		)
	)
	menu.update_pointer("right_hand", Vector3.ZERO, Vector3.ZERO, false)
	assert(not pointer.line.visible and not pointer.dot.visible)
	var schedule := UiSurface.PaintSchedule.new()
	assert(schedule.poll(1, false, 0))
	assert(schedule.poll(1, false, 10))
	assert(schedule.poll(1, false, 20))
	assert(not schedule.poll(1, false, 30))
	assert(schedule.poll(1, false, 300))
	assert(schedule.poll(1, true, 301))
	assert(schedule.poll(2, false, 302))
	schedule.invalidate()
	assert(schedule.poll(2, false, 303))
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
