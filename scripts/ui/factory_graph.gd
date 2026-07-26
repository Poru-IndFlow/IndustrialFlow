extends GraphEdit


signal machine_selected(machine: MachineModel)
signal selection_changed(selected_count: int)
signal machines_deleted(deleted_count: int)


var factory: FactoryModel
var refresh_manager: RefreshManager
var input_ports: Dictionary = {}
var output_ports: Dictionary = {}
var input_port_resources: Dictionary = {}
var output_port_resources: Dictionary = {}
var state_labels: Dictionary = {}
var resource_labels: Dictionary = {}
var dirty_machines: Dictionary = {}
var selection_notification_pending := false


func _ready() -> void:
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	right_disconnects = true


func bind_refresh_manager(manager: RefreshManager) -> void:
	refresh_manager = manager


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		_disconnect_factory_signals()

	factory = new_factory
	clear_graph()

	if factory == null:
		return

	factory.event_bus.machine_added.connect(_on_machine_added)
	factory.event_bus.machine_removed.connect(_on_machine_removed)
	factory.event_bus.machine_state_changed.connect(
		_on_machine_state_changed
	)
	factory.event_bus.machine_inventory_changed.connect(
		_on_machine_inventory_changed
	)
	factory.event_bus.connection_added.connect(_on_connection_added)
	factory.event_bus.connection_removed.connect(_on_connection_removed)

	for value: Variant in factory.machines.values():
		add_machine_node(value as MachineModel)

	_rebuild_connections()


func request_machine(definition_id: String) -> void:
	if factory == null:
		return

	var position := scroll_offset + size * 0.5
	var machine := factory.create_machine(definition_id, position)

	if machine != null:
		factory.add_machine(machine)


func delete_selected_machines() -> int:
	return _delete_machine_ids(_get_selected_machine_ids())


func clear_graph() -> void:
	clear_connections()
	input_ports.clear()
	output_ports.clear()
	input_port_resources.clear()
	output_port_resources.clear()
	state_labels.clear()
	resource_labels.clear()
	dirty_machines.clear()

	for child: Node in get_children():
		if child is GraphNode:
			child.queue_free()

	selection_changed.emit(0)


func add_machine_node(machine: MachineModel) -> void:
	var node := GraphNode.new()
	node.name = machine.instance_id
	node.title = machine.display_name
	node.position_offset = machine.graph_position
	node.custom_minimum_size = Vector2(210, 100)

	var state_label := Label.new()
	state_label.text = "State: %s" % _state_text(machine.state)
	node.add_child(state_label)
	state_labels[machine.instance_id] = state_label

	var resources := _get_machine_resources(machine)
	var input_port := 0
	var output_port := 0
	var row := 1

	for resource_id: String in resources:
		var accepts := _has_resource(
			machine.definition.get("inputs", []),
			resource_id
		)
		var produces := _has_resource(
			machine.definition.get("outputs", []),
			resource_id
		)

		var resource_label := Label.new()
		resource_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)
		node.add_child(resource_label)

		resource_labels[_port_key(
			machine.instance_id,
			resource_id
		)] = resource_label

		_update_resource_label(
			machine,
			resource_id,
			resource_label
		)

		var color := _resource_color(resource_id)
		node.set_slot(
			row,
			accepts,
			0,
			color,
			produces,
			0,
			color
		)

		if accepts:
			input_ports[_port_key(
				machine.instance_id,
				resource_id
			)] = input_port

			input_port_resources[_indexed_port_key(
				machine.instance_id,
				input_port
			)] = resource_id

			input_port += 1

		if produces:
			output_ports[_port_key(
				machine.instance_id,
				resource_id
			)] = output_port

			output_port_resources[_indexed_port_key(
				machine.instance_id,
				output_port
			)] = resource_id

			output_port += 1

		row += 1

	node.node_selected.connect(
		_on_graph_node_selected.bind(machine)
	)
	node.node_deselected.connect(
		_on_graph_node_deselected
	)
	node.position_offset_changed.connect(
		_on_node_position_changed.bind(node, machine)
	)

	add_child(node)


func _get_machine_resources(machine: MachineModel) -> Array[String]:
	var result: Array[String] = []

	for section_name: String in ["inputs", "outputs"]:
		var entries: Array = machine.definition.get(section_name, [])

		for entry: Variant in entries:
			var resource_id := str(
				(entry as Dictionary).get("resource", "")
			)

			if not resource_id.is_empty() and not result.has(resource_id):
				result.append(resource_id)

	result.sort()
	return result


func _has_resource(entries: Array, resource_id: String) -> bool:
	for entry: Variant in entries:
		if str((entry as Dictionary).get("resource", "")) == resource_id:
			return true

	return false


func _update_resource_label(
	machine: MachineModel,
	resource_id: String,
	label: Label
) -> void:
	var display_name := resource_id.replace("_", " ").capitalize()
	var amount := machine.inventory.get_amount(resource_id)

	label.text = "%s: %.1f" % [display_name, amount]


func _update_machine_inventory(machine: MachineModel) -> void:
	for resource_id: String in _get_machine_resources(machine):
		var key := _port_key(machine.instance_id, resource_id)
		var resource_label := resource_labels.get(key) as Label

		if resource_label != null:
			_update_resource_label(
				machine,
				resource_id,
				resource_label
			)


func _rebuild_connections() -> void:
	clear_connections()

	if factory == null:
		return

	for connection: ConnectionModel in factory.connections:
		_draw_connection(connection)


func _draw_connection(connection: ConnectionModel) -> void:
	var from_key := _port_key(
		connection.from_machine.instance_id,
		connection.resource_id
	)
	var to_key := _port_key(
		connection.to_machine.instance_id,
		connection.resource_id
	)

	if not output_ports.has(from_key) or not input_ports.has(to_key):
		return

	connect_node(
		connection.from_machine.instance_id,
		int(output_ports[from_key]),
		connection.to_machine.instance_id,
		int(input_ports[to_key])
	)


func _port_key(machine_id: String, resource_id: String) -> String:
	return "%s:%s" % [machine_id, resource_id]


func _indexed_port_key(machine_id: String, port: int) -> String:
	return "%s:%d" % [machine_id, port]


func _resource_color(resource_id: String) -> Color:
	match resource_id:
		"logs":
			return Color(0.55, 0.32, 0.16)
		"wood_chips":
			return Color(0.86, 0.67, 0.30)
		_:
			return Color(0.65, 0.75, 0.85)


func _disconnect_factory_signals() -> void:
	var machine_callback := Callable(self, "_on_machine_added")
	var machine_removed_callback := Callable(
		self,
		"_on_machine_removed"
	)
	var state_callback := Callable(
		self,
		"_on_machine_state_changed"
	)
	var inventory_callback := Callable(
		self,
		"_on_machine_inventory_changed"
	)
	var added_callback := Callable(self, "_on_connection_added")
	var removed_callback := Callable(
		self,
		"_on_connection_removed"
	)

	if factory.event_bus.machine_added.is_connected(
		machine_callback
	):
		factory.event_bus.machine_added.disconnect(
			machine_callback
		)

	if factory.event_bus.machine_removed.is_connected(
		machine_removed_callback
	):
		factory.event_bus.machine_removed.disconnect(
			machine_removed_callback
		)

	if factory.event_bus.machine_state_changed.is_connected(
		state_callback
	):
		factory.event_bus.machine_state_changed.disconnect(
			state_callback
		)

	if factory.event_bus.machine_inventory_changed.is_connected(
		inventory_callback
	):
		factory.event_bus.machine_inventory_changed.disconnect(
			inventory_callback
		)

	if factory.event_bus.connection_added.is_connected(
		added_callback
	):
		factory.event_bus.connection_added.disconnect(
			added_callback
		)

	if factory.event_bus.connection_removed.is_connected(
		removed_callback
	):
		factory.event_bus.connection_removed.disconnect(
			removed_callback
		)


func _on_connection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	if factory == null:
		return

	var from_id := str(from_node)
	var to_id := str(to_node)

	if from_id == to_id:
		return

	var output_key := _indexed_port_key(from_id, from_port)
	var input_key := _indexed_port_key(to_id, to_port)

	if not output_port_resources.has(output_key):
		return

	if not input_port_resources.has(input_key):
		return

	var output_resource := str(output_port_resources[output_key])
	var input_resource := str(input_port_resources[input_key])

	if output_resource != input_resource:
		return

	var from_machine := factory.get_machine(from_id)
	var to_machine := factory.get_machine(to_id)

	if from_machine == null or to_machine == null:
		return

	factory.add_connection(
		ConnectionModel.new(
			from_machine,
			to_machine,
			output_resource,
			1.0
		)
	)


func _on_disconnection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	if factory == null:
		return

	var from_id := str(from_node)
	var to_id := str(to_node)
	var output_key := _indexed_port_key(from_id, from_port)
	var input_key := _indexed_port_key(to_id, to_port)

	if not output_port_resources.has(output_key):
		return

	if not input_port_resources.has(input_key):
		return

	var output_resource := str(output_port_resources[output_key])
	var input_resource := str(input_port_resources[input_key])

	if output_resource != input_resource:
		return

	var connection := factory.find_connection(
		from_id,
		to_id,
		output_resource
	)

	if connection != null:
		factory.remove_connection(connection)


func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	_delete_machine_ids(nodes)


func _delete_machine_ids(nodes: Array[StringName]) -> int:
	if factory == null:
		return 0

	var deleted_count := 0
	for node_name: StringName in nodes:
		if factory.remove_machine(str(node_name)):
			deleted_count += 1

	if deleted_count > 0:
		machine_selected.emit(null)
		machines_deleted.emit(deleted_count)
		_request_selection_notification()

	return deleted_count


func _get_selected_machine_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for child: Node in get_children():
		var graph_node := child as GraphNode

		if graph_node != null and graph_node.selected:
			result.append(graph_node.name)

	return result


func _on_machine_removed(machine_id: String) -> void:
	var graph_node := get_node_or_null(
		NodePath(machine_id)
	) as GraphNode

	if graph_node != null:
		graph_node.queue_free()

	_remove_machine_port_data(input_ports, machine_id)
	_remove_machine_port_data(output_ports, machine_id)
	_remove_machine_port_data(input_port_resources, machine_id)
	_remove_machine_port_data(output_port_resources, machine_id)
	_remove_machine_port_data(resource_labels, machine_id)
	state_labels.erase(machine_id)

	_rebuild_connections()


func _remove_machine_port_data(
	port_data: Dictionary,
	machine_id: String
) -> void:
	var prefix := "%s:" % machine_id

	for key: Variant in port_data.keys():
		if str(key).begins_with(prefix):
			port_data.erase(key)


func _on_machine_state_changed(machine: MachineModel) -> void:
	if machine == null:
		return

	_request_machine_refresh(machine)


func _on_machine_inventory_changed(machine: MachineModel) -> void:
	if machine != null:
		_request_machine_refresh(machine)


func _request_machine_refresh(machine: MachineModel) -> void:
	dirty_machines[machine.instance_id] = machine

	if refresh_manager == null:
		_flush_machine_refreshes()
		return

	refresh_manager.request_refresh(
		&"factory_graph_machines",
		_flush_machine_refreshes
	)


func _flush_machine_refreshes() -> void:
	var machines_to_refresh := dirty_machines.values()
	dirty_machines.clear()

	for value: Variant in machines_to_refresh:
		var machine := value as MachineModel

		if machine == null:
			continue

		var state_label := state_labels.get(
			machine.instance_id
		) as Label

		if state_label != null:
			state_label.text = "State: %s" % _state_text(
				machine.state
			)

		_update_machine_inventory(machine)


func _on_machine_added(machine: MachineModel) -> void:
	add_machine_node(machine)


func _on_connection_added(connection: ConnectionModel) -> void:
	_draw_connection(connection)


func _on_connection_removed(_connection: ConnectionModel) -> void:
	_rebuild_connections()


func _on_graph_node_selected(machine: MachineModel) -> void:
	machine_selected.emit(machine)
	_request_selection_notification()


func _on_graph_node_deselected() -> void:
	_request_selection_notification()


func _request_selection_notification() -> void:
	if selection_notification_pending:
		return

	selection_notification_pending = true
	call_deferred("_emit_selection_changed")


func _emit_selection_changed() -> void:
	selection_notification_pending = false
	selection_changed.emit(_get_selected_machine_ids().size())


func _on_node_position_changed(
	node: GraphNode,
	machine: MachineModel
) -> void:
	machine.set_graph_position(node.position_offset)


func _state_text(state: MachineModel.State) -> String:
	return MachineModel.State.keys()[state].capitalize()
