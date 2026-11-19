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
var _next_scene_path: String = ""
## Preview sessions override the death destination; normal runs return to the start room.
var death_restart_scene: PackedScene
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
var main_scene: PackedScene:
	get:
		if main_scene == null:
			main_scene = load("res://scenes/start_room/start_room.tscn")
		return main_scene

const MAX_ROOMS_TO_GENERATE: int = 5
const CUSTOM_DATA_PATH: String = "res://custom_data"
const ContentLibrary = preload("res://autoloads/game_manager/content_library.gd")
var _content_library: RefCounted = ContentLibrary.new()
const END_ROOM_PATH: String = "res://scenes/end_room/end_room.tscn"
var _library_initialized: bool = false

var player_score: int = 0

var _cached_fade: Dictionary = {} # {"is_in": bool, "force": bool}
var _next_is_force: bool = false
 
# Content is initialized by the start room, or lazily for directly opened rooms.
# Autoloads also run in the station and preview, which do not need the full library.

## Refresh content without resetting scores or room progression.
func refresh_library(force_reload: bool = false) -> void:
	_content_library.refresh(CUSTOM_DATA_PATH, force_reload)
	all_level_configs = _content_library.levels.duplicate()
	all_animal_configs = _content_library.animals.duplicate()
	all_obstacle_configs = _content_library.obstacles.duplicate()
	_library_initialized = true

func reset_run() -> void:
	refresh_library()
	unused_level_configs.clear()
	animal_register.clear()
	room_is_cleared = false
	_room_ready_for_clear_check = false
	unused_level_configs.append_array(all_level_configs)
	current_room_index = 0
	player_score = 0
	GameManager.gallery_mode = false
	#Stat Resets etc here

func reread_sprites() -> void:
	_content_library.refresh_sprites()

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
	if not _library_initialized and not debug_mode_enabled and not scripted_level_config:
		refresh_library()
		unused_level_configs.assign(all_level_configs)
	is_in_load = true
	print ("load started")
	if not gallery_mode:
		if not no_progress:
			current_room_index += 1
		if current_room_index >= MAX_ROOMS_TO_GENERATE:
			entered_end_room.emit()
			init_scene_change_path(END_ROOM_PATH)
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
	if death_restart_scene:
		init_scene_change(death_restart_scene)
	else:
		init_start_room_return()
	player_died.emit()

func init_start_room_return() -> void:
	init_scene_change(main_scene)

func init_scene_change(new_scene: PackedScene) -> void:
	_next_scene_path = ""
	next_scene = new_scene
	changing_scenes = true
	start_fade.emit(true)
	pass

## Begin I/O while the current scene fades; poll without blocking the main thread.
func init_scene_change_path(scene_path: String) -> void:
	if changing_scenes:
		return
	var error := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		push_error("Could not request scene %s: %s" % [scene_path, error_string(error)])
		return
	_next_scene_path = scene_path
	next_scene = null
	changing_scenes = true
	start_fade.emit(true)

func _load_next_scene() -> void:
	var tree: SceneTree = get_tree()
	if not _next_scene_path.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_next_scene_path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
			status = ResourceLoader.load_threaded_get_status(_next_scene_path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("Could not load scene: %s" % _next_scene_path)
			_next_scene_path = ""
			changing_scenes = false
			is_in_load = false
			start_fade.emit(false)
			return
		next_scene = ResourceLoader.load_threaded_get(_next_scene_path) as PackedScene
		_next_scene_path = ""
	animal_register.clear()
	var error := tree.change_scene_to_packed(next_scene)
	if error != OK:
		push_error("Could not change scene: %s" % error_string(error))
		start_fade.emit(false)
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
