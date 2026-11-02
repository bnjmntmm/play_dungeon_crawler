@tool
class_name LevelCode
extends RefCounted
## Word codes for kids, because real names must not end up in the project.

const ADJECTIVES: PackedStringArray = [
	"roter", "blauer", "gruener", "gelber", "lila", "bunter", "wilder", "kleiner", "grosser", "mutiger",
]
const ANIMALS: PackedStringArray = [
	"fuchs", "igel", "baer", "wolf", "dachs", "frosch", "hirsch", "rabe", "drache", "hase",
]
const MAX_NUMBER: int = 99
const MAX_ATTEMPTS: int = 100

static func create_unused(custom_data_path: String) -> String:
	for attempt: int in MAX_ATTEMPTS:
		var code: String = "%s_%s_%d" % [
			ADJECTIVES[randi() % ADJECTIVES.size()],
			ANIMALS[randi() % ANIMALS.size()],
			randi_range(1, MAX_NUMBER),
		]
		if not DirAccess.dir_exists_absolute(custom_data_path.path_join(code)):
			return code
	return ""
