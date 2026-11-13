extends RefCounted
## Replaceable scene/input boundary. Tests override this object, never the main scene.
const HandPointer := preload("res://scripts/hand_pointer.gd")
var _host_ref: WeakRef


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func input_focused() -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	return host.display.preview or host.display.session_state == "session_focussed"


func controller_allowed(hand: String) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	if not input_focused():
		return false
	# Query current data too: XR input signals may arrive before our process callback.
	return (
		not HandPointer.is_optical(_hand_tracker(hand))
		and not HandPointer.is_hand_profile(XRServer.get_tracker(hand) as XRPositionalTracker)
		and not (host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand")
	)


func controller_ray(hand: String) -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	var controller = host.left_controller if hand == "left_hand" else host.right_controller
	if not controller or not controller.get_is_active() or not controller.get_has_tracking_data():
		return null
	var pose = controller.get_pose()
	if not pose or pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_NONE:
		return null
	return [controller.global_position, -controller.global_basis.z]


func ray(hand: String) -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	if not input_focused():
		return null
	if host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand":
		return host.hand_pointers[hand].ray
	if HandPointer.is_optical(_hand_tracker(hand)):
		return null
	return controller_ray(hand)


func head_tracked() -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	var head = XRServer.get_tracker("head") as XRPositionalTracker
	if not head or not head.has_pose("default"):
		return false
	var pose = head.get_pose("default")
	return pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE


func active_menu() -> Node3D:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	if host.library_menu and host.library_menu.visible:
		return host.library_menu
	if host.player_menu and host.player_menu.visible:
		return host.player_menu
	return null


func recenter() -> void:
	var host := _host_ref.get_ref() as Node3D
	if is_instance_valid(host):
		host.presentation_coordinator.recenter()


func _hand_tracker(hand: String) -> XRHandTracker:
	return (
		XRServer.get_tracker("/user/hand_tracker/" + ("left" if hand == "left_hand" else "right"))
		as XRHandTracker
	)
