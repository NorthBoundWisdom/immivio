extends SceneTree
## GPU parity with generated colour patterns only. No video file or saved images.

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func shader(path: String) -> Shader:
	var code := FileAccess.get_file_as_string(path).replace(
		'#include "res://shaders/video_coordinates.gdshaderinc"',
		FileAccess.get_file_as_string("res://shaders/video_coordinates.gdshaderinc")
	)
	code = code.replace(
		"varying flat int eye_index;", "uniform int test_eye = 0;\nvarying flat int eye_index;"
	)
	code = code.replace("eye_index = int(VIEW_INDEX);", "eye_index = test_eye;")
	var value := Shader.new()
	value.code = code
	return value


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	camera.position.z = 2
	viewport.add_child(camera)
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2, 2)
	viewport.add_child(quad)
	var pattern := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			pattern.set_pixel(
				x, y, Color(float(x) / 63, float(y) / 63, .2 if (x / 4 + y / 4) % 2 == 0 else .8, 1)
			)
	var texture := ImageTexture.create_from_image(pattern)
	var caption := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	caption.fill(Color(.2, .1, .05, .4))  # Premultiplied caption samples.
	var caption_texture := ImageTexture.create_from_image(caption)
	var old := ShaderMaterial.new()
	old.shader = shader("res://shaders/video_pair.gdshader")
	var fast := ShaderMaterial.new()
	fast.shader = shader("res://shaders/video_opaque_pair.gdshader")
	for material in [old, fast]:
		material.set_shader_parameter("color_texture", texture)
		material.set_shader_parameter("source_size", Vector2(64, 64))
		material.set_shader_parameter("subtitle_texture", caption_texture)
		material.set_shader_parameter("bitmap_subtitle_texture", caption_texture)
		material.set_shader_parameter("bitmap_subtitle_rect", Vector4(.2, .2, .6, .6))
	old.set_shader_parameter("alpha_enabled", false)
	for rotation in [0, 90, 180, 270]:
		for stereo in [false, true]:
			for eye in [0, 1]:
				for clarity in [0.0, 0.2, 0.6]:
					for captions in [false, true]:
						for material in [old, fast]:
							material.set_shader_parameter("rotation_degrees", rotation)
							material.set_shader_parameter("stereo_sbs", stereo)
							material.set_shader_parameter("test_eye", eye)
							material.set_shader_parameter("sharpness", clarity)
							material.set_shader_parameter("bitmap_subtitle_enabled", captions)
							material.set_shader_parameter("grade_enabled", captions)
							material.set_shader_parameter("grade_gain", Vector3(1.1, .9, 1.0))
						quad.material_override = old
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						var reference := viewport.get_texture().get_image()
						quad.material_override = fast
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						var actual := viewport.get_texture().get_image()
						for xy in [
							Vector2i(1, 1),
							Vector2i(17, 29),
							Vector2i(32, 32),
							Vector2i(51, 43),
							Vector2i(62, 62)
						]:
							checks += 1
							var a := actual.get_pixelv(xy)
							var b := reference.get_pixelv(xy)
							if (
								(
									maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
									> 1.0 / 255.0
								)
								or a.a < .99
							):
								(
									failures
									. append(
										(
											"Opaque parity: rotation=%d stereo=%s eye=%d sharpness=%s captions=%s"
											% [rotation, stereo, eye, clarity, captions]
										)
									)
								)
	# Upstream stereo viewing/alignment must work on the opaque fast path too.
	for selected in [0, 1, 2]:
		for swap in [false, true]:
			for vertical in [false, true]:
				for eye in [0, 1]:
					for material in [old, fast]:
						material.set_shader_parameter("rotation_degrees", 0)
						material.set_shader_parameter("stereo_sbs", true)
						material.set_shader_parameter("test_eye", eye)
						material.set_shader_parameter("viewing_eye", selected)
						material.set_shader_parameter("swap_eyes", swap)
						material.set_shader_parameter("top_bottom", vertical)
						material.set_shader_parameter("stereo_offset", Vector2(.08, .06))
						material.set_shader_parameter("bitmap_subtitle_enabled", false)
					quad.material_override = old
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var expected := viewport.get_texture().get_image()
					quad.material_override = fast
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var observed := viewport.get_texture().get_image()
					for point in [
						Vector2i(0, 0), Vector2i(17, 29), Vector2i(32, 32), Vector2i(63, 63)
					]:
						checks += 1
						var a := expected.get_pixelv(point)
						var b := observed.get_pixelv(point)
						if (
							maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
							> 1.0 / 255.0
						):
							failures.append(
								"Opaque stereo viewing/alignment differs from reference"
							)
	for material in [old, fast]:
		material.set_shader_parameter("viewing_eye", 0)
		material.set_shader_parameter("swap_eyes", false)
		material.set_shader_parameter("top_bottom", false)
		material.set_shader_parameter("stereo_offset", Vector2.ZERO)
	# Exercise the real native-handle binding too, without any video decoder.
	await process_frame
	var binding := preload("res://scripts/pair_texture_binding.gd").new()
	binding.opaque = true
	var alpha := Image.create(32, 16, false, Image.FORMAT_R8)
	alpha.fill(Color.WHITE)
	var alpha_texture := ImageTexture.create_from_image(alpha)
	for material in [old, fast]:
		for key in ["stereo_sbs", "bitmap_subtitle_enabled", "grade_enabled"]:
			material.set_shader_parameter(key, false)
		material.set_shader_parameter("rotation_degrees", 0)
		material.set_shader_parameter("sharpness", .2)
	old.set_shader_parameter("test_eye", 0)
	var pair := {
		"contract_version": 2,
		"source_epoch": 1,
		"consumer_copy_fence_ready": true,
		"color_target": "texture",
		"mask_kind": "opaque",
		"session_id": 1,
		"logical_session_id": 1,
		"generation": 1,
		"frame_id": 1,
		"pts_us": 0,
		"format_revision": 1,
		"presentation_revision": 1,
		"slot_token": 1,
		"color_texture_id": RenderingServer.texture_get_native_handle(texture.get_rid()),
		"alpha_texture_id": RenderingServer.texture_get_native_handle(alpha_texture.get_rid()),
		"width": 64,
		"height": 64,
		"alpha_width": 32,
		"alpha_height": 16,
		"rotation_degrees": 0,
		"mask_content_rect": [0, 0, 1, 1],
		"stereo_sbs": false,
		"alpha_slot_token": 1,
		"alpha_frame_id": 1,
		"alpha_pts_us": 0,
		"source_pts_verified": false,
		"source_ticket_origin": "standard_libmpv_render",
		"source_ticket_valid": true,
		"immutable_color_frame": true,
		"pair_identity_verified": true,
		"alpha_fence_ready": true,
		"alpha_gpu_uploaded": true,
		"alpha_texture_format": "GL_R8_numeric"
	}
	if not binding.bind(fast, pair):
		failures.append("Native opaque binding failed")
	quad.material_override = old
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var reference := viewport.get_texture().get_image().get_pixel(32, 32)
	quad.material_override = fast
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image().get_pixel(32, 32)
	checks += 1
	if (
		actual.r < .1
		or actual.g < .1
		or absf(actual.r - reference.r) > 1.0 / 255.0
		or absf(actual.g - reference.g) > 1.0 / 255.0
	):
		failures.append("Native opaque colour was not preserved")
	binding.unbind()
	await process_frame
	# An opaque opt-in must never override a numeric source mask.
	alpha.fill(Color(.25, 0, 0))
	alpha_texture.update(alpha)
	pair.source_pts_verified = true
	pair.mask_kind = "numeric"
	if not binding.bind(fast, pair):
		failures.append("Numeric source-mask binding failed")
	fast.set_shader_parameter("alpha_enabled", true)
	quad.material_override = fast
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var masked := viewport.get_texture().get_image().get_pixel(32, 32)
	checks += 1
	if fast.shader != binding.PAIR_SHADER or masked.a < .1 or masked.a > .9:
		failures.append("Opaque opt-in bypassed inferred transparency")
	binding.unbind()
	viewport.queue_free()
	var report := {
		"state": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"source": "generated colour pattern",
		"images_saved": false
	}
	var output := OS.get_environment("THRU3D_OPAQUE_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report))
	for failure in failures.slice(0, 5):
		push_error(failure)
	print("Opaque material parity: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
