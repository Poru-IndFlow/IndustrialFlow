class_name PrototypeFactoryBuilder
extends RefCounted

static func build(bus: EventBus) -> FactoryModel:
	ResourceRegistry.load_all()
	MachineRegistry.load_all()
	var factory := FactoryModel.new(bus)

	var supplier := factory.create_machine("log_supplier", Vector2(100, 220))
	var chipper := factory.create_machine("chipper", Vector2(430, 220))
	var stockpile := factory.create_machine("chip_stockpile", Vector2(780, 220))
	var water := factory.create_machine("water_utility", Vector2(100, 520))
	var gas := factory.create_machine("gas_utility", Vector2(100, 760))
	var boiler := factory.create_machine("boiler", Vector2(430, 620))
	var digester := factory.create_machine("batch_digester", Vector2(1130, 260))
	var raw_tank := factory.create_machine("raw_pulp_tank", Vector2(1480, 260))
	var washer := factory.create_machine("pulp_washer", Vector2(1830, 260))
	var finished_storage := factory.create_machine(
		"finished_pulp_storage",
		Vector2(2180, 260)
	)

	factory.add_machine(supplier)
	factory.add_machine(chipper)
	factory.add_machine(stockpile)
	factory.add_machine(water)
	factory.add_machine(gas)
	factory.add_machine(boiler)
	factory.add_machine(digester)
	factory.add_machine(raw_tank)
	factory.add_machine(washer)
	factory.add_machine(finished_storage)
	factory.add_connection(ConnectionModel.new(supplier, chipper, "logs", 1.0))
	factory.add_connection(ConnectionModel.new(chipper, stockpile, "wood_chips", 25.0))
	factory.add_connection(ConnectionModel.new(stockpile, digester, "wood_chips", 25.0))
	factory.add_connection(ConnectionModel.new(water, boiler, "water", 2.0))
	factory.add_connection(ConnectionModel.new(gas, boiler, "gas", 2.0))
	factory.add_connection(ConnectionModel.new(boiler, digester, "steam", 2.0))
	factory.add_connection(ConnectionModel.new(water, digester, "water", 2.0))
	factory.add_connection(ConnectionModel.new(digester, raw_tank, "raw_pulp", 10.0))
	factory.add_connection(ConnectionModel.new(raw_tank, washer, "raw_pulp", 10.0))
	factory.add_connection(ConnectionModel.new(water, washer, "water", 2.0))
	factory.add_connection(ConnectionModel.new(washer, finished_storage, "finished_pulp", 10.0))
	return factory
