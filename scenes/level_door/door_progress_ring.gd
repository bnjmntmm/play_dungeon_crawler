extends Node2D

const RADIUS := 12.0
const WIDTH := 3.0

var _progress: float = 0.0

func _ready() -> void:
	visible = false

func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	visible = _progress > 0.0
	queue_redraw()

func _draw() -> void:
	if _progress <= 0.0:
		return
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(0.05, 0.05, 0.05, 0.8), WIDTH + 2.0, true)
	draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * _progress, 48, Color(1.0, 0.82, 0.25, 1.0), WIDTH, true)
