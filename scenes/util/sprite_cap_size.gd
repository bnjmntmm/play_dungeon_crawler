extends Sprite2D

@export var max_width: float = 16

func _ready() -> void:
	texture_changed.connect(fit_to_max_width)
	frame_changed.connect(fit_to_max_width)  # only matters with hframes/vframes
	fit_to_max_width()

func fit_to_max_width() -> void:
	if texture == null:
		return
	var w := texture.get_width() / float(hframes)
	var s := minf(1.0, max_width / w)
	scale = Vector2(s, s)
