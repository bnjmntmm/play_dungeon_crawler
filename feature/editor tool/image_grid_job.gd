@tool
extends RefCounted
## File access and PNG decoding stay off the UI thread. Only small preview images
## cross back to the main thread, where textures and controls are created.

const THUMBNAIL_SIZE: int = 256

var task_id: int = -1
var _mutex := Mutex.new()
var _pending: Array[Dictionary] = []
var _cancelled: bool = false

func start(root_path: String, cached_stamps: Dictionary) -> void:
	task_id = WorkerThreadPool.add_task(_scan.bind(root_path, cached_stamps))

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var result := _cancelled
	_mutex.unlock()
	return result

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

func _scan(root_path: String, cached_stamps: Dictionary) -> void:
	for folder: String in DirAccess.get_directories_at(root_path):
		if is_cancelled():
			return
		var animal_dir := root_path.path_join(folder).path_join("animal")
		if not DirAccess.dir_exists_absolute(animal_dir):
			continue
		for file_name: String in DirAccess.get_files_at(animal_dir):
			if is_cancelled():
				return
			if file_name.get_extension().to_lower() != "png":
				continue
			var path := animal_dir.path_join(file_name)
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			var stamp := Vector2i(FileAccess.get_modified_time(path), file.get_length())
			var entry := {"path": path, "folder": folder, "stamp": stamp}
			if cached_stamps.get(path) != stamp:
				var image := Image.new()
				if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK or image.is_empty():
					continue
				var longest := maxi(image.get_width(), image.get_height())
				if longest > THUMBNAIL_SIZE:
					var ratio := float(THUMBNAIL_SIZE) / longest
					image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_BILINEAR)
				entry.image = image
			file.close()
			_mutex.lock()
			_pending.append(entry)
			_mutex.unlock()
