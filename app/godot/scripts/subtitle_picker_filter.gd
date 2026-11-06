extends RefCounted
## Filename filtering adapted from Thru3D 9a6a905..da5f86c. No remote/cloud search.
const VIDEO_EXTENSIONS := [
	"mp4", "mkv", "mov", "avi", "webm", "m4v", "ts", "m2ts", "wmv", "mpg", "mpeg", "strm"
]


static func clean(value: String) -> String:
	var result := ""
	for character in value:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			result += character
	return result.left(128)


static func default_query(filename: String) -> String:
	if filename.contains("://"):
		return ""
	var name := filename.strip_edges().replace("\\", "/").get_file()
	if name.get_extension().to_lower() in VIDEO_EXTENSIONS:
		name = name.get_basename()
	return clean(name.strip_edges())


static func filter_rows(rows: Array, query: String) -> Array:
	var needle := clean(query).strip_edges().to_lower()
	if needle.is_empty():
		return rows.duplicate()
	return rows.filter(func(row): return str(row.get("title", "")).to_lower().contains(needle))
