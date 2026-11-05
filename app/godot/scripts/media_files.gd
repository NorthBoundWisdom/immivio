extends RefCounted
## Source adapters enumerate videos. Also reject unsupported legacy/history rows
## and stale selections before they can reach the video decoder.
const UNSUPPORTED := ["jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "bmp", "tif", "tiff", "avif", "jxl", "mp3", "m4a", "wav", "flac", "ogg", "txt", "pdf", "srt", "ass", "ssa", "vtt"]


static func is_video(uri: String, title: String = "", kind: String = "video") -> bool:
	if kind != "video":
		return false
	for value in [uri, title]:
		var name: String = value.get_slice("?", 0).get_slice("#", 0).uri_decode()
		if name.get_extension().to_lower() in UNSUPPORTED:
			return false
	return not uri.is_empty()
