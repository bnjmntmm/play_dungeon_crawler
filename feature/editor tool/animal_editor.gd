@tool
class_name AnimalEditor
extends Control

signal saved(code: String)
signal animal_picked(code: String)

@onready var save_button: Button = %SaveButton
@onready var grid_con = %TextureGrid
@onready var image_dir = "res://custom_data/"
@export var grid_columns:int = 6
@export var grid_item_size:Vector2i = Vector2i(0,150)
@export var grid_item_margin:int = 5
var buttonDictionary: Dictionary[Button, ImageTexture]
var buttonPathDictionary: Dictionary[Button, String]
var buttonFolderDictionary: Dictionary[Button, String]

const ImageGridJob = preload("res://feature/editor tool/image_grid_job.gd")
var _image_job: RefCounted
var _retired_image_jobs: Array[RefCounted] = []
var _image_cache: Dictionary[String, Dictionary] = {}
var _visible_image_paths: Dictionary[String, bool] = {}

# currently selected image
var selected_image_path:String = ""
var selected_folder_name:String = ""

@onready var health_text_edit: LineEdit = %Health_TextEdit
@onready var damage_text_edit: LineEdit = %Damage_TextEdit
@onready var speed_text_edit: LineEdit = %Speed_TextEdit
@onready var attack_speed_text_edit: LineEdit = %AttackSpeed_TextEdit
@onready var attack_speed_progress_bar: ProgressBar = %"Attack Speed ProgressBar"
@onready var detection_range_text_edit: LineEdit = %DetectionRange_TextEdit

@onready var sound_dir = "res://assets/sounds/tiere/"
@onready var sound_option: OptionButton = %SoundOption
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
var soundDictionary: Dictionary[int, AudioStream]

@onready var animation_option_button: OptionButton = %"Animation OptionButton"
var animationDictionary: Dictionary[int, String] = {
	0 : "idle",
	1 : "woble",
	2 : "jump",
	3 : "squish"
}

@onready var info_label: Label = %InfoLabel
@onready var code_edit: LineEdit = %CodeEdit
@onready var name_edit: LineEdit = %NameEdit

const invalid_color:Color = Color(1,0,0)
@onready var animal_scene: AnimalScene = %AnimalScene
@onready var attack_timer: Timer = %AttackTimer

var config_file: AnimalConfig = AnimalConfig.new()
## False until an image is picked or an existing animal is loaded.
var form_unlocked: bool = false
var saved_path:String = ""
var default_sprite: Texture2D
var detection_ring: Line2D

const MAX_PREVIEW_ZOOM: float = 6.0
const RING_COLOR: Color = Color(1, 0.85, 0.2, 0.9)

## Health is capped at 10 (and must be above 0).
const HEALTH_MAX: int = 10
## Movement speed is capped at: 10
const MAX_MOVEMENT_SPEED : int = 10
## Attack speed is entered as 1-10, where 10 is the fastest.
const ATTACK_SPEED_MAX: int = 10
## Max Wahrnehmungsreichweite
const MAX_REACH_DISTANCE : int = 100
## The stored cooldown in seconds: entering 1 gives SLOWEST, entering 10 gives FASTEST.
const COOLDOWN_SLOWEST: float = 1.0
const COOLDOWN_FASTEST: float = 0.1

func _ready() -> void:
	attack_speed_progress_bar.step = 0.01

func _process(delta: float) -> void:
	_process_image_jobs()
	# The bar fills up until the next attack.
	attack_speed_progress_bar.max_value = attack_timer.wait_time
	attack_speed_progress_bar.value = attack_timer.wait_time - attack_timer.time_left

func initialize():
	print("initializing texture grid")
	clear_grid()
	populate_texture_selection()
	populate_sound_selection()
	
	default_sprite = _get_preview_sprite().texture
	use_kid(LevelCode.create_unused(KidFolders.CUSTOM_DATA_PATH))

func use_kid(code: String) -> void:
	code_edit.text = code
	var animal: AnimalConfig = KidFolders.load_animal(code)
	if animal:
		_load_into_form(animal)
		saved_path = KidFolders.get_animal_path(code)
	else:
		_reset_form()
		saved_path = ""

func _reset_form() -> void:
	config_file = AnimalConfig.new()
	selected_image_path = ""
	selected_folder_name = ""
	name_edit.text = ""
	for text: LineEdit in [health_text_edit, damage_text_edit, speed_text_edit, attack_speed_text_edit, detection_range_text_edit]:
		text.text = ""
		text.set_modulate(Color(1,1,1))
	_get_preview_sprite().texture = default_sprite
	_update_detection_ring()
	sound_option.select(-1)
	animation_option_button.select(0)
	_show_info("", false)
	_set_form_unlocked(false)

## Locks or unlocks everything a kid can edit. The stepper buttons are guarded in text_increment().
func _set_form_unlocked(unlocked: bool) -> void:
	form_unlocked = unlocked
	for text: LineEdit in [health_text_edit, damage_text_edit, speed_text_edit, attack_speed_text_edit, detection_range_text_edit, name_edit]:
		text.editable = unlocked
	sound_option.disabled = not unlocked
	animation_option_button.disabled = not unlocked
	save_button.disabled = not unlocked

func _show_pick_image_hint() -> void:
	_show_info("Wähle zuerst unten ein Bild für dein Tier aus.", true)

func _load_into_form(animal: AnimalConfig) -> void:
	# Unlock first: the change handlers ignore input while the form is locked.
	_set_form_unlocked(true)
	config_file = animal
	selected_image_path = ""
	selected_folder_name = ""
	name_edit.text = animal.display_name
	var values: Dictionary[LineEdit, float] = {
		health_text_edit: animal.health,
		damage_text_edit: animal.damage,
		speed_text_edit: animal.speed,
		attack_speed_text_edit: _cooldown_to_ui(animal.attack_speed),
		detection_range_text_edit: animal.detection_range,
	}
	for text: LineEdit in values:
		text.text = str(int(values[text]))
		text.text_changed.emit(text.text)
	_get_preview_sprite().texture = animal.sprite if animal.sprite else default_sprite
	sound_option.select(-1)
	for index: int in soundDictionary:
		if animal.sound and soundDictionary[index].data == animal.sound.data:
			sound_option.select(index)
			audio_stream_player.stream = soundDictionary[index]
	animation_option_button.select(animal.animation)
	_show_info("", false)

## 1 -> 1.0 s (slowest), 10 -> 0.1 s (fastest).
func _ui_to_cooldown(ui_value: int) -> float:
	var t: float = float(ui_value - 1) / float(ATTACK_SPEED_MAX - 1)
	return snappedf(lerpf(COOLDOWN_SLOWEST, COOLDOWN_FASTEST, t), 0.01)

## Reverse of _ui_to_cooldown. Old configs with bigger values end up as 1.
func _cooldown_to_ui(cooldown: float) -> int:
	var t: float = (cooldown - COOLDOWN_SLOWEST) / (COOLDOWN_FASTEST - COOLDOWN_SLOWEST)
	return clampi(roundi(1.0 + t * float(ATTACK_SPEED_MAX - 1)), 1, ATTACK_SPEED_MAX)

func _get_preview_camera() -> Camera2D:
	return animal_scene.get_parent().get_node("Camera2D") as Camera2D

## Collision shapes are only drawn inside the Godot editor, so the range gets its own ring.
## The camera zooms out for big ranges, so the whole ring always fits next to the animal.
func _update_detection_ring() -> void:
	if detection_ring == null:
		detection_ring = Line2D.new()
		detection_ring.default_color = RING_COLOR
		animal_scene.add_child(detection_ring)
	var radius: float = maxf(config_file.detection_range, 0.0)
	var points: PackedVector2Array = []
	for i: int in 65:
		points.append(Vector2.from_angle(TAU * i / 64.0) * radius)
	detection_ring.points = points
	detection_ring.visible = radius > 0.0
	var camera: Camera2D = _get_preview_camera()
	var half_view: Vector2 = Vector2(animal_scene.get_viewport().size) / 2.0
	var zoom: float = MAX_PREVIEW_ZOOM
	if radius > 0.0:
		zoom = clampf(minf(half_view.x, half_view.y) * 0.85 / radius, 0.5, MAX_PREVIEW_ZOOM)
	camera.zoom = Vector2.ONE * zoom
	detection_ring.width = 3.0 / zoom

## Zooms back in so the animation is clearly visible. The next range change zooms out again.
func _reset_preview_zoom() -> void:
	_get_preview_camera().zoom = Vector2.ONE * MAX_PREVIEW_ZOOM
	if detection_ring:
		detection_ring.width = 3.0 / MAX_PREVIEW_ZOOM

func _get_preview_sprite() -> Sprite2D:
	return animal_scene.get_node("SpriteScaler/Sprite2D") as Sprite2D

func _show_info(message: String, is_error: bool) -> void:
	info_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if is_error else Color(0.55, 1, 0.6))
	info_label.text = message

func clear_grid():
	for child in grid_con.get_children():
		child.queue_free()
	buttonDictionary.clear()
	buttonPathDictionary.clear()
	buttonFolderDictionary.clear()

# Scan and decode in a worker; add a few thumbnails per frame to keep input responsive.
func populate_texture_selection():
	if _image_job:
		_image_job.cancel()
		_retired_image_jobs.append(_image_job)
	grid_con.columns = grid_columns
	_visible_image_paths.clear()
	var stamps: Dictionary = {}
	for path: String in _image_cache:
		stamps[path] = _image_cache[path].stamp
	_image_job = ImageGridJob.new()
	_image_job.start(image_dir, stamps)

func _process_image_jobs() -> void:
	for index: int in range(_retired_image_jobs.size() - 1, -1, -1):
		if _retired_image_jobs[index].is_finished():
			_retired_image_jobs[index].wait()
			_retired_image_jobs.remove_at(index)
	if _image_job == null:
		return
	var finished: bool = _image_job.is_finished()
	var entries: Array[Dictionary] = _image_job.take_pending()
	for entry: Dictionary in entries:
		var path: String = entry.path
		if entry.has("image"):
			_image_cache[path] = {"stamp": entry.stamp, "texture": ImageTexture.create_from_image(entry.image)}
		if _image_cache.has(path):
			_visible_image_paths[path] = true
			_add_image_button(path, entry.folder, _image_cache[path].texture)
	# An empty batch after worker completion means the queue has been drained.
	if entries.is_empty() and finished:
		_image_job.wait()
		_image_job = null
		for path: String in _image_cache.keys():
			if not _visible_image_paths.has(path):
				_image_cache.erase(path)

func _exit_tree() -> void:
	if _image_job:
		_image_job.cancel()
		_retired_image_jobs.append(_image_job)
		_image_job = null
	for job: RefCounted in _retired_image_jobs:
		job.cancel()
	for job: RefCounted in _retired_image_jobs:
		job.wait()
	_retired_image_jobs.clear()

func _add_image_button(full_path: String, folder_name: String, tex: ImageTexture) -> void:
	var margin_con = MarginContainer.new()
	grid_con.add_child(margin_con)
	margin_con.add_theme_constant_override("margin_top", grid_item_margin)
	margin_con.add_theme_constant_override("margin_left", grid_item_margin)
	margin_con.add_theme_constant_override("margin_bottom", grid_item_margin)
	margin_con.add_theme_constant_override("margin_right", grid_item_margin)
	margin_con.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_con.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var button = Button.new()
	margin_con.add_child(button)
	button.icon = tex
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.custom_minimum_size = grid_item_size
	button.tooltip_text = folder_name + "/" + full_path.get_file()

	buttonDictionary[button] = tex
	buttonPathDictionary[button] = full_path
	buttonFolderDictionary[button] = folder_name

	button.pressed.connect(on_texture_button_clicked.bind(button))

## Picking an image loads the AnimalConfig that uses it, or starts a fresh one.
func on_texture_button_clicked(button: Button) -> void:
	var png_path: String = buttonPathDictionary.get(button, "")
	var folder: String = buttonFolderDictionary.get(button, "")

	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(png_path)) != OK or image.is_empty():
		_show_info("Das Bild konnte nicht geladen werden. Bitte aktualisieren.", true)
		return
	var texture := ImageTexture.create_from_image(image)
	var code: String = _find_code_for_image(png_path, texture)
	if code.is_empty():
		# New sprite: start from scratch.
		code = _new_code_for_folder(folder)
		_reset_form()
		saved_path = ""
	else:
		_load_into_form(KidFolders.load_animal(code))
		saved_path = KidFolders.get_animal_path(code)

	# Always bind the config to the chosen image.
	selected_image_path = png_path
	selected_folder_name = folder
	config_file.source_png = png_path
	config_file.sprite = texture
	_get_preview_sprite().texture = config_file.sprite
	code_edit.text = code
	_set_form_unlocked(true)
	animal_picked.emit(code)

## Returns the kid code of the AnimalConfig that uses this PNG, or "" if none does.
func _find_code_for_image(png_path: String, texture: ImageTexture) -> String:
	var legacy_code: String = ""
	var texture_data: PackedByteArray = texture.get_image().get_data()
	for folder: Dictionary in KidFolders.list():
		var animal: AnimalConfig = KidFolders.load_animal(folder.code)
		if animal == null:
			continue
		if animal.source_png == png_path:
			return folder.code
		# Older configs saved before source_png existed: match by pixel data.
		if animal.source_png.is_empty() and animal.sprite and legacy_code.is_empty():
			if animal.sprite.get_image().get_data() == texture_data:
				legacy_code = folder.code
	return legacy_code

## The PNG's own folder name is the natural code, unless that code is already taken by another animal.
func _new_code_for_folder(folder: String) -> String:
	var code: String = LevelCode.clean(folder)
	if code.is_empty() or FileAccess.file_exists(KidFolders.get_animal_path(code)):
		return LevelCode.create_unused(KidFolders.CUSTOM_DATA_PATH)
	return code

func populate_sound_selection():
	print("populating sound selection")
	var dir = DirAccess.open(sound_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		var i:int = 0
		while file_name != "":
			
			if dir.current_is_dir() == false:
				if file_name.ends_with(".wav"):
					var stream = AudioStreamWAV.load_from_file(sound_dir + file_name)
					
					var item_name:String = file_name.get_basename()
					var cut_item_name:String = item_name.get_slice("-",1)
					sound_option.add_item(cut_item_name)
					
					soundDictionary[i] = stream
					i = i + 1
			file_name = dir.get_next()
	else:
		print("Sound Filepath ", sound_dir , " could not be accessed")
	sound_option.select(-1)
	
#export the config
func _on_save_button_pressed() -> void:
	var problem: String = _find_save_problem()
	if not problem.is_empty():
		_show_info(problem, true)
		return
	config_file.damage = 1
	var code: String = LevelCode.clean(code_edit.text)
	var path: String = KidFolders.get_animal_path(code)
	config_file.display_name = name_edit.text.strip_edges()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(config_file, path) != OK:
		_show_info("Speichern hat nicht geklappt. Sag dem Dev-Team Bescheid.", true)
		return
	saved_path = path
	
	# additionally save right next to the chosen png as animal_<folder_name>.tres
	# (skipped if that file already belongs to a different animal)
	if selected_image_path != "" and selected_folder_name != "":
		var png_side_path:String = selected_image_path.get_base_dir().path_join("animal_" + selected_folder_name + ".tres")
		if png_side_path != path:
			var existing: AnimalConfig = null
			if FileAccess.file_exists(png_side_path):
				existing = ResourceLoader.load(png_side_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimalConfig
			if existing == null or existing.source_png == selected_image_path:
				if ResourceSaver.save(config_file, png_side_path) != OK:
					_show_info("Speichern neben dem Bild hat nicht geklappt: " + png_side_path, true)
					return
				print("also saved file to: ", png_side_path)
	
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_show_info("Gespeichert! Jetzt kannst du dein Tier in den Raum setzen.", false)
	saved.emit(code)

func _find_save_problem() -> String:
	if not form_unlocked:
		return "Wähle zuerst unten ein Bild für dein Tier aus."
	# Max value per field, -1 means no upper limit.
	var limits: Dictionary[LineEdit, int] = {
		health_text_edit: HEALTH_MAX,
		speed_text_edit: MAX_MOVEMENT_SPEED,
		attack_speed_text_edit: ATTACK_SPEED_MAX,
		detection_range_text_edit: MAX_REACH_DISTANCE,
	}
	for text: LineEdit in limits:
		var max_value: int = limits[text]
		if not text.text.is_valid_int() or int(text.text) <= 0:
			return "Alle Werte brauchen eine Zahl größer als 0."
		if max_value > 0 and int(text.text) > max_value:
			return "Dieser Wert darf höchstens %d sein." % max_value
	if config_file.sprite == null:
		return "Wähle unten ein Bild für dein Tier aus."
	if sound_option.get_selected_id() == -1:
		return "Wähle einen Ton für dein Tier aus."
	var code: String = LevelCode.clean(code_edit.text)
	if code.is_empty():
		return "Gib zuerst deinen Code ein."
	var path: String = KidFolders.get_animal_path(code)
	if path != saved_path and FileAccess.file_exists(path):
		return "Diesen Code gibt es schon. Nimm einen anderen."
	return ""

func _on_animation_option_button_item_selected(index: int) -> void:
	if not form_unlocked:
		return
	config_file.animation = index
	_reset_preview_zoom()
	if animal_scene.get_node_or_null("AnimationPlayer") != null:
		var anim_player = animal_scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
		var animString:String
		animString = animationDictionary[index]
		anim_player.stop()
		anim_player.play(animString)

## Picking a sound does not play it, only the preview button does.
func _on_sound_option_item_selected(index: int) -> void:
	if not form_unlocked:
		return
	audio_stream_player.stream = soundDictionary.get(index)
	config_file.sound = soundDictionary.get(index)

func _on_sound_preview_button_pressed() -> void:
	audio_stream_player.play()

## Accepts whole numbers above 0 and clamps them to max_value (if one is given).
## While the form is locked nothing is accepted.
func change_value(text: LineEdit, new_text: String, max_value: int = -1) -> bool:
	if not form_unlocked:
		return false
	if new_text.is_valid_int() and int(new_text) > 0:
		if max_value > 0 and int(new_text) > max_value:
			var caret: int = text.caret_column
			text.text = str(max_value)
			text.caret_column = mini(caret, text.text.length())
		text.set_modulate(Color(1,1,1))
		return true
	else:
		text.set_modulate(invalid_color)
		return false
		
func _on_health_text_edit_text_changed(new_text: String) -> void:
	if change_value(health_text_edit, new_text, HEALTH_MAX):
		config_file.health = int(health_text_edit.text)
		print("new health value: ", config_file.health)

func _on_damage_text_edit_text_changed(new_text: String) -> void:
	if change_value(damage_text_edit, new_text):
		config_file.damage = int(damage_text_edit.text)
		print("new damage value: ", config_file.damage)

func _on_speed_text_edit_text_changed(new_text: String) -> void:
	if change_value(speed_text_edit, new_text, MAX_MOVEMENT_SPEED):
		config_file.speed = int(speed_text_edit.text)
		print("new speed value: ", config_file.speed)

## The field takes 1-10 (10 = fastest). The config stores the cooldown in seconds (1.0 down to 0.1).
func _on_attack_speed_text_edit_text_changed(new_text: String) -> void:
	if change_value(attack_speed_text_edit, new_text, ATTACK_SPEED_MAX):
		config_file.attack_speed = _ui_to_cooldown(int(attack_speed_text_edit.text))
		print("new attack cooldown: ", config_file.attack_speed)
		attack_timer.wait_time = config_file.attack_speed
		attack_timer.start()
	else:
		attack_timer.stop()

func _on_detection_range_text_edit_text_changed(new_text: String) -> void:
	if change_value(detection_range_text_edit, new_text, MAX_REACH_DISTANCE):
		config_file.detection_range = int(detection_range_text_edit.text)
		print("new detection rate value: ", config_file.detection_range)
	_update_detection_ring()

## Steps the value and keeps it between 1 and max_value (no upper limit if max_value <= 0).
## Does nothing but show a hint while the form is locked.
func text_increment(text: LineEdit, value: int, max_value: int = -1) -> int:
	if not form_unlocked:
		_show_pick_image_hint()
		return 0
	var i: int = int(text.text) if text.text.is_valid_int() else 0
	i = maxi(i + value, 1)
	if max_value > 0:
		i = mini(i, max_value)
	text.text = str(i)
	text.text_changed.emit(text.text)
	return i

func _on_health_up_button_pressed() -> void:
	text_increment(health_text_edit, 1, HEALTH_MAX)

func _on_health_down_button_pressed() -> void:
	text_increment(health_text_edit, -1, HEALTH_MAX)

func _on_damage_up_button_pressed() -> void:
	text_increment(damage_text_edit, 1, )

func _on_damage_down_button_pressed() -> void:
	text_increment(damage_text_edit, -1)

func _on_speed_up_button_pressed() -> void:
	text_increment(speed_text_edit, 1, MAX_MOVEMENT_SPEED)

func _on_speed_down_button_pressed() -> void:
	text_increment(speed_text_edit, -1, MAX_MOVEMENT_SPEED)

func _on_attack_speed_up_button_pressed() -> void:
	text_increment(attack_speed_text_edit, 1, ATTACK_SPEED_MAX)

func _on_attack_speed_down_button_pressed() -> void:
	text_increment(attack_speed_text_edit, -1, ATTACK_SPEED_MAX)

## The text_changed handler sets the range and redraws the ring, so these only step the value.
func _on_detection_range_up_button_pressed() -> void:
	text_increment(detection_range_text_edit, 10, MAX_REACH_DISTANCE)

func _on_detection_range_down_button_pressed() -> void:
	text_increment(detection_range_text_edit, -10, MAX_REACH_DISTANCE)

## The timer now only drives the progress bar. Sound is played by the preview button only.
func _on_attack_timer_timeout() -> void:
	pass

func _on_refresh_pressed() -> void:
	clear_grid()
	populate_texture_selection()
