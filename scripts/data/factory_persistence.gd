class_name FactoryPersistence
extends RefCounted


const FORMAT_NAME := "IndustrialFlow Factory"
const FORMAT_VERSION := 1


static func save_factory(
	path: String,
	factory: FactoryModel,
	elapsed_simulation_seconds: float = 0.0
) -> Error:
	if factory == null:
		return ERR_INVALID_PARAMETER

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return FileAccess.get_open_error()

	var data: Dictionary = {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"elapsed_simulation_seconds": maxf(
			elapsed_simulation_seconds,
			0.0
		),
		"economy": factory.serialize_economy(),
		"research": factory.serialize_research(),
		"production_targets": factory.serialize_production_targets(),
		"customer_orders": factory.serialize_customer_orders(),
		"machines": _serialize_machines(factory),
		"connections": _serialize_connections(factory)
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


static func load_factory(
	path: String,
	event_bus: EventBus
) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if file == null:
		return _load_error(
			FileAccess.get_open_error(),
			"Could not open the selected project."
		)

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error: Error = json.parse(json_text)

	if parse_error != OK:
		return _load_error(
			parse_error,
			"Invalid project JSON at line %d: %s" % [
				json.get_error_line(),
				json.get_error_message()
			]
		)

	if not json.data is Dictionary:
		return _load_error(
			ERR_FILE_CORRUPT,
			"The project root must be a JSON object."
		)

	var data := json.data as Dictionary

	if str(data.get("format", "")) != FORMAT_NAME:
		return _load_error(
			ERR_FILE_UNRECOGNIZED,
			"This is not an IndustrialFlow project file."
		)

	var version := int(data.get("version", 0))

	if version != FORMAT_VERSION:
		return _load_error(
			ERR_FILE_UNRECOGNIZED,
			"Unsupported project version: %d." % version
		)

	return _deserialize_factory(data, event_bus)


static func _serialize_machines(factory: FactoryModel) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var machine_ids: Array = factory.machines.keys()
	machine_ids.sort()

	for value: Variant in machine_ids:
		var machine := factory.get_machine(str(value))

		if machine == null:
			continue

		result.append({
			"instance_id": machine.instance_id,
			"definition_id": machine.definition_id,
			"position": {
				"x": machine.graph_position.x,
				"y": machine.graph_position.y
			},
			"enabled": machine.enabled,
			"operating_rate": machine.operating_rate,
			"manual_operating_rate": machine.manual_operating_rate,
			"actual_operating_rate": machine.actual_operating_rate,
			"control_mode": int(machine.control_mode),
			"inventory_setpoint": machine.inventory_setpoint,
			"controller_kp": machine.controller_kp,
			"controller_ki": machine.controller_ki,
			"controller_integral": machine.controller_integral,
			"condition": machine.condition,
			"operating_hours": machine.operating_hours,
			"installed_upgrades": machine.installed_upgrades.duplicate(),
			"maintenance_remaining_seconds": machine.maintenance_remaining_seconds,
			"maintenance_total_seconds": machine.maintenance_total_seconds,
			"maintenance_is_emergency": machine.maintenance_is_emergency,
			"maintenance_policy_enabled": machine.maintenance_policy_enabled,
			"maintenance_policy_condition": machine.maintenance_policy_condition,
			"maintenance_policy_cash_reserve": machine.maintenance_policy_cash_reserve,
			"preventive_maintenance_count": machine.preventive_maintenance_count,
			"failure_count": machine.failure_count,
			"emergency_repair_count": machine.emergency_repair_count,
			"maintenance_spend": machine.maintenance_spend,
			"maintenance_downtime_seconds": machine.maintenance_downtime_seconds,
			"failed_downtime_seconds": machine.failed_downtime_seconds,
			"state": int(machine.state),
			"cycle_progress": machine.cycle_progress,
			"batch_active": machine.batch_active,
			"batch_outputs": machine.batch_outputs.duplicate(true),
			"inventory": machine.inventory.amounts.duplicate(true)
		})

	return result


static func _serialize_connections(
	factory: FactoryModel
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for connection: ConnectionModel in factory.connections:
		result.append({
			"from": connection.from_machine.instance_id,
			"to": connection.to_machine.instance_id,
			"resource": connection.resource_id,
			"capacity_per_second": connection.capacity_per_second,
			"enabled": connection.enabled
		})

	return result


static func _deserialize_factory(
	data: Dictionary,
	event_bus: EventBus
) -> Dictionary:
	if event_bus == null:
		return _load_error(
			ERR_INVALID_PARAMETER,
			"No event bus is available for the loaded factory."
		)

	var factory := FactoryModel.new(event_bus)
	var economy_data: Dictionary = data.get("economy", {})
	factory.restore_economy(economy_data)
	var research_data: Dictionary = data.get("research", {})
	factory.restore_research(research_data)
	factory.restore_production_targets(
		data.get("production_targets", []) as Array
	)
	factory.restore_customer_orders(
		data.get("customer_orders", []) as Array
	)
	var machine_entries: Array = data.get("machines", [])

	for value: Variant in machine_entries:
		if not value is Dictionary:
			return _load_error(
				ERR_FILE_CORRUPT,
				"A machine entry is invalid."
			)

		var entry := value as Dictionary
		var definition_id := str(entry.get("definition_id", ""))
		var instance_id := str(entry.get("instance_id", ""))
		var definition := MachineRegistry.get_definition(definition_id)

		if definition.is_empty() or instance_id.is_empty():
			return _load_error(
				ERR_FILE_CORRUPT,
				"Unknown or invalid machine: %s." % definition_id
			)

		var position_data: Dictionary = entry.get("position", {})
		var position := Vector2(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0))
		)
		var machine := MachineModel.create(
			definition,
			instance_id,
			event_bus,
			position
		)
		machine.enabled = bool(entry.get("enabled", true))
		machine.operating_rate = clampf(
			float(entry.get("operating_rate", 1.0)),
			0.0,
			1.5
		)
		machine.manual_operating_rate = clampf(
			float(
				entry.get(
					"manual_operating_rate",
					machine.operating_rate
				)
			),
			0.0,
			1.5
		)
		machine.control_mode = clampi(
			int(
				entry.get(
					"control_mode",
					MachineModel.ControlMode.MANUAL
				)
			),
			MachineModel.ControlMode.MANUAL,
			MachineModel.ControlMode.AUTOMATIC
		)
		machine.inventory_setpoint = maxf(
			0.0,
			float(
				entry.get(
					"inventory_setpoint",
					machine.inventory_setpoint
				)
			)
		)
		machine.controller_kp = maxf(
			0.0,
			float(
				entry.get(
					"controller_kp",
					machine.controller_kp
				)
			)
		)
		machine.controller_ki = maxf(
			0.0,
			float(
				entry.get(
					"controller_ki",
					machine.controller_ki
				)
			)
		)
		machine.controller_integral = clampf(
			float(entry.get("controller_integral", 0.0)),
			-machine.controller_output_max,
			machine.controller_output_max
		)
		machine.condition = clampf(
			float(entry.get("condition", 1.0)),
			0.0,
			1.0
		)
		machine.maintenance_policy_enabled = bool(
			entry.get("maintenance_policy_enabled", false)
		)
		machine.maintenance_policy_condition = clampf(
			float(
				entry.get(
					"maintenance_policy_condition",
					machine.maintenance_warning_condition
				)
			),
			0.01,
			0.99
		)
		machine.maintenance_policy_cash_reserve = maxf(
			0.0,
			float(entry.get("maintenance_policy_cash_reserve", 0.0))
		)
		machine.operating_hours = maxf(
			0.0,
			float(entry.get("operating_hours", 0.0))
		)
		machine.preventive_maintenance_count = maxi(
			0,
			int(
				entry.get(
					"preventive_maintenance_count",
					1
					if (
						float(entry.get("maintenance_remaining_seconds", 0.0)) > 0.0
						and not bool(entry.get("maintenance_is_emergency", false))
					)
					else 0
				)
			)
		)
		machine.failure_count = maxi(
			0,
			int(entry.get("failure_count", 1 if machine.condition <= 0.0 else 0))
		)
		machine.emergency_repair_count = maxi(
			0,
			int(
				entry.get(
					"emergency_repair_count",
					1 if bool(entry.get("maintenance_is_emergency", false)) else 0
				)
			)
		)
		machine.maintenance_spend = maxf(
			0.0,
			float(
				entry.get(
					"maintenance_spend",
					(
						machine.emergency_repair_cost
						if bool(entry.get("maintenance_is_emergency", false))
						else machine.maintenance_cost
					)
					if float(entry.get("maintenance_remaining_seconds", 0.0)) > 0.0
					else 0.0
				)
			)
		)
		machine.maintenance_downtime_seconds = maxf(
			0.0,
			float(entry.get("maintenance_downtime_seconds", 0.0))
		)
		machine.failed_downtime_seconds = maxf(
			0.0,
			float(entry.get("failed_downtime_seconds", 0.0))
		)
		machine.restore_installed_upgrades(
			entry.get("installed_upgrades", []) as Array
		)
		machine.actual_operating_rate = clampf(
			float(entry.get("actual_operating_rate", 0.0)),
			0.0,
			1.5
		)
		machine.state = int(
			entry.get("state", MachineModel.State.IDLE)
		)
		machine.restore_maintenance(
			float(entry.get("maintenance_remaining_seconds", 0.0)),
			float(entry.get("maintenance_total_seconds", 0.0)),
			bool(entry.get("maintenance_is_emergency", false))
		)
		machine.cycle_progress = float(
			entry.get("cycle_progress", 0.0)
		)
		machine.batch_active = bool(entry.get("batch_active", false))
		machine.batch_outputs.clear()
		var saved_batch_outputs: Array = entry.get("batch_outputs", [])

		for output: Variant in saved_batch_outputs:
			if output is Dictionary:
				machine.batch_outputs.append(
					(output as Dictionary).duplicate(true)
				)
		_restore_inventory(
			machine,
			entry.get("inventory", {}) as Dictionary
		)

		if not factory.add_machine(machine):
			return _load_error(
				ERR_FILE_CORRUPT,
				"Duplicate machine ID: %s." % instance_id
			)

	var connection_entries: Array = data.get("connections", [])

	for value: Variant in connection_entries:
		if not value is Dictionary:
			return _load_error(
				ERR_FILE_CORRUPT,
				"A connection entry is invalid."
			)

		var entry := value as Dictionary
		var from_machine := factory.get_machine(
			str(entry.get("from", ""))
		)
		var to_machine := factory.get_machine(
			str(entry.get("to", ""))
		)
		var resource_id := str(entry.get("resource", ""))

		if (
			from_machine == null
			or to_machine == null
			or resource_id.is_empty()
		):
			return _load_error(
				ERR_FILE_CORRUPT,
				"A connection references missing data."
			)

		var connection := ConnectionModel.new(
			from_machine,
			to_machine,
			resource_id,
			float(entry.get("capacity_per_second", 1.0))
		)
		connection.enabled = bool(entry.get("enabled", true))

		if not factory.add_connection(connection):
			return _load_error(
				ERR_FILE_CORRUPT,
				"Duplicate connection in project file."
			)

	factory.rebuild_instance_counters()
	return {
		"error": OK,
		"message": "",
		"factory": factory,
		"elapsed_simulation_seconds": maxf(
			float(
				data.get(
					"elapsed_simulation_seconds",
					0.0
				)
			),
			0.0
		)
	}


static func _restore_inventory(
	machine: MachineModel,
	inventory_data: Dictionary
) -> void:
	for value: Variant in inventory_data.keys():
		var resource_id := str(value)
		var amount := maxf(
			0.0,
			float(inventory_data[value])
		)
		machine.inventory.amounts[resource_id] = minf(
			amount,
			machine.inventory.get_capacity(resource_id)
		)


static func _load_error(error: Error, message: String) -> Dictionary:
	return {
		"error": error,
		"message": message,
		"factory": null
	}
