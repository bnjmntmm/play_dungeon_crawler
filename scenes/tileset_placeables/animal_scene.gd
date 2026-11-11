class_name AnimalScene 
extends BasePlaceable

signal pacified

enum AnimalAiState {inactive = 0, passive = 1, aggressive = 2}

@export var movement_speed: float = 4.0
@export var repath_interval: float = 0.25
@export var repath_min_distance: float = 8.0
@export var _attack_windup : float = 0.6

@export_group("Behaviour")
@export var passive_only: bool = false
@export var is_random: bool = false
@export_range(0.0, 30.0, 0.1) var lose_player_delay: float = 3.0
@export var roaming_enabled: bool = true
## Roaming distances are world-space pixels.
@export_range(1.0, 1000.0, 1.0) var roam_radius: float = 200.0
@export_range(0.0, 30.0, 0.1) var roam_pause_min: float = 1.0
@export_range(0.0, 30.0, 0.1) var roam_pause_max: float = 3.0
@export_range(0.05, 1.0, 0.05) var roam_speed_multiplier: float = 0.5

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var character_body: CharacterBody2D = $"."
@onready var attack_area: Area2D = $AttackArea
@onready var attack_windup_timer: Timer = $AttackWindupTimer
@onready var player_detection_area: Area2D = $PlayerDetectionArea
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var detection_shape: CollisionShape2D = $PlayerDetectionArea/DetectionShape
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var current_ai_behaviour: AnimalAiState = AnimalAiState.inactive
var _pending_ai_state : AnimalAiState
var _has_pending_ai_state : bool = false
var _is_attacking : bool = false

var player: PlayerCharacter
var _player_in_range := false
var _is_winding_up : bool = false

var _last_target_pos := Vector2.INF
var _repath_elapsed := 0.0
var _pacified := false
var _player_detected := false
var _lost_player_elapsed := 0.0
var _roam_pause_remaining := 0.0
var _roam_waiting := false
var _current_anim : String = ""

## From Config
## health / fed amount coming from the config
var max_health: int = 1
var health : int = 1
var attack_speed : int = 1
var damage : int = 1
var sound : AudioStreamWAV
var moveAnimType: Enums.AnimalAnimationType = 0

var _in_load: bool = true

const CHASE_DECAY_TIME := 1.0 
var _player_in_detection_range : bool = false
var _chase_decay_time: float = 0.0

func _ready() -> void:
	super._ready()
	sprite_2d = $SpriteScaler/Sprite2D
	player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player  == null and not GameManager.gallery_mode:
		push_error("AnimalScene could not find a PlayerCharacter in the 'player' group")
	navigation_agent.velocity_computed.connect(Callable(_on_velocity_computed))
	_change_ai_state(AnimalAiState.passive)
	if is_random:
		config = GameManager.all_animal_configs.pick_random()
		init_config()
	GameManager.register_animal(self)
	GameManager.change_level.connect(_enable_load.unbind(1))
	GameManager.loaded_new_room.connect(_disable_load.unbind(1))
	
func _enable_load()-> void:
	_in_load = true
	
func _disable_load()-> void:
	_in_load = false

func init_config() -> void:
	super.init_config()
	var anim_config := config as AnimalConfig
	if anim_config == null:
		push_error("AnimalScene requires an AnimalConfig")
		return
	health = anim_config.health
	max_health = anim_config.health
	damage = anim_config.damage
	#Factor?
	_attack_windup  = anim_config.attack_speed
	movement_speed = anim_config.speed * 10
	var detection_circle := detection_shape.shape as CircleShape2D
	print(detection_circle.radius)
	detection_circle.set_radius(anim_config.detection_range) 
	sound = anim_config.sound
	moveAnimType = anim_config.animation
	
func set_movement_target(movement_target: Vector2):
	navigation_agent.set_target_position(movement_target)

func _on_velocity_computed(safe_velocity: Vector2):
	character_body.velocity = safe_velocity
	character_body.move_and_slide()
	setWalkAnimation(character_body.velocity.length() > 0.1)

func _physics_process(delta):
	if _in_load:
		return
	if passive_only and current_ai_behaviour == AnimalAiState.aggressive:
		_change_ai_state(AnimalAiState.passive)
	_update_chase_decay(delta)
	_update_player_loss(delta)
	if _is_winding_up or _is_attacking:
		_on_velocity_computed(Vector2.ZERO)
		return
	# Do not query when the map has never synchronized and is empty.
	if NavigationServer2D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
		return
	_update_chase_target(delta)
	_update_roaming(delta)
	if navigation_agent.is_navigation_finished():
		_on_velocity_computed(Vector2.ZERO)
		return

	var next_path_position: Vector2 = navigation_agent.get_next_path_position()
	var speed := movement_speed
	if current_ai_behaviour == AnimalAiState.passive:
		speed *= roam_speed_multiplier
	var new_velocity: Vector2 = global_position.direction_to(next_path_position) * speed
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)

func _update_chase_target(delta: float) -> void:
	if current_ai_behaviour != AnimalAiState.aggressive or not _player_detected or not is_instance_valid(player):
		return

	_repath_elapsed += delta
	if _repath_elapsed < repath_interval:
		return
	_repath_elapsed = 0.0

	var min_distance_squared := repath_min_distance * repath_min_distance
	if _last_target_pos == Vector2.INF or player.global_position.distance_squared_to(_last_target_pos) >= min_distance_squared:
		set_movement_target(player.global_position)
		_last_target_pos = player.global_position

func _change_ai_state(new_state: AnimalAiState):
	if passive_only and new_state == AnimalAiState.aggressive:
		new_state = AnimalAiState.passive
	if new_state == current_ai_behaviour and not _is_attacking:
		return
	if _is_attacking:
		_pending_ai_state = new_state
		_has_pending_ai_state = true
		return
	current_ai_behaviour = new_state
	_roam_waiting = false
	if new_state != AnimalAiState.aggressive:
		attack_windup_timer.stop()
		_is_winding_up = false
	if new_state == AnimalAiState.inactive:
		set_movement_target(global_position)
		character_body.velocity = Vector2.ZERO
	
func _get_config_source() -> Dictionary:
	return GameManager.current_level_config.animal_resource_data


#region Everything Attack
func attack_player():
	if _is_attacking or passive_only or current_ai_behaviour != AnimalAiState.aggressive:
		return
	
	_is_attacking = true
	if _player_in_range and is_instance_valid(player):
		if sound:
			audio_stream_player.stream = sound
			audio_stream_player.play()
		#player.get_attacked(damage)
		player.get_attacked(1)
	_on_player_attack_finished()

func _on_player_attack_finished() -> void:
	_is_attacking = false
	if _has_pending_ai_state:
		_has_pending_ai_state = false
		_change_ai_state(_pending_ai_state)
	if _player_in_range and is_instance_valid(player):
		_start_attack_windup()

func _on_attack_windup_timer_timeout() -> void:
	_is_winding_up = false
	if _player_in_range and is_instance_valid(player):
		attack_player()

func _on_attack_area_body_entered(body: Node2D) -> void:
	if _in_load:
		return
	if body == player:
		_player_in_range = true
		_start_attack_windup()

func _start_attack_windup() -> void:
	if passive_only or current_ai_behaviour != AnimalAiState.aggressive or _is_winding_up or _is_attacking or not _player_in_range or not is_instance_valid(player):
		return
	_is_winding_up = true
	attack_windup_timer.start(_attack_windup)

func _on_attack_area_body_exited(body: Node2D) -> void:
	if _in_load:
		return
	if body == player:
		_player_in_range = false
		attack_windup_timer.stop()
		_is_winding_up = false
#endregion

## this function is called when we hit a animal with a baguette
func fed():
	print("current health: ", health)
	if health > 0 and current_ai_behaviour == AnimalAiState.aggressive:
		health -= 1
	if health == 0 and not _pacified:
		_pacified = true
		collision_shape_2d.set_deferred("disabled", true)
		_change_ai_state(AnimalAiState.inactive)
		pacified.emit()
		animation_player.play("RESET")
		animation_player.advance(0)
		animation_player.play("fed")
		animation_player.queue("fed_idle")
		GameManager.add_player_score(100 * max_health)

func is_pacified() -> bool:
	return _pacified

func _on_player_detection_area_body_entered(body: Node2D) -> void:
	if _in_load:
		return
	if body != player:
		return
	_player_detected = true
	_player_in_detection_range = true
	_chase_decay_time = 0.0
	_lost_player_elapsed = 0.0
	if passive_only or _pacified:
		return
	_last_target_pos = Vector2.INF
	_repath_elapsed = repath_interval
	_change_ai_state(AnimalAiState.aggressive)
	if _player_in_range:
		_start_attack_windup()

func set_passive_state(is_passive: bool)->void :
	if (AnimalAiState.inactive or _pacified):
		return
	passive_only = is_passive
	_change_ai_state(AnimalAiState.passive) if is_passive else _change_ai_state(AnimalAiState.aggressive)
	#Prevents bodyblocking at the door
	character_body.set_collision_mask_value(2, false if is_passive else true)
	character_body.set_collision_layer_value(3, false if is_passive else true)
	_on_velocity_computed(Vector2.ZERO)

func _on_player_detection_area_body_exited(body: Node2D) -> void:
	if _in_load:
		return
	if body == player:
		#_player_detected = false
		_lost_player_elapsed = 0.0
		_player_in_detection_range = false
		_chase_decay_time = 0.0
		if current_ai_behaviour == AnimalAiState.aggressive:
			# Continue to the last seen position, without tracking an unseen player.
			set_movement_target(player.global_position)

func _update_player_loss(delta: float) -> void:
	if current_ai_behaviour != AnimalAiState.aggressive:
		return
	if _player_detected and is_instance_valid(player):
		_lost_player_elapsed = 0.0
		return
	_lost_player_elapsed += delta
	if _lost_player_elapsed >= lose_player_delay:
		_change_ai_state(AnimalAiState.passive)

func _update_roaming(delta: float) -> void:
	if current_ai_behaviour != AnimalAiState.passive or not roaming_enabled:
		return
	# Finish the existing walk before selecting a roaming destination.
	if not navigation_agent.is_navigation_finished():
		return
	if not _roam_waiting:
		_roam_waiting = true
		_roam_pause_remaining = randf_range(roam_pause_min, maxf(roam_pause_min, roam_pause_max))
	_roam_pause_remaining -= delta
	if _roam_pause_remaining > 0.0:
		return
	_roam_waiting = false
	var map := navigation_agent.get_navigation_map()
	for attempt in 8:
		var offset := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * roam_radius
		var destination := NavigationServer2D.map_get_closest_point(map, global_position + offset)
		if global_position.distance_to(destination) <= navigation_agent.target_desired_distance + 8.0:
			continue
		var path := NavigationServer2D.map_get_path(map, global_position, destination, true, navigation_agent.navigation_layers)
		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 1.0:
			continue
		set_movement_target(destination)
		return

func setWalkAnimation(is_walking: bool) -> void:
	if moveAnimType == 0:
		return

	if _pacified:
		return
	
	var target := "idle"
	if is_walking:
		match moveAnimType:
			Enums.AnimalAnimationType.woble:
				target = "woble"
			Enums.AnimalAnimationType.jump:
				target = "jump"
			Enums.AnimalAnimationType.squish:
				target = "squish"

	if target == _current_anim:
		return

	if target == "idle":
		animation_player.play("RESET")
		animation_player.advance(0)  # apply RESET immediately

	animation_player.play(target)
	_current_anim = target
		
func _update_chase_decay(delta: float) -> void:
	if not _player_detected or _player_in_detection_range:
		return
	_chase_decay_time += delta
	if _chase_decay_time >= CHASE_DECAY_TIME:
		_player_detected = false
		_chase_decay_time = 0.0
		if current_ai_behaviour == AnimalAiState.aggressive and is_instance_valid(player):
			set_movement_target(player.global_position)
