extends Control

@export var partial_match: bool = true

const COLOR_ERROR := Color(1.0, 0.4, 0.4)
const SHAKE_STEP := 0.04   # seconds per shake movement
const ERROR_HOLD := 0.4    # seconds the message stays readable before leaving
const ERROR_RISE := 40.0   # pixels the message floats up
const ERROR_FADE := 0.6    # seconds for the rise + fade out

@onready var text_edit: TextEdit = $TextEdit
@onready var error_type: Label = $ErrorType
@onready var selected_level_indicator: TextureRect = $SelectedLevelIndicator
@onready var gallery_sfx: AudioStreamPlayer = $"../../GallerySFX"

const SWIPE_LEFT = preload("uid://berg3w4jyfyrm")
const SWIPE_RIGHT = preload("uid://ckw7ebb5xkyhv")

var _rest_position: Vector2
var _error_tween: Tween


func _ready() -> void:
	error_type.visible = false
	text_edit.editable = true
	# FOCUS_CLICK: only mouse clicks or an explicit grab_focus() can focus the field.
	# With FOCUS_ALL, pressing an arrow key (UI navigation) would focus it by accident,
	# and Space would then be typed instead of selecting the level.
	text_edit.focus_mode = Control.FOCUS_CLICK

	# Buttons must not take focus, otherwise Space / A / Cross would "press" them
	# instead of selecting the level. Mouse clicks still work.
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		button.focus_mode = Control.FOCUS_NONE

	# Whenever the field loses focus (Esc, finished search, mouse click elsewhere),
	# show the current level's title again.
	text_edit.focus_exited.connect(_sync_to_current_level)

	GameManager.loaded_new_room.connect(_on_loaded_new_room.unbind(1))
	_sync_to_current_level()


# --- Syncing with the GameManager ------------------------------------------------

func _on_loaded_new_room() -> void:
	_sync_to_current_level()


func _sync_to_current_level() -> void:
	var config := _current_config()
	text_edit.text = str(config.display_name) if config != null else ""
	_update_indicator()


func _current_config() -> LevelConfig:
	# The level that is actually loaded, independent of gallery_index.
	return GameManager.current_level_config


func _update_indicator() -> void:
	var current := _current_config()
	selected_level_indicator.visible = (
		current != null and GameManager.scripted_level_config == current
	)


# --- Input ------------------------------------------------------------------------
#
# Enter (not typing)      -> focus the text field so you can type
# Enter (typing)          -> run the search
# Esc (typing)            -> leave the text field
# Space / A / Cross       -> select the shown level as scripted_level_config
#                            (while typing, Space is a normal character, so only
#                            the gamepad button selects)

func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	var typing := text_edit.has_focus()

	if event is InputEventKey and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		if typing:
			_submit(text_edit.text.strip_edges())
		else:
			# Start a new search: clear the old text so no arrow-key editing is needed.
			text_edit.text = ""
			text_edit.grab_focus()
		return

	if typing:
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			text_edit.release_focus()
		elif event is InputEventJoypadButton and _is_select_event(event):
			get_viewport().set_input_as_handled()
			_select_current_level()
		return

	if _is_select_event(event):
		get_viewport().set_input_as_handled()
		_select_current_level()


func _is_select_event(event: InputEvent) -> bool:
	# Face button down (A on Xbox, Cross on PlayStation) is checked directly, so it
	# works even if ui_accept has no joypad button in your Input Map.
	if event is InputEventJoypadButton:
		return event.button_index == JOY_BUTTON_A
	# Space (and anything else mapped to ui_accept).
	return event.is_action_pressed("ui_accept")


func _submit(query: String) -> void:
	if query.is_empty():
		return

	var matches: Array[int] = _search(query)

	if matches.size() == 1:
		var index := matches[0]
		if GameManager.all_level_configs[index] != GameManager.current_level_config:
			# Jump to that level; loaded_new_room will update the text afterwards.
			GameManager.gallery_search(index)
		# Leave the field so Space / A / Cross can select the level right away.
		text_edit.release_focus()
	elif matches.size() > 1:
		var msg := "Mehrere Level mit diesem Suchbegriff gefunden! Bitte den Begriff anpassen."
		push_warning(msg)
		_show_error(msg)
	else:
		_show_error("Keine Ergebnisse mit diesem Suchbegriff")


func _select_current_level() -> void:
	var config := _current_config()
	if config == null:
		return
	GameManager.scripted_level_config = config
	_update_indicator()


# --- Error feedback: shake, float up, fade out ---------------------------------------

func _show_error(msg: String) -> void:
	if _error_tween != null and _error_tween.is_valid():
		_error_tween.kill()
		error_type.position = _rest_position
	else:
		_rest_position = error_type.position

	error_type.add_theme_color_override("font_color", COLOR_ERROR)
	error_type.text = msg
	error_type.modulate.a = 1.0
	error_type.visible = true

	var shake: Array[float] = [14.0, -14.0, 10.0, -10.0, 5.0, 0.0]
	var t := 0.0

	_error_tween = create_tween().set_parallel(true)
	for offset: float in shake:
		_error_tween.tween_property(
			error_type, "position:x", _rest_position.x + offset, SHAKE_STEP
		).set_delay(t)
		t += SHAKE_STEP

	var leave_at := t + ERROR_HOLD
	_error_tween.tween_property(
		error_type, "position:y", _rest_position.y - ERROR_RISE, ERROR_FADE
	).set_delay(leave_at).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_error_tween.tween_property(
		error_type, "modulate:a", 0.0, ERROR_FADE
	).set_delay(leave_at)

	_error_tween.finished.connect(_on_error_finished)


func _on_error_finished() -> void:
	error_type.visible = false
	error_type.position = _rest_position
	error_type.modulate.a = 1.0


# --- Search -------------------------------------------------------------------------

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


# --- Buttons ------------------------------------------------------------------------

func _on_button_pressed() -> void:
	GameManager.gallery_switch(false)
	gallery_sfx.stream = SWIPE_LEFT
	gallery_sfx.play()


func _on_button_2_pressed() -> void:
	GameManager.gallery_switch(true)
	gallery_sfx.stream = SWIPE_RIGHT
	gallery_sfx.play()
