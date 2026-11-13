extends "res://scripts/ray_menu.gd"

## Library: recent, local files, network media and settings; right content with sub-tabs,
## breadcrumbs and a scrolling list (ray drag anywhere on the list, or either thumbstick). Sources answer
## asynchronously through the platform's media_list(id, json) signal. Selection is controller ray + trigger only.

signal chosen(uri: String, title: String)
signal subtitle_chosen(selection: Dictionary)
signal subtitle_system_requested
var subtitle_picker := preload("res://scripts/subtitle_picker.gd").new(self)
signal player_requested
signal queue_requested(operation: String)
var queue_add_mode := false
var diagnostic_confirmation := false
var update_check := preload("res://scripts/update_check_menu.gd").new(self)
signal layout_changed
const VIEW_MODE := 90
var list_view := false
var compact := false
var playback_browser := false
const BrowseMemory := preload("res://scripts/directory_browse_memory.gd")
var browse_memory := BrowseMemory.new()
var _browse_scope := ""
var _browse_restore := {}


func directory_scope() -> String:
	if diagnostic_confirmation:
		return ""
	if subtitle_picker.active:
		return ""
	if account_panel.active() or not editor.is_empty():
		return ""
	match section:
		Section.NETWORK:
			return JSON.stringify([section, "sources"]) if network.mode.is_empty() else ""
		Section.LOCAL:
			return JSON.stringify([section, sources.local_path(), 0])
		Section.SMB:
			return JSON.stringify([section, sources.smb_server, sources.smb_path, 0])
		Section.DLNA:
			return JSON.stringify(
				[
					section,
					sources.dlna_server,
					sources.dlna_stack.back().id if not sources.dlna_stack.is_empty() else "0",
					0
				]
			)
		Section.MEDIA_SERVER:
			return JSON.stringify(
				[
					section,
					server_browser.server.get("id", ""),
					server_browser.view,
					server_browser.query
				]
			)
	return ""


func _row_identity(row: Dictionary) -> String:
	return (
		str(row.get("uri", row.get("container", {}).get("id", row.get("id", row.get("title", "")))))
		. sha256_text()
	)


func remember_browse() -> void:
	if _browse_scope.is_empty() or not _browse_restore.is_empty() or status == "Loading…":
		return
	var index := mini(_first_line() * _cols(), maxi(0, rows.size() - 1))
	browse_memory.remember(
		_browse_scope,
		{
			"index": index,
			"anchor": _row_identity(rows[index]) if not rows.is_empty() else "",
			"order": file_actions.order()
		}
	)


func _restore_browse() -> void:
	if _browse_restore.is_empty() or rows.is_empty() or status == "Loading…":
		return
	var index := int(_browse_restore.get("index", 0))
	for i in rows.size():
		if _row_identity(rows[i]) == _browse_restore.get("anchor", ""):
			index = i
			break
	scroll = clampf(float(index / _cols()), 0.0, _max_scroll())
	_browse_restore = {}


const QUEUE_ADD_LIST := 88
const QUEUE_DONE := 89
signal recenter_requested
signal setting_changed(key: String, value: Variant)
signal setting_previewed(key: String, value: Variant)
signal storage_eject_requested(volume: Dictionary)
signal storage_removed(volume: Dictionary)
signal file_delete_preparing(uri: String)
signal file_deleted(uri: String)
signal file_renamed(old_uri: String, new_uri: String, title: String)
var current_file_provider: Callable
const FileActions := preload("res://scripts/library_file_actions.gd")
var file_actions := FileActions.new(self)

const LibrarySourceController := preload("res://scripts/library_source_controller.gd")
var sources := LibrarySourceController.new(self)

const Section := LibrarySourceController.Section
const NAV := [
	"Recent",
	"Local files",
	"Shared folders (SMB)",
	"Local media libraries (DLNA)",
	"Settings",
	"Media servers",
	"Network media"
]
const NAV_ICONS := [
	"history", "device", "server", "cast", "settings", "media_library", "media_library"
]
const NAV_ORDER := [Section.RECENT, Section.LOCAL, Section.NETWORK, Section.SETTINGS]
var network := preload("res://scripts/network_sources.gd").new(self)
const ServerBrowser := preload("res://scripts/media_server_browser.gd")
const PlatformMethods := preload("res://scripts/platform_methods.gd")
const StorageVolume := preload("res://scripts/storage_volume.gd")
var server_browser: RefCounted = ServerBrowser.new(self)
const AccountPanel := preload("res://scripts/account_panel.gd")
var account_panel: RefCounted = AccountPanel.new(self)
const Quality := preload("res://scripts/display_quality.gd")
const ChoiceFields := preload("res://scripts/choice_fields.gd")
var choices := ChoiceFields.new(self)
## Settings pages in tab order; each page lists titled groups of related controls.
const SETTING_TABS := ["General", "Display", "Playback", "Appearance", "About"]
const GENERAL_TAB := 0  # language, hands, library data
const DISPLAY_TAB := 1  # picture quality, window placement
const PLAYBACK_TAB := 2  # video output, VR subtitles
const APPEARANCE_TAB := 3  # background, interface overlays
const ABOUT_TAB := 4
const ABOUT_HOME := 36
var _about_page := 0  # app, credits
## VR subtitle distances (metres); the text keeps its angular size at any distance.
const SubtitleDepth := preload("res://scripts/subtitle_depth.gd")
const AppBackground := preload("res://scripts/app_background.gd")
## Language rows in About: each language named in itself.
const LANGUAGE_NAMES := I18n.NAMES
const PANEL_SIZE := Vector2(1.46, 1.12)
const PANEL_CENTRE := Vector2(.13, 0)
const CAPTURE_ENVELOPE := Rect2(-1.18, -0.82, 2.16, 1.44)
const PANEL_PADDING := .06
const CONTENT_LEFT := PANEL_CENTRE.x - PANEL_SIZE.x * .5 + PANEL_PADDING
const CONTENT_RIGHT := PANEL_CENTRE.x + PANEL_SIZE.x * .5 - PANEL_PADDING
const CONTENT_TOP := PANEL_SIZE.y * .5 - PANEL_PADDING
const CONTENT_BOTTOM := -CONTENT_TOP
const HEADER_Y := CONTENT_TOP - .035
const FOOTER_Y := CONTENT_BOTTOM + .035
const SCROLLBAR_WIDTH := .02
const SCROLLBAR_HIT_WIDTH := .04
const SCROLLBAR_X := CONTENT_RIGHT - SCROLLBAR_WIDTH * .5
const BODY_WIDTH := CONTENT_RIGHT - CONTENT_LEFT - .07
const ROW_CENTRE_X := PANEL_CENTRE.x
const ROW_HEIGHT := .098
const GRID_TOP := HEADER_Y - .035 - .055
const BODY_BOTTOM := FOOTER_Y + .035 + .03
const BODY_HEIGHT := GRID_TOP - BODY_BOTTOM
const VISIBLE_ROWS := 7
const DRAG_START := 0.015  # metres of ray travel on the panel before a press becomes a drag
const STICK_DEADZONE := 0.2
const STICK_SPEED := 1.5  # visible pages per second at full deflection
const LIST_TOP := GRID_TOP - ROW_HEIGHT * .5
const ROW_PITCH := (BODY_HEIGHT - ROW_HEIGHT) / (VISIBLE_ROWS - 1)
const SETTING_ROWS := 8  # settings controls are shorter than media rows, so a page holds one more
const SETTING_PITCH := (BODY_HEIGHT - ROW_HEIGHT) / (SETTING_ROWS - 1)
const FIELDS := ["name", "host", "user", "password"]
const FIELD_NAMES := ["Name", "Address", "User", "Password"]
const KEYS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "."],
	["z", "x", "c", "v", "b", "n", "m", "-", "_", "@"]
]
const SYMBOLS := [
	["!", "#", "$", "%", "&", "*", "(", ")", "+", "="],
	["/", "\\", ":", ";", "'", '"', ",", "?", "~", "|"],
	["[", "]", "{", "}", "<", ">", "^", "`", ".", "@"],
	["-", "_", "0", "1", "2", "3", "4", "5", "6", "7"]
]

# Targets (ray_menu reserves negatives).
const PLAYER := -5
const RECENTER := -6
const NAV_BASE := 10
const TAB_BASE := 20
const BACK := 30
const ADD := 31
const REFRESH := 32
const EDIT := 33
const SAVE := 40
const CANCEL := 41
const DELETE := 42
const SHIFT := 43
const BACKSPACE := 44
const SPACE := 45
const SYMBOL_LAYER := 46
const GRANT := 47
const CLEAR_HISTORY := 49
const ALL_FILES := 34
const RECENT_PREVIOUS := 84
const RECENT_NEXT := 85
const USB_STORAGE := 86
const EJECT_STORAGE := 87
const SCROLLBAR := 48
const CRUMB_BASE := 50
const MediaFiles := preload("res://scripts/media_files.gd")
## Browsing shows a grid like common VR players (folders and videos as tiles); settings stay a list.
const COLS := 4
const GRID_LINES := 3
const RECENT_PAGE_SIZE := COLS * GRID_LINES
const TILE_SIZE := Vector2(
	(BODY_WIDTH - (COLS - 1) * .03) / COLS, (BODY_HEIGHT - (GRID_LINES - 1) * .02) / GRID_LINES
)
const GRID_PITCH := TILE_SIZE + Vector2(.03, .02)
const GRID_LEFT := ROW_CENTRE_X - BODY_WIDTH * .5 + TILE_SIZE.x * .5
const Thumbnails := preload("res://scripts/thumbnail_cache.gd")
const COVER_BYTES := 2 * 1024 * 1024
const FOLDER := Color(0.98, 0.78, 0.36)
const ROW_BASE := 100
const FIELD_BASE := 200
const KEY_BASE := 300

var catalog: RefCounted  # recent files
var platform: Object  # QuestPlayer singleton or a test double
var local_thumbnails := preload("res://scripts/local_thumbnail_controller.gd").new()
var settings_provider: Callable  # -> current application/display settings

var section := Section.RECENT
var tab := 0
var scroll := 0.0  # first visible line; fractional while moving, settles on a whole line
var _drag := {}  # hand, target, start_y, start_scroll, moved, last, at_us, velocity
var _fling := 0.0  # lines per second left by a released drag
var _stick_ms := -1000  # last thumbstick scroll; the list settles once the stick is released
var _list: Node3D  # drawn rows; moved for fractional scrolling
var _bar_thumb: MeshInstance3D
var focus_index := 0  # Desktop keyboard preview only.
var rows: Array[Dictionary] = []
var status := ""  # English; shown through I18n
var _recent_page := 0
var _recent_count := 0
var _recent_all_rows: Array[Dictionary] = []
var editor: Dictionary = {}  # SMB or DLNA server; empty when not editing
var _field := 1
var _shift := false
var _symbols := false
var _side: Node3D  # navigation column, angled towards the viewer
var _drawn_navigation_key := ""
var _covers := {}  # DLNA cover URL -> HTTPRequest while it downloads


func dismiss() -> void:
	local_thumbnails.cancel(self)
	diagnostic_confirmation = false
	subtitle_picker.close()
	remember_browse()
	browse_memory.flush()
	file_actions.reset()
	choices.reset()
	if account_panel.active():
		account_panel.close()
	_drag.clear()
	_fling = 0.0
	server_browser.cancel()
	super()


## The quick video switcher leaves the clock to the control bar below it; its session
## toggles sit at the right of the panel's own footer row so nothing overlaps the bar.
func refresh_session_controls(force: bool = false) -> void:
	var switcher := compact and playback_browser
	if switcher:
		var count := 2 if _session_controls().get("passthrough_visible", false) else 1
		var span := count * FOOTER_DIAMETER + (count - 1) * FOOTER_GAP
		var width := span + FOOTER_GAP + STATUS_WIDTH
		_footer_centre = Vector2(CONTENT_RIGHT - 0.02 - span + width * 0.5, FOOTER_Y)
	super(force)
	if is_instance_valid(device_status):
		device_status.visible = not switcher


func _ready() -> void:
	browse_memory.load_file()
	super()
	allow_user_dismiss = false
	curve_radius = 1.6
	choices.changed.connect(func(key, value): setting_changed.emit(key, value))
	choices.previewed.connect(func(key, value): setting_previewed.emit(key, value))
	_side = Node3D.new()
	_side.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(24)), Vector3(-0.84, 0, 0.1))
	add_child(_side)
	if platform and platform.has_signal("media_list"):
		platform.connect("media_list", _on_media_list)


func attach_platform(value: Object) -> void:
	platform = value
	update_check.attach(value)
	file_actions.sync_platform()
	if (
		platform
		and platform.has_signal("media_list")
		and not platform.is_connected("media_list", _on_media_list)
	):
		platform.connect("media_list", _on_media_list)
	if (
		platform
		and platform.has_signal("android_lifecycle")
		and not platform.is_connected("android_lifecycle", _on_android_lifecycle)
	):
		platform.connect("android_lifecycle", _on_android_lifecycle)
	_cache_revision += 1
	_cache_usage = null
	_request_cache_usage()


func capture_envelope() -> Rect2:
	# Browsing and ordinary settings share a projection from the first frame.
	return CAPTURE_ENVELOPE


func presentation_page() -> Variant:
	return [
		section,
		tab,
		compact,
		subtitle_picker.active,
		account_panel.active(),
		_about_page,
		choices.opened,
		network.mode,
		I18n.language
	]


func _on_android_lifecycle(state: String) -> void:
	if state == "resume" and sources.local_grant_pending:
		sources.local_grant_pending = false
		if section == Section.LOCAL and not account_panel.active():
			sources.load_section()
			refresh()
	if account_panel.active():
		account_panel.lifecycle(state)
		return
	if state == "resume" and server_browser.setup:
		server_browser.setup = false
		if section in [Section.MEDIA_SERVER, Section.NETWORK]:
			server_browser.load_servers()
			refresh()


func _reset_navigation() -> void:
	choices.reset()
	_recent_page = 0
	_drag = {}
	_fling = 0.0
	scroll = 0.0
	focus_index = 0


# --- scrolling: ray drag on the list, thumbsticks, fling ------------------------------------------


## Point on the panel plane (local), even outside any button; null when the ray misses the plane.
func _plane_point(origin: Vector3, direction: Vector3) -> Variant:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001:
		return null
	if (
		xr_surface
		and (xr_surface.native_supported or xr_surface.get("scene_curved") == true)
		and (
			xr_surface.active_menu == self
			or (xr_surface.has_method("captures_menu") and xr_surface.captures_menu(self))
		)
	):
		var mapped: Dictionary = xr_surface.map_ray(self, origin, direction)
		return to_local(mapped.get("canvas_point", mapped.point)) if not mapped.is_empty() else null
	var inverse := global_transform.affine_inverse()
	var start := inverse * origin
	var delta := inverse.basis * direction.normalized()
	if delta.z >= -0.00001 or start.z <= 0.0:
		return null
	return start + delta * (-start.z / delta.z)


func has_pointer_capture() -> bool:
	return not _drag.is_empty() or not choices.capture.is_empty()


func _row_target(target: int) -> bool:
	return target >= ROW_BASE and target < ROW_BASE + _drawn_slots()


## The list area, gaps between tiles included: a press there can drag the list.
func _in_list(point: Vector3) -> bool:
	var span := _bar_span()
	return (
		file_actions.modal.is_empty()
		and editor.is_empty()
		and not rows.is_empty()
		and point.x > CONTENT_LEFT
		and point.x < CONTENT_RIGHT
		and point.y < span.x + 0.01
		and point.y > span.x - span.y - 0.02
	)


func press_pointer(hand: String, origin: Vector3, direction: Vector3, tracked: bool) -> bool:
	if section == Section.SETTINGS and choices.press(hand, origin, direction, tracked):
		_fling = 0.0
		return true
	if not _drag.is_empty() and _drag.hand != hand:
		return true
	update_pointer(hand, origin, direction, tracked)
	var hit := ray_hit(origin, direction) if tracked else {}
	var target := int(hit.get("target", NONE))
	var start_y := 0.0
	if not hit.is_empty() and target != SCROLLBAR and not _row_target(target):
		_activate_hit(hit)
		return true
	if hit.is_empty():
		var point: Variant = _plane_point(origin, direction) if tracked else null
		if point == null or not _in_list(point):
			return false
		start_y = float(point.y)
	else:
		start_y = float(hit.point.y)
	# Rows, gaps and the scrollbar wait for release: a press that moves becomes a scroll.
	_fling = 0.0
	_drag = {
		"hand": hand,
		"target": target,
		"start_y": start_y,
		"start_scroll": scroll,
		"moved": false,
		"last": scroll,
		"at_us": Time.get_ticks_usec(),
		"velocity": 0.0
	}
	if target == SCROLLBAR:
		_scroll_to_bar(start_y)
		_drag.moved = true
	return true


func cancel_pointer(hand: String) -> void:
	choices.cancel(hand)
	if not _drag.is_empty() and _drag.hand == hand:
		_drag = {}
		_fling = 0.0
	super(hand)


func update_pointer(hand: String, origin: Vector3, direction: Vector3, tracked: bool) -> void:
	super(hand, origin, direction, tracked)
	choices.update(hand, origin, direction, tracked)
	if not tracked and not _drag.is_empty() and _drag.hand == hand:
		_drag = {}
		_fling = 0.0
	if _drag.is_empty() or _drag.hand != hand or not tracked:
		return
	var point: Variant = _plane_point(origin, direction)
	if point == null:
		return
	var y := float(point.y)
	if int(_drag.target) == SCROLLBAR:
		_scroll_to_bar(y)
		return
	if not _drag.moved and absf(y - float(_drag.start_y)) < DRAG_START:
		return
	_drag.moved = true
	# Content follows the ray: moving the ray up shows later rows.
	_set_scroll(float(_drag.start_scroll) + (y - float(_drag.start_y)) / _pitch())
	var now := Time.get_ticks_usec()
	var seconds := (now - int(_drag.at_us)) / 1000000.0
	if seconds > 0.004:
		_drag.velocity = lerpf(float(_drag.velocity), (scroll - float(_drag.last)) / seconds, 0.5)
		_drag.last = scroll
		_drag.at_us = now


func release_pointer(hand: String, origin: Vector3, direction: Vector3, tracked: bool) -> void:
	if choices.capture.get("hand", "") == hand:
		choices.release(hand, origin, direction, tracked)
		return
	if _drag.is_empty() or _drag.hand != hand:
		return
	var drag := _drag
	_drag = {}
	if drag.moved:
		# A quick flick keeps the list moving; a drag that stopped before release does not.
		var still := Time.get_ticks_usec() - int(drag.at_us) > 80000
		_fling = (
			0.0
			if still or absf(float(drag.velocity)) < 1.5
			else clampf(float(drag.velocity), -20.0, 20.0)
		)
		return
	if not tracked or int(drag.target) == NONE:
		return
	var hit := ray_hit(origin, direction)
	if not hit.is_empty() and int(hit.target) == int(drag.target):
		_activate_hit(hit)


## Thumbstick y (up positive) scrolls the list; it never selects.
func stick_scroll(y: float, delta: float) -> void:
	if not choices.capture.is_empty():
		return
	if not file_actions.modal.is_empty():
		return
	if section == Section.SETTINGS and choices.stick_scroll(y, delta):
		return
	if (
		not visible
		or not _drag.is_empty()
		or not editor.is_empty()
		or not is_finite(y)
		or absf(y) < STICK_DEADZONE
	):
		return
	_stick_ms = Time.get_ticks_msec()
	_fling = 0.0
	var amount := pow((absf(y) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.6)
	_set_scroll(scroll - signf(y) * amount * _lines() * STICK_SPEED * delta)


func _process(delta: float) -> void:
	local_thumbnails.tick(self)
	if visible:
		remember_browse()
	browse_memory.tick()
	_poll_cache_usage()
	if not file_actions.modal.is_empty():
		return
	if visible:
		account_panel.tick(delta)
	if (
		not visible
		or not _drag.is_empty()
		or not choices.capture.is_empty()
		or Time.get_ticks_msec() - _stick_ms < 120
	):
		return
	if absf(_fling) > 0.4:
		var before := scroll
		_set_scroll(scroll + _fling * delta)
		_fling = 0.0 if scroll == before else _fling * exp(-4.0 * delta)
		return
	_fling = 0.0
	# At rest the list sits on a whole line.
	var line := roundf(scroll)
	if scroll != line:
		_set_scroll(move_toward(scroll, line, delta * 5.0))


func _set_scroll(value: float) -> void:
	var clamped := clampf(value, 0.0, _max_scroll())
	if clamped == scroll:
		if section == Section.MEDIA_SERVER:
			server_browser.scroll_changed()
		return
	var redraw := floori(clamped + 0.001) != _first_line()
	scroll = clamped
	if redraw and _can_redraw_list():
		_redraw_list()
	elif redraw:
		_draw()
	else:
		_place_list()
	if section == Section.MEDIA_SERVER:
		server_browser.scroll_changed()


func _scroll_to_bar(y: float) -> void:
	var span := _bar_span()
	_set_scroll((span.x - y) / span.y * (_max_scroll() + 1.0) - 0.5)


func _can_redraw_list() -> bool:
	return (
		is_instance_valid(_list)
		and choices.opened.is_empty()
		and not subtitle_picker.active
		and file_actions.modal.is_empty()
		and section != Section.MEDIA_SERVER
	)


## Crossing a line redraws only the rows and scrollbar. A full redraw would also rebuild the
## tabs, header and footer, hide the pointer reticle and invalidate the XR layer every line,
## which flashes long lists such as the credits while they scroll.
func _redraw_list() -> void:
	var stale: Array[Node] = [_list]
	if is_instance_valid(_bar_thumb):
		stale.append(_bar_thumb)
	for index in range(_buttons.size() - 1, -1, -1):
		var button: Dictionary = _buttons[index]
		if button.target != SCROLLBAR and not _list.is_ancestor_of(button.node):
			continue
		if button.target == SCROLLBAR:
			stale.append(button.node)
		_tips.erase(button.target)
		_buttons.remove_at(index)
	_decorations = _decorations.filter(func(node): return node not in stale)
	for node in stale:
		node.free()
	_draw_rows()
	_update_highlights()


## First drawn line (float noise from dragging cannot drop a line).
func _first_line() -> int:
	return floori(scroll + 0.001)


## Drawn rows: the visible lines plus one, which shows while the list is between lines.
func _drawn_slots() -> int:
	return _cols() * (_lines() + 1)


## Shift the drawn rows by the fractional scroll; rows past the edges of the list hide.
func _place_list() -> void:
	if not is_instance_valid(_list):
		return
	var fraction := scroll - _first_line()
	_list.position.y = fraction * _pitch()
	for button in _buttons:
		if _row_target(button.target):
			var line := float((button.target - ROW_BASE) / _cols()) - fraction
			button["layout_visible"] = line > -0.35 and line < _lines() - 0.65
			button.node.visible = (
				button.layout_visible and (button.enabled or button.get("keep_visible", false))
			)
	if is_instance_valid(_bar_thumb):
		var span := _bar_span()
		var thumb: float = _bar_thumb.mesh.size.y
		var travel := (span.y - thumb) * (scroll / _max_scroll() if _max_scroll() > 0 else 0.0)
		_bar_thumb.position.y = span.x - travel - thumb * 0.5


func _grid() -> bool:
	if diagnostic_confirmation:
		return false
	if subtitle_picker.active:
		return false
	if account_panel.active():
		return false
	if section == Section.NETWORK:
		return false
	if section == Section.MEDIA_SERVER:
		return server_browser.grid() and not list_view
	return section != Section.SETTINGS and not list_view


func _cols() -> int:
	return COLS if _grid() else 1


## Visible lines (tile rows or list rows); [scroll] counts lines.
func _lines() -> int:
	if subtitle_picker.active:
		return 4
	if account_panel.active():
		return VISIBLE_ROWS
	if section == Section.MEDIA_SERVER:
		return server_browser.visible_lines()
	if section == Section.SETTINGS:
		return SETTING_ROWS
	return GRID_LINES if _grid() else VISIBLE_ROWS


func _pitch() -> float:
	if subtitle_picker.active:
		return ROW_PITCH
	if account_panel.active():
		return ROW_PITCH
	if section == Section.MEDIA_SERVER:
		return server_browser.pitch()
	if section == Section.SETTINGS:
		return SETTING_PITCH
	return GRID_PITCH.y if _grid() else ROW_PITCH


func _line_count() -> int:
	return ceili(float(rows.size()) / _cols())


## Scrollbar track: top and height.
func _bar_span() -> Vector2:
	if section == Section.MEDIA_SERVER and not account_panel.active():
		return server_browser.bar_span()
	return Vector2(GRID_TOP, BODY_HEIGHT)


func _max_scroll() -> float:
	return float(maxi(0, _line_count() - _lines()))


func refresh() -> void:
	var scope := directory_scope()
	if scope != _browse_scope:
		_browse_scope = scope
		_browse_restore = browse_memory.lookup(scope)
		if (
			not _browse_restore.is_empty()
			and file_actions.sortable()
			and not file_actions.orders.has(file_actions.scope())
		):
			file_actions.orders[file_actions.scope()] = _browse_restore.get("order", "name_asc")
	_rebuild_rows()
	_restore_browse()
	_draw()
	_update_highlights()


# --- requests -------------------------------------------------------------------------------


func _on_media_list(id: int, payload: String) -> void:
	if subtitle_picker.receive(id, payload):
		return
	sources.receive(id, payload)


func _grant_local_access() -> void:
	if sources.local_grant_pending:
		return
	if not PlatformMethods.supports(platform, "media_local_grant_all_files"):
		status = "Permission settings unavailable"
	else:
		sources.local_grant_pending = true
		status = "Loading…"
		platform.media_local_grant_all_files()
	refresh()


func _quick_usb_storage() -> void:
	file_actions.reset()
	var external := sources.external_volumes()
	if external.is_empty():
		return
	sources.local_stack.clear()
	sources.local_entries = []
	scroll = 0
	if external.size() == 1:
		sources.local_stack.append(external[0].duplicate(true))
	sources.load_section()
	refresh()


func _eject_volume() -> Dictionary:
	if not sources.local_stack.is_empty():
		return (
			sources.local_stack[0] if bool(sources.local_stack[0].get("removable", false)) else {}
		)
	var external := sources.external_volumes()
	return external[0] if external.size() == 1 else {}


func _request_storage_eject() -> void:
	var volume := _eject_volume()
	if volume.is_empty() or not sources.local_eject_pending.is_empty():
		return
	sources.local_eject_pending = str(volume.id)
	storage_eject_requested.emit(volume.duplicate(true))


func finish_storage_release(path: String) -> void:
	if path != sources.local_eject_pending:
		return
	sources.local_eject_pending = ""
	sources.local_release_notice = true
	if not sources.local_stack.is_empty() and str(sources.local_stack[0].id) == path:
		sources.local_stack.clear()
		sources.local_entries = []
		scroll = 0
	if section == Section.LOCAL:
		sources.load_section()
	refresh()


# --- rows -----------------------------------------------------------------------------------


func _rebuild_rows() -> void:
	rows.clear()
	if diagnostic_confirmation:
		rows.assign(
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
	if subtitle_picker.active:
		rows.assign(subtitle_picker.rows())
		scroll = clampf(scroll, 0, _max_scroll())
		return
	if account_panel.active():
		rows.assign(account_panel.rows())
		scroll = clampf(scroll, 0.0, _max_scroll())
		return
	match section:
		Section.NETWORK:
			rows.assign(network.rows())
		Section.RECENT:
			for entry in catalog.list_recent() if catalog else []:
				var seconds := int(entry.position_ms) / 1000
				rows.append(
					{
						"title": str(entry.title),
						"detail": "%02d:%02d" % [seconds / 60, seconds % 60] if seconds > 0 else "",
						"kind": "video",
						"icon": "video",
						"uri": str(entry.uri)
					}
				)
				if not str(entry.get("cover", "")).is_empty():
					rows.back()["cover"] = entry.cover
				_add_progress(rows.back(), entry)
		Section.LOCAL:
			for entry in sources.local_entries:
				var row := _entry_row(entry)
				if bool(entry.get("volume", false)):
					row.icon = "usb" if bool(entry.get("removable", false)) else "device"
				rows.append(row)
		Section.SMB:
			if sources.smb_server.is_empty():
				for server in sources.smb_servers:
					rows.append(
						{
							"title": str(server.name),
							"detail": str(server.host),
							"icon": "server",
							"smb_server": str(server.id)
						}
					)
				for found in sources.smb_found:
					if sources.smb_servers.any(func(s): return str(s.host) == str(found.host)):
						continue
					rows.append(
						{
							"title": str(found.name),
							"detail": str(found.host),
							"icon": "plus",
							"smb_found": found
						}
					)
			else:
				for entry in sources.smb_entries:
					rows.append(_entry_row(entry))
		Section.DLNA:
			if sources.dlna_server.is_empty():
				for server in sources.dlna_servers:
					rows.append(
						{
							"title": str(server.name),
							"detail": "",
							"icon": "cast",
							"dlna_server": str(server.id)
						}
					)
			else:
				for entry in sources.dlna_entries:
					rows.append(_entry_row(entry))
		Section.SETTINGS:
			rows.assign(_settings_rows())
	if section == Section.MEDIA_SERVER:
		rows = server_browser.rows()
	rows.assign(
		rows.filter(
			func(row):
				return (
					not row.has("uri")
					or MediaFiles.is_video(
						str(row.uri), str(row.get("title", "")), str(row.get("kind", "video"))
					)
				),
		)
	)
	for row in rows:
		if row.has("uri"):
			var parts: Array[String] = []
			if int(row.get("size", -1)) > 0:
				parts.append(_size(row))
			if int(row.get("modified", 0)) > 0:
				parts.append(Time.get_date_string_from_unix_time(int(row.modified) / 1000))
			var recent: Dictionary = (
				catalog.lookup(str(row.uri)) if catalog and catalog.has_method("lookup") else {}
			)
			if int(recent.get("position_ms", 0)) > 0:
				var seconds := int(recent.position_ms) / 1000
				parts.append("%02d:%02d" % [seconds / 60, seconds % 60])
				_add_progress(row, recent)
			if not parts.is_empty():
				row.detail = " · ".join(parts)
	file_actions.sort_rows()
	if section == Section.RECENT:
		_recent_all_rows.assign(rows)
		_recent_count = rows.size()
		_recent_page = clampi(_recent_page, 0, _recent_page_count() - 1)
		rows.assign(
			_recent_all_rows.slice(
				_recent_page * RECENT_PAGE_SIZE, (_recent_page + 1) * RECENT_PAGE_SIZE
			)
		)
	focus_index = clampi(focus_index, 0, maxi(0, rows.size() - 1))
	scroll = clampf(scroll, 0.0, _max_scroll())


## Rows of the open settings page: group headings followed by their controls.
func _settings_rows() -> Array[Dictionary]:
	var settings: Dictionary = settings_provider.call() if settings_provider.is_valid() else {}
	var out: Array[Dictionary] = []
	match tab:
		GENERAL_TAB:
			out.append(_group("Language & controls"))
			var languages: Array = []
			for value in I18n.CHOICES:
				languages.append({"value": value, "label": LANGUAGE_NAMES[value]})
			out.append(_choice_row("Language", "language", I18n.choice, languages))
			out.append(
				_choice_row(
					"Pinch/menu hand",
					"pinch_hand",
					str(settings.get("pinch_hand", "right_hand")),
					[
						{"value": "left_hand", "label": "Left hand"},
						{"value": "right_hand", "label": "Right hand"},
						{"value": "both", "label": "Both hands"}
					],
					true
				)
			)
			out.append(_group("Library"))
			out.append(_switch_row("Allow file management", "file_editing", file_actions.enabled))
			out.append(_switch_row("Save play history", "history", settings.get("history", true)))
			out.append(
				_switch_row(
					"Remember folder position", "browse_memory", settings.get("browse_memory", true)
				)
			)
			out.append(_cache_row())
		DISPLAY_TAB:
			out.append(_group("Picture"))
			var quality_choices: Array = [{"value": Quality.AUTO, "label": "Auto"}]
			for i in Quality.SCALES.size():
				quality_choices.append({"value": i, "label": Quality.NAMES[i]})
			out.append(
				_choice_row(
					"Display quality",
					"display_quality",
					int(settings.get("display_quality", Quality.DEFAULT)),
					quality_choices,
					false,
					"Restart to apply" if settings.get("display_quality_pending", false) else ""
				)
			)
			var rate_choices: Array = []
			for rate in settings.get("refresh_rates", []):
				rate_choices.append({"value": rate, "label": str(rate) + " Hz"})
			if not rate_choices.is_empty():
				out.append(
					_choice_row(
						"Refresh rate",
						"refresh_rate",
						float(settings.get("refresh_rate", 72.0)),
						rate_choices,
						rate_choices.size() <= 4
					)
				)
			var sharpness_choices: Array = []
			for i in Quality.SHARPNESS.size():
				sharpness_choices.append(
					{"value": Quality.SHARPNESS[i], "label": Quality.SHARPNESS_NAMES[i]}
				)
			out.append(
				_choice_row(
					"Sharpness",
					"sharpness",
					float(settings.get("sharpness", Quality.DEFAULT_SHARPNESS)),
					sharpness_choices,
					true
				)
			)
			out.append(_group("Window"))
			out.append(
				{
					"title": I18n.t("Window height"),
					"key": "window_height",
					"value": settings.get("window_height", -12.0),
					"slider": true,
					"span": Vector3(-60, 30, 1),
					"unit": "cm",
					"signed": true,
					"reset_value": -12.0
				}
			)
			out.append(
				_switch_row(
					"Reclining mode",
					"reclining_mode",
					settings.get("reclining_mode", false),
					"Allow tilted screens and menus"
				)
			)
		PLAYBACK_TAB:
			out.append(_group("Video"))
			out.append(
				_choice_row(
					"Resolution",
					"output_width",
					int(settings.get("output_width", Quality.AUTO_OUTPUT)),
					[
						{"value": Quality.AUTO_OUTPUT, "label": "Auto"},
						{"value": 0, "label": "Original size"},
						{"value": 5760, "label": "6K"},
						{"value": 4096, "label": "4K"}
					],
					true
				)
			)
			out.append(
				_switch_row(
					"Reuse last video mode",
					"reuse_last_mode",
					bool(settings.get("reuse_last_mode", false))
				)
			)
			out.append(_group("VR subtitles"))
			out.append_array(_subtitle_rows(settings))
		APPEARANCE_TAB:
			out.append(_group("Background"))
			var selected := str(settings.get("background", AppBackground.DEFAULT_CHOICE))
			out.append(
				_choice_row(
					"Background",
					"background",
					selected,
					[
						{"value": "starry_night", "label": "Starry night"},
						{"value": "belfast", "label": "Sunset"},
						{"value": "beach", "label": "Beach"},
						{"value": "cloud_sea", "label": "Sea of clouds"},
						{"value": "dark", "label": "Dark background"},
						{"value": "passthrough", "label": "Passthrough"}
					]
				)
			)
			if AppBackground.is_scenery(selected):
				var directions: Array = []
				for angle in range(0, 360, 45):
					directions.append({"value": angle, "label": str(angle) + "°"})
				out.append(
					_choice_row(
						"Direction",
						"background_yaw",
						int(settings.get("background_yaw", 0)),
						directions
					)
				)
				out.append(
					_choice_row(
						"Brightness",
						"background_brightness",
						float(settings.get("background_brightness", 1.0)),
						[
							{"value": 0.5, "label": "50%"},
							{"value": 0.75, "label": "75%"},
							{"value": 1.0, "label": "100%"},
							{"value": 1.25, "label": "125%"}
						],
						true
					)
				)
			out.append(_group("Interface"))
			out.append(
				{
					"title": I18n.t("Control bar opacity"),
					"key": "controls_opacity",
					"value": settings.get("controls_opacity", 0.86),
					"slider": true,
					"span": Vector3(0, 1, 0.05),
					"unit": "",
					"reset_value": 0.86
				}
			)
			out.append(_switch_row("Show FPS", "show_fps", bool(settings.get("show_fps", false))))
			status = (
				"Loading…"
				if settings.get("background_loading", false)
				else str(settings.get("background_error", ""))
			)
		ABOUT_TAB:
			out.append_array(_about_rows(settings))
	return out


## Subtitle placement shared by every VR video: distance, then direction, then position.
func _subtitle_rows(settings: Dictionary) -> Array[Dictionary]:
	var vertical := int(settings.get("subtitle_direction", 0)) == 1
	var distance := SubtitleDepth.slider_row(
		"subtitle_distance", float(settings.get("subtitle_distance", SubtitleDepth.DEFAULT))
	)
	distance.title = I18n.t("Subtitle distance")
	var direction := SubtitleDepth.direction_row(int(settings.get("subtitle_direction", 0)))
	direction.title = I18n.t("Subtitle direction")
	var position := SubtitleDepth.slider_row(
		"subtitle_position",
		float(settings.get("subtitle_position", SubtitleDepth.DEFAULT_POSITION))
	)
	position.title = I18n.t("Horizontal position" if vertical else "Subtitle position")
	return [distance, direction, position]


## Everything the app ships, grouped by role: [heading, [[name, license · authors], ...]].
## Native libraries are those statically linked into the bundled mpv-android build.
const CREDITS := [
	[
		"Engine & XR",
		[
			["Godot Engine 4.7.2", "MIT"],
			["Godot OpenXR Vendors 5.1.0", "MIT · vendor license notices"],
			["Khronos OpenXR Loader 1.1.54", "Apache-2.0"],
			["Godot OpenXR hand demo assets", "MIT"],
		]
	],
	[
		"Playback & decoding",
		[
			["mpv (mpv-android 2026-09-17)", "GPL-2.0-or-later"],
			["FFmpeg", "GPL-3.0-or-later"],
			["libplacebo", "LGPL-2.1-or-later"],
			["shaderc · glslang · SPIRV-Tools", "Apache-2.0 · BSD-3-Clause"],
			["dav1d", "BSD-2-Clause"],
		]
	],
	[
		"Subtitles & text",
		[
			["libass", "ISC"],
			["FreeType", "FreeType License"],
			["HarfBuzz", "MIT"],
			["GNU FriBidi", "LGPL-2.1-or-later"],
			["libunibreak", "zlib"],
			["ICU4J charset detector 79.1", "Unicode-3.0"],
		]
	],
	[
		"Network & storage",
		[
			["CodeLibs JCIFS 3.0.4", "LGPL-2.1"],
			["Bouncy Castle 1.85", "MIT"],
			["SLF4J API 1.7.36", "MIT"],
			["Mbed TLS 3.6.7", "Apache-2.0"],
			["libxml2", "MIT"],
		]
	],
	[
		"Runtime",
		[
			["Lua 5.2", "MIT"],
			["Kotlin standard library 2.4.21", "Apache-2.0"],
			["kotlinx.coroutines 1.6.4", "Apache-2.0"],
			["AndroidX Activity · Core · Fragment · Lifecycle", "Apache-2.0"],
			["Guava 33.3.1", "Apache-2.0"],
			["JSpecify 1.0.0 · JetBrains annotations 13.0", "Apache-2.0"],
		]
	],
	[
		"Background panorama",
		[
			[
				"Belfast Sunset (Pure Sky)",
				"Poly Haven · CC0 1.0 · Dimitrios Savva / Greg Zaal / Jarod Guest"
			],
			["Blouberg Sunrise 2", "Poly Haven · CC0 1.0 · Greg Zaal"],
		]
	],
]


func _about_rows(settings: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _about_page == 3:
		var licenses: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://i18n/licenses.json")
		)
		if licenses is Array:
			for license in licenses:
				out.append(
					{
						"title": str(license.name),
						"detail": str(license.license),
						"icon": "info",
						"license_id": str(license.id)
					}
				)
	elif _about_page == 2:
		for group in CREDITS:
			out.append(_group(group[0]))
			for credit in group[1]:
				out.append(_about_info(str(credit[0]), str(credit[1])))
	else:
		out.append(_about_info("Immivio", str(settings.get("version", ""))))
		out.append_array(update_check.rows())
		out.append(
			_about_info(I18n.t("Official website"), "https://northboundwisdom.github.io/immivio/")
		)
		out.append(
			_about_info(I18n.t("Source code"), "https://github.com/NorthBoundWisdom/immivio")
		)
		out.append({"title": I18n.t("Credits"), "icon": "info", "about_page": 2})
		out.append({"title": I18n.t("Open source licenses"), "icon": "info", "open_licenses": true})
		out.append(
			{
				"title": I18n.t("Save diagnostic log"),
				"icon": "info",
				"save_diagnostic_log": true,
				"detail":
				(
					I18n.t("Previous session log available")
					if settings.get("diagnostic_previous", false)
					else ""
				)
			}
		)
	return out


## Thumbnails and fetched film covers; the size shows under the title, the button arms then clears.
func _cache_row() -> Dictionary:
	if _cache_usage == null:
		_request_cache_usage()
	var cache: Vector2i = _cache_usage if _cache_usage != null else Vector2i.ZERO
	var armed := _confirm == "clear_cache"
	return {
		"title": I18n.t("Clear cache"),
		"detail":
		I18n.t("Loading…") if _cache_usage == null else (_bytes(cache.y) if cache.x > 0 else ""),
		"action": "Confirm clear" if armed else "Clear",
		"icon": "check" if armed else "trash",
		"selected": armed,
		"clear_cache": true,
		"empty": cache.x == 0
	}


## A titled divider that opens a group of settings; it takes one line and is never a target.
func _group(title: String) -> Dictionary:
	return {"title": I18n.t(title), "group": true}


func _switch_row(title: String, key: String, value: Variant, hint: String = "") -> Dictionary:
	return _choice_row(
		title,
		key,
		bool(value),
		[{"value": false, "label": "Off"}, {"value": true, "label": "On"}],
		false,
		hint
	)


## The open local folder's path ("" lists the storage volumes).
func _entry_row(entry: Dictionary) -> Dictionary:
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
		"detail": _size(entry),
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


func video_queue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = (
		server_browser.entries
		if section == Section.MEDIA_SERVER
		else (
			_recent_all_rows
			if section == Section.RECENT and not _recent_all_rows.is_empty()
			else rows
		)
	)
	for row in source:
		var uri := str(row.get("uri", ""))
		var title := str(row.get("title", ""))
		if uri.is_empty() or not MediaFiles.is_video(uri, title, str(row.get("kind", "video"))):
			continue
		if row.get("container", false) or row.has("folder"):
			continue
		result.append({"uri": uri, "title": title, "metadata": row.duplicate(true)})
	return result


static func _leaf(path: String) -> String:
	var parts := path.trim_suffix("/").split("/")
	return parts[parts.size() - 1] if parts.size() > 0 else path


static func _bytes(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(1, bytes / 1024)


static func _size(entry: Dictionary) -> String:
	var bytes := float(entry.get("size", 0))
	if bytes <= 0:
		return ""
	return (
		"%.1f GB" % (bytes / 1073741824.0)
		if bytes >= 1073741824.0
		else "%d MB" % int(bytes / 1048576.0)
	)


# --- activation -----------------------------------------------------------------------------

var _confirm := ""
var _cache_usage: Variant = null
var _cache_thread: Thread
var _cache_revision := 0
var _cache_job_revision := 0
var _cache_due_ms := 0
var _cache_redraw_pending := false


static func _scan_cache_usage() -> Vector2i:
	return Thumbnails.usage()


func _request_cache_usage() -> void:
	if _cache_thread:
		return
	_cache_job_revision = _cache_revision
	_cache_thread = Thread.new()
	if _cache_thread.start(_scan_cache_usage) != OK:
		_cache_thread = null
		_cache_usage = Vector2i.ZERO


func _poll_cache_usage() -> void:
	if _cache_thread and not _cache_thread.is_alive():
		var usage: Vector2i = _cache_thread.wait_to_finish()
		_cache_thread = null
		if _cache_job_revision == _cache_revision:
			_cache_usage = usage
			_cache_due_ms = Time.get_ticks_msec() + 10000
			_cache_redraw_pending = true
		else:
			_request_cache_usage()
	if (
		_cache_redraw_pending
		and visible
		and section == Section.SETTINGS
		and tab == GENERAL_TAB
		and not has_pointer_capture()
	):
		_cache_redraw_pending = false
		refresh()


func _exit_tree() -> void:
	local_thumbnails.cancel(self)
	browse_memory.flush()
	if _cache_thread:
		_cache_thread.wait_to_finish()
		_cache_thread = null


func _activate(target: int) -> void:
	if (
		target == ABOUT_HOME
		or (target >= NAV_BASE and target < NAV_BASE + NAV.size())
		or (target >= TAB_BASE and target < TAB_BASE + SETTING_TABS.size())
	):
		diagnostic_confirmation = false
	if subtitle_picker.active:
		subtitle_picker.action(target)
		return
	remember_browse()
	if target == VIEW_MODE:
		var index := _first_line() * _cols()
		list_view = not list_view
		scroll = float(index / _cols())
		setting_changed.emit("library_list_view", list_view)
		refresh()
		return
	if target in [CLOSE, PLAYER]:
		if playback_browser:
			dismiss()
			player_requested.emit()
		return
	if target == QUEUE_ADD_LIST:
		queue_requested.emit("queue_add_list")
		return
	if target == QUEUE_DONE:
		queue_requested.emit("queue_done")
		return
	if _activate_footer(target):
		return
	if file_actions.action(target):
		return
	if choices.action(target):
		return
	if account_panel.action(target):
		return
	if network.action(target):
		return
	if section == Section.MEDIA_SERVER and server_browser.action(target):
		return
	if not _row_target(target) and target != CLEAR_HISTORY:
		_confirm = ""
	if target == CLOSE:
		dismiss()
	elif target == PLAYER:
		dismiss()
		player_requested.emit()
	elif target == RECENTER:
		recenter_requested.emit()
	elif target >= NAV_BASE and target < NAV_BASE + NAV.size():
		if target == NAV_BASE + Section.NETWORK:
			network.open()
			return
		file_actions.reset()
		account_panel.close()
		server_browser.cancel()
		section = target - NAV_BASE
		tab = GENERAL_TAB if section == Section.SETTINGS else 0
		scroll = 0.0
		status = ""
		editor = {}
		if section == Section.SETTINGS and Time.get_ticks_msec() >= _cache_due_ms:
			_request_cache_usage()
		sources.load_section()
		refresh()
	elif target >= TAB_BASE and target < TAB_BASE + SETTING_TABS.size():
		tab = target - TAB_BASE
		scroll = 0.0
		sources.load_section()
		refresh()
	elif target == BACK:
		_go_back()
	elif target == ABOUT_HOME:
		_about_page = 0
		scroll = 0.0
		refresh()
	elif target == REFRESH:
		_refresh_source()
	elif target == RECENT_PREVIOUS:
		_turn_recent_page(-1)
	elif target == RECENT_NEXT:
		_turn_recent_page(1)
	elif target == ADD:
		_open_editor({})
	elif target == EDIT:
		var current: Array = (
			sources.dlna_servers.filter(func(s): return str(s.id) == sources.dlna_server)
			if section == Section.DLNA
			else sources.smb_servers.filter(func(s): return str(s.id) == sources.smb_server)
		)
		_open_editor(current[0] if current.size() > 0 else {})
	elif target == GRANT:
		_grant_local_access()
	elif target == ALL_FILES:
		_grant_local_access()
	elif target == USB_STORAGE:
		_quick_usb_storage()
	elif target == EJECT_STORAGE:
		_request_storage_eject()
	elif target == CLEAR_HISTORY:
		if _confirm != "clear_history":
			_confirm = "clear_history"
		else:
			_confirm = ""
			setting_changed.emit("clear_history", true)
		refresh()
	elif target >= CRUMB_BASE and target < CRUMB_BASE + 10:
		_go_to(target - CRUMB_BASE)
	elif _row_target(target):
		var index := _first_line() * _cols() + target - ROW_BASE
		if index < rows.size():
			_choose(rows[index])
	elif not editor.is_empty():
		_editor_input(target)


func _choose(row: Dictionary) -> void:
	if (
		row.has("uri")
		and not MediaFiles.is_video(
			str(row.uri), str(row.get("title", "")), str(row.get("kind", "video"))
		)
	):
		return
	if row.get("check_updates", false):
		update_check.request()
		return
	if row.get("open_update_release", false):
		update_check.open_release()
		return
	if subtitle_picker.active:
		subtitle_picker.choose(row)
		return
	remember_browse()
	if file_actions.select(row):
		return
	if account_panel.choose(row):
		return
	if network.choose(row):
		return
	if row.has("save_diagnostic_log"):
		diagnostic_confirmation = true
		scroll = 0
		refresh()
		return
	if row.has("cancel_diagnostic_save") or row.has("confirm_diagnostic_save"):
		if not diagnostic_confirmation:
			return
		diagnostic_confirmation = false
		if row.has("confirm_diagnostic_save"):
			setting_changed.emit("save_diagnostic_log", true)
		refresh()
		return
	if row.has("open_licenses"):
		_open_licenses()
		return
	if row.has("license_id"):
		var id := str(row.license_id)
		var text := ""
		if id == "godot":
			text = Engine.get_license_text()
		elif id == "godot-third-party":
			text = _engine_notices()
		else:
			text = (
				str(platform.license_text(id))
				if PlatformMethods.supports(platform, "license_text")
				else _desktop_license_text(id)
			)
		account_panel.show_license(
			str(row.title), text if not text.is_empty() else I18n.t("License unavailable")
		)
		return
	if row.has("about_page"):
		_about_page = int(row.about_page)
		scroll = 0.0
		refresh()
		return
	if section == Section.MEDIA_SERVER:
		server_browser.choose(row)
		return
	if row.has("uri") and not str(row.uri).is_empty():
		dismiss()
		chosen.emit(str(row.uri), str(row.title))
	elif row.has("smb_server"):
		sources.smb_server = str(row.smb_server)
		sources.smb_path = ""
		sources.smb_entries = []
		sources.request("smb_browse", platform.media_smb_browse(sources.smb_server, ""))
		scroll = 0.0
		refresh()
	elif row.has("smb_found"):
		_open_editor({"name": str(row.smb_found.name), "host": str(row.smb_found.host)})
	elif row.has("dlna_server"):
		sources.dlna_server = str(row.dlna_server)
		sources.dlna_stack = []
		sources.dlna_entries = []
		sources.request("dlna_browse", platform.media_dlna_browse(sources.dlna_server, "0"))
		scroll = 0.0
		refresh()
	elif row.has("container"):
		var container: Dictionary = row.container
		scroll = 0.0
		if section == Section.LOCAL:
			sources.local_stack.append(container.duplicate(true))
			sources.local_entries = []
			sources.load_section()
		elif section == Section.SMB:
			sources.smb_path = str(container.id)
			sources.smb_entries = []
			sources.request(
				"smb_browse", platform.media_smb_browse(sources.smb_server, sources.smb_path)
			)
		else:
			sources.dlna_stack.append({"id": str(container.id), "title": str(container.title)})
			sources.dlna_entries = []
			sources.request(
				"dlna_browse", platform.media_dlna_browse(sources.dlna_server, str(container.id))
			)
		refresh()
	elif row.has("clear_cache"):
		if bool(row.get("empty", false)):
			return
		if _confirm != "clear_cache":
			_confirm = "clear_cache"
			refresh()
			return
		_confirm = ""
		_cancel_covers()
		local_thumbnails.cancel(self)
		Thumbnails.clear()
		_cache_revision += 1
		_cache_usage = null
		refresh()
	elif row.has("setting"):
		if bool(row.get("cold", false)) and _confirm != str(row.setting[1]):
			_confirm = str(row.setting[1])
			refresh()
			return
		_confirm = ""
		setting_changed.emit(str(row.setting[0]), row.setting[1])
		refresh()


func _go_back() -> void:
	remember_browse()
	file_actions.reset()
	scroll = 0.0
	status = ""
	if not editor.is_empty():
		editor = {}
		if network.mode == "add":
			network.open()
			return
	elif section == Section.LOCAL:
		sources.local_stack.pop_back()
		sources.local_entries = []
		sources.load_section()
	elif section == Section.SMB:
		if sources.smb_path.is_empty():
			network.open()
			return
		else:
			sources.smb_path = (
				sources.smb_path.get_base_dir() if sources.smb_path.contains("/") else ""
			)
			sources.smb_entries = []
			sources.request(
				"smb_browse", platform.media_smb_browse(sources.smb_server, sources.smb_path)
			)
	elif section == Section.DLNA:
		if sources.dlna_stack.is_empty():
			network.open()
			return
		else:
			sources.dlna_stack.pop_back()
			sources.dlna_entries = []
			sources.request(
				"dlna_browse",
				platform.media_dlna_browse(
					sources.dlna_server,
					str(sources.dlna_stack.back().id) if sources.dlna_stack.size() > 0 else "0"
				)
			)
	elif section == Section.MEDIA_SERVER:
		network.open()
		return
	refresh()


## Path segments of the current folder, the server (or library) first.
func _crumbs() -> Array:
	match section:
		Section.LOCAL:
			return (
				[]
				if sources.local_stack.is_empty()
				else (
					[I18n.t(NAV[Section.LOCAL])]
					+ sources.local_stack.map(func(c): return str(c.title))
				)
			)
		Section.SMB:
			if sources.smb_server.is_empty():
				return []
			var names: Array = (
				sources
				. smb_servers
				. filter(func(s): return str(s.id) == sources.smb_server)
				. map(func(s): return str(s.name))
			)
			var parts: Array = [str(names[0]) if names.size() > 0 else "SMB"]
			for part in sources.smb_path.split("/", false):
				parts.append(part)
			return parts
		Section.DLNA:
			if sources.dlna_server.is_empty():
				return []
			var names: Array = (
				sources
				. dlna_servers
				. filter(func(s): return str(s.id) == sources.dlna_server)
				. map(func(s): return str(s.name))
			)
			var parts: Array = [str(names[0]) if names.size() > 0 else "DLNA"]
			for container in sources.dlna_stack:
				parts.append(str(container.title))
			return parts
	return []


## Jump to path segment [level] (0: the server or library root).
func _go_to(level: int) -> void:
	remember_browse()
	file_actions.reset()
	var depth := _crumbs().size() - 1
	if level < 0 or level >= depth:
		return
	scroll = 0.0
	status = ""
	match section:
		Section.LOCAL:
			sources.local_stack.resize(level)
			sources.local_entries = []
			sources.load_section()
		Section.SMB:
			sources.smb_path = "/".join(sources.smb_path.split("/", false).slice(0, level))
			sources.smb_entries = []
			sources.request(
				"smb_browse", platform.media_smb_browse(sources.smb_server, sources.smb_path)
			)
		Section.DLNA:
			sources.dlna_stack.resize(level)
			sources.dlna_entries = []
			sources.request(
				"dlna_browse",
				platform.media_dlna_browse(
					sources.dlna_server,
					str(sources.dlna_stack.back().id) if sources.dlna_stack.size() > 0 else "0"
				)
			)
	refresh()


func _refresh_source() -> void:
	sources.refresh_source()


# --- Network server editor with a ray keyboard --------------------------------------------------


func _open_editor(server: Dictionary) -> void:
	file_actions.reset()
	editor = {
		"id": str(server.get("id", "")),
		"name": str(server.get("name", "")),
		"host": str(server.get("host", "")),
		"user": str(server.get("user", "")),
		"password": "",
		"has_password": bool(server.get("has_password", false))
	}
	if section == Section.DLNA:
		var location := str(server.get("location", ""))
		var authority := (
			location.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0)
			if location.contains("://")
			else location
		)
		var scheme := location.get_slice("://", 0) if location.contains("://") else "http"
		var host := authority.get_slice(":", 0)
		var port := "443" if scheme == "https" else "80"
		if authority.begins_with("["):
			host = authority.get_slice("]", 0).trim_prefix("[")
			if authority.contains("]:"):
				port = authority.get_slice("]:", 1)
		elif authority.contains(":"):
			port = authority.get_slice(":", 1)
		if location.is_empty():
			port = "8200"
		editor = {
			"id": str(server.get("id", "")),
			"location": location,
			"host": host,
			"port": port,
			"initial_host": host,
			"initial_port": port,
			"scheme": scheme
		}
		_field = 0
	else:
		_field = 1 if str(editor.host).is_empty() else 2
	status = ""
	_shift = false
	_symbols = false
	refresh()


func _editor_fields() -> Array:
	return ["host", "port"] if section == Section.DLNA else FIELDS


func _editor_busy() -> bool:
	return sources.pending.has(int(editor.get("request_id", -1)))


func _editor_input(target: int) -> void:
	if _editor_busy() and target != CANCEL:
		return
	var fields := _editor_fields()
	var key: String = fields[_field]
	if target >= FIELD_BASE and target < FIELD_BASE + fields.size():
		_field = target - FIELD_BASE
	elif target >= KEY_BASE and target < KEY_BASE + 40:
		var layer: Array = SYMBOLS if _symbols else KEYS
		var character: String = layer[(target - KEY_BASE) / 10][(target - KEY_BASE) % 10]
		editor[key] = str(editor[key]) + (character.to_upper() if _shift else character)
		_shift = false
	elif target == SHIFT:
		_shift = not _shift
	elif target == SYMBOL_LAYER:
		_symbols = not _symbols
	elif target == SPACE:
		editor[key] = str(editor[key]) + " "
	elif target == BACKSPACE:
		editor[key] = str(editor[key]).left(-1)
	elif target == CANCEL:
		editor = {}
		if network.mode == "add":
			network.open()
			return
	elif target == DELETE and section == Section.DLNA:
		if (
			PlatformMethods.supports(platform, "media_dlna_remove")
			and not str(editor.id).is_empty()
		):
			var id: int = platform.media_dlna_remove(str(editor.id))
			sources.request("dlna_remove", id)
			editor.request_id = id
	elif target == SAVE and section == Section.DLNA:
		if str(editor.host).strip_edges().is_empty() or str(editor.port).strip_edges().is_empty():
			_field = 0 if str(editor.host).strip_edges().is_empty() else 1
		elif PlatformMethods.supports(platform, "media_dlna_save"):
			var request := {
				"id": editor.id, "host": editor.host, "port": editor.port, "scheme": editor.scheme
			}
			if (
				editor.host == editor.initial_host
				and editor.port == editor.initial_port
				and not str(editor.location).is_empty()
			):
				request.location = editor.location
			var id: int = platform.media_dlna_save(JSON.stringify(request))
			sources.request("dlna_save", id)
			editor.request_id = id
			if network.mode == "add":
				network.save_request = id
	elif target == DELETE:
		if platform and not str(editor.id).is_empty():
			sources.request("smb_servers", platform.media_smb_remove(str(editor.id)))
			if sources.smb_server == str(editor.id):
				sources.smb_server = ""
		editor = {}
	elif target == SAVE:
		if str(editor.host).strip_edges().is_empty():
			_field = 1
		elif platform:
			var request := {
				"id": editor.id,
				"name": editor.name,
				"host": editor.host,
				"user": editor.user,
				"password": editor.password
			}
			var id: int = platform.media_smb_save(JSON.stringify(request))
			sources.request("smb_servers", id)
			if network.mode == "add":
				network.save_request = id
			sources.smb_server = ""
			editor = {}
	refresh()


# --- drawing --------------------------------------------------------------------------------


## Keep the navigation's text/material instances alive while only the list scrolls.
func _clear_content_layout(keep_navigation: bool) -> void:
	if not keep_navigation:
		_clear_layout()
		return
	var buttons := _buttons.filter(func(button): return _side.is_ancestor_of(button.node))
	var labels := _labels.filter(func(node): return _side.is_ancestor_of(node))
	var decorations := _decorations.filter(func(node): return _side.is_ancestor_of(node))
	var tips := {}
	var hover := {}
	for button in buttons:
		if _tips.has(button.target):
			tips[button.target] = _tips[button.target]
	for hand in _hover:
		if buttons.any(func(button): return button.target == _hover[hand]):
			hover[hand] = _hover[hand]
	_buttons = _buttons.filter(func(button): return not _side.is_ancestor_of(button.node))
	_labels = _labels.filter(func(node): return not _side.is_ancestor_of(node))
	_decorations = _decorations.filter(func(node): return not _side.is_ancestor_of(node))
	_clear_layout()
	_buttons.append_array(buttons)
	_labels.append_array(labels)
	_decorations.append_array(decorations)
	_tips.merge(tips)
	_hover.merge(hover)


func _draw() -> void:
	var navigation_key := I18n.language + str(playback_browser)
	var keep_navigation := (
		navigation_key == _drawn_navigation_key
		and is_instance_valid(_side)
		and _side.get_child_count() > 0
	)
	_clear_content_layout(keep_navigation)
	_side.visible = false
	if subtitle_picker.active:
		subtitle_picker.draw()
		return
	if not file_actions.modal.is_empty():
		file_actions.draw_modal()
		return
	# Like common VR players: a navigation column angled towards the viewer, the browser beside
	# it, and round actions floating under the browser.
	_set_backdrop(PANEL_SIZE, PANEL_CENTRE)
	_side.visible = true
	if not keep_navigation:
		var column := _quad(Vector2(0.42, 1.12), Vector3.ZERO, PANEL, 10)
		_side.add_child(column)
		_decorations.append(column)
		_draw_brand(column)
		var order := nav_order()
		for position in order.size():
			var i: int = order[position]
			_nav_button(
				NAV_BASE + i,
				I18n.t(NAV[i]),
				NAV_ICONS[i],
				Vector2(0, 0.39 - position * 0.13),
				i == (Section.NETWORK if network.contains(section) else section)
			)
		_drawn_navigation_key = navigation_key
	_update_navigation_selection()
	if account_panel.active():
		account_panel.draw()
		return
	if not editor.is_empty():
		_draw_editor()
		return
	if section not in [Section.SETTINGS, Section.NETWORK] and not file_actions.editing:
		_glyph(
			VIEW_MODE,
			"list" if not list_view else "media_library",
			Vector2(CONTENT_LEFT + .0325, FOOTER_Y),
			0.065,
			true,
			I18n.t("List view" if not list_view else "Icon view")
		)
	if playback_browser and not file_actions.editing:
		_glyph(
			PLAYER,
			"close",
			Vector2(CONTENT_LEFT + .1325, FOOTER_Y),
			0.065,
			true,
			I18n.t("Back to video")
		)
	if section == Section.MEDIA_SERVER:
		server_browser.draw()
		return
	if section == Section.NETWORK:
		network.draw()
		return
	# Right header: sub-tabs at the top level, otherwise a clickable path with back.
	var crumbs := _crumbs()
	if crumbs.is_empty():
		if section in [Section.SMB, Section.DLNA]:
			_button(BACK, "", Vector2(CONTENT_LEFT + .045, HEADER_Y), Vector2(.09, .07), true, "up")
		var tabs: Array = SETTING_TABS if section == Section.SETTINGS else []
		if section == Section.SETTINGS and tab == ABOUT_TAB and _about_page != 0:
			tabs = []
			var page_title := _label(
				I18n.t("Open source licenses" if _about_page == 3 else "Credits"),
				Vector3(PANEL_CENTRE.x, HEADER_Y, .004),
				24
			)
			page_title.font = ui_font_bold()
		var tab_width := (
			(CONTENT_RIGHT - CONTENT_LEFT - maxf(0, tabs.size() - 1) * .015) / maxf(1, tabs.size())
		)
		for i in tabs.size():
			_tab_button(
				TAB_BASE + i,
				I18n.t(tabs[i]),
				Vector2(CONTENT_LEFT + tab_width * .5 + i * (tab_width + .015), HEADER_Y),
				tab_width,
				i == tab
			)
		if section in [Section.RECENT, Section.LOCAL, Section.SMB, Section.DLNA]:
			_heading(I18n.t(NAV[section]), Vector3(CONTENT_LEFT, HEADER_Y, .004))
	else:
		_button(BACK, "", Vector2(CONTENT_LEFT + .045, HEADER_Y), Vector2(0.09, 0.07), true, "up")
		_draw_crumbs(crumbs)
	if section in [Section.LOCAL, Section.SMB, Section.DLNA]:
		_button(
			REFRESH,
			"",
			Vector2(CONTENT_RIGHT - .045, HEADER_Y),
			Vector2(0.09, 0.07),
			platform != null,
			"refresh"
		)
	if section == Section.LOCAL and not sources.local_all_files and platform:
		_button(
			ALL_FILES,
			"",
			Vector2(CONTENT_RIGHT - .155, HEADER_Y),
			Vector2(0.09, 0.07),
			not sources.local_grant_pending,
			"unlock"
		)
		_tips[ALL_FILES] = I18n.t("Allow access to all files")
	if section == Section.LOCAL and not sources.external_volumes().is_empty():
		_button(
			USB_STORAGE,
			"",
			Vector2(CONTENT_RIGHT - .265, HEADER_Y),
			Vector2(0.09, 0.07),
			true,
			"usb"
		)
		_tips[USB_STORAGE] = I18n.t("USB storage")
		if not _eject_volume().is_empty():
			_button(
				EJECT_STORAGE,
				"",
				Vector2(CONTENT_RIGHT - .375, HEADER_Y),
				Vector2(0.09, 0.07),
				sources.local_eject_pending.is_empty(),
				"eject"
			)
			_tips[EJECT_STORAGE] = I18n.t("Stop app access")
	if section == Section.RECENT and not rows.is_empty():
		# Two presses: the first lights the button, the second clears.
		_button(
			CLEAR_HISTORY,
			"",
			Vector2(CONTENT_RIGHT - .045, HEADER_Y),
			Vector2(0.09, 0.07),
			true,
			"check" if _confirm == "clear_history" else "trash",
			_confirm == "clear_history"
		)
		_tips[CLEAR_HISTORY] = I18n.t("Clear history")
	if section == Section.DLNA:
		if sources.dlna_server.is_empty():
			_button(
				ADD,
				"",
				Vector2(CONTENT_RIGHT - .155, HEADER_Y),
				Vector2(0.09, 0.07),
				PlatformMethods.supports(platform, "media_dlna_save"),
				"plus"
			)
			_tips[ADD] = I18n.t("Add server")
		elif sources.dlna_servers.any(
			func(server):
				return str(server.id) == sources.dlna_server and bool(server.get("manual", false))
		):
			_button(
				EDIT, "", Vector2(CONTENT_RIGHT - .155, HEADER_Y), Vector2(0.09, 0.07), true, "edit"
			)
	if section == Section.SMB and sources.smb_server.is_empty():
		_button(
			ADD,
			"",
			Vector2(CONTENT_RIGHT - .155, HEADER_Y),
			Vector2(0.09, 0.07),
			platform != null,
			"plus"
		)
	if section == Section.SMB and not sources.smb_server.is_empty():
		_button(
			EDIT, "", Vector2(CONTENT_RIGHT - .155, HEADER_Y), Vector2(0.09, 0.07), true, "edit"
		)
	file_actions.draw_header()
	_decoration(
		Vector2(CONTENT_RIGHT - CONTENT_LEFT, .002),
		Vector2(PANEL_CENTRE.x, GRID_TOP + .03),
		DIVIDER
	)
	_draw_rows()
	if section == Section.SETTINGS and tab == ABOUT_TAB:
		_draw_about()
	if queue_add_mode:
		_button(
			QUEUE_ADD_LIST,
			I18n.t("Add current list"),
			Vector2(-0.22, 0.57),
			Vector2(0.62, 0.07),
			not video_queue().is_empty()
		)
		_button(QUEUE_DONE, I18n.t("Done adding"), Vector2(0.46, 0.57), Vector2(0.62, 0.07))
	if status in ["Video access needed", "Media access needed", "All files access needed"]:
		_button(
			GRANT,
			I18n.t("Grant"),
			Vector2(0.19, -0.34),
			Vector2(0.3, 0.07),
			not sources.local_grant_pending,
			"",
			true
		)
	if file_actions.editing and not file_actions.uncertain and file_actions.pending <= 0:
		file_actions.draw_footer()
	if section == Section.RECENT:
		_button(RECENT_PREVIOUS, "‹", Vector2(.15, HEADER_Y), Vector2(0.09, 0.07), _recent_page > 0)
		_label(
			"%d / %d" % [_recent_page + 1, _recent_page_count()], Vector3(.33, HEADER_Y, .004), 18
		)
		_button(
			RECENT_NEXT,
			"›",
			Vector2(.51, HEADER_Y),
			Vector2(0.09, 0.07),
			_recent_page + 1 < _recent_page_count()
		)
	var status_left := CONTENT_LEFT + (.23 if playback_browser else .12)
	var status_width := (
		CONTENT_RIGHT
		- status_left
		- (.26 if compact and playback_browser else 0.0)
		- (.32 if file_actions.uncertain or file_actions.pending > 0 else 0.0)
	)
	var footer_status := (
		""
		if file_actions.editing and not file_actions.uncertain and file_actions.pending <= 0
		else I18n.t(status)
	)
	var line := _label(
		_fit_title(footer_status, "", status_width, 17), Vector3(status_left, FOOTER_Y, .004), 17
	)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.modulate = MUTED
	if file_actions.uncertain or file_actions.pending > 0:
		_button(
			FileActions.CHECK_STATUS,
			I18n.t(file_actions.pending_text()),
			Vector2(CONTENT_RIGHT - .15, FOOTER_Y),
			Vector2(0.30, 0.06),
			file_actions.pending == 0,
			"refresh"
		)


## Path pills (last four segments); every segment but the current one jumps there.
func _draw_crumbs(crumbs: Array) -> void:
	var x := CONTENT_LEFT + .12
	# Leave room for account actions; the up button still exposes every parent.
	var first := maxi(
		0, crumbs.size() - (2 if section in [Section.LOCAL] or file_actions.sortable() else 4)
	)
	for i in range(first, crumbs.size()):
		var text := _fit_title(str(crumbs[i]), "", .16, 19)
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x * 0.0012 + 0.05
		var current := i == crumbs.size() - 1
		_button(
			CRUMB_BASE + i,
			text,
			Vector2(x + width * 0.5, HEADER_Y),
			Vector2(width, 0.065),
			not current
		)
		var label: Label3D = _buttons.back().node.get_child(0)
		label.font_size = 19
		label.modulate = TEXT if current else MUTED
		if current:
			label.font = ui_font_bold()
			_buttons.back().base_color = Color(TILE, 0.0)
			_buttons.back()["keep_visible"] = true
			_buttons.back().node.visible = true
		x += width + 0.035
		if not current:
			_label("›", Vector3(x - 0.0175, HEADER_Y, 0.004), 19).modulate = MUTED


func _header_title() -> String:
	match section:
		Section.LOCAL:
			return " / ".join(sources.local_stack.map(func(c): return str(c.title)))
		Section.SMB:
			if sources.smb_server.is_empty():
				return ""
			var names: Array = (
				sources
				. smb_servers
				. filter(func(s): return str(s.id) == sources.smb_server)
				. map(func(s): return str(s.name))
			)
			return (
				(str(names[0]) if names.size() > 0 else "SMB")
				+ ("" if sources.smb_path.is_empty() else " / " + sources.smb_path)
			)
		Section.DLNA:
			if sources.dlna_server.is_empty():
				return ""
			var names: Array = (
				sources
				. dlna_servers
				. filter(func(s): return str(s.id) == sources.dlna_server)
				. map(func(s): return str(s.name))
			)
			var path := " / ".join(sources.dlna_stack.map(func(c): return str(c.title)))
			return (
				(str(names[0]) if names.size() > 0 else "DLNA")
				+ ("" if path.is_empty() else " / " + path)
			)
	return ""


func _draw_rows() -> void:
	choices.begin(str([section, tab]))
	_list = Node3D.new()
	add_child(_list)
	_decorations.append(_list)
	_bar_thumb = null
	var first := _first_line() * _cols()
	var row_top: float = (
		server_browser.list_top()
		if section == Section.MEDIA_SERVER and not account_panel.active()
		else LIST_TOP
	)
	for i in range(first, mini(rows.size(), first + _drawn_slots())):
		var row: Dictionary = rows[i]
		var k := i - first
		if _grid():
			if section == Section.MEDIA_SERVER:
				server_browser.tile(
					ROW_BASE + k,
					row,
					Vector2(
						GRID_LEFT + (k % COLS) * GRID_PITCH.x,
						server_browser.list_top() - TILE_SIZE.y * .5 - (k / COLS) * _pitch()
					)
				)
			else:
				_tile(
					ROW_BASE + k,
					row,
					Vector2(
						GRID_LEFT + (k % COLS) * GRID_PITCH.x,
						GRID_TOP - TILE_SIZE.y * 0.5 - (k / COLS) * GRID_PITCH.y
					)
				)
		else:
			var centre := Vector2(ROW_CENTRE_X, row_top - k * _pitch())
			if row.get("group", false):
				_setting_group(ROW_BASE + k, row, centre, k == 0)
				continue
			if row.has("choices") or row.get("slider", false):
				_setting_field(ROW_BASE + k, row, centre)
				continue
			if row.has("action"):
				_setting_action(ROW_BASE + k, row, centre)
				continue
			_row_button(
				ROW_BASE + k,
				str(row.title),
				"" if row.get("about_info", false) else str(row.get("detail", "")),
				str(row.get("icon", "video")),
				Vector2(ROW_CENTRE_X, row_top - k * _pitch()),
				bool(row.get("selected", false)),
				bool(row.get("stack_detail", false))
			)
			if section == Section.LOCAL and str(row.get("icon", "")) == "video":
				var picture := _picture(row)
				if picture:
					var preview := _quad(
						Vector2(0.072, 0.052), Vector3(-0.565, 0, 0.008), Color.WHITE, 14
					)
					_show_picture(preview, picture)
					_buttons.back().node.add_child(preview)
			if bool(row.get("about_info", false)):
				_buttons.back().enabled = false
				_buttons.back()["keep_visible"] = true
				_buttons.back().base_color = Color(TILE, 0.0)
				var node: MeshInstance3D = _buttons.back().node
				var title: Label3D = node.get_child(0)
				title.position.y = 0.023
				title.text = _fit_title(str(row.title), "", 1.08, 21)
				title.font_size = 21
				# Informational rows use two lines, leaving long contacts and credits readable.
				var detail := _label(
					_fit_title(str(row.detail), "", 1.08, 17),
					Vector3(-0.48, -0.024, 0.004),
					17,
					node
				)
				detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				detail.modulate = MUTED
				if account_panel.view == "license":
					_buttons.back().base_color = Color(0, 0, 0, 0)
					node.material_override.set_shader_parameter("surface_color", Color(0, 0, 0, 0))
					node.get_child(1).visible = false
					title.position.x = -0.58
					detail.position.x = -0.58
					title.font_size = 19
					detail.font_size = 19
					detail.modulate = Color.WHITE
					title.text = str(row.title)
					detail.text = str(row.detail)
	if _max_scroll() > 0:
		_draw_scrollbar(_bar_span())
	elif rows.is_empty() and status.is_empty() and section != Section.NETWORK:
		# Network media draws its own empty state with guidance; this one would sit under it.
		_icon(
			NAV_ICONS[section] if section < NAV_ICONS.size() else "video",
			Vector3(PANEL_CENTRE.x, 0.06, 0.004),
			0.08,
			Color(MUTED, 0.7)
		)
		var empty := _label(I18n.t("No items"), Vector3(PANEL_CENTRE.x, -0.03, 0.004), 20)
		empty.modulate = MUTED
	_place_list()
	choices.finish()


func _draw_scrollbar(span: Vector2) -> void:
	_button(
		SCROLLBAR, "", Vector2(SCROLLBAR_X, span.x - span.y * .5), Vector2(SCROLLBAR_WIDTH, span.y)
	)
	_buttons.back().base_color = Color(TEXT, 0.06)
	# Keep the generous ray target while giving the visible rail equal edge padding.
	_buttons.back().rect = Rect2(
		SCROLLBAR_X - SCROLLBAR_HIT_WIDTH * .5, span.x - span.y, SCROLLBAR_HIT_WIDTH, span.y
	)
	var thumb := span.y * float(_lines()) / _line_count()
	_bar_thumb = _decoration(
		Vector2(.010, thumb), Vector2(SCROLLBAR_X, span.x - thumb * .5), Color(TEXT, 0.32)
	)
	_bar_thumb.material_override.render_priority = 13


## Settings rows share one grid: the title (and an optional muted hint) on the left, the
## control in a fixed right column, so every page lines up the same way.
const SETTING_TITLE_X := -0.55
const SETTING_TITLE_WIDTH := 0.43
const SETTING_FIELD_X := 0.225
const SETTING_FIELD_WIDTH := 0.72
const SETTING_ACTION_WIDTH := 0.26
const SETTING_CARD_GAP := 0.012
const CARD := Color(0.063, 0.09, 0.14, 1.0)


func _setting_field(target: int, row: Dictionary, centre: Vector2) -> void:
	choices.field(
		_setting_heading(target, row, centre, str(row.get("hint", ""))),
		row,
		Vector2(SETTING_FIELD_X, 0),
		SETTING_FIELD_WIDTH
	)


## The row's title as an inert, transparent row; the controls are separate targets.
func _setting_heading(
	target: int, row: Dictionary, centre: Vector2, hint: String
) -> MeshInstance3D:
	_row_button(target, str(row.title), "", "", centre, false)
	var button: Dictionary = _buttons.back()
	button.enabled = false
	button["keep_visible"] = true  # The row holds a heading and separate choice controls.
	button.base_color = Color(TILE, 0.0)
	var node: MeshInstance3D = button.node
	if node.get_child_count() > 1:
		node.get_child(1).visible = false
	# Each setting sits on its own card; controls draw above it (priority 13+).
	var card := _quad(
		Vector2(BODY_WIDTH, _pitch() - SETTING_CARD_GAP), Vector3(0, 0, -0.001), CARD, 11
	)
	card.material_override.set_shader_parameter("corner_radius", 0.02)
	node.add_child(card)
	var title: Label3D = node.get_child(0)
	title.position = Vector3(SETTING_TITLE_X, 0.014 if not hint.is_empty() else 0, 0.004)
	title.font_size = 18
	title.text = _fit_title(str(row.title), "", SETTING_TITLE_WIDTH, 18)
	if not hint.is_empty():
		var label := _label(
			_fit_title(I18n.t(hint), "", SETTING_TITLE_WIDTH, 13),
			Vector3(SETTING_TITLE_X, -0.022, 0.004),
			13,
			node
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.modulate = MUTED
	return node


## One-button action (clear cache): right-aligned in the control column; pressing it chooses the row.
func _setting_action(target: int, row: Dictionary, centre: Vector2) -> void:
	_setting_heading(target, row, centre, str(row.get("detail", "")))
	var right := centre.x + SETTING_FIELD_X + SETTING_FIELD_WIDTH * .5
	_control_button(
		target,
		I18n.t(str(row.action)),
		Vector2(right - SETTING_ACTION_WIDTH * .5, centre.y),
		SETTING_ACTION_WIDTH,
		not bool(row.get("empty", false)),
		str(row.get("icon", "")),
		false,
		_list
	)
	_buttons.back()["keep_visible"] = true  # An empty cache shows a dimmed button, not a gap.
	_buttons.back().node.visible = true
	_above_card(_buttons.back().node)
	_lit(bool(row.get("selected", false)))


## Controls placed on a setting card draw over it regardless of transparent sort order.
func _above_card(node: MeshInstance3D) -> void:
	node.material_override.render_priority = 13
	for child in node.get_children():
		if child is Label3D:
			child.render_priority = 14
		elif child is MeshInstance3D:
			child.material_override.render_priority = 14


## Group heading: accent caption set low in its line, so it reads with the cards below it.
func _setting_group(target: int, row: Dictionary, centre: Vector2, _first: bool) -> void:
	_row_button(target, str(row.title), "", "", centre, false)
	var button: Dictionary = _buttons.back()
	button.enabled = false
	button["keep_visible"] = true
	button.base_color = Color(TILE, 0.0)
	var node: MeshInstance3D = button.node
	if node.get_child_count() > 1:
		node.get_child(1).visible = false
	var title: Label3D = node.get_child(0)
	title.position = Vector3(SETTING_TITLE_X - 0.03, -0.012, 0.004)
	title.font_size = 16
	title.font = ui_font_bold()
	title.modulate = ACCENT
	title.text = _fit_title(str(row.title), "", BODY_WIDTH - 0.1, 16)


func _choice_row(
	title: String,
	key: String,
	value: Variant,
	options: Array,
	compact: bool = false,
	hint: String = ""
) -> Dictionary:
	return {
		"title": I18n.t(title),
		"key": key,
		"value": value,
		"choices": options,
		"compact": compact,
		"hint": hint
	}


## A folder, video or server as a tile: a large glyph (videos keep a dark picture area with the
## length or size in the corner), the name in up to two lines below.
func _tile(target: int, row: Dictionary, centre: Vector2) -> void:
	var icon := str(row.get("icon", "video"))
	_button(
		target, _fit_title(str(row.title), "", 0.5, 18), centre, TILE_SIZE, true, "", false, _list
	)
	var button: Dictionary = _buttons.back()
	if str(button.node.get_child(0).text) != str(row.title):
		_tips[target] = str(row.title)
	button.base_color = (
		SELECTED
		if file_actions.editing and file_actions.row_uri(row) == file_actions.selected
		else TILE
	)
	button.enabled = not file_actions.editing or not file_actions.row_uri(row).is_empty()
	button.node.material_override.set_shader_parameter("surface_color", button.base_color)
	var node: MeshInstance3D = button.node
	var name: Label3D = node.get_child(0)
	name.font_size = 18
	name.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	name.width = (TILE_SIZE.x - 0.03) / name.pixel_size
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name.position = Vector3(0, -0.06, 0.004)
	var picture := icon in ["video", "image"]
	var area_size := Vector2(TILE_SIZE.x - .02, TILE_SIZE.y - .10)
	var area := _quad(
		area_size,
		Vector3(0, 0.04, 0.003),
		Color(0.055, 0.078, 0.122) if picture else Color(TILE, 0.0),
		12
	)
	area.material_override.set_shader_parameter("corner_radius", 0.012)
	node.add_child(area)
	var shown: Texture2D = _picture(row) if picture else null
	if shown:
		_show_picture(area, shown)
	else:
		var glyph := _icon(
			icon,
			Vector3(0, 0.04, 0.005),
			0.065 if picture else 0.1,
			MUTED if picture else (FOLDER if icon == "folder" else TEXT),
			node
		)
		glyph.material_override.render_priority = 13
	if file_actions.editing and not file_actions.row_uri(row).is_empty():
		_icon(
			"check" if file_actions.row_uri(row) == file_actions.selected else "circle",
			Vector3(-0.115, 0.095, 0.009),
			0.035,
			ACCENT,
			node
		)
	var bottom := 0.04 - area_size.y * 0.5
	var progress := float(row.get("progress", -1.0)) if picture else -1.0
	if progress >= 0.0:
		var span := area_size.x - 0.03
		var track := _quad(
			Vector2(span, 0.005), Vector3(0, bottom + 0.0045, 0.005), Color(0, 0, 0, 0.55), 13
		)
		node.add_child(track)
		var fill := _quad(
			Vector2(maxf(0.005, span * progress), 0.005),
			Vector3(-span * 0.5 + maxf(0.005, span * progress) * 0.5, bottom + 0.0045, 0.006),
			ACCENT,
			14
		)
		node.add_child(fill)
	var detail := str(row.get("detail", ""))
	if not detail.is_empty():
		# Length or size on a dark chip in the picture's corner, readable over any frame.
		var text := _fit_title(detail, "", TILE_SIZE.x - 0.06, 14)
		var width := ui_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.0012
		var right := area_size.x * 0.5 - 0.008
		var y := bottom + 0.022
		var chip := _quad(
			Vector2(width + 0.018, 0.026),
			Vector3(right - (width + 0.018) * 0.5, y, 0.005),
			Color(0.0, 0.0, 0.0, 0.62),
			13
		)
		chip.material_override.set_shader_parameter("corner_radius", 0.013)
		node.add_child(chip)
		var badge := _label(text, Vector3(right - 0.009, y, 0.006), 14, node)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.render_priority = 14
		badge.modulate = Color(TEXT, 0.92)


## The current choice is lit by colour (tinted tile, accent text), not a solid accent fill.
func _lit(selected: bool) -> void:
	if not selected:
		return
	var button: Dictionary = _buttons.back()
	button.base_color = SELECTED
	button.foreground = ACCENT
	button.node.get_child(0).modulate = ACCENT


## Page title at the top-left of the browser.
func _heading(text: String, location: Vector3, size: int = 26) -> Label3D:
	var title := _label(text, location, size)
	title.font = ui_font_bold()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return title


## Settings tab: idle tabs sit on the panel as plain text; the current one is a lit chip.
func _tab_button(target: int, text: String, centre: Vector2, width: float, current: bool) -> void:
	_control_button(target, text, centre, width)
	var button: Dictionary = _buttons.back()
	var label: Label3D = button.node.get_child(0)
	label.font_size = 18
	if current:
		_lit(true)
		label.font = ui_font_bold()
	else:
		button.base_color = Color(TILE, 0.0)
		button.foreground = NAV_IDLE
		label.modulate = NAV_IDLE


## How far a started video got, when its length is known: tiles show it as a bar.
static func _add_progress(row: Dictionary, entry: Dictionary) -> void:
	var duration := int(entry.get("duration_ms", -1))
	var position := int(entry.get("position_ms", 0))
	if duration > 0 and position > 0:
		row["progress"] = clampf(float(position) / duration, 0.0, 1.0)


## Draws [texture] inside [area]'s rounded shape instead of a square-cornered material.
func _show_picture(area: MeshInstance3D, texture: Texture2D) -> void:
	var surface: ShaderMaterial = area.material_override
	surface.set_shader_parameter("surface_color", Color.WHITE)
	surface.set_shader_parameter("use_texture", true)
	surface.set_shader_parameter("surface_texture", texture)
	surface.set_shader_parameter("sheen", 0.0)


## Cached local/played frame, or the cover a DLNA server offers.
func _picture(row: Dictionary) -> Texture2D:
	if row.has("scene"):
		var server_picture: Texture2D = server_browser.cover(row)
		return server_picture if server_picture else Thumbnails.texture(str(row.get("uri", "")))
	var cover := str(row.get("cover", ""))
	var played := Thumbnails.texture(str(row.get("uri", "")))
	if cover.is_empty():
		return played
	var cached := Thumbnails.texture(cover)
	if cached:
		_cache_cover_for_rows(cover, cached.get_image() if not played else null)
	if not cached and not _covers.has(cover) and _covers.size() < 4:
		_fetch_cover(cover)
	return cached if cached else played


func _cache_cover_for_rows(cover: String, image: Image) -> void:
	for row in rows:
		if row.get("cover", "") != cover or str(row.get("uri", "")).is_empty():
			continue
		var uri := str(row.uri)
		if image and not Thumbnails.has(uri):
			Thumbnails.store(uri, image)
		if catalog and catalog.has_method("set_cover") and catalog.set_cover(uri, cover):
			catalog.save()


func _fetch_cover(url: String) -> void:
	var request := HTTPRequest.new()
	request.body_size_limit = COVER_BYTES
	request.timeout = 10.0
	add_child(request)
	_covers[url] = request
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
			_covers.erase(url)
			request.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var image := Image.new()
			if (
				image.load_jpg_from_buffer(body) != OK
				and image.load_png_from_buffer(body) != OK
				and image.load_webp_from_buffer(body) != OK
			):
				return
			if Thumbnails.store(url, image):
				_cache_cover_for_rows(url, image)
				if visible:
					_draw()
	)
	if request.request(url) != OK:
		_covers.erase(url)
		request.queue_free()


func _cancel_covers() -> void:
	for request in _covers.values():
		request.cancel_request()
		request.queue_free()
	_covers.clear()


func _recent_page_count() -> int:
	return maxi(1, ceili(float(_recent_count) / RECENT_PAGE_SIZE))


func _turn_recent_page(step: int) -> void:
	_recent_page = clampi(_recent_page + step, 0, _recent_page_count() - 1)
	scroll = 0.0
	_drag = {}
	_fling = 0.0
	refresh()


func _row_button(
	target: int,
	title: String,
	detail: String,
	icon: String,
	centre: Vector2,
	selected: bool,
	stack_detail: bool = false
) -> void:
	if section == Section.SETTINGS:
		_control_button(target, title, centre, BODY_WIDTH, true, "", false, _list)
	else:
		_button(
			target,
			_fit_title(title, "", 1.08 if stack_detail else 0.9, 20 if stack_detail else 22),
			centre,
			Vector2(BODY_WIDTH, ROW_HEIGHT),
			true,
			"",
			false,
			_list
		)
	if str(_buttons.back().node.get_child(0).text) != title:
		_tips[target] = title
	_lit(selected)
	var node: MeshInstance3D = _buttons.back().node
	var label: Label3D = node.get_child(0)
	label.position.x = -0.48
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.font_size = (
		CONTROL_FONT_SIZE if section == Section.SETTINGS else (20 if stack_detail else 22)
	)
	if stack_detail:
		label.position.y = .019
	_icon(
		icon,
		Vector3(-0.565, 0, 0.004),
		CONTROL_ICON_SIZE if section == Section.SETTINGS else 0.045,
		_buttons.back().foreground,
		node
	)
	if not detail.is_empty():
		var info := _label(
			_fit_title(detail, "", 1.08, 14) if stack_detail else detail,
			Vector3(-.48, -.024, .004) if stack_detail else Vector3(.58, 0, .004),
			14 if stack_detail else 17,
			node
		)
		info.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if stack_detail else HORIZONTAL_ALIGNMENT_RIGHT
		)
		info.modulate = MUTED


const NAV_IDLE := Color(0.76, 0.81, 0.88)
const NAV_WIDTH := 0.36
static var _brand_texture: Texture2D


## App mark and name at the top of the navigation column.
func _draw_brand(column: MeshInstance3D) -> void:
	var mark := _quad(
		Vector2.ONE * 0.056, Vector3(-NAV_WIDTH * .5 + 0.05, 0.495, 0.004), Color.WHITE, 12
	)
	# Clip to the icon's own squircle; the source image has light corners.
	mark.material_override.set_shader_parameter("corner_radius", 0.013)
	_show_picture(mark, _brand())
	column.add_child(mark)
	var name := _label("Immivio", Vector3(-NAV_WIDTH * .5 + 0.094, 0.495, 0.004), 26, column)
	name.font = ui_font_bold()
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_quad(Vector2(NAV_WIDTH - 0.02, 0.002), Vector3(0, 0.45, 0.003), DIVIDER, 12))


## The launcher icon is far larger than its spot here: keep one small, mipmapped copy.
static func _brand() -> Texture2D:
	if _brand_texture == null:
		var image := (load("res://branding/immivio-icon.png") as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
		_brand_texture = ImageTexture.create_from_image(image)
	return _brand_texture


## Navigation entry on the angled column: rows rest on the panel itself; the current
## one gets a tinted fill, an accent bar at its leading edge and a heavier label.
func _nav_button(target: int, text: String, icon: String, centre: Vector2, selected: bool) -> void:
	_control_button(target, text, centre, NAV_WIDTH, true, "", false, _side)
	var button: Dictionary = _buttons.back()
	button.base_color = SELECTED if selected else Color(TILE, 0.0)
	var node: MeshInstance3D = button.node
	var label: Label3D = node.get_child(0)
	label.position.x = -0.08
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = ACCENT if selected else NAV_IDLE
	_icon(icon, Vector3(-0.13, 0, 0.004), CONTROL_ICON_SIZE, ACCENT if selected else NAV_IDLE, node)
	var marker := _quad(
		Vector2(0.006, CONTROL_HEIGHT * 0.5), Vector3(-NAV_WIDTH * .5 + 0.012, 0, 0.004), ACCENT, 12
	)
	marker.visible = selected
	node.add_child(marker)


## Over a playing video the library only switches videos, so it hides Settings.
func nav_order() -> Array:
	return NAV_ORDER.filter(func(item): return not playback_browser or item != Section.SETTINGS)


## Opened over a playing video the library is a quick video switcher: one size, anchored
## above the control bar, without settings.
func set_playback_browser(playing: bool) -> void:
	var changed := playback_browser != playing
	playback_browser = playing
	compact = playing
	allow_user_dismiss = playing
	if playing and section == Section.SETTINGS:
		file_actions.reset()
		account_panel.close()
		section = Section.RECENT
		tab = 0
		scroll = 0.0
		status = ""
		if visible:
			sources.load_section()
	if changed and visible:
		refresh()


func _update_navigation_selection() -> void:
	for button in _buttons:
		if button.target < NAV_BASE or button.target >= NAV_BASE + NAV.size():
			continue
		var selected: bool = (
			button.target == NAV_BASE + (Section.NETWORK if network.contains(section) else section)
		)
		button.base_color = SELECTED if selected else Color(TILE, 0.0)
		var label: Label3D = button.node.get_child(0)
		label.modulate = ACCENT if selected else NAV_IDLE
		label.font = ui_font_bold() if selected else ui_font()
		var icon: MeshInstance3D = button.node.get_child(1)
		icon.material_override.albedo_color = ACCENT if selected else NAV_IDLE
		if button.node.get_child_count() > 2:
			button.node.get_child(2).visible = selected


func _draw_about() -> void:
	if _about_page != 0:
		_control_button(
			ABOUT_HOME,
			"",
			Vector2(CONTENT_RIGHT - CONTROL_HEIGHT * .5, HEADER_Y),
			CONTROL_HEIGHT,
			true,
			"up"
		)


func _about_info(title: String, detail: String) -> Dictionary:
	return {"title": title, "detail": detail, "icon": "info", "about_info": true}


func _open_licenses() -> void:
	_about_page = 3
	scroll = 0.0
	refresh()


func _desktop_license_text(id: String) -> String:
	var index: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://i18n/licenses.json")
	)
	if not index is Array:
		return ""
	for item in index:
		if item.id == id:
			var text := ""
			for asset in item.get("assets", []):
				var path := ProjectSettings.globalize_path("res://../../third_party/" + str(asset))
				if FileAccess.file_exists(path):
					text += FileAccess.get_file_as_string(path) + "\n\n"
			return text
	return ""


func _engine_notices() -> String:
	var text := ""
	for component in Engine.get_copyright_info():
		text += str(component.get("name", "")) + "\n"
		for part in component.get("parts", []):
			text += (
				"\n".join(part.get("copyright", [])) + "\n" + str(part.get("license", "")) + "\n\n"
			)
	var licenses := Engine.get_license_info()
	for name in licenses:
		text += str(name) + "\n\n" + str(licenses[name]) + "\n\n"
	return text


func _draw_editor() -> void:
	var dlna_editor := section == Section.DLNA
	var fields := _editor_fields()
	_heading("DLNA" if dlna_editor else "SMB", Vector3(-0.42, 0.46, 0.004))
	for i in fields.size():
		var value := str(editor[fields[i]])
		if fields[i] == "password":
			value = (
				"•".repeat(value.length())
				if not value.is_empty()
				else ("••••" if bool(editor.has_password) else "")
			)
		var centre := (
			Vector2(0.025 if i == 0 else 0.665, 0.30)
			if dlna_editor
			else Vector2(-0.12 + (i % 2) * 0.64, 0.36 - (i / 2) * 0.115)
		)
		if dlna_editor and i == 0 and value.is_empty():
			value = "192.168.1.10"
		var field_width := (0.91 if i == 0 else 0.31) if dlna_editor else 0.62
		_button(
			FIELD_BASE + i,
			_fit_title(value, "", field_width - 0.10 if dlna_editor else 0.42, 21),
			centre,
			Vector2(field_width, 0.1),
			not _editor_busy()
		)
		_lit(i == _field)
		var node: MeshInstance3D = _buttons.back().node
		var label: Label3D = node.get_child(0)
		label.position = Vector3(-field_width * 0.5 + 0.04 if dlna_editor else -0.17, -0.012, 0.004)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if i == _field and not _editor_busy():
			label.modulate = TEXT
		var name := _label(
			I18n.t("IP address" if i == 0 else "Port") if dlna_editor else I18n.t(FIELD_NAMES[i]),
			Vector3(
				-field_width * 0.5 + 0.03 if dlna_editor else -0.28,
				0.02 if dlna_editor else 0.0,
				0.004
			),
			17,
			node
		)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.modulate = ACCENT if i == _field else MUTED
	var layer: Array = SYMBOLS if _symbols else KEYS
	for r in layer.size():
		for c in 10:
			var character: String = layer[r][c]
			_button(
				KEY_BASE + r * 10 + c,
				character.to_upper() if _shift else character,
				Vector2(-0.38 + c * 0.126, 0.1 - r * 0.098),
				Vector2(0.115, 0.085)
			)
	var y := 0.1 - 4 * 0.098
	_button(SHIFT, "⇧", Vector2(-0.32, y), Vector2(0.18, 0.085), true, "", _shift)
	_button(
		SYMBOL_LAYER,
		"#+=" if not _symbols else "abc",
		Vector2(-0.13, y),
		Vector2(0.18, 0.085),
		true,
		"",
		_symbols
	)
	_button(SPACE, "␣", Vector2(0.15, y), Vector2(0.34, 0.085))
	_button(BACKSPACE, "", Vector2(0.43, y), Vector2(0.18, 0.085), true, "backspace")
	# A key among keys: keep the keyboard's rectangle rather than the icon capsule.
	_buttons.back().node.material_override.set_shader_parameter("corner_radius", CONTROL_RADIUS)
	var actions := -0.44
	_button(
		SAVE,
		"",
		Vector2(0.73, actions),
		Vector2(0.18, 0.08),
		(
			not _editor_busy()
			and not str(editor.get("host", "")).strip_edges().is_empty()
			and (not dlna_editor or not str(editor.port).strip_edges().is_empty())
		),
		"check",
		true
	)
	_button(CANCEL, "", Vector2(0.52, actions), Vector2(0.18, 0.08), true, "close")
	if not str(editor.id).is_empty():
		_button(
			DELETE,
			I18n.t("Delete"),
			Vector2(0.24, actions),
			Vector2(0.24, 0.08),
			not _editor_busy()
		)
	if dlna_editor and not status.is_empty():
		_label(I18n.t(status), Vector3(0.13, -0.54, 0.004), 18)


# --- desktop preview helpers ----------------------------------------------------------------


func _activate_hit(hit: Dictionary) -> void:
	if int(hit.target) == SCROLLBAR:
		_scroll_to_bar(float(hit.point.y))
	else:
		super(hit)


func move_focus(direction: int) -> void:
	if rows.is_empty():
		return
	focus_index = posmod(focus_index + direction, rows.size())
	var line := focus_index / _cols()
	scroll = clampf(
		(
			float(line - _lines() + 1)
			if line >= _first_line() + _lines()
			else minf(_first_line(), line)
		),
		0.0,
		_max_scroll()
	)
	_draw()


func activate_desktop() -> void:
	if visible and focus_index < rows.size():
		_choose(rows[focus_index])
