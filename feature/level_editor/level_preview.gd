class_name LevelPreview
extends Node

const LEVEL_PATH: String = "user://level_editor_preview.tres"
## The wrapper brings the UI with its SceneFader, without it no room ever loads.
const LEVEL_SCENE_PATH: String = "res://scenes/level_gen/dynamic_level_complete.tscn"
## The game itself only reads controllers, the editor station may not have one.
const KEYBOARD_CONTROLS: Dictionary[String, Key] = {
	"movement_left": KEY_A,
	"movement_right": KEY_D,
	"movement_up": KEY_W,
	"movement_down": KEY_S,
}

func _ready() -> void:
	_add_keyboard_controls()
	var level: LevelConfig = ResourceLoader.load(LEVEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelConfig
	if level == null:
		push_error("LevelPreview found no level at %s" % LEVEL_PATH)
		get_tree().quit()
		return
	var level_scene: Node = (load(LEVEL_SCENE_PATH) as PackedScene).instantiate()
	var dynamic_level: Node = level_scene.get_node("DynamicLevel")
	dynamic_level.set("debug_mode_enabled", true)
	dynamic_level.set("debug_switch_level", false)
	dynamic_level.set("debug_level", level)
	add_child(level_scene)

func _add_keyboard_controls() -> void:
	for action: String in KEYBOARD_CONTROLS:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = KEYBOARD_CONTROLS[action]
		InputMap.action_add_event(action, key_event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
