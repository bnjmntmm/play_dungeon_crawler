extends Control

@onready var label: Label = $ColorRect/MarginContainer/Label
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.loaded_new_room.connect(_display_new_leve_name)
	pass # Replace with function body.

func _display_new_leve_name(new_name: String):
	animation_player.play("RESET")
	label.text = new_name
	animation_player.play("Reveal_Title")
	
