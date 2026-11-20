extends Node2D

# The random animals need the library before their own _ready callbacks run.
func _enter_tree() -> void:
	GameManager.reset_run()

func _ready() -> void:
	GameManager.force_fade(false)
	if MusicManager.is_playing():
		MusicManager.play_ambience()
	else:
		MusicManager.play_pair(
			preload("res://assets/sounds/bgm/Background_Ambience_V2.wav"),
			preload("res://assets/sounds/bgm/Music_Action.wav"),
			[
				{"a_start": 0.0, "a_end": 35.888},
				{"a_start": 53.834},
			]
		)
