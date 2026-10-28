extends Node

signal start_fade(is_in: bool)
signal change_level(level_data: PackedByteArray)
signal player_reposition(new_pos: Vector2)

var nextEntryDoor : LevelDoor

var debug_mode_enabled : bool
var debug_level : LevelConfig

var registered_animals : Array[AnimalScene]
var all_level_configs: Array[LevelConfig]
var unused_level_configs: Array[LevelConfig]
var max_room_to_generate: int
var current_room_index: int

const CUSTOM_DATA_PATH: String = "res://custom_data"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	all_level_configs = _load_all_configs(CUSTOM_DATA_PATH)
	_reset_run()
	pass # Replace with function body.

func _load_all_configs(dir_path: String) -> Array[LevelConfig]:
	var configs : Array[LevelConfig]
	
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		configs.append_array(_load_all_configs(dir_path.path_join(sub_dir)))
	
	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		var file_path: String = dir_path.path_join(file_name)
		if !ResourceLoader.exists(file_path, "LevelConfig"):
			continue
		var config : LevelConfig = load(file_path)
		if config is LevelConfig:
			configs.append(config)
	return configs

func _reset_run() -> void:
	unused_level_configs.clear()
	unused_level_configs.append_array(all_level_configs)
	#Stat Resets etc here
	
func _room_fade_event(is_in: bool) -> void:
	start_fade.emit(is_in)
	pass

func _choose_next_level() -> LevelConfig:
	if debug_mode_enabled && debug_level:
		return debug_level
	if unused_level_configs.size() < 1:
		unused_level_configs.clear()
		unused_level_configs.append_array(all_level_configs)
	var ran_index: int = randi_range(0, unused_level_configs.size() - 1)
	var chosen_level_config : LevelConfig = unused_level_configs.pop_at(ran_index)
	return chosen_level_config

func handle_fade_callback(is_in: bool) -> void:
	if is_in:
		_load_new_room()
	else:
		pass

func init_room_change() -> void:
	start_fade.emit(true)

func _load_new_room() -> void:
	var chosen_level: LevelConfig = _choose_next_level()
	change_level.emit(chosen_level.tile_map_data)
	player_reposition.emit(nextEntryDoor.global_position)
	start_fade.emit(false)
	pass
