extends GraphEdit


signal machine_selected(machine: MachineModel)
signal connection_selected(connection: ConnectionModel)
signal selection_changed(selected_count: int)
signal machines_deleted(deleted_count: int, salvage_value: float)
signal placement_state_changed(active: bool, valid: bool, message: String)


var factory: FactoryModel
var refresh_manager: RefreshManager
var history: EditorHistory
var input_ports: Dictionary = {}
var output_ports: Dictionary = {}
var input_port_resources: Dictionary = {}
var output_port_resources: Dictionary = {}
var state_labels: Dictionary = {}
var name_labels: Dictionary = {}
var metrics_labels: Dictionary = {}
var resource_labels: Dictionary = {}
var dirty_machines: Dictionary = {}
var selection_notification_pending := false
var move_start_positions: Dictionary = {}
var selected_connection: ConnectionModel
var pending_machine: MachineModel
var pending_placement_valid := false
var dragged_route_connection: ConnectionModel
var dragged_route_point_index := -1
var route_drag_start_points: Array[Vector2] = []
var flow_animation_time := 0.0
var flow_animation_paused := false

const GRID_CELL_SIZE := 32.0
const ROUTE_NODE_CLEARANCE := 16.0
const ROUTE_OBSTACLE_CLEARANCE := 12.0
const ROUTE_OVERLAP_EPSILON := 1.0
const FLOW_PARTICLE_MIN_RATE := 0.001
const FLOW_PARTICLE_SPACING := 64.0
const FLOW_PARTICLE_MIN_SPEED := 42.0
const FLOW_PARTICLE_MAX_SPEED := 96.0
const FLOW_PARTICLE_GLOW_RADIUS := 5.0
const FLOW_PARTICLE_CORE_RADIUS := 2.5
const GRID_MINOR_COLOR := Color(0.18, 0.20, 0.23, 0.45)
const GRID_MAJOR_COLOR := Color(0.26, 0.29, 0.33, 0.65)
const FOOTPRINT_VALID_COLOR := Color(0.20, 0.78, 0.46, 0.42)
const FOOTPRINT_INVALID_COLOR := Color(0.90, 0.25, 0.25, 0.48)


func _ready() -> void:
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	begin_node_move.connect(_on_begin_node_move)
	end_node_move.connect(_on_end_node_move)
	right_disconnects = true
	snapping_enabled = true
	snapping_distance = int(GRID_CELL_SIZE)
	set_process(true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not flow_animation_paused:
		flow_animation_time += delta
	queue_redraw()


func _draw() -> void:
	_draw_plant_grid()
	_draw_routed_connections()


func _gui_input(event: InputEvent) -> void:
	var motion_event := event as InputEventMouseMotion
	if motion_event != null and dragged_route_connection != null:
		_drag_route_point(motion_event.position)
		accept_event()
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return

	if (
		not mouse_event.pressed
		and mouse_event.button_index == MOUSE_BUTTON_LEFT
		and dragged_route_connection != null
	):
		_finish_route_drag()
		accept_event()
		return

	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var handle := _route_handle_at_screen_point(mouse_event.position)
		if not handle.is_empty():
			_begin_route_drag(
			handle.get("connection") as ConnectionModel,
				int(handle.get("index", -1))
			)
			accept_event()
			return

		var connection := _connection_at_screen_point(mouse_event.position)
		if connection == null:
			return

		_select_connection(connection)
		if mouse_event.double_click:
			_add_route_point_at(connection, mouse_event.position)
		accept_event()
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var handle := _route_handle_at_screen_point(mouse_event.position)
		if not handle.is_empty():
			_remove_route_point(
				handle.get("connection") as ConnectionModel,
				int(handle.get("index", -1))
			)
			accept_event()
			return

		var connection := _connection_at_screen_point(mouse_event.position)
		if connection != null:
			_execute_history_action(
				"remove %s connection" % _resource_display_name(connection.resource_id),
				_remove_existing_connection.bind(connection),
				_add_existing_connection.bind(connection)
			)
			accept_event()


func bind_refresh_manager(manager: RefreshManager) -> void:
	refresh_manager = manager


func bind_history(new_history: EditorHistory) -> void:
	history = new_history


func set_flow_animation_paused(value: bool) -> void:
	flow_animation_paused = value
	queue_redraw()


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
	factory.event_bus.machine_settings_changed.connect(_on_machine_state_changed)
	factory.event_bus.machine_performance_changed.connect(_on_machine_state_changed)
	factory.event_bus.machine_power_changed.connect(_on_machine_state_changed)
	factory.event_bus.machine_control_changed.connect(_on_machine_state_changed)
	factory.event_bus.machine_condition_changed.connect(_on_machine_state_changed)
	factory.event_bus.connection_added.connect(_on_connection_added)
	factory.event_bus.connection_removed.connect(_on_connection_removed)

	for value: Variant in factory.machines.values():
		add_machine_node(value as MachineModel)

	_rebuild_connections()


func request_machine(definition_id: String) -> bool:
	if factory == null:
		return false

	if not factory.can_afford_machine(definition_id):
		return false

	if pending_machine != null:
		return false

	var position := _snap_position(scroll_offset + size * 0.5 / zoom)
	var machine := factory.create_machine(definition_id, position)

	if machine != null:
		machine.placement_committed = false
		machine.graph_position = _find_free_position(machine, position)
		pending_machine = machine
		if factory.add_machine(machine):
			pending_placement_valid = _is_placement_valid(machine)
			placement_state_changed.emit(
				true,
				pending_placement_valid,
				_placement_message(machine)
			)
			select_and_focus_machine(machine.instance_id)
			return true

		pending_machine = null

	return false


func delete_selected_machines() -> int:
	return _delete_machine_ids(_get_selected_machine_ids())


func select_and_focus_machine(machine_id: String) -> void:
	var target := get_node_or_null(
		NodePath(machine_id)
	) as GraphNode

	if target == null or factory == null:
		return

	for child: Node in get_children():
		var graph_node := child as GraphNode

		if graph_node != null:
			graph_node.selected = graph_node == target

	scroll_offset = (
		target.position_offset
		+ target.size * 0.5
		- size * 0.5 / zoom
	)

	var machine := factory.get_machine(machine_id)

	if machine != null:
		machine_selected.emit(machine)

	_request_selection_notification()


func clear_graph() -> void:
	selected_connection = null
	dragged_route_connection = null
	dragged_route_point_index = -1
	route_drag_start_points.clear()
	pending_machine = null
	pending_placement_valid = false
	clear_connections()
	input_ports.clear()
	output_ports.clear()
	input_port_resources.clear()
	output_port_resources.clear()
	state_labels.clear()
	name_labels.clear()
	metrics_labels.clear()
	resource_labels.clear()
	dirty_machines.clear()

	for child: Node in get_children():
		if child is GraphNode:
			remove_child(child)
			child.queue_free()

	selection_changed.emit(0)
	placement_state_changed.emit(false, false, "")


func add_machine_node(machine: MachineModel) -> void:
	var node := GraphNode.new()
	node.name = machine.instance_id
	node.title = ""
	node.position_offset = machine.graph_position
	var footprint_size := Vector2(machine.get_oriented_footprint()) * GRID_CELL_SIZE
	node.custom_minimum_size = footprint_size
	node.size = footprint_size
	node.draggable = not machine.placement_committed
	node.resizable = false
	node.add_theme_constant_override("separation", 0)
	_apply_machine_node_style(node, machine)

	var name_label := Label.new()
	name_label.text = machine.display_name
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT)
	node.add_child(name_label)
	name_labels[machine.instance_id] = name_label

	var state_label := Label.new()
	state_label.clip_text = true
	state_label.add_theme_font_size_override("font_size", 10)
	node.add_child(state_label)
	state_labels[machine.instance_id] = state_label

	var metrics_label := Label.new()
	metrics_label.clip_text = true
	metrics_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metrics_label.add_theme_font_size_override("font_size", 10)
	node.add_child(metrics_label)
	metrics_labels[machine.instance_id] = metrics_label
	_update_machine_summary(machine)

	var resources := _get_machine_resources(machine)
	var input_port := 0
	var output_port := 0
	var row := 3

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
		resource_label.clip_text = true
		resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		resource_label.add_theme_font_size_override("font_size", 10)
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
		var port_type := ResourceRegistry.get_port_type(
			resource_id
		)
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
	node.size = footprint_size
	queue_redraw()


func _apply_machine_node_style(node: GraphNode, machine: MachineModel) -> void:
	var background := ThemeManager.COLOR_SURFACE
	var border := _state_color(machine.state)
	if not machine.placement_committed:
		background = (
			FOOTPRINT_VALID_COLOR.darkened(0.55)
			if pending_placement_valid
			else FOOTPRINT_INVALID_COLOR.darkened(0.45)
		)
		border = (
			ThemeManager.COLOR_SUCCESS
			if pending_placement_valid
			else ThemeManager.COLOR_DANGER
		)

	var normal := _make_node_style(background, border, 2)
	var selected := _make_node_style(
		background.lightened(0.05),
		ThemeManager.COLOR_ACCENT,
		3
	)
	node.add_theme_stylebox_override("panel", normal)
	node.add_theme_stylebox_override("panel_selected", selected)
	var titlebar := StyleBoxFlat.new()
	titlebar.bg_color = Color.TRANSPARENT
	titlebar.content_margin_left = 0.0
	titlebar.content_margin_right = 0.0
	titlebar.content_margin_top = 0.0
	titlebar.content_margin_bottom = 0.0
	node.add_theme_stylebox_override("titlebar", titlebar)
	node.add_theme_stylebox_override("titlebar_selected", titlebar)


func _make_node_style(
	background: Color,
	border: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(2)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _update_machine_summary(machine: MachineModel) -> void:
	var state_label := state_labels.get(machine.instance_id) as Label
	var metrics_label := metrics_labels.get(machine.instance_id) as Label
	var node := get_node_or_null(NodePath(machine.instance_id)) as GraphNode
	var mode := (
		"AUTO"
		if machine.control_mode == MachineModel.ControlMode.AUTOMATIC
		else "MAN"
	)
	var style_needs_update := false

	if state_label != null:
		var state_text := "%s  •  %s" % [
			_state_text(machine.state).to_upper(),
			mode
		]
		style_needs_update = state_label.text != state_text
		state_label.text = state_text
		state_label.add_theme_color_override(
			"font_color",
			_state_color(machine.state)
		)

	if metrics_label != null:
		metrics_label.text = _machine_metrics_text(machine)

	if node != null and style_needs_update:
		_apply_machine_node_style(node, machine)


func _machine_metrics_text(machine: MachineModel) -> String:
	var footprint := machine.get_oriented_footprint()
	var condition_text := "Cond %.0f%%" % (machine.condition * 100.0)
	if machine.is_batch_machine():
		return "%s • %s" % [machine.get_batch_status_text(), condition_text]

	if machine.supports_inventory_control():
		var unit := ResourceRegistry.get_unit(machine.control_resource)
		if footprint.x >= 6 and footprint.y >= 6:
			return "SP %.0f  PV %.0f %s\nCO %.0f%%  •  %s" % [
				machine.inventory_setpoint,
				machine.controlled_inventory_amount,
				unit,
				machine.operating_rate * 100.0,
				condition_text
			]
		return "SP%.0f PV%.0f\nCO%.0f%% C%.0f%%" % [
			machine.inventory_setpoint,
			machine.controlled_inventory_amount,
			machine.operating_rate * 100.0,
			machine.condition * 100.0
		]

	if footprint.x >= 6 and footprint.y >= 6:
		return "Rate %.0f%% • Power %.2f PU\n%s" % [
			machine.actual_operating_rate * 100.0,
			machine.power_demand,
			condition_text
		]

	return "Rate %.0f%% • %s" % [
		machine.actual_operating_rate * 100.0,
		condition_text
	]


func commit_pending_placement() -> bool:
	if (
		pending_machine == null
		or not pending_placement_valid
		or factory == null
	):
		return false
	if not factory.can_afford_machine(pending_machine.definition_id):
		placement_state_changed.emit(
			true,
			false,
			"Insufficient cash to construct %s" % pending_machine.display_name
		)
		return false

	var machine := pending_machine
	_execute_history_action(
		"construct %s" % machine.display_name,
		_commit_machine_placement.bind(machine),
		_uncommit_machine_placement.bind(machine)
	)
	pending_machine = null
	pending_placement_valid = false
	placement_state_changed.emit(false, false, "")
	queue_redraw()
	return machine.placement_committed


func cancel_pending_placement() -> bool:
	if pending_machine == null or factory == null:
		return false

	var machine := pending_machine
	pending_machine = null
	pending_placement_valid = false
	factory.remove_machine(machine.instance_id)
	machine_selected.emit(null)
	placement_state_changed.emit(false, false, "")
	queue_redraw()
	return true


func rotate_pending_placement() -> bool:
	if pending_machine == null:
		return false

	pending_machine.placement_orientation = (
		pending_machine.placement_orientation + 90
	) % 360
	var node := get_node_or_null(
		NodePath(pending_machine.instance_id)
	) as GraphNode
	if node != null:
		var footprint_size := (
			Vector2(pending_machine.get_oriented_footprint())
			* GRID_CELL_SIZE
		)
		node.custom_minimum_size = footprint_size
		node.size = footprint_size
	pending_placement_valid = _is_placement_valid(pending_machine)
	if node != null:
		_apply_machine_node_style(node, pending_machine)
	placement_state_changed.emit(
		true,
		pending_placement_valid,
		_placement_message(pending_machine)
	)
	queue_redraw()
	return true


func _commit_machine_placement(machine: MachineModel) -> void:
	if factory.commit_machine_placement(machine):
		var node := get_node_or_null(NodePath(machine.instance_id)) as GraphNode
		if node != null:
			node.position_offset = machine.graph_position
			node.draggable = false
			_apply_machine_node_style(node, machine)
		if pending_machine == machine:
			pending_machine = null
			pending_placement_valid = false
			placement_state_changed.emit(false, false, "")


func _uncommit_machine_placement(machine: MachineModel) -> void:
	if factory.reverse_machine_placement_commit(machine):
		pending_machine = machine
		pending_placement_valid = _is_placement_valid(machine)
		var node := get_node_or_null(NodePath(machine.instance_id)) as GraphNode
		if node != null:
			node.draggable = true
			_apply_machine_node_style(node, machine)
		placement_state_changed.emit(
			true,
			pending_placement_valid,
			_placement_message(machine)
		)


func _draw_plant_grid() -> void:
	var spacing := GRID_CELL_SIZE * zoom
	if spacing < 4.0:
		return

	var top_left_world := _screen_to_world(Vector2.ZERO)
	var column := int(floor(top_left_world.x / GRID_CELL_SIZE))
	var first_x_world := column * GRID_CELL_SIZE
	var x := _world_to_screen(Vector2(first_x_world, 0.0)).x
	while x <= size.x:
		var color := GRID_MAJOR_COLOR if column % 5 == 0 else GRID_MINOR_COLOR
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, 1.0)
		x += spacing
		column += 1

	var row := int(floor(top_left_world.y / GRID_CELL_SIZE))
	var first_y_world := row * GRID_CELL_SIZE
	var y := _world_to_screen(Vector2(0.0, first_y_world)).y
	while y <= size.y:
		var color := GRID_MAJOR_COLOR if row % 5 == 0 else GRID_MINOR_COLOR
		draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 1.0)
		y += spacing
		row += 1


func _draw_routed_connections() -> void:
	if factory == null:
		return

	# Migrate every legacy route before generating any replacement. This keeps
	# one connection from treating another connection's obsolete lane as occupied.
	for connection: ConnectionModel in factory.connections:
		if connection.route_version < ConnectionModel.ROUTE_VERSION:
			connection.route_points.clear()
			connection.route_version = ConnectionModel.ROUTE_VERSION
			connection.route_initialized = false
			connection.route_valid = false

	for connection: ConnectionModel in factory.connections:
		_ensure_connection_route(connection)
		var route: Array[Vector2] = _get_connection_route_world(connection)
		if route.size() < 2:
			continue

		var color := _resource_color(connection.resource_id)
		if not connection.enabled:
			color = ThemeManager.COLOR_TEXT_MUTED
		if connection == selected_connection:
			color = color.lightened(0.25)
		var width := 5.0 if connection == selected_connection else 3.0

		for index: int in range(route.size() - 1):
			draw_line(
				_world_to_screen(route[index]),
				_world_to_screen(route[index + 1]),
				color,
				width,
				true
			)

		_draw_flow_particles(connection, route, color)

		if connection == selected_connection:
			for point: Vector2 in connection.route_points:
				var screen_point := _world_to_screen(point)
				draw_rect(
					Rect2(screen_point - Vector2(5, 5), Vector2(10, 10)),
					ThemeManager.COLOR_ACCENT,
					true
				)


func _draw_flow_particles(
	connection: ConnectionModel,
	route: Array[Vector2],
	line_color: Color
) -> void:
	if (
		flow_animation_paused
		or not connection.enabled
		or connection.current_rate_per_second <= FLOW_PARTICLE_MIN_RATE
		or route.size() < 2
	):
		return

	var route_length := _route_length(route)
	if route_length <= 0.01:
		return

	var capacity := maxf(connection.capacity_per_second, 0.001)
	var utilization := clampf(
		connection.current_rate_per_second / capacity,
		0.0,
		1.0
	)
	var speed := lerpf(
		FLOW_PARTICLE_MIN_SPEED,
		FLOW_PARTICLE_MAX_SPEED,
		utilization
	)
	var distance := fposmod(
		flow_animation_time * speed,
		FLOW_PARTICLE_SPACING
	)
	var glow_color := line_color
	glow_color.a = 0.30
	var core_color := line_color.lightened(0.65)
	core_color.a = 1.0

	while distance < route_length:
		var world_point: Vector2 = _point_on_route(route, distance)
		var screen_point := _world_to_screen(world_point)
		draw_circle(
			screen_point,
			FLOW_PARTICLE_GLOW_RADIUS,
			glow_color
		)
		draw_circle(
			screen_point,
			FLOW_PARTICLE_CORE_RADIUS,
			core_color
		)
		distance += FLOW_PARTICLE_SPACING


func _route_length(route: Array[Vector2]) -> float:
	var total := 0.0
	for index: int in range(route.size() - 1):
		total += route[index].distance_to(route[index + 1])
	return total


func _point_on_route(route: Array[Vector2], distance: float) -> Vector2:
	if route.is_empty():
		return Vector2.ZERO

	var remaining := maxf(distance, 0.0)
	for index: int in range(route.size() - 1):
		var start: Vector2 = route[index]
		var finish: Vector2 = route[index + 1]
		var segment_length := start.distance_to(finish)
		if segment_length <= 0.001:
			continue
		if remaining <= segment_length:
			return start.lerp(finish, remaining / segment_length)
		remaining -= segment_length

	return route[route.size() - 1]


func _ensure_connection_route(connection: ConnectionModel) -> void:
	if connection == null:
		return

	if connection.route_version < ConnectionModel.ROUTE_VERSION:
		connection.route_points.clear()
		connection.route_version = ConnectionModel.ROUTE_VERSION
		connection.route_initialized = false
		connection.route_valid = false

	if connection.route_initialized:
		return

	var route: Array[Vector2] = _automatic_interior_route(connection)
	if route.size() >= 2:
		connection.set_route_points(_intermediate_points(route))
	else:
		# Do not run the full lane search every redraw when no legal route exists.
		connection.route_initialized = true
		connection.route_valid = false


func _get_connection_route_world(
	connection: ConnectionModel
) -> Array[Vector2]:
	var endpoints: Array[Vector2] = _get_connection_endpoints(connection)
	if endpoints.size() != 2:
		return []
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if terminals.size() != 2:
		return []

	var interior: Array[Vector2] = _get_connection_interior_route(connection)
	if interior.size() < 2:
		return []

	var route: Array[Vector2] = [endpoints[0], terminals[0]]
	for index: int in range(1, interior.size() - 1):
		route.append(interior[index])
	route.append(terminals[1])
	route.append(endpoints[1])
	return _clean_route(route)


func _get_connection_interior_route(
	connection: ConnectionModel
) -> Array[Vector2]:
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if terminals.size() != 2:
		return []

	if connection.route_initialized:
		if not connection.route_valid:
			return []
		var cached_route: Array[Vector2] = [terminals[0]]
		for point: Vector2 in connection.route_points:
			cached_route.append(point)
		cached_route.append(terminals[1])
		return _clean_route(cached_route)

	return _automatic_interior_route(connection)


func _get_connection_endpoints(
	connection: ConnectionModel
) -> Array[Vector2]:
	var from_node := get_node_or_null(
		NodePath(connection.from_machine.instance_id)
	) as GraphNode
	var to_node := get_node_or_null(
		NodePath(connection.to_machine.instance_id)
	) as GraphNode
	if from_node == null or to_node == null:
		return []

	var from_key := _port_key(
		connection.from_machine.instance_id,
		connection.resource_id
	)
	var to_key := _port_key(
		connection.to_machine.instance_id,
		connection.resource_id
	)
	if not output_ports.has(from_key) or not input_ports.has(to_key):
		return []

	var from_port := int(output_ports[from_key])
	var to_port := int(input_ports[to_key])
	return [
		from_node.position_offset + from_node.get_output_port_position(from_port),
		to_node.position_offset + to_node.get_input_port_position(to_port)
	]


func _get_connection_clear_terminals(
	connection: ConnectionModel
) -> Array[Vector2]:
	var endpoints: Array[Vector2] = _get_connection_endpoints(connection)
	if endpoints.size() != 2:
		return []
	var from_rect: Rect2 = _get_footprint_rect(connection.from_machine)
	var to_rect: Rect2 = _get_footprint_rect(connection.to_machine)
	return [
		Vector2(from_rect.end.x + ROUTE_NODE_CLEARANCE, endpoints[0].y),
		Vector2(to_rect.position.x - ROUTE_NODE_CLEARANCE, endpoints[1].y)
	]


func _automatic_interior_route(connection: ConnectionModel) -> Array[Vector2]:
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if terminals.size() != 2:
		return []

	return _auto_route_between(
		connection,
		terminals[0],
		terminals[1]
	)


func _auto_route_between(
	connection: ConnectionModel,
	start: Vector2,
	finish: Vector2
) -> Array[Vector2]:
	var direct: Array[Vector2] = [start, finish]
	if _polyline_clear(connection, direct):
		return direct

	var horizontal_first: Array[Vector2] = [
		start,
		Vector2(finish.x, start.y),
		finish
	]
	if _polyline_clear(connection, horizontal_first):
		return _clean_route(horizontal_first)

	var vertical_first: Array[Vector2] = [
		start,
		Vector2(start.x, finish.y),
		finish
	]
	if _polyline_clear(connection, vertical_first):
		return _clean_route(vertical_first)

	var middle_x := _snap_scalar((start.x + finish.x) * 0.5)
	for offset: int in range(0, 65):
		var x_candidates: Array[float] = [
			middle_x + offset * GRID_CELL_SIZE,
			middle_x - offset * GRID_CELL_SIZE
		]
		for corridor_x: float in x_candidates:
			var route_x: Array[Vector2] = [
				start,
				Vector2(corridor_x, start.y),
				Vector2(corridor_x, finish.y),
				finish
			]
			if _polyline_clear(connection, route_x):
				return _clean_route(route_x)

	var middle_y := _snap_scalar((start.y + finish.y) * 0.5)
	for offset: int in range(0, 65):
		var y_candidates: Array[float] = [
			middle_y + offset * GRID_CELL_SIZE,
			middle_y - offset * GRID_CELL_SIZE
		]
		for corridor_y: float in y_candidates:
			var route_y: Array[Vector2] = [
				start,
				Vector2(start.x, corridor_y),
				Vector2(finish.x, corridor_y),
				finish
			]
			if _polyline_clear(connection, route_y):
				return _clean_route(route_y)

	return []


func _route_through_points(
	connection: ConnectionModel,
	start: Vector2,
	finish: Vector2,
	points: Array[Vector2]
) -> Array[Vector2]:
	var route: Array[Vector2] = [start]
	var targets: Array[Vector2] = points.duplicate()
	targets.append(finish)

	for target: Vector2 in targets:
		var current: Vector2 = route.back()
		if is_equal_approx(current.x, target.x) or is_equal_approx(current.y, target.y):
			var direct_candidate: Array[Vector2] = route.duplicate()
			direct_candidate.append(target)
			if not _polyline_clear(connection, direct_candidate):
				return []
			route.append(target)
			continue

		var option_a: Array[Vector2] = route.duplicate()
		option_a.append(Vector2(target.x, current.y))
		option_a.append(target)
		if _polyline_clear(connection, option_a):
			route = option_a
			continue

		var option_b: Array[Vector2] = route.duplicate()
		option_b.append(Vector2(current.x, target.y))
		option_b.append(target)
		if _polyline_clear(connection, option_b):
			route = option_b
			continue

		var detour: Array[Vector2] = _auto_route_between(connection, current, target)
		if detour.size() < 2 or not _polyline_clear(connection, detour):
			return []
		for index: int in range(1, detour.size()):
			route.append(detour[index])

	return _clean_route(route)


func _polyline_clear(
	connection: ConnectionModel,
	route: Array[Vector2]
) -> bool:
	if route.size() < 2:
		return false

	for index: int in range(route.size() - 1):
		var start: Vector2 = route[index]
		var finish: Vector2 = route[index + 1]
		if (
			not is_equal_approx(start.x, finish.x)
			and not is_equal_approx(start.y, finish.y)
		):
			return false

		for value: Variant in factory.machines.values():
			var machine := value as MachineModel
			if machine == null:
				continue
			if _segment_intersects_rect(
				start,
				finish,
				_get_footprint_rect(machine).grow(ROUTE_OBSTACLE_CLEARANCE)
			):
				return false

		if _segment_overlaps_other_material(connection, start, finish):
			return false

	return true


func _segment_overlaps_other_material(
	connection: ConnectionModel,
	start: Vector2,
	finish: Vector2
) -> bool:
	if factory == null:
		return false

	for other: ConnectionModel in factory.connections:
		if other == connection or other.resource_id == connection.resource_id:
			continue
		var other_route: Array[Vector2] = _get_connection_route_world_unchecked(other)
		for index: int in range(other_route.size() - 1):
			if _segments_share_track(
				start,
				finish,
				other_route[index],
				other_route[index + 1]
			):
				return true
	return false


func _get_connection_route_world_unchecked(
	connection: ConnectionModel
) -> Array[Vector2]:
	var endpoints: Array[Vector2] = _get_connection_endpoints(connection)
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if endpoints.size() != 2 or terminals.size() != 2:
		return []

	var route: Array[Vector2] = [endpoints[0], terminals[0]]
	for point: Vector2 in connection.route_points:
		route.append(point)
	route.append(terminals[1])
	route.append(endpoints[1])
	return _clean_route(route)


func _segments_share_track(
	a_start: Vector2,
	a_finish: Vector2,
	b_start: Vector2,
	b_finish: Vector2
) -> bool:
	var a_horizontal := is_equal_approx(a_start.y, a_finish.y)
	var b_horizontal := is_equal_approx(b_start.y, b_finish.y)
	var a_vertical := is_equal_approx(a_start.x, a_finish.x)
	var b_vertical := is_equal_approx(b_start.x, b_finish.x)

	if a_horizontal and b_horizontal:
		if absf(a_start.y - b_start.y) > ROUTE_OVERLAP_EPSILON:
			return false
		return _ranges_overlap_more_than_point(
			a_start.x,
			a_finish.x,
			b_start.x,
			b_finish.x
		)

	if a_vertical and b_vertical:
		if absf(a_start.x - b_start.x) > ROUTE_OVERLAP_EPSILON:
			return false
		return _ranges_overlap_more_than_point(
			a_start.y,
			a_finish.y,
			b_start.y,
			b_finish.y
		)

	return false


func _ranges_overlap_more_than_point(
	a_start: float,
	a_finish: float,
	b_start: float,
	b_finish: float
) -> bool:
	var overlap_start := maxf(minf(a_start, a_finish), minf(b_start, b_finish))
	var overlap_finish := minf(maxf(a_start, a_finish), maxf(b_start, b_finish))
	return overlap_finish - overlap_start > ROUTE_OVERLAP_EPSILON


func _segment_intersects_rect(
	start: Vector2,
	finish: Vector2,
	rect: Rect2
) -> bool:
	if is_equal_approx(start.y, finish.y):
		var min_x := minf(start.x, finish.x)
		var max_x := maxf(start.x, finish.x)
		return (
			start.y >= rect.position.y
			and start.y <= rect.end.y
			and max_x >= rect.position.x
			and min_x <= rect.end.x
		)

	if is_equal_approx(start.x, finish.x):
		var min_y := minf(start.y, finish.y)
		var max_y := maxf(start.y, finish.y)
		return (
			start.x >= rect.position.x
			and start.x <= rect.end.x
			and max_y >= rect.position.y
			and min_y <= rect.end.y
		)

	return true


func _clean_route(route: Array[Vector2]) -> Array[Vector2]:
	var cleaned: Array[Vector2] = []
	for point: Vector2 in route:
		var is_new_point := cleaned.is_empty()
		if not cleaned.is_empty():
			var last_point: Vector2 = cleaned.back()
			is_new_point = last_point.distance_to(point) > 0.01
		if is_new_point:
			cleaned.append(point)

	var index := 1
	while index < cleaned.size() - 1:
		var previous: Vector2 = cleaned[index - 1]
		var current: Vector2 = cleaned[index]
		var following: Vector2 = cleaned[index + 1]
		if (
			(is_equal_approx(previous.x, current.x) and is_equal_approx(current.x, following.x))
			or (is_equal_approx(previous.y, current.y) and is_equal_approx(current.y, following.y))
		):
			cleaned.remove_at(index)
			continue
		index += 1

	return cleaned


func _intermediate_points(route: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index: int in range(1, route.size() - 1):
		result.append(route[index])
	return result


func _snap_scalar(value: float) -> float:
	return roundf(value / GRID_CELL_SIZE) * GRID_CELL_SIZE


func _world_to_screen(point: Vector2) -> Vector2:
	var reference_node := _get_view_reference_node()
	if reference_node != null:
		return (
			reference_node.position
			+ (point - reference_node.position_offset) * zoom
		)

	return (point - scroll_offset) * zoom


func _screen_to_world(point: Vector2) -> Vector2:
	var reference_node := _get_view_reference_node()
	if reference_node != null:
		return (
			reference_node.position_offset
			+ (point - reference_node.position) / zoom
		)

	return point / zoom + scroll_offset


func _get_view_reference_node() -> GraphNode:
	for child: Node in get_children():
		var graph_node := child as GraphNode
		if graph_node != null:
			return graph_node

	return null


func _connection_at_screen_point(point: Vector2) -> ConnectionModel:
	if factory == null:
		return null

	var closest: ConnectionModel
	var closest_distance := 9.0
	for connection: ConnectionModel in factory.connections:
		var route: Array[Vector2] = _get_connection_route_world(connection)
		for index: int in range(route.size() - 1):
			var distance := _point_segment_distance(
				point,
				_world_to_screen(route[index]),
				_world_to_screen(route[index + 1])
			)
			if distance < closest_distance:
				closest_distance = distance
				closest = connection

	return closest


func _route_handle_at_screen_point(point: Vector2) -> Dictionary:
	if selected_connection == null:
		return {}

	for index: int in range(selected_connection.route_points.size()):
		if _world_to_screen(
			selected_connection.route_points[index]
		).distance_to(point) <= 8.0:
			return {
				"connection": selected_connection,
				"index": index
			}

	return {}


func _point_segment_distance(
	point: Vector2,
	start: Vector2,
	finish: Vector2
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)

	var weight := clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(start + segment * weight)


func _closest_route_segment_index(
	connection: ConnectionModel,
	screen_point: Vector2
) -> int:
	var route: Array[Vector2] = _get_connection_interior_route(connection)
	var result := -1
	var closest_distance := INF
	for index: int in range(route.size() - 1):
		var distance := _point_segment_distance(
			screen_point,
			_world_to_screen(route[index]),
			_world_to_screen(route[index + 1])
		)
		if distance < closest_distance:
			closest_distance = distance
			result = index
	return result


func _add_route_point_at(
	connection: ConnectionModel,
	screen_point: Vector2
) -> void:
	var route: Array[Vector2] = _get_connection_interior_route(connection)
	if route.size() < 2:
		return

	var segment_index := _closest_route_segment_index(connection, screen_point)
	if segment_index < 0:
		return

	var points: Array[Vector2] = _intermediate_points(route)
	var snapped := _snap_position(_screen_to_world(screen_point))
	points.insert(mini(segment_index, points.size()), snapped)
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if terminals.size() != 2:
		return
	var candidate_route: Array[Vector2] = _route_through_points(
		connection,
		terminals[0],
		terminals[1],
		points
	)
	if candidate_route.size() < 2:
		return

	var final_points: Array[Vector2] = _intermediate_points(candidate_route)
	var previous_points: Array[Vector2] = connection.route_points.duplicate()
	_execute_history_action(
		"add connection route point",
		_set_connection_route_points.bind(connection, final_points),
		_set_connection_route_points.bind(connection, previous_points)
	)


func _remove_route_point(
	connection: ConnectionModel,
	point_index: int
) -> void:
	if point_index < 0 or point_index >= connection.route_points.size():
		return

	var previous_points: Array[Vector2] = connection.route_points.duplicate()
	var points: Array[Vector2] = connection.route_points.duplicate()
	points.remove_at(point_index)
	var terminals: Array[Vector2] = _get_connection_clear_terminals(connection)
	if terminals.size() != 2:
		return
	var candidate_route: Array[Vector2] = _route_through_points(
		connection,
		terminals[0],
		terminals[1],
		points
	)
	if candidate_route.size() < 2:
		return

	var final_points: Array[Vector2] = _intermediate_points(candidate_route)
	_execute_history_action(
		"remove connection route point",
		_set_connection_route_points.bind(connection, final_points),
		_set_connection_route_points.bind(connection, previous_points)
	)


func _begin_route_drag(
	connection: ConnectionModel,
	point_index: int
) -> void:
	if connection == null or point_index < 0:
		return
	_select_connection(connection)
	dragged_route_connection = connection
	dragged_route_point_index = point_index
	route_drag_start_points = connection.route_points.duplicate()


func _drag_route_point(screen_point: Vector2) -> void:
	if (
		dragged_route_connection == null
		or dragged_route_point_index < 0
		or dragged_route_point_index >= dragged_route_connection.route_points.size()
	):
		return

	var points: Array[Vector2] = dragged_route_connection.route_points.duplicate()
	points[dragged_route_point_index] = _snap_position(
		_screen_to_world(screen_point)
	)
	var terminals: Array[Vector2] = _get_connection_clear_terminals(dragged_route_connection)
	if terminals.size() != 2:
		return
	var route: Array[Vector2] = _route_through_points(
		dragged_route_connection,
		terminals[0],
		terminals[1],
		points
	)
	if route.size() < 2:
		return

	var normalized_points: Array[Vector2] = _intermediate_points(route)
	dragged_route_connection.set_route_points(normalized_points)
	queue_redraw()


func _finish_route_drag() -> void:
	if dragged_route_connection == null:
		return

	var connection: ConnectionModel = dragged_route_connection
	var previous_points: Array[Vector2] = route_drag_start_points.duplicate()
	var route: Array[Vector2] = _get_connection_interior_route(connection)
	var final_points: Array[Vector2] = _intermediate_points(route)
	connection.set_route_points(final_points)

	dragged_route_connection = null
	dragged_route_point_index = -1
	route_drag_start_points.clear()

	if history != null and final_points != previous_points:
		history.record_completed(
			"move connection route point",
			_set_connection_route_points.bind(connection, final_points),
			_set_connection_route_points.bind(connection, previous_points)
		)


func _set_connection_route_points(
	connection: ConnectionModel,
	points: Array[Vector2]
) -> void:
	if connection == null:
		return
	connection.set_route_points(points)
	queue_redraw()


func _get_footprint_rect(machine: MachineModel) -> Rect2:
	return Rect2(
		_snap_position(machine.graph_position),
		Vector2(machine.get_oriented_footprint()) * GRID_CELL_SIZE
	)


func _is_placement_valid(machine: MachineModel) -> bool:
	if factory == null or machine == null:
		return false

	var candidate := _get_footprint_rect(machine)
	for value: Variant in factory.machines.values():
		var other := value as MachineModel
		if other == null or other == machine:
			continue
		if candidate.intersects(_get_footprint_rect(other)):
			return false

	return true


func _find_free_position(machine: MachineModel, origin: Vector2) -> Vector2:
	machine.graph_position = _snap_position(origin)
	if _is_placement_valid(machine):
		return machine.graph_position

	for ring: int in range(1, 33):
		for y: int in range(-ring, ring + 1):
			for x: int in range(-ring, ring + 1):
				if absi(x) != ring and absi(y) != ring:
					continue
				machine.graph_position = _snap_position(origin) + Vector2(
					x * GRID_CELL_SIZE,
					y * GRID_CELL_SIZE
				)
				if _is_placement_valid(machine):
					return machine.graph_position

	return _snap_position(origin)


func _snap_position(position: Vector2) -> Vector2:
	return Vector2(
		roundf(position.x / GRID_CELL_SIZE) * GRID_CELL_SIZE,
		roundf(position.y / GRID_CELL_SIZE) * GRID_CELL_SIZE
	)


func _placement_message(machine: MachineModel) -> String:
	var footprint := machine.get_oriented_footprint()
	return "%s footprint %d × %d — %s" % [
		machine.display_name,
		footprint.x,
		footprint.y,
		"ready to construct" if pending_placement_valid else "overlaps existing equipment"
	]


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
	if connection == null:
		return
	queue_redraw()


func _get_model_connection(
	graph_connection: Dictionary
) -> ConnectionModel:
	if factory == null:
		return null

	var from_id := str(
		graph_connection.get("from_node", "")
	)
	var to_id := str(
		graph_connection.get("to_node", "")
	)
	var from_port := int(
		graph_connection.get("from_port", -1)
	)
	var output_key := _indexed_port_key(from_id, from_port)

	if not output_port_resources.has(output_key):
		return null

	return factory.find_connection(
		from_id,
		to_id,
		str(output_port_resources[output_key])
	)


func _select_connection(connection: ConnectionModel) -> void:
	if selected_connection == connection:
		connection_selected.emit(connection)
		return

	if selected_connection != null:
		_set_connection_activity(selected_connection, 0.0)

	selected_connection = connection

	if selected_connection != null:
		_set_connection_activity(selected_connection, 1.0)

	connection_selected.emit(selected_connection)


func _set_connection_activity(
	_connection: ConnectionModel,
	_activity: float
) -> void:
	queue_redraw()


func _port_key(machine_id: String, resource_id: String) -> String:
	return "%s:%s" % [machine_id, resource_id]


func _indexed_port_key(machine_id: String, port: int) -> String:
	return "%s:%d" % [machine_id, port]


func _resource_color(resource_id: String) -> Color:
	return ResourceRegistry.get_colour(resource_id)


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

	var summary_signals: Array[Signal] = [
		factory.event_bus.machine_settings_changed,
		factory.event_bus.machine_performance_changed,
		factory.event_bus.machine_power_changed,
		factory.event_bus.machine_control_changed,
		factory.event_bus.machine_condition_changed
	]
	for summary_signal: Signal in summary_signals:
		if summary_signal.is_connected(state_callback):
			summary_signal.disconnect(state_callback)

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
	if not from_machine.placement_committed or not to_machine.placement_committed:
		return

	var connection := ConnectionModel.new(
		from_machine,
		to_machine,
		output_resource,
		1.0
	)
	_execute_history_action(
		"connect %s" % _resource_display_name(output_resource),
		_add_existing_connection.bind(connection),
		_remove_existing_connection.bind(connection)
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
		_execute_history_action(
			"disconnect %s" % _resource_display_name(
				output_resource
			),
			_remove_existing_connection.bind(connection),
			_add_existing_connection.bind(connection)
		)


func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	_delete_machine_ids(nodes)


func _delete_machine_ids(nodes: Array[StringName]) -> int:
	if factory == null:
		return 0

	var machines: Array[MachineModel] = []

	for node_name: StringName in nodes:
		var machine := factory.get_machine(str(node_name))

		if machine != null:
			machines.append(machine)

	if machines.is_empty():
		return 0

	var cancelled_count := 0
	if pending_machine != null and machines.has(pending_machine):
		var provisional_machine := pending_machine
		cancel_pending_placement()
		machines.erase(provisional_machine)
		cancelled_count = 1
		if machines.is_empty():
			return 1

	var connections := _get_related_connections(machines)
	var salvage_value := 0.0

	for machine: MachineModel in machines:
		salvage_value += factory.get_machine_salvage_value(machine)

	var label := (
		"dismantle machine"
		if machines.size() == 1
		else "dismantle %d machines" % machines.size()
	)
	_execute_history_action(
		label,
		_remove_machine_group.bind(machines),
		_restore_machine_group.bind(machines, connections)
	)

	var deleted_count := machines.size() + cancelled_count

	if deleted_count > 0:
		machine_selected.emit(null)
		machines_deleted.emit(deleted_count, salvage_value)
		_request_selection_notification()

	return deleted_count


func _get_related_connections(
	machines: Array[MachineModel]
) -> Array[ConnectionModel]:
	var result: Array[ConnectionModel] = []
	var machine_ids: Array[String] = []

	for machine: MachineModel in machines:
		machine_ids.append(machine.instance_id)

	for connection: ConnectionModel in factory.connections:
		if (
			machine_ids.has(connection.from_machine.instance_id)
			or machine_ids.has(connection.to_machine.instance_id)
		):
			result.append(connection)

	return result


func _remove_machine_group(machines: Array[MachineModel]) -> void:
	for machine: MachineModel in machines:
		factory.salvage_machine(machine)


func _restore_machine_group(
	machines: Array[MachineModel],
	connections: Array[ConnectionModel]
) -> void:
	for machine: MachineModel in machines:
		factory.reverse_machine_salvage(machine)

	for connection: ConnectionModel in connections:
		factory.add_connection(connection)


func _purchase_existing_machine(machine: MachineModel) -> void:
	factory.purchase_machine(machine)


func _reverse_machine_purchase(machine: MachineModel) -> void:
	factory.reverse_machine_purchase(machine)


func _add_existing_connection(connection: ConnectionModel) -> void:
	factory.add_connection(connection)


func _remove_existing_connection(connection: ConnectionModel) -> void:
	factory.remove_connection(connection)


func _execute_history_action(
	label: String,
	do_action: Callable,
	undo_action: Callable
) -> void:
	if history == null:
		do_action.call()
		return

	history.execute(label, do_action, undo_action)


func _get_selected_machine_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for child: Node in get_children():
		var graph_node := child as GraphNode

		if graph_node != null and graph_node.selected:
			result.append(graph_node.name)

	return result


func _on_machine_removed(machine_id: String) -> void:
	if pending_machine != null and pending_machine.instance_id == machine_id:
		pending_machine = null
		pending_placement_valid = false
		placement_state_changed.emit(false, false, "")
	var graph_node := get_node_or_null(
		NodePath(machine_id)
	) as GraphNode

	if graph_node != null:
		remove_child(graph_node)
		graph_node.queue_free()

	_remove_machine_port_data(input_ports, machine_id)
	_remove_machine_port_data(output_ports, machine_id)
	_remove_machine_port_data(input_port_resources, machine_id)
	_remove_machine_port_data(output_port_resources, machine_id)
	_remove_machine_port_data(resource_labels, machine_id)
	state_labels.erase(machine_id)
	name_labels.erase(machine_id)
	metrics_labels.erase(machine_id)

	_rebuild_connections()
	_request_selection_notification()


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

		_update_machine_summary(machine)
		_update_machine_inventory(machine)


func _on_machine_added(machine: MachineModel) -> void:
	add_machine_node(machine)


func _on_connection_added(connection: ConnectionModel) -> void:
	_draw_connection(connection)


func _on_connection_removed(_connection: ConnectionModel) -> void:
	if selected_connection == _connection:
		selected_connection = null
		connection_selected.emit(null)

	_rebuild_connections()


func _on_graph_node_selected(machine: MachineModel) -> void:
	if selected_connection != null:
		_set_connection_activity(selected_connection, 0.0)
		selected_connection = null

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
	if machine.placement_committed:
		if node.position_offset != machine.graph_position:
			node.position_offset = machine.graph_position
		return

	var snapped := _snap_position(node.position_offset)
	machine.set_graph_position(snapped)
	pending_placement_valid = _is_placement_valid(machine)
	_apply_machine_node_style(node, machine)
	placement_state_changed.emit(
		true,
		pending_placement_valid,
		_placement_message(machine)
	)
	queue_redraw()


func _on_begin_node_move() -> void:
	move_start_positions.clear()

	for node_name: StringName in _get_selected_machine_ids():
		var machine := factory.get_machine(str(node_name))

		if machine != null and not machine.placement_committed:
			move_start_positions[machine.instance_id] = (
				machine.graph_position
			)


func _on_end_node_move() -> void:
	if move_start_positions.is_empty():
		return

	var end_positions: Dictionary = {}

	for machine_id: Variant in move_start_positions.keys():
		var machine := factory.get_machine(str(machine_id))

		if machine != null:
			end_positions[str(machine_id)] = machine.graph_position

	if end_positions == move_start_positions:
		move_start_positions.clear()
		return

	var start_positions := move_start_positions.duplicate()
	move_start_positions.clear()

	if history != null:
		history.record_completed(
			"move machines",
			_apply_machine_positions.bind(end_positions),
			_apply_machine_positions.bind(start_positions)
		)


func _apply_machine_positions(positions: Dictionary) -> void:
	for machine_id: Variant in positions.keys():
		var machine := factory.get_machine(str(machine_id))
		var graph_node := get_node_or_null(
			NodePath(str(machine_id))
		) as GraphNode
		var position: Vector2 = positions[machine_id]

		if machine != null:
			machine.set_graph_position(position)

		if graph_node != null:
			graph_node.position_offset = position

	if pending_machine != null:
		pending_placement_valid = _is_placement_valid(pending_machine)
		placement_state_changed.emit(
			true,
			pending_placement_valid,
			_placement_message(pending_machine)
		)


func _resource_display_name(resource_id: String) -> String:
	return resource_id.replace("_", " ").capitalize()


func _state_text(state: MachineModel.State) -> String:
	return MachineModel.State.keys()[state].capitalize()


func _state_color(state: MachineModel.State) -> Color:
	match state:
		MachineModel.State.RUNNING:
			return ThemeManager.COLOR_SUCCESS
		MachineModel.State.BLOCKED_INPUT, MachineModel.State.BLOCKED_OUTPUT:
			return ThemeManager.COLOR_WARNING
		MachineModel.State.FAILED:
			return ThemeManager.COLOR_DANGER
		MachineModel.State.MAINTENANCE:
			return ThemeManager.COLOR_ACCENT
		MachineModel.State.DISABLED:
			return ThemeManager.COLOR_TEXT_MUTED
		_:
			return ThemeManager.COLOR_TEXT
