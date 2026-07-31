class_name ResearchRegistry
extends RefCounted


const DIRECTORY := "res://data/research"
static var _definitions: Dictionary = {}
static var _loaded := false


static func load_all(force := false) -> void:
	if _loaded and not force:
		return

	_definitions.clear()
	var directory := DirAccess.open(DIRECTORY)

	if directory == null:
		push_error("Cannot open %s" % DIRECTORY)
		return

	directory.list_dir_begin()
	var file_name := directory.get_next()

	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var definition := DefinitionLoader.load_json_file(
				"%s/%s" % [DIRECTORY, file_name]
			)
			var research_id := str(definition.get("id", ""))

			if not research_id.is_empty():
				_definitions[research_id] = definition

		file_name = directory.get_next()

	directory.list_dir_end()
	_loaded = true


static func get_definition(research_id: String) -> Dictionary:
	load_all()
	return _definitions.get(research_id, {}) as Dictionary


static func get_all_definitions() -> Array[Dictionary]:
	load_all()
	var result: Array[Dictionary] = []

	for value: Variant in _definitions.values():
		result.append(value as Dictionary)

	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.get("display_name", "")).naturalnocasecmp_to(
				str(right.get("display_name", ""))
			) < 0
	)
	return result


static func get_for_machine(
	definition_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for definition: Dictionary in get_all_definitions():
		if str(definition.get("target_machine_id", "")) == definition_id:
			result.append(definition)

	return result
