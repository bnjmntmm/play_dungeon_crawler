class_name NavigationRegion2DRuntimeBuilder
extends NavigationRegion2D
## Rebuilt at runtime from the level's static collision shapes plus a hand-drawn floor outline.

signal navigation_ready
signal _bake_completed

## Polygon2D (invisible) that traces the walkable floor. Assign it in the inspector.
@export var floor_polygon: Polygon2D
## World-space minimum radius; expanded automatically for larger spawned animals.
@export var minimum_agent_radius: float = 40
@export var clearance_margin: float = 2.0

var rebuilding := false
var _rebuild_requested := false
var _bake_finished := false

func rebuild(source_root: Node2D) -> void:
	if floor_polygon == null:
		push_error("NavigationRegion2DRuntimeBuilder: floor_polygon is not assigned.")
		return

	_rebuild_requested = true
	if rebuilding:
		await navigation_ready
		return
	rebuilding = true
	var paused_animals: Array[Node] = []
	while _rebuild_requested:
		_rebuild_requested = false
		enabled = false
		# Scene instances and queued deletions must settle before parsing.
		await get_tree().process_frame
		var tile_layers := source_root.find_children("*", "TileMapLayer", true, false)
		for tile_layer: TileMapLayer in tile_layers:
			tile_layer.update_internals()
		await get_tree().process_frame

		var character_bodies := source_root.find_children("*", "CharacterBody2D", true, false)
		for animal in character_bodies:
			if animal is AnimalScene and animal.is_physics_processing():
				paused_animals.append(animal)
				animal.set_physics_process(false)

		var polygon := NavigationPolygon.new()
		polygon.agent_radius = _get_agent_radius(source_root) + clearance_margin
		polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
		polygon.parsed_collision_mask = 1 # World only; exclude player/animal/trigger shapes.

		var source := NavigationMeshSourceGeometryData2D.new()
		NavigationServer2D.parse_source_geometry_data(polygon, source, source_root)

		# Walkable outline, converted into source_root's local space.
		# Collision shapes parsed above get carved out of this area.
		var to_root := source_root.global_transform.affine_inverse() * floor_polygon.global_transform
		var outline := PackedVector2Array()
		for p in floor_polygon.polygon:
			outline.append(to_root * p)
		source.add_traversable_outline(outline)

		_bake_finished = false
		NavigationServer2D.bake_from_source_geometry_data_async(polygon, source, _on_bake_completed)
		# Small or empty inputs can invoke the callback before the call returns.
		if not _bake_finished:
			await _bake_completed

		var previous_region_iteration := NavigationServer2D.region_get_iteration_id(get_rid())
		navigation_polygon = polygon
		global_transform = source_root.global_transform
		while NavigationServer2D.region_get_iteration_id(get_rid()) == previous_region_iteration:
			await get_tree().physics_frame

		previous_region_iteration = NavigationServer2D.region_get_iteration_id(get_rid())
		enabled = true
		while NavigationServer2D.region_get_iteration_id(get_rid()) == previous_region_iteration:
			await get_tree().physics_frame
		# Flush the map after the region's asynchronous iteration is ready.
		NavigationServer2D.map_force_update(get_navigation_map())

		# Uncomment to debug an empty result:
		# print("nav bake: has_data=", source.has_data(), " polygons=", polygon.get_polygon_count())

	for animal in paused_animals:
		if is_instance_valid(animal):
			animal.set_physics_process(true)
	rebuilding = false
	navigation_ready.emit()

func _on_bake_completed() -> void:
	_bake_finished = true
	_bake_completed.emit()

func _get_agent_radius(source_root: Node) -> float:
	var radius := minimum_agent_radius
	for node in source_root.find_children("*", "CharacterBody2D", true, false):
		if node is AnimalScene:
			var collision := node.get_node("CollisionShape2D") as CollisionShape2D
			if collision.shape is CircleShape2D:
				var world_scale := collision.global_transform.get_scale().abs()
				radius = maxf(radius, collision.shape.radius * maxf(world_scale.x, world_scale.y))
	#return radius
	# Radius is always the same, so it is hand set. This specific value creates nav meshes
	# that work with small rooms.
	return 29
