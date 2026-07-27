extends DockPanel


signal machine_requested(definition_id: String)


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
		var button := UIWidgets.create_action_button(
			str(
				definition.get(
					"display_name",
					definition_id.capitalize()
				)
			),
			str(definition.get("description", ""))
		)
		button.pressed.connect(
			_on_machine_button_pressed.bind(definition_id)
		)
		machine_list.add_child(button)


func _on_machine_button_pressed(definition_id: String) -> void:
	machine_requested.emit(definition_id)
