class_name FactoryModel
extends RefCounted

var machines: Dictionary = {}
var connections: Array[ConnectionModel] = []
var event_bus: EventBus
var _next_instance_numbers: Dictionary = {}

func _init(bus: EventBus) -> void:
	event_bus = bus

func create_machine(definition_id: String, position: Vector2) -> MachineModel:
	var definition := MachineRegistry.get_definition(definition_id)
	if definition.is_empty():
		return null

	var number := int(_next_instance_numbers.get(definition_id, 1))
	var instance_id := "%s_%d" % [definition_id, number]

	while machines.has(instance_id):
		number += 1
		instance_id = "%s_%d" % [definition_id, number]

	_next_instance_numbers[definition_id] = number + 1
	return MachineModel.create(
		definition,
		instance_id,
		event_bus,
		position
	)

func rebuild_instance_counters() -> void:
	_next_instance_numbers.clear()

	for value: Variant in machines.values():
		var machine := value as MachineModel
		var prefix := "%s_" % machine.definition_id
		var number := 1

		if machine.instance_id.begins_with(prefix):
			number = int(machine.instance_id.trim_prefix(prefix)) + 1

		_next_instance_numbers[machine.definition_id] = maxi(
			number,
			int(_next_instance_numbers.get(machine.definition_id, 1))
		)

func add_machine(machine: MachineModel) -> bool:
	if machine == null or machines.has(machine.instance_id):
		return false

	machines[machine.instance_id] = machine
	event_bus.machine_added.emit(machine)
	return true

func remove_machine(machine_id: String) -> bool:
	if not machines.has(machine_id):
		return false

	var related: Array[ConnectionModel] = []
	for connection: ConnectionModel in connections:
		if connection.from_machine.instance_id == machine_id 		or connection.to_machine.instance_id == machine_id:
			related.append(connection)

	for connection: ConnectionModel in related:
		remove_connection(connection)

	machines.erase(machine_id)
	event_bus.machine_removed.emit(machine_id)
	return true

func get_machine(machine_id: String) -> MachineModel:
	return machines.get(machine_id) as MachineModel

func add_connection(connection: ConnectionModel) -> bool:
	if connection == null:
		return false

	if has_connection(
		connection.from_machine.instance_id,
		connection.to_machine.instance_id,
		connection.resource_id
	):
		return false

	connections.append(connection)
	event_bus.connection_added.emit(connection)
	return true

func remove_connection(connection: ConnectionModel) -> bool:
	var index := connections.find(connection)
	if index < 0:
		return false

	connections.remove_at(index)
	event_bus.connection_removed.emit(connection)
	return true

func has_connection(
	from_id: String,
	to_id: String,
	resource_id: String
) -> bool:
	for connection: ConnectionModel in connections:
		if connection.from_machine.instance_id == from_id 		and connection.to_machine.instance_id == to_id 		and connection.resource_id == resource_id:
			return true

	return false

func find_connection(
	from_id: String,
	to_id: String,
	resource_id: String
) -> ConnectionModel:
	for connection: ConnectionModel in connections:
		if connection.from_machine.instance_id == from_id 		and connection.to_machine.instance_id == to_id 		and connection.resource_id == resource_id:
			return connection

	return null

func tick(delta_seconds: float) -> void:
	for connection: ConnectionModel in connections:
		connection.tick(delta_seconds)

	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		machine.tick(delta_seconds)
		machine.advance_production_telemetry(delta_seconds)
