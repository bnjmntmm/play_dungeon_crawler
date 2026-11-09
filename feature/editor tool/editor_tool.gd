@tool
class_name AnimalEditorTool
extends EditorScript

var window:Window = Window.new()
var levelScene:PackedScene = preload("uid://b67wubyj4rlpj")

func _run() -> void:
	#window.borderless = true
	#window.always_on_top = true
	#/4.0 * 3.0
	EditorInterface.popup_dialog_centered(window, DisplayServer.screen_get_size()/4.0 * 3.0)
	
	var scene = levelScene.instantiate() as Control
	window.add_child(scene)
	if scene.has_method("initialize"):
		scene.initialize()
	
	window.close_requested.connect(func():window.queue_free())
