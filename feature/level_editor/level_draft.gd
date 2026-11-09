@tool
class_name LevelDraft
extends RefCounted

## Source and alternative ids of the scene tiles in scene_tileset.tres.
const ANIMAL_SOURCE_ID: int = 0
const OBSTACLE_SOURCE_ID: int = 1
const SCENE_TILE_ID: int = 1

var animals: Dictionary[Vector2i, AnimalConfig] = {}
var obstacles: Dictionary[Vector2i, BaseConfig] = {}

func place(cell: Vector2i, config: BaseConfig) -> void:
	erase(cell)
	if config is AnimalConfig:
		animals[cell] = config
	else:
		obstacles[cell] = config

func erase(cell: Vector2i) -> void:
	animals.erase(cell)
	obstacles.erase(cell)

func clear() -> void:
	animals.clear()
	obstacles.clear()

func is_empty() -> bool:
	return animals.is_empty() and obstacles.is_empty()

func get_placed_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(animals.keys() + obstacles.keys())
	return cells

func get_obstacle_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(obstacles.keys())
	return cells

func get_config(cell: Vector2i) -> BaseConfig:
	if animals.has(cell):
		return animals[cell]
	return obstacles.get(cell)

func load_from(level: LevelConfig) -> void:
	animals = level.animal_resource_data.duplicate()
	obstacles = level.obstacle_resource_data.duplicate()

func apply_to(level: LevelConfig, scene_tile_set: TileSet) -> void:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = scene_tile_set
	for cell: Vector2i in animals:
		layer.set_cell(cell, ANIMAL_SOURCE_ID, Vector2i.ZERO, SCENE_TILE_ID)
	for cell: Vector2i in obstacles:
		layer.set_cell(cell, OBSTACLE_SOURCE_ID, Vector2i.ZERO, SCENE_TILE_ID)

	level.tile_map_data = layer.get_tile_map_data_as_array()
	level.animal_resource_data = animals.duplicate()
	level.obstacle_resource_data = obstacles.duplicate()
	layer.free()
