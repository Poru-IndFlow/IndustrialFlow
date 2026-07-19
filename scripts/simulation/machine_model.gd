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
var cycle_progress := 0.0
var graph_position := Vector2.ZERO

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


func set_graph_position(position: Vector2) -> void:
	graph_position = position
