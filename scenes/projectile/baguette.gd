class_name Baguette
extends Area2D

@export var speed : float = 500.0

var direction : Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body is AnimalScene:
		body.fed()
	queue_free()
