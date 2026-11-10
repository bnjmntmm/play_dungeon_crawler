class_name ObstacleScene

extends BasePlaceable

func _get_config_source() -> Dictionary:
	return GameManager.current_level_config.obstacle_resource_data

func retrieve_config(pos: Vector2i):
	config = _get_config_source().get(pos)
	if config:
		init_config()
	else:
		print("No Config found for : {", pos.x," ",pos.y ,"}")
		#TODO For Debugging, remove this
		var config: BaseConfig = BaseConfig.new()
		config.uuid = str(randi())
		config.sprite = sprite_2d.texture
		GameManager.current_level_config.obstacle_resource_data.set(pos,config)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
