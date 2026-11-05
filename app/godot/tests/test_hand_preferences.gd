extends SceneTree
const Policy := preload("res://scripts/hand_preferences.gd")
func sample(point: Vector3, down: bool, pressed: bool = false, released: bool = false) -> Dictionary:
	return {"source": "hand", "tracked": true, "position": point, "down": down, "pressed": pressed, "released": released}
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")
func _run() -> void:
	assert(Policy.normalize("bad") == "right_hand")
	var origin := Vector3(0, 1.6, -1)
	var left := origin - Vector3(.3, 0, 0)
	var host := preload("res://scripts/main.gd").new()
	root.add_child(host)
	host.set_process(false)
	host.recent_menu.dismiss()
	host.video_menu.dismiss()
	host.video.set_process(false)
	host.video.local_uri = "file:///video.mp4"
	host.video.media.begin(1)
	host.video.media.state = "paused"
	host.video.media.frame_counter = 1
	host.video._waiting_first = false
	host.video.panel.visible = true
	host._place_screen()
	for hand in host.hand_pointers:
		host.hand_pointers[hand].source = "hand"
		host.hand_pointers[hand].ray = [host._eye(), (host.video.panel.global_position - host._eye()).normalized()]
	assert(host.pinch_hand == "right_hand" and not host._picture_pinch_allowed("left_hand"))
	host._dispatch_hand_input({"left_hand": sample(left, true, true)})
	host._dispatch_hand_input({"left_hand": sample(left, false, false, true)})
	assert(not host.video_menu.visible)
	host._dispatch_hand_input({"right_hand": sample(origin, true, true)})
	host._dispatch_hand_input({"right_hand": sample(origin, false, false, true)})
	assert(host.video_menu.visible)
	var button: Dictionary = host.video_menu._buttons.filter(func(item): return item.target == host.video_menu.MODE)[0]
	host.hand_pointers.left_hand.ray = [button.node.global_position + button.node.global_basis.z, -button.node.global_basis.z]
	host._on_pointer_button("trigger_click", "left_hand")
	host._on_pointer_release("trigger_click", "left_hand")
	assert(host.video_menu._mode_open)
	host._show_recent_menu(true)
	host.recent_menu.section = host.recent_menu.Section.SETTINGS
	host.recent_menu.tab = host.recent_menu.GENERAL_TAB
	host.recent_menu.refresh()
	var probe := preload("res://scripts/selected_features_device_probe.gd").new()
	assert(await probe.choose(host.recent_menu, "pinch_hand", "both"))
	assert(host.pinch_hand == "both")
	assert(host.settings.get_value("controls", "pinch_hand") == "both")
	for hand in host.hand_pointers:
		assert(not host.hand_pointers[hand].armed and not host.hand_pointers[hand].down)
	host._on_setting_changed("pinch_hand", "retired-value")
	assert(host.pinch_hand == "both")
	var settings := ConfigFile.new()
	settings.set_value("controls", "pinch_hand", "invalid")
	assert(preload("res://scripts/player_settings_migration.gd").apply(settings))
	assert(settings.get_value("controls", "pinch_hand") == "right_hand")
	assert(not preload("res://scripts/player_settings_migration.gd").apply(settings))
	host.queue_free()
	await process_frame
	preload("res://tests/support/test_result.gd").finish(self, 0)
