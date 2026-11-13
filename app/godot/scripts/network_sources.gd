extends RefCounted
## Unified entry for saved/discovered network sources; backend browsers retain
## their own account, folder and playback state.
const I18n := preload("res://scripts/i18n.gd")
const Methods := preload("res://scripts/platform_methods.gd")
const ADD := 94
const MANAGE := 95
const DISCOVER := 96
var menu: Node3D
var mode := ""
var save_request := 0


func _init(owner: Node3D) -> void:
	menu = owner


func contains(section: int) -> bool:
	return (
		section
		in [menu.Section.NETWORK, menu.Section.SMB, menu.Section.DLNA, menu.Section.MEDIA_SERVER]
	)


func open() -> void:
	menu.remember_browse()
	menu.file_actions.reset()
	menu.account_panel.close()
	menu.server_browser.cancel()
	menu.section = menu.Section.NETWORK
	mode = ""
	save_request = 0
	menu._editor = {}
	menu.status = ""
	menu._reset_navigation()
	load_sources()
	menu.refresh()


func load_sources(discover: bool = false) -> void:
	# Keep saved sources visible while refreshed results arrive independently.
	if Methods.supports(menu.platform, "media_server_request"):
		menu.server_browser.request("servers")
	for request in [["smb_servers", "media_smb_servers"], ["dlna_servers", "media_dlna_servers"]]:
		if Methods.supports(menu.platform, request[1]):
			menu.sources.request(request[0], menu.platform.call(request[1]))
	if discover or menu._smb_found.is_empty():
		if Methods.supports(menu.platform, "media_smb_discover"):
			menu.sources.request("smb_found", menu.platform.media_smb_discover())
	if discover or menu._dlna_servers.is_empty():
		if Methods.supports(menu.platform, "media_dlna_discover"):
			menu.sources.request("dlna_discover", menu.platform.media_dlna_discover())


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not mode.is_empty():
		result.assign(
			[
				{
					"title": I18n.t("Shared folders (SMB)"),
					"detail": I18n.t("Folders shared by a computer or NAS"),
					"icon": "server",
					"network_type": menu.Section.SMB,
					"stack_detail": true
				},
				{
					"title": I18n.t("Local media libraries (DLNA)"),
					"detail": I18n.t("Media libraries announced on your local network"),
					"icon": "cast",
					"network_type": menu.Section.DLNA,
					"stack_detail": true
				}
			]
		)
		for provider in menu.account_panel.PROVIDERS:
			result.append(
				{
					"title": menu.account_panel.provider_name(provider),
					"detail": I18n.t("Media servers"),
					"stack_detail": true,
					"icon": preload("res://scripts/provider_icons.gd").key(provider),
					"network_type": menu.Section.MEDIA_SERVER,
					"network_provider": provider
				}
			)
		return result
	# Saved sources first, then what the local network announces; each list under its own heading.
	var saved: Array[Dictionary] = []
	var found: Array[Dictionary] = []
	for server in menu._smb_servers:
		saved.append(
			{
				"id": "smb:" + str(server.id),
				"title": str(server.name),
				"detail": I18n.t("Shared folders (SMB)"),
				"icon": "server",
				"network_section": menu.Section.SMB,
				"smb_server": str(server.id)
			}
		)
	for server in menu.server_browser.servers:
		saved.append(
			{
				"id": "server:" + str(server.id),
				"title": str(server.name),
				"detail": menu.account_panel.provider_name(str(server.get("provider", ""))),
				"icon":
				preload("res://scripts/provider_icons.gd").key(str(server.get("provider", ""))),
				"network_section": menu.Section.MEDIA_SERVER,
				"server_account": server
			}
		)
	for server in menu._dlna_servers:
		(saved if bool(server.get("manual", false)) else found).append(
			{
				"id": "dlna:" + str(server.id),
				"title": str(server.name),
				"detail": I18n.t("Local media libraries (DLNA)"),
				"icon": "cast",
				"network_section": menu.Section.DLNA,
				"dlna_server": str(server.id)
			}
		)
	for candidate in menu._smb_found:
		if not menu._smb_servers.any(func(server): return str(server.host) == str(candidate.host)):
			found.append(
				{
					"id": "smb-found:" + str(candidate.host),
					"title": str(candidate.name),
					"detail": str(candidate.host) + " · " + I18n.t("Shared folders (SMB)"),
					"icon": "plus",
					"network_section": menu.Section.SMB,
					"smb_found": candidate
				}
			)
	if not saved.is_empty():
		result.append({"title": I18n.t("My sources"), "group": true})
		result.append_array(saved)
	if not found.is_empty():
		result.append({"title": I18n.t("Found on this network"), "group": true})
		result.append_array(found)
	return result


func action(target: int) -> bool:
	if menu.section != menu.Section.NETWORK:
		return false
	if target in [ADD, MANAGE]:
		mode = "add" if target == ADD else "manage"
		save_request = 0
		menu.status = ""
		menu._reset_navigation()
		menu.refresh()
		return true
	if target == DISCOVER and mode == "add":
		menu.section = menu.Section.MEDIA_SERVER
		menu.account_panel.open("server")
		if menu.account_panel.active():
			menu.account_panel.start("discover")
		return true
	if target == menu.BACK and not mode.is_empty():
		mode = ""
		menu._reset_navigation()
		menu.refresh()
		return true
	return false


func choose(row: Dictionary) -> bool:
	if not row.has("network_section") and not row.has("network_type"):
		return false
	menu.server_browser.cancel()
	menu.section = int(row.get("network_section", row.get("network_type")))
	menu._reset_navigation()
	menu.status = ""
	if row.has("network_type"):
		if menu.section == menu.Section.MEDIA_SERVER:
			menu.account_panel.open("server", mode == "manage", str(row.network_provider))
		elif mode == "add":
			menu._open_editor({})
		else:
			if menu.section == menu.Section.SMB:
				menu._smb_server = ""
			elif menu.section == menu.Section.DLNA:
				menu._dlna_server = ""
			menu.sources.load_section()
		menu.refresh()
	else:
		var source := row.duplicate()
		source.erase("network_section")
		if source.has("smb_server") and menu._smb_server == str(source.smb_server):
			menu.sources.request(
				"smb_browse", menu.platform.media_smb_browse(menu._smb_server, menu._smb_path)
			)
			menu.refresh()
		elif source.has("dlna_server") and menu._dlna_server == str(source.dlna_server):
			menu.sources.request(
				"dlna_browse",
				menu.platform.media_dlna_browse(
					menu._dlna_server,
					str(menu._dlna_stack.back().id) if not menu._dlna_stack.is_empty() else "0"
				)
			)
			menu.refresh()
		elif (
			source.has("server_account")
			and menu.server_browser.server.get("id") == source.server_account.get("id")
			and menu.server_browser.view != "servers"
		):
			menu.refresh()
		else:
			menu._choose(source)
	return true


func draw() -> void:
	var chooser := not mode.is_empty()
	if chooser:
		menu._button(
			menu.BACK,
			"",
			Vector2(menu.CONTENT_LEFT + .045, menu.HEADER_Y),
			Vector2(.09, .07),
			true,
			"up"
		)
	var title := I18n.t(
		"Add source" if mode == "add" else ("Manage sources" if chooser else "Network media")
	)
	var label: Label3D = menu._label(
		title, Vector3(menu.CONTENT_LEFT + (.12 if chooser else 0), menu.HEADER_Y, .004), 26
	)
	label.font = menu.ui_font_bold()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if mode == "add":
		menu._glyph(
			DISCOVER,
			"refresh",
			Vector2(menu.CONTENT_RIGHT - .0375, menu.HEADER_Y),
			.075,
			Methods.supports(menu.platform, "account_open"),
			I18n.t("Search local network")
		)
	if not chooser:
		menu._control_button(
			ADD,
			I18n.t("Add source"),
			Vector2(menu.CONTENT_RIGHT - .38, menu.HEADER_Y),
			.32,
			true,
			"plus"
		)
		menu._glyph(
			MANAGE,
			"settings",
			Vector2(menu.CONTENT_RIGHT - .1475, menu.HEADER_Y),
			.075,
			true,
			I18n.t("Manage sources")
		)
		menu._glyph(
			menu.REFRESH,
			"refresh",
			Vector2(menu.CONTENT_RIGHT - .0375, menu.HEADER_Y),
			.075,
			menu.platform != null,
			I18n.t("Refresh")
		)
	menu._decoration(
		Vector2(menu.CONTENT_RIGHT - menu.CONTENT_LEFT, .002),
		Vector2(menu.PANEL_CENTRE.x, menu.GRID_TOP + .03),
		menu.DIVIDER
	)
	menu._draw_rows()
	if menu.rows.is_empty():
		menu._icon("media_library", Vector3(menu.PANEL_CENTRE.x, .2, .004), .09, menu.MUTED)
		var empty: Label3D = menu._label(
			I18n.t("No network sources yet"), Vector3(menu.PANEL_CENTRE.x, .09, .004), 22
		)
		empty.font = menu.ui_font_bold()
		var hint: Label3D = menu._label(
			I18n.t("Add a source or refresh to find devices"),
			Vector3(menu.PANEL_CENTRE.x, .02, .004),
			17
		)
		hint.modulate = menu.MUTED
	var status: Label3D = menu._label(
		menu._fit_title(I18n.t(menu.status), "", menu.CONTENT_RIGHT - menu.CONTENT_LEFT, 17),
		Vector3(menu.CONTENT_LEFT, menu.FOOTER_Y, .004),
		17
	)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status.modulate = menu.MUTED
