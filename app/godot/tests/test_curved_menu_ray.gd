extends SceneTree
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Menu := preload("res://scripts/ray_menu.gd")
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rect := Rect2(-1.2, -.8, 2.4, 1.6)
	var radius := 1.6
	for pose in [
		Transform3D.IDENTITY,
		Transform3D(Basis(Vector3.UP, .7) * Basis(Vector3.RIGHT, .3), Vector3(1, 1.6, -2))
	]:
		for x in [-1.1, -.6, 0.0, .5, 1.1]:
			for y in [-.7, 0.0, .7]:
				var point: Vector3 = (
					pose * Vector3(sin(x / radius) * radius, y, (1 - cos(x / radius)) * radius)
				)
				var origin: Vector3 = pose * Vector3(.1, .05, 1.0)
				var hit := Surface.project_curved_ray(pose, rect, radius, origin, point - origin)
				check(not hit.is_empty(), "Curved ray hits translated/rotated edges and centre")
				if hit.is_empty():
					continue
				check(
					(
						hit.point.distance_to(point) < .0001
						and hit.canvas_point.distance_to(pose * Vector3(x, y, 0)) < .0001
					),
					"Arc UV and physical pointer agree"
				)
	for sample in [
		[Vector3.ZERO, Vector3.ZERO],
		[Vector3(0, 0, -1), Vector3.BACK],
		[Vector3(0, 2, 1), Vector3.FORWARD],
		[Vector3(0, 0, 1), Vector3.UP],
		[Vector3(NAN, 0, 1), Vector3.FORWARD]
	]:
		check(
			(
				Surface
				. project_curved_ray(Transform3D.IDENTITY, rect, radius, sample[0], sample[1])
				. is_empty()
			),
			"Invalid/outside/rear rays cannot hit cylinder"
		)
	var menu := Menu.new()
	root.add_child(menu)
	menu.visible = true
	menu.curve_radius = radius
	menu._button(42, "Edge", Vector2(.8, .2), Vector2(.12, .12))
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = menu
	compositor.scene_curved = true
	compositor.surface_rect = rect
	menu.xr_surface = compositor
	var origin := menu.to_global(Vector3(0, 0, 1))
	var point := menu.to_global(
		Vector3(sin(.8 / radius) * radius, .2, (1 - cos(.8 / radius)) * radius)
	)
	var hit: Dictionary = menu.ray_hit(origin, point - origin)
	check(hit.get("target") == 42, "Bent edge targets select their original controls")
	if not hit.is_empty():
		check(
			(
				hit.point.distance_to(Vector3(.8, .2, 0)) < .0001
				and hit.world_point.distance_to(point) < .0001
			),
			"Input keeps canvas coordinates and curved laser endpoint separately"
		)
	menu.update_pointer("right_hand", origin, point - origin, true)
	check(
		menu._pointers.right_hand.dot.position.distance_to(Vector3(.8, .2, .008)) < .0001,
		"Reticle is captured at the correct texture coordinate"
	)
	menu.xr_surface = null
	compositor.free()
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Curved menu rays: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
