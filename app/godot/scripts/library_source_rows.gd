extends RefCounted
## Source list construction, row metadata and ordering; state remains with its existing owners.
const I18n := preload("res://scripts/i18n.gd")
const Section := preload("res://scripts/library_source_controller.gd").Section
const MediaFiles := preload("res://scripts/media_files.gd")
var menu: Node3D


func _init(owner: Node3D) -> void:
	menu = owner


func rebuild() -> void:
	menu.rows.clear()
	if menu.diagnostic_confirmation:
		menu.rows.assign(
			[
				{
					"title": I18n.t("Save diagnostic log to Downloads?"),
					"detail": "",
					"about_info": true
				},
				{"title": I18n.t("Save"), "confirm_diagnostic_save": true},
				{"title": I18n.t("Cancel"), "cancel_diagnostic_save": true}
			]
		)
		return
	if menu.subtitle_picker.active:
		menu.rows.assign(menu.subtitle_picker.rows())
		menu.scroll = clampf(menu.scroll, 0, menu._max_scroll())
		return
	if menu.account_panel.active():
		menu.rows.assign(menu.account_panel.rows())
		menu.scroll = clampf(menu.scroll, 0.0, menu._max_scroll())
		return
	match menu.section:
		Section.NETWORK:
			menu.rows.assign(menu.network.rows())
		Section.RECENT:
			for entry in menu.catalog.list_recent() if menu.catalog else []:
				var seconds := int(entry.position_ms) / 1000
				menu.rows.append(
					{
						"title": str(entry.title),
						"detail": "%02d:%02d" % [seconds / 60, seconds % 60] if seconds > 0 else "",
						"kind": "video",
						"icon": "video",
						"uri": str(entry.uri)
					}
				)
				if not str(entry.get("cover", "")).is_empty():
					menu.rows.back()["cover"] = entry.cover
				add_progress(menu.rows.back(), entry)
		Section.LOCAL:
			for entry in menu.sources.local_entries:
				var row := entry_row(entry)
				if bool(entry.get("volume", false)):
					row.icon = "usb" if bool(entry.get("removable", false)) else "device"
				menu.rows.append(row)
		Section.SMB:
			if menu.sources.smb_server.is_empty():
				for server in menu.sources.smb_servers:
					menu.rows.append(
						{
							"title": str(server.name),
							"detail": str(server.host),
							"icon": "server",
							"smb_server": str(server.id)
						}
					)
				for found in menu.sources.smb_found:
					if menu.sources.smb_servers.any(func(s): return str(s.host) == str(found.host)):
						continue
					menu.rows.append(
						{
							"title": str(found.name),
							"detail": str(found.host),
							"icon": "plus",
							"smb_found": found
						}
					)
			else:
				for entry in menu.sources.smb_entries:
					menu.rows.append(entry_row(entry))
		Section.DLNA:
			if menu.sources.dlna_server.is_empty():
				for server in menu.sources.dlna_servers:
					menu.rows.append(
						{
							"title": str(server.name),
							"detail": "",
							"icon": "cast",
							"dlna_server": str(server.id)
						}
					)
			else:
				for entry in menu.sources.dlna_entries:
					menu.rows.append(entry_row(entry))
		Section.SETTINGS:
			menu.rows.assign(menu._settings_rows())
	if menu.section == Section.MEDIA_SERVER:
		menu.rows = menu.server_browser.rows()
	menu.rows.assign(
		menu.rows.filter(
			func(row):
				return (
					not row.has("uri")
					or MediaFiles.is_video(
						str(row.uri), str(row.get("title", "")), str(row.get("kind", "video"))
					)
				),
		)
	)
	for row in menu.rows:
		if row.has("uri"):
			var parts: Array[String] = []
			if int(row.get("size", -1)) > 0:
				parts.append(size(row))
			if int(row.get("modified", 0)) > 0:
				parts.append(Time.get_date_string_from_unix_time(int(row.modified) / 1000))
			var recent: Dictionary = (
				menu.catalog.lookup(str(row.uri))
				if menu.catalog and menu.catalog.has_method("lookup")
				else {}
			)
			if int(recent.get("position_ms", 0)) > 0:
				var seconds := int(recent.position_ms) / 1000
				parts.append("%02d:%02d" % [seconds / 60, seconds % 60])
				add_progress(row, recent)
			if not parts.is_empty():
				row.detail = " · ".join(parts)
	menu.file_actions.sort_rows()
	if menu.section == Section.RECENT:
		menu._recent_all_rows.assign(menu.rows)
		menu._recent_count = menu.rows.size()
		menu._recent_page = clampi(menu._recent_page, 0, menu._recent_page_count() - 1)
		menu.rows.assign(
			menu._recent_all_rows.slice(
				menu._recent_page * menu.RECENT_PAGE_SIZE,
				(menu._recent_page + 1) * menu.RECENT_PAGE_SIZE
			)
		)
	menu.focus_index = clampi(menu.focus_index, 0, maxi(0, menu.rows.size() - 1))
	menu.scroll = clampf(menu.scroll, 0.0, menu._max_scroll())


## The open local folder's path ("" lists the storage volumes).
func entry_row(entry: Dictionary) -> Dictionary:
	if bool(entry.get("container", false)):
		var folder_row := {
			"title": str(entry.title),
			"detail": "",
			"icon": "folder",
			"container": entry,
			"folder": true,
			"delete_uri": str(entry.get("delete_uri", "")),
			"can_delete": bool(entry.get("can_delete", false)),
			"delete_reason":
			str(entry.get("delete_reason", "File deletion unavailable for this source"))
		}
		for field in ["size", "modified"]:
			if entry.has(field):
				folder_row[field] = entry[field]
		return folder_row
	var row := {
		"title": str(entry.title),
		"detail": size(entry),
		"kind": "video",
		"icon": "video",
		"uri": str(entry.get("uri", ""))
	}
	for field in ["size", "modified", "can_delete", "delete_reason", "id"]:
		if entry.has(field):
			row[field] = entry[field]
	if not str(entry.get("cover", "")).is_empty():
		row["cover"] = str(entry.cover)
	return row


static func size(entry: Dictionary) -> String:
	var bytes := float(entry.get("size", 0))
	if bytes <= 0:
		return ""
	return (
		"%.1f GB" % (bytes / 1073741824.0)
		if bytes >= 1073741824.0
		else "%d MB" % int(bytes / 1048576.0)
	)


## How far a started video got, when its length is known: tiles show it as a bar.
static func add_progress(row: Dictionary, entry: Dictionary) -> void:
	var duration := int(entry.get("duration_ms", -1))
	var position := int(entry.get("position_ms", 0))
	if duration > 0 and position > 0:
		row["progress"] = clampf(float(position) / duration, 0.0, 1.0)
