class_name Factory
extends RefCounted


signal machine_added(machine: MachineModel)
signal connection_added(connection: ConnectionModel)


var machines: Dictionary = {}
var connections: Array[ConnectionModel] = []


func add_machine(machine: MachineModel) -> void:
	if machine == null:
		return

	if machines.has(machine.instance_id):
		push_error(
			"Duplicate machine instance id: %s"
			% machine.instance_id
		)
		return

	machines[machine.instance_id] = machine
	machine_added.emit(machine)


func get_machine(instance_id: String) -> MachineModel:
	return machines.get(instance_id) as MachineModel


func add_connection(connection: ConnectionModel) -> void:
	if connection == null:
		return

	connections.append(connection)
	connection_added.emit(connection)


func tick(delta_seconds: float) -> void:
	for connection: ConnectionModel in connections:
		connection.tick(delta_seconds)

	for machine_value: Variant in machines.values():
		var machine := machine_value as MachineModel

		if machine != null:
			machine.tick(delta_seconds)
