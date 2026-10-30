class_name PlayerCharacter
extends CharacterBody2D

signal died

const BAGUETTE = preload("uid://d3c6bx7pcq5kw")

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

var nearest_animal : AnimalScene
@onready var throw_area: Area2D = $ThrowArea
var _movement_lock: bool = false

## used for instantiating baguette
var current_level_scene = null


func _ready() -> void:
	current_level_scene = get_tree().current_scene
	GameManager.player_reposition.connect(player_room_reset)

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("movement_left", "movement_right","movement_up","movement_down")
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
		
		## spawn baguette
		var bag = BAGUETTE.instantiate() as Baguette
		current_level_scene.add_child(bag,true)
		bag.global_position = global_position
		bag.direction = global_position.direction_to(nearest_animal.global_position)

func get_nearest_animal() -> AnimalScene:
	var nearest: AnimalScene
	var nearest_distance := INF
	
	for animal in throw_area.get_overlapping_bodies():
		if animal is AnimalScene:
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
