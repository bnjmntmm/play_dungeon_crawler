class_name PlayerCharacter
extends CharacterBody2D

const BAGUETTE = preload("uid://d3c6bx7pcq5kw")
const SPEED = 300.0
const JUMP_VELOCITY = -400.0

## cake slices are our lives
@export var cake_slices = 4
@export var damage_cooldown: float = 1.0
@export var use_slice_count_from_manager: bool = false

@export_group("Controller Light")
@export var debug_joy_light: bool = false
@export var joy_light_up: Color = Color(0.2, 0.6, 1.0)
@export var joy_light_right: Color = Color(1.0, 0.3, 0.2)
@export var joy_light_down: Color = Color(1.0, 0.75, 0.15)
@export var joy_light_left: Color = Color(0.25, 1.0, 0.45)
@export_range(0.1, 20.0, 0.1) var joy_light_blend_speed: float = 4.0

var _controller_ids: Array[int] = []
var _joy_light_color: Color
var _direction_light_color: Color

var nearest_animal : AnimalScene
var _movement_lock: bool = false
var _damage_cooldown_active: bool = false
var safe_zone_count : int = 0

## used for instantiating baguette
var current_level_scene = null

@onready var throw_area: Area2D = $ThrowArea

func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	current_level_scene = get_tree().current_scene
	GameManager.player_reposition.connect(player_room_reset)
	GameManager.entered_end_room.connect(store_slices_to_manager)
	_joy_light_color = joy_light_down
	_direction_light_color = joy_light_down
	_refresh_joy_lights()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if (use_slice_count_from_manager):
		cake_slices = GameManager.player_final_cake_slices

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("movement_left", "movement_right","movement_up","movement_down")
	_update_joy_light(delta, direction)
	if direction:
		velocity = direction * SPEED
	else:
		velocity = Vector2(move_toward(velocity.x, 0, SPEED), move_toward(velocity.y, 0, SPEED))
	# Vector is still calculated for gallery
	if _movement_lock:
		return
	move_and_slide()

func throw_baguette():
	if nearest_animal:
		print("throwing baguette at: ", nearest_animal.name)
		_vibrate_joy()
		
		## spawn baguette
		var bag = BAGUETTE.instantiate() as Baguette
		current_level_scene.add_child(bag,true)
		bag.global_position = global_position
		bag.direction = global_position.direction_to(nearest_animal.global_position)

func get_attacked(dmg: int):
	print("got attacked")
	if _damage_cooldown_active or cake_slices <= 0:
		return

	# Set the guard before awaiting so simultaneous hits only remove one slice.
	_damage_cooldown_active = true
	cake_slices -= dmg
	print("slices left: ", cake_slices)
	if cake_slices == 0:
		GameManager.on_player_died()
		set_movement_lock(true)

	await get_tree().create_timer(damage_cooldown).timeout
	_damage_cooldown_active = false

func get_nearest_animal() -> AnimalScene:
	var nearest: AnimalScene
	var nearest_distance := INF
	
	for animal in throw_area.get_overlapping_bodies():
		if animal is AnimalScene:
			if animal.current_ai_behaviour != animal.AnimalAiState.aggressive:
				continue
			var distance : float = global_position.distance_squared_to(animal.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = animal
	return nearest

func _on_recheck_nearest_animal_timeout() -> void:
	nearest_animal = get_nearest_animal()

func _on_throw_timer_timeout() -> void:
	throw_baguette()

func _position_player(new_pos: Vector2):
	global_position = new_pos

func player_room_reset(new_pos: Vector2):
	_position_player(new_pos)
	set_movement_lock(false)
	

func set_movement_lock(is_locked: bool):
	_movement_lock = is_locked


func _refresh_joy_lights() -> void:
	_controller_ids.clear()
	for controller_id in Input.get_connected_joypads():
		if Input.has_joy_light(controller_id):
			_controller_ids.append(controller_id)
			if debug_joy_light:
				Input.set_joy_light(controller_id, _joy_light_color)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_joy_lights()


func _get_direction_light_color(direction: Vector2) -> Color:
	var horizontal := joy_light_right if direction.x >= 0.0 else joy_light_left
	var vertical := joy_light_down if direction.y >= 0.0 else joy_light_up
	# Diagonal movement blends the two neighboring direction colors.
	var total := absf(direction.x) + absf(direction.y)
	if is_zero_approx(total):
		return _direction_light_color
	return horizontal.lerp(vertical, absf(direction.y) / total)

func _vibrate_joy():
	if not Input.has_joy_vibration(_controller_ids[0]):
		return
	if Input.is_joy_vibrating(_controller_ids[0]):
		Input.stop_joy_vibration(_controller_ids[0])
	Input.start_joy_vibration(_controller_ids[0],0,.2,.1)
	
func store_slices_to_manager()-> void:
	GameManager.player_final_cake_slices = cake_slices;
	pass

func _update_joy_light(delta: float, movement: Vector2) -> void:
	if not debug_joy_light:
		return
	if not movement.is_zero_approx():
		_direction_light_color = _get_direction_light_color(movement)
	var target := _direction_light_color
	# Exponential smoothing keeps the transition speed independent of frame rate.
	_joy_light_color = _joy_light_color.lerp(target, 1.0 - exp(-joy_light_blend_speed * delta))
	for controller_id in _controller_ids:
		Input.set_joy_light(controller_id, _joy_light_color)
