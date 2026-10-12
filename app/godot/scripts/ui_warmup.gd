extends Node
## Compile common UI resources offscreen before their first interactive use.
## Synthetic state only: no media, thumbnails, account data or pixel readback.
const Menu := preload("res://scripts/player_menu.gd")
const Library := preload("res://scripts/library_menu.gd")
const Icons := preload("res://scripts/menu_icons.gd")
const STATE := {"has_video": true, "title": "Thru3D", "source_uri": "warmup://synthetic",
	"geometry": 0, "stereo": true, "ai_enabled": false, "duration_ms": 60000,
	"position_ms": 30000, "audio_available": true, "playing": true}
const PAGES := ["bar", "screen", "playback", "sync", "queue", "info", "color0", "color1", "color2", "stereo", "mode", "subtitles", "volume",
	"screen_immersive", "stereo_left", "screen_mono", "playback_mono", "sync_mono", "queue_mono", "color0_mono", "color1_mono", "color2_mono", "ipd_mono",
	"depth", "audio", "subtitle_immersive", "queue_populated", "bookmarks", "playback_alpha", "stereo_tb", "info_available"]
var playback_menu: Node3D

const SESSION_STATE := {"follow": false, "passthrough_visible": true, "passthrough": false, "alpha": false}
const LIBRARY_TABS := [Library.GENERAL_TAB, Library.DISPLAY_TAB, Library.VIDEO_TAB, Library.SUBTITLES_TAB, Library.BACKGROUND_TAB, Library.ABOUT_TAB]
var complete := false
var pages_rendered := 0
var max_build_us := 0
var library_pages_rendered := 0

func prepare_library(menu: Node3D, tab: int) -> void:
	menu.section = Library.Section.SETTINGS
	menu.tab = tab
	menu._cache_usage = Vector2i.ZERO
	menu.refresh()

func _ready() -> void: _run.call_deferred()

func prepare(menu: Node3D, page: String) -> void:
	menu._reset_navigation()
	var name := page.trim_suffix("_mono")
	match name:
		"bar", "mode", "subtitles", "volume", "depth", "audio", "subtitle_immersive", "bookmarks":
			menu.section = 0
		"info", "info_available": menu.section = 2
		_: menu.section = 1
	match name:
		"screen", "screen_immersive": menu._adjustment = "screen"
		"stereo", "stereo_left", "stereo_tb", "ipd": menu._adjustment = "stereo_view"
		"sync": menu._adjustment = "sync"
		"queue", "queue_populated": menu._adjustment = "queue"
		_: menu._adjustment = "color_grade" if name.begins_with("color") else ""
	menu._grade_page = int(name.trim_prefix("color")) if name.begins_with("color") else 0
	menu._mode_open = name == "mode"; menu._subtitle_open = name in ["subtitles", "subtitle_immersive"]
	menu._volume_open = name == "volume"; menu._depth_open = name == "depth"
	menu._state = STATE.duplicate(true)
	menu._state["stereo"] = not page.ends_with("_mono") and name != "depth"
	menu._state["ai_enabled"] = name in ["depth", "playback_alpha"]
	menu._state["top_bottom"] = name == "stereo_tb"
	menu._state["capabilities_available"] = name == "info_available"
	menu._state["viewing_eye"] = 1 if name == "stereo_left" else 0
	menu._state["geometry"] = 1 if name in ["screen_immersive", "subtitle_immersive", "playback_alpha"] else 0
	if name == "queue_populated":
		menu._state["queue_items"] = [{"uri":"warmup://synthetic", "title":"Thru3D synthetic"}]
	if name in ["audio", "subtitle_immersive", "subtitles"]:
		menu._state["audio_options"] = [{"id":1,"value":1,"label":"Synthetic audio"}]
		menu._state["subtitle_options"] = [{"id":1,"codec":"subrip","title":"Synthetic subtitle"}]
		menu._state["audio_available"] = true; menu._state["audio_track_id"] = 1
		menu._state["text_subtitle_tracks"] = 1
	if name == "bookmarks":
		menu._state["bookmark_scope"] = "warmup://synthetic"
		menu._state["bookmarks"] = [{"id":"synthetic","position_ms":10000}]
		menu.bookmarks.opened = true; menu.bookmarks.scope = "warmup://synthetic"
	menu._draw()
	if name == "audio":
		menu.choices.opened = "audio_track"; menu._draw()

func _run() -> void:
	# Spread SVG decoding/texture uploads across startup frames.
	var count := 0
	for key in Icons.PATHS:
		Icons.texture(key); count += 1
		if count % 4 == 0: await get_tree().process_frame
	var target := SubViewport.new()
	target.size = Vector2i(256, 192); target.own_world_3d = true
	target.transparent_bg = true; target.msaa_3d = Viewport.MSAA_DISABLED
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(target)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 1.8
	camera.position.z = 1; camera.near = .01; camera.far = 3
	target.add_child(camera); camera.current = true
	# Settings are reachable as soon as the library opens; warm them first.
	var library := Library.new(); target.add_child(library)
	library.session_controls_provider = func(): return SESSION_STATE
	library.set_process(false); library.position = Vector3.ZERO; library.visible = true
	for tab in LIBRARY_TABS:
		var started := Time.get_ticks_usec()
		prepare_library(library, tab)
		library._hover = {"warmup": library.TEMP_PASSTHROUGH}
		library._update_highlights()
		max_build_us = maxi(max_build_us, Time.get_ticks_usec() - started)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		library_pages_rendered += 1
	library.free()
	var menu := Menu.new(); target.add_child(menu)
	menu.session_controls_provider = func(): return SESSION_STATE
	menu.set_process(false); menu.position = Vector3.ZERO; menu.visible = true
	for page in PAGES:
		var started := Time.get_ticks_usec()
		prepare(menu, page)
		menu._hover = {"warmup": menu.TEMP_PASSTHROUGH}
		menu._update_highlights()
		max_build_us = maxi(max_build_us, Time.get_ticks_usec() - started)
		# Rendering, rather than creating hidden nodes, warms shader/font variants.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		pages_rendered += 1
	if is_instance_valid(playback_menu): playback_menu.adopt_prepared_layouts(menu)
	target.queue_free()
	complete = true

func snapshot() -> Dictionary:
	return {"complete": complete, "pages_rendered": pages_rendered, "max_build_us": max_build_us,
		"library_pages_rendered": library_pages_rendered,
		"synthetic_only": true, "cpu_readback": false}
