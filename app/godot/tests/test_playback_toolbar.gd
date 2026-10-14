extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state := {
		"has_video": true,
		"playing": true,
		"playback_state": "playing",
		"duration_ms": 60000,
		"position_ms": 10000,
		"geometry": 0,
		"title": "Toolbar",
		"has_previous_video": true,
		"has_next_video": true,
		"bookmark_scope": "toolbar",
		"bookmark_ready": true,
		"bookmark_seekable": true,
		"bookmark_undo": true,
		"bookmarks": [{"id": "first", "position_ms": 10000}, {"id": "second", "position_ms": 30000}]
	}
	var menu := Menu.new()
	menu.state_provider = func(): return state
	menu.session_controls_provider = func():
		return {"follow": true, "passthrough_visible": true, "passthrough": true, "alpha": false}
	root.add_child(menu)
	menu.set_process(false)
	menu.toggle()
	menu.device_status.status_provider = func():
		return {"level": 100, "charging": true, "clock24": false}
	menu.device_status.clock_provider = func(): return {"hour": 23, "minute": 59}
	menu.device_status.refresh(true)
	menu.refresh_session_controls()
	check(
		not menu._buttons.any(
			func(button): return button.target in [menu.FOLLOW, menu.TEMP_PASSTHROUGH, 100]
		),
		"Video toolbar omits session toggles and duplicate library action"
	)
	check(
		menu._buttons.any(func(button): return button.target == 107),
		"Close video is the single return action"
	)
	var operations := []
	menu.action_requested.connect(func(operation): operations.append(operation))
	menu._activate(107)
	check(operations == ["stop"], "Single close action uses stop-and-return production route")
	for button in menu._buttons:
		if button.target == menu.SEEK:
			continue
		check(
			button.rect.position.y > menu.BAR_SEEK_Y,
			"Every toolbar/bookmark button is above timeline: %d" % button.target
		)
	var status := menu.device_status
	check(
		status.position.y - status.HEIGHT / 2 > menu.BAR_SEEK_Y,
		"Battery and clock are above timeline"
	)
	check(
		is_equal_approx(status._pill.mesh.size.y, menu.FOOTER_DIAMETER),
		"Status and floating buttons have matching heights"
	)
	check(
		status._pill.material_override.get_shader_parameter("surface_color") == menu.TILE,
		"Status uses the floating-button tile color"
	)
	check(
		is_equal_approx(
			float(status._pill.material_override.get_shader_parameter("corner_radius")),
			menu.FOOTER_DIAMETER / 2
		),
		"Status uses matching capsule corners"
	)
	var status_rect := Rect2(
		Vector2(
			status.position.x - status._pill.mesh.size.x / 2, status.position.y - status.HEIGHT / 2
		),
		status._pill.mesh.size
	)
	for button in menu._buttons:
		check(
			not status_rect.intersects(button.rect),
			"Long charging/12-hour status does not overlap action %d" % button.target
		)
	var play: Dictionary = menu._buttons.filter(func(button): return button.target == 102)[0]
	var previous: Dictionary = menu._buttons.filter(func(button): return button.target == 101)[0]
	var next: Dictionary = menu._buttons.filter(func(button): return button.target == 103)[0]
	check(
		(
			is_zero_approx(play.rect.get_center().x)
			and previous.rect.get_center().x < 0
			and next.rect.get_center().x > 0
		),
		"Play is centred between adjacent previous and next"
	)
	for title in ["Short.mp4", "Long Unicode 文件名 😀 ".repeat(10) + ".mp4"]:
		state.title = title
		menu.refresh_values()
		menu.refresh_session_controls()
		var pill: MeshInstance3D = menu._title_pill
		var title_rect := Rect2(
			Vector2(pill.position.x - pill.mesh.size.x / 2, pill.position.y - pill.mesh.size.y / 2),
			pill.mesh.size
		)
		var battery_rect := Rect2(
			Vector2(
				status.position.x - status._pill.mesh.size.x / 2,
				status.position.y - status.HEIGHT / 2
			),
			status._pill.mesh.size
		)
		var close: Dictionary = menu._buttons.filter(func(button): return button.target == 107)[0]
		check(
			(
				not title_rect.intersects(battery_rect)
				and not battery_rect.intersects(close.rect)
				and close.rect.position.x > battery_rect.end.x
			),
			"Title, charging clock and close fit in one header without overlap"
		)
		check(
			(
				menu._title.text.ends_with(".mp4")
				and (menu._title.text == title or menu._title.text.contains("…"))
			),
			"Long names keep their suffix and elide the middle"
		)
		check(
			(
				(
					(
						menu
						. ui_font()
						. get_string_size(menu._title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
						. x
					)
					* .0012
				)
				<= pill.mesh.size.x - .059
			),
			"Actual shaped title fits its capsule"
		)
	check(
		is_equal_approx(menu._backdrop.mesh.size.y, .20),
		"The timeline backdrop has no retired title or settings-row padding"
	)
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Playback toolbar: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
