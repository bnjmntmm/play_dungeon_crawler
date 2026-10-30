extends TileMapLayer

@export var dumpData : bool = true
@export var override_level_config : LevelConfig	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if !dumpData:
		return
	
	if override_level_config:
		var path : String = override_level_config.resource_path;
		var res: LevelConfig = load(path)
		res.tile_map_data = get_tile_map_data_as_array()
		if ResourceSaver.save(res, path) != OK:
			push_error("Konnte Resource nicht speichern!")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
