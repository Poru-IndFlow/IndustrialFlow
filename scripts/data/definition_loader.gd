class_name DefinitionLoader
extends RefCounted

static func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing definition: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open: %s" % path)
		return {}

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("JSON error in %s line %d: %s" % [
			path, json.get_error_line(), json.get_error_message()
		])
		return {}

	if not json.data is Dictionary:
		push_error("Definition root must be an object: %s" % path)
		return {}

	return json.data
