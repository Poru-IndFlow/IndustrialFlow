class_name MachineModel
extends RefCounted

enum State {
	IDLE,
	RUNNING,
	BLOCKED_INPUT,
	BLOCKED_OUTPUT,
	DISABLED
}

enum ControlMode {
	MANUAL,
	AUTOMATIC
}

var instance_id := ""
var definition_id := ""
var display_name := ""
var definition: Dictionary = {}
var recipe: RecipeDefinition
var inventory: Inventory
var behaviour: MachineBehaviour
var event_bus: EventBus
var state := State.IDLE
var enabled := true
var operating_rate := 1.0
var manual_operating_rate := 1.0
var actual_operating_rate := 0.0
var ramp_up_seconds := 1.0
var ramp_down_seconds := 1.0
var performance_curve: Array[Dictionary] = []
var power_curve: Array[Dictionary] = []
var idle_power_ratio := 0.15
var power_demand := 0.0
var control_mode := ControlMode.MANUAL
var control_resource := ""
var inventory_setpoint := 0.0
var controlled_inventory_amount := 0.0
var controller_kp := 2.0
var controller_ki := 0.001
var controller_output_min := 0.0
var controller_output_max := 1.5
var controller_integral := 0.0
var controller_error := 0.0
var cycle_progress := 0.0
var graph_position := Vector2.ZERO
var production_rates_per_second: Dictionary = {}
var consumption_rates_per_second: Dictionary = {}
var _produced_in_window: Dictionary = {}
var _consumed_in_window: Dictionary = {}
var _telemetry_elapsed := 0.0

const TELEMETRY_WINDOW_SECONDS := 1.0

static func create(
	machine_definition: Dictionary,
	new_instance_id: String,
	bus: EventBus,
	position := Vector2.ZERO
) -> MachineModel:
	var machine := MachineModel.new()
	machine.definition = machine_definition.duplicate(true)
	machine.definition_id = str(machine_definition.get("id", "unknown"))
	machine.instance_id = new_instance_id
	machine.display_name = str(
		machine_definition.get("display_name", machine.definition_id.capitalize())
	)
	machine.event_bus = bus
	machine.graph_position = position
	machine.ramp_up_seconds = maxf(
		0.001,
		float(machine_definition.get("ramp_up_seconds", 1.0))
	)
	machine.ramp_down_seconds = maxf(
		0.001,
		float(machine_definition.get("ramp_down_seconds", 1.0))
	)
	machine.performance_curve = _load_performance_curve(
		machine_definition
	)
	machine.power_curve = _load_curve(
		machine_definition,
		"power_curve",
		"power"
	)
	machine.idle_power_ratio = clampf(
		float(machine_definition.get("idle_power_ratio", 0.15)),
		0.0,
		1.0
	)
	machine.control_resource = str(
		machine_definition.get("control_resource", "")
	)
	machine.inventory_setpoint = maxf(
		0.0,
		float(machine_definition.get("inventory_setpoint", 0.0))
	)
	machine.controller_kp = maxf(
		0.0,
		float(machine_definition.get("controller_kp", 2.0))
	)
	machine.controller_ki = maxf(
		0.0,
		float(machine_definition.get("controller_ki", 0.001))
	)
	machine.controller_output_min = clampf(
		float(machine_definition.get("controller_output_min", 0.0)),
		0.0,
		1.5
	)
	machine.controller_output_max = clampf(
		float(machine_definition.get("controller_output_max", 1.5)),
		machine.controller_output_min,
		1.5
	)
	machine.recipe = RecipeDefinition.from_machine_definition(machine_definition)

	var capacities: Dictionary = {}
	for section in ["internal_storage", "storage_capacity"]:
		var data: Dictionary = machine_definition.get(section, {})
		for key: Variant in data.keys():
			capacities[str(key)] = float(data[key])

	machine.inventory = Inventory.new(capacities)
	machine.behaviour = BehaviourFactory.create(
		str(machine_definition.get("processing_mode", "storage"))
	)
	return machine


static func _load_performance_curve(
	machine_definition: Dictionary
) -> Array[Dictionary]:
	return _load_curve(
		machine_definition,
		"performance_curve",
		"output"
	)


static func _load_curve(
	machine_definition: Dictionary,
	definition_key: String,
	value_key: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = machine_definition.get(
		definition_key,
		[]
	)

	for value: Variant in entries:
		if not value is Dictionary:
			continue

		var entry := value as Dictionary
		var point: Dictionary = {
			"speed": clampf(
				float(entry.get("speed", 0.0)),
				0.0,
				1.5
			)
		}
		point[value_key] = maxf(
			float(entry.get(value_key, 0.0)),
			0.0
		)
		result.append(point)

	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left["speed"]) < float(right["speed"])
	)
	return result


func tick(delta_seconds: float) -> void:
	_update_actual_operating_rate(delta_seconds)

	if not enabled:
		set_state(State.DISABLED)
		_update_power_demand()
		return

	if actual_operating_rate <= 0.0:
		set_state(State.IDLE)
		_update_power_demand()
		return

	behaviour.tick(self, delta_seconds)
	_update_power_demand()


func get_effective_production_rate() -> float:
	if performance_curve.is_empty():
		return actual_operating_rate

	var first := performance_curve[0]

	if actual_operating_rate <= float(first["speed"]):
		return float(first["output"])

	for index: int in range(1, performance_curve.size()):
		var left := performance_curve[index - 1]
		var right := performance_curve[index]
		var right_speed := float(right["speed"])

		if actual_operating_rate > right_speed:
			continue

		var left_speed := float(left["speed"])
		var span := right_speed - left_speed

		if span <= 0.0:
			return float(right["output"])

		var weight := (
			(actual_operating_rate - left_speed) / span
		)
		return lerpf(
			float(left["output"]),
			float(right["output"]),
			weight
		)

	return float(performance_curve.back()["output"])


func get_production_efficiency() -> float:
	if actual_operating_rate <= 0.0:
		return 0.0

	return (
		get_effective_production_rate()
		/ actual_operating_rate
	)


func get_active_power_demand() -> float:
	if power_curve.is_empty() or actual_operating_rate <= 0.0:
		return 0.0

	var first := power_curve[0]

	if actual_operating_rate <= float(first["speed"]):
		return float(first["power"])

	for index: int in range(1, power_curve.size()):
		var left := power_curve[index - 1]
		var right := power_curve[index]
		var right_speed := float(right["speed"])

		if actual_operating_rate > right_speed:
			continue

		var left_speed := float(left["speed"])
		var span := right_speed - left_speed

		if span <= 0.0:
			return float(right["power"])

		var weight := (
			(actual_operating_rate - left_speed) / span
		)
		return lerpf(
			float(left["power"]),
			float(right["power"]),
			weight
		)

	return float(power_curve.back()["power"])


func get_power_mode() -> String:
	if not enabled or actual_operating_rate <= 0.0:
		return "Off"

	return "Active" if state == State.RUNNING else "Idle at speed"


func _update_power_demand() -> void:
	var active_demand := get_active_power_demand()
	var new_demand := 0.0

	if enabled and actual_operating_rate > 0.0:
		new_demand = (
			active_demand
			if state == State.RUNNING
			else active_demand * idle_power_ratio
		)

	if is_equal_approx(power_demand, new_demand):
		return

	power_demand = new_demand

	if event_bus != null:
		event_bus.machine_power_changed.emit(self)

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if event_bus != null:
		event_bus.machine_state_changed.emit(self)

func notify_inventory_changed() -> void:
	if event_bus != null:
		event_bus.machine_inventory_changed.emit(self)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return

	enabled = value

	if not enabled:
		set_state(State.DISABLED)
	elif (
		operating_rate <= 0.0
		and actual_operating_rate <= 0.0
	):
		set_state(State.IDLE)

	notify_settings_changed()


func set_operating_rate(value: float) -> void:
	var clamped_rate := clampf(value, 0.0, 1.5)

	if control_mode == ControlMode.MANUAL:
		manual_operating_rate = clamped_rate

	if is_equal_approx(operating_rate, clamped_rate):
		return

	operating_rate = clamped_rate

	if (
		enabled
		and operating_rate <= 0.0
		and actual_operating_rate <= 0.0
	):
		set_state(State.IDLE)

	notify_settings_changed()


func supports_inventory_control() -> bool:
	return not control_resource.is_empty()


func set_control_mode(value: int) -> void:
	var new_mode := clampi(
		value,
		ControlMode.MANUAL,
		ControlMode.AUTOMATIC
	)

	if control_mode == new_mode:
		return

	if new_mode == ControlMode.AUTOMATIC:
		manual_operating_rate = operating_rate
		controller_integral = _get_bumpless_integral()
	else:
		operating_rate = manual_operating_rate
		controller_integral = 0.0

	control_mode = new_mode
	notify_settings_changed()
	notify_control_changed()


func set_inventory_setpoint(value: float) -> void:
	var new_setpoint := maxf(value, 0.0)

	if is_equal_approx(inventory_setpoint, new_setpoint):
		return

	inventory_setpoint = new_setpoint
	controller_integral = 0.0
	controller_error = (
		inventory_setpoint - controlled_inventory_amount
	)
	notify_settings_changed()
	notify_control_changed()


func set_controller_kp(value: float) -> void:
	var new_value := maxf(value, 0.0)

	if is_equal_approx(controller_kp, new_value):
		return

	controller_kp = new_value
	controller_integral = 0.0
	notify_settings_changed()
	notify_control_changed()


func set_controller_ki(value: float) -> void:
	var new_value := maxf(value, 0.0)

	if is_equal_approx(controller_ki, new_value):
		return

	controller_ki = new_value
	controller_integral = 0.0
	notify_settings_changed()
	notify_control_changed()


func update_inventory_controller(
	inventory_amount: float,
	delta_seconds: float
) -> void:
	var new_inventory_amount := maxf(inventory_amount, 0.0)
	var inventory_changed := not is_equal_approx(
		controlled_inventory_amount,
		new_inventory_amount
	)
	controlled_inventory_amount = new_inventory_amount
	controller_error = inventory_setpoint - controlled_inventory_amount

	if (
		control_mode != ControlMode.AUTOMATIC
		or not supports_inventory_control()
		or delta_seconds <= 0.0
	):
		if inventory_changed:
			notify_control_changed()
		return

	var previous_rate := operating_rate
	var previous_integral := controller_integral

	if inventory_setpoint <= 0.0:
		controller_integral = 0.0
		operating_rate = 0.0

		if (
			inventory_changed
			or not is_equal_approx(previous_rate, operating_rate)
			or not is_equal_approx(
				previous_integral,
				controller_integral
			)
		):
			notify_control_changed()
		return

	var normalized_error := (
		controller_error / maxf(inventory_setpoint, 1.0)
	)
	var output_min := minf(
		controller_output_min,
		manual_operating_rate
	)
	var output_max := minf(
		controller_output_max,
		manual_operating_rate
	)
	var proposed_integral := controller_integral + (
		controller_ki * normalized_error * delta_seconds
	)
	var proposed_output := (
		controller_kp * normalized_error
		+ proposed_integral
	)
	var blocks_positive_windup := (
		proposed_output > output_max
		and normalized_error > 0.0
	)
	var blocks_negative_windup := (
		proposed_output < output_min
		and normalized_error < 0.0
	)

	if not blocks_positive_windup and not blocks_negative_windup:
		controller_integral = proposed_integral

	controller_integral = clampf(
		controller_integral,
		-output_max,
		output_max
	)
	operating_rate = clampf(
		controller_kp * normalized_error + controller_integral,
		output_min,
		output_max
	)

	if (
		inventory_changed
		or not is_equal_approx(previous_rate, operating_rate)
		or not is_equal_approx(
			previous_integral,
			controller_integral
		)
	):
		notify_control_changed()


func _get_bumpless_integral() -> float:
	if inventory_setpoint <= 0.0:
		return 0.0

	var normalized_error := (
		(inventory_setpoint - controlled_inventory_amount)
		/ maxf(inventory_setpoint, 1.0)
	)
	var output_max := minf(
		controller_output_max,
		manual_operating_rate
	)
	return clampf(
		manual_operating_rate - controller_kp * normalized_error,
		-output_max,
		output_max
	)


func notify_control_changed() -> void:
	if event_bus != null:
		event_bus.machine_control_changed.emit(self)


func notify_settings_changed() -> void:
	if event_bus != null:
		event_bus.machine_settings_changed.emit(self)


func _update_actual_operating_rate(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	var target_rate := operating_rate if enabled else 0.0
	var ramp_seconds := (
		ramp_up_seconds
		if target_rate > actual_operating_rate
		else ramp_down_seconds
	)
	var previous_rate := actual_operating_rate
	actual_operating_rate = move_toward(
		actual_operating_rate,
		target_rate,
		delta_seconds / ramp_seconds
	)

	if (
		not is_equal_approx(previous_rate, actual_operating_rate)
		and event_bus != null
	):
		event_bus.machine_performance_changed.emit(self)


func record_produced(resource_id: String, amount: float) -> void:
	if resource_id.is_empty() or amount <= 0.0:
		return

	_produced_in_window[resource_id] = (
		float(_produced_in_window.get(resource_id, 0.0))
		+ amount
	)


func record_consumed(resource_id: String, amount: float) -> void:
	if resource_id.is_empty() or amount <= 0.0:
		return

	_consumed_in_window[resource_id] = (
		float(_consumed_in_window.get(resource_id, 0.0))
		+ amount
	)


func advance_production_telemetry(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	_telemetry_elapsed += delta_seconds

	if _telemetry_elapsed < TELEMETRY_WINDOW_SECONDS:
		return

	var new_production_rates := _calculate_window_rates(
		_produced_in_window,
		_telemetry_elapsed
	)
	var new_consumption_rates := _calculate_window_rates(
		_consumed_in_window,
		_telemetry_elapsed
	)
	var changed := (
		new_production_rates != production_rates_per_second
		or new_consumption_rates != consumption_rates_per_second
	)

	production_rates_per_second = new_production_rates
	consumption_rates_per_second = new_consumption_rates
	_produced_in_window.clear()
	_consumed_in_window.clear()
	_telemetry_elapsed = 0.0

	if changed and event_bus != null:
		event_bus.machine_production_changed.emit(self)


func _calculate_window_rates(
	amounts: Dictionary,
	elapsed_seconds: float
) -> Dictionary:
	var rates: Dictionary = {}

	if elapsed_seconds <= 0.0:
		return rates

	for key: Variant in amounts.keys():
		var resource_id := str(key)
		var amount := float(amounts.get(resource_id, 0.0))

		if amount > 0.0:
			rates[resource_id] = amount / elapsed_seconds

	return rates


func set_graph_position(position: Vector2) -> void:
	graph_position = position
