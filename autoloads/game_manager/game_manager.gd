extends Node

signal start_fade(is_in: bool)
signal change_level(level_data: PackedByteArray)
signal player_reposition(new_pos: Vector2)
signal init_configs()
signal loaded_new_room(room_name: String)
signal room_cleared
signal entered_end_room()
signal player_died()
signal player_score_changed()

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
var scripted_level_config: LevelConfig = null

var all_animal_configs: Array[AnimalConfig]

var all_obstacle_configs: Array[BaseConfig] = []

var player_final_cake_slices: int = 0
var animal_register: Array[AnimalScene] = []
var room_is_cleared: bool = false
var _room_ready_for_clear_check: bool = false

#no const to avoid circular dependency issue
var main_scene: PackedScene = load("res://scenes/start_room/start_room.tscn")

const MAX_ROOMS_TO_GENERATE: int = 5
const CUSTOM_DATA_PATH: String = "res://custom_data"
const RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]
const END_ROOM = preload("uid://brkub0ovdbfcx")

var player_score: int = 0

var _cached_fade: Dictionary = {} # {"is_in": bool, "force": bool}
var _next_is_force: bool = false
 
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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
		var config : LevelConfig = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as LevelConfig
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
		var config : AnimalConfig = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE) as AnimalConfig
		if config:
			configs.append(config)
	return configs

func _load_all_obstacle_configs(dir_path: String) -> Array[BaseConfig]:
	var result: Array[BaseConfig] = []

	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		result.append_array(_load_all_obstacle_configs(dir_path.path_join(sub_dir)))

	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() not in RESOURCE_EXTENSIONS:
			continue
		var file_path: String = dir_path.path_join(file_name)
		if not ResourceLoader.exists(file_path):
			continue
		# Peek at the type first so levels and animals aren't needlessly replaced
		var peek: Resource = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if peek is BaseConfig and not peek is AnimalConfig:
			var fresh := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE) as BaseConfig
			if fresh:
				result.append(fresh)
	return result

func reset_run() -> void:
	all_level_configs = _load_all_level_configs(CUSTOM_DATA_PATH)
	all_animal_configs = _load_all_animal_configs(CUSTOM_DATA_PATH)
	all_obstacle_configs = _load_all_obstacle_configs(CUSTOM_DATA_PATH)
	reread_sprites()
	unused_level_configs.clear()
	animal_register.clear()
	room_is_cleared = false
	_room_ready_for_clear_check = false
	unused_level_configs.append_array(all_level_configs)
	current_room_index = 0
	player_score = 0
	GameManager.gallery_mode = false
	#Stat Resets etc here

func _collect_base_configs(dir_path: String) -> Array[BaseConfig]:
	var result: Array[BaseConfig] = []

	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		result.append_array(_collect_base_configs(dir_path.path_join(sub_dir)))

	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() not in RESOURCE_EXTENSIONS:
			continue
		var file_path: String = dir_path.path_join(file_name)
		if not ResourceLoader.exists(file_path):
			continue
		var res: Resource = ResourceLoader.load(
			file_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res is BaseConfig:
			result.append(res)
	return result

func reread_sprites() -> void:
	for config: BaseConfig in all_animal_configs:
		if not config.refresh_sprite():
			push_warning("No sprite refresh for %s" % config.resource_path)
	for config: BaseConfig in all_obstacle_configs:
		if not config.refresh_sprite():
			push_warning("No sprite refresh for %s" % config.resource_path)

func _room_fade_event(is_in: bool) -> void:
	start_fade.emit(is_in)
	pass

func _choose_next_level() -> LevelConfig:
	if debug_mode_enabled && debug_level:
		return debug_level
	if scripted_level_config && not gallery_mode:
		return scripted_level_config
	if gallery_mode:
			return all_level_configs[gallery_index]
	if unused_level_configs.size() < 1:
		unused_level_configs.clear()
		unused_level_configs.append_array(all_level_configs)
	var ran_index: int = randi_range(0, unused_level_configs.size() - 1)
	var chosen_level_config : LevelConfig = unused_level_configs.pop_at(ran_index)
	return chosen_level_config

func handle_fade_callback(is_in: bool) -> void:
	var was_force: bool = is_force_fade
	is_force_fade = false
	if is_in and not was_force:
		if changing_scenes:
			_load_next_scene()
		else:
			_load_new_room()
	_flush_cached_fade.call_deferred(is_in and not was_force)

func init_room_change(no_progress: bool) -> void:
	is_in_load = true
	print ("load started")
	if not gallery_mode:
		if not no_progress:
			current_room_index += 1
		if current_room_index >= MAX_ROOMS_TO_GENERATE:
			entered_end_room.emit()
			init_scene_change(END_ROOM)
	start_fade.emit(true)

func _load_new_room() -> void:
	current_level_config = _choose_next_level()
	animal_register.clear()
	room_is_cleared = false
	_room_ready_for_clear_check = false
	change_level.emit(current_level_config.tile_map_data)
	pass
	
func on_room_loaded() -> void:
	init_configs.emit()
	_room_ready_for_clear_check = true
	_check_room_clear()
	player_reposition.emit(nextEntryDoor.player_spawn_pos_visualizer.global_position)
	if gallery_mode:
		on_player_repos()

func on_player_repos()-> void:
	loaded_new_room.emit(current_level_config.display_name)
	start_fade.emit(false)
	is_in_load = false
	if not gallery_mode && scripted_level_config:
		scripted_level_config = null
	print ("loaded")
	MusicManager.play_action()
	
func on_player_died() -> void:
	get_tree().create_timer(1).timeout
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
	_next_is_force = true
	start_fade.emit(is_in) 
	if _next_is_force:      
		_next_is_force = false
		is_force_fade = true
		

func gallery_switch(is_right: bool)-> void:
	if is_in_load:
		return
	gallery_index += 1 if is_right else -1
	gallery_index = posmod(gallery_index, all_level_configs.size())
	is_in_load = true
	init_room_change(true)
	pass
	
func gallery_search(new_index: int)-> void:
	if is_in_load:
		return
	gallery_index = new_index
	is_in_load = true
	init_room_change(true)
	
	pass

func set_all_enemy_passive(passive: bool)->void :
	for animal: AnimalScene in animal_register:
		animal.set_passive_state(passive)

func register_animal(scene: AnimalScene)-> void:
	if animal_register.has(scene):
		return
	animal_register.append(scene)
	if not scene.pacified.is_connected(_check_room_clear):
		scene.pacified.connect(_check_room_clear)
	if _room_ready_for_clear_check:
		call_deferred("_check_room_clear")

func _check_room_clear() -> void:
	if not _room_ready_for_clear_check or room_is_cleared:
		return
	for animal: AnimalScene in animal_register:
		if is_instance_valid(animal) and not animal.is_pacified():
			return
	room_is_cleared = true
	room_cleared.emit()

func add_player_score(pts: int)-> void:
	player_score += pts
	player_score_changed.emit()

func cache_fade(is_in: bool) -> void:
	_cached_fade = {"is_in": is_in, "force": _next_is_force}
	_next_is_force = false

func _flush_cached_fade(handled_fade_in: bool) -> void:
	if _cached_fade.is_empty():
		return
	var cached: Dictionary = _cached_fade
	_cached_fade = {}
	# A plain fade-in on top of a finished fade-in is redundant: the callback
	# above already did whatever was pending (load room or change scene).
	if handled_fade_in and cached["is_in"] and not cached["force"]:
		return
	is_force_fade = cached["force"]
	start_fade.emit(cached["is_in"])
