extends Node
## Compile common UI resources offscreen before their first interactive use.
## Synthetic state only: no media, thumbnails, account data or pixel readback.
const Menu := preload("res://scripts/player_menu.gd")
const Icons := preload("res://scripts/menu_icons.gd")
const STATE := {"has_video": true, "title": "Thru3D", "source_uri": "warmup://synthetic",
	"geometry": 0, "stereo": true, "ai_enabled": false, "duration_ms": 60000,
	"position_ms": 30000, "audio_available": true, "playing": true}
const PAGES := ["bar", "screen", "playback", "info", "color0", "color1", "color2", "stereo", "mode", "subtitles", "volume"]
var complete := false
var pages_rendered := 0
var max_build_us := 0

func _ready() -> void: _run.call_deferred()

func prepare(menu: Node3D, page: String) -> void:
	menu._reset_navigation()
	menu.section = 0 if page in ["bar", "mode", "subtitles", "volume"] else (2 if page == "info" else 1)
	menu._adjustment = "screen" if page == "screen" else ("stereo_view" if page == "stereo" else ("color_grade" if page.begins_with("color") else ""))
	menu._grade_page = int(page.trim_prefix("color")) if page.begins_with("color") else 0
	menu._mode_open = page == "mode"
	menu._subtitle_open = page == "subtitles"
	menu._volume_open = page == "volume"
	menu._state = STATE.duplicate(true)
	menu._draw()

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
	var menu := Menu.new(); target.add_child(menu)
	menu.set_process(false); menu.position = Vector3.ZERO; menu.visible = true
	for page in PAGES:
		var started := Time.get_ticks_usec()
		prepare(menu, page)
		max_build_us = maxi(max_build_us, Time.get_ticks_usec() - started)
		# Rendering, rather than creating hidden nodes, warms shader/font variants.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		pages_rendered += 1
	target.queue_free()
	complete = true

func snapshot() -> Dictionary:
	return {"complete": complete, "pages_rendered": pages_rendered, "max_build_us": max_build_us,
		"synthetic_only": true, "cpu_readback": false}
