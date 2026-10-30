class_name BasePlaceable
extends Node2D

@onready var sprite_2d: Sprite2D = $Sprite2D

@export var auto_init: bool = true
@export var config: BaseConfig

func _ready() -> void:
	GameManager.init_configs.connect(_start_init)

func _start_init() -> void:
	if auto_init && config:
		init_config()
	else:
		var layer := get_parent() as TileMapLayer
		if layer:
			var cell: Vector2i = layer.local_to_map(position)
			retrieve_config(cell)
	pass # Replace with function body.

func retrieve_config(pos: Vector2i):
	config = _get_config_source().get(pos)
	if config:
		init_config()
	else:
		print("No Config found for : {", pos.x," ",pos.y ,"}")

func _get_config_source() -> Dictionary:
	return {}

func init_config():
	sprite_2d.texture = config.sprite
