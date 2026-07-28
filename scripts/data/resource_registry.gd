class_name ResourceRegistry
extends RefCounted

const DIRECTORY := "res://data/resources"
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
			var def := DefinitionLoader.load_json_file("%s/%s" % [DIRECTORY, file_name])
			var id := str(def.get("id", ""))
			if not id.is_empty():
				_definitions[id] = def
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

	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(
				left.get("display_name", "")
			).naturalnocasecmp_to(
				str(right.get("display_name", ""))
			) < 0
	)
	return result


static func get_display_name(id: String) -> String:
	return str(get_definition(id).get("display_name", id.capitalize()))

static func get_port_type(id: String) -> int:
	return int(get_definition(id).get("port_type", 0))

static func get_unit(id: String) -> String:
	return str(get_definition(id).get("unit", "units"))

static func get_colour(id: String) -> Color:
	var arr: Array = get_definition(id).get("colour", [1.0, 1.0, 1.0, 1.0])
	if arr.size() < 3:
		return Color.WHITE
	return Color(
		float(arr[0]), float(arr[1]), float(arr[2]),
		float(arr[3]) if arr.size() > 3 else 1.0
	)
