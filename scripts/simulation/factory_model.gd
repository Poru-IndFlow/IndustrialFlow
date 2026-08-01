class_name FactoryModel
extends RefCounted

const DEFAULT_STARTING_CASH := 10000.0
const ECONOMY_WINDOW_SECONDS := 1.0
const DEFAULT_SALVAGE_RATIO := 0.5
const MAX_ECONOMY_SAMPLES := 120

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
		_account_for_machine(machine, delta_seconds)
		machine.advance_production_telemetry(delta_seconds)

	_advance_economy_telemetry(delta_seconds)


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
