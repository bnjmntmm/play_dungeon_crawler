class_name Baguette
extends Area2D

@export var speed : float = 150.0
@export var spin_speed: float = 400
@export var possible_foods: Array[Sprite2D]

@onready var food_1: Sprite2D = $Food1
@onready var food_2: Sprite2D = $Food2
@onready var food_3: Sprite2D = $Food3
@onready var food_4: Sprite2D = $Food4

var direction : Vector2 = Vector2.ZERO

func _ready() -> void:
	#Clear on screen change
	possible_foods.append(food_1)
	possible_foods.append(food_2)
	possible_foods.append(food_3)
	possible_foods.append(food_4)
	GameManager.change_level.connect(queue_free.unbind(1))
	possible_foods.pick_random().visible = true
	

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	rotation_degrees -= spin_speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body is AnimalScene:
		body.fed()
	self.queue_free()
