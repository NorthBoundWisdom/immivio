extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
const Directory := preload("res://scripts/photo_directory.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Main := preload("res://scripts/main.gd")
var checks := 0
var failures: Array[String] = []
var folder := "user://photo_layout_test_%d" % Time.get_ticks_usec()
var entries: Array[Dictionary] = []


class Cloud:
	extends RefCounted
	signal media_list(id: int, payload: String)
	var requests := []
	var cancelled := []

	func media_photo_directory_page(path: String, offset: int, order: String) -> int:
		requests.append({"path": path, "offset": offset, "order": order})
		return requests.size()

	func media_photo_directory_cancel(id: int) -> void:
		cancelled.append(id)

	func media_cloud_sorted_page(path: String, offset: int, _refresh: bool, order: String) -> int:
		push_error("Album scanning must not steal the library's active browse")
		return -1

	func media_cloud_cancel(id: int) -> void:
		cancelled.append(id)


class Harness:
	extends "res://scripts/main.gd"
	var rays := {}

	func _ray(hand: String) -> Variant:
		return rays.get(hand)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func settle(photo: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while photo.loading and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(not photo.loading and photo.error.is_empty(), "Selected image completes")
	await process_frame


func load_previews(photo: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		photo.gallery._process(0.016)
		if photo.gallery.cards.keys().all(
			func(index): return photo.gallery.previews.texture(str(photo.queue[index].uri)) != null
		):
			break
		await create_timer(0.01).timeout
	var missing: Array = photo.gallery.cards.keys().filter(
		func(index): return photo.gallery.previews.texture(str(photo.queue[index].uri)) == null
	)
	check(
		missing.is_empty(),
		(
			"Unopened neighbours load independent aspect-preserving previews: layout=%d, missing=%s, failed=%s"
			% [photo.gallery.mode, missing, photo.gallery.previews._failed]
		)
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 96:
		var size := (
			Vector2i(240, 120)
			if i % 3 == 0
			else (Vector2i(100, 160) if i % 3 == 1 else Vector2i(150, 150))
		)
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_hsv(i / 96.0, 0.7, 0.9))
		var path := ProjectSettings.globalize_path(folder.path_join("%02d.png" % i))
		image.save_png(path)
		entries.append({"uri": "file://" + path, "title": "%02d.png" % i, "kind": "image"})
	var photo := Photo.new()
	photo.history_enabled = false
	photo.mode_memory = Memory.new(folder.path_join("modes"))
	root.add_child(photo)
	var camera := Camera3D.new()
	camera.position.y = 1.6
	root.add_child(camera)
	photo.view_camera = camera
	photo.flat_pose.origin = Vector3(0, 1.6, -3)
	photo.open_image(str(entries[0].uri), "00.png", entries)
	await settle(photo)
	check(
		photo.gallery.mode == 0 and photo.panel.visible and photo.gallery.cards.is_empty(),
		"Single mode retains the original surface"
	)
	photo.set_layout_mode(1)
	await load_previews(photo)
	check(
		photo.gallery.cards.size() == 6 and photo.panel.visible,
		"Side layout retains a full central photo and six distinct previews"
	)
	check(
		photo.gallery.cards.has(95) and photo.gallery.cards.has(1),
		"Side previews wrap in directory order"
	)
	for index in photo.gallery.cards:
		var size: Vector2 = photo.gallery.cards[index].size
		var texture: Texture2D = photo.gallery.previews.texture(str(entries[index].uri))
		check(
			absf(size.x / size.y - float(texture.get_width()) / texture.get_height()) < 0.01,
			"Side layout keeps each source aspect ratio"
		)
	photo.set_screen_scale(4.0)
	await load_previews(photo)
	check(
		photo.gallery.cards.values().all(func(card): return card.node.visible),
		"Enlarging the main photo never hides the side rail"
	)
	for card in photo.gallery.cards.values():
		var direction: Vector3 = card.pose.origin - photo.gallery.anchor.origin
		check(
			absf(atan2(direction.x, -direction.z)) < 0.7,
			"Side rail stays within the user's front view after enlargement"
		)
	photo.set_screen_scale(1.0)
	photo.set_layout_mode(2)
	await load_previews(photo)
	check(
		(
			not photo.panel.visible
			and photo.gallery.cards.has(0)
			and photo.gallery.cards.has(95)
			and photo.gallery.cards.has(1)
		),
		"Wall overview includes first, real last and second images"
	)
	check(
		photo.gallery.cards[95].pose.origin.x < 0 and photo.gallery.cards[1].pose.origin.x > 0,
		"First photo's left neighbour is the directory last"
	)
	for count in [2, 3]:
		photo.gallery.set_wall_rows(count)
		await load_previews(photo)
		var levels := {}
		var indices: Array = photo.gallery.cards.keys()
		indices.sort()
		for slot in indices.size():
			check(indices[slot] == slot, "Multi-row wall uses a contiguous directory group")
		for card in photo.gallery.cards.values():
			var local: Vector3 = photo.gallery.anchor.affine_inverse() * card.pose.origin
			levels[snappedf(local.y, 0.001)] = true
			check(
				absf(local.y) + card.size.y * 0.5 < 1.3,
				"Rows stay within a gaze-centered vertical budget"
			)
		check(levels.size() == count, "All selected rows are populated")
		var config := ConfigFile.new()
		photo.gallery.save_settings(config)
		var restored := Photo.Gallery.new()
		restored.restore_settings(config)
		check(restored.wall_rows == count, "Wall row count survives settings restoration")
		restored.free()
	photo.gallery.set_wall_rows(1)
	await load_previews(photo)
	var wall_poses := {}
	for index in photo.gallery.cards:
		wall_poses[index] = photo.gallery.cards[index].pose
	var wall_anchor: Transform3D = photo.gallery.anchor
	photo.gallery.activate(1)
	await settle(photo)
	photo.gallery._process(1)
	camera.rotation.y = 0.7
	photo.gallery.return_focus()
	photo.gallery._process(1)
	check(
		(
			photo.gallery.anchor.is_equal_approx(wall_anchor)
			and photo.gallery.cards.keys() == wall_poses.keys()
		),
		"Closing a wall exhibit preserves the original window after a head turn"
	)
	for index in wall_poses:
		check(
			photo.gallery.cards[index].pose.is_equal_approx(wall_poses[index]),
			"Wall exhibits return to the same physical slots"
		)
	camera.rotation.y = 0
	var normal_count: int = photo.gallery.cards.size()
	photo.gallery.set_view_scale(2)
	await load_previews(photo)
	check(
		photo.gallery.cards.size() < normal_count,
		"Wall enlarging reduces exhibits instead of scaling the ring radius"
	)
	for card in photo.gallery.cards.values():
		check(is_equal_approx(card.size.y, 2.1), "Wall uses a shared image height")
	photo.gallery.set_view_scale(1)
	photo.gallery.set_view_distance(1.5)
	await load_previews(photo)
	var close_count: int = photo.gallery.cards.size()
	photo.gallery.set_view_distance(6.0)
	await load_previews(photo)
	check(
		photo.gallery.cards.size() > close_count,
		"Wall distance expands the ring capacity without enlarging the photos"
	)
	check(
		photo.gallery.cards.values().all(
			func(card): return is_equal_approx( card.pose.origin.distance_to(photo.gallery.anchor.origin), 6.0 )
		),
		"Wall distance applies to every exhibit"
	)
	photo.gallery.set_view_distance(4.0)
	await load_previews(photo)
	var group_centre: int = photo.gallery._wall_start
	var group_nodes: Array = photo.gallery.cards.keys()
	check(photo.gallery.change_batch(1), "A circular wall can advance to the next ordered group")
	photo.gallery._process(0.23)
	await settle(photo)
	await load_previews(photo)
	photo.gallery._process(1)
	check(
		photo.index != group_centre and photo.gallery.cards.keys() != group_nodes,
		"Wall batch advances directory order and replaces its visible window"
	)
	check(photo.gallery.change_batch(-1), "Wall group navigation has a matching previous action")
	photo.gallery._process(0.23)
	await settle(photo)
	await load_previews(photo)
	photo.gallery._process(1)
	check(
		photo.index == group_centre and photo.gallery.cards.keys() == group_nodes,
		"Previous group restores the actual earlier window despite adaptive card counts"
	)
	var initial: Transform3D = photo.gallery.cards[0].pose
	var ray: Vector3 = (initial.origin - camera.position).normalized()
	check(
		photo.gallery.press_pointer("left_hand", camera.position, ray),
		"Wall ray can capture a photo"
	)
	photo.gallery.cancel_pointer("left_hand")
	photo.gallery.release_pointer("left_hand", camera.position, ray)
	check(photo.gallery.focus == -1, "Tracking cancellation never becomes a photo click")
	photo.set_layout_mode(3)
	await load_previews(photo)
	check(
		photo.gallery.cards.size() > 20,
		"Default fragments are denser than the original twenty-card limit"
	)
	var widths: Array = photo.gallery.cards.values().map(func(card): return card.size.x)
	check(widths.max() / widths.min() > 1.4, "Memories retain visibly different sizes")
	photo.gallery.set_view_scale(2.0)
	await load_previews(photo)
	var large_count: int = photo.gallery.cards.size()
	photo.gallery.set_view_scale(1.0)
	photo.gallery.set_view_distance(6)
	await load_previews(photo)
	check(photo.gallery.cards.size() > large_count, "Fragment count adapts to size and distance")
	photo.gallery.set_view_distance(3.6)
	await load_previews(photo)
	var card_index: int = photo.gallery.cards.keys()[2]
	var original: Dictionary = photo.gallery.cards[card_index].duplicate()
	var saved_poses := {}
	for index in photo.gallery.cards:
		saved_poses[index] = photo.gallery.cards[index].pose
	check(
		photo.gallery.cards.values().all(func(card): return card.pose.origin.y > camera.position.y),
		"Fragments occupy the upper space"
	)
	check(
		photo.gallery.cards.values().any(func(card): return card.shape != Photo.Gallery.RECT),
		"Fragments have actual irregular mesh silhouettes"
	)
	photo.gallery.activate(card_index)
	await settle(photo)
	photo.gallery._process(1.0)
	check(
		photo.panel.visible and photo.index == card_index and photo.gallery.progress == 1,
		"Fragment expands to the complete existing photo surface"
	)
	check(
		photo.gallery.cards[card_index].shown_shape == Photo.Gallery.RECT,
		"Expanded fragment exposes the complete rectangular composition"
	)
	var focus_pose: Transform3D = photo.gallery.focus_pose
	camera.position.x += 0.3
	camera.rotation.y = 0.4
	photo.gallery._process(0.1)
	check(
		photo.gallery.focus_pose.is_equal_approx(focus_pose),
		"Turning the head does not reshuffle or move a focused photo"
	)
	photo.gallery.return_focus()
	photo.gallery._process(1.0)
	check(
		photo.gallery.focus == -1 and not photo.panel.visible,
		"Second click/return closes the complete photo"
	)
	check(
		(
			photo.gallery.cards[card_index].pose.is_equal_approx(original.pose)
			and photo.gallery.cards[card_index].shape == original.shape
		),
		"Return restores the exact fragment location and silhouette"
	)
	for index in saved_poses:
		check(
			photo.gallery.cards[index].pose.is_equal_approx(saved_poses[index]),
			"Other memories keep their original positions"
		)
	var aim: Vector3 = (photo.gallery.cards[card_index].pose.origin - camera.position).normalized()
	photo.gallery.press_pointer("left_hand", camera.position, aim)
	photo.gallery.update_pointer("left_hand", camera.position, aim.rotated(Vector3.UP, 0.2))
	photo.gallery.release_pointer("left_hand", camera.position, aim)
	check(photo.gallery.focus == -1, "A dragged fragment does not click when released")
	var old_batch: Array = photo.gallery.cards.keys()
	var old_shapes: Array = photo.gallery.cards.values().map(func(card): return card.pose)
	check(photo.gallery.shuffle_fragments(), "Overview can request a fresh memory batch")
	check(not photo.gallery.shuffle_fragments(), "A running swap cannot queue repeated batches")
	photo.gallery._process(0.11)
	check(
		(
			photo.gallery._swap_alpha > 0
			and photo.gallery._swap_alpha < 1
			and photo.gallery.cards.keys() == old_batch
		),
		"Old memories visibly fade before replacement"
	)
	photo.gallery._process(0.12)
	await load_previews(photo)
	photo.gallery._process(1.0)
	check(
		photo.gallery.cards.keys().all(func(index): return index not in old_batch),
		"A large album prefers previously unseen memories"
	)
	check(
		photo.gallery.cards.values().map(func(card): return card.pose) != old_shapes,
		"New batch randomizes its arrangement and shape"
	)
	check(
		photo.gallery._swap_phase == 0 and photo.gallery._swap_alpha == 1,
		"New memories finish appearing"
	)
	photo.set_layout_mode(0)
	check(
		photo.panel.visible and photo.gallery.cards.is_empty(),
		"Switching back preserves the current photo in single mode"
	)
	photo.set_layout_mode(2)
	photo.gallery._process(0.01)
	photo.set_layout_mode(1)
	check(
		photo.panel.visible,
		"Switching from wall overview to side previews restores the central image"
	)
	photo.set_layout_mode(0)
	photo.close_image()
	check(
		photo.gallery.previews._textures.is_empty() and not photo.directory.loading,
		"Closing releases previews and cancels directory scanning"
	)
	photo.open_image(str(entries[0].uri), "00.png", entries.slice(0, 2))
	await settle(photo)
	photo.set_layout_mode(2)
	await load_previews(photo)
	check(photo.gallery.cards.size() == 2, "A two-photo wall contains no duplicate fillers")
	photo.queue_complete = false
	photo.gallery._signature = ""
	photo.gallery._reflow = true
	photo.gallery._process(0.01)
	check(
		not photo.snapshot().can_previous,
		"Incomplete directory cannot pretend its current page is a circular album"
	)
	photo.queue_free()
	camera.queue_free()
	await process_frame
	await _directory_checks()
	await _directory_reindex_checks()
	await _input_checks()
	for failure in failures:
		push_error(failure)
	print("Photo layouts: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)


func _directory_checks() -> void:
	var directory := Directory.new()
	var cloud := Cloud.new()
	directory.platform = cloud
	root.add_child(directory)
	var results := []
	directory.completed.connect(
		func(items, complete, error):
			results.append({"items": items, "complete": complete, "error": error})
	)
	directory.start({"path": "cloud://account/folder", "order": "name_asc"})
	directory.receive(
		1,
		JSON.stringify(
			{
				"state": "ready",
				"path": "cloud://account/folder",
				"order": "name_asc",
				"offset": 0,
				"next_offset": 48,
				"entries": [entries[0], {"uri": "file://movie.mp4", "title": "movie.mp4"}]
			}
		)
	)
	check(
		results.is_empty() and cloud.requests[1].offset == 48,
		"Directory metadata continues beyond the opened page"
	)
	directory.receive(
		2,
		JSON.stringify(
			{
				"state": "ready",
				"path": "cloud://account/folder",
				"order": "name_asc",
				"offset": 48,
				"next_offset": -1,
				"entries": [entries[0], entries[35]]
			}
		)
	)
	check(
		(
			results.size() == 1
			and results[0].complete
			and results[0].items.size() == 2
			and results[0].items.back().uri == entries[35].uri
		),
		"Complete directory keeps the true tail, filters videos and deduplicates items"
	)
	directory.start({"path": "cloud://account/other", "order": "name_desc"})
	directory.receive(2, "{}")
	check(directory.loading, "Late old-page responses are ignored")
	directory.receive(
		3,
		JSON.stringify(
			{"state": "ready", "path": "cloud://account/wrong", "order": "name_desc", "offset": 0}
		)
	)
	check(
		not directory.loading and not results.back().complete,
		"Wrong-folder page never completes a captured album"
	)
	directory.start({"path": "cloud://account/other", "order": "name_desc"})
	directory.cancel()
	check(cloud.cancelled.has(4), "Leaving an album cancels its pending page request")
	directory.queue_free()
	await process_frame


func _input_checks() -> void:
	var app := Harness.new()
	app.settings_path = folder.path_join("app.cfg")
	root.add_child(app)
	app.set_process(false)
	app.recent_menu.dismiss()
	app.photo.history_enabled = false
	app.photo.mode_memory = Memory.new(folder.path_join("input_modes"))
	app.photo_active = true
	app.player_menu = app.photo_menu
	app.photo.open_image(str(entries[0].uri), "00.png", entries)
	await settle(app.photo)
	app._on_photo_action("photo_layout_3")
	app.photo_menu.dismiss()
	app.photo.gallery._process(0.01)
	app.photo_menu.toggle()
	app.photo_menu._activate(app.photo_menu.PHOTO_ADJUST)
	check(
		(
			app.photo_menu._adjust_rows.size() == 2
			and app.photo_menu._adjust_rows[450].key == "gallery_scale"
		),
		"Overview adjustment changes the whole layout, without hidden main-photo controls"
	)
	app._on_photo_adjustment("gallery_scale", 1.2)
	check(
		is_equal_approx(app.photo.gallery.view_scale, 1.2) and app.photo.screen_scale == 1.0,
		"Gallery size adjustment preserves the separate single-photo size"
	)
	app._on_photo_adjustment("gallery_distance", 5.0)
	check(
		app.photo.gallery.view_distance == 5.0 and app.photo.screen_distance == 3.0,
		"Overview distance does not overwrite the independent single-photo distance"
	)
	app._on_photo_adjustment("gallery_scale", 1.0)
	app.photo_menu._activate(app.photo_menu.PHOTO_ADJUST_BACK)
	app.photo_menu.dismiss()
	app.photo.gallery._process(0.01)
	var index: int = app.photo.gallery.cards.keys()[0]
	var origin: Vector3 = app.xr_camera.global_position
	var direction: Vector3 = (app.photo.gallery.cards[index].pose.origin - origin).normalized()
	app.rays["left_hand"] = [origin, direction]
	app.photo.gallery.update_pointer("left_hand", origin, direction)
	check(
		(
			app.photo.gallery._pointers.left_hand.line.visible
			and app.photo.gallery._pointers.left_hand.dot.visible
		),
		"Gallery provides a ray and endpoint for bare-hand targeting"
	)
	check(app.photo.gallery.cards[index].rim.visible, "Targeted irregular silhouette is outlined")
	app._on_pointer_button("trigger_click", "left_hand")
	check(
		app.photo.gallery.has_capture() and app._grab.is_empty(),
		"Main routes a fragment trigger to the gallery before screen dragging"
	)
	app._process_sticks(Vector2.ZERO, Vector2(0, 1), 0.1)
	check(app.photo.gallery.view_scale == 1, "Pointer capture suppresses stick shortcuts")
	app._on_pointer_release("trigger_click", "left_hand")
	app.photo.gallery._process(1.0)
	check(app.photo.gallery.focus == index, "Main release expands the selected fragment")
	app.photo_menu.toggle()
	app.photo_menu._activate(app.photo_menu.PHOTO_ADJUST)
	check(
		(
			app.photo_menu._adjust_rows[450].key == "screen_distance"
			and app.photo_menu._adjust_rows[451].key == "screen_scale"
		),
		"Expanded memory exposes full-photo distance and scale controls"
	)
	app._on_photo_adjustment("screen_scale", 1.5)
	app.photo.gallery._process(1)
	check(
		is_equal_approx(app.photo._flat.size.x, app.photo._screen_base.x * 1.5),
		"Expanded memory size survives gallery refresh"
	)
	app._on_photo_adjustment("screen_distance", 2.2)
	app.photo.gallery._process(1)
	check(
		is_equal_approx(
			app.photo.panel.global_position.distance_to(app.xr_camera.global_position), 2.2
		),
		"Expanded memory distance survives gallery refresh"
	)
	app.photo_menu.dismiss()
	var zoom_inputs := {
		"left_hand":
		{
			"source": "hand",
			"tracked": true,
			"down": true,
			"pressed": true,
			"position": Vector3(-0.15, 1.2, -0.5)
		},
		"right_hand":
		{
			"source": "hand",
			"tracked": true,
			"down": true,
			"pressed": true,
			"position": Vector3(0.15, 1.2, -0.5)
		}
	}
	app._dispatch_hand_input(zoom_inputs)
	zoom_inputs.left_hand.pressed = false
	zoom_inputs.right_hand.pressed = false
	zoom_inputs.left_hand.position.x = -0.20
	zoom_inputs.right_hand.position.x = 0.20
	app._dispatch_hand_input(zoom_inputs)
	check(
		is_equal_approx(app.photo.screen_scale, 2.0) and app.photo.gallery.focus == index,
		"Two pinches scale the opened memory instead of being swallowed by card selection"
	)
	zoom_inputs.left_hand.down = false
	zoom_inputs.right_hand.down = false
	zoom_inputs.left_hand.released = true
	zoom_inputs.right_hand.released = true
	app._dispatch_hand_input(zoom_inputs)
	app.photo.set_screen_scale(1)

	app._on_photo_adjustment("screen_distance", 4.0)
	check(
		is_equal_approx(
			app.photo.gallery.focus_pose.origin.distance_to(app.xr_camera.global_position), 4.0
		),
		"Expanded photo retains existing distance adjustments instead of snapping back"
	)
	app._show_player_menu()
	app._on_pointer_button("trigger_click", "left_hand")
	app._on_pointer_release("trigger_click", "left_hand")
	check(app.photo.gallery.focus == index, "Visible photo controls isolate gallery selection")
	app.photo_menu._activate(app.photo_menu.PHOTO_LAYOUT)
	check(
		(
			app.photo_menu._layout_open
			and app.photo_menu._buttons.any(
				func(button): return button.target == app.photo_menu.PHOTO_LAYOUT_BASE + 3
			)
		),
		"Four short layout tiles are available through the ray menu"
	)
	var current: Dictionary = app.photo_menu._buttons.filter(func(button): return button.target == app.photo_menu.PHOTO_LAYOUT_BASE + 3)[0]
	app.photo_menu._update_highlights()
	check(
		(
			current.base_color == app.photo_menu.SELECTED
			and (
				current.node.material_override.get_shader_parameter("surface_color")
				== app.photo_menu.SELECTED
			)
		),
		"Current layout survives hover refresh and has a permanent selection mark"
	)
	var layout_button: Dictionary = app.photo_menu._buttons.filter(func(button): return button.target == app.photo_menu.PHOTO_LAYOUT)[0]
	check(
		layout_button.base_color.a == 1.0,
		"Layout action uses the same solid round tile as adjacent actions"
	)
	app.photo_menu._activate(app.photo_menu.PHOTO_LAYOUT_BASE)
	check(
		app.photo.gallery.mode == 0 and app.photo.panel.visible,
		"Ray menu can return to existing single mode"
	)
	app._on_photo_action("photo_layout_1")
	app.photo_menu.dismiss()
	await load_previews(app.photo)
	var side_pose: Transform3D = app.photo.flat_pose
	var side_anchor: Transform3D = app.photo.gallery.anchor
	app._screen_uri = app.photo.local_uri
	app.photo.placement_pending = false
	app._head_placed = true
	app.xr_camera.rotation.y = 0.8
	var side_index: int = app.photo.gallery.cards.keys()[0]
	app.photo.gallery.activate(side_index)
	await settle(app.photo)
	app.photo.finish_transition()
	app._process(0.016)
	check(
		(
			app.photo.flat_pose.is_equal_approx(side_pose)
			and app.photo.gallery.anchor.is_equal_approx(side_anchor)
		),
		"Selecting a side image while looking sideways never recenters the main frame"
	)
	app.xr_camera.rotation.y = 0
	app._on_photo_action("photo_layout_3")
	app.photo_menu.dismiss()
	await load_previews(app.photo)
	app.photo.gallery.activate(app.photo.gallery.cards.keys()[0])
	await settle(app.photo)
	app.photo.gallery._process(1)
	app._on_photo_action("photo_layout_1")
	await load_previews(app.photo)
	check(
		app.photo.gallery.cards.values().all(
			func(card): return card.node.material_override.get_shader_parameter("brightness") == 1.0
		),
		"Reused side previews never retain the dimming from an opened fragment"
	)
	app._on_photo_action("photo_layout_2")
	app._on_photo_adjustment("gallery_scale", 1.4)
	app._on_photo_adjustment("gallery_distance", 6.2)
	app._save_photo_adjustments()
	app.photo_menu.dismiss()
	await load_previews(app.photo)
	var input := {
		"left_hand":
		{
			"source": "hand",
			"tracked": true,
			"down": true,
			"pressed": true,
			"position": Vector3(-0.15, 1.2, -0.5)
		},
		"right_hand":
		{
			"source": "hand",
			"tracked": true,
			"down": true,
			"pressed": true,
			"position": Vector3(0.15, 1.2, -0.5)
		}
	}
	app._dispatch_hand_input(input)
	check(
		app.photo.gallery.has_capture() and app.photo.gallery.capture.is_empty(),
		"Two pinches replace a single ray capture with shared scale ownership"
	)
	input.left_hand.pressed = false
	input.right_hand.pressed = false
	input.left_hand.position.x = -0.21
	input.right_hand.position.x = 0.21
	app._dispatch_hand_input(input)
	check(
		is_equal_approx(app.photo.gallery.view_scale, 1.96) and app.photo.gallery.focus == -1,
		"Spreading two hands scales the wall without opening a photo"
	)
	input.left_hand.down = false
	input.left_hand.released = true
	app._dispatch_hand_input(input)
	check(
		app.photo.gallery.has_capture(),
		"One remaining pinch cannot become a new single-photo click"
	)
	input.right_hand.down = false
	input.right_hand.released = true
	app._dispatch_hand_input(input)
	check(
		not app.photo.gallery.has_capture() and app.photo.gallery.focus == -1,
		"Dual-pinch releases complete once and never click"
	)
	var cfg := ConfigFile.new()
	check(cfg.load(app.settings_path) == OK, "Mode and layout transforms are written to disk")
	var restored := Photo.new()
	restored.restore_view_settings(cfg)
	check(
		(
			restored.gallery.mode == 2
			and is_equal_approx(restored.gallery.view_scale, 1.96)
			and is_equal_approx(restored.gallery.view_distance, 6.2)
		),
		"A fresh photo viewer restores last mode, size and distance"
	)
	restored.gallery.set_mode(3)
	check(
		restored.gallery.view_scale == 1 and restored.gallery.view_distance == 5.0,
		"Each layout restores its own transform when switching modes"
	)
	restored.free()
	app.photo.gallery._process(0.01)
	app.photo_menu.toggle()
	check(
		app.photo_menu._buttons.any(
			func(button): return button.target == app.photo_menu.PHOTO_SHUFFLE and button.enabled
		),
		"Wall has an explicit next-group toolbar action"
	)
	check(
		app.photo_menu._tips[app.photo_menu.PHOTO_NEXT] == app.photo_menu.I18n.t("Next group"),
		"Wall arrows clearly identify group navigation"
	)
	app.photo_menu._activate(app.photo_menu.PHOTO_NEXT)
	check(
		app.photo.gallery._swap_phase == 1,
		"Production menu arrows page the wall instead of advancing one image"
	)
	app.queue_free()
	await process_frame


func _directory_reindex_checks() -> void:
	var photo := Photo.new()
	photo.history_enabled = false
	photo.mode_memory = Memory.new(folder.path_join("reindex_modes"))
	root.add_child(photo)
	photo.open_image(str(entries[15].uri), "15.png", entries.slice(10, 20))
	await settle(photo)
	photo.queue_complete = false
	photo.set_layout_mode(3)
	photo.gallery._process(0.01)
	var original: Transform3D = photo.gallery.cards[5].pose
	photo.gallery.activate(5)
	photo.gallery._process(1.0)
	photo._directory_result = {"entries": entries.duplicate(true), "complete": true, "error": ""}
	photo._replace_directory()
	photo.gallery._process(0.01)
	check(
		photo.index == 15 and photo.gallery.focus == 15 and photo.local_uri == entries[15].uri,
		"Completing a directory reindexes by URI without changing the focused image"
	)
	photo.gallery.return_focus()
	photo.gallery._process(1.0)
	check(
		photo.gallery.cards[15].pose.is_equal_approx(original),
		"Index completion during focus preserves the original fragment return location"
	)
	photo.queue_free()
	await process_frame
