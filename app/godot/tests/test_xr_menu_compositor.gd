extends SceneTree
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Menu := preload("res://scripts/ray_menu.gd")
var failures: Array[String] = []

class Mapping extends Node:
	var native_supported := true
	var active_menu: Node3D
	var pose := Transform3D.IDENTITY
	func map_ray(_menu: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
		return Surface.project_ray(pose, Vector2(2, 2), origin, direction)
	func invalidate() -> void: pass

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var menu := Menu.new(); root.add_child(menu); menu.visible = true
	menu.global_transform = Transform3D(Basis(Vector3.UP, .2), Vector3(0, 1.6, -2))
	menu._button(42, "Synthetic", Vector2(.3, 0), Vector2(.06, .12))
	var button: MeshInstance3D = menu._buttons.back().node
	button.position.z = .25; button.rotation.y = .4
	var mapping := Mapping.new(); mapping.active_menu = menu; mapping.pose = menu.global_transform
	menu.xr_surface = mapping
	var point := menu.to_global(Vector3(.3, 0, 0))
	var origin := Vector3(-.7, 1.6, 0)
	var hit: Dictionary = menu.ray_hit(origin, point - origin)
	check(hit.get("target") == 42, "Flat compositor pixels map onto the original angled 3D control")
	check(menu.to_global(hit.get("point", Vector3.ZERO)).distance_to(point) < .0001, "Pointer feedback stays on the visible compositor surface")
	var blank := menu.to_global(Vector3(-.3, .2, 0))
	menu.update_pointer("right_hand", origin, blank-origin, true)
	check(menu._pointers.right_hand.dot.visible and menu._pointers.right_hand.dot.position.distance_to(Vector3(-.3,.2,.008)) < .0001 and menu._hover.right_hand == Menu.NONE, "Native compositor blank panel pixels stop the laser without selecting a button")
	check(Surface.project_ray(Transform3D.IDENTITY, Vector2(2, 2), Vector3(0, 0, -1), Vector3.BACK).is_empty(), "Back-face rays are rejected")
	check(Surface.project_ray(Transform3D.IDENTITY, Vector2(2, 2), Vector3(2, 0, 1), Vector3.FORWARD).is_empty(), "Rays outside the surface are rejected")
	check(Surface.project_ray(Transform3D.IDENTITY, Vector2(2, 2), Vector3(0, 0, 1), Vector3.RIGHT).is_empty(), "Parallel rays are rejected")
	var font: Font = menu.ui_font()
	check(font.multichannel_signed_distance_field and font.generate_mipmaps, "Menu fonts use scalable distance fields and mipmaps")
	check(font.has_char("播".unicode_at(0)) and font.has_char("A".unicode_at(0)), "CJK and Latin glyph coverage remains available")
	var fallback: Font = font.fallbacks[0]
	check(fallback.multichannel_signed_distance_field, "Fallback text uses the same distance-field rendering")
	menu.xr_surface = null
	menu.scale = Vector3(.75, 2.0/3.0, 1)
	mapping.pose = Surface.capture_pose(menu)
	menu.xr_surface = mapping
	point = menu.to_global(Vector3(.3, 0, 0))
	hit = menu.ray_hit(origin, point-origin)
	check(hit.get("target") == 42 and menu.to_global(hit.get("point", Vector3.ZERO)).distance_to(point) < .0001, "Nonuniform panel resizing keeps compositor ray targets aligned")
	check(mapping.pose.basis.get_scale().is_equal_approx(Vector3.ONE), "Native quad/camera stay unscaled while capturing resized UI")
	var compositor := Surface.new(); root.add_child(compositor)
	compositor.active_menu = menu; compositor._update_bounds()
	check(compositor.content_bounds.has_point(Vector2((point-mapping.pose.origin).dot(mapping.pose.basis.x), (point-mapping.pose.origin).dot(mapping.pose.basis.y))), "Capture bounds include physically scaled controls")
	var pointer := menu._pointer("right_hand")
	compositor.native_supported = true
	compositor._tag(pointer.line); compositor._tag(pointer.dot)
	check(pointer.line.layers & Surface.UI_LAYER == 0 and pointer.line.layers & 1 != 0, "Laser stays in the scene and cannot flatten into a panel projection stripe")
	check(pointer.dot.layers & Surface.UI_LAYER != 0, "Panel reticle remains visible in the native UI layer")
	compositor.free()
	menu.xr_surface = null; mapping.free(); menu.free()
	for failure in failures: push_error(failure)
	print("XR menu composition mapping/font checks: ", "passed" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
