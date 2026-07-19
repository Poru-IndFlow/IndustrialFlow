class_name MachineRegistry
extends RefCounted

const DIRECTORY := "res://data/machines"
static var _definitions: Dictionary = {}
static var _loaded := false

static func load_all(force := false) -> void:
	if _loaded and not force:
		return
	_definitions.clear()
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		push_error("Cannot open %s" % DIRECTORY)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var definition := DefinitionLoader.load_json_file("%s/%s" % [DIRECTORY, file_name])
			var id := str(definition.get("id", ""))
			if not id.is_empty():
				_definitions[id] = definition
		file_name = dir.get_next()
	dir.list_dir_end()
	_loaded = true

static func get_definition(id: String) -> Dictionary:
	load_all()
	return _definitions.get(id, {})

static func get_all_definitions() -> Array[Dictionary]:
	load_all()
	var result: Array[Dictionary] = []
	for value: Variant in _definitions.values():
		result.append(value as Dictionary)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac := str(a.get("category", "other"))
		var bc := str(b.get("category", "other"))
		if ac == bc:
			return str(a.get("display_name", "")) < str(b.get("display_name", ""))
		return ac < bc
	)
	return result
