@tool
class_name SpriteScaler
extends Node2D

@export var sprite: Sprite2D
@export var target_width: float = 16.0:
	set(value):
		target_width = value
		if is_node_ready():
			fit()

func _ready() -> void:
	if sprite == null:
		push_warning("SpriteScaler: assign a sprite.")
		return
	sprite.texture_changed.connect(fit)
	fit()

func fit() -> void:
	if sprite == null or sprite.texture == null:
		return
	var tex_w := sprite.region_rect.size.x if sprite.region_enabled else float(sprite.texture.get_width())
	var w := tex_w / float(sprite.hframes)
	if w <= 0.0:
		return
	var s := target_width / w
	scale = Vector2(s, s)
