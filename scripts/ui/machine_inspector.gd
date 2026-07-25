extends PanelContainer


var factory: FactoryModel
var selected_machine: MachineModel

var name_label: Label
var id_label: Label
var state_label: Label
var input_list: VBoxContainer
var output_list: VBoxContainer
var inventory_list: VBoxContainer


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Machine Inspector"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	root.add_child(HSeparator.new())

	name_label = Label.new()
	name_label.text = "No machine selected"
	name_label.add_theme_font_size_override("font_size", 16)
	root.add_child(name_label)

	id_label = Label.new()
	root.add_child(id_label)

	state_label = Label.new()
	root.add_child(state_label)

	root.add_child(HSeparator.new())

	var input_title := Label.new()
	input_title.text = "Inputs"
	input_title.add_theme_font_size_override("font_size", 15)
	root.add_child(input_title)

	input_list = VBoxContainer.new()
	root.add_child(input_list)

	root.add_child(HSeparator.new())

	var output_title := Label.new()
	output_title.text = "Outputs"
	output_title.add_theme_font_size_override("font_size", 15)
	root.add_child(output_title)

	output_list = VBoxContainer.new()
	root.add_child(output_list)

	root.add_child(HSeparator.new())

	var inventory_title := Label.new()
	inventory_title.text = "Inventory"
	inventory_title.add_theme_font_size_override("font_size", 15)
	root.add_child(inventory_title)

	inventory_list = VBoxContainer.new()
	root.add_child(inventory_list)


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		_disconnect_factory_signals()

	factory = new_factory
	selected_machine = null
	_refresh()

	if factory == null:
		return

	factory.event_bus.machine_state_changed.connect(
		_on_machine_changed
	)
	factory.event_bus.machine_inventory_changed.connect(
		_on_machine_changed
	)
	factory.event_bus.machine_removed.connect(
		_on_machine_removed
	)


func show_machine(machine: MachineModel) -> void:
	selected_machine = machine
	_refresh()


func _disconnect_factory_signals() -> void:
	var state_callback := Callable(
		self,
		"_on_machine_changed"
	)
	var inventory_callback := Callable(
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

	if factory.event_bus.machine_removed.is_connected(
		removed_callback
	):
		factory.event_bus.machine_removed.disconnect(
			removed_callback
		)


func _on_machine_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_refresh()


func _on_machine_removed(machine_id: String) -> void:
	if (
		selected_machine != null
		and selected_machine.instance_id == machine_id
	):
		selected_machine = null
		_refresh()


func _refresh() -> void:
	_clear_container(input_list)
	_clear_container(output_list)
	_clear_container(inventory_list)

	if selected_machine == null:
		name_label.text = "No machine selected"
		id_label.text = ""
		state_label.text = ""

		_add_empty_label(input_list)
		_add_empty_label(output_list)
		_add_empty_label(inventory_list)
		return

	name_label.text = selected_machine.display_name
	id_label.text = "ID: %s" % selected_machine.instance_id
	state_label.text = "State: %s" % _state_text(
		selected_machine.state
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

		var row := HBoxContainer.new()
		inventory_list.add_child(row)

		var resource_label := Label.new()
		resource_label.text = _resource_display_name(resource_id)
		resource_label.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)
		row.add_child(resource_label)

		var quantity_label := Label.new()
		quantity_label.text = "%.1f / %.1f" % [
			amount,
			capacity
		]
		quantity_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT
		)
		row.add_child(quantity_label)


func _clear_container(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		child.queue_free()


func _add_empty_label(container: VBoxContainer) -> void:
	var empty_label := Label.new()
	empty_label.text = "None"
	empty_label.modulate = Color(0.65, 0.65, 0.65)
	container.add_child(empty_label)


func _resource_display_name(resource_id: String) -> String:
	return resource_id.replace("_", " ").capitalize()


func _state_text(state: MachineModel.State) -> String:
	return (
		MachineModel.State.keys()[state]
		as String
	).capitalize()