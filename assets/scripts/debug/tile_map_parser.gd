extends TileMapLayer

@export var dump_data : bool = true
@export var override_level_config : LevelConfig

@export var add_test_animal : bool = true
@export var animal_config_to_spawn: AnimalConfig

@export var add_test_obstacle : bool = true
@export var obstacle_config_to_spawn: BaseConfig

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if !dump_data:
		return
		
	if override_level_config:
		var path : String = override_level_config.resource_path;
		var res: LevelConfig = load(path)
		
		if add_test_animal:
			var animal_test_pos:= Vector2(9,4)
			set_cell(animal_test_pos,0 ,Vector2i.ZERO, 1)
			res.animal_resource_data.set(animal_test_pos, animal_config_to_spawn)
		
		if add_test_obstacle:
			var obstacle_test_pos:= Vector2(9,5)
			set_cell(obstacle_test_pos,1 ,Vector2i.ZERO, 1)
			res.obstacle_resource_data.set(obstacle_test_pos, obstacle_config_to_spawn)
		
		res.tile_map_data = get_tile_map_data_as_array()
		if ResourceSaver.save(res, path) != OK:
			push_error("Konnte Resource nicht speichern!")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
