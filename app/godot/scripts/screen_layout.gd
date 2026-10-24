extends RefCounted
## Flat-screen defaults are independent from per-file projection/stereo preferences.
const Presets := preload("res://scripts/screen_presets.gd")
var host_ref: WeakRef
var guide: MeshInstance3D
var guide_until := 0


func _init(host: Node3D) -> void:
	host_ref = weakref(host)


func fixed() -> bool:
	return bool(host_ref.get_ref().settings.get_value("screen", "fixed", false))


func restore() -> void:
	var host: Node3D = host_ref.get_ref()
	host.video.screen_preset = str(host.settings.get_value("screen", "preset", ""))
	host.video.screen_eye_level = clampf(
		float(host.settings.get_value("screen", "eye_level", 0.5)), 0, 1
	)
	if fixed():
		host.video.set_screen_distance(float(host.settings.get_value("screen", "distance", 2.0)))
		host.video.set_screen_scale(float(host.settings.get_value("screen", "scale", 1.0)))
		host.video.set_screen_curve(float(host.settings.get_value("screen", "curve", 0.0)))
		host.video.screen_preset = str(host.settings.get_value("screen", "preset", ""))


func save(force: bool = false) -> void:
	var host: Node3D = host_ref.get_ref()
	if host.photo_active or (fixed() and not force):
		return
	for pair in [
		["distance", host.video.screen_distance],
		["scale", host.video.screen_scale],
		["curve", host.video.screen_curve],
		["preset", host.video.screen_preset],
		["eye_level", host.video.screen_eye_level]
	]:
		host.settings.set_value("screen", pair[0], pair[1])
	host.settings.save(host.settings_path)


func adjust(key: String, value: Variant) -> bool:
	var host: Node3D = host_ref.get_ref()
	if key == "screen_fixed":
		if fixed() == bool(value): return true
		host.settings.set_value("screen", "fixed", bool(value))
		save(true)
		return true
	if key == "screen_save_default":
		save(true)
		return true
	if host.photo_active or host.video.geometry != 0:
		return false
	if key == "screen_preset":
		var preset := Presets.find(str(value))
		if preset.is_empty():
			return true
		host.video.screen_preset = preset.id
		host.video.screen_eye_level = preset.eye_level
		host.video.set_screen_distance(preset.distance)
		host.video._apply_geometry()
		host.view_follow._poses.erase(host._surface_key(host.video))
		host._place_screen()
	elif key == "screen_eye_level":
		host.video.screen_eye_level = clampf(float(value), 0, 1)
		host.view_follow._poses.erase(host._surface_key(host.video))
		host._place_screen()
	elif key == "screen_curve":
		host.video.set_screen_curve(float(value))
	elif key == "screen_grid":
		show_guide()
		return true
	else:
		return false
	save()
	show_guide()
	return true


func show_guide() -> void:
	var host: Node3D = host_ref.get_ref()
	var head: Variant = host._head_pose()
	if head == null or host.photo_active or host.video.geometry != 0:
		return
	if not is_instance_valid(guide):
		guide = MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for x in range(-20, 21, 2):
			mesh.surface_add_vertex(Vector3(x, 0, -1))
			mesh.surface_add_vertex(Vector3(x, 0, -55))
		for z in range(1, 56, 2):
			mesh.surface_add_vertex(Vector3(-20, 0, -z))
			mesh.surface_add_vertex(Vector3(20, 0, -z))
		mesh.surface_end()
		guide.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.15, 0.3, 0.32)
		guide.material_override = material
		host.add_child(guide)
	guide.global_transform = host._upright_pose(head)
	guide.global_position.y -= 1.25
	guide.visible = true
	guide_until = Time.get_ticks_msec() + 5000


func tick() -> void:
	if is_instance_valid(guide):
		var host: Node3D = host_ref.get_ref()
		guide.visible = (
			Time.get_ticks_msec() < guide_until
			and not host.photo_active
			and host.video.geometry == 0
			and host.video.panel.visible
		)
