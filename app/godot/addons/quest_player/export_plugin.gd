@tool
extends EditorPlugin

var android_export: QuestPlayerExport


func _enter_tree() -> void:
	android_export = QuestPlayerExport.new()
	add_export_plugin(android_export)


func _exit_tree() -> void:
	remove_export_plugin(android_export)
	android_export = null


class QuestPlayerExport:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "QuestPlayer"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(
			[
				(
					"res://addons/quest_player/bin/player-plugin-%s.aar"
					% ("debug" if debug else "release")
				),
				"res://addons/quest_player/bin/cloudcore.aar"
			]
		)

	func _get_android_dependencies(
		_platform: EditorExportPlatform, _debug: bool
	) -> PackedStringArray:
		# The AAR embeds jcifs without the unused HTTP NTLM adapters. Resolve only
		# its unchanged runtime dependencies here, never the original full jcifs jar.
		var manifest := "res://addons/quest_player/bin/dependencies.json"
		if not FileAccess.file_exists(manifest):
			push_error("Configure the Android workflow before exporting")
			return PackedStringArray()
		var dependencies: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if not dependencies is Array:
			push_error("Invalid Android dependency manifest")
			return PackedStringArray()
		return PackedStringArray(dependencies)
