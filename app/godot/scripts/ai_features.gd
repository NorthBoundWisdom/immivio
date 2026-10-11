extends RefCounted
## Older plugins and desktop previews retain their existing behavior.
static func available(platform: Object = null) -> bool:
	if platform == null and Engine.has_singleton("QuestPlayer"):
		platform = Engine.get_singleton("QuestPlayer")
	if preload("res://scripts/platform_methods.gd").supports(platform, "ai_enabled"):
		return bool(platform.call("ai_enabled"))
	return true
