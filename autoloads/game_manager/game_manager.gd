extends Node

signal start_fade(is_in: bool)
signal change_level(level_data: PackedByteArray)

var debug_mode_enabled : bool
var debug_level : LevelConfig

var registered_animals
var all_level_configs
var unused_level_configs
var max_room_to_generate: int
var current_room_index: int

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if debug_mode_enabled:
		load_new_room()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func room_fade_event(is_in: bool) -> void:
	start_fade.emit(is_in)
	pass

func choose_next_level() -> LevelConfig:
	if debug_mode_enabled && debug_level:
		return debug_level
	#Random Logic here
	return null

func load_new_room() -> void:
	var chosen_level: LevelConfig = choose_next_level()
	#UI Load Display Name etc.
	change_level.emit(chosen_level.tile_map_data)
	pass
