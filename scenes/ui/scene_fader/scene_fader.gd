class_name SceneFader
extends Control

@onready var color_rect: ColorRect = $ColorRect
@export var fade_duration: float = 1.0
@export var use_game_manager_callbacks: bool = true

var is_in: bool
var tween: Tween

signal on_fade_completed(is_in: bool)

func _ready() -> void:
	if use_game_manager_callbacks:
		GameManager.start_fade.connect(start_fade)
		on_fade_completed.connect(GameManager.handle_fade_callback)
	pass

func change_fade_color(new_color: Color) -> void:
	color_rect.color = new_color
	pass

func start_fade(is_in_new: bool) -> void:
	is_in = is_in_new
	_fade_to(1.0 if is_in else 0.0)

func _fade_to(target_alpha: float) -> void:
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()
	tween.tween_property(color_rect, "color:a", target_alpha, fade_duration)
	tween.finished.connect(_on_fade_finished)
	
func _on_fade_finished() -> void:
	on_fade_completed.emit(is_in)
