@tool
class_name KidFolders
extends RefCounted
## One folder per kid under custom_data. The folder name is the code, the animal name is what kids recognise.

const CUSTOM_DATA_PATH: String = "res://custom_data"
const ANIMAL_PATH_TEMPLATE: String = "res://custom_data/%s/animal/animal_%s.tres"
const LEVEL_PATH_TEMPLATE: String = "res://custom_data/%s/level/level_%s.tres"

static var _animals: Dictionary[String, Resource] = {}
static var _stamps: Dictionary[String, Vector2i] = {}

static func get_animal_path(code: String) -> String:
	return ANIMAL_PATH_TEMPLATE % [code, code]

static func get_level_path(code: String) -> String:
	return LEVEL_PATH_TEMPLATE % [code, code]

## Returns [{code, name}] sorted by name, only for folders that hold an animal or a level.
static func list() -> Array[Dictionary]:
	var folders: Array[Dictionary] = []
	for code: String in DirAccess.get_directories_at(CUSTOM_DATA_PATH):
		var name: String = get_display_name(code)
		if not name.is_empty():
			folders.append({"code": code, "name": name})
	folders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return folders

static func get_display_name(code: String) -> String:
	var animal: AnimalConfig = _load(get_animal_path(code)) as AnimalConfig
	if animal and not animal.display_name.is_empty():
		return animal.display_name
	if animal or ResourceLoader.exists(get_level_path(code)):
		return code
	return ""

static func load_animal(code: String) -> AnimalConfig:
	var animal := _load(get_animal_path(code)) as AnimalConfig
	# Form edits stay private until saved; textures/audio can remain shared.
	return animal.duplicate() as AnimalConfig if animal else null

static func _load(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		_animals.erase(path)
		_stamps.erase(path)
		return null
	var disk_path: String = path if FileAccess.file_exists(path) else path + ".remap"
	var file := FileAccess.open(disk_path, FileAccess.READ)
	var stamp := Vector2i(FileAccess.get_modified_time(disk_path), file.get_length()) if file else Vector2i(-1, -1)
	if _animals.has(path) and _stamps.get(path) == stamp:
		return _animals[path]
	var animal := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if animal:
		_animals[path] = animal
		_stamps[path] = stamp
	return animal
