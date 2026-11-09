extends CanvasLayer

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_update_visibility()

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_visibility()

func _update_visibility() -> void:
	visible = Input.get_connected_joypads().is_empty()
