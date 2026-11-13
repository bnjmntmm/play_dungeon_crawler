extends Node

@onready var end_cutscene: AnimationPlayer = $EndCutscene
@onready var player_start_pos: Marker2D = $EndCutscene/PlayerStartPos
@onready var player: PlayerCharacter = $Player
@onready var omas_picknicktisch: Sprite2D = $OmasPicknicktisch
@onready var animation_player: AnimationPlayer = $OmaChar1/AnimationPlayer
@onready var end_room_notice: Control = $EndRoomUI/EndRoomNotice

var is_waiting_for_end: bool = false
var in_transition: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.force_fade(false)
	animation_player.play("idle")
	MusicManager.play_ambience()

func _on_cutscene_trigger_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		var player: PlayerCharacter= body as PlayerCharacter
		player._movement_lock = true
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(player, "global_position", player_start_pos.global_position, 0.4)
		await t.finished

		end_cutscene.play("end_cutscene")
	pass # Replace with function body.


func _on_end_cutscene_animation_finished(anim_name: StringName) -> void:
	if anim_name == "end_cutscene":
		is_waiting_for_end = true
		var msg := end_room_notice as EndRoomNotice
		msg._show_end_msg()
		
func _input(event: InputEvent) -> void:
	if in_transition:
		return
	if event.is_action_pressed("ui_accept"):
		in_transition = true
		get_viewport().set_input_as_handled()
		GameManager.init_start_room_return()
		
