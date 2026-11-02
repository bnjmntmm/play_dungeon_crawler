@tool
class_name LevelRules
extends RefCounted
## Checks that keep a kid's room playable. Works on plain cells, so it needs no scene.

const SAFE_RADIUS: int = 2

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

static func get_safe_cells(floor_cells: Array[Vector2i], door_cells: Array[Vector2i]) -> Array[Vector2i]:
	var safe_cells: Array[Vector2i] = []
	for cell: Vector2i in floor_cells:
		for door_cell: Vector2i in door_cells:
			var distance: Vector2i = (cell - door_cell).abs()
			if maxi(distance.x, distance.y) <= SAFE_RADIUS:
				safe_cells.append(cell)
				break
	return safe_cells

static func get_unreachable_doors(
	floor_cells: Array[Vector2i],
	door_cells: Array[Vector2i],
	obstacle_cells: Array[Vector2i]
) -> Array[Vector2i]:
	if door_cells.is_empty():
		return []

	var open_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in floor_cells:
		open_cells[cell] = true
	for cell: Vector2i in obstacle_cells:
		open_cells.erase(cell)

	var reached: Dictionary[Vector2i, bool] = {door_cells[0]: true}
	var to_visit: Array[Vector2i] = [door_cells[0]]
	while not to_visit.is_empty():
		var cell: Vector2i = to_visit.pop_back()
		for direction: Vector2i in NEIGHBOURS:
			var next_cell: Vector2i = cell + direction
			if open_cells.has(next_cell) and not reached.has(next_cell):
				reached[next_cell] = true
				to_visit.append(next_cell)

	var unreachable: Array[Vector2i] = []
	for door_cell: Vector2i in door_cells:
		if not reached.has(door_cell):
			unreachable.append(door_cell)
	return unreachable
