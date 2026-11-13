extends RefCounted
## The existing license wrapping and two-line row format, independent of account editing.
var lines: Array[String] = []


func clear() -> void:
	lines.clear()


func load_text(text: String, font: Font) -> void:
	for original in text.split("\n"):
		var line := ""
		for c in original:
			if (
				(font.get_string_size(line + c, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x * 0.0012)
				> 1.12
			):
				lines.append(line)
				line = ""
			line += c
		lines.append(line)


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(0, lines.size(), 2):
		result.append(
			{
				"title": lines[i],
				"detail": lines[i + 1] if i + 1 < lines.size() else "",
				"icon": "info",
				"about_info": true
			}
		)
	return result
