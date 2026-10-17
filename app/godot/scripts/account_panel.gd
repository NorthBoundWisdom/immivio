extends RefCounted
## Media server accounts and license reading in the VR library ray menu.
const I18n := preload("res://scripts/i18n.gd")
const Methods := preload("res://scripts/platform_methods.gd")
const BASE := 2000
const FIELD := 2100
const KEY := 2200
var menu: Node
var view := ""
var kind := ""
var provider := ""
var session := 0
var data := {}
var items: Array = []
var fields: Array[String] = []
var field := ""
var shift := false
var symbols := false
var poll_time := 0.0
var revision := -1
var paused := false
var license_lines: Array[String] = []
var title := ""


func _init(owner: Node) -> void:
	menu = owner


func active() -> bool:
	return not view.is_empty()


func supported() -> bool:
	return Methods.supports(menu.platform, "account_open")


func close() -> void:
	if session > 0 and menu.platform:
		menu.platform.account_cancel(session)
	session = 0
	view = ""
	data = {}
	items = []
	fields.clear()
	field = ""
	license_lines.clear()
	menu.scroll = 0.0
	revision = -1
	paused = false
	_defaults = {}


func open(source: String, manage: bool = false) -> void:
	close()
	kind = source
	menu.server_browser.cancel()
	if not supported():
		menu.status = "Account settings unavailable"
		menu.refresh()
		return
	view = "accounts" if manage else "choose"
	title = "Media servers"
	if manage:
		load_accounts()
	menu.status = ""
	menu._reset_navigation()
	menu.refresh()


func load_accounts() -> void:
	var parsed: Variant = JSON.parse_string(menu.platform.account_list(kind))
	items = parsed if parsed is Array else []
	if not parsed is Array:
		menu.status = "Account settings unavailable"


func start(
	type: String, selected_provider: String = "", id: String = "", defaults: Dictionary = {}
) -> void:
	if session > 0:
		menu.platform.account_cancel(session)
	provider = selected_provider
	session = menu.platform.account_open(type, provider, id, JSON.stringify(defaults))
	view = "discover" if type == "discover" else "form"
	fields.assign(["name", "base", "username", "password"])
	if type == "server" and provider == "stash":
		fields.erase("username")
	if type == "server" and provider == "plex":
		fields.assign(["name", "base"])
	field = "base"
	if not field in fields:
		field = "name"
	_defaults = {}
	data = {}
	revision = -1
	title = "Search local network" if type == "discover" else provider_name(provider)
	menu.scroll = 0.0
	poll()
	menu.refresh()


func provider_name(value: String) -> String:
	return (
		{
			"emby": "Emby",
			"jellyfin": "Jellyfin",
			"stash": "Stash",
			"xbvr": "XBVR",
			"plex": "Plex"
		}
		. get(value, value)
	)


func poll() -> void:
	if session <= 0 or not menu.platform:
		return
	var parsed: Variant = JSON.parse_string(menu.platform.account_snapshot(session))
	if not parsed is Dictionary or parsed.is_empty():
		return
	var previous_pairing_expired := bool(data.get("pairing_expired", false))
	data = parsed
	var state := str(data.get("state", "form"))
	if state == "done":
		close()
		menu.server_browser.load_servers()
		menu.refresh()
		return
	if state in ["discover", "plex_link", "plex_servers"]:
		view = state
	if view == "discover":
		items = data.get("result", {}).get("servers", [])
	if view == "plex_servers":
		items = data.get("result", {}).get("servers", [])
	var changed := (
		int(data.get("revision", 0)) != revision
		or previous_pairing_expired != bool(data.get("pairing_expired", false))
	)
	revision = int(data.get("revision", 0))
	if changed:
		menu.refresh()


func tick(delta: float) -> void:
	if not active() or paused:
		return
	poll_time += delta
	if poll_time >= 0.2:
		poll_time = 0.0
		poll()


func lifecycle(state: String) -> void:
	paused = state == "pause"
	if not paused:
		poll()


func command(action: String, extra: Dictionary = {}) -> void:
	if session > 0:
		menu.platform.account_action(session, action, JSON.stringify(extra))
		poll()


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if view == "choose":
		result.append(
			{
				"title": I18n.t("Search local network"),
				"icon": "refresh",
				"account_discover": true
			}
		)
		for p in ["emby", "jellyfin", "plex", "stash", "xbvr"]:
			result.append({"title": provider_name(p), "icon": "server", "account_provider": p})
	elif view == "accounts":
		for item in items:
			result.append(
				{
					"title": str(item.name),
					"detail": provider_name(str(item.provider)),
					"icon": "edit",
					"account_edit": item
				}
			)
	elif view == "discover":
		for item in items:
			result.append(
				{
					"title": str(item.name) if not str(item.name).is_empty() else I18n.t("Server"),
					"detail": str(item.base),
					"icon": "server",
					"account_found": item
				}
			)
	elif view == "plex_servers":
		for item in items:
			result.append({"title": str(item.name), "icon": "server", "plex_server": str(item.id)})
	elif view == "license":
		for i in range(0, license_lines.size(), 2):
			result.append(
				{
					"title": license_lines[i],
					"detail": license_lines[i + 1] if i + 1 < license_lines.size() else "",
					"icon": "info",
					"about_info": true
				}
			)
	return result


func choose(row: Dictionary) -> bool:
	if not active():
		return false
	if row.has("account_provider"):
		start(kind, str(row.account_provider), "", _defaults)
	elif row.has("plex_server"):
		command("plex_select", {"server_id": str(row.plex_server)})
	elif row.has("account_edit"):
		start(kind, str(row.account_edit.provider), str(row.account_edit.id))
	elif row.has("account_discover"):
		start("discover")
	elif row.has("account_found"):
		var found: Dictionary = row.account_found
		if str(found.provider).is_empty():
			_defaults = found
			view = "choose"
			menu.refresh()
		else:
			start("server", str(found.provider), "", found)
	return true


var _defaults := {}


func action(target: int) -> bool:
	if not active() or target < BASE:
		return false
	if paused:
		return true
	if target == BASE:
		close()
		menu._load_section()
		menu.refresh()
		return true
	if target >= FIELD and target < FIELD + fields.size():
		field = fields[target - FIELD]
		menu.refresh()
		return true
	if target >= KEY and target < KEY + 40:
		var layer: Array = menu.SYMBOLS if symbols else menu.KEYS
		var value: String = layer[(target - KEY) / 10][(target - KEY) % 10]
		input("append", value.to_upper() if shift else value)
		shift = false
		return true
	match target - BASE:
		1:
			shift = not shift
			menu.refresh()
		2:
			symbols = not symbols
			menu.refresh()
		3:
			input("append", " ")
		4:
			input("backspace", "")
		5:
			input("paste", "")
		6:
			command("save_server")
		22:
			if session > 0:
				menu.platform.account_cancel(session)
				session = 0
			view = "choose"
			menu.scroll = 0.0
			menu.refresh()
		27:
			command("plex_authorize")
		28:
			command("plex_confirm")
	return true


func input(action_name: String, text: String) -> void:
	if data.get("busy", false):
		return
	menu.platform.account_input(session, field, action_name, text)
	poll()


func _draw_server_choices() -> void:
	menu._list = Node3D.new()
	menu.add_child(menu._list)
	menu._decorations.append(menu._list)
	menu._bar_thumb = null
	for i in range(1, menu.rows.size()):
		var k := i - 1
		var row: Dictionary = menu.rows[i]
		menu._button(
			menu.ROW_BASE + i,
			str(row.title),
			Vector2(-0.17 + (k % 2) * 0.65, 0.24 - (k / 2) * 0.19),
			Vector2(0.60, 0.16),
			true,
			"media_library",
			false,
			menu._list
		)
	if not menu.rows.is_empty():
		menu._button(
			menu.ROW_BASE,
			str(menu.rows[0].title),
			Vector2(0.155, -0.36),
			Vector2(1.25, 0.095),
			true,
			"",
			false,
			menu._list
		)


func draw() -> void:
	menu._button(BASE, "", Vector2(-0.52, 0.46), Vector2(0.09, 0.07), true, "up")
	menu._label(I18n.t(title), Vector3(0.13, 0.46, 0.004), 24)
	var enabled := not bool(data.get("busy", false))
	if view in ["choose", "accounts", "discover", "license", "plex_servers"]:
		if view == "choose" and kind == "server":
			_draw_server_choices()
		else:
			menu._draw_rows()
		if view == "accounts":
			menu._button(BASE + 22, "", Vector2(0.8, 0.46), Vector2(0.09, 0.07), true, "plus")
		if view == "discover":
			menu._button(
				BASE + 22, I18n.t("Add manually"), Vector2(0.15, -0.51), Vector2(0.38, 0.07)
			)
	elif view == "form":
		draw_fields(enabled)
		draw_keyboard(enabled)
		if provider == "plex":
			menu._button(
				BASE + 27, I18n.t("Authorize"), Vector2(0.17, 0.012),
				Vector2(0.7, 0.077), enabled, "", true
			)
		if provider != "plex" or _editing_id():
			menu._button(
				BASE + 6, I18n.t("Test and save"), Vector2(0.3, -0.51),
				Vector2(0.4, 0.07), enabled, "", true
			)
	elif view == "plex_link":
		menu._label("plex.tv/link", Vector3(0.15, 0.22, 0.008), 30)
		menu._label(str(data.get("result", {}).get("code", "")), Vector3(0.15, 0.05, 0.008), 56)
		menu._label(I18n.t("Pair on phone or computer"), Vector3(0.15, -0.065, 0.008), 17)
		menu._button(
			BASE + 28,
			I18n.t("Confirm pairing" if enabled else "Checking…"),
			Vector2(0.15, -0.21),
			Vector2(0.72, 0.09),
			(
				enabled
				and data.get("result", {}).has("code")
				and not bool(data.get("pairing_expired", false))
				and str(data.get("error", "")) != "Pairing code expired"
			),
			"",
			true
		)
		menu._button(BASE + 27, "", Vector2(0.15, -0.34), Vector2(0.12, 0.08), enabled, "refresh")
	var error := str(data.get("error", ""))
	error = I18n.t(error)
	if bool(data.get("busy", false)) and view != "plex_link":
		error = I18n.t("Connecting…")
	if not error.is_empty():
		menu._label(error, Vector3(0.15, 0.375, 0.006), 17)


func _editing_id() -> bool:
	return bool(data.get("editing_account", false))


func draw_fields(enabled: bool) -> void:
	var names := {
		"name": "Name",
		"base": "Server address",
		"username": "Username",
		"password": "Password"
	}
	if provider == "stash":
		names.password = "API Key"
	if provider == "plex":
		names.base = "Server address (optional)"
	for i in fields.size():
		var key: String = fields[i]
		var value := str(data.get("fields", {}).get(key, ""))
		if key == "password":
			value = "•".repeat(mini(int(data.get(key + "_length", 0)), 32))
			if key == "password" and value.is_empty() and data.get("has_password", false):
				value = I18n.t("Keep saved login")
		var y := 0.30 - i * 0.087
		menu._button(
			FIELD + i, "", Vector2(0.17, y), Vector2(1.2, 0.077), enabled, "", key == field
		)
		var node: MeshInstance3D = menu._buttons.back().node
		var label: Label3D = node.get_child(0)
		label.text = I18n.t(names[key])
		label.font_size = 16
		label.position = Vector3(-0.57, 0.012, 0.004)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var detail: Label3D = menu._label(
			menu._fit_title(value, "", 1.1, 19), Vector3(-0.57, -0.018, 0.004), 19, node
		)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		detail.modulate = Color(0.04, 0.10, 0.08) if key == field else Color.WHITE


func draw_keyboard(enabled: bool, offset: Vector2 = Vector2.ZERO) -> void:
	var layer: Array = menu.SYMBOLS if symbols else menu.KEYS
	for row in 4:
		for col in 10:
			var value: String = layer[row][col]
			menu._button(
				KEY + row * 10 + col,
				value.to_upper() if shift else value,
				Vector2(-0.40 + col * 0.125, -0.10 - row * 0.071) + offset,
				Vector2(0.114, 0.061),
				enabled
			)
	for spec in [
		[1, "⇧", -0.36, 0.16],
		[2, "#+=" if not symbols else "abc", -0.16, 0.2],
		[3, "␣", 0.15, 0.36],
		[4, "⌫", 0.46, 0.2],
		[5, I18n.t("Paste"), 0.7, 0.22]
	]:
		menu._button(
			BASE + int(spec[0]),
			str(spec[1]),
			Vector2(float(spec[2]), -0.405) + offset,
			Vector2(float(spec[3]), 0.073),
			enabled
		)


func show_license(name: String, text: String) -> void:
	close()
	view = "license"
	title = name
	for original in text.split("\n"):
		var line := ""
		for c in original:
			if (
				(
					menu.ui_font().get_string_size(line + c, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
					* 0.0012
				)
				> 1.12
			):
				license_lines.append(line)
				line = ""
			line += c
		license_lines.append(line)
	menu._reset_navigation()
	menu.refresh()
