extends Node2D

@onready var scene_fader: SceneFader = $CanvasLayer/SceneFader

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.gallery_mode = true
	scene_fader.start_fade(false)
	pass # Replace with function body.

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_left"):
		on_left_pressed()
	elif Input.is_action_just_pressed("ui_right"):
		on_right_pressed()
	elif Input.is_action_just_pressed("ui_up"):
		on_up_pressed()

func on_left_pressed() -> void:
	GameManager.gallery_switch(false)

func on_right_pressed() -> void:
	GameManager.gallery_switch(true)
	
func on_up_pressed() -> void:
	scene_fader.start_fade(true)
	GameManager.init_start_room_return()
