@tool
class_name LevelEditor
extends Control
## Room editor for the Game Design station: pick something on the left, click it into the room.

const LEVEL_SCENE_PATH: String = "res://scenes/level_gen/dynamic_level.tscn"
const CUSTOM_DATA_PATH: String = "res://custom_data"
const LEVEL_PATH_TEMPLATE: String = "res://custom_data/%s/level/level_%s.tres"
const PREVIEW_SCENE_PATH: String = "res://feature/level_editor/level_preview.tscn"
const CONFIG_EXTENSIONS: PackedStringArray = ["tres", "res"]

const SAFE_COLOR: Color = Color(0.35, 0.85, 0.45, 0.3)
const HOVER_COLOR: Color = Color(1, 1, 1, 0.35)

@onready var palette_grid: GridContainer = %PaletteGrid
@onready var eraser_button: Button = %EraserButton
@onready var room_view: Control = %RoomView
@onready var room_root: Node2D = %RoomRoot
@onready var kid_id_edit: LineEdit = %KidIdEdit
@onready var status_label: Label = %StatusLabel

var draft: LevelDraft = LevelDraft.new()
var selected_config: BaseConfig
var scene_tile_set: TileSet
var floor_cells: Array[Vector2i] = []
var door_cells: Array[Vector2i] = []
var safe_cells: Array[Vector2i] = []
var room_rect: Rect2 = Rect2()
var tile_size: Vector2 = Vector2.ZERO
var previews: Dictionary[Vector2i, Sprite2D] = {}
var hover_rect: ColorRect
var palette_group: ButtonGroup = ButtonGroup.new()
var loaded_path: String = ""
var loaded_uuid: String = ""
var preview_pid: int = -1

## Inside the Godot editor LevelEditorTool calls initialize(), so opening this scene stays harmless.
func _ready() -> void:
	if not Engine.is_editor_hint():
		initialize()

func _exit_tree() -> void:
	_stop_preview()

func initialize() -> void:
	_load_room()
	_build_safe_overlay()
	build_palette()
	eraser_button.button_group = palette_group
	eraser_button.pressed.connect(_select_config.bind(null))
	room_view.gui_input.connect(_on_room_view_gui_input)
	room_view.mouse_exited.connect(_hide_hover)
	room_view.resized.connect(_fit_room)
	_fit_room()
	_suggest_code()
	_set_status("Wähle links etwas aus und klicke es in den Raum.")

## Reads walls, doors and safe areas from the real level scene, so the editor always matches the game.
func _load_room() -> void:
	var level_scene: Node = (load(LEVEL_SCENE_PATH) as PackedScene).instantiate()
	room_root.add_child(level_scene.get_node("TileLayers/MainLevelLayer").duplicate())
	var objects_layer: TileMapLayer = level_scene.get_node("TileLayers/LevelObjectsTileLayer") as TileMapLayer
	scene_tile_set = objects_layer.tile_set
	tile_size = Vector2(scene_tile_set.tile_size) * objects_layer.scale

	var wall_rects: Array[Rect2] = _get_shape_rects(level_scene, "TileLayers/RoomCollisions")
	room_rect = wall_rects[0]
	for wall_rect: Rect2 in wall_rects:
		room_rect = room_rect.merge(wall_rect)
	var inner_rect: Rect2 = _get_inner_rect(wall_rects, room_rect.get_center())
	var first_cell: Vector2i = Vector2i((inner_rect.position / tile_size).floor())
	var last_cell: Vector2i = Vector2i((inner_rect.end / tile_size).ceil())
	for x: int in range(first_cell.x, last_cell.x):
		for y: int in range(first_cell.y, last_cell.y):
			if inner_rect.has_point(_get_cell_center(Vector2i(x, y))):
				floor_cells.append(Vector2i(x, y))

	for door: Node2D in level_scene.get_node("LevelExits").get_children():
		door_cells.append(_get_nearest_floor_cell(door.position + door.get("player_spawn_offset")))
	var safe_rects: Array[Rect2] = _get_shape_rects(level_scene, "SafeAreas")
	for cell: Vector2i in floor_cells:
		var center: Vector2 = _get_cell_center(cell)
		if safe_rects.any(func(safe_rect: Rect2) -> bool: return safe_rect.has_point(center)):
			safe_cells.append(cell)
	level_scene.free()

func _get_shape_rects(level_scene: Node, parent_path: String) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for shape_node: Node in level_scene.get_node(parent_path).find_children("*", "CollisionShape2D", true, false):
		var shape_transform: Transform2D = Transform2D.IDENTITY
		var node: Node = shape_node
		while node != level_scene:
			shape_transform = (node as Node2D).transform * shape_transform
			node = node.get_parent()
		var shape_size: Vector2 = ((shape_node as CollisionShape2D).shape as RectangleShape2D).size
		rects.append(shape_transform * Rect2(-shape_size / 2.0, shape_size))
	return rects

## The walls leave gaps for the doors, so the floor is the space between the innermost wall edges.
func _get_inner_rect(wall_rects: Array[Rect2], room_center: Vector2) -> Rect2:
	var inner_start: Vector2 = -Vector2.INF
	var inner_end: Vector2 = Vector2.INF
	for wall_rect: Rect2 in wall_rects:
		var wall_center: Vector2 = wall_rect.get_center()
		if wall_rect.size.y > wall_rect.size.x:
			if wall_center.x < room_center.x:
				inner_start.x = maxf(inner_start.x, wall_rect.end.x)
			else:
				inner_end.x = minf(inner_end.x, wall_rect.position.x)
		elif wall_center.y < room_center.y:
			inner_start.y = maxf(inner_start.y, wall_rect.end.y)
		else:
			inner_end.y = minf(inner_end.y, wall_rect.position.y)
	return Rect2(inner_start, inner_end - inner_start)

func _get_cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size

func _get_nearest_floor_cell(point: Vector2) -> Vector2i:
	var nearest: Vector2i = floor_cells[0]
	for cell: Vector2i in floor_cells:
		if _get_cell_center(cell).distance_to(point) < _get_cell_center(nearest).distance_to(point):
			nearest = cell
	return nearest

func _build_safe_overlay() -> void:
	for cell: Vector2i in safe_cells:
		room_root.add_child(_create_cell_rect(cell, SAFE_COLOR))
	hover_rect = _create_cell_rect(Vector2i.ZERO, HOVER_COLOR)
	hover_rect.z_index = 1
	hover_rect.hide()
	room_root.add_child(hover_rect)

func _create_cell_rect(cell: Vector2i, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.size = tile_size
	rect.position = Vector2(cell) * tile_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func build_palette() -> void:
	for button: Node in palette_grid.get_children():
		button.free()
	for config: BaseConfig in _collect_configs(CUSTOM_DATA_PATH):
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = palette_group
		button.icon = config.sprite
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = Vector2(96, 112)
		button.text = "Tier" if config is AnimalConfig else "Hindernis"
		button.tooltip_text = config.resource_path.get_file()
		button.pressed.connect(_select_config.bind(config))
		palette_grid.add_child(button)

func _collect_configs(dir_path: String) -> Array[BaseConfig]:
	var configs: Array[BaseConfig] = []
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		if sub_dir != "level":
			configs.append_array(_collect_configs(dir_path.path_join(sub_dir)))
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() in CONFIG_EXTENSIONS:
			var config: BaseConfig = load(dir_path.path_join(file)) as BaseConfig
			if config:
				configs.append(config)
	return configs

func _select_config(config: BaseConfig) -> void:
	selected_config = config

func _fit_room() -> void:
	if room_rect.size == Vector2.ZERO:
		return
	var room_scale: float = minf(room_view.size.x / room_rect.size.x, room_view.size.y / room_rect.size.y)
	room_root.scale = Vector2(room_scale, room_scale)
	room_root.position = (room_view.size - room_rect.size * room_scale) / 2.0 - room_rect.position * room_scale

func _on_room_view_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouse:
		return
	var mouse_event: InputEventMouse = event as InputEventMouse
	var cell: Vector2i = Vector2i(((mouse_event.position - room_root.position) / room_root.scale / tile_size).floor())
	_show_hover(cell)
	if mouse_event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_erase_cell(cell)
	elif mouse_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if selected_config:
			_place_cell(cell)
		else:
			_erase_cell(cell)

func _place_cell(cell: Vector2i) -> void:
	if cell not in floor_cells:
		return
	if cell in safe_cells:
		_set_status("Vor den Türen muss Platz bleiben.")
		return
	if draft.get_config(cell) == selected_config:
		return
	draft.place(cell, selected_config)
	_update_preview(cell)

func _erase_cell(cell: Vector2i) -> void:
	draft.erase(cell)
	_update_preview(cell)

func _update_preview(cell: Vector2i) -> void:
	if previews.has(cell):
		previews[cell].queue_free()
		previews.erase(cell)
	var config: BaseConfig = draft.get_config(cell)
	if config == null or config.sprite == null:
		return
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = config.sprite
	sprite.position = _get_cell_center(cell)
	sprite.scale = Vector2.ONE * tile_size.x / maxf(config.sprite.get_width(), config.sprite.get_height())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room_root.add_child(sprite)
	previews[cell] = sprite

func _show_hover(cell: Vector2i) -> void:
	hover_rect.visible = cell in floor_cells
	hover_rect.position = Vector2(cell) * tile_size

func _hide_hover() -> void:
	hover_rect.hide()

func _clear_room() -> void:
	for cell: Vector2i in draft.get_placed_cells():
		_erase_cell(cell)

func _on_clear_button_pressed() -> void:
	_clear_room()
	_set_status("Der Raum ist wieder leer.")

func _suggest_code() -> void:
	kid_id_edit.text = LevelCode.create_unused(CUSTOM_DATA_PATH)

func _on_new_code_button_pressed() -> void:
	_suggest_code()
	_set_status("Dein neuer Code ist: %s" % kid_id_edit.text)

func _on_load_button_pressed() -> void:
	var kid_id: String = _read_kid_id()
	if kid_id.is_empty():
		_set_status("Gib zuerst deinen Code ein.")
		return
	var path: String = LEVEL_PATH_TEMPLATE % [kid_id, kid_id]
	if not ResourceLoader.exists(path):
		_set_status("Zu diesem Code gibt es noch kein Level.")
		return
	var level: LevelConfig = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelConfig
	if level == null:
		_set_status("Dieses Level konnte nicht geladen werden.")
		return
	_clear_room()
	draft.load_from(level)
	for cell: Vector2i in draft.get_placed_cells():
		_update_preview(cell)
	loaded_path = path
	loaded_uuid = level.uuid
	_set_status("Dein Level ist geladen.")

func _on_try_button_pressed() -> void:
	var problem: String = _find_room_problem()
	if not problem.is_empty():
		_set_status(problem)
		return
	if not _write_preview_level():
		_set_status("Ausprobieren hat nicht geklappt. Sag dem Dev-Team Bescheid.")
		return
	_start_preview()

func _write_preview_level() -> bool:
	var level: LevelConfig = LevelConfig.new()
	level.uuid = "level_editor_preview"
	level.display_name = _read_kid_id()
	draft.apply_to(level, scene_tile_set)
	return ResourceSaver.save(level, LevelPreview.LEVEL_PATH) == OK

## The game runs as its own process, so the draft stays open here while a kid plays.
func _start_preview() -> void:
	_stop_preview()
	var arguments: PackedStringArray = ["--path", ProjectSettings.globalize_path("res://"), PREVIEW_SCENE_PATH]
	preview_pid = OS.create_process(OS.get_executable_path(), arguments)
	if preview_pid == -1:
		_set_status("Ausprobieren hat nicht geklappt. Sag dem Dev-Team Bescheid.")
	else:
		_set_status("Viel Spaß! Mit Esc kommst du zurück zum Editor.")

func _stop_preview() -> void:
	if preview_pid != -1 and OS.is_process_running(preview_pid):
		OS.kill(preview_pid)
	preview_pid = -1

func _on_save_button_pressed() -> void:
	_save_level()

func _save_level() -> bool:
	var problem: String = _find_save_problem()
	if not problem.is_empty():
		_set_status(problem)
		return false

	var kid_id: String = _read_kid_id()
	var path: String = LEVEL_PATH_TEMPLATE % [kid_id, kid_id]
	var level: LevelConfig = LevelConfig.new()
	level.uuid = loaded_uuid if path == loaded_path else str(ResourceUID.create_id())
	level.display_name = kid_id
	draft.apply_to(level, scene_tile_set)

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(level, path) != OK:
		_set_status("Speichern hat nicht geklappt. Sag dem Dev-Team Bescheid.")
		return false
	loaded_path = path
	loaded_uuid = level.uuid
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_set_status("Gespeichert! Dein Code ist: %s" % kid_id)
	return true

func _find_save_problem() -> String:
	var kid_id: String = _read_kid_id()
	if kid_id.is_empty():
		return "Gib zuerst deinen Code ein."
	var problem: String = _find_room_problem()
	if not problem.is_empty():
		return problem
	var path: String = LEVEL_PATH_TEMPLATE % [kid_id, kid_id]
	if path != loaded_path and FileAccess.file_exists(path):
		return "Diesen Code gibt es schon. Lade dein Level oder nimm einen anderen."
	return ""

func _find_room_problem() -> String:
	if draft.is_empty():
		return "Dein Raum ist noch leer."
	for cell: Vector2i in draft.get_placed_cells():
		if cell in safe_cells:
			return "Vor den Türen muss Platz bleiben."
	if not LevelRules.get_unreachable_doors(floor_cells, door_cells, draft.get_obstacle_cells()).is_empty():
		return "Eine Tür ist zugebaut. Der Spieler muss zu allen Türen kommen."
	return ""

func _read_kid_id() -> String:
	return LevelCode.clean(kid_id_edit.text)

func _set_status(message: String) -> void:
	status_label.text = message
