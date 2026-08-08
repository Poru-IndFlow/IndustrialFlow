class_name ResearchWorkspace
extends ScrollContainer


var factory: FactoryModel
var cash_label: Label
var research_list: VBoxContainer


func _ready() -> void:
	_build_interface()
	_refresh()


func bind_factory(new_factory: FactoryModel) -> void:
	var research_callback := Callable(self, "_on_factory_changed")
	var economy_callback := Callable(self, "_on_factory_changed")

	if factory != null and factory.event_bus != null:
		if factory.event_bus.research_changed.is_connected(
			research_callback
		):
			factory.event_bus.research_changed.disconnect(
				research_callback
			)

		if factory.event_bus.economy_changed.is_connected(
			economy_callback
		):
			factory.event_bus.economy_changed.disconnect(
				economy_callback
			)

	factory = new_factory

	if factory != null and factory.event_bus != null:
		if not factory.event_bus.research_changed.is_connected(
			research_callback
		):
			factory.event_bus.research_changed.connect(
				research_callback
			)

		if not factory.event_bus.economy_changed.is_connected(
			economy_callback
		):
			factory.event_bus.economy_changed.connect(
				economy_callback
			)

	_refresh()


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	var title := Label.new()
	title.text = "Research"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Purchase independent ideas, then install them on individual machines."
	)
	subtitle.modulate = ThemeManager.COLOR_TEXT_MUTED
	content.add_child(subtitle)

	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 16)
	content.add_child(cash_label)
	content.add_child(HSeparator.new())

	research_list = VBoxContainer.new()
	research_list.add_theme_constant_override("separation", 10)
	research_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(research_list)


func _refresh() -> void:
	if not is_node_ready() or research_list == null:
		return

	cash_label.text = "Available cash: %s" % _format_currency(
		factory.cash_balance if factory != null else 0.0
	)
	UIWidgets.clear_container(research_list)
	var definitions := ResearchRegistry.get_all_definitions()

	if definitions.is_empty():
		research_list.add_child(
			UIWidgets.create_empty_label("No research ideas available.")
		)
		return

	for definition: Dictionary in definitions:
		_add_research_card(definition)


func _add_research_card(definition: Dictionary) -> void:
	var research_id := str(definition.get("id", ""))
	var researched := (
		factory != null and factory.is_researched(research_id)
	)
	var researching := (
		factory != null and factory.is_researching(research_id)
	)
	var cost := maxf(
		0.0,
		float(definition.get("research_cost", 0.0))
	)
	var duration := maxf(
		1.0,
		float(definition.get("research_duration_seconds", 60.0))
	)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_list.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)

	var name_label := Label.new()
	name_label.text = str(definition.get("display_name", research_id))
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var badge_text := "Available"
	var badge_color := ThemeManager.COLOR_ACCENT

	if researched:
		badge_text = "Complete"
		badge_color = ThemeManager.COLOR_SUCCESS
	elif researching:
		badge_text = "In Progress"
		badge_color = ThemeManager.COLOR_WARNING

	var badge := UIWidgets.create_status_badge(badge_text, badge_color)
	header.add_child(badge)

	var description := Label.new()
	description.text = str(definition.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)

	var target_id := str(definition.get("target_machine_id", ""))
	var installation_cost := maxf(
		0.0,
		float(definition.get("installation_cost", 0.0))
	)
	var installation_duration := maxf(
		0.1,
		float(definition.get("installation_duration_seconds", 30.0))
	)
	var details := Label.new()
	details.text = "Research %s · %.0f s · Install %s + %.0f s downtime per %s · %s" % [
		_format_currency(cost),
		duration,
		_format_currency(installation_cost),
		installation_duration,
		target_id.replace("_", " ").capitalize(),
		ResearchRegistry.get_effect_summary(definition)
	]
	details.modulate = ThemeManager.COLOR_TEXT_MUTED
	content.add_child(details)

	if researched and factory != null:
		var eligible_count := 0
		var installed_count := 0
		var installing_count := 0

		for value: Variant in factory.machines.values():
			var machine := value as MachineModel

			if (
				machine == null
				or not machine.placement_committed
				or machine.definition_id != target_id
			):
				continue

			eligible_count += 1

			if machine.has_upgrade(research_id):
				installed_count += 1
			elif machine.is_installing_upgrade(research_id):
				installing_count += 1

		var fleet_label := Label.new()
		fleet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		if eligible_count <= 0:
			fleet_label.text = "Fleet installation: no constructed %s machines" % (
				target_id.replace("_", " ").capitalize()
			)
		else:
			fleet_label.text = "Fleet installation: %d / %d installed" % [
				installed_count,
				eligible_count
			]

			if installing_count > 0:
				fleet_label.text += " · %d installing" % installing_count

		fleet_label.modulate = (
			ThemeManager.COLOR_SUCCESS
			if eligible_count > 0 and installed_count == eligible_count
			else ThemeManager.COLOR_TEXT_MUTED
		)
		content.add_child(fleet_label)

	if researching:
		var progress := ProgressBar.new()
		progress.min_value = 0.0
		progress.max_value = 100.0
		progress.value = factory.get_research_progress(research_id) * 100.0
		progress.show_percentage = true
		content.add_child(progress)

		var remaining_label := Label.new()
		remaining_label.text = "%.0f s remaining" % (
			factory.get_research_remaining_seconds(research_id)
		)
		remaining_label.modulate = ThemeManager.COLOR_TEXT_MUTED
		content.add_child(remaining_label)

	var button := Button.new()

	if researched:
		button.text = "Research Complete"
	elif researching:
		button.text = "Research In Progress"
	elif factory != null and factory.has_active_research():
		button.text = "Research Lab Busy"
	else:
		button.text = "Start Research — %s" % _format_currency(cost)

	button.disabled = (
		researched
		or researching
		or factory == null
		or not factory.can_research(research_id)
	)
	button.pressed.connect(_on_research_pressed.bind(research_id))
	content.add_child(button)


func _on_research_pressed(research_id: String) -> void:
	if factory != null:
		factory.research_idea(research_id)


func _on_factory_changed(_value: Variant) -> void:
	_refresh()


func _format_currency(amount: float) -> String:
	if amount < 0.0:
		return "-$%.2f" % absf(amount)

	return "$%.2f" % amount
