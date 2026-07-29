extends DockPanel


var factory: FactoryModel
var selected_machine: MachineModel
var selected_connection: ConnectionModel
var refresh_manager: RefreshManager
var history: EditorHistory

var name_label: Label
var id_label: Label
var state_badge: Label
var operation_section: VBoxContainer
var connection_operation_section: VBoxContainer
var enabled_check_box: CheckBox
var operating_rate_spin_box: SpinBox
var actual_rate_value_label: Label
var effective_rate_value_label: Label
var efficiency_value_label: Label
var connection_enabled_check_box: CheckBox
var connection_capacity_spin_box: SpinBox
var input_title: Label
var output_title: Label
var inventory_title: Label
var input_list: VBoxContainer
var output_list: VBoxContainer
var inventory_list: VBoxContainer
var updating_controls := false


func _ready() -> void:
	dock_title = "Machine Inspector"
	super._ready()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	get_content_root().add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	name_label = Label.new()
	name_label.text = "No machine selected"
	name_label.add_theme_font_size_override("font_size", 16)
	root.add_child(name_label)

	id_label = Label.new()
	root.add_child(id_label)

	state_badge = UIWidgets.create_status_badge(
		"No selection",
		ThemeManager.COLOR_TEXT_MUTED
	)
	root.add_child(state_badge)

	root.add_child(HSeparator.new())

	operation_section = VBoxContainer.new()
	root.add_child(operation_section)

	var operation_title := UIWidgets.create_section_header(
		"Operation"
	)
	operation_section.add_child(operation_title)

	enabled_check_box = CheckBox.new()
	enabled_check_box.text = "Enabled"
	enabled_check_box.toggled.connect(_on_enabled_toggled)
	operation_section.add_child(enabled_check_box)

	var rate_row := HBoxContainer.new()
	operation_section.add_child(rate_row)

	var rate_label := Label.new()
	rate_label.text = "Operating rate"
	rate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_row.add_child(rate_label)

	operating_rate_spin_box = SpinBox.new()
	operating_rate_spin_box.custom_minimum_size = Vector2(105, 0)
	operating_rate_spin_box.min_value = 0.0
	operating_rate_spin_box.max_value = 150.0
	operating_rate_spin_box.step = 5.0
	operating_rate_spin_box.suffix = "%"
	operating_rate_spin_box.value_changed.connect(
		_on_operating_rate_changed
	)
	rate_row.add_child(operating_rate_spin_box)

	var actual_rate_row := UIWidgets.create_labeled_value(
		"Actual speed",
		"0%"
	)
	actual_rate_value_label = UIWidgets.get_value_label(
		actual_rate_row
	)
	operation_section.add_child(actual_rate_row)

	var effective_rate_row := UIWidgets.create_labeled_value(
		"Effective output",
		"0%"
	)
	effective_rate_value_label = UIWidgets.get_value_label(
		effective_rate_row
	)
	operation_section.add_child(effective_rate_row)

	var efficiency_row := UIWidgets.create_labeled_value(
		"Speed efficiency",
		"—"
	)
	efficiency_value_label = UIWidgets.get_value_label(
		efficiency_row
	)
	operation_section.add_child(efficiency_row)

	operation_section.add_child(HSeparator.new())

	connection_operation_section = VBoxContainer.new()
	connection_operation_section.visible = false
	root.add_child(connection_operation_section)

	var connection_operation_title := (
		UIWidgets.create_section_header("Connection Control")
	)
	connection_operation_section.add_child(
		connection_operation_title
	)

	connection_enabled_check_box = CheckBox.new()
	connection_enabled_check_box.text = "Enabled"
	connection_enabled_check_box.toggled.connect(
		_on_connection_enabled_toggled
	)
	connection_operation_section.add_child(
		connection_enabled_check_box
	)

	var capacity_row := HBoxContainer.new()
	connection_operation_section.add_child(capacity_row)

	var capacity_label := Label.new()
	capacity_label.text = "Capacity"
	capacity_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	capacity_row.add_child(capacity_label)

	connection_capacity_spin_box = SpinBox.new()
	connection_capacity_spin_box.custom_minimum_size = (
		Vector2(130, 0)
	)
	connection_capacity_spin_box.min_value = 0.05
	connection_capacity_spin_box.max_value = 10.0
	connection_capacity_spin_box.step = 0.05
	connection_capacity_spin_box.value_changed.connect(
		_on_connection_capacity_changed
	)
	capacity_row.add_child(connection_capacity_spin_box)

	connection_operation_section.add_child(HSeparator.new())

	input_title = UIWidgets.create_section_header("Inputs")
	root.add_child(input_title)

	input_list = VBoxContainer.new()
	root.add_child(input_list)

	root.add_child(HSeparator.new())

	output_title = UIWidgets.create_section_header("Outputs")
	root.add_child(output_title)

	output_list = VBoxContainer.new()
	root.add_child(output_list)

	root.add_child(HSeparator.new())

	inventory_title = UIWidgets.create_section_header("Inventory")
	root.add_child(inventory_title)

	inventory_list = VBoxContainer.new()
	root.add_child(inventory_list)


func bind_refresh_manager(manager: RefreshManager) -> void:
	refresh_manager = manager


func bind_history(new_history: EditorHistory) -> void:
	history = new_history


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		_disconnect_factory_signals()

	factory = new_factory
	selected_machine = null
	selected_connection = null
	_request_refresh()

	if factory == null:
		return

	factory.event_bus.machine_state_changed.connect(
		_on_machine_changed
	)
	factory.event_bus.machine_inventory_changed.connect(
		_on_machine_changed
	)
	factory.event_bus.machine_settings_changed.connect(
		_on_machine_changed
	)
	factory.event_bus.machine_performance_changed.connect(
		_on_machine_performance_changed
	)
	factory.event_bus.connection_flow_changed.connect(
		_on_connection_changed
	)
	factory.event_bus.connection_settings_changed.connect(
		_on_connection_changed
	)
	factory.event_bus.connection_removed.connect(
		_on_connection_removed
	)
	factory.event_bus.machine_removed.connect(
		_on_machine_removed
	)


func show_machine(machine: MachineModel) -> void:
	selected_machine = machine
	selected_connection = null
	_request_refresh()


func show_connection(connection: ConnectionModel) -> void:
	selected_connection = connection
	selected_machine = null
	_request_refresh()


func _disconnect_factory_signals() -> void:
	var state_callback := Callable(
		self,
		"_on_machine_changed"
	)
	var inventory_callback := Callable(
		self,
		"_on_machine_changed"
	)
	var settings_callback := Callable(
		self,
		"_on_machine_changed"
	)
	var removed_callback := Callable(
		self,
		"_on_machine_removed"
	)
	var performance_callback := Callable(
		self,
		"_on_machine_performance_changed"
	)
	var connection_callback := Callable(
		self,
		"_on_connection_changed"
	)
	var connection_removed_callback := Callable(
		self,
		"_on_connection_removed"
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

	if factory.event_bus.machine_settings_changed.is_connected(
		settings_callback
	):
		factory.event_bus.machine_settings_changed.disconnect(
			settings_callback
		)

	if factory.event_bus.machine_performance_changed.is_connected(
		performance_callback
	):
		factory.event_bus.machine_performance_changed.disconnect(
			performance_callback
		)

	if factory.event_bus.machine_removed.is_connected(
		removed_callback
	):
		factory.event_bus.machine_removed.disconnect(
			removed_callback
		)

	if factory.event_bus.connection_flow_changed.is_connected(
		connection_callback
	):
		factory.event_bus.connection_flow_changed.disconnect(
			connection_callback
		)

	if factory.event_bus.connection_settings_changed.is_connected(
		connection_callback
	):
		factory.event_bus.connection_settings_changed.disconnect(
			connection_callback
		)

	if factory.event_bus.connection_removed.is_connected(
		connection_removed_callback
	):
		factory.event_bus.connection_removed.disconnect(
			connection_removed_callback
		)


func _on_machine_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_request_refresh()


func _on_machine_performance_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_performance_labels()


func _on_machine_removed(machine_id: String) -> void:
	if (
		selected_machine != null
		and selected_machine.instance_id == machine_id
	):
		selected_machine = null
		_request_refresh()


func _on_connection_changed(connection: ConnectionModel) -> void:
	if connection == selected_connection:
		_request_refresh()


func _on_connection_removed(connection: ConnectionModel) -> void:
	if connection == selected_connection:
		selected_connection = null
		_request_refresh()


func _request_refresh() -> void:
	if refresh_manager == null:
		_refresh()
		return

	refresh_manager.request_refresh(
		&"machine_inspector",
		_refresh
	)


func _refresh() -> void:
	UIWidgets.clear_container(input_list)
	UIWidgets.clear_container(output_list)
	UIWidgets.clear_container(inventory_list)

	if selected_connection != null:
		_refresh_connection()
		return

	if selected_machine == null:
		set_dock_title("Inspector")
		operation_section.visible = false
		connection_operation_section.visible = false
		input_title.text = "Inputs"
		output_title.text = "Outputs"
		inventory_title.text = "Inventory"
		updating_controls = true
		name_label.text = "No machine selected"
		id_label.text = ""
		enabled_check_box.button_pressed = false
		enabled_check_box.disabled = true
		operating_rate_spin_box.value = 0.0
		operating_rate_spin_box.editable = false
		actual_rate_value_label.text = "0%"
		effective_rate_value_label.text = "0%"
		efficiency_value_label.text = "—"
		updating_controls = false
		UIWidgets.update_status_badge(
			state_badge,
			"No selection",
			ThemeManager.COLOR_TEXT_MUTED
		)

		_add_empty_label(input_list)
		_add_empty_label(output_list)
		_add_empty_label(inventory_list)
		return

	set_dock_title("Machine Inspector")
	operation_section.visible = true
	connection_operation_section.visible = false
	input_title.text = "Inputs"
	output_title.text = "Outputs"
	inventory_title.text = "Inventory"
	name_label.text = selected_machine.display_name
	id_label.text = "ID: %s" % selected_machine.instance_id
	updating_controls = true
	enabled_check_box.disabled = false
	enabled_check_box.button_pressed = selected_machine.enabled
	operating_rate_spin_box.editable = true
	operating_rate_spin_box.value = (
		selected_machine.operating_rate * 100.0
	)
	_update_performance_labels()
	updating_controls = false
	UIWidgets.update_status_badge(
		state_badge,
		_state_text(selected_machine.state),
		_state_color(selected_machine.state)
	)

	_populate_resource_section(
		input_list,
		selected_machine.definition.get("inputs", [])
	)
	_populate_resource_section(
		output_list,
		selected_machine.definition.get("outputs", [])
	)
	_populate_inventory()


func _update_performance_labels() -> void:
	if (
		actual_rate_value_label == null
		or effective_rate_value_label == null
		or efficiency_value_label == null
	):
		return

	if selected_machine == null:
		actual_rate_value_label.text = "0%"
		effective_rate_value_label.text = "0%"
		efficiency_value_label.text = "—"
		return

	actual_rate_value_label.text = "%.0f%%" % (
		selected_machine.actual_operating_rate * 100.0
	)
	effective_rate_value_label.text = "%.0f%%" % (
		selected_machine.get_effective_production_rate() * 100.0
	)
	if selected_machine.actual_operating_rate > 0.0:
		efficiency_value_label.text = "%.0f%%" % (
			selected_machine.get_production_efficiency() * 100.0
		)
	else:
		efficiency_value_label.text = "—"


func _refresh_connection() -> void:
	set_dock_title("Connection Inspector")
	operation_section.visible = false
	connection_operation_section.visible = true
	input_title.text = "Endpoints"
	output_title.text = "Flow"
	inventory_title.text = "Configuration"

	var source := selected_connection.from_machine
	var destination := selected_connection.to_machine
	var resource_id := selected_connection.resource_id
	var unit := ResourceRegistry.get_unit(resource_id)

	updating_controls = true
	connection_enabled_check_box.button_pressed = (
		selected_connection.enabled
	)
	connection_capacity_spin_box.value = (
		selected_connection.capacity_per_second
	)
	connection_capacity_spin_box.suffix = " %s/s" % unit
	updating_controls = false

	name_label.text = ResourceRegistry.get_display_name(
		resource_id
	)
	id_label.text = "%s → %s" % [
		source.display_name,
		destination.display_name
	]
	UIWidgets.update_status_badge(
		state_badge,
		"Enabled" if selected_connection.enabled else "Disabled",
		(
			ThemeManager.COLOR_SUCCESS
			if selected_connection.enabled
			else ThemeManager.COLOR_TEXT_MUTED
		)
	)

	input_list.add_child(
		UIWidgets.create_labeled_value(
			"Source",
			source.display_name
		)
	)
	input_list.add_child(
		UIWidgets.create_labeled_value(
			"Destination",
			destination.display_name
		)
	)
	output_list.add_child(
		UIWidgets.create_labeled_value(
			"Resource",
			ResourceRegistry.get_display_name(resource_id)
		)
	)
	output_list.add_child(
		UIWidgets.create_labeled_value(
			"Current rate",
			"%.2f %s/s" % [
				selected_connection.current_rate_per_second,
				unit
			]
		)
	)
	inventory_list.add_child(
		UIWidgets.create_labeled_value(
			"Capacity",
			"%.2f %s/s" % [
				selected_connection.capacity_per_second,
				unit
			]
		)
	)
	inventory_list.add_child(
		UIWidgets.create_labeled_value(
			"Enabled",
			"Yes" if selected_connection.enabled else "No"
		)
	)


func _on_connection_enabled_toggled(value: bool) -> void:
	if updating_controls or selected_connection == null:
		return

	var previous_value := selected_connection.enabled
	var label := (
		"enable connection"
		if value
		else "disable connection"
	)
	_execute_setting_action(
		label,
		selected_connection.set_enabled.bind(value),
		selected_connection.set_enabled.bind(previous_value)
	)


func _on_connection_capacity_changed(value: float) -> void:
	if updating_controls or selected_connection == null:
		return

	var previous_value := (
		selected_connection.capacity_per_second
	)

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set connection capacity",
		selected_connection.set_capacity_per_second.bind(value),
		selected_connection.set_capacity_per_second.bind(
			previous_value
		)
	)


func _execute_setting_action(
	label: String,
	do_action: Callable,
	undo_action: Callable
) -> void:
	if history == null:
		do_action.call()
		return

	history.execute(label, do_action, undo_action)


func _on_enabled_toggled(enabled: bool) -> void:
	if updating_controls or selected_machine == null:
		return

	selected_machine.set_enabled(enabled)


func _on_operating_rate_changed(percent: float) -> void:
	if updating_controls or selected_machine == null:
		return

	selected_machine.set_operating_rate(percent / 100.0)


func _populate_resource_section(
	container: VBoxContainer,
	entries: Array
) -> void:
	if entries.is_empty():
		_add_empty_label(container)
		return

	for value: Variant in entries:
		var entry := value as Dictionary
		var resource_id := str(entry.get("resource", ""))

		if resource_id.is_empty():
			continue

		var resource_label := Label.new()
		resource_label.text = _resource_display_name(resource_id)
		container.add_child(resource_label)

	if container.get_child_count() == 0:
		_add_empty_label(container)


func _populate_inventory() -> void:
	var resource_ids: Array = (
		selected_machine.inventory.capacities.keys()
	)
	resource_ids.sort()

	if resource_ids.is_empty():
		_add_empty_label(inventory_list)
		return

	for value: Variant in resource_ids:
		var resource_id := str(value)
		var amount := selected_machine.inventory.get_amount(
			resource_id
		)
		var capacity := selected_machine.inventory.get_capacity(
			resource_id
		)

		var row := UIWidgets.create_labeled_value(
			_resource_display_name(resource_id),
			"%.1f / %.1f" % [amount, capacity]
		)
		inventory_list.add_child(row)


func _add_empty_label(container: VBoxContainer) -> void:
	container.add_child(UIWidgets.create_empty_label())


func _resource_display_name(resource_id: String) -> String:
	return resource_id.replace("_", " ").capitalize()


func _state_text(state: MachineModel.State) -> String:
	return (
		MachineModel.State.keys()[state]
		as String
	).capitalize()


func _state_color(state: MachineModel.State) -> Color:
	match state:
		MachineModel.State.RUNNING:
			return ThemeManager.COLOR_SUCCESS
		MachineModel.State.BLOCKED_INPUT:
			return ThemeManager.COLOR_WARNING
		MachineModel.State.BLOCKED_OUTPUT:
			return ThemeManager.COLOR_WARNING
		MachineModel.State.DISABLED:
			return ThemeManager.COLOR_DANGER
		_:
			return ThemeManager.COLOR_ACCENT
