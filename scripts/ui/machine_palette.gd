extends DockPanel


signal machine_requested(definition_id: String)

var factory: FactoryModel
var machine_buttons: Dictionary = {}


func _ready() -> void:
	dock_title = "Machines"
	super._ready()

	var root := VBoxContainer.new()
	get_content_root().add_child(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var machine_list := VBoxContainer.new()
	machine_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(machine_list)

	var definitions: Array[Dictionary] = (
		MachineRegistry.get_all_definitions()
	)
	var current_category := ""

	for definition: Dictionary in definitions:
		var category := str(definition.get("category", "other"))

		if category != current_category:
			current_category = category

			var category_label := UIWidgets.create_section_header(
				category.capitalize()
			)
			machine_list.add_child(category_label)

		var definition_id := str(definition.get("id", ""))
		var purchase_cost := maxf(
			0.0,
			float(definition.get("purchase_cost", 0.0))
		)
		var display_name := str(
			definition.get(
				"display_name",
				definition_id.capitalize()
			)
		)
		var footprint: Array = definition.get("grid_footprint", [4, 4])
		var footprint_text := "%d × %d" % [
			int(footprint[0]),
			int(footprint[1])
		]
		var button := UIWidgets.create_action_button(
			"%s  ·  %s  ·  $%.0f" % [display_name, footprint_text, purchase_cost],
			"%s\nFootprint: %s grid cells\nConstruction price: $%.2f" % [
				str(definition.get("description", "")),
				footprint_text,
				purchase_cost
			]
		)
		button.pressed.connect(
			_on_machine_button_pressed.bind(definition_id)
		)
		machine_list.add_child(button)
		machine_buttons[definition_id] = button

	_update_affordability()


func bind_factory(new_factory: FactoryModel) -> void:
	var callback := Callable(self, "_on_economy_changed")

	if factory != null and factory.event_bus != null:
		if factory.event_bus.economy_changed.is_connected(callback):
			factory.event_bus.economy_changed.disconnect(callback)

	factory = new_factory

	if factory != null and factory.event_bus != null:
		if not factory.event_bus.economy_changed.is_connected(callback):
			factory.event_bus.economy_changed.connect(callback)

	_update_affordability()


func _on_economy_changed(_value: Variant) -> void:
	_update_affordability()


func _update_affordability() -> void:
	for key: Variant in machine_buttons.keys():
		var definition_id := str(key)
		var button := machine_buttons.get(definition_id) as Button

		if button == null:
			continue

		button.disabled = (
			factory != null
			and not factory.can_afford_machine(definition_id)
		)


func _on_machine_button_pressed(definition_id: String) -> void:
	machine_requested.emit(definition_id)
