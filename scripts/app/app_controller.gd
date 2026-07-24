extends Node


@onready var factory_graph := get_node(
	"../RootVBox/Workspace/FactoryGraph"
)

var event_bus: EventBus
var factory: FactoryModel
var clock: SimulationClock


func _ready() -> void:
	event_bus = EventBus.new()
	set_factory(PrototypeFactoryBuilder.build(event_bus))

	clock = SimulationClock.new()
	clock.name = "SimulationClock"
	add_child(clock)
	clock.tick_advanced.connect(_on_tick_advanced)


func set_factory(new_factory: FactoryModel) -> void:
	factory = new_factory
	factory_graph.bind_factory(factory)


func _on_tick_advanced(delta_seconds: float) -> void:
	if factory != null:
		factory.tick(delta_seconds)