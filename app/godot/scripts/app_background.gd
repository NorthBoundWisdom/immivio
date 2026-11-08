extends Node
## Application scenery independent from video playback.
signal changed
## Bundled photographic panoramas (Poly Haven, CC0), loaded only when selected.
const PANORAMAS := {
	"belfast": "res://backgrounds/belfast_sunset_puresky.jpg",
	"beach": "res://backgrounds/blouberg_sunrise_2.jpg",
}
## Procedural scenes, no image assets: the smooth base is baked once on the GPU when a scene is
## chosen; stars, ridges and the sun stay per pixel, so they are sharp at any resolution.
const PROCEDURAL := {"starry_night": 0, "cloud_sea": 2}
const PROCEDURAL_SHADER := preload("res://shaders/procedural_sky.gdshader")
const BAKE_SHADER := preload("res://shaders/procedural_bake.gdshader")
const BAKE_SIZE := Vector2i(4096, 2048)
const DEFAULT_CHOICE := "starry_night"
const CHOICES := ["starry_night", "belfast", "beach", "cloud_sea", "dark", "passthrough"]
var choice := DEFAULT_CHOICE
var yaw := 0.0
var brightness := 1.0
var loading := false
var error := ""
var sky := Sky.new()
var _material := PanoramaSkyMaterial.new()
var _procedural := ShaderMaterial.new()
var _panorama: Texture2D
var _panorama_path := ""  # the path _panorama holds
var _requested: Array[String] = []  # threaded loads in flight; superseded ones are dropped
var _bake: SubViewport  # exists only while a procedural scene is chosen
var _bake_material := ShaderMaterial.new()
var _baked_scene := -1  # the scene the bake texture holds
var _baking_scene := -1  # the scene rendering into it
var _bake_frame := 0  # process frame of the request; the one-shot render follows that frame


func _ready() -> void:
	sky.sky_material = _material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_material.filter = true
	_procedural.shader = PROCEDURAL_SHADER
	_bake_material.shader = BAKE_SHADER
	if not select(choice):
		select(DEFAULT_CHOICE)


## Scenery the viewer can turn and dim: the panorama and every procedural scene.
static func is_scenery(value: String) -> bool:
	return PANORAMAS.has(value) or PROCEDURAL.has(value)


func select(value: String) -> bool:
	if value not in CHOICES:
		return false
	choice = value
	error = ""
	var path: String = PANORAMAS.get(choice, "")
	if not path.is_empty() and path != _panorama_path and path not in _requested:
		# Switching quickly never waits on an earlier load; it finishes and is dropped.
		if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
			_requested.append(path)
		else:
			error = "Background unavailable"
	_apply()
	return true


func _process(_delta: float) -> void:
	if _bake and _baking_scene >= 0 and Engine.get_process_frames() >= _bake_frame + 2:
		_baked_scene = _baking_scene
		_baking_scene = -1
		_apply()
	for path in _requested.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_requested.erase(path)
		var texture := (
			ResourceLoader.load_threaded_get(path) as Texture2D
			if status == ResourceLoader.THREAD_LOAD_LOADED
			else null
		)
		if path != PANORAMAS.get(choice, ""):
			continue
		if texture:
			# Replacing the previous panorama releases it; one panorama stays in memory.
			_panorama = texture
			_panorama_path = path
		else:
			error = "Background unavailable"
		_apply()


func _apply() -> void:
	var path: String = PANORAMAS.get(choice, "")
	if PROCEDURAL.has(choice):
		_bake_scene(PROCEDURAL[choice])
		_procedural.set_shader_parameter("scene", _baked_scene)
		_procedural.set_shader_parameter("energy", brightness)
		sky.sky_material = _procedural
		loading = _baked_scene != PROCEDURAL[choice]
	else:
		_release_bake()
		_material.panorama = _panorama if not path.is_empty() and path == _panorama_path else null
		_material.energy_multiplier = brightness
		sky.sky_material = _material
		loading = not path.is_empty() and path in _requested
	changed.emit()


func ready_sky() -> Sky:
	if PROCEDURAL.has(choice):
		return sky if _baked_scene == PROCEDURAL[choice] else null
	return sky if _material.panorama != null else null


func _bake_scene(scene: int) -> void:
	if scene in [_baked_scene, _baking_scene]:
		return
	if not _bake:
		_bake = SubViewport.new()
		_bake.size = BAKE_SIZE
		_bake.disable_3d = true
		_bake.transparent_bg = false
		_bake.gui_disable_input = true
		_bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var canvas := ColorRect.new()
		canvas.size = BAKE_SIZE
		canvas.material = _bake_material
		_bake.add_child(canvas)
		add_child(_bake)
		_procedural.set_shader_parameter("baked", _bake.get_texture())
	_bake_material.set_shader_parameter("scene", scene)
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	_baking_scene = scene
	_bake_frame = Engine.get_process_frames()


## Panoramas and plain backgrounds do not keep the 32 MB bake texture.
func _release_bake() -> void:
	if not _bake:
		return
	_procedural.set_shader_parameter("baked", null)
	_bake.queue_free()
	_bake = null
	_baked_scene = -1
	_baking_scene = -1


func rotate_sky() -> void:
	yaw = fposmod(yaw + 45.0, 360.0)
	changed.emit()


func cycle_brightness() -> void:
	brightness = 0.5 if brightness >= 1.25 else brightness + 0.25
	_apply()


func set_yaw(value: float) -> void:
	if not is_finite(value):
		return
	yaw = fposmod(value, 360.0)
	changed.emit()


func set_brightness(value: float) -> void:
	if not is_finite(value):
		return
	brightness = clampf(value, 0.5, 1.25)
	_apply()


func _exit_tree() -> void:
	for path in _requested:
		ResourceLoader.load_threaded_get(path)
	_requested.clear()
