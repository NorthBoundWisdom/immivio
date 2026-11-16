extends MeshInstance3D


func _init() -> void:
	mesh = QuadMesh.new()
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	visible = false
	var appearance := ShaderMaterial.new()
	appearance.shader = preload("res://shaders/flat_caption.gdshader")
	appearance.render_priority = 1
	material_override = appearance


func show_caption(source: Label3D, canvas: Node) -> bool:
	visible = (
		source.visible
		and not source.text.is_empty()
		and source.modulate.a < 1.0
		and canvas.request(source)
	)
	if not visible:
		return false
	(mesh as QuadMesh).size = canvas.physical_size(source)
	global_transform = canvas.pose(source)
	global_basis = global_basis.orthonormalized()
	material_override.set_shader_parameter("caption_texture", canvas.viewport.get_texture())
	return true
