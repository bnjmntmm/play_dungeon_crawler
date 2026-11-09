extends TabContainer
## Game Design station: kids build an animal first, then place it in their room.

@onready var animal_editor: Control = $Tier
@onready var level_editor: LevelEditor = $Raum

func _ready() -> void:
	animal_editor.initialize()
	tab_changed.connect(_on_tab_changed)

## Both tabs share one code, so the animal and the room end up in the same kid folder.
func _on_tab_changed(tab: int) -> void:
	if get_tab_control(tab) == level_editor:
		level_editor.kid_id_edit.text = animal_editor.code_edit.text
		level_editor.build_palette()
	else:
		animal_editor.code_edit.text = level_editor.kid_id_edit.text
