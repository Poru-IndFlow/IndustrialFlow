class_name ConnectionModel
extends RefCounted

var from_machine: MachineModel
var to_machine: MachineModel
var resource_id := ""
var capacity_per_second := 1.0
var enabled := true
var last_transferred_amount := 0.0
var current_rate_per_second := 0.0
var total_transferred := 0.0

func _init(
	source: MachineModel,
	destination: MachineModel,
	resource: String,
	capacity := 1.0
) -> void:
	from_machine = source
	to_machine = destination
	resource_id = resource
	capacity_per_second = maxf(capacity, 0.0)

func tick(delta_seconds: float) -> float:
	if (
		delta_seconds <= 0.0
		or not enabled
		or from_machine == null
		or to_machine == null
	):
		_update_flow_telemetry(0.0, delta_seconds)
		return 0.0

	var amount := minf(
		capacity_per_second * delta_seconds,
		minf(
			from_machine.inventory.get_amount(resource_id),
			to_machine.inventory.get_free_capacity(resource_id)
		)
	)

	if amount <= 0.0:
		_update_flow_telemetry(0.0, delta_seconds)
		return 0.0

	var removed := from_machine.inventory.remove(resource_id, amount)
	var accepted := to_machine.inventory.add(resource_id, removed)

	if accepted < removed:
		from_machine.inventory.add(resource_id, removed - accepted)

	from_machine.notify_inventory_changed()
	to_machine.notify_inventory_changed()
	_update_flow_telemetry(accepted, delta_seconds)
	return accepted


func set_enabled(value: bool) -> void:
	if enabled == value:
		return

	enabled = value

	if from_machine != null and from_machine.event_bus != null:
		from_machine.event_bus.connection_settings_changed.emit(
			self
		)


func set_capacity_per_second(value: float) -> void:
	var new_capacity := clampf(value, 0.05, 10.0)

	if is_equal_approx(capacity_per_second, new_capacity):
		return

	capacity_per_second = new_capacity

	if from_machine != null and from_machine.event_bus != null:
		from_machine.event_bus.connection_settings_changed.emit(
			self
		)


func _update_flow_telemetry(
	transferred_amount: float,
	delta_seconds: float
) -> void:
	var previous_rate := current_rate_per_second
	last_transferred_amount = maxf(transferred_amount, 0.0)
	total_transferred += last_transferred_amount
	current_rate_per_second = (
		last_transferred_amount / delta_seconds
		if delta_seconds > 0.0
		else 0.0
	)

	if is_equal_approx(previous_rate, current_rate_per_second):
		return

	if from_machine != null and from_machine.event_bus != null:
		from_machine.event_bus.connection_flow_changed.emit(self)
