extends Node2D

@onready var scene_fader: SceneFader = $CanvasLayer/SceneFader
@onready var gallery_sfx: AudioStreamPlayer = $GallerySFX
@onready var gallery_searcher: GallerySearcher = $CanvasLayer/GallerySearcher

const SWIPE_LEFT = preload("uid://berg3w4jyfyrm")
const SWIPE_RIGHT = preload("uid://ckw7ebb5xkyhv")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.gallery_mode = true
	gallery_searcher.xpressed.connect(on_up_pressed)
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
	gallery_sfx.stream = SWIPE_LEFT
	gallery_sfx.play()
	
func on_right_pressed() -> void:
	GameManager.gallery_switch(true)
	gallery_sfx.stream = SWIPE_RIGHT
	gallery_sfx.play()
	
func on_up_pressed() -> void:
	scene_fader.start_fade(true)
	GameManager.init_start_room_return()
