extends SceneTree
const Export := preload("res://addons/quest_player/export_plugin.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	var common: String = Export.QuestPlayerExport.application_entries(false)
	var pico: String = Export.QuestPlayerExport.application_entries(true)
	assert(
		(
			common.contains("ExternalPlaybackActivity")
			and common.contains("android.intent.action.VIEW")
			and common.contains("android.intent.action.SEND")
		)
	)
	assert(not common.contains("ImmivioLauncherActivity"))
	assert(pico.contains("ImmivioLauncherActivity"))
	var xml := XMLParser.new()
	assert(
		(
			xml.open_buffer(
				(
					(
						"<application xmlns:android='http://schemas.android.com/apk/res/android'>"
						+ pico
						+ "</application>"
					)
					. to_utf8_buffer()
				)
			)
			== OK
		)
	)
	var activities := 0
	while xml.read() == OK:
		if xml.get_node_type() == XMLParser.NODE_ELEMENT and xml.get_node_name() == "activity":
			activities += 1
	assert(activities == 2)
	var uri := "externalvideo://01234567/video"
	var memory := preload("res://scripts/file_mode_memory.gd").new()
	assert(memory.key_for(uri).is_empty())
	var recent := preload("res://scripts/recent_files.gd").new()
	assert(not recent.opened(uri, "External film", false))
	preload("res://tests/support/test_result.gd").finish(self, 0)
