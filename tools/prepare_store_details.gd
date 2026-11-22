extends SceneTree
## Deterministic store detail cards using actual emulator captures, not generated UI.
## godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 \
##   --path app/godot --script ../../tools/prepare_store_details.gd
const SIZE := Vector2i(2560, 1440)
const BASE := "res://../../branding/pico/details/"
# Card palette follows the in-app "Aurora" skin: deep navy, one sky-blue accent
# taken from the app icon, and a faint warm glow echoing the icon's play mark.
const BACKDROP := Color("070f1d")
const GLOW := Color("1d4f7c")
const WARM := Color("ffc48a")
const ACCENT := Color("74ccf7")
const INK := Color("f2f6fc")
const MUTED := Color("a3b3c9")
const DIM := Color("6f829d")
const CHIP := Color("1b3d5d")
const FRAME_LEFT := 872.0
const FRAME_WIDTH := 1560.0
var viewport: SubViewport
var page: Control
var font: Font
var bold: Font
var failed := false
const CARDS := [
	{
		"file": "01-playback",
		"zh_title": "你的影院\n随处开场",
		"en_title": "Your cinema.\nYour space.",
		"zh_body": "从平面大屏到 180°、360° 全景，\n按影片选择喜欢的观看方式。",
		"en_body":
		"From a virtual screen to 180° and 360° video, choose the view that fits your film.",
		"zh_items": ["平面视频与 3D 立体视频", "倍速、进度与队列随手可调", "免费使用，无需订阅"],
		"en_items":
		[
			"Flat and 3D stereo video",
			"Speed, timeline and queue controls",
			"Free to use. No subscription."
		],
		"crop": Rect2i(128, 80, 2304, 1296),
		"zh_label": "真实应用画面 · 播放控制",
		"en_label": "ACTUAL APP CAPTURE · PLAYBACK"
	},
	{
		"file": "02-media-sources",
		"zh_title": "你的片库\n一个入口",
		"en_title": "Your library.\nOne place.",
		"zh_body": "本地文件、家庭共享与媒体服务器，\n在头显中直接浏览与播放。",
		"en_body":
		"Browse local files, home shares and compatible media servers inside your headset.",
		"zh_items": ["本地视频与文件夹", "SMB 共享与 DLNA 媒体库", "Emby、Jellyfin、Plex 等来源"],
		"en_items":
		[
			"Local videos and folders",
			"SMB shares and DLNA libraries",
			"Emby, Jellyfin, Plex and more"
		],
		"crop": Rect2i(560, 290, 1480, 925),
		"zh_label": "真实应用画面 · 网络媒体",
		"en_label": "ACTUAL APP CAPTURE · NETWORK MEDIA"
	},
	{
		"file": "03-subtitles",
		"zh_title": "字幕位置\n由你决定",
		"en_title": "Captions.\nYour way.",
		"zh_body": "让文字跟随你的观看习惯，\n为沉浸式视频选择合适的位置。",
		"en_body": "Place text where it works for you, with flexible controls for immersive video.",
		"zh_items": ["支持双语文字字幕", "方向、位置与距离可调", "跟随视角与透明度设置"],
		"en_items":
		[
			"Bilingual text subtitles",
			"Direction, position and distance",
			"Follow view and transparency"
		],
		"crop": Rect2i(560, 290, 1480, 925),
		"zh_label": "真实应用画面 · VR 字幕",
		"en_label": "ACTUAL APP CAPTURE · VR SUBTITLES"
	},
	{
		"file": "04-display",
		"zh_title": "舒服的位置\n清楚的画面",
		"en_title": "Settle in.\nMake it yours.",
		"zh_body": "调整窗口高度、显示质量和锐度，\n躺着看也能把画面放在顺手的位置。",
		"en_body":
		"Adjust window height, display quality and sharpness, and keep the view right when you lie back.",
		"zh_items": ["窗口高度自由调节", "显示质量与锐度选择", "躺姿模式，躺着也能看"],
		"en_items":
		[
			"Adjustable window height",
			"Quality and sharpness choices",
			"Reclining mode for lying back"
		],
		"crop": Rect2i(560, 290, 1480, 925),
		"zh_label": "真实应用画面 · 显示设置",
		"en_label": "ACTUAL APP CAPTURE · DISPLAY SETTINGS"
	}
]


func _initialize() -> void:
	_run.call_deferred()


func style(
	color: Color, radius: int = 0, border: Color = Color.TRANSPARENT, width: int = 2
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(width if border.a > 0 else 0)
	box.anti_aliasing = true
	box.corner_detail = 16
	return box


func box(
	rect: Rect2,
	color: Color,
	radius: int = 0,
	border: Color = Color.TRANSPARENT,
	parent: Control = null
) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("panel", style(color, radius, border))
	(parent if parent else page).add_child(node)
	return node


func text(value: String, rect: Rect2, size: int, color: Color = INK, heavy: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", bold if heavy else font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)
	return label


func image(picture: Image, rect: Rect2, parent: Control = null) -> TextureRect:
	var node := TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture = ImageTexture.create_from_image(picture)
	node.position = rect.position
	node.size = rect.size
	(parent if parent else page).add_child(node)
	return node


func glow(centre: Vector2, radius: float, color: Color) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, Color(color, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5, .5)
	texture.fill_to = Vector2(1, .5)
	texture.width = 512
	texture.height = 512
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.position = centre - Vector2.ONE * radius
	node.size = Vector2.ONE * radius * 2
	page.add_child(node)


## Width of [value] at [size] in the regular face, for chips sized to their text.
func measure(value: String, size: int, heavy: bool = false) -> float:
	return (bold if heavy else font).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func draw_card(card: Dictionary, locale: String, index: int) -> void:
	var zh := locale == "zh-CN"
	var key := "zh_" if zh else "en_"
	box(Rect2(Vector2.ZERO, Vector2(SIZE)), BACKDROP)
	glow(Vector2(1660, 720), 1250, Color(GLOW, 0.62))
	glow(Vector2(140, 1420), 760, Color(WARM, 0.07))
	glow(Vector2(2500, 40), 620, Color(ACCENT, 0.06))
	# Brand row and eyebrow.
	image(
		Image.load_from_file(ProjectSettings.globalize_path("res://../../website/assets/icon.png")),
		Rect2(128, 104, 84, 84)
	)
	text("Immivio", Rect2(236, 106, 500, 80), 54, INK, true)
	var eyebrow := "VR 视频播放器" if zh else "VR VIDEO PLAYER"
	var eyebrow_width := measure(eyebrow, 24) + 48
	box(Rect2(128, 236, eyebrow_width, 48), Color(CHIP, 0.55), 24, Color(ACCENT, 0.35))
	text(eyebrow, Rect2(152, 241, eyebrow_width, 40), 24, ACCENT)
	text("%02d / 04" % index, Rect2(2232, 118, 200, 60), 28, DIM)
	# Headline, body and three features.
	text(card[key + "title"], Rect2(124, 340, 720, 300), 98 if zh else 88, INK, true)
	text(card[key + "body"], Rect2(130, 650, 640, 190), 33, MUTED)
	for i in card[key + "items"].size():
		var y: float = 880 + i * 104
		box(Rect2(130, y, 52, 52), Color(CHIP, 0.9), 16, Color(ACCENT, 0.28))
		box(Rect2(149, y + 19, 14, 14), ACCENT, 7)
		text(card[key + "items"][i], Rect2(206, y + 1, 600, 60), 31, INK)
	# Capture: rounded, framed and shadowed, never letterboxed.
	var source := ProjectSettings.globalize_path(
		BASE + "source/" + locale + "/" + card.file + ".png"
	)
	var screenshot := Image.load_from_file(source)
	if screenshot == null or screenshot.get_size() != SIZE:
		push_error("Expected a 2560x1440 emulator capture: " + source)
		failed = true
		return
	var crop: Rect2i = card.crop
	var selected := screenshot.get_region(crop)
	selected.resize(int(FRAME_WIDTH), roundi(FRAME_WIDTH * crop.size.y / crop.size.x), Image.INTERPOLATE_LANCZOS)
	var frame := Rect2(
		Vector2(FRAME_LEFT, roundf((SIZE.y - selected.get_height()) * .5) + 20),
		Vector2(selected.get_size())
	)
	var shadow := box(frame, Color.TRANSPARENT, 36)
	var shadow_style: StyleBoxFlat = shadow.get_theme_stylebox("panel")
	shadow_style.shadow_color = Color(0, 0, 0, .55)
	shadow_style.shadow_size = 70
	shadow_style.shadow_offset = Vector2(0, 28)
	var clip := box(frame, Color.BLACK, 36)
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	image(selected, Rect2(Vector2.ZERO, frame.size), clip)
	box(frame, Color.TRANSPARENT, 36, Color(1, 1, 1, .14))
	text(card[key + "label"], Rect2(FRAME_LEFT + 4, frame.position.y - 66, 1400, 44), 24, ACCENT)
	# Footer: platforms, licence and an honest capture note.
	text(
		"PICO  ·  META QUEST  ·  " + ("免费开源" if zh else "FREE & OPEN SOURCE"),
		Rect2(130, 1290, 1200, 46),
		25,
		MUTED
	)
	var note := (
		"Android 虚拟机实拍 · 画面已裁切缩放用于排版 · 以头显实际体验为准"
		if zh
		else "Actual Android emulator capture · Cropped/scaled for layout · Headset experience may vary"
	)
	text(note, Rect2(130, 1346, 2300, 44), 21, DIM)


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
		if (
			source == null
			or source.get_size() != SIZE
			or FileAccess.get_sha256(path) != capture.sha256
		):
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
				if (
					data.size() > 5_000_000
					or data.size() < 2
					or data[0] != 0xff
					or data[1] != 0xd8
					or decoded == null
					or decoded.get_size() != SIZE
				):
					failed = true
					push_error("Detail image must be JPEG, 2560x1440 and <=5 MB")
			page.free()
	# A separate contact sheet is for local review; upload only the locale folders.
	var previews := ProjectSettings.globalize_path(
		"res://../../artifacts/captures/branding/store-details"
	)
	DirAccess.make_dir_recursive_absolute(previews)
	for locale in ["zh-CN", "en"]:
		var sheet := Image.create(2560, 1440, false, Image.FORMAT_RGB8)
		for index in CARDS.size():
			var thumb := Image.load_from_file(
				ProjectSettings.globalize_path(BASE + locale + "/" + CARDS[index].file + ".jpg")
			)
			thumb.convert(Image.FORMAT_RGB8)
			thumb.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(
				thumb, Rect2i(0, 0, 1280, 720), Vector2i((index % 2) * 1280, (index / 2) * 720)
			)
		sheet.save_jpg(previews.path_join("overview-" + locale + ".jpg"), .92)
	print(
		"Prepared 4 detail-page JPEGs per language at 2560x1440; sources are actual emulator captures"
	)
	viewport.queue_free()
	quit(1 if failed else 0)
