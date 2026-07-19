class_name FactoryLoader
extends RefCounted


static func create_prototype_factory() -> Factory:
	var factory := Factory.new()

	var supplier := _load_machine(
		"res://data/machines/log_supplier.json",
		"log_supplier_1"
	)

	var chipper := _load_machine(
		"res://data/machines/chipper.json",
		"chipper_1"
	)

	var stockpile := _load_machine(
		"res://data/machines/chip_stockpile.json",
		"chip_stockpile_1"
	)

	factory.add_machine(supplier)
	factory.add_machine(chipper)
	factory.add_machine(stockpile)

	factory.add_connection(
		ConnectionModel.new(
			supplier,
			chipper,
			"logs",
			1.0
		)
	)

	factory.add_connection(
		ConnectionModel.new(
			chipper,
			stockpile,
			"wood_chips",
			25.0
		)
	)

	return factory


static func _load_machine(
	file_path: String,
	instance_id: String
) -> MachineModel:
	var definition := DefinitionLoader.load_json_file(file_path)

	if definition.is_empty():
		push_error(
			"Could not load machine definition: %s"
			% file_path
		)
		return null

	return MachineModel.from_definition(definition, instance_id)
