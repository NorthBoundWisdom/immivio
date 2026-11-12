extends RefCounted
## The pre-cache sky used a gamma-encoded 4K base without star detail. Keep this
## independent input for diagnostics comparing it with the linear HDR cache.


static func create(parent: Node) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(4096, 2048)
	view.disable_3d = true
	view.gui_disable_input = true
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/procedural_bake.gdshader")
	material.set_shader_parameter("scene", 0)
	material.set_shader_parameter("cache_stars", false)
	var canvas := ColorRect.new()
	canvas.size = view.size
	canvas.material = material
	view.add_child(canvas)
	parent.add_child(view)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	return view
