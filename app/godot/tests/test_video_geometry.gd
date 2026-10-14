extends SceneTree
const Geometry := preload("res://scripts/video_geometry.gd")
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var valid := {
		"width": 1280, "height": 640, "pixel_aspect": 1.0, "unapplied_rotation_degrees": 0
	}
	check(
		Geometry.legacy_compatible(valid, true, Geometry.Geometry.FISHEYE),
		"Explicit packed fisheye format is accepted"
	)
	for changed in [
		{"width": 1279},
		{"height": 639},
		{"width": 100},
		{"height": 0},
		{"pixel_aspect": 1.2},
		{"unapplied_rotation_degrees": 90}
	]:
		var format := valid.duplicate()
		format.merge(changed, true)
		check(
			not Geometry.legacy_compatible(format, true, Geometry.Geometry.FISHEYE),
			"Incompatible packing is rejected: " + str(changed)
		)
	check(
		not Geometry.legacy_compatible(valid, false, Geometry.Geometry.FISHEYE),
		"Mono content cannot be interpreted as packed SBS"
	)
	check(
		not Geometry.legacy_compatible(valid, true, Geometry.Geometry.HALF_EQUIRECT),
		"Equirectangular content cannot use fisheye tile addressing"
	)
	check(
		Geometry.packed_dimensions(1280, 640) == Vector2i(512, 256),
		"Known producer fixture retains its packed dimensions"
	)
	for size in [Vector2i(1, 1), Vector2i(1919, 1079), Vector2i(8192, 4096)]:
		var packed := Geometry.packed_dimensions(size.x, size.y)
		check(
			packed.x >= 4 and packed.y >= 2 and packed.x % 4 == 0 and packed.y % 2 == 0,
			"Packing preserves eye/tile alignment"
		)
	for span in [PI, TAU]:
		var mesh := Geometry.hemisphere(3.0, 12, 6, span)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(
			vertices.size() == uv.size() and indices.size() % 3 == 0,
			"Every vertex has UVs and faces are triangles"
		)
		for index in indices:
			check(index >= 0 and index < vertices.size(), "Mesh indices remain in bounds")
		for i in vertices.size():
			check(
				absf(vertices[i].length() - 3.0) < .0001,
				"Projection vertices remain on the requested sphere"
			)
			check(
				uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1,
				"Projection UVs remain inside the source image"
			)
			if span == PI:
				check(vertices[i].z <= .0001, "VR180 never wraps behind the viewer")
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
