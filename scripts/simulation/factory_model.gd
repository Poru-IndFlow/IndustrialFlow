class_name FactoryModel
extends RefCounted

const DEFAULT_STARTING_CASH := 10000.0
const ECONOMY_WINDOW_SECONDS := 1.0
const DEFAULT_SALVAGE_RATIO := 0.5
const MAX_ECONOMY_SAMPLES := 120
const ORDER_STATUS_OFFERED := "offered"
const ORDER_STATUS_ACTIVE := "active"
const ORDER_STATUS_COMPLETED := "completed"
const ORDER_STATUS_FAILED := "failed"
const ORDER_STATUS_DECLINED := "declined"
const ORDER_UNIT_PRICES := {
	"gas": 0.4,
	"logs": 1.5,
	"steam": 1.0,
	"water": 0.2,
	"wood_chips": 0.05
}

var machines: Dictionary = {}
var connections: Array[ConnectionModel] = []
var event_bus: EventBus
var cash_balance := DEFAULT_STARTING_CASH
var total_revenue := 0.0
var total_expenses := 0.0
var revenue_per_second := 0.0
var expenses_per_second := 0.0
var net_cash_flow_per_second := 0.0
var machine_economy: Dictionary = {}
var resource_economy: Dictionary = {}
var economy_samples: Array[Dictionary] = []
var researched_ideas: Dictionary = {}
var production_targets: Array[Dictionary] = []
var _next_production_target_id := 1
var customer_orders: Array[Dictionary] = []
var _next_customer_order_id := 1
var _next_instance_numbers: Dictionary = {}
var _revenue_in_window := 0.0
var _expenses_in_window := 0.0
var _economy_elapsed := 0.0
var _economy_sample_time := 0.0

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


func get_machine_purchase_cost(definition_id: String) -> float:
	var definition := MachineRegistry.get_definition(definition_id)
	return maxf(
		0.0,
		float(definition.get("purchase_cost", 0.0))
	)


func get_machine_salvage_value(machine: MachineModel) -> float:
	if machine == null:
		return 0.0

	var purchase_cost := maxf(
		0.0,
		float(machine.definition.get("purchase_cost", 0.0))
	)
	var salvage_ratio := clampf(
		float(
			machine.definition.get(
				"salvage_ratio",
				DEFAULT_SALVAGE_RATIO
			)
		),
		0.0,
		1.0
	)
	return purchase_cost * salvage_ratio


func can_afford_machine(definition_id: String) -> bool:
	return cash_balance >= get_machine_purchase_cost(definition_id)


func purchase_machine(machine: MachineModel) -> bool:
	if machine == null or machines.has(machine.instance_id):
		return false

	var purchase_cost := get_machine_purchase_cost(
		machine.definition_id
	)

	if not add_machine(machine):
		return false

	_apply_capital_expense(machine.instance_id, purchase_cost)
	return true


func reverse_machine_purchase(machine: MachineModel) -> bool:
	if machine == null or not remove_machine(machine.instance_id):
		return false

	_reverse_capital_expense(
		machine.instance_id,
		get_machine_purchase_cost(machine.definition_id)
	)
	return true


func salvage_machine(machine: MachineModel) -> bool:
	if machine == null or not remove_machine(machine.instance_id):
		return false

	_apply_salvage_revenue(
		machine.instance_id,
		get_machine_salvage_value(machine)
	)
	return true


func reverse_machine_salvage(machine: MachineModel) -> bool:
	if machine == null or machines.has(machine.instance_id):
		return false

	if not add_machine(machine):
		return false

	_reverse_salvage_revenue(
		machine.instance_id,
		get_machine_salvage_value(machine)
	)
	return true

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
		_try_start_automatic_maintenance(machine)
		_account_for_machine(machine, delta_seconds)
		machine.advance_production_telemetry(delta_seconds)

	_advance_economy_telemetry(delta_seconds)
	_advance_production_targets(delta_seconds)
	_advance_customer_orders(delta_seconds)


func generate_customer_order() -> Dictionary:
	var definitions: Array[Dictionary] = []

	for definition: Dictionary in ResourceRegistry.get_all_definitions():
		if bool(definition.get("customer_order_enabled", true)):
			definitions.append(definition)

	if definitions.is_empty():
		return {}

	var definition: Dictionary = definitions.pick_random()
	var resource_id := str(definition.get("id", ""))
	var quantity := _generate_order_quantity(resource_id)
	var deadline_seconds := float(randi_range(3, 12) * 60)
	var base_price := float(ORDER_UNIT_PRICES.get(resource_id, 1.0))
	var reward := quantity * base_price * randf_range(1.15, 1.5)
	var penalty := reward * 0.25
	var order := {
		"id": _next_customer_order_id,
		"resource_id": resource_id,
		"quantity": quantity,
		"reward": reward,
		"late_penalty": penalty,
		"deadline_total_seconds": deadline_seconds,
		"deadline_remaining_seconds": deadline_seconds,
		"status": ORDER_STATUS_OFFERED,
		"linked_target_id": 0
	}
	_next_customer_order_id += 1
	customer_orders.append(order)
	_emit_customer_orders_changed()
	return order


func _generate_order_quantity(resource_id: String) -> float:
	match resource_id:
		"wood_chips":
			return float(randi_range(5, 20) * 100)
		"logs":
			return float(randi_range(1, 5) * 10)
		"water":
			return float(randi_range(5, 20))
		"steam":
			return float(randi_range(3, 10))
		"gas":
			return float(randi_range(2, 8))
		_:
			return float(randi_range(5, 20))


func get_customer_order(order_id: int) -> Dictionary:
	for order: Dictionary in customer_orders:
		if int(order.get("id", 0)) == order_id:
			return order

	return {}


func accept_customer_order(order_id: int) -> bool:
	var order := get_customer_order(order_id)

	if order.is_empty() or str(order.get("status", "")) != ORDER_STATUS_OFFERED:
		return false

	order["status"] = ORDER_STATUS_ACTIVE
	var target := add_production_target(
		str(order["resource_id"]),
		float(order["quantity"]),
		0,
		float(order["deadline_remaining_seconds"])
	)
	order["linked_target_id"] = int(target.get("id", 0))
	_emit_customer_orders_changed()
	return true


func decline_customer_order(order_id: int) -> bool:
	var order := get_customer_order(order_id)

	if order.is_empty() or str(order.get("status", "")) != ORDER_STATUS_OFFERED:
		return false

	order["status"] = ORDER_STATUS_DECLINED
	_emit_customer_orders_changed()
	return true


func get_plant_inventory_amount(resource_id: String) -> float:
	var total := 0.0

	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine != null:
			total += machine.inventory.get_amount(resource_id)

	return total


func can_deliver_customer_order(order_id: int) -> bool:
	var order := get_customer_order(order_id)
	return (
		not order.is_empty()
		and str(order.get("status", "")) == ORDER_STATUS_ACTIVE
		and get_plant_inventory_amount(str(order["resource_id"]))
		>= float(order["quantity"])
	)


func deliver_customer_order(order_id: int) -> bool:
	if not can_deliver_customer_order(order_id):
		return false

	var order := get_customer_order(order_id)
	var resource_id := str(order["resource_id"])
	var remaining := float(order["quantity"])

	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine == null or remaining <= 0.0:
			continue

		var removed := machine.inventory.remove(resource_id, remaining)

		if removed > 0.0:
			remaining -= removed
			machine.notify_inventory_changed()

	var reward := float(order["reward"])
	order["status"] = ORDER_STATUS_COMPLETED
	_record_revenue(reward)
	_record_resource_economy(resource_id, reward, 0.0)
	_remove_linked_order_target(order)
	_emit_economy_changed()
	_emit_customer_orders_changed()
	return true


func serialize_customer_orders() -> Array[Dictionary]:
	return customer_orders.duplicate(true)


func restore_customer_orders(entries: Array) -> void:
	customer_orders.clear()
	_next_customer_order_id = 1

	for value: Variant in entries:
		if not value is Dictionary:
			continue

		var entry := (value as Dictionary).duplicate(true)
		var resource_id := str(entry.get("resource_id", ""))

		if ResourceRegistry.get_definition(resource_id).is_empty():
			continue

		var order_id := maxi(1, int(entry.get("id", 1)))
		entry["id"] = order_id
		entry["quantity"] = maxf(1.0, float(entry.get("quantity", 1.0)))
		entry["reward"] = maxf(0.0, float(entry.get("reward", 0.0)))
		entry["late_penalty"] = maxf(
			0.0,
			float(entry.get("late_penalty", 0.0))
		)
		entry["deadline_total_seconds"] = maxf(
			0.0,
			float(entry.get("deadline_total_seconds", 0.0))
		)
		entry["deadline_remaining_seconds"] = maxf(
			0.0,
			float(entry.get("deadline_remaining_seconds", 0.0))
		)
		entry["linked_target_id"] = maxi(
			0,
			int(entry.get("linked_target_id", 0))
		)
		customer_orders.append(entry)
		_next_customer_order_id = maxi(_next_customer_order_id, order_id + 1)


func _advance_customer_orders(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	for order: Dictionary in customer_orders:
		if str(order.get("status", "")) != ORDER_STATUS_ACTIVE:
			continue

		order["deadline_remaining_seconds"] = maxf(
			0.0,
			float(order.get("deadline_remaining_seconds", 0.0)) - delta_seconds
		)

		if float(order["deadline_remaining_seconds"]) > 0.0:
			continue

		order["status"] = ORDER_STATUS_FAILED
		var penalty := float(order.get("late_penalty", 0.0))
		_record_expense(penalty)
		_remove_linked_order_target(order)
		_emit_economy_changed()
		_emit_customer_orders_changed()


func _remove_linked_order_target(order: Dictionary) -> void:
	var target_id := int(order.get("linked_target_id", 0))

	if target_id > 0:
		remove_production_target(target_id)

	order["linked_target_id"] = 0


func _emit_customer_orders_changed() -> void:
	if event_bus != null:
		event_bus.customer_orders_changed.emit(self)


func add_production_target(
	resource_id: String,
	target_quantity: float,
	priority: int = 1,
	deadline_seconds: float = 0.0
) -> Dictionary:
	if (
		ResourceRegistry.get_definition(resource_id).is_empty()
		or target_quantity <= 0.0
	):
		return {}

	var target := {
		"id": _next_production_target_id,
		"resource_id": resource_id,
		"target_quantity": target_quantity,
		"produced_quantity": 0.0,
		"priority": clampi(priority, 0, 2),
		"deadline_total_seconds": maxf(deadline_seconds, 0.0),
		"deadline_remaining_seconds": maxf(deadline_seconds, 0.0)
	}
	_next_production_target_id += 1
	production_targets.append(target)
	_emit_production_targets_changed()
	return target


func remove_production_target(target_id: int) -> bool:
	for index in range(production_targets.size()):
		if int(production_targets[index].get("id", 0)) == target_id:
			production_targets.remove_at(index)
			_emit_production_targets_changed()
			return true

	return false


func get_production_target(target_id: int) -> Dictionary:
	for target: Dictionary in production_targets:
		if int(target.get("id", 0)) == target_id:
			return target

	return {}


func update_production_target(
	target_id: int,
	target_quantity: float,
	priority: int,
	deadline_seconds: float
) -> bool:
	var target := get_production_target(target_id)

	if target.is_empty() or target_quantity <= 0.0:
		return false

	target["target_quantity"] = target_quantity
	target["produced_quantity"] = minf(
		float(target.get("produced_quantity", 0.0)),
		target_quantity
	)
	target["priority"] = clampi(priority, 0, 2)
	target["deadline_total_seconds"] = maxf(deadline_seconds, 0.0)
	target["deadline_remaining_seconds"] = maxf(deadline_seconds, 0.0)
	_emit_production_targets_changed()
	return true


func move_production_target(target_id: int, direction: int) -> bool:
	var index := -1

	for candidate_index in range(production_targets.size()):
		if int(production_targets[candidate_index].get("id", 0)) == target_id:
			index = candidate_index
			break

	if index < 0 or direction == 0:
		return false

	var priority := int(production_targets[index].get("priority", 1))
	var step := -1 if direction < 0 else 1
	var swap_index := index + step

	while swap_index >= 0 and swap_index < production_targets.size():
		if int(production_targets[swap_index].get("priority", 1)) == priority:
			var moved_target := production_targets[index]
			production_targets[index] = production_targets[swap_index]
			production_targets[swap_index] = moved_target
			_emit_production_targets_changed()
			return true

		swap_index += step

	return false


func serialize_production_targets() -> Array[Dictionary]:
	return production_targets.duplicate(true)


func restore_production_targets(entries: Array) -> void:
	production_targets.clear()
	_next_production_target_id = 1

	for value: Variant in entries:
		if not value is Dictionary:
			continue

		var entry := value as Dictionary
		var resource_id := str(entry.get("resource_id", ""))
		var target_quantity := maxf(
			0.0,
			float(entry.get("target_quantity", 0.0))
		)

		if (
			ResourceRegistry.get_definition(resource_id).is_empty()
			or target_quantity <= 0.0
		):
			continue

		var target_id := maxi(1, int(entry.get("id", 1)))
		production_targets.append({
			"id": target_id,
			"resource_id": resource_id,
			"target_quantity": target_quantity,
			"produced_quantity": clampf(
				float(entry.get("produced_quantity", 0.0)),
				0.0,
				target_quantity
			),
			"priority": clampi(int(entry.get("priority", 1)), 0, 2),
			"deadline_total_seconds": maxf(
				0.0,
				float(entry.get("deadline_total_seconds", 0.0))
			),
			"deadline_remaining_seconds": maxf(
				0.0,
				float(entry.get("deadline_remaining_seconds", 0.0))
			)
		})
		_next_production_target_id = maxi(
			_next_production_target_id,
			target_id + 1
		)


func _advance_production_targets(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or production_targets.is_empty():
		return

	var gross_rates: Dictionary = {}

	for value: Variant in machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		for key: Variant in machine.production_rates_per_second.keys():
			var resource_id := str(key)
			gross_rates[resource_id] = (
				float(gross_rates.get(resource_id, 0.0))
				+ float(machine.production_rates_per_second.get(key, 0.0))
			)

	var available_production: Dictionary = {}

	for key: Variant in gross_rates.keys():
		available_production[str(key)] = (
			float(gross_rates[key]) * delta_seconds
		)

	for target: Dictionary in production_targets:
		if (
			float(target["produced_quantity"])
			< float(target["target_quantity"])
			and float(target.get("deadline_total_seconds", 0.0)) > 0.0
		):
			target["deadline_remaining_seconds"] = maxf(
				0.0,
				float(target.get("deadline_remaining_seconds", 0.0))
				- delta_seconds
			)

	var ordered_targets: Array[Dictionary] = production_targets.duplicate()
	ordered_targets.sort_custom(_sort_production_targets)

	for target: Dictionary in ordered_targets:
		var target_quantity := float(target["target_quantity"])
		var produced_quantity := float(target["produced_quantity"])

		if produced_quantity >= target_quantity:
			continue

		var resource_id := str(target["resource_id"])
		var available := float(
			available_production.get(resource_id, 0.0)
		)
		var allocated := minf(
			target_quantity - produced_quantity,
			available
		)
		target["produced_quantity"] = produced_quantity + allocated
		available_production[resource_id] = maxf(
			available - allocated,
			0.0
		)


func _sort_production_targets(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 1))
	var right_priority := int(right.get("priority", 1))

	if left_priority != right_priority:
		return left_priority < right_priority

	return production_targets.find(left) < production_targets.find(right)


func _emit_production_targets_changed() -> void:
	if event_bus != null:
		event_bus.production_targets_changed.emit(self)


func serialize_economy() -> Dictionary:
	return {
		"cash_balance": cash_balance,
		"total_revenue": total_revenue,
		"total_expenses": total_expenses,
		"machine_economy": _serialize_economy_accounts(
			machine_economy
		),
		"resource_economy": _serialize_economy_accounts(
			resource_economy
		)
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
	machine_economy.clear()
	resource_economy.clear()
	_restore_economy_accounts(
		machine_economy,
		data.get("machine_economy", {}) as Dictionary
	)
	_restore_economy_accounts(
		resource_economy,
		data.get("resource_economy", {}) as Dictionary
	)


func get_machine_economy(machine_id: String) -> Dictionary:
	return machine_economy.get(machine_id, {}) as Dictionary


func get_resource_economy(resource_id: String) -> Dictionary:
	return resource_economy.get(resource_id, {}) as Dictionary


func clear_economy_samples() -> void:
	economy_samples.clear()
	_economy_sample_time = 0.0
	_emit_economy_changed()


func serialize_research() -> Dictionary:
	return researched_ideas.duplicate(true)


func restore_research(data: Dictionary) -> void:
	researched_ideas.clear()

	for key: Variant in data.keys():
		var research_id := str(key)

		if (
			bool(data.get(key, false))
			and not ResearchRegistry.get_definition(research_id).is_empty()
		):
			researched_ideas[research_id] = true


func is_researched(research_id: String) -> bool:
	return bool(researched_ideas.get(research_id, false))


func can_research(research_id: String) -> bool:
	if is_researched(research_id):
		return false

	var definition := ResearchRegistry.get_definition(research_id)
	var cost := maxf(
		0.0,
		float(definition.get("research_cost", 0.0))
	)
	return not definition.is_empty() and cash_balance >= cost


func research_idea(research_id: String) -> bool:
	if not can_research(research_id):
		return false

	var definition := ResearchRegistry.get_definition(research_id)
	var cost := maxf(
		0.0,
		float(definition.get("research_cost", 0.0))
	)
	cash_balance -= cost
	total_expenses += cost
	researched_ideas[research_id] = true
	_emit_economy_changed()

	if event_bus != null:
		event_bus.research_changed.emit(self)

	return true


func can_install_upgrade(
	machine: MachineModel,
	research_id: String
) -> bool:
	if (
		machine == null
		or not is_researched(research_id)
		or machine.has_upgrade(research_id)
	):
		return false

	var definition := ResearchRegistry.get_definition(research_id)
	var installation_cost := maxf(
		0.0,
		float(definition.get("installation_cost", 0.0))
	)
	return (
		not definition.is_empty()
		and str(definition.get("target_machine_id", ""))
		== machine.definition_id
		and cash_balance >= installation_cost
	)


func install_machine_upgrade(
	machine: MachineModel,
	research_id: String
) -> bool:
	if not can_install_upgrade(machine, research_id):
		return false

	var definition := ResearchRegistry.get_definition(research_id)
	var installation_cost := maxf(
		0.0,
		float(definition.get("installation_cost", 0.0))
	)

	if not machine.install_upgrade(research_id):
		return false

	cash_balance -= installation_cost
	total_expenses += installation_cost
	_adjust_machine_lifetime(
		machine.instance_id,
		0.0,
		installation_cost
	)
	_emit_economy_changed()
	return true


func can_start_machine_maintenance(machine: MachineModel) -> bool:
	return (
		machine != null
		and machine.can_start_maintenance()
		and cash_balance >= machine.get_current_maintenance_cost()
	)


func start_machine_maintenance(machine: MachineModel) -> bool:
	if not can_start_machine_maintenance(machine):
		return false

	var maintenance_cost := machine.get_current_maintenance_cost()

	if not machine.start_maintenance():
		return false

	cash_balance -= maintenance_cost
	total_expenses += maintenance_cost
	_adjust_machine_lifetime(
		machine.instance_id,
		0.0,
		maintenance_cost
	)
	_emit_economy_changed()
	return true


func _try_start_automatic_maintenance(machine: MachineModel) -> void:
	if (
		machine == null
		or not machine.maintenance_policy_enabled
		or machine.is_under_maintenance()
		or machine.is_failed()
		or machine.condition > machine.maintenance_policy_condition
	):
		return

	var maintenance_cost := machine.get_current_maintenance_cost()

	if (
		cash_balance - maintenance_cost
		< machine.maintenance_policy_cash_reserve
	):
		return

	start_machine_maintenance(machine)


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
	var purchase_expense := _record_resource_transactions(
		produced,
		purchase_prices,
		false
	)
	var sales_revenue := _record_resource_transactions(
		consumed,
		sale_prices,
		true
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

	var machine_expense := purchase_expense + operating_expense
	_record_machine_economy(
		machine.instance_id,
		sales_revenue,
		machine_expense
	)
	_record_revenue(sales_revenue)
	_record_expense(machine_expense)


func _record_resource_transactions(
	amounts: Dictionary,
	prices: Dictionary,
	is_sale: bool
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
		var value := amount * unit_price
		total += value

		if value > 0.0:
			_record_resource_economy(
				resource_id,
				value if is_sale else 0.0,
				0.0 if is_sale else value
			)

	return total


func _record_machine_economy(
	machine_id: String,
	revenue: float,
	expense: float
) -> void:
	var account := _get_economy_account(
		machine_economy,
		machine_id
	)
	_add_to_economy_account(account, revenue, expense)


func _record_resource_economy(
	resource_id: String,
	revenue: float,
	expense: float
) -> void:
	var account := _get_economy_account(
		resource_economy,
		resource_id
	)
	_add_to_economy_account(account, revenue, expense)


func _get_economy_account(
	accounts: Dictionary,
	account_id: String
) -> Dictionary:
	if accounts.has(account_id):
		return accounts[account_id] as Dictionary

	var account: Dictionary = {
		"total_revenue": 0.0,
		"total_expenses": 0.0,
		"revenue_per_second": 0.0,
		"expenses_per_second": 0.0,
		"revenue_in_window": 0.0,
		"expenses_in_window": 0.0
	}
	accounts[account_id] = account
	return account


func _add_to_economy_account(
	account: Dictionary,
	revenue: float,
	expense: float
) -> void:
	account["total_revenue"] = (
		float(account.get("total_revenue", 0.0)) + revenue
	)
	account["total_expenses"] = (
		float(account.get("total_expenses", 0.0)) + expense
	)
	account["revenue_in_window"] = (
		float(account.get("revenue_in_window", 0.0)) + revenue
	)
	account["expenses_in_window"] = (
		float(account.get("expenses_in_window", 0.0)) + expense
	)


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


func _apply_capital_expense(machine_id: String, amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance -= amount
	total_expenses += amount
	_adjust_machine_lifetime(machine_id, 0.0, amount)
	_emit_economy_changed()


func _reverse_capital_expense(machine_id: String, amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance += amount
	total_expenses = maxf(0.0, total_expenses - amount)
	_adjust_machine_lifetime(machine_id, 0.0, -amount)
	_emit_economy_changed()


func _apply_salvage_revenue(machine_id: String, amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance += amount
	total_revenue += amount
	_adjust_machine_lifetime(machine_id, amount, 0.0)
	_emit_economy_changed()


func _reverse_salvage_revenue(machine_id: String, amount: float) -> void:
	if amount <= 0.0:
		return

	cash_balance -= amount
	total_revenue = maxf(0.0, total_revenue - amount)
	_adjust_machine_lifetime(machine_id, -amount, 0.0)
	_emit_economy_changed()


func _adjust_machine_lifetime(
	machine_id: String,
	revenue_delta: float,
	expense_delta: float
) -> void:
	var account := _get_economy_account(machine_economy, machine_id)
	account["total_revenue"] = maxf(
		0.0,
		float(account.get("total_revenue", 0.0)) + revenue_delta
	)
	account["total_expenses"] = maxf(
		0.0,
		float(account.get("total_expenses", 0.0)) + expense_delta
	)


func _emit_economy_changed() -> void:
	if event_bus != null:
		event_bus.economy_changed.emit(self)


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
	_update_economy_account_rates(machine_economy)
	_update_economy_account_rates(resource_economy)
	_economy_sample_time += _economy_elapsed
	economy_samples.append({
		"time": _economy_sample_time,
		"cash": cash_balance,
		"revenue": revenue_per_second,
		"expenses": expenses_per_second,
		"net": net_cash_flow_per_second
	})

	if economy_samples.size() > MAX_ECONOMY_SAMPLES:
		economy_samples.pop_front()

	_revenue_in_window = 0.0
	_expenses_in_window = 0.0
	_economy_elapsed = 0.0

	if event_bus != null:
		event_bus.economy_changed.emit(self)


func _update_economy_account_rates(accounts: Dictionary) -> void:
	for value: Variant in accounts.values():
		var account := value as Dictionary

		if account.is_empty():
			continue

		account["revenue_per_second"] = (
			float(account.get("revenue_in_window", 0.0))
			/ _economy_elapsed
		)
		account["expenses_per_second"] = (
			float(account.get("expenses_in_window", 0.0))
			/ _economy_elapsed
		)
		account["revenue_in_window"] = 0.0
		account["expenses_in_window"] = 0.0


func _serialize_economy_accounts(accounts: Dictionary) -> Dictionary:
	var result: Dictionary = {}

	for key: Variant in accounts.keys():
		var account := accounts.get(key, {}) as Dictionary
		result[str(key)] = {
			"total_revenue": maxf(
				0.0,
				float(account.get("total_revenue", 0.0))
			),
			"total_expenses": maxf(
				0.0,
				float(account.get("total_expenses", 0.0))
			)
		}

	return result


func _restore_economy_accounts(
	target: Dictionary,
	saved_accounts: Dictionary
) -> void:
	for key: Variant in saved_accounts.keys():
		var saved := saved_accounts.get(key, {}) as Dictionary
		var account := _get_economy_account(target, str(key))
		account["total_revenue"] = maxf(
			0.0,
			float(saved.get("total_revenue", 0.0))
		)
		account["total_expenses"] = maxf(
			0.0,
			float(saved.get("total_expenses", 0.0))
		)


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
