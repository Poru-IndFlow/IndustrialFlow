extends PanelContainer


var factory: FactoryModel
var selected_machine: MachineModel
var name_label: Label
var id_label: Label
var state_label: Label
var inventory_list: VBoxContainer


func _ready() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var title := Label.new()
	title.text = "Machine Inspector"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	root.add_child(HSeparator.new())

	name_label = Label.new()
	name_label.text = "No machine selected"
	root.add_child(name_label)

	id_label = Label.new()
	root.add_child(id_label)

	state_label = Label.new()
	root.add_child(state_label)

	root.add_child(HSeparator.new())

	var inventory_title := Label.new()
	inventory_title.text = "Inventory"
	root.add_child(inventory_title)

	inventory_list = VBoxContainer.new()
	root.add_child(inventory_list)


func bind_factory(new_factory: FactoryModel) -> void:
	if factory != null:
		var state_callback := Callable(
			self,
			"_on_machine_changed"
		)
		var inventory_callback := Callable(
			self,
			"_on_machine_changed"
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


func show_machine(machine: MachineModel) -> void:
	selected_machine = machine
	_refresh()


func _on_machine_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_refresh()


func _refresh() -> void:
	for child: Node in inventory_list.get_children():
		child.queue_free()

	if selected_machine == null:
		name_label.text = "No machine selected"
		id_label.text = ""
		state_label.text = ""
		return

	name_label.text = selected_machine.display_name
	id_label.text = "ID: %s" % selected_machine.instance_id
	state_label.text = "State: %s" % (
		MachineModel.State.keys()[selected_machine.state]
		as String
	).capitalize()

	var resource_ids: Array = (
		selected_machine.inventory.capacities.keys()
	)
	resource_ids.sort()

	if resource_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "None"
		inventory_list.add_child(empty_label)
		return

	for value: Variant in resource_ids:
		var resource_id := str(value)
		var amount := selected_machine.inventory.get_amount(
			resource_id
		)
		var capacity := selected_machine.inventory.get_capacity(
			resource_id
		)

		var inventory_label := Label.new()
		inventory_label.text = "%s: %.1f / %.1f" % [
			resource_id.replace("_", " ").capitalize(),
			amount,
			capacity
		]
		inventory_list.add_child(inventory_label)