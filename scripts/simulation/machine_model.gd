class_name MachineModel
extends RefCounted

enum State {
	IDLE,
	RUNNING,
	BLOCKED_INPUT,
	BLOCKED_OUTPUT,
	DISABLED
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

func tick(delta_seconds: float) -> void:
	if not enabled:
		set_state(State.DISABLED)
		return

	if operating_rate <= 0.0:
		set_state(State.IDLE)
		return

	behaviour.tick(self, delta_seconds)

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
	elif operating_rate <= 0.0:
		set_state(State.IDLE)

	notify_settings_changed()


func set_operating_rate(value: float) -> void:
	var clamped_rate := clampf(value, 0.0, 1.5)

	if is_equal_approx(operating_rate, clamped_rate):
		return

	operating_rate = clamped_rate

	if enabled and operating_rate <= 0.0:
		set_state(State.IDLE)

	notify_settings_changed()


func notify_settings_changed() -> void:
	if event_bus != null:
		event_bus.machine_settings_changed.emit(self)


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
