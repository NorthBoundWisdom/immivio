class_name DiagnosticLog extends RefCounted
const EVENT_PATH := "user://diagnostics/events.jsonl"
const MAX_BYTES := 256 * 1024
static var urls := RegEx.create_from_string("(?i)(?:https?|smb|file|content|medialib|externalvideo|user)://[^\\s\"<>]+")
static var secrets := RegEx.create_from_string("(?im)((?:[\"']?)(?:token|access_token|refresh_token|password|passwd|pwd|pw|authorization|cookie|set-cookie|api[_-]?key|signature|username|user_name|user_id|account|account_name|email|key|secret|client_secret)(?:[\"']?)\\s*[:=]\\s*)(?:\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'|[^\\r\\n,;}\\]]+)")
static var private_key := RegEx.create_from_string("(?i)^(?:.*token|.*password|.*authorization|.*cookie|.*signature|.*secret|.*account.*|username|user_name|user_id|user|email|api[_-]?key|key|pw|pwd|passwd)$")
static var paths := RegEx.create_from_string("(?:/storage/|/sdcard/|/data/user/|/Users/)[^\\s\"<>]+")
static func safe_text(value: String) -> String:
	return secrets.sub(paths.sub(urls.sub(value.left(2048), "[source]", true), "[path]", true), "$1[redacted]", true)
static func clean(value: Variant, budget: Array = [256], depth: int = 0) -> Variant:
	if depth == 0:
		budget = [256]
	budget[0] -= 1
	if budget[0] < 0 or depth > 6:
		return "[bounded]"
	if value is Dictionary:
		var result := {}
		for key in value.keys().slice(0, 32):
			var name := str(key).left(64)
			result[safe_text(name)] = "[redacted]" if private_key.search(name) else clean(value[key], budget, depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for item in value.slice(0, 32):
			result.append(clean(item, budget, depth + 1))
		return result
	if value is String:
		return safe_text(value)
	if value is bool or value is int or value == null:
		return value
	if value is float:
		return value if is_finite(value) else "[non-finite]"
	return "[object]"
static func record(event: String, details: Dictionary = {}) -> void:
	var entry := {"schema_version": 1, "event": safe_text(event).left(64), "monotonic_us": Time.get_ticks_usec(), "unix_seconds": Time.get_unix_time_from_system(), "details": clean(details, [256])}
	var line := JSON.stringify(entry)
	if line.to_utf8_buffer().size() > 8192:
		entry.details = {"bounded": true}
		line = JSON.stringify(entry)
	print("[VP_EVENT] ", line)
	if Engine.has_singleton("QuestPlayer"):
		var platform := Engine.get_singleton("QuestPlayer")
		if platform.has_method("record_diagnostic_event") and platform.record_diagnostic_event(entry.event, line):
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://diagnostics"))
	var current := FileAccess.open(EVENT_PATH, FileAccess.READ)
	var length := current.get_length() if current else 0
	if current:
		current.close()
	if length + line.to_utf8_buffer().size() + 1 > MAX_BYTES:
		var backup := "user://diagnostics/events.1.jsonl"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(EVENT_PATH), ProjectSettings.globalize_path(backup))
	var file := FileAccess.open(EVENT_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(EVENT_PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
