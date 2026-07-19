extends GraphEdit


var factory: Factory
var _node_by_machine_id: Dictionary = {}


func _ready() -> void:
	ResourceRegistry.load_all()

	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)

	right_disconnects = true
	show_arrange_button = true


func bind_factory(factory_model: Factory) -> void:
	factory = factory_model
	clear_connections()

	for child: Node in get_children():
		if child is GraphNode:
			child.queue_free()

	_node_by_machine_id.clear()

	_create_machine_node_from_model(
		factory.get_machine("log_supplier_1"),
		Vector2(100, 220)
	)

	_create_machine_node_from_model(
		factory.get_machine("chipper_1"),
		Vector2(430, 220)
	)

	_create_machine_node_from_model(
		factory.get_machine("chip_stockpile_1"),
		Vector2(780, 220)
	)

	_create_visual_connections()


func _create_visual_connections() -> void:
	if factory == null:
		return

	for connection: ConnectionModel in factory.connections:
		var from_node := _node_by_machine_id.get(
			connection.from_machine.instance_id
		) as GraphNode

		var to_node := _node_by_machine_id.get(
			connection.to_machine.instance_id
		) as GraphNode

		if from_node == null or to_node == null:
			continue

		var from_port := _find_output_port(
			from_node,
			connection.resource_id
		)

		var to_port := _find_input_port(
			to_node,
			connection.resource_id
		)

		if from_port < 0 or to_port < 0:
			continue

		connect_node(
			from_node.name,
			from_port,
			to_node.name,
			to_port
		)


func _on_connection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	if from_node == to_node:
		return

	if is_node_connected(from_node, from_port, to_node, to_port):
		return

	var from_graph_node := get_node_or_null(
		NodePath(str(from_node))
	) as GraphNode

	var to_graph_node := get_node_or_null(
		NodePath(str(to_node))
	) as GraphNode

	if from_graph_node == null or to_graph_node == null:
		return

	var from_resource := _get_output_resource_id(
		from_graph_node,
		from_port
	)

	var to_resource := _get_input_resource_id(
		to_graph_node,
		to_port
	)

	if from_resource.is_empty() or from_resource != to_resource:
		push_warning("Ports must carry the same resource.")
		return

	connect_node(from_node, from_port, to_node, to_port)


func _on_disconnection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)


func _create_machine_node_from_model(
	machine: MachineModel,
	graph_position: Vector2
) -> GraphNode:
	if machine == null:
		return null

	var graph_node := GraphNode.new()
	graph_node.name = StringName(machine.instance_id)
	graph_node.title = machine.display_name
	graph_node.position_offset = graph_position
	graph_node.resizable = false
	graph_node.custom_minimum_size = Vector2(240, 0)

	graph_node.set_meta("machine_id", machine.instance_id)
	graph_node.set_meta("machine_model", machine)

	add_child(graph_node)
	_node_by_machine_id[machine.instance_id] = graph_node

	_add_status_row(graph_node)

	for input_data: Dictionary in machine.recipe.inputs:
		_add_input_row(
			graph_node,
			str(input_data.get("resource", ""))
		)

	for output_data: Dictionary in machine.recipe.outputs:
		_add_output_row(
			graph_node,
			str(output_data.get("resource", ""))
		)

	_add_inventory_rows(graph_node, machine)

	machine.inventory_changed.connect(
		_on_machine_inventory_changed
	)
	machine.state_changed.connect(
		_on_machine_state_changed
	)

	_refresh_machine_node(machine)
	return graph_node


func _add_status_row(graph_node: GraphNode) -> void:
	var label := Label.new()
	label.name = "StatusLabel"
	label.custom_minimum_size = Vector2(210, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "Status: Idle"

	graph_node.add_child(label)

	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot_enabled_left(slot_index, false)
	graph_node.set_slot_enabled_right(slot_index, false)


func _add_input_row(
	graph_node: GraphNode,
	resource_id: String
) -> void:
	var label := Label.new()
	label.text = ResourceRegistry.get_display_name(resource_id)
	label.custom_minimum_size = Vector2(210, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.tooltip_text = resource_id
	label.set_meta("resource_id", resource_id)
	label.set_meta("port_direction", "input")

	graph_node.add_child(label)

	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot(
		slot_index,
		true,
		ResourceRegistry.get_port_type(resource_id),
		ResourceRegistry.get_colour(resource_id),
		false,
		0,
		Color.WHITE
	)


func _add_output_row(
	graph_node: GraphNode,
	resource_id: String
) -> void:
	var label := Label.new()
	label.text = ResourceRegistry.get_display_name(resource_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(210, 34)
	label.tooltip_text = resource_id
	label.set_meta("resource_id", resource_id)
	label.set_meta("port_direction", "output")

	graph_node.add_child(label)

	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot(
		slot_index,
		false,
		0,
		Color.WHITE,
		true,
		ResourceRegistry.get_port_type(resource_id),
		ResourceRegistry.get_colour(resource_id)
	)


func _add_inventory_rows(
	graph_node: GraphNode,
	machine: MachineModel
) -> void:
	var inventory_title := Label.new()
	inventory_title.text = "Inventory"
	inventory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_title.custom_minimum_size = Vector2(210, 28)
	graph_node.add_child(inventory_title)

	var title_slot := graph_node.get_child_count() - 1
	graph_node.set_slot_enabled_left(title_slot, false)
	graph_node.set_slot_enabled_right(title_slot, false)

	for resource_value: Variant in machine.inventory.capacities.keys():
		var resource_id := str(resource_value)
		var label := Label.new()
		label.name = StringName("Inventory_%s" % resource_id)
		label.custom_minimum_size = Vector2(210, 28)
		label.set_meta("inventory_resource_id", resource_id)

		graph_node.add_child(label)

		var slot_index := graph_node.get_child_count() - 1
		graph_node.set_slot_enabled_left(slot_index, false)
		graph_node.set_slot_enabled_right(slot_index, false)


func _refresh_machine_node(machine: MachineModel) -> void:
	var graph_node := _node_by_machine_id.get(
		machine.instance_id
	) as GraphNode

	if graph_node == null:
		return

	var status_label := graph_node.get_node_or_null(
		"StatusLabel"
	) as Label

	if status_label != null:
		status_label.text = "Status: %s" % _state_to_text(
			machine.state
		)

	for child: Node in graph_node.get_children():
		if not child is Label:
			continue

		if not child.has_meta("inventory_resource_id"):
			continue

		var resource_id := str(
			child.get_meta("inventory_resource_id")
		)

		var amount := machine.inventory.get_amount(resource_id)
		var capacity := machine.inventory.get_capacity(resource_id)
		var unit := ResourceRegistry.get_unit_name(resource_id)
		var capacity_text := "∞"

		if not is_inf(capacity):
			capacity_text = "%.1f" % capacity

		(child as Label).text = "%s: %.1f / %s %s" % [
			ResourceRegistry.get_display_name(resource_id),
			amount,
			capacity_text,
			unit
		]


func _on_machine_inventory_changed(
	machine: MachineModel
) -> void:
	_refresh_machine_node(machine)


func _on_machine_state_changed(
	machine: MachineModel
) -> void:
	_refresh_machine_node(machine)


func _state_to_text(state: MachineModel.State) -> String:
	match state:
		MachineModel.State.IDLE:
			return "Idle"
		MachineModel.State.RUNNING:
			return "Running"
		MachineModel.State.BLOCKED_INPUT:
			return "Waiting for input"
		MachineModel.State.BLOCKED_OUTPUT:
			return "Output blocked"
		MachineModel.State.DISABLED:
			return "Disabled"
		_:
			return "Unknown"


func _find_output_port(
	graph_node: GraphNode,
	resource_id: String
) -> int:
	var port_index := 0

	for child: Node in graph_node.get_children():
		if child.has_meta("port_direction"):
			if str(child.get_meta("port_direction")) == "output":
				if str(child.get_meta("resource_id")) == resource_id:
					return port_index
				port_index += 1

	return -1


func _find_input_port(
	graph_node: GraphNode,
	resource_id: String
) -> int:
	var port_index := 0

	for child: Node in graph_node.get_children():
		if child.has_meta("port_direction"):
			if str(child.get_meta("port_direction")) == "input":
				if str(child.get_meta("resource_id")) == resource_id:
					return port_index
				port_index += 1

	return -1


func _get_output_resource_id(
	graph_node: GraphNode,
	port_index: int
) -> String:
	var current_port := 0

	for child: Node in graph_node.get_children():
		if not child.has_meta("port_direction"):
			continue
		if str(child.get_meta("port_direction")) != "output":
			continue

		if current_port == port_index:
			return str(child.get_meta("resource_id"))

		current_port += 1

	return ""


func _get_input_resource_id(
	graph_node: GraphNode,
	port_index: int
) -> String:
	var current_port := 0

	for child: Node in graph_node.get_children():
		if not child.has_meta("port_direction"):
			continue
		if str(child.get_meta("port_direction")) != "input":
			continue

		if current_port == port_index:
			return str(child.get_meta("resource_id"))

		current_port += 1

	return ""
