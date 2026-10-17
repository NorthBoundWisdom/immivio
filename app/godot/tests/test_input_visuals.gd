extends SceneTree
const Visuals := preload("res://scripts/input_visuals.gd")
var failures: Array[String] = []
var checks := 0


class PlaybackMain:
	extends "res://scripts/main.gd"

	func _head_tracked() -> bool:
		return true

	func _controller_ray(hand: String) -> Variant:
		# Headless preview has no active runtime; use the synthetic tracked aim pose.
		var tracker := XRServer.get_tracker(hand) as XRPositionalTracker
		var pose := tracker.get_pose("aim") if tracker else null
		if pose == null or not pose.has_tracking_data:
			return null
		return [pose.transform.origin, -pose.transform.basis.z]


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var origin := XROrigin3D.new()
	root.add_child(origin)
	var visuals := Visuals.new()
	visuals.use_runtime_models = false
	origin.add_child(visuals)
	var controllers := []
	var trackers := []
	for side in ["left", "right"]:
		var controller := XRControllerTracker.new()
		controller.name = side + "_hand"
		controller.set_pose(
			"grip",
			Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.4)),
			Vector3.ZERO,
			Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH
		)
		controller.set_pose(
			"aim",
			Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.6)),
			Vector3.ZERO,
			Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH
		)
		XRServer.add_tracker(controller)
		controllers.append(controller)
		var tracker := XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = (
			XRPositionalTracker.TRACKER_HAND_LEFT
			if side == "left"
			else XRPositionalTracker.TRACKER_HAND_RIGHT
		)
		tracker.has_tracking_data = false
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	await process_frame
	visuals.update_visibility(true)
	for hand in visuals.hands:
		var entry: Dictionary = visuals.hands[hand]
		check(
			entry.controller_gate.visible and not entry.hand_gate.visible,
			hand + " shows controller only"
		)
		check(entry.grip.pose == "grip", "Model uses grip rather than ray aim")
		check(visuals._has_mesh(entry.fallback), "Runtime-free controller has geometry")
		var skeleton := visuals._find_skeleton(entry.hand_fallback)
		check(skeleton != null and skeleton.get_bone_count() >= 26, "Fallback hand is fully rigged")
		check(
			skeleton.get_child(skeleton.get_child_count() - 1) is XRHandModifier3D,
			"Fallback hand has tracked skeleton modifier"
		)
		check(visuals._has_mesh(entry.hand_fallback), "Fallback hand has skinned geometry")
	# Optical tracking wins even while emulated controller poses remain valid.
	trackers[1].has_tracking_data = true
	trackers[1].hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	visuals.update_visibility(true)
	check(
		(
			visuals.hands.right_hand.hand_gate.visible
			and not visuals.hands.right_hand.controller_gate.visible
		),
		"Optical hand suppresses controller duplicate"
	)
	check(visuals.hands.left_hand.controller_gate.visible, "Other hand ownership is independent")
	visuals.update_visibility(false)
	check(
		(
			not visuals.hands.left_hand.controller_gate.visible
			and not visuals.hands.right_hand.hand_gate.visible
		),
		"Lost focus hides both input sources"
	)
	trackers[1].has_tracking_data = false
	controllers[1].invalidate_pose("grip")
	visuals.update_visibility(true)
	check(
		(
			not visuals.hands.right_hand.hand_gate.visible
			and not visuals.hands.right_hand.controller_gate.visible
		),
		"Tracking loss hides stale geometry"
	)
	trackers[0].has_tracking_data = true
	trackers[0].hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	visuals.update_visibility(true)
	check(
		(
			visuals.hands.left_hand.controller_gate.visible
			and not visuals.hands.left_hand.hand_gate.visible
		),
		"Controller-inferred joints do not replace controller model"
	)
	# Runtime assets replace fallback only after actual mesh geometry is present.
	var runtime := Node3D.new()
	visuals.hands.left_hand.grip.add_child(runtime)
	visuals.hands.left_hand.ext = runtime
	visuals.update_visibility(true)
	check(visuals.hands.left_hand.fallback.visible, "Empty runtime scene retains fallback")
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	runtime.add_child(mesh)
	visuals.update_visibility(true)
	check(
		not visuals.hands.left_hand.fallback.visible and runtime.visible,
		"Loaded runtime geometry replaces fallback"
	)
	runtime.remove_child(mesh)
	mesh.free()
	visuals.update_visibility(true)
	check(visuals.hands.left_hand.fallback.visible, "Runtime removal restores fallback")
	# Synthetic tracking stays live while the real model gates time out.
	for i in controllers.size():
		trackers[i].has_tracking_data = false
		set_grip(controllers[i], Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.4)))
	await process_frame
	visuals.update_visibility(true)
	visuals.update_visibility(true, 2.8, true)
	check(visuals.hands.left_hand.controller_gate.visible, "Playback starts with a visible controller")
	visuals.update_visibility(true, 0.3, true)
	check(
		not visuals.hands.left_hand.controller_gate.visible
		and not visuals.hands.right_hand.controller_gate.visible,
		"Idle playback hides both controller models"
	)
	check(visuals._pose_tracked(visuals.hands.left_hand.grip), "Hidden model retains live tracking")
	for i in 4:
		set_grip(controllers[0], Transform3D(Basis.IDENTITY, Vector3(0.2 + (0.001 if i % 2 else -0.001), 1.3, -0.4)))
		await process_frame
		visuals.update_visibility(true, 0.5, true)
	check(not visuals.hands.left_hand.controller_gate.visible, "Tracking jitter does not wake a model")
	set_grip(controllers[1], Transform3D(Basis.IDENTITY, Vector3(0.24, 1.3, -0.4)))
	await process_frame
	visuals.update_visibility(true, 0.1, true)
	check(
		visuals.hands.right_hand.controller_gate.visible
		and not visuals.hands.left_hand.controller_gate.visible,
		"Moving a controller restores only that model"
	)
	visuals.update_visibility(true, 3.1, true)
	set_grip(controllers[0], Transform3D(Basis(Vector3.UP, deg_to_rad(12)), Vector3(0.2, 1.3, -0.4)))
	await process_frame
	visuals.update_visibility(true, 0.1, true)
	check(visuals.hands.left_hand.controller_gate.visible, "Rotating in place restores the model")
	visuals.update_visibility(true, 3.1, true)
	visuals.controller_activity("right_hand")
	visuals.update_visibility(true, 0.1, true)
	check(visuals.hands.right_hand.controller_gate.visible, "Explicit input restores an idle model")
	visuals.update_visibility(true, 10.0, true, true)
	check(
		visuals.hands.left_hand.controller_gate.visible and visuals.hands.right_hand.controller_gate.visible,
		"Menu interaction keeps both controllers visible"
	)
	visuals.update_visibility(true, 3.1, true)
	visuals.update_visibility(false, 0.1, true)
	visuals.update_visibility(true, 0.1, true)
	check(visuals.hands.left_hand.controller_gate.visible, "Regaining focus restarts the idle grace period")
	visuals.update_visibility(true, 10.0)
	check(visuals.hands.left_hand.controller_gate.visible, "Outside playback models do not time out")
	trackers[1].has_tracking_data = true
	trackers[1].hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	visuals.update_visibility(true, 10.0, true)
	check(visuals.hands.right_hand.hand_gate.visible, "Optical hand visibility is preserved")
	trackers[1].has_tracking_data = false
	await playback_checks()
	for tracker in controllers + trackers:
		XRServer.remove_tracker(tracker)
	origin.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Input visuals: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)


func set_grip(tracker: XRControllerTracker, pose: Transform3D) -> void:
	tracker.set_pose("grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func playback_checks() -> void:
	var app := PlaybackMain.new()
	app.settings_path = "user://controller-visibility.cfg"
	root.add_child(app)
	app.set_process(false)
	app.video.set_process(false)
	app.photo.set_process(false)
	app.display.preview = true
	app.video.local_uri = "file:///movie.mp4"
	app.video.panel.visible = true
	app.video.media.state = "playing"
	app.recent_menu.dismiss()
	app.player_menu.dismiss()
	await process_frame
	app._update_hand_input(0.0)
	app._update_hand_input(3.1)
	check(
		not app.input_visuals.hands.left_hand.controller_gate.visible,
		"Video state drives automatic hiding through the production input coordinator"
	)
	check(app._ray("left_hand") != null, "Hidden controller retains its aim ray")
	app._process_sticks(Vector2.ZERO, Vector2(0, 0.5), 0.016)
	app._update_hand_input(0.1)
	check(app.input_visuals.hands.right_hand.controller_gate.visible, "Stick deflection wakes its model")
	app._update_hand_input(3.1)
	app._on_controller_button("trigger_click", "left_hand")
	app._update_hand_input(0.1)
	check(
		app.input_visuals.hands.left_hand.controller_gate.visible and app._trigger_taps.has("left_hand"),
		"Trigger wakes a hidden controller and still reaches picture input"
	)
	app._on_controller_release("trigger_click", "left_hand")
	app._update_hand_input(10.0)
	check(
		app.player_menu.visible and app.input_visuals.hands.left_hand.controller_gate.visible,
		"Trigger release opens controls and keeps models visible"
	)
	app.player_menu.dismiss()
	app._update_hand_input(3.1)
	check(not app.input_visuals.hands.left_hand.controller_gate.visible, "Hiding resumes after controls close")
	app.video.local_uri = ""
	app._update_hand_input(10.0)
	check(app.input_visuals.hands.left_hand.controller_gate.visible, "Leaving video restores the controller")
	app.queue_free()
	await process_frame
