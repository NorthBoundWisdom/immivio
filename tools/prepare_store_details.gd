extends SceneTree
## Deterministic store detail cards using actual emulator captures, not generated UI.
## godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 \
##   --path app/godot --script ../../tools/prepare_store_details.gd
const SIZE := Vector2i(2560, 1440)
const BASE := "res://../../branding/pico/details/"
const ACCENT := Color("77e4db")
const INK := Color("f4f7fc")
const MUTED := Color("a8b9cf")
var viewport: SubViewport
var page: Control
var font: Font
var bold: Font
var failed := false
const CARDS := [
	{"file": "01-playback", "zh_title": "你的影院\n随处开场", "en_title": "Your cinema.\nYour space.",
	 "zh_body": "从平面大屏到 180°、360°全景，\n按影片选择喜欢的观看方式。",
	 "en_body": "From a virtual screen to 180° and 360° video, choose the view that fits your film.",
	 "zh_items": ["普通视频与 3D 立体视频", "倍速、进度与队列随手可调", "免费使用，无需订阅"],
	 "en_items": ["Flat and 3D stereo video", "Speed, timeline and queue controls", "Free to use. No subscription."],
	 "crop": Rect2i(120, 0, 2320, 1392), "zh_label": "真实应用画面 · 播放控制", "en_label": "ACTUAL APP CAPTURE · PLAYBACK"},
	{"file": "02-media-sources", "zh_title": "你的片库\n一个入口", "en_title": "Your library.\nOne place.",
	 "zh_body": "本地文件、家庭共享与媒体服务器，\n在头显中直接浏览与播放。",
	 "en_body": "Browse local files, home shares and compatible media servers inside your headset.",
	 "zh_items": ["本地视频与文件夹", "SMB 共享与 DLNA 媒体库", "Emby、Jellyfin、Plex 等来源"],
	 "en_items": ["Local videos and folders", "SMB shares and DLNA libraries", "Emby, Jellyfin, Plex and more"],
	 "crop": Rect2i(500, 235, 1585, 1000), "zh_label": "真实应用画面 · 网络媒体", "en_label": "ACTUAL APP CAPTURE · NETWORK MEDIA"},
	{"file": "03-subtitles", "zh_title": "字幕位置\n由你决定", "en_title": "Captions.\nYour way.",
	 "zh_body": "让文字跟随你的观看习惯，\n为沉浸式视频选择合适的位置。",
	 "en_body": "Place text where it works for you, with flexible controls for immersive video.",
	 "zh_items": ["支持双语文字字幕", "调节字幕方向、位置与距离", "支持选择外挂文字字幕"],
	 "en_items": ["Bilingual text subtitles", "Direction, position and distance", "External text subtitle selection"],
	 "crop": Rect2i(500, 235, 1585, 1000), "zh_label": "真实应用画面 · VR 字幕", "en_label": "ACTUAL APP CAPTURE · VR SUBTITLES"},
	{"file": "04-display", "zh_title": "舒服的位置\n清楚的画面", "en_title": "Settle in.\nMake it yours.",
	 "zh_body": "调整窗口高度、显示质量和清晰度，\n把观影界面放在顺手的位置。",
	 "en_body": "Adjust window height, display quality and sharpness for a view that feels right.",
	 "zh_items": ["窗口高度自由调节", "显示质量与锐度选择", "播放条透明度可调"],
	 "en_items": ["Adjustable window height", "Quality and sharpness choices", "Control-bar opacity settings"],
	 "crop": Rect2i(500, 235, 1585, 1000), "zh_label": "真实应用画面 · 显示设置", "en_label": "ACTUAL APP CAPTURE · DISPLAY SETTINGS"}
]


func _initialize() -> void:
	_run.call_deferred()


func box(rect: Rect2, color: Color, radius: int = 0, border: Color = Color.TRANSPARENT) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(2 if border.a > 0 else 0)
	node.add_theme_stylebox_override("panel", style)
	page.add_child(node)
	return node


func text(value: String, rect: Rect2, size: int, color: Color = INK, heavy: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", bold if heavy else font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)
	return label


func image(picture: Image, rect: Rect2) -> void:
	var node := TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.texture = ImageTexture.create_from_image(picture)
	node.position = rect.position
	node.size = rect.size
	page.add_child(node)


func draw_card(card: Dictionary, locale: String, index: int) -> void:
	var zh := locale == "zh-CN"
	var key := "zh_" if zh else "en_"
	box(Rect2(Vector2.ZERO, Vector2(SIZE)), Color("071528"))
	# A soft radial wash echoes the turquoise/blue identity without obscuring UI.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("163b51"), Color("071528")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.72, .42)
	texture.fill_to = Vector2(1.4, 1.1)
	texture.width = 1280
	texture.height = 720
	var wash := TextureRect.new()
	wash.texture = texture
	wash.size = Vector2(SIZE)
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.add_child(wash)
	image(Image.load_from_file(ProjectSettings.globalize_path("res://../../website/assets/icon.png")), Rect2(112, 82, 84, 84))
	text("Immivio", Rect2(218, 78, 500, 90), 58, INK, true)
	text("VR VIDEO PLAYER", Rect2(112, 196, 650, 50), 26, ACCENT)
	text("%02d / 04" % index, Rect2(2250, 94, 200, 60), 28, MUTED)
	box(Rect2(112, 283, 72, 5), ACCENT, 2)
	text(card[key + "title"], Rect2(110, 328, 690, 256), 88 if zh else 82, INK, true)
	text(card[key + "body"], Rect2(116, 630, 630, 180), 33, MUTED)
	for i in card[key + "items"].size():
		var y: int = 891 + i * 93
		box(Rect2(116, y + 18, 9, 9), ACCENT, 4)
		text(card[key + "items"][i], Rect2(145, y, 610, 80), 29, INK)
	var source := ProjectSettings.globalize_path(BASE + "source/" + locale + "/" + card.file + ".png")
	var screenshot := Image.load_from_file(source)
	if screenshot == null or screenshot.get_size() != SIZE:
		push_error("Expected a 2560x1440 emulator capture: " + source)
		failed = true
		return
	var crop: Rect2i = card.crop
	var selected := screenshot.get_region(crop)
	box(Rect2(842, 296, 1606, 972), Color("000710"), 26, Color("31516b"))
	image(selected, Rect2(858, 312, 1574, 940))
	text(card[key + "label"], Rect2(864, 242, 1510, 44), 24, ACCENT)
	text("PICO / META QUEST     ·     FREE & OPEN SOURCE", Rect2(116, 1288, 1790, 46), 25, MUTED)
	var note := "Android 虚拟机实拍 · 画面已裁切缩放用于排版 · 以头显实际体验为准" if zh else "Actual Android emulator capture · Cropped/scaled for layout · Headset experience may vary"
	text(note, Rect2(116, 1352, 2330, 44), 21, Color("778da9"))


func _run() -> void:
	# Fail before writing any output if a source capture is missing or changed.
	var manifest_path := ProjectSettings.globalize_path(BASE + "capture.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("captures", []).size() != 8:
		push_error("Expected provenance for all eight emulator captures")
		quit(1)
		return
	for capture in manifest.captures:
		var path := ProjectSettings.globalize_path(BASE + str(capture.file))
		var source := Image.load_from_file(path)
		if source == null or source.get_size() != SIZE or FileAccess.get_sha256(path) != capture.sha256:
			push_error("Capture differs from its recorded source: " + path)
			quit(1)
			return
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	font = system
	var heading := SystemFont.new()
	heading.font_names = system.font_names
	heading.font_weight = 600
	var emphasis := FontVariation.new()
	emphasis.base_font = heading
	emphasis.variation_embolden = .3
	bold = emphasis
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for locale in ["zh-CN", "en"]:
		var directory := ProjectSettings.globalize_path(BASE + locale)
		DirAccess.make_dir_recursive_absolute(directory)
		for i in CARDS.size():
			page = Control.new()
			page.size = Vector2(SIZE)
			viewport.add_child(page)
			draw_card(CARDS[i], locale, i + 1)
			await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var result := viewport.get_texture().get_image()
			result.convert(Image.FORMAT_RGB8)
			var destination := directory.path_join(CARDS[i].file + ".jpg")
			if result.save_jpg(destination, .94) != OK:
				failed = true
				push_error("Unable to save detail JPEG")
			else:
				var data := FileAccess.get_file_as_bytes(destination)
				var decoded := Image.load_from_file(destination)
				if data.size() > 5_000_000 or data.size() < 2 or data[0] != 0xff or data[1] != 0xd8 or decoded == null or decoded.get_size() != SIZE:
					failed = true
					push_error("Detail image must be JPEG, 2560x1440 and <=5 MB")
			page.free()
	# A separate contact sheet is for local review; upload only the locale folders.
	var previews := ProjectSettings.globalize_path("res://../../artifacts/captures/branding/store-details")
	DirAccess.make_dir_recursive_absolute(previews)
	for locale in ["zh-CN", "en"]:
		var sheet := Image.create(2560, 1440, false, Image.FORMAT_RGB8)
		for index in CARDS.size():
			var thumb := Image.load_from_file(ProjectSettings.globalize_path(BASE + locale + "/" + CARDS[index].file + ".jpg"))
			thumb.convert(Image.FORMAT_RGB8)
			thumb.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(thumb, Rect2i(0, 0, 1280, 720), Vector2i((index % 2) * 1280, (index / 2) * 720))
		sheet.save_jpg(previews.path_join("overview-" + locale + ".jpg"), .92)
	print("Prepared 4 detail-page JPEGs per language at 2560x1440; sources are actual emulator captures")
	viewport.queue_free()
	quit(1 if failed else 0)
