class_name LevelDoor
extends Area2D

@export var enter_door : LevelDoor

@export_range(0.5, 10.0, 0.1) var skip_duration: float = 2.5

@onready var progress_ring: Node2D = $ProgressRing

var _entry_player: PlayerCharacter
var _skip_elapsed: float = 0.0
var _skip_started: bool = false

func _process(delta: float) -> void:
	if not _skip_started:
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
		var player: PlayerCharacter = body
		if GameManager.nextEntryDoor == self:
			_entry_player = player
			_skip_elapsed = 0.0
			_skip_started = true
			progress_ring.set_progress(0.0)
		else:
			player.set_movement_lock(true)
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
