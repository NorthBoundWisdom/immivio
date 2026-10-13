extends SceneTree
## Deterministic platform sizing of the supplied artwork; no retouching or redrawing.
## Run: godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var original := Image.load_from_file(ProjectSettings.globalize_path("res://branding/thru3d-icon.png"))
	if original == null or original.is_empty():
		push_error("Application icon is missing")
		quit(1); return
	# Keep the complete tile inside Android's adaptive-icon safe area.
	var foreground := original.duplicate() as Image
	foreground.resize(288, 288, Image.INTERPOLATE_LANCZOS)
	foreground.convert(Image.FORMAT_RGBA8)
	var canvas := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	canvas.blit_rect(foreground, Rect2i(0, 0, 288, 288), Vector2i(72, 72))
	var result := canvas.save_png(ProjectSettings.globalize_path("res://branding/thru3d-adaptive.png"))
	if result != OK:
		push_error("Unable to save branding asset: %s" % result)
		quit(1)
		return
	var web := original.duplicate() as Image
	web.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	result = web.save_png(ProjectSettings.globalize_path("res://../../website/assets/icon.png"))
	if result != OK:
		push_error("Unable to save branding asset: %s" % result)
		quit(1)
		return
	print("Prepared 432px adaptive foreground and 256px website icon from the original artwork")
	quit()
