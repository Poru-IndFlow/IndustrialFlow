extends Node


@export var factory_graph_path: NodePath = NodePath("../FactoryGraph")

var factory: Factory
var clock: SimulationClock


func _ready() -> void:
	factory = FactoryLoader.create_prototype_factory()

	var factory_graph := get_node_or_null(factory_graph_path)

	if factory_graph == null:
		push_error(
			"FactoryGraph node not found at: %s"
			% factory_graph_path
		)
		return

	if not factory_graph.has_method("bind_factory"):
		push_error(
			"FactoryGraph script does not provide bind_factory()."
		)
		return

	factory_graph.call("bind_factory", factory)

	clock = SimulationClock.new()
	clock.name = "SimulationClock"
	add_child(clock)
	clock.tick_advanced.connect(_on_tick_advanced)


func _on_tick_advanced(delta_seconds: float) -> void:
	if factory != null:
		factory.tick(delta_seconds)
