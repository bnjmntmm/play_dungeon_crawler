@tool
extends RefCounted
## Owns disk reads and image decoding. Controls and texture uploads stay on the UI thread.

var task_id: int = -1
var _mutex := Mutex.new()
var _pending: Array[Dictionary] = []
var _cancelled: bool = false
var _total: int = 0

func start(root_path: String, cached: Dictionary) -> void:
	task_id = WorkerThreadPool.add_task(_scan.bind(root_path, cached))

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var result: bool = _cancelled
	_mutex.unlock()
	return result

func total() -> int:
	_mutex.lock()
	var result: int = _total
	_mutex.unlock()
	return result

func _set_total(value: int) -> void:
	_mutex.lock()
	_total = value
	_mutex.unlock()

func take_pending(limit: int = 2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_mutex.lock()
	for index: int in mini(limit, _pending.size()):
		result.append(_pending.pop_front())
	_mutex.unlock()
	return result

func is_finished() -> bool:
	return task_id >= 0 and WorkerThreadPool.is_task_completed(task_id)

func wait() -> void:
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1

func _collect(dir_path: String, paths: Dictionary, pngs: Array[String]) -> void:
	if is_cancelled():
		return
	for sub_dir: String in DirAccess.get_directories_at(dir_path):
		if sub_dir != "level":
			_collect(dir_path.path_join(sub_dir), paths, pngs)
	for file: String in DirAccess.get_files_at(dir_path):
		var name: String = file.trim_suffix(".remap").trim_suffix(".import")
		if name.get_extension() in ["tres", "res"]:
			paths[dir_path.path_join(name)] = true
		elif dir_path.get_file() == "obstacle" and file.get_extension().to_lower() == "png":
			pngs.append(dir_path.path_join(file))

func _stamp(path: String) -> Vector2i:
	var disk_path: String = path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".remap"):
		disk_path += ".remap"
	var file := FileAccess.open(disk_path, FileAccess.READ)
	if file == null:
		return Vector2i(-1, -1)
	return Vector2i(FileAccess.get_modified_time(disk_path), file.get_length())

func _enqueue(path: String, config: BaseConfig, stamp: Vector2i, cached: Dictionary, new_obstacle: bool = false) -> void:
	var entry: Dictionary = {"path": path, "config": config, "stamp": stamp, "new_obstacle": new_obstacle}
	if config and not config.source_png.is_empty():
		entry.png_stamp = _stamp(config.source_png)
		if cached.get("png_stamp") != entry.png_stamp or cached.get("config") != config:
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(config.source_png)) == OK and not image.is_empty():
				entry.image = image
	_mutex.lock()
	_pending.append(entry)
	_mutex.unlock()

func _scan(root_path: String, cached: Dictionary) -> void:
	var paths: Dictionary = {}
	var pngs: Array[String] = []
	_collect(root_path, paths, pngs)
	_set_total(paths.size())
	var known_pngs: Dictionary = {}
	for path: String in paths:
		if is_cancelled():
			return
		var stamp: Vector2i = _stamp(path)
		var previous: Dictionary = cached.get(path, {})
		var config: BaseConfig
		if previous.get("stamp") == stamp:
			config = previous.get("config")
		else:
			# Independent resources avoid mutating configs currently used by the UI.
			if ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_REUSE) == OK:
				config = ResourceLoader.load_threaded_get(path) as BaseConfig
		if config and not config.source_png.is_empty():
			known_pngs[config.source_png] = true
		_enqueue(path, config, stamp, previous)
	var missing: Array[String] = []
	for png_path: String in pngs:
		var path: String = png_path.get_basename() + ".tres"
		if not known_pngs.has(png_path) and not paths.has(path) and not paths.has(png_path.get_basename() + ".res"):
			missing.append(png_path)
	_set_total(paths.size() + missing.size())
	for png_path: String in missing:
		if is_cancelled():
			return
		var config := BaseConfig.new()
		config.uuid = str(ResourceUID.create_id())
		config.source_png = png_path
		_enqueue(png_path.get_basename() + ".tres", config, Vector2i(-1, -1), {}, true)
