extends Node
## Application scenery independent from video playback.
signal changed
const BELFAST := "res://backgrounds/belfast_sunset_puresky.jpg"
const CHOICES := ["belfast", "dark", "passthrough"]
var choice := "belfast"
var yaw := 0.0
var brightness := 1.0
var loading := false
var error := ""
var sky := Sky.new()
var _material := PanoramaSkyMaterial.new()
var _builtin: Texture2D
var _builtin_requested := false


func _ready() -> void:
	sky.sky_material = _material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_material.filter = true
	if not select(choice):
		select("belfast")


func select(value: String) -> bool:
	if value not in CHOICES:
		return false
	choice = value
	error = ""
	if choice == "belfast" and not _builtin and not _builtin_requested:
		_builtin_requested = ResourceLoader.load_threaded_request(BELFAST, "Texture2D") == OK
		if not _builtin_requested:
			error = "Background unavailable"
	_apply()
	return true


func _process(_delta: float) -> void:
	if not _builtin_requested:
		return
	var status := ResourceLoader.load_threaded_get_status(BELFAST)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_builtin = ResourceLoader.load_threaded_get(BELFAST) as Texture2D
		_builtin_requested = false
		_apply()
	elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		_builtin_requested = false
		error = "Background unavailable"
		_apply()


func _apply() -> void:
	_material.panorama = _builtin if choice == "belfast" else null
	_material.energy_multiplier = brightness
	loading = choice == "belfast" and _builtin_requested
	changed.emit()


func ready_sky() -> Sky:
	return sky if _material.panorama != null else null


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
	if _builtin_requested:
		ResourceLoader.load_threaded_get(BELFAST)
