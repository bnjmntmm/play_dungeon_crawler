extends Node2D

signal on_change_level_complete

@export var debug_mode_enabled : bool
@export var debug_switch_level: bool = false
@export var debug_level : LevelConfig
@export var debug_entry : LevelDoor

@export var no_player : bool

@onready var default_start_door: LevelDoor = $LevelExits/LevelDoor3
@onready var main_level_layer: TileMapLayer = $TileLayers/MainLevelLayer
@onready var level_objects_tile_layer: TileMapLayer = $TileLayers/LevelObjectsTileLayer
@onready var room_navigation: NavigationRegion2DRuntimeBuilder = $NavigationRegion2D
@onready var player: PlayerCharacter = $Player
#@onready var canvas_layer: CanvasLayer = $CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#canvas_layer.show()
	if no_player:
		player.queue_free()
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
	level_objects_tile_layer.update_internals()
	
	await rebuild_navigation()
	
	on_change_level_complete.emit()
	GameManager.on_room_loaded()
	pass

## Call after changing floor or obstacle tiles during gameplay.
func rebuild_navigation() -> void:
	await room_navigation.rebuild($TileLayers)
