extends Node

signal start_fade(is_in: bool)
signal change_level(level_data: PackedByteArray)
signal player_reposition(new_pos: Vector2)
signal init_configs()
signal entered_end_room()
signal player_died()

var nextEntryDoor : LevelDoor

var debug_mode_enabled : bool
var debug_level : LevelConfig

var gallery_mode: bool = false
var gallery_index: int = 0
var changing_scenes: bool = false
var next_scene: PackedScene
var is_force_fade: bool = false
var is_in_load: bool = false

var all_level_configs: Array[LevelConfig]
var unused_level_configs: Array[LevelConfig]
var current_room_index: int
var current_level_config: LevelConfig

var all_animal_configs: Array[AnimalConfig]

var player_final_cake_slices: int = 0
var animal_register: Array[AnimalScene] = []

#no const to avoid circular dependency issue
var main_scene: PackedScene = load("res://scenes/start_room/start_room.tscn")

const MAX_ROOMS_TO_GENERATE: int = 5
const CUSTOM_DATA_PATH: String = "res://custom_data"
const RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]
const END_ROOM = preload("uid://brkub0ovdbfcx")
 
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	all_level_configs = _load_all_level_configs(CUSTOM_DATA_PATH)
	all_animal_configs = _load_all_animal_configs(CUSTOM_DATA_PATH)
	reset_run()

func _load_all_level_configs(dir_path: String) -> Array[LevelConfig]:
	var configs : Array[LevelConfig]
	
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		configs.append_array(_load_all_level_configs(dir_path.path_join(sub_dir)))
	
	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() not in RESOURCE_EXTENSIONS:
			continue
		var file_path: String = dir_path.path_join(file_name)
		if !ResourceLoader.exists(file_path):
			continue
		var config : LevelConfig = load(file_path) as LevelConfig
		if config:
			configs.append(config)
	return configs
	
func _load_all_animal_configs(dir_path: String) -> Array[AnimalConfig]:
	var configs : Array[AnimalConfig]
	
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		configs.append_array(_load_all_animal_configs(dir_path.path_join(sub_dir)))
	
	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() not in RESOURCE_EXTENSIONS:
			continue
		var file_path: String = dir_path.path_join(file_name)
		if !ResourceLoader.exists(file_path):
			continue
		var config : AnimalConfig = load(file_path) as AnimalConfig
		if config:
			configs.append(config)
	return configs

func reset_run() -> void:
	unused_level_configs.clear()
	animal_register.clear()
	unused_level_configs.append_array(all_level_configs)
	current_room_index = 0
	GameManager.gallery_mode = false
	#Stat Resets etc here
	
func _room_fade_event(is_in: bool) -> void:
	start_fade.emit(is_in)
	pass

func _choose_next_level() -> LevelConfig:
	if debug_mode_enabled && debug_level:
		return debug_level
	if gallery_mode:
		return all_level_configs[gallery_index]
	if unused_level_configs.size() < 1:
		unused_level_configs.clear()
		unused_level_configs.append_array(all_level_configs)
	var ran_index: int = randi_range(0, unused_level_configs.size() - 1)
	var chosen_level_config : LevelConfig = unused_level_configs.pop_at(ran_index)
	return chosen_level_config

func handle_fade_callback(is_in: bool) -> void:
	if is_force_fade:
		is_force_fade = false
		return
	if is_in:
		if changing_scenes:
			_load_next_scene()
		else:
			_load_new_room()
	else:
		pass

func init_room_change() -> void:
	is_in_load = true
	print ("load started")
	if not gallery_mode:
		current_room_index += 1
		if current_room_index >= MAX_ROOMS_TO_GENERATE:
			entered_end_room.emit()
			init_scene_change(END_ROOM)
	start_fade.emit(true)

func _load_new_room() -> void:
	current_level_config = _choose_next_level()
	animal_register.clear()
	change_level.emit(current_level_config.tile_map_data)
	pass
	
func on_room_loaded() -> void:
	init_configs.emit()
	player_reposition.emit(nextEntryDoor.global_position + nextEntryDoor.player_spawn_offset)
	start_fade.emit(false)
	is_in_load = false
	print ("loaded")
	
func on_player_died() -> void:
	init_start_room_return()
	player_died.emit()

func init_start_room_return() -> void:
	init_scene_change(main_scene)

func init_scene_change(new_scene: PackedScene) -> void:
	next_scene = new_scene
	changing_scenes = true
	start_fade.emit(true)
	pass

func _load_next_scene() -> void:
	var tree: SceneTree = get_tree()
	animal_register.clear()
	tree.change_scene_to_packed(next_scene)
	changing_scenes = false
	
func force_fade(is_in: bool) -> void:
	is_force_fade = true
	start_fade.emit(is_in)
		

func gallery_switch(is_right: bool)-> void:
	if is_in_load:
		return
	gallery_index += 1 if is_right else -1
	gallery_index = posmod(gallery_index, all_level_configs.size())
	is_in_load = true
	init_room_change()
	pass

func set_all_enemy_passive(passive: bool)->void :
	for animal: AnimalScene in animal_register:
		animal.set_passive_state(passive)

func register_animal(scene: AnimalScene)-> void:
	animal_register.append(scene)
