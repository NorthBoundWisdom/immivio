extends RefCounted
## Session queue. Entries retain stable library URIs; decoded sessions remain owned by the player.
const LIMIT := 500
var items: Array[Dictionary] = []
var shuffle := false
var revision := 0
var custom := false
var anchor := ""
var _removed_uri := ""
var _continuation := ""
var _order: Array[String] = []


func replace(entries: Array) -> void:
	var copied := entries.duplicate(true)
	items.clear()
	append(copied)
	if items.is_empty():
		_changed()


func append(entries: Array) -> void:
	var previous_size := items.size()
	var known := {}
	for item in items:
		known[str(item.uri)] = true
	for entry in entries:
		if items.size() >= LIMIT:
			break
		if not entry is Dictionary:
			continue
		var uri := str(entry.get("uri", ""))
		if uri.is_empty() or uri.length() > 8192 or known.has(uri):
			continue
		if not (
			uri.get_slice(":", 0)
			in ["file", "content", "smb", "cloud", "medialib", "http", "https"]
		):
			continue
		if not entry.get("metadata", {}) is Dictionary:
			continue
		items.append(
			{
				"uri": uri,
				"title": str(entry.get("title", uri.get_file())).left(512),
				"metadata": entry.get("metadata", {}).duplicate(true)
			}
		)
		known[uri] = true
	if items.size() != previous_size:
		_changed()


func configure(key: String, enabled: bool, current_uri: String = "") -> void:
	if not current_uri.is_empty():
		anchor = current_uri
	match key:
		"queue_shuffle":
			shuffle = enabled
	_changed()


func _changed() -> void:
	revision += 1
	_order.assign(items.map(func(item): return str(item.uri)))
	if shuffle:
		_order.shuffle()
		if _order.has(anchor):
			_order.erase(anchor)
			_order.push_front(anchor)


func adjacent(uri: String, direction: int) -> Dictionary:
	if direction == 0 or _order.is_empty():
		return {}
	var index := _order.find(uri)
	if index < 0:
		if direction <= 0:
			return {}
		if uri == _removed_uri:
			return find(_continuation)
		return find(_order[0]) if uri == anchor else {}
	var next := index + (1 if direction > 0 else -1)
	if next < 0 or next >= _order.size():
		return {}
	return find(_order[next])


func find(uri: String) -> Dictionary:
	for item in items:
		if item.uri == uri:
			return item
	return {}


func remove(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	if items[index].uri == anchor:
		_removed_uri = anchor
		_continuation = str(adjacent(anchor, 1).get("uri", ""))
		if _continuation == anchor:
			_continuation = ""
	items.remove_at(index)
	_changed()


func move(index: int, direction: int) -> void:
	var target := index + direction
	if index < 0 or index >= items.size() or target < 0 or target >= items.size():
		return
	var item := items[index]
	items.remove_at(index)
	items.insert(target, item)
	_changed()


func clear() -> void:
	items.clear()
	_removed_uri = ""
	_continuation = ""
	_changed()


func saved_entries() -> Array:
	var result: Array = []
	for item in items:
		var metadata := {}
		for key in ["basename", "size"]:
			if item.metadata.has(key):
				metadata[key] = item.metadata[key]
		result.append({"uri": item.uri, "title": item.title, "metadata": metadata})
	return result


func relocate(old_uri: String, new_uri: String, title: String) -> void:
	for item in items:
		if item.uri == old_uri:
			item.uri = new_uri
			item.title = title
			item.metadata = {}
	_changed()
