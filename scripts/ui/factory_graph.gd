extends GraphEdit


signal machine_selected(machine: MachineModel)


var factory: FactoryModel


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		var old_callback := Callable(self, "_on_machine_added")
		if factory.event_bus.machine_added.is_connected(old_callback):
			factory.event_bus.machine_added.disconnect(old_callback)

	factory = new_factory
	clear_graph()

	if factory == null:
		return

	factory.event_bus.machine_added.connect(_on_machine_added)

	for value: Variant in factory.machines.values():
		add_machine_node(value as MachineModel)


func request_machine(definition_id: String) -> void:
	if factory == null:
		return

	var position := scroll_offset + size * 0.5
	var machine := factory.create_machine(definition_id, position)

	if machine != null:
		factory.add_machine(machine)


func clear_graph() -> void:
	for child: Node in get_children():
		if child is GraphNode:
			child.queue_free()


func add_machine_node(machine: MachineModel) -> void:
	var node := GraphNode.new()
	node.name = machine.instance_id
	node.title = machine.display_name
	node.position_offset = machine.graph_position
	node.custom_minimum_size = Vector2(190, 100)

	var state_label := Label.new()
	state_label.text = "State: %s" % _state_text(machine.state)
	node.add_child(state_label)

	node.node_selected.connect(
		_on_graph_node_selected.bind(machine)
	)
	node.position_offset_changed.connect(
		_on_node_position_changed.bind(node, machine)
	)

	add_child(node)


func _on_machine_added(machine: MachineModel) -> void:
	add_machine_node(machine)


func _on_graph_node_selected(machine: MachineModel) -> void:
	machine_selected.emit(machine)


func _on_node_position_changed(
	node: GraphNode,
	machine: MachineModel
) -> void:
	machine.set_graph_position(node.position_offset)


func _state_text(state: MachineModel.State) -> String:
	return MachineModel.State.keys()[state].capitalize()