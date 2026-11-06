extends SceneTree
## Deterministic sizing/composition of the supplied artwork. No retouching/redrawing.
## godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func load_art(path: String) -> Image:
	var result := Image.load_from_file(ProjectSettings.globalize_path(path))
	if result == null or result.is_empty():
		push_error("Branding source is missing: " + path)
		failed = true
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	result.convert(Image.FORMAT_RGBA8)
	return result


func png(picture: Image, path: String) -> void:
	if picture.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("Unable to save branding asset: " + path)
		failed = true


func scaled(picture: Image, side: int) -> Image:
	var result := picture.duplicate() as Image
	result.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return result


func background(source: Image, side: int) -> Image:
	var canvas := Image.create(side, side, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("061b43"))
	var layer := scaled(source, side)
	canvas.blend_rect(layer, Rect2i(0, 0, side, side), Vector2i.ZERO)
	return canvas


func play_layer(source: Image, side: int) -> Image:
	# The separately supplied play image has a larger mark than the surround layer.
	# Centre its complete canvas at half scale to match the supplied poster's proportions.
	var canvas := Image.create(side, side, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var mark := scaled(source, side / 2)
	canvas.blit_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), Vector2i(side / 4, side / 4))
	return canvas


## PICO poster upload contract: JPEG, exact dimensions and no more than 5 MB.
func store_poster(source: Image, size: Vector2i, path: String) -> void:
	var picture := source.duplicate() as Image
	picture.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	picture.convert(Image.FORMAT_RGB8)
	var destination := ProjectSettings.globalize_path(path)
	if picture.save_jpg(destination, .92) != OK:
		push_error("Unable to save PICO poster: " + path)
		failed = true
		return
	var encoded := FileAccess.get_file_as_bytes(destination)
	var decoded := Image.load_from_file(destination)
	if (
		encoded.size() < 2
		or encoded.size() > 5_000_000
		or encoded[0] != 0xff
		or encoded[1] != 0xd8
		or decoded == null
		or decoded.get_size() != size
	):
		push_error("PICO poster must be JPEG, match its required dimensions and be <=5 MB: " + path)
		failed = true


func _run() -> void:
	var original := load_art("res://branding/immivio-icon.png")
	var backdrop := load_art("res://../../branding/source/background.png")
	var surround := load_art("res://../../branding/source/surround.png")
	var play := load_art("res://../../branding/source/play.png")
	var wide_source := load_art("res://../../branding/source/poster-wide.png")
	var square_source := load_art("res://../../branding/source/poster-square.png")
	if failed:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://../../website/assets/branding")
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://../../branding/pico")
	)
	var mark := scaled(surround, 288)
	var triangle := play_layer(play, 288)
	mark.blend_rect(triangle, Rect2i(0, 0, 288, 288), Vector2i.ZERO)
	var foreground := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	foreground.fill(Color.TRANSPARENT)
	foreground.blit_rect(mark, Rect2i(0, 0, 288, 288), Vector2i(72, 72))
	png(foreground, "res://branding/immivio-adaptive.png")
	png(background(backdrop, 432), "res://branding/immivio-icon-background.png")
	var mono := foreground.duplicate() as Image
	for y in 432:
		for x in 432:
			mono.set_pixel(x, y, Color(1, 1, 1, foreground.get_pixel(x, y).a))
	png(mono, "res://branding/immivio-monochrome.png")
	var web := scaled(original, 256)
	# Remove the supplied opaque white corner matte, retaining all interior art.
	for y in 256:
		for x in 256:
			var corner := (Vector2(x + 0.5, y + 0.5) - Vector2(128, 128)).abs() - Vector2(63, 63)
			var distance := corner.max(Vector2.ZERO).length() - 64.0
			var color := web.get_pixel(x, y)
			color.a *= clampf(0.5 - distance, 0.0, 1.0)
			web.set_pixel(x, y, color)
	png(web, "res://../../website/assets/icon.png")
	var wide := wide_source.duplicate() as Image
	wide.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
	if (
		wide.save_webp(
			ProjectSettings.globalize_path("res://../../website/assets/branding/immivio-wide.webp"),
			true,
			.88
		)
		!= OK
	):
		failed = true
	var social := wide.duplicate() as Image
	social.resize(1200, 675, Image.INTERPOLATE_LANCZOS)
	if (
		social.save_jpg(
			ProjectSettings.globalize_path(
				"res://../../website/assets/branding/immivio-social.jpg"
			),
			.9
		)
		!= OK
	):
		failed = true
	var square := square_source.duplicate() as Image
	square.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	if (
		square.save_webp(
			ProjectSettings.globalize_path(
				"res://../../website/assets/branding/immivio-square.webp"
			),
			true,
			.88
		)
		!= OK
	):
		failed = true
	# Ready-sized source artwork for the PICO portal, kept outside the APK project.
	png(scaled(original, 1024), "res://../../branding/pico/icon-1024.png")
	png(background(backdrop, 1024), "res://../../branding/pico/background-1024.png")
	png(scaled(surround, 1024), "res://../../branding/pico/surround-1024.png")
	png(play_layer(play, 1024), "res://../../branding/pico/play-1024.png")
	# Resize each upload poster directly from its original, not a smaller website derivative.
	store_poster(
		wide_source, Vector2i(2560, 1440), "res://../../branding/pico/poster-wide-2560x1440.jpg"
	)
	store_poster(
		square_source, Vector2i(1024, 1024), "res://../../branding/pico/poster-square-1024.jpg"
	)
	print(
		"Prepared application/adaptive/themed icons, responsive website posters, social preview and PICO artwork"
	)
	quit(1 if failed else 0)
