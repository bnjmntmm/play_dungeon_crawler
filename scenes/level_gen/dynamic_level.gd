extends Node2D

signal on_change_level_complete

@export var debug_mode_enabled : bool
@export var debug_switch_level: bool = false
@export var debug_level : LevelConfig
@export var debug_entry : LevelDoor

@onready var default_start_door: LevelDoor = $LevelExits/LevelDoor3
@onready var level_objects_tile_layer: TileMapLayer = $TileLayers/LevelObjectsTileLayer
@onready var player: PlayerCharacter = $Player


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.change_level.connect(change_level)
	GameManager.nextEntryDoor = default_start_door
	if debug_mode_enabled:
		GameManager.debug_mode_enabled = debug_mode_enabled
		if debug_level:
			GameManager.debug_level = debug_level
		if debug_entry:
			GameManager.nextEntryDoor = debug_entry
	GameManager.init_room_change()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") && debug_switch_level:
		GameManager.init_room_change()
	pass

func change_level(level_data: PackedByteArray) -> void:
	level_objects_tile_layer.clear()
	level_objects_tile_layer.set_tile_map_data_from_array(level_data)
	on_change_level_complete.emit()
	pass
