class_name FactoryModel
extends RefCounted

const DEFAULT_STARTING_CASH := 10000.0
const ECONOMY_WINDOW_SECONDS := 1.0

var machines: Dictionary = {}
var connections: Array[ConnectionModel] = []
var event_bus: EventBus
var cash_balance := DEFAULT_STARTING_CASH
var total_revenue := 0.0
var total_expenses := 0.0
var revenue_per_second := 0.0
var expenses_per_second := 0.0
var net_cash_flow_per_second := 0.0
var _next_instance_numbers: Dictionary = {}
var _revenue_in_window := 0.0
var _expenses_in_window := 0.0
var _economy_elapsed := 0.0

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
	_update_inventory_controllers(delta_seconds)

	for connection: ConnectionModel in connections:
		connection.tick(delta_seconds)

	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		machine.tick(delta_seconds)
		_account_for_machine(machine, delta_seconds)
		machine.advance_production_telemetry(delta_seconds)

	_advance_economy_telemetry(delta_seconds)


func serialize_economy() -> Dictionary:
	return {
		"cash_balance": cash_balance,
		"total_revenue": total_revenue,
		"total_expenses": total_expenses
	}


func restore_economy(data: Dictionary) -> void:
	cash_balance = float(
		data.get("cash_balance", DEFAULT_STARTING_CASH)
	)
	total_revenue = maxf(
		0.0,
		float(data.get("total_revenue", 0.0))
	)
	total_expenses = maxf(
		0.0,
		float(data.get("total_expenses", 0.0))
	)
	revenue_per_second = 0.0
	expenses_per_second = 0.0
	net_cash_flow_per_second = 0.0
	_revenue_in_window = 0.0
	_expenses_in_window = 0.0
	_economy_elapsed = 0.0


func _account_for_machine(
	machine: MachineModel,
	delta_seconds: float
) -> void:
	var produced: Dictionary = machine.drain_economic_production()
	var consumed: Dictionary = machine.drain_economic_consumption()
	var purchase_prices: Dictionary = machine.definition.get(
		"purchase_prices",
		{}
	)
	var sale_prices: Dictionary = machine.definition.get(
		"sale_prices",
		{}
	)
	var purchase_expense := _calculate_transaction_value(
		produced,
		purchase_prices
	)
	var sales_revenue := _calculate_transaction_value(
		consumed,
		sale_prices
	)
	var power_hour_cost := maxf(
		0.0,
		float(
			machine.definition.get(
				"operating_cost_per_power_hour",
				0.0
			)
		)
	)
	var operating_expense := (
		maxf(machine.power_demand, 0.0)
		* power_hour_cost
		* maxf(delta_seconds, 0.0)
		/ 3600.0
	)

	_record_revenue(sales_revenue)
	_record_expense(purchase_expense + operating_expense)


func _calculate_transaction_value(
	amounts: Dictionary,
	prices: Dictionary
) -> float:
	var total := 0.0

	for key: Variant in amounts.keys():
		var resource_id := str(key)
		var amount := maxf(
			0.0,
			float(amounts.get(resource_id, 0.0))
		)
		var unit_price := maxf(
			0.0,
			float(prices.get(resource_id, 0.0))
		)
		total += amount * unit_price

	return total


func _record_revenue(amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance += amount
	total_revenue += amount
	_revenue_in_window += amount


func _record_expense(amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance -= amount
	total_expenses += amount
	_expenses_in_window += amount


func _advance_economy_telemetry(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	_economy_elapsed += delta_seconds

	if _economy_elapsed < ECONOMY_WINDOW_SECONDS:
		return

	revenue_per_second = _revenue_in_window / _economy_elapsed
	expenses_per_second = _expenses_in_window / _economy_elapsed
	net_cash_flow_per_second = (
		revenue_per_second - expenses_per_second
	)
	_revenue_in_window = 0.0
	_expenses_in_window = 0.0
	_economy_elapsed = 0.0

	if event_bus != null:
		event_bus.economy_changed.emit(self)


func _update_inventory_controllers(delta_seconds: float) -> void:
	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine == null or not machine.supports_inventory_control():
			continue

		var downstream_inventory := 0.0

		for connection: ConnectionModel in connections:
			if (
				not connection.enabled
				or connection.from_machine != machine
				or connection.resource_id != machine.control_resource
			):
				continue

			downstream_inventory += (
				connection.to_machine.inventory.get_amount(
					machine.control_resource
				)
			)

		machine.update_inventory_controller(
			downstream_inventory,
			delta_seconds
		)
