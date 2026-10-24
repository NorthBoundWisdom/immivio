extends RefCounted
## Bounded, hashed directory identities; disabling history never promotes session entries later.
const LIMIT := 512
var path := "user://directory_browse.cfg"
var session := {}
var disk := {}
var enabled := true
var persist := true
var dirty := false
var due := 0


func load_file() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var value: Variant = config.get_value("browse", "entries", {})
	if value is Dictionary:
		for key in value:
			if key is String and key.length() == 64 and value[key] is Dictionary:
				disk[key] = clean(value[key])
	trim(disk)


static func clean(value: Dictionary) -> Dictionary:
	return {
		"index": clampi(int(value.get("index", 0)), 0, 100000),
		"anchor": str(value.get("anchor", "")).left(64),
		"page": clampi(int(value.get("page", 0)), 0, 10000),
		"order": str(value.get("order", "name_asc"))
	}


func configure(remember: bool, history: bool) -> void:
	if persist and not history:
		flush()
	enabled = remember
	persist = history


func lookup(scope: String) -> Dictionary:
	if not enabled or scope.is_empty():
		return {}
	var key := scope.sha256_text()
	return session.get(key, disk.get(key, {}) if persist else {}).duplicate(true)


func remember(scope: String, value: Dictionary) -> void:
	if not enabled or scope.is_empty():
		return
	var key := scope.sha256_text()
	var entry := clean(value)
	if session.get(key) == entry:
		return
	session.erase(key)
	session[key] = entry
	trim(session)
	if persist:
		disk.erase(key)
		disk[key] = entry.duplicate()
		trim(disk)
		dirty = true
		due = Time.get_ticks_msec() + 700


func trim(entries: Dictionary) -> void:
	while entries.size() > LIMIT:
		entries.erase(entries.keys()[0])


func clear() -> void:
	session.clear()
	disk.clear()
	dirty = true
	flush()


func tick() -> void:
	if dirty and Time.get_ticks_msec() >= due:
		flush()


func flush() -> void:
	if not dirty:
		return
	var config := ConfigFile.new()
	config.set_value("browse", "entries", disk)
	if config.save(path + ".tmp") == OK and DirAccess.rename_absolute(path + ".tmp", path) == OK:
		dirty = false
