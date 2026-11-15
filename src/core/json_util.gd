class_name JsonUtil
extends RefCounted
## Small helpers for reading JSON content files.
## Note: JSON numbers always parse as float in Godot. Cast with int() where an
## integer is meant (the data registry and engine do this at load time).


## Parses a JSON file. Returns null (and logs an error) on failure.
static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JsonUtil: file not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JsonUtil: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Lists files with the given extension in a directory (non-recursive, sorted).
static func list_files(dir_path: String, extension: String = "json") -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.get_extension() == extension:
			out.append(dir_path.path_join(file_name))
	out.sort()
	return out
