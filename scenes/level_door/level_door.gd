class_name LevelDoor
extends Area2D

@export var enter_door : LevelDoor

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		print("NextEntry: ", GameManager.nextEntryDoor, "--", enter_door)
		var player: PlayerCharacter = body
		if GameManager.nextEntryDoor == self:
			print("we got back to the prev door")
		else:
			print("we used another room")
			player.set_movement_lock(true)
			GameManager.nextEntryDoor = enter_door
			GameManager.init_room_change()
		
