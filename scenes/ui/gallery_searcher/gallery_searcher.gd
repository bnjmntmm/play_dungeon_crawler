extends Control

@export var toggle_key: Key = KEY_ENTER
@export var display_name_property: StringName = &"display_name"
@export var partial_match: bool = true

const COLOR_ERROR := Color(1.0, 0.4, 0.4)
const COLOR_PROMPT := Color.WHITE

@onready var text_edit: TextEdit = $TextEdit
@onready var error_type: Label = $ColorRect/MarginContainer/ErrorType
@onready var color_rect: ColorRect = $ColorRect

var _pending_index: int = -1
var _awaiting_confirm: bool = false


func _ready() -> void:
	visible = false
	error_type.visible = false
	text_edit.gui_input.connect(_on_text_edit_gui_input)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == toggle_key:
			if visible:
				close_search()
			else:
				open_search()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close_search()
			get_viewport().set_input_as_handled()


func open_search() -> void:
	visible = true
	_reset_state()
	text_edit.text = ""
	text_edit.call_deferred("grab_focus")


func close_search() -> void:
	_reset_state()
	visible = false
	text_edit.release_focus()


func _reset_state() -> void:
	_pending_index = -1
	_awaiting_confirm = false
	_hide_error()


func _on_text_edit_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	# While the save question is showing, only y / n count; everything else is swallowed.
	if _awaiting_confirm:
		text_edit.accept_event()
		if event.echo:
			return
		match event.keycode:
			KEY_Y:
				_confirm_save()
			KEY_N:
				_cancel_save()
		return

	# TextEdit is multiline, so swallow Enter and use it to submit instead.
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		text_edit.accept_event()
		_submit(text_edit.text.strip_edges())


func _submit(query: String) -> void:
	if query.is_empty():
		return

	var matches: Array[int] = _search(query)

	if matches.size() == 1:
		_pending_index = matches[0]
		var config: LevelConfig = GameManager.all_level_configs[_pending_index]
		_awaiting_confirm = true
		_show_message(
			"Level \"%s\" gefunden. Ergebnis speichern? (y/n)" % str(config.display_name),
			COLOR_PROMPT
		)
		GameManager.gallery_search(_pending_index)
	elif matches.size() > 1:
		var msg := "Mehrere Level mit diesem Suchbegriff gefunden! Bitte den Begriff anpassen."
		_show_message(msg, COLOR_ERROR)
		push_warning(msg)
	else:
		_show_message("Keine Ergebnisse mit diesem Suchbegriff", COLOR_ERROR)


func _confirm_save() -> void:
	var config: LevelConfig = GameManager.all_level_configs[_pending_index]
	GameManager.scripted_level_config = config
	close_search()


func _cancel_save() -> void:
	_pending_index = -1
	_awaiting_confirm = false
	_hide_error()
	text_edit.text = ""
	close_search()


func _show_message(msg: String, color: Color) -> void:
	error_type.add_theme_color_override("font_color", color)
	error_type.text = msg
	color_rect.visible = true
	error_type.visible = true


func _hide_error() -> void:
	color_rect.visible = false
	error_type.visible = false


func _search(query: String) -> Array[int]:
	var q := query.to_lower()
	var exact: Array[int] = []
	var partial: Array[int] = []

	var configs := GameManager.all_level_configs
	for i in configs.size():
		var config: LevelConfig = configs[i]
		if config == null:
			continue
		var name_str := str(config.display_name).to_lower()
		if name_str == q:
			exact.append(i)
		elif partial_match and name_str.contains(q):
			partial.append(i)

	# An exact match wins over partial ones.
	if exact.size() > 0:
		return exact
	return partial
