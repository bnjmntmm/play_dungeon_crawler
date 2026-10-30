class_name AnimalScene 
extends BasePlaceable

enum animal_ai_state {inactive = 0, passive = 1, aggressive = 2}

@export var movement_speed: float = 4.0
@export var repath_interval: float = 0.25
@export var repath_min_distance: float = 8.0

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var character_body: CharacterBody2D = $"."

var current_ai_behavior: animal_ai_state = animal_ai_state.inactive
var _last_target_pos := Vector2.INF
var _repath_timer: Timer

func _ready() -> void:
	navigation_agent.velocity_computed.connect(Callable(_on_velocity_computed))
	
func set_movement_target(movement_target: Vector2):
	navigation_agent.set_target_position(movement_target)

func _on_velocity_computed(safe_velocity: Vector2):
	character_body.velocity = safe_velocity
	character_body.move_and_slide()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _physics_process(delta):
	# Do not query when the map has never synchronized and is empty.
	if NavigationServer2D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
		return
	if navigation_agent.is_navigation_finished():
		return

	var next_path_position: Vector2 = navigation_agent.get_next_path_position()
	var new_velocity: Vector2 = global_position.direction_to(next_path_position) * movement_speed
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)

func _change_ai_state():
	pass

func _get_config_source() -> Dictionary:
	return GameManager.current_level_config.animal_resource_data

func fed():
	pass
