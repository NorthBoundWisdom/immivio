extends Node3D
## Render the original world-space beams from each XR eye, above the native UI layer.
## The UI texture keeps only its reticle; these two images retain beam depth and parallax.
const RAY_LAYER := 1 << 18
const SORT_ORDER := 10
const VIEW_HEIGHT := 1536
const NEAR := 0.02
const FAR := 20.0
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var layers: Array[OpenXRCompositionLayerQuad] = []
var active := false
var _bridge: Object
var _surfaces: Array = [null, null]
var _textures := PackedInt64Array([0, 0])
var _frames := PackedInt32Array([0, 0])
var _generation := -1
var _pending: Array[Dictionary] = [{}, {}]
var _presented: Array[Dictionary] = [{}, {}]
var _status: Array = []


func configure(head: Camera3D) -> void:
	if OS.get_name() == "Android":
		_bridge = JavaClassWrapper.wrap("org.vrpassthroughplayer.plugin.XrPointerSurfaceBridge")
	for eye in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(VIEW_HEIGHT, VIEW_HEIGHT)
		viewport.transparent_bg = true
		viewport.world_3d = head.get_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		views.append(viewport)
		var camera := Camera3D.new()
		camera.cull_mask = RAY_LAYER
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.environment = Environment.new()
		camera.environment.background_mode = Environment.BG_COLOR
		camera.environment.background_color = Color.TRANSPARENT
		viewport.add_child(camera)
		camera.current = true
		cameras.append(camera)
		var layer := OpenXRCompositionLayerQuad.new()
		layer.alpha_blend = true
		layer.sort_order = SORT_ORDER
		layer.eye_visibility = (
			OpenXRCompositionLayer.EYE_VISIBILITY_LEFT
			if eye == 0
			else OpenXRCompositionLayer.EYE_VISIBILITY_RIGHT
		)
		layer.quad_size = Vector2.ONE * .001
		if _bridge:
			# Keep Godot's GLES targets ordinary textures, as in the existing UI presenter.
			layer.use_android_surface = true
			layer.android_surface_size = viewport.size
			var xr := XRServer.primary_interface
			if xr and str(xr.get_system_info().get("XRRuntimeName", "")).begins_with("Oculus"):
				layer.set("XR_FB_composition_layer_image_layout/vertical_flip", true)
		head.get_parent().add_child(layer)
		layers.append(layer)


## The asymmetry and pose come from XR, not from the menu's orthographic capture camera.
func update_eye(eye: int, pose: Transform3D, projection: Projection) -> void:
	var aspect := projection.y.y / projection.x.x
	var size := Vector2i(roundi(VIEW_HEIGHT * aspect), VIEW_HEIGHT)
	if size.x > 2048:
		size = Vector2i(2048, roundi(2048 / aspect))
	if views[eye].size != size:
		views[eye].size = size
	var offset := Vector2(projection.z.x / projection.x.x, projection.z.y / projection.y.y)
	cameras[eye].set_frustum(2.0 * NEAR / projection.y.y, offset * NEAR, NEAR, FAR)
	cameras[eye].global_transform = pose
	# At one metre this quad spans precisely the eye's frustum. The pixels on it are
	# already a perspective render of the 3D beam, with a different image for each eye.
	var image := {
		"pose": pose * Transform3D(Basis.IDENTITY, Vector3(offset.x, offset.y, -1)),
		"size": Vector2(2.0 / projection.x.x, 2.0 / projection.y.y)
	}
	if _bridge:
		_present_eye(eye, size, image)
	else:
		layers[eye].global_transform = image.pose
		layers[eye].quad_size = image.size
	views[eye].render_target_update_mode = SubViewport.UPDATE_ONCE
	active = true


func _present_eye(eye: int, size: Vector2i, image: Dictionary) -> void:
	var generation: int = _bridge.contextGeneration()
	if generation != _generation:
		_generation = generation
		_textures.fill(0)
		_frames.fill(0)
		for index in 2:
			_pending[index].clear()
			_presented[index].clear()
	if layers[eye].android_surface_size != size:
		layers[eye].android_surface_size = size
	var surface: Object = layers[eye].get_android_surface()
	if surface != _surfaces[eye]:
		_surfaces[eye] = surface
		_frames[eye] = 0
		_textures[eye] = 0
		_pending[eye].clear()
		_presented[eye].clear()
		_bridge.attachSurface(eye, surface)
	_frames[eye] += 1
	_status = JSON.parse_string(_bridge.status())
	var state: Dictionary = _status[eye] if _status.size() > eye else {}
	var acknowledged := int(state.get("presented_serial", -1))
	if not bool(state.get("ready", false)):
		_presented[eye].clear()
	if bool(state.get("ready", false)) and _pending[eye].has(acknowledged):
		_presented[eye] = _pending[eye][acknowledged]
		for key in _pending[eye].keys():
			if int(key) <= acknowledged:
				_pending[eye].erase(key)
	if _presented[eye].is_empty():
		layers[eye].quad_size = Vector2.ONE * .001
	else:
		layers[eye].global_transform = _presented[eye].pose
		layers[eye].quad_size = _presented[eye].size
	if surface == null or _frames[eye] < 2:
		return
	if _textures[eye] == 0:
		_textures[eye] = RenderingServer.texture_get_native_handle(
			RenderingServer.viewport_get_texture(views[eye].get_viewport_rid())
		)
	if _textures[eye] <= 0:
		return
	var serial := Engine.get_process_frames()
	_pending[eye][serial] = image
	while _pending[eye].size() > 4:
		_pending[eye].erase(_pending[eye].keys()[0])
	_bridge.submitTexture(eye, _textures[eye], size.x, size.y, _generation, serial)
	_bridge.setEnabled(true)


func hide_beams() -> void:
	active = false
	if _bridge:
		_bridge.setEnabled(false)
	for eye in layers.size():
		layers[eye].quad_size = Vector2.ONE * .001
		views[eye].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_pending[eye].clear()
		_presented[eye].clear()
		_frames[eye] = 0


func snapshot() -> Dictionary:
	if _bridge:
		_status = JSON.parse_string(_bridge.status())
	return {
		"active": active,
		"views": views.size(),
		"sort_order": SORT_ORDER,
		"cull_mask": RAY_LAYER,
		"view_sizes": views.map(func(viewport): return [viewport.size.x, viewport.size.y]),
		"presentation": _status
	}


func _exit_tree() -> void:
	if _bridge:
		_bridge.setEnabled(false)
		for eye in 2:
			_bridge.attachSurface(eye, null)
	for layer in layers:
		if is_instance_valid(layer):
			layer.queue_free()
