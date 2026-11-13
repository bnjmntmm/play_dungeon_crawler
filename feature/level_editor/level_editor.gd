@tool
class_name LevelEditor
extends Control
## Room editor for the Game Design station: pick something on the left, click it into the room.

const LEVEL_SCENE_PATH: String = "res://scenes/level_gen/dynamic_level.tscn"
const CUSTOM_DATA_PATH: String = "res://custom_data"
const PREVIEW_SCENE_PATH: String = "res://feature/level_editor/level_preview.tscn"
signal saved(code: String)

const CONFIG_EXTENSIONS: PackedStringArray = ["tres", "res"]

## Folder name that holds obstacle PNGs, e.g. custom_data/<name>/obstacle/rock.png
const OBSTACLE_FOLDER: String = "obstacle"

## Red, because the bright green zones looked like the place to put things.
const SAFE_COLOR: Color = Color(0.95, 0.2, 0.15, 0.35)
const HOVER_COLOR: Color = Color(1, 1, 1, 0.35)
const HOVER_BLOCKED_COLOR: Color = Color(1, 0.2, 0.15, 0.6)
const ANIMAL_COLOR: Color = Color(0.55, 0.32, 0.12)
const OBSTACLE_COLOR: Color = Color(0.16, 0.3, 0.5)
const MESSAGE_SECONDS: float = 1.6
const MAX_LISTED_MATCHES: int = 4

@onready var animal_grid: GridContainer = %AnimalGrid
@onready var obstacle_grid: GridContainer = %ObstacleGrid
@onready var identity_box: Control = %IdentityBox
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
## The level that was loaded (or saved) in this session. Only this one may be overwritten.
var loaded_path: String = ""
var loaded_uuid: String = ""
var loaded_name_key: String = ""
var preview_pid: int = -1
var last_message: String = ""
var last_message_time: int = 0
var notify_layer: Control
var _name_cleaner: RegEx
var _reported_invalid: Dictionary[String, bool] = {}

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

# ---------------------------------------------------------------------------
# Palette and obstacle scanning
# ---------------------------------------------------------------------------

func build_palette() -> void:
	scan_new_obstacles()
	for grid: GridContainer in [animal_grid, obstacle_grid]:
		for button: Node in grid.get_children():
			button.free()
	for config: BaseConfig in _collect_configs(CUSTOM_DATA_PATH):
		var is_animal: bool = config is AnimalConfig
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = palette_group
		button.icon = config.sprite
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = Vector2(120, 120)
		button.text = _get_config_name(config)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = button.text
		_style_palette_button(button, ANIMAL_COLOR if is_animal else OBSTACLE_COLOR)
		button.set_meta("config_path", config.resource_path)
		button.pressed.connect(_select_config.bind(config))
		(animal_grid if is_animal else obstacle_grid).add_child(button)
		if selected_config and selected_config.resource_path == config.resource_path:
			button.button_pressed = true
			selected_config = config

func _get_config_name(config: BaseConfig) -> String:
	if config is AnimalConfig and not (config as AnimalConfig).display_name.is_empty():
		return (config as AnimalConfig).display_name
	return "Tier" if config is AnimalConfig else "Hindernis"

func _style_palette_button(button: Button, color: Color) -> void:
	var styles: Dictionary[String, Color] = {
		"normal": color,
		"hover": color.lightened(0.15),
		"pressed": color.lightened(0.3),
		"hover_pressed": color.lightened(0.3),
	}
	for style_name: String in styles:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = styles[style_name]
		style.set_corner_radius_all(8)
		style.set_content_margin_all(6)
		if style_name.ends_with("pressed"):
			style.border_color = Color.WHITE
			style.set_border_width_all(4)
		button.add_theme_stylebox_override(style_name, style)

## Selects a palette entry by file, e.g. the animal a kid just saved in the other tab.
func select_config_path(path: String) -> void:
	for grid: GridContainer in [animal_grid, obstacle_grid]:
		for button: Button in grid.get_children():
			if button.get_meta("config_path") == path:
				button.button_pressed = true
				button.pressed.emit()

## Creates a BaseConfig for every valid PNG in an obstacle folder that has none yet.
## Returns how many were created, so a refresh button can report it later.
func scan_new_obstacles() -> int:
	var created: int = _scan_dir_for_obstacles(CUSTOM_DATA_PATH)
	if created > 0 and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return created

func _scan_dir_for_obstacles(dir_path: String) -> int:
	var created: int = 0
	if dir_path.get_file() == OBSTACLE_FOLDER:
		created += _create_missing_obstacles(dir_path)
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		if sub_dir != "level" and sub_dir != "animal":
			created += _scan_dir_for_obstacles(dir_path.path_join(sub_dir))
	return created

func _create_missing_obstacles(dir_path: String) -> int:
	# What already has a config here: by source_png, or by a .tres with the same file name as the PNG.
	var known_pngs: Dictionary[String, bool] = {}
	var known_names: Dictionary[String, bool] = {}
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() not in CONFIG_EXTENSIONS:
			continue
		known_names[file.get_basename()] = true
		var config: BaseConfig = ResourceLoader.load(dir_path.path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as BaseConfig
		if config and not config.source_png.is_empty():
			known_pngs[config.source_png] = true

	var created: int = 0
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension().to_lower() != "png":
			continue
		var png_path: String = dir_path.path_join(file)
		if known_pngs.has(png_path) or known_names.has(file.get_basename()):
			continue
		var config: BaseConfig = BaseConfig.new()
		config.uuid = str(ResourceUID.create_id())  # unused, just needs a value
		config.source_png = png_path
		if not config.refresh_sprite():
			if not _reported_invalid.has(png_path):
				_reported_invalid[png_path] = true
				push_warning("Obstacle image could not be loaded: %s" % png_path)
			continue
		var config_path: String = dir_path.path_join(file.get_basename() + ".tres")
		if ResourceSaver.save(config, config_path) != OK:
			push_warning("Could not save obstacle config: %s" % config_path)
			continue
		created += 1
	return created

func _collect_configs(dir_path: String) -> Array[BaseConfig]:
	var configs: Array[BaseConfig] = []
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		if sub_dir != "level":
			configs.append_array(_collect_configs(dir_path.path_join(sub_dir)))
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() in CONFIG_EXTENSIONS:
			## REPLACE keeps placed configs valid while picking up changes from the animal tab.
			var config: BaseConfig = ResourceLoader.load(dir_path.path_join(file), "", ResourceLoader.CACHE_MODE_REPLACE) as BaseConfig
			if config:
				configs.append(config)
	return configs

func _select_config(config: BaseConfig) -> void:
	selected_config = config

# ---------------------------------------------------------------------------
# Room view and editing
# ---------------------------------------------------------------------------

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
		_notify("Hier nicht! Vor den Türen muss Platz bleiben.")
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
	hover_rect.color = HOVER_BLOCKED_COLOR if cell in safe_cells and selected_config else HOVER_COLOR
	hover_rect.position = Vector2(cell) * tile_size

func _hide_hover() -> void:
	hover_rect.hide()

func _clear_room() -> void:
	for cell: Vector2i in draft.get_placed_cells():
		_erase_cell(cell)

func _on_clear_button_pressed() -> void:
	_clear_room()
	_forget_loaded_level()
	kid_id_edit.text = ""
	_set_status("Der Raum ist wieder leer. Gib deinem neuen Level einen Namen.")

## After this, no level counts as loaded, so saving under an existing name is blocked again.
func _forget_loaded_level() -> void:
	loaded_path = ""
	loaded_uuid = ""
	loaded_name_key = ""

## The station picks the kid folder in its header, so the name row here is only for the standalone tool.
func set_identity_visible(is_visible: bool) -> void:
	identity_box.visible = is_visible

# ---------------------------------------------------------------------------
# Level names: lookup, search and uniqueness
# ---------------------------------------------------------------------------

## Lowercase and only letters/digits, so "My_Cool Level!" and "mycoollevel" count as the same name.
func _normalize(text: String) -> String:
	if _name_cleaner == null:
		_name_cleaner = RegEx.create_from_string("[^\\p{L}\\p{N}]")
	return _name_cleaner.sub(text.to_lower(), "", true)

func _read_level_name() -> String:
	return kid_id_edit.text.strip_edges()

## Shown name: underscores become spaces, repeated spaces collapse.
func _get_display_name() -> String:
	var display_name: String = _read_level_name().replace("_", " ")
	while display_name.contains("  "):
		display_name = display_name.replace("  ", " ")
	return display_name.strip_edges()

## Folder name for a new level: the typed name, safe for the file system, spaces as underscores.
func _to_folder_name(text: String) -> String:
	var folder: String = text.strip_edges().validate_filename().replace(" ", "_")
	while folder.contains("__"):
		folder = folder.replace("__", "_")
	return folder

## One dictionary per saved level: {folder, path, config, level_name}.
func _make_level_entry(folder: String) -> Dictionary:
	var path: String = KidFolders.get_level_path(folder)
	if not ResourceLoader.exists(path):
		return {}
	var config: LevelConfig = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelConfig
	if config == null:
		return {}
	var level_name: String = config.display_name if not config.display_name.is_empty() else folder
	return {"folder": folder, "path": path, "config": config, "level_name": level_name}

## GameManager is an autoload and not available inside the Godot editor, so levels are read from disk.
func _collect_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for folder: String in DirAccess.get_directories_at(CUSTOM_DATA_PATH):
		var entry: Dictionary = _make_level_entry(folder)
		if not entry.is_empty():
			levels.append(entry)
	return levels

## Both the shown name and the folder name count, so old levels are found and protected too.
func _get_name_keys(level: Dictionary) -> Array[String]:
	return [_normalize(level.level_name), _normalize(level.folder)]

## Exact (normalized) matches win over partial ones.
func _search(query: String) -> Array[Dictionary]:
	var exact: Array[Dictionary] = []
	var partial: Array[Dictionary] = []
	var query_key: String = _normalize(query)
	if query_key.is_empty():
		return exact
	for level: Dictionary in _collect_levels():
		var keys: Array[String] = _get_name_keys(level)
		if query_key in keys:
			exact.append(level)
			continue
		for key: String in keys:
			if key.contains(query_key):
				partial.append(level)
				break
	return exact if not exact.is_empty() else partial

func _find_level_by_name(level_name: String) -> Dictionary:
	var key: String = _normalize(level_name)
	for level: Dictionary in _collect_levels():
		if key in _get_name_keys(level):
			return level
	return {}

## A level may only be overwritten when it was loaded (or created) here and the name still is the same.
func _is_overwriting_loaded() -> bool:
	return not loaded_path.is_empty() and _normalize(_read_level_name()) == loaded_name_key

func _get_save_path() -> String:
	if _is_overwriting_loaded():
		return loaded_path
	return KidFolders.get_level_path(_to_folder_name(_read_level_name()))

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## Opens the room saved in this kid folder, or an empty room for a new kid.
func use_kid(code: String) -> void:
	_clear_room()
	_forget_loaded_level()
	var entry: Dictionary = _make_level_entry(code)
	if entry.is_empty():
		kid_id_edit.text = code
		_set_status("Wähle links etwas aus und klicke es in den Raum.")
	else:
		_load_level(entry)

func _load_level(level: Dictionary) -> void:
	_clear_room()
	draft.load_from(level.config)
	for cell: Vector2i in draft.get_placed_cells():
		_update_preview(cell)
	loaded_path = level.path
	loaded_uuid = (level.config as LevelConfig).uuid
	loaded_name_key = _normalize(level.level_name)
	kid_id_edit.text = level.level_name
	_set_status("Dein Level \"%s\" ist geladen." % level.level_name)

func _suggest_code() -> void:
	kid_id_edit.text = LevelCode.create_unused(CUSTOM_DATA_PATH)

func _on_new_code_button_pressed() -> void:
	_suggest_code()
	_set_status("Dein neuer Name ist: %s" % kid_id_edit.text)

func _on_load_button_pressed() -> void:
	var query: String = _read_level_name()
	if _normalize(query).is_empty():
		_set_status("Gib zuerst den Namen deines Levels ein.")
		return
	var matches: Array[Dictionary] = _search(query)
	if matches.is_empty():
		_set_status("Kein Level mit dem Namen \"%s\" gefunden. Prüfe die Schreibweise, oder speichere es als neues Level." % query)
		return
	if matches.size() > 1:
		var names: PackedStringArray = []
		for level: Dictionary in matches.slice(0, MAX_LISTED_MATCHES):
			names.append(level.level_name)
		var more: String = ", ..." if matches.size() > MAX_LISTED_MATCHES else ""
		_set_status("Mehrere Levels passen: %s%s. Schreib den Namen genauer." % [", ".join(names), more])
		return
	_load_level(matches[0])

# ---------------------------------------------------------------------------
# Trying and saving
# ---------------------------------------------------------------------------

func _on_try_button_pressed() -> void:
	var problem: String = _find_room_problem()
	if not problem.is_empty():
		_notify(problem)
		return
	if not _write_preview_level():
		_set_status("Ausprobieren hat nicht geklappt. Sag dem Dev-Team Bescheid.")
		return
	_start_preview()

func _write_preview_level() -> bool:
	var level: LevelConfig = LevelConfig.new()
	level.uuid = "level_editor_preview"
	level.display_name = _get_display_name()
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

	var path: String = _get_save_path()
	var level: LevelConfig = LevelConfig.new()
	level.uuid = loaded_uuid if path == loaded_path else str(ResourceUID.create_id())
	level.display_name = _get_display_name()
	draft.apply_to(level, scene_tile_set)

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(level, path) != OK:
		_set_status("Speichern hat nicht geklappt. Sag dem Dev-Team Bescheid.")
		return false
	# From now on this level counts as loaded, so the same kid can keep saving it.
	loaded_path = path
	loaded_uuid = level.uuid
	loaded_name_key = _normalize(level.display_name)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_set_status("Gespeichert! Dein Level heißt: %s" % level.display_name)
	saved.emit(path.get_base_dir().get_base_dir().get_file())
	return true

func _find_save_problem() -> String:
	var level_name: String = _read_level_name()
	if _normalize(level_name).is_empty():
		return "Gib deinem Level zuerst einen Namen."
	if not _is_overwriting_loaded():
		var existing: Dictionary = _find_level_by_name(level_name)
		if not existing.is_empty():
			return "Ein Level mit dem Namen \"%s\" gibt es schon. Lade es zuerst, wenn du es ändern willst, oder nimm einen anderen Namen." % existing.level_name
		if FileAccess.file_exists(_get_save_path()):
			return "Dieser Name ist schon vergeben. Nimm einen anderen."
	return _find_room_problem()

func _find_room_problem() -> String:
	if draft.is_empty():
		return "Dein Raum ist noch leer."
	for cell: Vector2i in draft.get_placed_cells():
		if cell in safe_cells:
			return "Vor den Türen muss Platz bleiben."
	if not LevelRules.get_unreachable_doors(floor_cells, door_cells, draft.get_obstacle_cells()).is_empty():
		return "Eine Tür ist zugebaut. Der Spieler muss zu allen Türen kommen."
	return ""

func _set_status(message: String) -> void:
	status_label.text = message

## Floating messages live on their own clipped layer, so they never affect the layout.
func _get_notify_layer() -> Control:
	if notify_layer == null or not is_instance_valid(notify_layer):
		notify_layer = Control.new()
		notify_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notify_layer.clip_contents = true
		notify_layer.custom_minimum_size = Vector2.ZERO
		notify_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		room_view.add_child(notify_layer)
	return notify_layer

## The status line alone went unnoticed, so problems also float up from the mouse for a moment.
func _notify(message: String) -> void:
	_set_status(message)
	var now: int = Time.get_ticks_msec()
	if message == last_message and now - last_message_time < MESSAGE_SECONDS * 1000.0:
		return
	last_message = message
	last_message_time = now

	var layer: Control = _get_notify_layer()
	var label: Label = Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wrap at a fixed width, so a long message gets taller instead of wider.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = minf(layer.size.x * 0.8, 700.0)
	layer.add_child(label)
	label.reset_size()

	var mouse_position: Vector2 = room_view.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, layer.size).has_point(mouse_position):
		mouse_position = layer.size / 2.0
	label.position = (mouse_position - Vector2(label.size.x / 2.0, label.size.y + 16)).clamp(
		Vector2.ZERO, (layer.size - label.size).max(Vector2.ZERO))

	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 60.0, MESSAGE_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, MESSAGE_SECONDS).set_delay(MESSAGE_SECONDS / 2.0)
	tween.chain().tween_callback(label.queue_free)


func _on_eraser_button_2_pressed() -> void:
	var created: int = scan_new_obstacles()
	build_palette()
	_set_status("%d neue Hindernisse gefunden." % created)
