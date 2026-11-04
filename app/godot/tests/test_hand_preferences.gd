extends SceneTree
const Policy := preload("res://scripts/hand_preferences.gd")
const Gestures := preload("res://scripts/photo_hand_gestures.gd")
func sample(point: Vector3, down: bool, pressed: bool = false, released: bool = false) -> Dictionary:
	return {"source": "hand", "tracked": true, "position": point, "down": down, "pressed": pressed, "released": released}
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")
func _run() -> void:
	assert(Policy.normalize("bad") == "right_hand")
	var gestures := Gestures.new()
	var origin := Vector3(0, 1.6, -1)
	var left := origin - Vector3(0.3, 0, 0)
	var ignored := gestures.update({"left_hand": sample(left, true, true)}, true, 1.0, Basis.IDENTITY, 1.0, 1)
	assert(ignored.consumed.is_empty() and gestures.mode.is_empty())
	var both := {"left_hand": sample(left, true, true), "right_hand": sample(origin, true, true)}
	gestures.update(both, true, 1.0, Basis.IDENTITY, 1.0, 1)
	assert(gestures.mode == "dual")
	gestures.set_initiator_hand("left_hand")
	assert(gestures.mode.is_empty() and gestures.owners.is_empty())
	var host := preload("res://scripts/main.gd").new()
	root.add_child(host)
	host.set_process(false)
	host.recent_menu.dismiss()
	host.video_menu.dismiss()
	host.photo_menu.dismiss()
	host.photo_active = true
	host.player_menu = host.photo_menu
	host.photo.local_uri = "file:///photo.jpg"
	host.photo.panel.visible = true
	host.photo._texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	host.photo.platform = preload("res://tests/test_photo_hand_gestures.gd").Host.new()
	for hand in host.hand_pointers:
		host.hand_pointers[hand].source = "hand"
		host.hand_pointers[hand].ray = [Vector3(0, 1.6, 0), Vector3.FORWARD]
	assert(host.pinch_hand == "right_hand" and not host._picture_pinch_allowed("left_hand"))
	host._dispatch_hand_input({"left_hand": sample(left, true, true)})
	host._dispatch_hand_input({"left_hand": sample(left, false, false, true)})
	assert(not host.photo_menu.visible)
	host._dispatch_hand_input({"right_hand": sample(origin, true, true)})
	host._dispatch_hand_input({"right_hand": sample(origin, false, false, true)})
	assert(host.photo_menu.visible)
	var button: Dictionary = host.photo_menu._buttons.filter(func(item): return item.target == host.photo_menu.MODE)[0]
	host.hand_pointers.left_hand.ray = [button.node.global_position + button.node.global_basis.z, -button.node.global_basis.z]
	host._on_pointer_button("trigger_click", "left_hand")
	host._on_pointer_release("trigger_click", "left_hand")
	assert(host.photo_menu._mode_open)
	host._show_recent_menu(true)
	host.recent_menu.section = host.recent_menu.Section.SETTINGS
	host.recent_menu.tab = host.recent_menu.GENERAL_TAB
	host.recent_menu.refresh()
	var probe := preload("res://scripts/selected_features_device_probe.gd").new()
	assert(await probe.choose(host.recent_menu, "pinch_hand", "both"))
	assert(host.pinch_hand == "both" and host.photo_hands.initiator_hand == "both")
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
