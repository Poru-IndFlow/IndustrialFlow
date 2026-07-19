class_name PrototypeFactoryBuilder
extends RefCounted

static func build(bus: EventBus) -> FactoryModel:
	ResourceRegistry.load_all()
	MachineRegistry.load_all()
	var factory := FactoryModel.new(bus)

	var supplier := factory.create_machine("log_supplier", Vector2(100, 220))
	var chipper := factory.create_machine("chipper", Vector2(430, 220))
	var stockpile := factory.create_machine("chip_stockpile", Vector2(780, 220))

	factory.add_machine(supplier)
	factory.add_machine(chipper)
	factory.add_machine(stockpile)
	factory.add_connection(ConnectionModel.new(supplier, chipper, "logs", 1.0))
	factory.add_connection(ConnectionModel.new(chipper, stockpile, "wood_chips", 25.0))
	return factory
