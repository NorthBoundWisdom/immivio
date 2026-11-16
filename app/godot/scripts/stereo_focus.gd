extends RefCounted
## Focus uses a tiny rectified, current-view stereo sample. Matching runs on a worker.
const LIMITS := Vector2(0.3, 50.0)
const SIZE := Vector2i(192, 40)
const INTERVAL_MS := 500
var distance := 0.0
var inverse := 0.0
var recent: Array[float] = []
var last_valid_ms := 0
var report := {}


func reset() -> void:
	distance = 0.0
	inverse = 0.0
	recent.clear()
	report.clear()
	last_valid_ms = 0


static func gaze(forward: Vector3) -> Vector2:
	var d := forward.normalized()
	return Vector2(atan2(d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


static func measurable(angles: Vector2, geometry: int, fov: float) -> bool:
	if absf(angles.y) > deg_to_rad(60.0):
		return false
	if geometry == 3:
		return true
	if absf(angles.x) > deg_to_rad(73.0):
		return false
	return (
		geometry != 2
		or (
			acos(clampf(cos(angles.x) * cos(angles.y), -1.0, 1.0)) + deg_to_rad(16.0)
			< deg_to_rad(fov * 0.5)
		)
	)


static func inverse_distance(
	disparity: float, ipd: float, angles: Vector2, full_sphere: bool
) -> float:
	var across := 1.0 if full_sphere else maxf(cos(angles.x), 0.05)
	return clampf(
		disparity * cos(angles.y) / (maxf(ipd, 0.001) * across), 1.0 / LIMITS.y, 1.0 / LIMITS.x
	)


func observe(
	value: Dictionary, ipd: float, angles: Vector2, full_sphere: bool, alignment: float, now_ms: int
) -> void:
	report = value.duplicate(true)
	if not value.get("valid", false):
		return
	var disparity := deg_to_rad(float(value.degrees)) - alignment * (TAU if full_sphere else PI)
	# Divergent/zero matches have no finite near depth; preserve a safe far limit.
	var measured := inverse_distance(disparity, ipd, angles, full_sphere)
	recent.append(measured)
	if recent.size() > 3:
		recent.pop_front()
	var ordered := recent.duplicate()
	ordered.sort()
	inverse = float(ordered[ordered.size() / 2])
	last_valid_ms = now_ms


func settle(delta: float, now_ms: int) -> void:
	if inverse <= 0:
		return
	if now_ms - last_valid_ms > 2500:
		reset()
		return
	var current := 1.0 / distance if distance > 0 else inverse
	current = lerpf(current, inverse, 1.0 - exp(-maxf(delta, 0.0) / 0.4))
	distance = clampf(1.0 / maxf(current, 0.0001), LIMITS.x, LIMITS.y)


static func measure(image: Image) -> Dictionary:
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return {"valid": false}
	var w := SIZE.x / 2
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(w * SIZE.y)
	right.resize(left.size())
	for y in SIZE.y:
		for x in w:
			left[y * w + x] = image.get_pixel(x, y).get_luminance()
			right[y * w + x] = image.get_pixel(x + w, y).get_luminance()
	var scores: Array[float] = []
	var best := -1.0
	var best_shift := 0
	# 29 degrees across 96 pixels, -4..13 degree disparities.
	for shift in range(-13, 44):
		var sa := 0.0
		var sb := 0.0
		var aa := 0.0
		var bb := 0.0
		var ab := 0.0
		var count := 0.0
		var a_offset := roundi(shift * 0.5)
		var b_offset := a_offset - shift
		for y in range(4, SIZE.y - 4, 2):
			for x in range(25, 71, 2):
				var a := left[y * w + x + a_offset]
				var b := right[y * w + x + b_offset]
				sa += a
				sb += b
				aa += a * a
				bb += b * b
				ab += a * b
				count += 1
		var va := aa - sa * sa / count
		var vb := bb - sb * sb / count
		var score := (
			(ab - sa * sb / count) / sqrt(va * vb) if minf(va, vb) / count > 0.00025 else -1.0
		)
		scores.append(score)
		if score > best:
			best = score
			best_shift = shift
	var second := -1.0
	for i in scores.size():
		if absi(i - 13 - best_shift) > 3:
			second = maxf(second, scores[i])
	return {
		"valid": best >= 0.65 and best - second > 0.05 and best_shift > -13 and best_shift < 43,
		"degrees": float(best_shift) * 29.0 / w,
		"peak": best,
		"runner_up": second
	}


class Probe:
	extends RefCounted
	var viewport: SubViewport
	var material: ShaderMaterial
	var token := 0
	var epoch := 0
	var platform: Object

	func cancel() -> void:
		epoch += 1
		if token > 0 and platform:
			platform.cancel_focus_readback(token)
		token = 0
		if is_instance_valid(viewport):
			viewport.queue_free()
		viewport = null
		material = null

	func capture(parent: Node, color: RID, values: Dictionary, native: Object = null) -> Image:
		var generation := epoch
		platform = native
		if not is_instance_valid(viewport):
			viewport = SubViewport.new()
			viewport.size = Vector2i(192, 40)
			viewport.own_world_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 1.0
			camera.position.z = 1.0
			viewport.add_child(camera)
			var quad := MeshInstance3D.new()
			quad.mesh = QuadMesh.new()
			quad.mesh.size = Vector2(192.0 / 40, 1.0)
			material = ShaderMaterial.new()
			material.shader = preload("res://shaders/stereo_focus_probe.gdshader")
			quad.material_override = material
			viewport.add_child(quad)
			parent.add_child(viewport)
		for key in values:
			material.set_shader_parameter(key, values[key])
		RenderingServer.material_set_param(material.get_rid(), "color_texture", color)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if generation != epoch or not is_instance_valid(viewport):
			return null
		var image: Image
		if native == null:
			# Desktop GPU fixtures only. Android playback never uses synchronous get_image.
			image = viewport.get_texture().get_image()
		elif preload("res://scripts/platform_methods.gd").supports(
			native, "request_focus_readback"
		):
			token = native.request_focus_readback(
				RenderingServer.texture_get_native_handle(viewport.get_texture().get_rid()), 192, 40
			)
			var started := Time.get_ticks_msec()
			while token > 0 and generation == epoch and Time.get_ticks_msec() - started <= 200:
				var bytes: PackedByteArray = native.poll_focus_readback(token)
				if bytes.size() == 192 * 40 * 4:
					image = Image.create_from_data(192, 40, false, Image.FORMAT_RGBA8, bytes)
					break
				if not is_instance_valid(parent) or not parent.is_inside_tree():
					break
				await parent.get_tree().process_frame
			if token > 0:
				native.cancel_focus_readback(token)
			token = 0
		if generation == epoch and material:
			RenderingServer.material_set_param(material.get_rid(), "color_texture", null)
		return image


static func capture(parent: Node, color: RID, values: Dictionary) -> Image:
	var probe := Probe.new()
	var image: Image = await probe.capture(parent, color, values)
	probe.cancel()
	return image
