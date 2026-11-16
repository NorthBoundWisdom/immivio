extends RefCounted
## Pure geometry/eligibility; no frame or decoder ownership lives here.
const STRIDE := 28


static func surface_flip(runtime: String, pico: bool, system: String = "") -> bool:
	var name := runtime.to_lower()
	if name.begins_with("oculus") or name.begins_with("meta"):
		return true
	if (
		pico
		or name.contains("pico")
		or name.begins_with("pxr")
		or system.to_lower().contains("pico")
	):
		return false
	return true


static func compatible(video: Object) -> String:
	if video.packed_file or video.packed_alpha:
		return "packed alpha needs shader"
	if video.color_grade.preset != "Original" or video.sharpness > 0:
		return "picture settings need shader"
	if video.stereo_focus_mode != 0:
		return "stereo focus needs shader"
	if not is_zero_approx(video.stereo_horizontal) or not is_zero_approx(video.stereo_vertical):
		return "stereo alignment needs shader"
	if (
		int(video.media.last_pair.get("rotation_degrees", 0)) != 0
		or int(video.media.format.get("unapplied_rotation_degrees", 0)) != 0
		or int(video.media.format.get("source_rotation_degrees", 0)) != 0
	):
		return "source rotation needs shader"
	return ""


static func fisheye_span(degrees: float) -> Vector2:
	var horizontal := deg_to_rad(clampf(degrees, 90, 360))
	return Vector2(TAU if degrees > 180.0 else horizontal, minf(horizontal, PI))


static func picture_size(
	source: Vector2i, geometry: int, fov: float, stereo: bool, stacked: bool, limit: Vector2i
) -> Vector2i:
	if source.x <= 0 or source.y <= 0 or limit.x <= 0 or limit.y <= 0:
		return Vector2i.ZERO
	var result := Vector2(source)
	if geometry == 2:
		var eye := (
			Vector2(source)
			/ (Vector2(1, 2) if stereo and stacked else Vector2(2, 1) if stereo else Vector2.ONE)
		)
		var density := minf(24.0, minf(eye.x, eye.y) / fov)
		var span := fisheye_span(fov)
		result = Vector2(rad_to_deg(span.x), rad_to_deg(span.y)) * density
		result *= Vector2(1, 2) if stereo and stacked else Vector2(2, 1) if stereo else Vector2.ONE
	var ratio := minf(
		1.0, minf(float(mini(limit.x, 8192)) / result.x, float(mini(limit.y, 8192)) / result.y)
	)
	ratio = minf(ratio, sqrt(35389440.0 / (result.x * result.y)))
	return Vector2i(maxi(2, floori(result.x * ratio) & ~1), maxi(2, floori(result.y * ratio) & ~1))


static func layers(
	geometry: Dictionary,
	origin: Transform3D,
	projection: int,
	fov: float,
	stereo: bool,
	stacked: bool,
	swap: bool,
	viewing: int,
	image: Vector2i,
	source: int,
	flip: int
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if image.x <= 0 or image.y <= 0 or not geometry.get("pose") is Transform3D:
		return result
	var pose: Transform3D = origin.affine_inverse() * geometry.pose
	var scale := pose.basis.get_scale()
	if (
		pose.basis.determinant() <= 0
		or not is_equal_approx(scale.x, scale.y)
		or not is_equal_approx(scale.x, scale.z)
	):
		return result
	pose.basis = pose.basis.orthonormalized()
	var shape := PackedFloat32Array()
	var kind := 0
	if projection == 0:
		var size: Vector2 = geometry.size * Vector2(scale.x, scale.y)
		var radius: float = float(geometry.radius) * scale.x
		if radius > 0:
			kind = 1
			pose.origin += pose.basis.z * radius
			shape = PackedFloat32Array([radius, size.x / radius, size.x / size.y, 0])
		else:
			shape = PackedFloat32Array([size.x, size.y, 0, 0])
	else:
		kind = 2
		var span := (
			fisheye_span(fov) if projection == 2 else Vector2(TAU if projection == 3 else PI, PI)
		)
		shape = PackedFloat32Array(
			[geometry.sphere_radius * scale.x, span.x, span.y * 0.5, -span.y * 0.5]
		)
	var q := pose.basis.get_rotation_quaternion()
	for physical in [0] if not stereo or viewing != 0 else [1, 2]:
		var rect := Rect2i(Vector2i.ZERO, image)
		if stereo:
			var eye: int = physical - 1 if viewing == 0 else viewing - 1
			if swap:
				eye = 1 - eye
			rect = (
				Rect2i(0, eye * image.y / 2, image.x, image.y / 2)
				if stacked
				else Rect2i(eye * image.x / 2, 0, image.x / 2, image.y)
			)
		var values := PackedFloat32Array(
			[
				kind,
				physical,
				pose.origin.x,
				pose.origin.y,
				pose.origin.z,
				q.x,
				q.y,
				q.z,
				q.w,
				rect.position.x,
				rect.position.y,
				rect.size.x,
				rect.size.y
			]
		)
		values.append_array(shape)
		values.resize(STRIDE)
		values[17] = flip
		values[19] = source
		values[20] = 1
		values[21] = 1
		values[22] = 1
		result.append_array(values)
	return result
