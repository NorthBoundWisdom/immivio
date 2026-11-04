extends Node3D
const UI := preload("res://scripts/ray_menu.gd")
const I18n := preload("res://scripts/i18n.gd")
const Policy := preload("res://scripts/immersive_adjustments.gd")
var source: Callable
var labels: Array[Label3D] = []
func _ready() -> void:
	position = Vector3(0, 0.25, -1.2)
	for i in 2:
		var label := Label3D.new()
		label.font = UI.ui_font()
		label.font_size = 23
		label.pixel_size = 0.0008
		label.outline_size = 8
		label.no_depth_test = true
		label.position.y = -i * 0.065
		add_child(label)
		labels.append(label)
func _process(_delta: float) -> void:
	var samples: Array = source.call() if source.is_valid() else []
	visible = not samples.is_empty()
	for i in labels.size():
		labels[i].visible = i < samples.size()
		if i >= samples.size():
			continue
		var sample: Dictionary = samples[i]
		labels[i].text = I18n.t(sample.title) + "  " + Policy.value_text(sample.key, sample.value) + "  [%+.0f … %+.0f%%]" % [sample.span.x, sample.span.y]
		labels[i].modulate.a = sample.alpha
