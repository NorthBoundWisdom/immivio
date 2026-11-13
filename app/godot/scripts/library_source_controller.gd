extends RefCounted
## Owns asynchronous library requests and cancellation.

var _host_ref: WeakRef
const PlatformMethods := preload("res://scripts/platform_methods.gd")

enum Section { RECENT, LOCAL, SMB, DLNA, SETTINGS, MEDIA_SERVER, NETWORK }
var pending: Dictionary = {}  # request id -> kind
var _request_sections := {}
var local_stack: Array = []  # [{id, title}] from a storage volume down to the open folder
var local_entries: Array = []
var local_all_files: bool = true
var local_grant_pending: bool = false
var local_volumes: Array = []
var local_eject_pending: String = ""
var local_release_notice: bool = false
var smb_servers: Array = []
var smb_found: Array = []
var smb_server: String = ""
var smb_path: String = ""
var smb_entries: Array = []


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func request(kind: String, id: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if id is int and id > 0:
		if kind.begins_with("dlna") and kind not in ["dlna_save", "dlna_remove"]:
			for previous in pending.keys():
				if pending[previous] == kind:
					pending.erase(previous)
					_request_sections.erase(previous)
		pending[id] = kind
		_request_sections[id] = host.section
		if kind == "local":
			for previous in pending.keys():
				if previous != id and pending[previous] == "local":
					pending.erase(previous)
					_request_sections.erase(previous)
		host.status = "Loading…"
	else:
		host.status = "Unavailable"


func receive(id: int, payload: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.local_thumbnails.receive(host, id, payload):
		return
	if host.file_actions.receive(id, payload):
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
			if volumes == local_volumes:
				return
			var removed = external_volumes().filter(
				func(volume):
					return not volumes.any(func(current): return str(current.id) == str(volume.id))
			)
			local_volumes = volumes
			for volume in removed:
				host.storage_removed.emit(volume.duplicate(true))
			if (
				not local_eject_pending.is_empty()
				and not local_volumes.any(
					func(volume): return str(volume.id) == local_eject_pending
				)
			):
				local_eject_pending = ""
			if (
				not local_stack.is_empty()
				and not local_volumes.any(
					func(volume): return str(volume.id) == str(local_stack[0].id)
				)
			):
				local_stack.clear()
				local_entries = []
				local_eject_pending = ""
			if host.section == Section.LOCAL and not host.account_panel.active():
				load_section()
				if host.visible:
					host.refresh()
			return
		if event is Dictionary and event.get("source") == "local_access":
			var access_state = str(event.get("state", "error"))
			local_grant_pending = access_state in ["requested", "settings_opened"]
			if host.section != Section.LOCAL or host.account_panel.active():
				return
			if access_state == "granted":
				load_section()
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
			if host.section in [Section.MEDIA_SERVER, Section.NETWORK]:
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
	if not pending.has(id):
		return
	var kind: String = pending[id]
	pending.erase(id)
	var requested_section: int = _request_sections.get(id, host.section)
	_request_sections.erase(id)
	if requested_section != host.section:
		return
	if kind.begins_with("dlna") and host.section not in [Section.DLNA, Section.NETWORK]:
		return
	var parsed: Variant = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return
	var result: Dictionary = parsed
	if (
		kind == "smb_browse"
		and result.has("server_id")
		and (str(result.get("server_id")) != smb_server or str(result.get("path")) != smb_path)
	):
		return
	if (
		kind == "dlna_browse"
		and result.has("object_id")
		and (
			str(result.get("server_id")) != host.source_dlna_server
			or (
				str(result.object_id)
				!= (
					str(host.source_dlna_stack.back().id)
					if not host.source_dlna_stack.is_empty()
					else "0"
				)
			)
		)
	):
		return
	if kind == "local" and result.has("path") and str(result.path) != local_path():
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
		host.status = str(result.get("error", "Error")).left(80)
	else:
		match kind:
			"local":
				if str(result.get("path", "")) == local_path():
					local_entries = result.get("entries", [])
					local_volumes = result.get(
						"volumes",
						(
							local_entries.filter(func(entry): return entry.get("volume", false))
							if local_path().is_empty()
							else local_volumes
						)
					)
					local_all_files = bool(result.get("all_files", true))
					if local_release_notice:
						local_release_notice = false
						if host.section == Section.LOCAL:
							host.status = "App access stopped. Use system settings before unplugging."
			"smb_servers":
				smb_servers = result.get("servers", [])
			"smb_found":
				smb_found = result.get("discovered", [])
			"smb_browse":
				if (
					str(result.get("server_id")) == smb_server
					and str(result.get("path")) == smb_path
				):
					smb_entries = result.get("entries", [])
			"dlna_servers", "dlna_discover", "dlna_save", "dlna_remove":
				host.source_dlna_servers = result.get("servers", [])
				if (
					kind in ["dlna_save", "dlna_remove"]
					and int(host.source_editor.get("request_id", -1)) == id
				):
					host.source_editor = {}
					host.source_dlna_server = ""
					host.source_dlna_stack.clear()
					host.source_dlna_entries.clear()
					host.scroll = 0.0
			"dlna_browse":
				var current_object = (
					str(host.source_dlna_stack.back().id)
					if not host.source_dlna_stack.is_empty()
					else "0"
				)
				if (
					str(result.get("server_id")) == host.source_dlna_server
					and str(result.get("object_id", current_object)) == current_object
				):
					host.source_dlna_entries = result.get("entries", [])
	if (
		state == "ready"
		and host.network.mode == "add"
		and id == host.network.save_request
		and host.source_editor.is_empty()
		and kind in ["smb_servers", "dlna_save"]
	):
		host.network.open()
		return
	if host.visible:
		host.refresh()


func load_section() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.section == Section.NETWORK:
		host.network.load_sources()
		return
	if host.section == Section.MEDIA_SERVER:
		host.server_browser.load_servers()
		return
	if not host.platform:
		host.status = (
			"Headset only" if host.section in [Section.LOCAL, Section.SMB, Section.DLNA] else ""
		)
		return
	match host.section:
		Section.LOCAL:
			# Always read again: files change, and access may have just been granted in settings.
			request("local", host.platform.media_local_browse(local_path()))
		Section.SMB:
			if smb_server.is_empty():
				request("smb_servers", host.platform.media_smb_servers())
		Section.DLNA:
			if host.source_dlna_server.is_empty():
				if PlatformMethods.supports(host.platform, "media_dlna_servers"):
					request("dlna_servers", host.platform.media_dlna_servers())
				if host.source_dlna_servers.is_empty():
					request("dlna_discover", host.platform.media_dlna_discover())


func local_path() -> String:
	return "" if local_stack.is_empty() else str(local_stack.back().id)


func external_volumes() -> Array:
	return local_volumes.filter(func(volume): return bool(volume.get("removable", false)))


func refresh_source() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.section == Section.NETWORK:
		host.network.load_sources(true)
		host.refresh()
		return
	if not host.platform:
		return
	match host.section:
		Section.LOCAL:
			local_grant_pending = false  # Also recovers when a VR settings overlay sends no resume.
			local_eject_pending = ""
		Section.SMB:
			if smb_server.is_empty():
				request("smb_found", host.platform.media_smb_discover())
			else:
				request("smb_browse", host.platform.media_smb_browse(smb_server, smb_path))
		Section.DLNA:
			if host.source_dlna_server.is_empty():
				request("dlna_discover", host.platform.media_dlna_discover())
			else:
				request(
					"dlna_browse",
					host.platform.media_dlna_browse(
						host.source_dlna_server,
						(
							str(host.source_dlna_stack.back().id)
							if host.source_dlna_stack.size() > 0
							else "0"
						)
					)
				)
			host.refresh()
			return
	load_section()
	host.refresh()
