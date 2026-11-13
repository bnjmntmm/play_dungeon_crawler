extends Control
class_name EndRoomNotice

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _show_end_msg():
	animation_player.play("reveal")
