extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var state := {"has_video":true,"playing":true,"playback_state":"playing","duration_ms":60000,"position_ms":10000,
		"geometry":0,"title":"Toolbar","bookmark_scope":"toolbar","bookmark_ready":true,"bookmark_seekable":true,
		"bookmark_undo":true,"bookmarks":[{"id":"first","position_ms":10000},{"id":"second","position_ms":30000}]}
	var menu := Menu.new(); menu.state_provider = func(): return state
	menu.session_controls_provider = func(): return {"follow":true,"passthrough_visible":true,"passthrough":true,"alpha":false}
	root.add_child(menu); menu.set_process(false); menu.toggle()
	menu.device_status.status_provider = func():return {"level":100,"charging":true,"clock24":false}
	menu.device_status.clock_provider = func():return {"hour":23,"minute":59}
	menu.device_status.refresh(true)
	check(not menu._buttons.any(func(button):return button.target in [menu.FOLLOW,menu.TEMP_PASSTHROUGH,100]),"Video toolbar omits session toggles and duplicate library action")
	check(menu._buttons.any(func(button):return button.target==107),"Close video is the single return action")
	var operations := []
	menu.action_requested.connect(func(operation):operations.append(operation))
	menu._activate(107)
	check(operations==["stop"],"Single close action uses stop-and-return production route")
	for button in menu._buttons:
		if button.target==menu.SEEK:continue
		check(button.rect.position.y > menu.BAR_SEEK_Y,"Every toolbar/bookmark button is above timeline: %d" % button.target)
	var status := menu.device_status
	check(status.position.y-status.HEIGHT/2 > menu.BAR_SEEK_Y,"Battery and clock are above timeline")
	check(is_equal_approx(status._pill.mesh.size.y,menu.FOOTER_DIAMETER),"Status and floating buttons have matching heights")
	check(status._pill.material_override.get_shader_parameter("surface_color")==menu.TILE,"Status uses the floating-button tile color")
	check(is_equal_approx(float(status._pill.material_override.get_shader_parameter("corner_radius")),menu.FOOTER_DIAMETER/2),"Status uses matching capsule corners")
	var status_rect := Rect2(Vector2(status.position.x-status._pill.mesh.size.x/2,status.position.y-status.HEIGHT/2),status._pill.mesh.size)
	for button in menu._buttons:
		check(not status_rect.intersects(button.rect),"Long charging/12-hour status does not overlap action %d" % button.target)
	for section in [1,2]:
		menu.section = section; menu.refresh(); menu.refresh_session_controls(true)
		check(not menu._buttons.any(func(button):return button.target in [menu.FOLLOW,menu.TEMP_PASSTHROUGH]),"Expanded playback pages omit session toggles")
		check(status.position.y > menu._backdrop.position.y+menu._backdrop.mesh.size.y/2,"Expanded page status remains above content")
	menu.free()
	for failure in failures:push_error(failure)
	print("Playback toolbar: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
