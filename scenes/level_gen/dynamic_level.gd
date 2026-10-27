extends Node2D

signal on_change_level_complete

@export var debug_mode_enabled : bool
@export var debug_level : LevelConfig
@export var debug_entry : LevelDoor
@onready var level_objects_tile_layer: TileMapLayer = $TileLayers/LevelObjectsTileLayer
@onready var player: PlayerCharacter = $Player


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if debug_mode_enabled && debug_level:
		GameManager.debug_mode_enabled = debug_mode_enabled
		GameManager.debug_level = debug_level
		GameManager.change_level.connect(change_level)
		GameManager.nextEntryDoor = debug_entry
		position_player()
		#GameManager.load_new_room()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		GameManager.load_new_room()
	pass

func change_level(level_data: PackedByteArray) -> void:
	level_objects_tile_layer.clear()
	level_objects_tile_layer.set_tile_map_data_from_array(level_data)
	on_change_level_complete.emit()
	position_player()
	pass


func position_player():
	player.global_position = GameManager.nextEntryDoor.global_position
