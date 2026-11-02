@tool
class_name LevelEditorTool
extends EditorScript

const EDITOR_SCENE_PATH: String = "res://feature/level_editor/level_editor.tscn"

func _run() -> void:
	var window: Window = Window.new()
	window.title = "Level Editor"
	var editor: LevelEditor = (load(EDITOR_SCENE_PATH) as PackedScene).instantiate() as LevelEditor
	window.add_child(editor)
	window.close_requested.connect(window.queue_free)
	EditorInterface.popup_dialog_centered(window, Vector2i(DisplayServer.screen_get_size() / 4.0 * 3.0))
	editor.initialize()
