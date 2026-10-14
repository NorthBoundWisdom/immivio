extends RefCounted
## Borrowed native GL names. Caller must claim a complete pair before bind(),
## and keep the native display lease until unbind() plus the post-draw fence.
## This helper neither claims nor retires native slots.

const PAIR_SHADER := preload("res://shaders/video_pair.gdshader")
const Contract := preload("res://scripts/playback_frame_contract.gd")
const OPAQUE_SHADER := preload("res://shaders/video_opaque_pair.gdshader")
var opaque := false  # Display opts in only for ordinary, non-packed, non-inferred RGBA.

var material: ShaderMaterial
var color_rid := RID()
var alpha_rid := RID()
var ticket: Dictionary = {}


func bind(target: ShaderMaterial, pair: Dictionary) -> bool:
	if material or not target or not _valid(pair):
		return false
	color_rid = RenderingServer.texture_create_from_native_handle(
		RenderingServer.TEXTURE_TYPE_2D,
		Image.FORMAT_RGBA8,
		int(pair.color_texture_id),
		int(pair.width),
		int(pair.height),
		1
	)
	alpha_rid = RenderingServer.texture_create_from_native_handle(
		RenderingServer.TEXTURE_TYPE_2D,
		Image.FORMAT_R8,
		int(pair.alpha_texture_id),
		int(pair.alpha_width),
		int(pair.alpha_height),
		1
	)
	if not color_rid.is_valid() or not alpha_rid.is_valid():
		_free_wrappers()
		return false
	var ordinary: bool = opaque and pair.mask_kind == "opaque"
	_use_shader(target, OPAQUE_SHADER if ordinary else PAIR_SHADER)
	var rect: Array = pair.mask_content_rect
	material = target
	ticket = pair.duplicate(true)
	material.set_shader_parameter("source_size", Vector2(pair.width, pair.height))
	material.set_shader_parameter(
		"model_size", Vector2(float(pair.alpha_width) * 0.5, pair.alpha_height)
	)
	material.set_shader_parameter("model_content_rect", Vector4(rect[0], rect[1], rect[2], rect[3]))
	material.set_shader_parameter("stereo_sbs", bool(pair.stereo_sbs))
	material.set_shader_parameter("rotation_degrees", int(pair.rotation_degrees))
	RenderingServer.material_set_param(material.get_rid(), "color_texture", color_rid)
	RenderingServer.material_set_param(material.get_rid(), "alpha_texture", alpha_rid)
	return true


## The borrowed source color wrapper. Its native lease is owned by the caller.
func color_texture() -> RID:
	return color_rid


func unbind() -> Dictionary:
	if material:
		RenderingServer.material_set_param(material.get_rid(), "color_texture", null)
		RenderingServer.material_set_param(material.get_rid(), "alpha_texture", null)
	material = null
	_free_wrappers()
	var previous := ticket
	ticket = {}
	return previous


## Switch between the RGBA and decoder-image shader, keeping every uniform the display set.
static func _use_shader(target: ShaderMaterial, shader: Shader) -> void:
	if target.shader == shader:
		return
	var values := {}
	if target.shader:
		for uniform in target.shader.get_shader_uniform_list():
			var name := str(uniform.name)
			if not name in ["color_texture", "alpha_texture"]:
				values[name] = target.get_shader_parameter(name)
	target.shader = shader
	for name in values:
		if values[name] != null:
			target.set_shader_parameter(name, values[name])


func _free_wrappers() -> void:
	for rid in [color_rid, alpha_rid]:
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	color_rid = RID()
	alpha_rid = RID()


## Timing and descriptor checks live in the shared playback contract.
static func timing_valid(pair: Dictionary) -> bool:
	return Contract.timing_valid(pair)


static func _valid(pair: Dictionary) -> bool:
	return Contract.valid(pair)
