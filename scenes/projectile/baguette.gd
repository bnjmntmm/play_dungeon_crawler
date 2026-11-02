class_name Baguette
extends Area2D

@export var speed : float = 150.0
@export var spin_speed: float = 400

var direction : Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	rotation_degrees -= spin_speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body is AnimalScene:
		body.fed()
	self.queue_free()
