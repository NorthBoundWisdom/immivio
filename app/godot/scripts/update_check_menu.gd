extends RefCounted
## Session-only state. Attaching, rendering, resuming and startup never initiate network IO.
const Methods := preload("res://scripts/platform_methods.gd")
const I18n := preload("res://scripts/i18n.gd")
const STATES := ["available", "latest", "network_error", "rate_limited", "invalid_response"]
var owner_ref: WeakRef
var platform: Object
var pending := 0
var state := "idle"
var tag := ""
var current_version := ""
func _init(owner: Node3D) -> void:
	owner_ref = weakref(owner)
func attach(value: Object) -> void:
	if platform == value:
		return
	if is_instance_valid(platform) and platform.has_signal("update_check_ready") and platform.is_connected("update_check_ready", receive):
		platform.disconnect("update_check_ready", receive)
	platform = value
	pending = 0
	state = "idle"
	tag = ""
	if is_instance_valid(platform) and platform.has_signal("update_check_ready"):
		platform.connect("update_check_ready", receive)
func request() -> void:
	if state == "checking":
		return
	current_version = str(ProjectSettings.get_setting("application/config/version", ""))
	tag = ""
	state = "checking"
	pending = int(platform.request_update_check(current_version)) if Methods.supports(platform, "request_update_check") else -1
	if pending <= 0:
		state = "network_error"
	_refresh()
func receive(id: int, raw: String) -> void:
	if pending <= 0 or id != pending or state != "checking":
		return
	pending = 0
	var data: Variant = JSON.parse_string(raw)
	state = "invalid_response"
	if data is Dictionary and data.get("state") in STATES and data.get("version") == current_version:
		state = str(data.state)
		if state == "available":
			var value := str(data.get("tag", ""))
			if value.length() <= 256 * 1024 and RegEx.create_from_string("^v[0-9]+[.][0-9]+[.][0-9]+$").search(value):
				tag = value
			else:
				state = "invalid_response"
	_refresh()
func open_release() -> void:
	if state == "available" and not tag.is_empty() and Methods.supports(platform, "open_update_release"):
		if not platform.open_update_release(tag):
			state = "network_error"
			_refresh()
func rows() -> Array:
	var label := {"idle": "Check for updates", "checking": "Checking for updates…", "latest": "Up to date", "available": "New version available", "network_error": "Network error. Retry.", "rate_limited": "GitHub rate limit. Try later.", "invalid_response": "Update check failed. Retry."}
	var detail := ""
	if state == "latest":
		detail = I18n.t("Current version") + ": " + current_version
	elif state == "available":
		detail = tag.left(128)
	var result: Array = [{"title": I18n.t(label[state]), "detail": detail, "icon": "refresh", "check_updates": true}]
	if state == "available":
		result.append({"title": I18n.t("Open release page"), "detail": "GitHub", "icon": "forward", "open_update_release": true})
	return result
func _refresh() -> void:
	var owner := owner_ref.get_ref() as Node3D
	if is_instance_valid(owner):
		owner.refresh()
