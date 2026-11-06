extends SceneTree
const Encoding := preload("res://scripts/file_subtitle_encoding.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	var key := "日本語.srt".sha256_text()
	var tracks := [
		{"id": 4, "title": "日本語.srt", "external": true, "encoding_key": key},
		{"id": 8, "title": "Embedded", "external": false}
	]
	assert(Encoding.row(tracks, 8, {}).is_empty())
	var row := Encoding.row(tracks, 4, {key: "windows-31j"})
	assert(row.value.encoding == "windows-31j")
	assert(Encoding.valid({key: "GB18030"}))
	assert(not Encoding.valid({key: "arbitrary-codec"}))
	var video := preload("res://scripts/mpv_video_display.gd").new()
	video.media.playback = {
		"details":
		{
			"subtitle_tracks":
			[
				{
					"id": 4,
					"codec": "subrip",
					"external": true,
					"title": "日本語.srt",
					"encoding_key": key
				}
			]
		}
	}
	assert(
		not video.set_subtitle_encoding({"track_key": "stale".sha256_text(), "encoding": "Big5"})
	)
	assert(video.set_subtitle_encoding({"track_key": key, "encoding": "Big5"}))
	assert(video.subtitle_encodings[key] == "Big5")
	var menu := preload("res://scripts/player_menu.gd").new()
	var invalid := {
		"id": 4, "title": "Caption", "external": true, "encoding_key": key, "encoding_invalid": true
	}
	assert(menu._subtitle_label(invalid).contains("Encoding invalid"))
	menu.free()
	video.free()
	var store := Memory.new("user://encoding-test")
	var mode := {
		"profile": "320x320",
		"geometry": 0,
		"stereo_sbs": false,
		"swap_eyes": false,
		"alpha_requested": false,
		"subtitle_encodings": {key: "Big5"}
	}
	assert(store.remember("file:///movie.mp4", mode))
	assert(store.save())
	var restored := Memory.new("user://encoding-test")
	restored.load_saved()
	assert(restored.lookup("file:///movie.mp4").subtitle_encodings[key] == "Big5")
	preload("res://tests/support/test_result.gd").finish(self, 0)
