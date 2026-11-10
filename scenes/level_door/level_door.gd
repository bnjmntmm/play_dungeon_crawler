@tool
class_name LevelDoor
extends Area2D

signal door_state_changed(is_open: bool)

const OPEN_DOOR_TEXTURE: Texture2D = preload("res://assets/sprites/world_sprites/Tuer_offen.png")
const CLOSED_DOOR_TEXTURE: Texture2D = preload("res://assets/sprites/world_sprites/Tuer_zu.png")

@export var enter_door : LevelDoor

@export var is_teleport_door: bool = false
@export var teleport_destination: PackedScene
@export_range(0.0, 2.0, 0.01) var door_fade_duration: float = 0.2
#@export var sprite_rotation_degrees: float = 0.0:
	#set(value):
		#sprite_rotation_degrees = value
		#$DoorSprite.rotation_degrees = sprite_rotation_degrees
		#$CollisionShape2D.rotation_degrees = sprite_rotation_degrees
		#$DoorwayBlocker.rotation_degrees = sprite_rotation_degrees

@export_range(0.5, 10.0, 0.1) var skip_duration: float = 2.5
@export var player_spawn_offset: Vector2
@export var always_open: bool = true
@export var no_sprite: bool = false

@onready var door_sprite: Sprite2D = $DoorSprite
@onready var open_door_sprite: Sprite2D = $DoorSprite/OpenDoorSprite
@onready var doorway_blocker_shape: CollisionShape2D = $DoorwayBlocker/CollisionShape2D
@onready var progress_ring: Node2D = $ProgressRing
@onready var player_spawn_pos_visualizer: Marker2D = $PlayerSpawnPosVisualizer

var _entry_player: PlayerCharacter
var _skip_elapsed: float = 0.0
var _skip_started: bool = false
var _is_open: bool = false
var _door_fade_tween: Tween

func _ready() -> void:
	#why dont we use just normal rotations?
	#_apply_sprite_rotation()
	if no_sprite and is_instance_valid(door_sprite):
		door_sprite.visible = false
	if always_open or (is_teleport_door and not Engine.is_editor_hint()):
		set_door_open(true)
		doorway_blocker_shape.disabled = true  # immediate, we're not in a physics callback

#func _apply_sprite_rotation() -> void:
	#if is_instance_valid(door_sprite):
		#door_sprite.rotation_degrees = sprite_rotation_degrees
		#$CollisionShape2D.rotation_degrees = sprite_rotation_degrees
		#$DoorwayBlocker.rotation_degrees = sprite_rotation_degrees

func set_door_open(is_open: bool) -> void:
	if always_open or is_teleport_door:
		is_open = true
	if _is_open == is_open:
		return
	_is_open = is_open
	if _door_fade_tween and _door_fade_tween.is_valid():
		_door_fade_tween.kill()
	var open_alpha := 1.0 if is_open else 0.0
	if Engine.is_editor_hint() or door_fade_duration <= 0.0:
		door_sprite.self_modulate.a = 1.0 - open_alpha
		open_door_sprite.self_modulate.a = open_alpha
	else:
		_door_fade_tween = create_tween().set_parallel(true)
		_door_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_door_fade_tween.tween_property(door_sprite, "self_modulate:a", 1.0 - open_alpha, door_fade_duration)
		_door_fade_tween.tween_property(open_door_sprite, "self_modulate:a", open_alpha, door_fade_duration)
	doorway_blocker_shape.set_deferred("disabled", is_open)
	door_state_changed.emit(is_open)

func _process(delta: float) -> void:
	if not _skip_started or is_teleport_door:
		return
	if not is_instance_valid(_entry_player) or GameManager.nextEntryDoor != self:
		_reset_skip()
		return
	_skip_elapsed = minf(_skip_elapsed + delta, skip_duration)
	progress_ring.set_progress(_skip_elapsed / skip_duration)
	if _skip_elapsed >= skip_duration:
		_skip_started = false
		_entry_player.set_movement_lock(true)
		GameManager.nextEntryDoor = enter_door
		GameManager.init_room_change()

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		if not _is_open:
			return
		var player: PlayerCharacter = body
		if GameManager.nextEntryDoor == self:
			_entry_player = player
			_skip_elapsed = 0.0
			_skip_started = true
			progress_ring.set_progress(0.0)
		else:
			player.set_movement_lock(true)
			if is_teleport_door:
				GameManager.init_scene_change(teleport_destination)
			else:
				GameManager.nextEntryDoor = enter_door
				GameManager.init_room_change()

func _on_body_exited(body: Node2D) -> void:
	if body == _entry_player:
		_reset_skip()

func _reset_skip() -> void:
	_skip_started = false
	_skip_elapsed = 0.0
	_entry_player = null
	progress_ring.set_progress(0.0)
