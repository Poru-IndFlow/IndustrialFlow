extends DockPanel


var factory: FactoryModel
var selected_machine: MachineModel
var refresh_manager: RefreshManager

var name_label: Label
var id_label: Label
var state_badge: Label
var enabled_check_box: CheckBox
var operating_rate_spin_box: SpinBox
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

	var operation_title := UIWidgets.create_section_header(
		"Operation"
	)
	root.add_child(operation_title)

	enabled_check_box = CheckBox.new()
	enabled_check_box.text = "Enabled"
	enabled_check_box.toggled.connect(_on_enabled_toggled)
	root.add_child(enabled_check_box)

	var rate_row := HBoxContainer.new()
	root.add_child(rate_row)

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

	root.add_child(HSeparator.new())

	var input_title := UIWidgets.create_section_header("Inputs")
	root.add_child(input_title)

	input_list = VBoxContainer.new()
	root.add_child(input_list)

	root.add_child(HSeparator.new())

	var output_title := UIWidgets.create_section_header("Outputs")
	root.add_child(output_title)

	output_list = VBoxContainer.new()
	root.add_child(output_list)

	root.add_child(HSeparator.new())

	var inventory_title := UIWidgets.create_section_header("Inventory")
	root.add_child(inventory_title)

	inventory_list = VBoxContainer.new()
	root.add_child(inventory_list)


func bind_refresh_manager(manager: RefreshManager) -> void:
	refresh_manager = manager


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		_disconnect_factory_signals()

	factory = new_factory
	selected_machine = null
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
	factory.event_bus.machine_removed.connect(
		_on_machine_removed
	)


func show_machine(machine: MachineModel) -> void:
	selected_machine = machine
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

	if factory.event_bus.machine_removed.is_connected(
		removed_callback
	):
		factory.event_bus.machine_removed.disconnect(
			removed_callback
		)


func _on_machine_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_request_refresh()


func _on_machine_removed(machine_id: String) -> void:
	if (
		selected_machine != null
		and selected_machine.instance_id == machine_id
	):
		selected_machine = null
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

	if selected_machine == null:
		updating_controls = true
		name_label.text = "No machine selected"
		id_label.text = ""
		enabled_check_box.button_pressed = false
		enabled_check_box.disabled = true
		operating_rate_spin_box.value = 0.0
		operating_rate_spin_box.editable = false
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

	name_label.text = selected_machine.display_name
	id_label.text = "ID: %s" % selected_machine.instance_id
	updating_controls = true
	enabled_check_box.disabled = false
	enabled_check_box.button_pressed = selected_machine.enabled
	operating_rate_spin_box.editable = true
	operating_rate_spin_box.value = (
		selected_machine.operating_rate * 100.0
	)
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
