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
	GameManager.death_restart_scene = load("res://feature/level_editor/level_preview.tscn") as PackedScene
	# Each retry is a fresh preview, not progress toward the normal game's end room.
	GameManager.current_room_index = 0
	GameManager.player_score = 0
	var level: LevelConfig = ResourceLoader.load(LEVEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelConfig
	if level == null:
		push_error("LevelPreview found no level at %s" % LEVEL_PATH)
		get_tree().quit()
		return
	_refresh_level_sprites(level)
	var level_scene: Node = (load(LEVEL_SCENE_PATH) as PackedScene).instantiate()
	# Keep the normal room-loading callbacks, but make trying a draft immediate.
	var fader: SceneFader = level_scene.get_node("CombinedUi/SceneFader") as SceneFader
	fader.fade_duration = 0.1
	var dynamic_level: Node = level_scene.get_node("DynamicLevel")
	dynamic_level.set("debug_mode_enabled", true)
	dynamic_level.set("debug_switch_level", false)
	dynamic_level.set("debug_level", level)
	add_child(level_scene)

## Refresh only referenced drawings, once per resource even when placed many times.
func _refresh_level_sprites(level: LevelConfig) -> void:
	var refreshed: Dictionary[BaseConfig, bool] = {}
	for config: BaseConfig in level.animal_resource_data.values() + level.obstacle_resource_data.values():
		if config == null or refreshed.has(config):
			continue
		refreshed[config] = true
		if not config.source_png.is_empty():
			config.refresh_sprite()

func _add_keyboard_controls() -> void:
	for action: String in KEYBOARD_CONTROLS:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = KEYBOARD_CONTROLS[action]
		InputMap.action_add_event(action, key_event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
