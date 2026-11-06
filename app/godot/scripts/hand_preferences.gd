extends RefCounted
## Primary-hand policy adapted from upstream ControllerBindings, without importing rebinding.
const DEFAULT := "right_hand"
const CHOICES := ["left_hand", "right_hand", "both"]


static func normalize(value: Variant) -> String:
	return str(value) if value is String and value in CHOICES else DEFAULT


static func allows(hand: String, choice: String) -> bool:
	return hand in ["left_hand", "right_hand"] and (choice == "both" or hand == choice)
