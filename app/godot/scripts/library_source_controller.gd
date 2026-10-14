extends RefCounted
## Owns asynchronous library requests, cancellation and cloud pagination.

var _host_ref: WeakRef
const PlatformMethods := preload("res://scripts/platform_methods.gd")

enum Section { RECENT, LOCAL, SMB, DLNA, CLOUD, SETTINGS, MEDIA_SERVER }
var _pending := {}  # request id -> kind
var _local_stack: Array = []  # [{id, title}] from a storage volume down to the open folder
var _local_entries: Array = []
var _cloud_stack: Array = []
var _cloud_entries: Array = []
var _cloud_page := 0  # zero-based, committed only after a successful response
var _cloud_next := -1
var _cloud_total := -1
var _cloud_offsets: Array[int] = [0]
var _cloud_positions := {}
var _cloud_location := ""
var _cloud_requested_page := 0
var _cloud_busy := false


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func _request(kind: String, id: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if id is int and id > 0:
		if kind == "cloud":
			for previous in host._pending.keys():
				if host._pending[previous] == "cloud":
					host._pending.erase(previous)
		if kind.begins_with("dlna") and kind not in ["dlna_save", "dlna_remove"]:
			for previous in host._pending.keys():
				if host._pending[previous] == kind:
					host._pending.erase(previous)
		host._pending[id] = kind
		if kind == "local":
			for previous in host._pending.keys():
				if previous != id and host._pending[previous] == "local":
					host._pending.erase(previous)
		host.status = "Loading…"
	else:
		host.status = "Unavailable"


func _on_media_list(id: int, payload: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.file_actions.receive(id, payload):
		return
	if host.cloud_accounts.receive(id, payload):
		return
	# Unsolicited store notifications also work when Quest does not pause/resume VR.
	if id == 0:
		var event: Variant = JSON.parse_string(payload)
		if event is Dictionary and event.get("source") == "local_storage":
			if event.get("state") == "error":
				if host.section == Section.LOCAL:
					host.status = "Storage device unavailable"
					host.refresh()
				return
			var volumes: Array = event.get("volumes", [])
			if volumes == host._local_volumes:
				return
			var removed = host._external_volumes().filter(
				func(volume): return not volumes.any(func(current): return str(current.id) == str(volume.id))
			)
			host._local_volumes = volumes
			for volume in removed:
				host.storage_removed.emit(volume.duplicate(true))
			if (
				not host._local_eject_pending.is_empty()
				and not host._local_volumes.any(
					func(volume): return str(volume.id) == host._local_eject_pending
				)
			):
				host._local_eject_pending = ""
			if (
				not host._local_stack.is_empty()
				and not host._local_volumes.any(
					func(volume): return str(volume.id) == str(host._local_stack[0].id)
				)
			):
				host._local_stack.clear()
				host._local_entries = []
				host._local_eject_pending = ""
			if host.section == Section.LOCAL and not host.account_panel.active():
				host._load_section()
				if host.visible:
					host.refresh()
			return
		if event is Dictionary and event.get("source") == "local_access":
			var access_state = str(event.get("state", "error"))
			host._local_grant_pending = access_state in ["requested", "settings_opened"]
			if host.section != Section.LOCAL or host.account_panel.active():
				return
			if access_state == "granted":
				host._load_section()
			elif access_state == "settings_opened":
				host.status = "Allow access in system settings"
			elif access_state == "requested":
				host.status = "Media access needed"
			else:
				host.status = str(event.get("error", "Permission settings unavailable"))
			if host.visible:
				host.refresh()
			return
		if (
			event is Dictionary
			and event.get("source") == "medialib"
			and event.get("state") == "accounts_changed"
		):
			host.server_browser.setup = false
			if host.section == Section.MEDIA_SERVER:
				# Let a VR deletion finish its saved-filter cleanup before reloading.
				if host.server_browser.pending.values().any(
					func(request): return request.action == "remove"
				):
					return
				host.server_browser.load_servers()
				host.refresh()
			return
	if host.server_browser.receive(id, payload):
		return
	if not host._pending.has(id):
		return
	var kind: String = host._pending[id]
	host._pending.erase(id)
	if kind.begins_with("dlna") and host.section != Section.DLNA:
		return
	if kind == "cloud":
		host._cloud_busy = false
	if kind == "cloud" and host.section != Section.CLOUD:
		return
	var parsed: Variant = JSON.parse_string(payload)
	if not parsed is Dictionary:
		if kind == "cloud":
			host.file_actions.cloud_failed()
			host.status = "Cloud connection failed"
			host.refresh()
		return
	var result: Dictionary = parsed
	if (
		kind == "cloud"
		and (
			str(result.get("path", "")) != host._cloud_path()
			or int(result.get("offset", 0)) != host._cloud_offsets[host._cloud_requested_page]
			or (
				not host._cloud_path().is_empty()
				and PlatformMethods.supports(host.platform, "media_cloud_sorted_page")
				and str(result.get("order", "")) != host.file_actions.cloud_order()
			)
		)
	):
		# A matching request ID with the wrong page is a protocol failure, not pending work.
		host.file_actions.cloud_failed()
		host.status = "Cloud connection failed"
		if host.visible:
			host.refresh()
		return
	host.status = ""
	var state = str(result.get("state", "error"))
	if state == "denied":
		host.status = (
			"All files access needed"
			if str(result.get("error", "")) == "ALL_FILES_ACCESS_NEEDED"
			else "Media access needed"
		)
	elif state != "ready":
		if kind == "cloud":
			host.file_actions.cloud_failed()
		host.status = str(result.get("error", "Error")).left(80)
	else:
		match kind:
			"cloud":
				host.file_actions.commit_cloud(str(result.get("order", "")))
				host._cloud_entries = result.get("entries", [])
				host._cloud_page = host._cloud_requested_page
				host._cloud_next = int(result.get("next_offset", -1))
				host._cloud_total = int(result.get("total", -1))
				host._cloud_page_size = maxi(1, int(result.get("page_size", 48)))
				host._reset_navigation()
			"local":
				if str(result.get("path", "")) == host._local_path():
					host._local_entries = result.get("entries", [])
					host._local_volumes = result.get(
						"volumes",
						(
							host._local_entries.filter(
								func(entry): return entry.get("volume", false)
							)
							if host._local_path().is_empty()
							else host._local_volumes
						)
					)
					host._local_all_files = bool(result.get("all_files", true))
					if host._local_release_notice:
						host._local_release_notice = false
						if host.section == Section.LOCAL:
							host.status = "Storage access stopped. You can unplug."
			"smb_servers":
				host._smb_servers = result.get("servers", [])
			"smb_found":
				host._smb_found = result.get("discovered", [])
			"smb_browse":
				if (
					str(result.get("server_id")) == host._smb_server
					and str(result.get("path")) == host._smb_path
				):
					host._smb_entries = result.get("entries", [])
			"dlna_servers", "dlna_discover", "dlna_save", "dlna_remove":
				host._dlna_servers = result.get("servers", [])
				if (
					kind in ["dlna_save", "dlna_remove"]
					and int(host._editor.get("request_id", -1)) == id
				):
					host._editor = {}
					host._dlna_server = ""
					host._dlna_stack.clear()
					host._dlna_entries.clear()
					host.scroll = 0.0
			"dlna_browse":
				var current_object = (
					str(host._dlna_stack.back().id) if not host._dlna_stack.is_empty() else "0"
				)
				if (
					str(result.get("server_id")) == host._dlna_server
					and str(result.get("object_id", current_object)) == current_object
				):
					host._dlna_entries = result.get("entries", [])
	if host.visible:
		host.refresh()


func _load_section() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.section == Section.MEDIA_SERVER:
		host.server_browser.load_servers()
		return
	if not host.platform:
		host.status = (
			"Headset only"
			if host.section in [Section.LOCAL, Section.SMB, Section.DLNA, Section.CLOUD]
			else ""
		)
		return
	match host.section:
		Section.CLOUD:
			host._load_cloud()
		Section.LOCAL:
			# Always read again: files change, and access may have just been granted in settings.
			host._request("local", host.platform.media_local_browse(host._local_path()))
		Section.SMB:
			if host._smb_server.is_empty():
				host._request("smb_servers", host.platform.media_smb_servers())
		Section.DLNA:
			if host._dlna_server.is_empty():
				if PlatformMethods.supports(host.platform, "media_dlna_servers"):
					host._request("dlna_servers", host.platform.media_dlna_servers())
				if host._dlna_servers.is_empty():
					host._request("dlna_discover", host.platform.media_dlna_discover())


func _local_path() -> String:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return ""
	return "" if host._local_stack.is_empty() else str(host._local_stack.back().id)


func _cloud_path() -> String:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return ""
	return "" if host._cloud_stack.is_empty() else str(host._cloud_stack.back().id)


func _cancel_cloud() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	for id in host._pending.keys():
		if host._pending[id] == "cloud":
			if PlatformMethods.supports(host.platform, "media_cloud_cancel"):
				host.platform.media_cloud_cancel(int(id))
			host._pending.erase(id)
	host._cloud_busy = false


func _load_cloud(reset: bool = true, force: bool = false, page: int = 0) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._cancel_cloud()
	if reset:
		if not host._cloud_entries.is_empty() or host._cloud_page > 0:
			host._cloud_positions[host._cloud_location] = {
				"page": host._cloud_page, "offsets": host._cloud_offsets.duplicate()
			}
			while host._cloud_positions.size() > 32:
				host._cloud_positions.erase(host._cloud_positions.keys()[0])
		host._cloud_location = host._cloud_path()
		var saved_page: Dictionary = host._cloud_positions.get(host._cloud_location, {})
		host._cloud_entries = []
		host._cloud_page = 0
		host._cloud_offsets.assign(saved_page.get("offsets", [0]))
		page = int(saved_page.get("page", 0))
		host._cloud_next = -1
		host._cloud_total = -1
	if not host.platform or page < 0 or page >= host._cloud_offsets.size():
		return
	host._cloud_requested_page = page
	host._cloud_busy = true
	if (
		PlatformMethods.supports(host.platform, "media_cloud_sorted_page")
		and not host._cloud_path().is_empty()
	):
		host._request(
			"cloud",
			host.platform.media_cloud_sorted_page(
				host._cloud_path(),
				host._cloud_offsets[page],
				force,
				host.file_actions.cloud_order()
			)
		)
	elif PlatformMethods.supports(host.platform, "media_cloud_page"):
		host._request(
			"cloud",
			host.platform.media_cloud_page(host._cloud_path(), host._cloud_offsets[page], force)
		)
	elif page == 0:
		host._request("cloud", host.platform.media_cloud_browse(host._cloud_path(), force))
	else:
		host.status = "Unavailable"
	if not host._pending.values().has("cloud"):
		host._cloud_busy = false


func _turn_cloud_page(step: int) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._cloud_busy or host._cloud_stack.is_empty():
		return
	var page = host._cloud_page + step
	if page < 0 or (step > 0 and host._cloud_next < 0):
		return
	if step > 0:
		host._cloud_offsets.resize(page + 1)
		host._cloud_offsets[page] = host._cloud_next
	host._load_cloud(false, false, page)
	host.refresh()


func _refresh_source() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.platform:
		return
	if host.section == Section.CLOUD:
		host._load_cloud(false, true, host._cloud_page)
		host.refresh()
		return
	match host.section:
		Section.LOCAL:
			host._local_grant_pending = false  # Also recovers when a VR settings overlay sends no resume.
			host._local_eject_pending = ""
		Section.SMB:
			if host._smb_server.is_empty():
				host._request("smb_found", host.platform.media_smb_discover())
			else:
				host._request(
					"smb_browse", host.platform.media_smb_browse(host._smb_server, host._smb_path)
				)
		Section.DLNA:
			if host._dlna_server.is_empty():
				host._request("dlna_discover", host.platform.media_dlna_discover())
			else:
				host._request(
					"dlna_browse",
					host.platform.media_dlna_browse(
						host._dlna_server,
						str(host._dlna_stack.back().id) if host._dlna_stack.size() > 0 else "0"
					)
				)
			host.refresh()
			return
	host._load_section()
	host.refresh()
