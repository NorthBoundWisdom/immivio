extends Node

## Startup-only existence checks. No decoder, thumbnails, or network requests.
signal changed

const Methods := preload("res://scripts/platform_methods.gd")
var catalog: RefCounted
var platform: Object
var _pending: Array[Dictionary] = []
var _entry: Dictionary = {}
var _request := 0
var _wait := 0.0
var _deadline := 0.0
var _busy_retries := 0


func start(history: RefCounted, host: Object = null) -> void:
	catalog = history
	platform = host
	_pending = catalog.list_recent()
	if (
		Methods.supports(platform, "request_local_video_access")
		and platform.has_signal("local_video_access")
	):
		platform.connect("local_video_access", _on_access)
	set_process(true)


func _process(delta: float) -> void:
	if _request > 0:
		_deadline -= delta
		if _deadline <= 0.0:
			var expired := _request
			_request = 0
			_entry = {}
			platform.cancel_local_video_access(expired)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _pending.is_empty():
		set_process(false)
		return
	var entry: Dictionary = _pending.pop_front()
	var uri := str(entry.uri)
	if not (uri.begins_with("file://") or uri.begins_with("content://")):
		return
	if (
		Methods.supports(platform, "request_local_video_access")
		and platform.has_signal("local_video_access")
	):
		_entry = entry
		_request = platform.request_local_video_access(uri)
		if _request > 0:
			_deadline = 12.0
			_busy_retries = 0
		else:
			_entry = {}
			_busy_retries += 1
			if _busy_retries < 3:
				_pending.push_front(entry)
			else:
				_busy_retries = 0
			_wait = 0.25
	elif uri.begins_with("file://") and _file_missing(uri):
		_remove(entry)


static func _file_missing(uri: String) -> bool:
	var path := uri.substr(7).uri_decode().simplify_path()
	if not path.is_absolute_path():
		return false
	if FileAccess.file_exists(path):
		return false
	# An unavailable volume or denied directory is not evidence of deletion.
	for prefix in ["/storage/", "/mnt/media_rw/", "/Volumes/"]:
		if path.begins_with(prefix):
			var mount: String = prefix + path.substr(prefix.length()).get_slice("/", 0)
			if mount == "/storage/emulated":
				mount += "/0"
			if DirAccess.open(mount) == null:
				return false
	# If a containing folder was deleted, confirm its absence in the nearest
	# readable ancestor rather than keeping all of its stale children forever.
	var candidate := path
	var parent_path := candidate.get_base_dir()
	var parent := DirAccess.open(parent_path)
	while not parent:
		candidate = parent_path
		parent_path = candidate.get_base_dir()
		if parent_path == candidate or parent_path.is_empty():
			return false
		parent = DirAccess.open(parent_path)
	if parent.list_dir_begin() != OK:
		return false
	parent.include_hidden = true
	var found := false
	var name := parent.get_next()
	while not name.is_empty():
		if name == candidate.get_file():
			found = true
		name = parent.get_next()
	parent.list_dir_end()
	return not found


func _on_access(id: int, payload: String) -> void:
	if id != _request or _entry.is_empty():
		return
	var parser := JSON.new()
	if parser.parse(payload) != OK:
		return
	var result: Variant = parser.data
	if not result is Dictionary or result.get("uri") != _entry.uri:
		return
	var entry := _entry
	_entry = {}
	_request = 0
	_wait = 0.05
	if result.get("state") == "error" and result.get("error") == "LOCAL_DOCUMENT_MISSING":
		if str(entry.uri).begins_with("file://"):
			if _file_missing(entry.uri):
				_remove(entry)
		elif result.get("missing_confirmed", false) == true:
			_remove(entry)


func _remove(entry: Dictionary) -> void:
	# A selection/rename during the scan must not be removed by an old response.
	var current: Dictionary = catalog.lookup(entry.uri)
	if current.get("opened", -1) != entry.opened:
		return
	if catalog.forget(entry.uri):
		catalog.save()
		changed.emit()


func _exit_tree() -> void:
	if is_instance_valid(platform):
		if (
			platform.has_signal("local_video_access")
			and platform.is_connected("local_video_access", _on_access)
		):
			platform.disconnect("local_video_access", _on_access)
		if _request > 0:
			platform.cancel_local_video_access(_request)
