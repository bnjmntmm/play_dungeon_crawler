class_name PlayerCharacter
extends CharacterBody2D

const BAGUETTE = preload("uid://d3c6bx7pcq5kw")
const SPEED = 300.0
const JUMP_VELOCITY = -400.0

## cake slices are our lives
@export var cake_slices = 3
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

## true as soon as the throw cooldown is over; a throw then happens
## immediately once an enemy is in range
var _can_throw: bool = true
var _in_load: bool = false
var _is_dead: bool = false

## used for instantiating baguette
var current_level_scene = null

@onready var throw_area: Area2D = $ThrowArea
@onready var throw_timer: Timer = $ThrowTimer

@onready var body: Sprite2D = $Body
@onready var player_char_foot_back_1: Sprite2D = $Body/PlayerCharFootBack1
@onready var player_char_foot_front_1: Sprite2D = $Body/PlayerCharFootFront1
@onready var cake: Sprite2D = $Body/Cake

const PLAYER_CHAR_IDLE = preload("uid://d4ek1mcec1syn")
const PLAYER_CHAR_GRAB_CANDY = preload("uid://djkg0usp4l5kv")
const PLAYER_CHAR_THROW_CANDY = preload("uid://d3t3yovvomy8v")
const PLAYER_CHAR_DEAD = preload("uid://b6m0d6l2wuvet")

const CAKE_1HP = preload("uid://qfwu162w12je")
const CAKE_2HP = preload("uid://c13qeobdx6dg1")
const CAKE_3HP = preload("uid://vtar3jptmcey")

@onready var foot_anims: AnimationPlayer = $Body/FootAnims

const STEP_1 := preload("uid://s3wul7r8fa6i")
const STEP_2 := preload("uid://camxn6785ixcw")
const STEP_3 := preload("uid://bprsewct2xo3k")
const STEP_4 := preload("uid://n2fvb5qcaif6")
const STEP_5 := preload("uid://boekrvm7wcxpq")

const STEP_ARRAY := [STEP_1,STEP_2,STEP_3,STEP_4,STEP_5]
@onready var step_sound: AudioStreamPlayer = $StepSound

const THROW_1 := preload("uid://dyvpk14dj42jq")
const THROW_2 := preload("uid://ctetmom48jjeu")
const THROW_3 := preload("uid://dtxqlo4mrqfe6")

const THROW_ARRAY := [THROW_1,THROW_2,THROW_3]
@onready var throw_sound: AudioStreamPlayer = $ThrowSound


const DEADZONE := 0.3

const THROW_POSE_TIME := 0.2
var _throw_pose_left := 0.0

var reparent_cake_node: Node2D

func _enter_tree() -> void:
	add_to_group("player")

func _ready() -> void:
	current_level_scene = get_tree().current_scene
	GameManager.player_reposition.connect(player_room_reset)
	GameManager.entered_end_room.connect(store_slices_to_manager)
	GameManager.change_level.connect(_enable_load.unbind(1))
	GameManager.loaded_new_room.connect(_disable_load.unbind(1))
	_joy_light_color = joy_light_down
	_direction_light_color = joy_light_down
	_refresh_joy_lights()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if (use_slice_count_from_manager):
		cake_slices = GameManager.player_final_cake_slices
	
	# The ThrowTimer is now only the cooldown between two throws.
	# Its wait_time in the inspector is the cooldown.
	throw_timer.one_shot = true
	throw_timer.stop()
	_can_throw = true
	_update_cake_slices()

func _enable_load()-> void:
	_in_load = true
	
func _disable_load()-> void:
	_in_load = false

func _physics_process(delta: float) -> void:
	_throw_pose_left = maxf(_throw_pose_left - delta, 0.0)
	_try_throw()
	_update_body_texture()
	
	var direction := Input.get_vector("movement_left", "movement_right","movement_up","movement_down",DEADZONE)
	_update_joy_light(delta, direction)
	if direction:
		velocity = direction * SPEED
	else:
		velocity = Vector2(move_toward(velocity.x, 0, SPEED), move_toward(velocity.y, 0, SPEED))
	# Vector is still calculated for gallery
	if _movement_lock:
		setWalkAnimation(Vector2.ZERO)
		return
	_turn_player(direction)
	setWalkAnimation(velocity)
	move_and_slide()

func _try_throw() -> void:
	if _in_load:
		return
	nearest_animal = get_nearest_animal()   # refresh every frame, even on cooldown
	if nearest_animal == null or not _can_throw:
		return
	throw_baguette()
	_can_throw = false
	throw_timer.start()

func throw_baguette():
	if nearest_animal:
		_throw_pose_left = THROW_POSE_TIME
		print("throwing baguette at: ", nearest_animal.name)
		_vibrate_joy()
		_play_random_throw_sound()
		## spawn baguette
		var bag = BAGUETTE.instantiate() as Baguette
		current_level_scene.add_child(bag,true)
		bag.global_position = global_position
		bag.direction = global_position.direction_to(nearest_animal.global_position)

func get_attacked(dmg: int)-> bool:
	print("got attacked")
	if _damage_cooldown_active or cake_slices <= 0:
		return false

	# Set the guard before awaiting so simultaneous hits only remove one slice.
	_damage_cooldown_active = true
	cake_slices -= dmg
	print("slices left: ", cake_slices)
	if cake_slices == 0:
		GameManager.on_player_died()
		set_movement_lock(true)
	_update_cake_slices()
	_start_dmg_cooldown()
	return true	

func _start_dmg_cooldown():
	await get_tree().create_timer(damage_cooldown).timeout
	_damage_cooldown_active = false

func get_nearest_animal() -> AnimalScene:
	var nearest: AnimalScene
	var nearest_distance := INF
	
	for animal in throw_area.get_overlapping_bodies():
		if animal is AnimalScene:
			if animal.passive_only:
				continue
			var distance : float = global_position.distance_squared_to(animal.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = animal
	return nearest

func _on_recheck_nearest_animal_timeout() -> void:
	nearest_animal = get_nearest_animal()

func _on_throw_timer_timeout() -> void:
	_can_throw = true

func _position_player(new_pos: Vector2):
	global_position = new_pos

func player_room_reset(new_pos: Vector2):
	_position_player(new_pos)
	set_movement_lock(false)
	GameManager.on_player_repos()
	

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
	if _controller_ids.is_empty():
		return
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

func _turn_player(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var flip_sprite: bool = dir.x > 0
	body.flip_h = flip_sprite
	player_char_foot_back_1.flip_h = flip_sprite
	player_char_foot_front_1.flip_h = flip_sprite

func setWalkAnimation(speed: Vector2) -> void:
	if _is_dead:
		return
	if speed.length() > 0.0 and not _movement_lock:
		foot_anims.play("foot_walk")
		foot_anims.speed_scale = clampf(speed.length() / SPEED, 0.3, 1.0)
	else:
		foot_anims.play("foot_idle")
		foot_anims.speed_scale = 1.0
	
func _update_body_texture() -> void:
	if _is_dead:
		return
	if _throw_pose_left > 0.0:
		body.texture = PLAYER_CHAR_THROW_CANDY
	elif is_instance_valid(nearest_animal) and not _can_throw:
		body.texture = PLAYER_CHAR_GRAB_CANDY
	else:
		body.texture = PLAYER_CHAR_IDLE

func _update_cake_slices() -> void:
	match cake_slices:
		3:
			cake.texture = CAKE_3HP
		2:
			cake.texture = CAKE_2HP
		1:
			cake.texture = CAKE_1HP
		0:
			foot_anims.stop()
			body.texture = PLAYER_CHAR_DEAD
			_is_dead = true
			cake.visible = false
			player_char_foot_back_1.visible = false
			player_char_foot_front_1.visible = false

func reparent_cake() -> void:
	cake.reparent(reparent_cake_node, true)
	$"../EndCutscene".clear_caches()

func _play_random_step_sound():
	step_sound.stream = STEP_ARRAY.pick_random()
	step_sound.pitch_scale = randf_range(0.95,1.05)
	step_sound.play()
	
func _play_random_throw_sound():
	throw_sound.stream = THROW_ARRAY.pick_random()
	throw_sound.pitch_scale = randf_range(0.95,1.05)
	throw_sound.play()
