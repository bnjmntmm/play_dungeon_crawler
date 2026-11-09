@tool
class_name AnimalEditor
extends Control

signal saved(code: String)

@onready var save_button: Button = %SaveButton
@onready var grid_con = %TextureGrid
@onready var image_dir = "res://feature/editor tool/Cracks/"
@export var grid_columns:int = 6
@export var grid_item_size:Vector2i = Vector2i(0,150)
@export var grid_item_margin:int = 5
var buttonDictionary: Dictionary[Button, ImageTexture]

@onready var health_text_edit: LineEdit = %Health_TextEdit
@onready var damage_text_edit: LineEdit = %Damage_TextEdit
@onready var speed_text_edit: LineEdit = %Speed_TextEdit
@onready var attack_speed_text_edit: LineEdit = %AttackSpeed_TextEdit
@onready var attack_speed_progress_bar: ProgressBar = %"Attack Speed ProgressBar"
@onready var detection_range_text_edit: LineEdit = %DetectionRange_TextEdit

@onready var sound_dir = "res://feature/editor tool/Sounds/"
@onready var sound_option: OptionButton = %SoundOption
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
var soundDictionary: Dictionary[int, AudioStream]

@onready var info_label: Label = %InfoLabel
@onready var code_edit: LineEdit = %CodeEdit
@onready var name_edit: LineEdit = %NameEdit

const invalid_color:Color = Color(1,0,0)
@onready var animal_scene: AnimalScene = %AnimalScene
@onready var attack_timer: Timer = %AttackTimer

var config_file:AnimalConfig
var saved_path:String = ""
var default_sprite: Texture2D
var detection_ring: Line2D

const MAX_PREVIEW_ZOOM: float = 6.0
const RING_COLOR: Color = Color(1, 0.85, 0.2, 0.9)

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	attack_speed_progress_bar.max_value = attack_timer.wait_time
	attack_speed_progress_bar.value = attack_timer.time_left

func initialize():
	print("initializing texture grid")
	clear_grid()
	populate_texture_selection()
	populate_sound_selection()
	
	default_sprite = _get_preview_sprite().texture
	use_kid(LevelCode.create_unused(KidFolders.CUSTOM_DATA_PATH))

## Shows the animal saved in this kid folder, or an empty form for a new one.
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
	name_edit.text = ""
	for text: LineEdit in [health_text_edit, damage_text_edit, speed_text_edit, attack_speed_text_edit, detection_range_text_edit]:
		text.text = ""
		text.set_modulate(Color(1,1,1))
	_get_preview_sprite().texture = default_sprite
	_update_detection_ring()
	sound_option.select(-1)
	%"Animation OptionButton".select(0)
	attack_timer.stop()
	_show_info("", false)

func _load_into_form(animal: AnimalConfig) -> void:
	config_file = animal
	name_edit.text = animal.display_name
	var values: Dictionary[LineEdit, float] = {
		health_text_edit: animal.health,
		damage_text_edit: animal.damage,
		speed_text_edit: animal.speed,
		attack_speed_text_edit: animal.attack_speed,
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
	%"Animation OptionButton".select(animal.animation)
	_show_info("", false)

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
	var camera: Camera2D = animal_scene.get_parent().get_node("Camera2D")
	var half_view: Vector2 = Vector2(animal_scene.get_viewport().size) / 2.0
	var zoom: float = MAX_PREVIEW_ZOOM
	if radius > 0.0:
		zoom = clampf(minf(half_view.x, half_view.y) * 0.85 / radius, 0.5, MAX_PREVIEW_ZOOM)
	camera.zoom = Vector2.ONE * zoom
	detection_ring.width = 3.0 / zoom

func _get_preview_sprite() -> Sprite2D:
	return animal_scene.get_node("Sprite2D") as Sprite2D

func _show_info(message: String, is_error: bool) -> void:
	info_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if is_error else Color(0.55, 1, 0.6))
	info_label.text = message

func clear_grid():
	for child in grid_con.get_children():
		child.queue_free()
	
func populate_texture_selection():
	grid_con.columns = grid_columns
	print("populating texture grid")
	var dir = DirAccess.open(image_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if dir.current_is_dir() == false:
				# filter by file ending
				var img:Image
				var tex:ImageTexture
				
				if file_name.ends_with("png"):
					#print("file: " + file_name)
					img = Image.load_from_file(image_dir + file_name)
					tex = ImageTexture.create_from_image(img)
					
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
					#print("tex: ", tex)
					button.icon = tex
					button.expand_icon = true
					button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
					button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
					button.custom_minimum_size = grid_item_size
					
					buttonDictionary.get_or_add(button)
					buttonDictionary.set(button, tex)
					
					# on button press setze variable (verknüpfe das signal I guess)
					button.pressed.connect(on_texture_button_clicked.bind(button))
			file_name = dir.get_next()
	else:
		print("Textures Filepath ", image_dir , " could not be accessed")

func on_texture_button_clicked(button:Button):
	for child in animal_scene.get_children():
		if child is Sprite2D:
			child.texture = buttonDictionary.get(button)
	config_file.sprite = buttonDictionary.get(button)

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
					#print("adding file: ", file_name)
					sound_option.add_item(item_name)
					
					soundDictionary.get_or_add(i)
					soundDictionary.set(i, stream)
					i = i + 1
			file_name = dir.get_next()
	else:
		print("Sound Filepath ", sound_dir , " could not be accessed")
	sound_option.select(-1)
	#print(soundDictionary)
	
#export the config
func _on_save_button_pressed() -> void:
	var problem: String = _find_save_problem()
	if not problem.is_empty():
		_show_info(problem, true)
		return
	var code: String = LevelCode.clean(code_edit.text)
	var path: String = KidFolders.get_animal_path(code)
	config_file.display_name = name_edit.text.strip_edges()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(config_file, path) != OK:
		_show_info("Speichern hat nicht geklappt. Sag dem Dev-Team Bescheid.", true)
		return
	saved_path = path
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_show_info("Gespeichert! Jetzt kannst du dein Tier in den Raum setzen.", false)
	saved.emit(code)

func _find_save_problem() -> String:
	for text: LineEdit in [health_text_edit, damage_text_edit, speed_text_edit, attack_speed_text_edit, detection_range_text_edit]:
		if not text.text.is_valid_int() or int(text.text) <= 0:
			return "Alle Werte brauchen eine Zahl größer als 0."
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
	config_file.animation = index

func _on_sound_option_item_selected(index: int) -> void:
	audio_stream_player.stream = soundDictionary.get(index)
	audio_stream_player.play()
	config_file.sound = soundDictionary.get(index)

func _on_sound_preview_button_pressed() -> void:
	audio_stream_player.play()

func change_value(text:LineEdit, new_text:String):
	if new_text.is_valid_int() and int(new_text) >0:
		text.set_modulate(Color(1,1,1))
		return true
	else:
		text.set_modulate(invalid_color)
		return false
		
func _on_health_text_edit_text_changed(new_text: String) -> void:
	if change_value(health_text_edit, new_text):
		config_file.health = int(new_text)
		print("new health value: ", config_file.health)

func _on_damage_text_edit_text_changed(new_text: String) -> void:
	if change_value(damage_text_edit, new_text):
		config_file.damage = int(new_text)
		print("new damage value: ", config_file.damage)

func _on_speed_text_edit_text_changed(new_text: String) -> void:
	if change_value(speed_text_edit, new_text):
		config_file.speed = int(new_text)
		print("new speed value: ", config_file.speed)

func _on_attack_speed_text_edit_text_changed(new_text: String) -> void:
	if change_value(attack_speed_text_edit, new_text):
		config_file.attack_speed = int(new_text)
		print("new attack speed value: ", config_file.attack_speed)
		attack_timer.autostart = true
		attack_timer.wait_time = float(config_file.attack_speed)
	else:
		attack_timer.autostart = false

func _on_detection_range_text_edit_text_changed(new_text: String) -> void:
	if change_value(detection_range_text_edit, new_text):
		config_file.detection_range = int(new_text)
		print("new detection rate value: ", config_file.detection_range)
	_update_detection_ring()

func text_increment(text:LineEdit, value: int):
	var i:int
	if text.text == "":
		i = 0
	if text.text.is_valid_int():
		i = int(text.text)
	i += value
	if i >= 0:
		text.text = str(i)
		text.text_changed.emit(str(i))
		return i

func _on_health_up_button_pressed() -> void:
	text_increment(health_text_edit, 1)

func _on_health_down_button_pressed() -> void:
	text_increment(health_text_edit, -1)

func _on_damage_up_button_pressed() -> void:
	text_increment(damage_text_edit, 1)

func _on_damage_down_button_pressed() -> void:
	text_increment(damage_text_edit, -1)

func _on_speed_up_button_pressed() -> void:
	text_increment(speed_text_edit, 1)

func _on_speed_down_button_pressed() -> void:
	text_increment(speed_text_edit, -1)

func _on_attack_speed_up_button_pressed() -> void:
	text_increment(attack_speed_text_edit, 1)

func _on_attack_speed_down_button_pressed() -> void:
	text_increment(attack_speed_text_edit, -1)

func _on_detection_range_up_button_pressed() -> void:
	config_file.detection_range = text_increment(detection_range_text_edit, 10)
	_update_detection_ring()

func _on_detection_range_down_button_pressed() -> void:
	config_file.detection_range = text_increment(detection_range_text_edit, -10)
	_update_detection_ring()

func _on_attack_timer_timeout() -> void:
	if sound_option.is_hovered() == false and sound_option.get_popup().visible == false:
		audio_stream_player.play()

func _on_refresh_pressed() -> void:
	clear_grid()
	populate_texture_selection()
	pass # Replace with function body.
