@tool
class_name KidFolders
extends RefCounted
## One folder per kid under custom_data. The folder name is the code, the animal name is what kids recognise.

const CUSTOM_DATA_PATH: String = "res://custom_data"
const ANIMAL_PATH_TEMPLATE: String = "res://custom_data/%s/animal/animal_%s.tres"
const LEVEL_PATH_TEMPLATE: String = "res://custom_data/%s/level/level_%s.tres"

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
	return _load(get_animal_path(code)) as AnimalConfig

static func _load(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
