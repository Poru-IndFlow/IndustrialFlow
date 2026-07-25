extends Node


@onready var factory_graph := get_node(
	"../RootVBox/Workspace/FactoryGraph"
)

@onready var machine_palette := get_node(
	"../RootVBox/Workspace/MachinePalette"
)

@onready var machine_inspector := get_node(
	"../RootVBox/Workspace/MachineInspector"
)

var event_bus: EventBus
var factory: FactoryModel
var clock: SimulationClock


func _ready() -> void:
	machine_palette.machine_requested.connect(
	_on_machine_requested
)

	factory_graph.machine_selected.connect(
	_on_machine_selected
)

	event_bus = EventBus.new()
	set_factory(PrototypeFactoryBuilder.build(event_bus))

	clock = SimulationClock.new()
	clock.name = "SimulationClock"
	add_child(clock)
	clock.tick_advanced.connect(_on_tick_advanced)


func set_factory(new_factory: FactoryModel) -> void:
	factory = new_factory
	factory_graph.bind_factory(factory)
	machine_inspector.bind_factory(factory)


func _on_tick_advanced(delta_seconds: float) -> void:
	if factory != null:
		factory.tick(delta_seconds)

func _on_machine_requested(definition_id: String) -> void:
	factory_graph.request_machine(definition_id)

func _on_machine_selected(machine: MachineModel) -> void:
	machine_inspector.show_machine(machine)