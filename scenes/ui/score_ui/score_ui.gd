extends Control

@onready var label: Label = $ColorRect/MarginContainer/Label
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.player_score_changed.connect(_update_player_score)
	pass # Replace with function body.

func _update_player_score()-> void:
	label.text = "%010d" % GameManager.player_score
	animation_player.play("increased_score")
	pass
