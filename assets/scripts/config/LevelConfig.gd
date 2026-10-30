class_name LevelConfig
extends Resource


@export var uuid: String
@export var display_name : String

@export var tile_map_data : PackedByteArray
@export var animal_resource_data: Dictionary[Vector2i, AnimalConfig] = {}
@export var obstacle_resource_data: Dictionary[Vector2i, BaseConfig] = {}
