extends SceneTree
## Verify the pinned font bytes and the same SystemFont lookup used by the UI.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected prepared font specifications")
		quit(1)
		return
	var specs: Variant = JSON.parse_string(args[0])
	if not specs is Array or specs.is_empty():
		push_error("Invalid prepared font specifications")
		quit(1)
		return
	for spec in specs:
		var family := str(spec.family)
		var bytes := FileAccess.get_file_as_bytes(str(spec.path))
		print(
			"Checking host font ",
			family,
			": ",
			bytes.size(),
			" bytes; system path=",
			OS.get_system_font_path(family)
		)
		var file := FontFile.new()
		file.data = bytes
		var system := SystemFont.new()
		system.font_names = PackedStringArray([family])
		for font in [file, system]:
			if not font.has_char("A".unicode_at(0)) or not font.has_char("播".unicode_at(0)):
				push_error("Prepared font lacks Latin/CJK coverage: " + family)
				quit(1)
				return
	print("IMMIVIO_HOST_FONTS_OK")
	quit(0)
