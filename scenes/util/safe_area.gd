extends Area2D

func _on_body_entered(body: Node2D) -> void:
	var player := body as PlayerCharacter
	if player:
		player.safe_zone_count += 1
		if (player.safe_zone_count >= 1):
			GameManager.set_all_enemy_passive(true)
#
func _on_body_exited(body: Node2D) -> void:
	var player := body as PlayerCharacter
	if player:
		player.safe_zone_count -= 1
		if (player.safe_zone_count <= 0):
			GameManager.set_all_enemy_passive(false)
