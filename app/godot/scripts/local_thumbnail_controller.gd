extends RefCounted
## Decode only visible local videos, one at a time, while the full library is idle.
const Platform := preload("res://scripts/platform_methods.gd")
const Cache := preload("res://scripts/thumbnail_cache.gd")
const Naming := preload("res://scripts/media_naming.gd")
const MediaFiles := preload("res://scripts/media_files.gd")
var _context := ""
var _pending := {}
var _attempted := {}
var _refresh_pending := false
var _next_request := 0
var _suspended := false


func set_suspended(menu: Node3D, value: bool) -> void:
	if value != _suspended:
		cancel(menu)
		_suspended = value


static func signature(row: Dictionary) -> String:
	return str([str(row.get("uri", "")), row.get("size", -1), row.get("modified", 0)])


func cancel(menu: Node3D) -> void:
	if not _pending.is_empty() and Platform.supports(menu.platform, "media_local_thumbnail_cancel"):
		menu.platform.media_local_thumbnail_cancel()
	_pending.clear()
	_attempted.clear()
	_context = ""
	_refresh_pending = false


func tick(menu: Node3D) -> void:
	var context: String = (
		menu._local_path()
		if (
			menu.visible
			and menu.section == menu.Section.LOCAL
			and not menu.playback_browser
			and not _suspended
		)
		else ""
	)
	if context != _context:
		cancel(menu)
		_context = context
	if context.is_empty() or not Platform.supports(menu.platform, "media_local_thumbnail"):
		return
	if menu.has_pointer_capture() or not menu._drag.is_empty() or absf(menu._fling) > 0.4:
		return
	if _refresh_pending:
		_refresh_pending = false
		menu.refresh()
	var now := Time.get_ticks_msec()
	if not _pending.is_empty():
		if now - int(_pending.started) > 15000:
			if Platform.supports(menu.platform, "media_local_thumbnail_cancel"):
				menu.platform.media_local_thumbnail_cancel()
			_pending.clear()
		return
	if now < _next_request:
		return
	var first: int = menu._first_line() * menu._cols()
	for row in menu.rows.slice(first, first + menu._drawn_slots()):
		var uri := str(row.get("uri", ""))
		if not uri.begins_with("file://") or not MediaFiles.is_video(uri) or row.has("container"):
			continue
		var fingerprint := signature(row)
		if Cache.has(uri) and not Cache.preview_matches(uri, fingerprint):
			Cache.forget(uri)
		if Cache.has(uri) or _attempted.has(fingerprint):
			continue
		_attempted[fingerprint] = true
		if _attempted.size() > 512:
			_attempted.erase(_attempted.keys()[0])
		var id: int = menu.platform.media_local_thumbnail(uri)
		if id > 0:
			_pending = {
				"id": id,
				"uri": uri,
				"title": row.get("title", uri.get_file()),
				"signature": fingerprint,
				"started": now
			}
		_next_request = now + 200
		return


func receive(menu: Node3D, id: int, payload: String) -> bool:
	if _pending.is_empty() or id != _pending.id:
		return false
	var request := _pending
	_pending = {}
	var value: Variant = JSON.parse_string(payload)
	if not value is Dictionary or value.get("uri", "") != request.uri:
		return true
	if (
		not menu.visible
		or _suspended
		or menu.playback_browser
		or menu.section != menu.Section.LOCAL
		or menu._local_path() != _context
	):
		return true
	if not menu.rows.any(func(row): return signature(row) == request.signature):
		return true
	if value.get("state") == "busy":
		_attempted.erase(request.signature)
		_next_request = Time.get_ticks_msec() + 1000
		return true
	var encoded := str(value.get("jpeg", ""))
	if value.get("state") != "ready" or encoded.is_empty() or encoded.length() > 1048576:
		return true
	var image := Image.new()
	if image.load_jpg_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
		return true
	if image.get_width() > 1280 or image.get_height() > 1280:
		return true
	var width := int(value.get("width", 0))
	var height := int(value.get("height", 0))
	if width <= 0 or height <= 0:
		return true
	var mode := Naming.complete(Naming.from_name(str(request.title)), width, height)
	# A displayed-frame thumbnail may have arrived meanwhile; it has better layout metadata.
	if (
		not Cache.has(request.uri)
		and Cache.store(
			request.uri, Cache.preview_frame(image, mode, Vector2(width, height)), request.signature
		)
	):
		_refresh_pending = true
	return true
