class_name ScadaWorkspace
extends VBoxContainer


signal machine_requested(machine: MachineModel)

var factory: FactoryModel
var input_ports: Dictionary = {}
var output_ports: Dictionary = {}
var state_labels: Dictionary = {}
var metrics_labels: Dictionary = {}
var resource_labels: Dictionary = {}

@onready var build_label := %BuildLabel as Label
@onready var system_status := %SystemStatus as Label
@onready var fit_plant_button := %FitPlantButton as Button
@onready var process_graph := %ProcessGraph as GraphEdit


func _ready() -> void:
	build_label.text = BuildInfo.get_display_string()
	fit_plant_button.pressed.connect(_fit_plant)
	_update_system_status()


func bind_factory(new_factory: FactoryModel) -> void:
	_disconnect_factory_events()
	factory = new_factory
	_clear_graph()

	if factory == null:
		_update_system_status()
		return

	_connect_factory_events()

	for value: Variant in factory.machines.values():
		_add_machine_node(value as MachineModel)

	_rebuild_connections()
	_update_system_status()
	call_deferred("_fit_plant")


func _connect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	factory.event_bus.machine_added.connect(_on_machine_added)
	factory.event_bus.machine_removed.connect(_on_machine_removed)
	factory.event_bus.machine_state_changed.connect(_on_machine_changed)
	factory.event_bus.machine_inventory_changed.connect(_on_machine_changed)
	factory.event_bus.machine_performance_changed.connect(_on_machine_changed)
	factory.event_bus.machine_power_changed.connect(_on_machine_changed)
	factory.event_bus.machine_condition_changed.connect(_on_machine_changed)
	factory.event_bus.machine_maintenance_changed.connect(_on_machine_changed)
	factory.event_bus.connection_added.connect(_on_connection_added)
	factory.event_bus.connection_removed.connect(_on_connection_removed)
	factory.event_bus.connection_flow_changed.connect(_on_connection_changed)
	factory.event_bus.connection_settings_changed.connect(_on_connection_changed)


func _disconnect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	_disconnect_signal(
		factory.event_bus.machine_added,
		Callable(self, "_on_machine_added")
	)
	_disconnect_signal(
		factory.event_bus.machine_removed,
		Callable(self, "_on_machine_removed")
	)

	var machine_callback := Callable(self, "_on_machine_changed")
	var machine_signals: Array[Signal] = [
		factory.event_bus.machine_state_changed,
		factory.event_bus.machine_inventory_changed,
		factory.event_bus.machine_performance_changed,
		factory.event_bus.machine_power_changed,
		factory.event_bus.machine_condition_changed,
		factory.event_bus.machine_maintenance_changed
	]

	for factory_signal: Signal in machine_signals:
		_disconnect_signal(factory_signal, machine_callback)

	_disconnect_signal(
		factory.event_bus.connection_added,
		Callable(self, "_on_connection_added")
	)
	_disconnect_signal(
		factory.event_bus.connection_removed,
		Callable(self, "_on_connection_removed")
	)

	var connection_callback := Callable(self, "_on_connection_changed")
	_disconnect_signal(
		factory.event_bus.connection_flow_changed,
		connection_callback
	)
	_disconnect_signal(
		factory.event_bus.connection_settings_changed,
		connection_callback
	)


func _disconnect_signal(
	factory_signal: Signal,
	callback: Callable
) -> void:
	if factory_signal.is_connected(callback):
		factory_signal.disconnect(callback)


func _clear_graph() -> void:
	if process_graph == null:
		return

	process_graph.clear_connections()
	input_ports.clear()
	output_ports.clear()
	state_labels.clear()
	metrics_labels.clear()
	resource_labels.clear()

	for child: Node in process_graph.get_children():
		if child is GraphNode:
			process_graph.remove_child(child)
			child.queue_free()


func _add_machine_node(machine: MachineModel) -> void:
	if machine == null:
		return

	var node := GraphNode.new()
	node.name = machine.instance_id
	node.title = machine.display_name
	node.position_offset = machine.graph_position
	node.custom_minimum_size = Vector2(245, 145)
	node.draggable = false

	var state_label := Label.new()
	state_label.custom_minimum_size = Vector2(215, 0)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(state_label)
	state_labels[machine.instance_id] = state_label

	var metrics_label := Label.new()
	metrics_label.custom_minimum_size = Vector2(215, 0)
	metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics_label.clip_text = true
	metrics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(metrics_label)
	metrics_labels[machine.instance_id] = metrics_label

	var resources := _get_machine_resources(machine)
	var input_port := 0
	var output_port := 0
	var row := 2

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
		resource_label.custom_minimum_size = Vector2(215, 0)
		resource_label.clip_text = true
		resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_child(resource_label)
		resource_labels[_port_key(machine.instance_id, resource_id)] = resource_label
		var color := ResourceRegistry.get_colour(resource_id)
		var port_type := ResourceRegistry.get_port_type(resource_id)
		node.set_slot(
			row,
			accepts,
			port_type,
			color,
			produces,
			port_type,
			color
		)

		if accepts:
			input_ports[_port_key(machine.instance_id, resource_id)] = input_port
			input_port += 1

		if produces:
			output_ports[_port_key(machine.instance_id, resource_id)] = output_port
			output_port += 1

		row += 1

	node.node_selected.connect(_on_node_selected.bind(machine))
	process_graph.add_child(node)
	_update_machine_node(machine)


func _update_machine_node(machine: MachineModel) -> void:
	if machine == null:
		return

	var state_label := state_labels.get(machine.instance_id) as Label
	var metrics_label := metrics_labels.get(machine.instance_id) as Label

	if state_label != null:
		state_label.text = _state_text(machine.state)
		state_label.add_theme_color_override(
			"font_color",
			_state_color(machine.state)
		)

	if metrics_label != null:
		metrics_label.text = "Rate %.0f%%  •  Power %.2f PU\nCondition %.1f%%" % [
			machine.actual_operating_rate * 100.0,
			machine.power_demand,
			machine.condition * 100.0
		]

	for resource_id: String in _get_machine_resources(machine):
		var label := resource_labels.get(
			_port_key(machine.instance_id, resource_id)
		) as Label

		if label != null:
			label.text = "%s  %.1f %s" % [
				ResourceRegistry.get_display_name(resource_id),
				machine.inventory.get_amount(resource_id),
				ResourceRegistry.get_unit(resource_id)
			]


func _rebuild_connections() -> void:
	process_graph.clear_connections()

	if factory == null:
		return

	for connection: ConnectionModel in factory.connections:
		_draw_connection(connection)


func _draw_connection(connection: ConnectionModel) -> void:
	if connection == null:
		return

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

	process_graph.connect_node(
		connection.from_machine.instance_id,
		int(output_ports[from_key]),
		connection.to_machine.instance_id,
		int(input_ports[to_key])
	)
	_update_connection_activity(connection)


func _update_connection_activity(connection: ConnectionModel) -> void:
	if connection == null:
		return

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

	var activity := 0.0

	if connection.enabled and connection.capacity_per_second > 0.0:
		activity = clampf(
			connection.current_rate_per_second
			/ connection.capacity_per_second,
			0.0,
			1.0
		)

	process_graph.set_connection_activity(
		connection.from_machine.instance_id,
		int(output_ports[from_key]),
		connection.to_machine.instance_id,
		int(input_ports[to_key]),
		activity
	)


func _fit_plant() -> void:
	if process_graph == null or factory == null or factory.machines.is_empty():
		return

	var bounds := Rect2()
	var first := true

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		var machine_rect := Rect2(
			machine.graph_position,
			Vector2(245, 170)
		)
		bounds = machine_rect if first else bounds.merge(machine_rect)
		first = false

	if first:
		return

	bounds = bounds.grow(80.0)
	var available := process_graph.size - Vector2(80, 80)
	var target_zoom := minf(
		available.x / maxf(bounds.size.x, 1.0),
		available.y / maxf(bounds.size.y, 1.0)
	)
	process_graph.zoom = clampf(
		target_zoom,
		process_graph.zoom_min,
		process_graph.zoom_max
	)
	process_graph.scroll_offset = (
		bounds.get_center()
		- process_graph.size * 0.5 / process_graph.zoom
	)


func _update_system_status() -> void:
	if system_status == null:
		return

	if factory == null or factory.machines.is_empty():
		system_status.text = "No equipment"
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_TEXT_MUTED
		)
		return

	var failed := 0
	var alarms := 0

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		if machine.is_failed():
			failed += 1
		elif (
			machine.is_maintenance_due()
			or machine.is_breakdown_risk_warning()
			or machine.state in [
				MachineModel.State.BLOCKED_INPUT,
				MachineModel.State.BLOCKED_OUTPUT,
				MachineModel.State.DISABLED
			]
		):
			alarms += 1

	if failed > 0:
		system_status.text = "%d FAILED  •  %d additional alarms" % [
			failed,
			alarms
		]
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_DANGER
		)
	elif alarms > 0:
		system_status.text = "%d active alarm%s" % [
			alarms,
			"" if alarms == 1 else "s"
		]
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_WARNING
		)
	else:
		system_status.text = "Plant operating normally"
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_SUCCESS
		)


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


func _port_key(machine_id: String, resource_id: String) -> String:
	return "%s:%s" % [machine_id, resource_id]


func _state_text(state: MachineModel.State) -> String:
	return (MachineModel.State.keys()[state] as String).capitalize()


func _state_color(state: MachineModel.State) -> Color:
	match state:
		MachineModel.State.RUNNING:
			return ThemeManager.COLOR_SUCCESS
		MachineModel.State.BLOCKED_INPUT, MachineModel.State.BLOCKED_OUTPUT:
			return ThemeManager.COLOR_WARNING
		MachineModel.State.DISABLED, MachineModel.State.FAILED:
			return ThemeManager.COLOR_DANGER
		MachineModel.State.MAINTENANCE:
			return ThemeManager.COLOR_ACCENT
		_:
			return ThemeManager.COLOR_TEXT_MUTED


func _on_machine_added(machine: MachineModel) -> void:
	_add_machine_node(machine)
	_update_system_status()
	call_deferred("_fit_plant")


func _on_machine_removed(machine_id: String) -> void:
	var node := process_graph.get_node_or_null(NodePath(machine_id)) as GraphNode

	if node != null:
		process_graph.remove_child(node)
		node.queue_free()

	_rebuild_connections()
	_update_system_status()


func _on_machine_changed(machine: MachineModel) -> void:
	_update_machine_node(machine)
	_update_system_status()


func _on_connection_added(connection: ConnectionModel) -> void:
	_draw_connection(connection)


func _on_connection_removed(_connection: ConnectionModel) -> void:
	_rebuild_connections()


func _on_connection_changed(connection: ConnectionModel) -> void:
	_update_connection_activity(connection)


func _on_node_selected(machine: MachineModel) -> void:
	machine_requested.emit(machine)
