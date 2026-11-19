extends RefCounted
## Checks the library on refresh, keeping unchanged resources and decoded drawings.

const RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]

var levels: Array[LevelConfig] = []
var animals: Array[AnimalConfig] = []
var obstacles: Array[BaseConfig] = []

var _resources: Dictionary[String, Resource] = {}
var _resource_stamps: Dictionary[String, Vector2i] = {}
var _sprites: Dictionary[String, Texture2D] = {}
var _sprite_stamps: Dictionary[String, Vector2i] = {}

func refresh(root_path: String, force_reload: bool = false, excluded_directories: PackedStringArray = []) -> void:
	var paths: Dictionary[String, bool] = {}
	_collect_paths(root_path, paths, excluded_directories)
	for path: String in _resources.keys():
		if not paths.has(path):
			_resources.erase(path)
			_resource_stamps.erase(path)

	for path: String in paths:
		var stamp: Vector2i = _file_stamp(path)
		if not force_reload and _resources.has(path) and _resource_stamps.get(path) == stamp:
			continue
		# Replace cached objects in place so levels referencing these configs stay current.
		# External resources are refreshed individually by this scan.
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if resource:
			_resources[path] = resource
			_resource_stamps[path] = stamp
		else:
			_resources.erase(path)
			_resource_stamps.erase(path)

	levels.clear()
	animals.clear()
	obstacles.clear()
	for resource: Resource in _resources.values():
		if resource is LevelConfig:
			levels.append(resource)
		elif resource is AnimalConfig:
			animals.append(resource)
		elif resource is BaseConfig:
			obstacles.append(resource)
	refresh_sprites(force_reload)

func refresh_sprites(force_reload: bool = false) -> void:
	# Levels may contain embedded configs, not just references to standalone files.
	var configs: Dictionary[BaseConfig, bool] = {}
	for config: BaseConfig in animals + obstacles:
		configs[config] = true
	for level: LevelConfig in levels:
		for config: BaseConfig in level.animal_resource_data.values() + level.obstacle_resource_data.values():
			if config:
				configs[config] = true

	var used_pngs: Dictionary[String, bool] = {}
	for config: BaseConfig in configs:
		var path: String = config.source_png
		if path.is_empty():
			continue
		# Shared drawings are checked and decoded once, even across different configs.
		if not used_pngs.has(path):
			used_pngs[path] = true
			var stamp: Vector2i = _file_stamp(path)
			if force_reload or not _sprites.has(path) or _sprite_stamps.get(path) != stamp:
				if config.refresh_sprite():
					_sprites[path] = config.sprite
					_sprite_stamps[path] = stamp
				else:
					_sprites.erase(path)
					_sprite_stamps.erase(path)
					push_warning("No sprite refresh for %s" % path)
		if _sprites.has(path):
			config.sprite = _sprites[path]

	for path: String in _sprites.keys():
		if not used_pngs.has(path):
			_sprites.erase(path)
			_sprite_stamps.erase(path)

func _collect_paths(dir_path: String, paths: Dictionary[String, bool], excluded_directories: PackedStringArray) -> void:
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		if sub_dir not in excluded_directories:
			_collect_paths(dir_path.path_join(sub_dir), paths, excluded_directories)
	for file: String in DirAccess.get_files_at(dir_path):
		var file_name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() in RESOURCE_EXTENSIONS:
			paths[dir_path.path_join(file_name)] = true

func _file_stamp(path: String) -> Vector2i:
	# Exported configs can have only a remap file at their original path.
	var disk_path: String = path
	if not FileAccess.file_exists(disk_path) and FileAccess.file_exists(path + ".remap"):
		disk_path = path + ".remap"
	var file: FileAccess = FileAccess.open(disk_path, FileAccess.READ)
	if file == null:
		return Vector2i(-1, -1)
	return Vector2i(FileAccess.get_modified_time(disk_path), file.get_length())
