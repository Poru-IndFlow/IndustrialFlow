class_name MachineModel
extends RefCounted

enum State {
	IDLE,
	RUNNING,
	BLOCKED_INPUT,
	BLOCKED_OUTPUT,
	DISABLED,
	MAINTENANCE,
	FAILED
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
var breakdown_chance_curve: Array[Dictionary] = []
var breakdown_warning_chance_per_hour := 0.05
var breakdown_critical_chance_per_hour := 0.2
var idle_power_ratio := 0.15
var power_demand := 0.0
var condition := 1.0
var operating_hours := 0.0
var wear_per_operating_hour := 0.0
var minimum_condition_efficiency := 0.65
var maximum_wear_power_multiplier := 1.5
var maintenance_warning_condition := 0.75
var maintenance_critical_condition := 0.4
var maintenance_cost := 0.0
var maintenance_duration_seconds := 0.0
var maintenance_remaining_seconds := 0.0
var maintenance_total_seconds := 0.0
var emergency_repair_cost := 0.0
var emergency_repair_duration_seconds := 0.0
var maintenance_is_emergency := false
var maintenance_policy_enabled := false
var maintenance_policy_condition := 0.75
var maintenance_policy_cash_reserve := 0.0
var preventive_maintenance_count := 0
var failure_count := 0
var emergency_repair_count := 0
var maintenance_spend := 0.0
var maintenance_downtime_seconds := 0.0
var failed_downtime_seconds := 0.0
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
var batch_active := false
var batch_outputs: Array[Dictionary] = []
var graph_position := Vector2.ZERO
var production_rates_per_second: Dictionary = {}
var consumption_rates_per_second: Dictionary = {}
var installed_upgrades: Array[String] = []
var _produced_in_window: Dictionary = {}
var _consumed_in_window: Dictionary = {}
var _economic_production: Dictionary = {}
var _economic_consumption: Dictionary = {}
var _telemetry_elapsed := 0.0
var _last_condition_notification := 1.0
var _last_hours_notification := 0.0

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
	machine.breakdown_chance_curve = _load_breakdown_chance_curve(
		machine_definition
	)
	machine.breakdown_warning_chance_per_hour = clampf(
		float(
			machine_definition.get(
				"breakdown_warning_chance_per_hour",
				0.05
			)
		),
		0.0,
		1.0
	)
	machine.breakdown_critical_chance_per_hour = clampf(
		float(
			machine_definition.get(
				"breakdown_critical_chance_per_hour",
				0.2
			)
		),
		machine.breakdown_warning_chance_per_hour,
		1.0
	)
	machine.idle_power_ratio = clampf(
		float(machine_definition.get("idle_power_ratio", 0.15)),
		0.0,
		1.0
	)
	machine.wear_per_operating_hour = maxf(
		0.0,
		float(
			machine_definition.get(
				"wear_per_operating_hour",
				0.0
			)
		)
	)
	machine.minimum_condition_efficiency = clampf(
		float(
			machine_definition.get(
				"minimum_condition_efficiency",
				0.65
			)
		),
		0.0,
		1.0
	)
	machine.maximum_wear_power_multiplier = maxf(
		1.0,
		float(
			machine_definition.get(
				"maximum_wear_power_multiplier",
				1.5
			)
		)
	)
	machine.maintenance_warning_condition = clampf(
		float(
			machine_definition.get(
				"maintenance_warning_condition",
				0.75
			)
		),
		0.0,
		1.0
	)
	machine.maintenance_critical_condition = clampf(
		float(
			machine_definition.get(
				"maintenance_critical_condition",
				0.4
			)
		),
		0.0,
		machine.maintenance_warning_condition
	)
	machine.maintenance_policy_condition = machine.maintenance_warning_condition
	machine.maintenance_cost = maxf(
		0.0,
		float(machine_definition.get("maintenance_cost", 0.0))
	)
	machine.maintenance_duration_seconds = maxf(
		0.1,
		float(
			machine_definition.get(
				"maintenance_duration_seconds",
				30.0
			)
		)
	)
	machine.emergency_repair_cost = maxf(
		machine.maintenance_cost,
		float(
			machine_definition.get(
				"emergency_repair_cost",
				machine.maintenance_cost * 2.0
			)
		)
	)
	machine.emergency_repair_duration_seconds = maxf(
		machine.maintenance_duration_seconds,
		float(
			machine_definition.get(
				"emergency_repair_duration_seconds",
				machine.maintenance_duration_seconds * 2.0
			)
		)
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


static func _load_breakdown_chance_curve(
	machine_definition: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = machine_definition.get(
		"breakdown_chance_curve",
		[]
	)

	for value: Variant in entries:
		if not value is Dictionary:
			continue

		var entry := value as Dictionary
		result.append({
			"condition": clampf(
				float(entry.get("condition", 1.0)),
				0.0,
				1.0
			),
			"chance": clampf(
				float(entry.get("chance", 0.0)),
				0.0,
				1.0
			)
		})

	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left["condition"]) < float(right["condition"])
	)
	return result


func tick(delta_seconds: float) -> void:
	if is_under_maintenance():
		actual_operating_rate = 0.0
		set_state(State.MAINTENANCE)
		_advance_maintenance(delta_seconds)
		_update_power_demand()
		return

	if is_failed():
		actual_operating_rate = 0.0
		set_state(State.FAILED)
		_advance_failed_downtime(delta_seconds)
		_update_power_demand()
		return

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
	_roll_for_breakdown(delta_seconds)
	_advance_wear(delta_seconds)
	_update_power_demand()


func get_effective_production_rate() -> float:
	return (
		_get_base_production_rate()
		* get_condition_efficiency()
		* _get_upgrade_effect_multiplier("output_multiplier")
	)


func _get_base_production_rate() -> float:
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
	return (
		_get_base_power_demand()
		* get_condition_power_multiplier()
		* _get_upgrade_effect_multiplier("power_multiplier")
	)


func has_upgrade(research_id: String) -> bool:
	return installed_upgrades.has(research_id)


func install_upgrade(research_id: String) -> bool:
	if research_id.is_empty() or has_upgrade(research_id):
		return false

	var definition := ResearchRegistry.get_definition(research_id)

	if (
		definition.is_empty()
		or str(definition.get("target_machine_id", ""))
		!= definition_id
	):
		return false

	installed_upgrades.append(research_id)
	_update_power_demand()

	if event_bus != null:
		event_bus.machine_upgrades_changed.emit(self)
		event_bus.machine_performance_changed.emit(self)

	return true


func restore_installed_upgrades(values: Array) -> void:
	installed_upgrades.clear()

	for value: Variant in values:
		var research_id := str(value)
		var definition := ResearchRegistry.get_definition(research_id)

		if (
			research_id.is_empty()
			or definition.is_empty()
			or str(definition.get("target_machine_id", ""))
			!= definition_id
			or installed_upgrades.has(research_id)
		):
			continue

		installed_upgrades.append(research_id)


func _get_upgrade_effect_multiplier(effect_id: String) -> float:
	var multiplier := 1.0

	for research_id: String in installed_upgrades:
		var definition := ResearchRegistry.get_definition(research_id)
		var effects: Dictionary = definition.get("effects", {})
		multiplier *= maxf(
			0.0,
			float(effects.get(effect_id, 1.0))
		)

	return multiplier


func _get_base_power_demand() -> float:
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


func supports_maintenance() -> bool:
	return wear_per_operating_hour > 0.0


func get_condition_efficiency() -> float:
	return lerpf(
		minimum_condition_efficiency,
		1.0,
		condition
	)


func get_condition_power_multiplier() -> float:
	return lerpf(
		maximum_wear_power_multiplier,
		1.0,
		condition
	)


func is_maintenance_due() -> bool:
	return (
		supports_maintenance()
		and condition <= maintenance_warning_condition
	)


func is_maintenance_critical() -> bool:
	return (
		supports_maintenance()
		and condition <= maintenance_critical_condition
	)


func is_under_maintenance() -> bool:
	return maintenance_remaining_seconds > 0.0


func is_failed() -> bool:
	return condition <= 0.0 and not is_under_maintenance()


func get_current_maintenance_cost() -> float:
	return (
		emergency_repair_cost
		if maintenance_is_emergency or is_failed()
		else maintenance_cost
	)


func get_current_maintenance_duration() -> float:
	return (
		emergency_repair_duration_seconds
		if maintenance_is_emergency or is_failed()
		else maintenance_duration_seconds
	)


func can_start_maintenance() -> bool:
	return (
		supports_maintenance()
		and not is_under_maintenance()
		and condition < 0.999
	)


func set_maintenance_policy_enabled(value: bool) -> void:
	if maintenance_policy_enabled == value:
		return

	maintenance_policy_enabled = value
	notify_settings_changed()


func set_maintenance_policy_condition(value: float) -> void:
	var new_value := clampf(value, 0.01, 0.99)

	if is_equal_approx(maintenance_policy_condition, new_value):
		return

	maintenance_policy_condition = new_value
	notify_settings_changed()


func set_maintenance_policy_cash_reserve(value: float) -> void:
	var new_value := maxf(value, 0.0)

	if is_equal_approx(maintenance_policy_cash_reserve, new_value):
		return

	maintenance_policy_cash_reserve = new_value
	notify_settings_changed()


func start_maintenance() -> bool:
	if not can_start_maintenance():
		return false

	maintenance_is_emergency = is_failed()
	maintenance_total_seconds = get_current_maintenance_duration()
	maintenance_remaining_seconds = maintenance_total_seconds
	maintenance_spend += get_current_maintenance_cost()

	if maintenance_is_emergency:
		emergency_repair_count += 1
	else:
		preventive_maintenance_count += 1

	actual_operating_rate = 0.0
	set_state(State.MAINTENANCE)
	_update_power_demand()
	_notify_maintenance_changed()
	return true


func restore_maintenance(
	remaining_seconds: float,
	total_seconds: float,
	is_emergency: bool = false
) -> void:
	maintenance_total_seconds = maxf(total_seconds, 0.0)
	maintenance_remaining_seconds = clampf(
		remaining_seconds,
		0.0,
		maintenance_total_seconds
	)
	maintenance_is_emergency = is_emergency and is_under_maintenance()

	if is_under_maintenance():
		actual_operating_rate = 0.0
		state = State.MAINTENANCE


func get_maintenance_progress() -> float:
	if maintenance_total_seconds <= 0.0:
		return 0.0

	return clampf(
		1.0
		- maintenance_remaining_seconds
		/ maintenance_total_seconds,
		0.0,
		1.0
	)


func _advance_maintenance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or not is_under_maintenance():
		return

	var elapsed := minf(delta_seconds, maintenance_remaining_seconds)
	maintenance_downtime_seconds += elapsed
	maintenance_remaining_seconds = maxf(
		0.0,
		maintenance_remaining_seconds - delta_seconds
	)

	if is_under_maintenance():
		_notify_maintenance_changed()
		return

	condition = 1.0
	_last_condition_notification = condition
	maintenance_is_emergency = false
	set_state(State.DISABLED if not enabled else State.IDLE)
	notify_condition_changed()
	_notify_maintenance_changed()


func _advance_failed_downtime(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	var previous_whole_seconds := floori(failed_downtime_seconds)
	failed_downtime_seconds += delta_seconds

	if floori(failed_downtime_seconds) != previous_whole_seconds:
		_notify_maintenance_changed()


func get_total_downtime_seconds() -> float:
	return maintenance_downtime_seconds + failed_downtime_seconds


func get_breakdown_chance_per_hour() -> float:
	if breakdown_chance_curve.is_empty():
		return 0.0

	var first := breakdown_chance_curve[0]

	if condition <= float(first["condition"]):
		return float(first["chance"])

	for index: int in range(1, breakdown_chance_curve.size()):
		var left := breakdown_chance_curve[index - 1]
		var right := breakdown_chance_curve[index]
		var right_condition := float(right["condition"])

		if condition <= right_condition:
			var left_condition := float(left["condition"])
			var span := right_condition - left_condition
			var weight := (
				(condition - left_condition) / span
				if span > 0.0
				else 0.0
			)
			return lerpf(
				float(left["chance"]),
				float(right["chance"]),
				weight
			)

	return float(breakdown_chance_curve[-1]["chance"])


func is_breakdown_risk_warning() -> bool:
	return (
		not is_failed()
		and not is_under_maintenance()
		and get_breakdown_chance_per_hour()
		>= breakdown_warning_chance_per_hour
	)


func is_breakdown_risk_critical() -> bool:
	return (
		not is_failed()
		and not is_under_maintenance()
		and get_breakdown_chance_per_hour()
		>= breakdown_critical_chance_per_hour
	)


func _roll_for_breakdown(delta_seconds: float) -> void:
	if (
		delta_seconds <= 0.0
		or state != State.RUNNING
		or not supports_maintenance()
	):
		return

	var hourly_chance := get_breakdown_chance_per_hour()

	if hourly_chance <= 0.0:
		return

	var exposure_hours := (
		delta_seconds * maxf(actual_operating_rate, 0.0) / 3600.0
	)
	var tick_chance := 1.0 - pow(1.0 - hourly_chance, exposure_hours)

	if randf() < tick_chance:
		_fail_machine()


func _fail_machine() -> void:
	if state == State.FAILED:
		return

	condition = 0.0
	actual_operating_rate = 0.0
	failure_count += 1
	_last_condition_notification = condition
	set_state(State.FAILED)
	notify_condition_changed()


func _notify_maintenance_changed() -> void:
	if event_bus != null:
		event_bus.machine_maintenance_changed.emit(self)


func _advance_wear(delta_seconds: float) -> void:
	if (
		delta_seconds <= 0.0
		or state != State.RUNNING
		or not supports_maintenance()
	):
		return

	var load_factor := maxf(actual_operating_rate, 0.0)
	var elapsed_hours := (
		delta_seconds * load_factor / 3600.0
	)
	operating_hours += elapsed_hours
	condition = clampf(
		condition
		- wear_per_operating_hour
		* _get_upgrade_effect_multiplier("wear_multiplier")
		* elapsed_hours,
		0.0,
		1.0
	)

	if condition <= 0.0:
		_fail_machine()

	if (
		absf(condition - _last_condition_notification) >= 0.0025
		or operating_hours - _last_hours_notification >= 0.01
	):
		_last_condition_notification = condition
		_last_hours_notification = operating_hours
		notify_condition_changed()


func notify_condition_changed() -> void:
	if event_bus != null:
		event_bus.machine_condition_changed.emit(self)


func get_power_mode() -> String:
	if is_under_maintenance():
		return "Maintenance"

	if not enabled or actual_operating_rate <= 0.0:
		return "Off"

	return "Active" if state == State.RUNNING else "Idle at speed"


func _update_power_demand() -> void:
	var active_demand := get_active_power_demand()
	var new_demand := 0.0

	if (
		enabled
		and not is_under_maintenance()
		and actual_operating_rate > 0.0
	):
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
	_economic_production[resource_id] = (
		float(_economic_production.get(resource_id, 0.0))
		+ amount
	)


func record_consumed(resource_id: String, amount: float) -> void:
	if resource_id.is_empty() or amount <= 0.0:
		return

	_consumed_in_window[resource_id] = (
		float(_consumed_in_window.get(resource_id, 0.0))
		+ amount
	)
	_economic_consumption[resource_id] = (
		float(_economic_consumption.get(resource_id, 0.0))
		+ amount
	)


func drain_economic_production() -> Dictionary:
	var result: Dictionary = _economic_production.duplicate(true)
	_economic_production.clear()
	return result


func drain_economic_consumption() -> Dictionary:
	var result: Dictionary = _economic_consumption.duplicate(true)
	_economic_consumption.clear()
	return result


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
