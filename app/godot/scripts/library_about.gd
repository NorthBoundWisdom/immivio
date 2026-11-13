extends RefCounted
## About/credits rows and license resolution; the library retains page/navigation state.
const I18n := preload("res://scripts/i18n.gd")
const PlatformMethods := preload("res://scripts/platform_methods.gd")
var menu: Node3D


func _init(owner: Node3D) -> void:
	menu = owner


## Everything the app ships, grouped by role: [heading, [[name, license · authors], ...]].
## Native libraries are those statically linked into the bundled mpv-android build.
const CREDITS := [
	[
		"Engine & XR",
		[
			["Godot Engine 4.7.2", "MIT"],
			["Godot OpenXR Vendors 5.1.0", "MIT · vendor license notices"],
			["Khronos OpenXR Loader 1.1.65", "Apache-2.0"],
			["Godot OpenXR hand demo assets", "MIT"],
		]
	],
	[
		"Playback & decoding",
		[
			["mpv (mpv-android 2026-09-17)", "GPL-2.0-or-later"],
			["FFmpeg", "GPL-3.0-or-later"],
			["libplacebo", "LGPL-2.1-or-later"],
			["shaderc · glslang · SPIRV-Tools", "Apache-2.0 · BSD-3-Clause"],
			["dav1d", "BSD-2-Clause"],
		]
	],
	[
		"Subtitles & text",
		[
			["libass", "ISC"],
			["FreeType", "FreeType License"],
			["HarfBuzz", "MIT"],
			["GNU FriBidi", "LGPL-2.1-or-later"],
			["libunibreak", "zlib"],
			["ICU4J charset detector 79.1", "Unicode-3.0"],
		]
	],
	[
		"Network & storage",
		[
			["CodeLibs JCIFS 3.0.4", "LGPL-2.1"],
			["Bouncy Castle 1.87", "MIT"],
			["SLF4J API 2.0.20", "MIT"],
			["Mbed TLS 3.6.7", "Apache-2.0"],
			["libxml2", "MIT"],
		]
	],
	[
		"Runtime",
		[
			["Lua 5.2", "MIT"],
			["Kotlin standard library 2.4.21", "Apache-2.0"],
			["kotlinx.coroutines 1.6.4", "Apache-2.0"],
			["AndroidX Activity · Core · Fragment · Lifecycle", "Apache-2.0"],
			["Guava 33.3.1", "Apache-2.0"],
			["JSpecify 1.0.0 · JetBrains annotations 13.0", "Apache-2.0"],
		]
	],
	[
		"Background panorama",
		[
			[
				"Belfast Sunset (Pure Sky)",
				"Poly Haven · CC0 1.0 · Dimitrios Savva / Greg Zaal / Jarod Guest"
			],
			["Blouberg Sunrise 2", "Poly Haven · CC0 1.0 · Greg Zaal"],
		]
	],
]


func rows(settings: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if menu._about_page == 3:
		var licenses: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://i18n/licenses.json")
		)
		if licenses is Array:
			for license in licenses:
				out.append(
					{
						"title": str(license.name),
						"detail": str(license.license),
						"icon": "info",
						"license_id": str(license.id)
					}
				)
	elif menu._about_page == 2:
		for group in CREDITS:
			out.append(menu._group(group[0]))
			for credit in group[1]:
				out.append(info(str(credit[0]), str(credit[1])))
	else:
		out.append(info("Immivio", str(settings.get("version", ""))))
		out.append_array(menu.update_check.rows())
		out.append(info(I18n.t("Official website"), "https://northboundwisdom.github.io/immivio/"))
		out.append(info(I18n.t("Source code"), "https://github.com/NorthBoundWisdom/immivio"))
		out.append({"title": I18n.t("Credits"), "icon": "info", "about_page": 2})
		out.append({"title": I18n.t("Open source licenses"), "icon": "info", "open_licenses": true})
		out.append(
			{
				"title": I18n.t("Save diagnostic log"),
				"icon": "info",
				"save_diagnostic_log": true,
				"detail":
				(
					I18n.t("Previous session log available")
					if settings.get("diagnostic_previous", false)
					else ""
				)
			}
		)
	return out


func draw() -> void:
	if menu._about_page != 0:
		menu._control_button(
			menu.ABOUT_HOME,
			"",
			Vector2(menu.CONTENT_RIGHT - menu.CONTROL_HEIGHT * .5, menu.HEADER_Y),
			menu.CONTROL_HEIGHT,
			true,
			"up"
		)


func info(title: String, detail: String) -> Dictionary:
	return {"title": title, "detail": detail, "icon": "info", "about_info": true}


func open_licenses() -> void:
	menu._about_page = 3
	menu.scroll = 0.0
	menu.refresh()


func desktop_license_text(id: String) -> String:
	var index: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://i18n/licenses.json")
	)
	if not index is Array:
		return ""
	for item in index:
		if item.id == id:
			var text := ""
			for asset in item.get("assets", []):
				var path := ProjectSettings.globalize_path("res://../../third_party/" + str(asset))
				if FileAccess.file_exists(path):
					text += FileAccess.get_file_as_string(path) + "\n\n"
			return text
	return ""


func engine_notices() -> String:
	var text := ""
	for component in Engine.get_copyright_info():
		text += str(component.get("name", "")) + "\n"
		for part in component.get("parts", []):
			text += (
				"\n".join(part.get("copyright", [])) + "\n" + str(part.get("license", "")) + "\n\n"
			)
	var licenses := Engine.get_license_info()
	for name in licenses:
		text += str(name) + "\n\n" + str(licenses[name]) + "\n\n"
	return text


func show_license(row: Dictionary) -> void:
	var id := str(row.license_id)
	var text := ""
	if id == "godot":
		text = Engine.get_license_text()
	elif id == "godot-third-party":
		text = engine_notices()
	else:
		text = (
			str(menu.platform.license_text(id))
			if PlatformMethods.supports(menu.platform, "license_text")
			else desktop_license_text(id)
		)
	menu.account_panel.show_license(
		str(row.title), text if not text.is_empty() else I18n.t("License unavailable")
	)
	return
