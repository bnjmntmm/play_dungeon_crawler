extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.reset_run()
	GameManager.force_fade(false)
	pass # Replace with function body.
