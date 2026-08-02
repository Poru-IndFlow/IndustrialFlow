class_name ProductionPlanning
extends VBoxContainer


var factory: FactoryModel
var refresh_elapsed := 0.0

@onready var build_label := %BuildLabel as Label
@onready var summary_label := %SummaryLabel as Label
@onready var resource_option := %ResourceOption as OptionButton
@onready var quantity_spin_box := %QuantitySpinBox as SpinBox
@onready var add_target_button := %AddTargetButton as Button
@onready var target_list := %TargetList as VBoxContainer


func _ready() -> void:
	build_label.text = BuildInfo.get_display_string()
	_populate_resources()
	add_target_button.pressed.connect(_on_add_target_pressed)
	_refresh(true)


func bind_factory(new_factory: FactoryModel) -> void:
	_disconnect_factory()
	factory = new_factory
	refresh_elapsed = 0.0

	if factory != null and factory.event_bus != null:
		factory.event_bus.production_targets_changed.connect(
			_on_targets_changed
		)

	_refresh(true)


func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	refresh_elapsed += delta_seconds

	if refresh_elapsed >= 1.0:
		refresh_elapsed = fmod(refresh_elapsed, 1.0)
		_refresh()


func _disconnect_factory() -> void:
	if factory == null or factory.event_bus == null:
		return

	var callback := Callable(self, "_on_targets_changed")

	if factory.event_bus.production_targets_changed.is_connected(callback):
		factory.event_bus.production_targets_changed.disconnect(callback)


func _populate_resources() -> void:
	resource_option.clear()

	for definition: Dictionary in ResourceRegistry.get_all_definitions():
		var resource_id := str(definition.get("id", ""))

		if resource_id.is_empty():
			continue

		resource_option.add_item(
			str(definition.get("display_name", resource_id.capitalize()))
		)
		resource_option.set_item_metadata(
			resource_option.item_count - 1,
			resource_id
		)

	add_target_button.disabled = resource_option.item_count == 0


func _on_add_target_pressed() -> void:
	if factory == null or resource_option.selected < 0:
		return

	var resource_id := str(
		resource_option.get_item_metadata(resource_option.selected)
	)
	factory.add_production_target(resource_id, quantity_spin_box.value)


func _on_targets_changed(_factory: FactoryModel) -> void:
	_refresh(true)


func _refresh(force: bool = false) -> void:
	if target_list == null or summary_label == null:
		return

	if not force and _is_remove_button_hovered():
		return

	UIWidgets.clear_container(target_list)

	if factory == null or factory.production_targets.is_empty():
		summary_label.text = "No production targets"
		target_list.add_child(
			UIWidgets.create_empty_label(
				"Add a resource quantity to begin production planning."
			)
		)
		return

	var complete_count := 0

	for target: Dictionary in factory.production_targets:
		if float(target["produced_quantity"]) >= float(target["target_quantity"]):
			complete_count += 1

		_add_target_row(target)

	summary_label.text = "%d active • %d complete" % [
		factory.production_targets.size() - complete_count,
		complete_count
	]


func _is_remove_button_hovered() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return (
		hovered is Button
		and (hovered as Button).text == "Remove"
		and target_list.is_ancestor_of(hovered)
	)


func _add_target_row(target: Dictionary) -> void:
	var resource_id := str(target["resource_id"])
	var target_quantity := float(target["target_quantity"])
	var produced_quantity := float(target["produced_quantity"])
	var gross_rate := _get_resource_rate(resource_id, true)
	var consumption_rate := _get_resource_rate(resource_id, false)
	var net_rate := gross_rate - consumption_rate
	var remaining := maxf(target_quantity - produced_quantity, 0.0)
	var unit := ResourceRegistry.get_unit(resource_id)
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	var content := VBoxContainer.new()
	var heading := HBoxContainer.new()
	var title := Label.new()
	var remove_button := Button.new()
	var progress := ProgressBar.new()
	var details := Label.new()
	var diagnosis := Label.new()

	target_list.add_child(panel)
	panel.add_child(margin)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_child(content)
	content.add_child(heading)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "%s — %.1f %s target" % [
		ResourceRegistry.get_display_name(resource_id),
		target_quantity,
		unit
	]
	heading.add_child(title)
	remove_button.text = "Remove"
	remove_button.pressed.connect(
		_on_remove_target_pressed.bind(int(target["id"]))
	)
	heading.add_child(remove_button)
	progress.max_value = target_quantity
	progress.value = produced_quantity
	progress.show_percentage = true
	content.add_child(progress)

	if remaining <= 0.0:
		details.text = "Completed %.1f / %.1f %s • Target progress is now locked" % [
			produced_quantity,
			target_quantity,
			unit
		]
		content.add_child(details)
		diagnosis.text = "Target achieved"
		diagnosis.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_SUCCESS
		)
		content.add_child(diagnosis)
		return

	details.text = (
		"Produced %.1f / %.1f %s • Gross %.2f %s/s • Consumption %.2f %s/s • Net %+.2f %s/s • ETA %s"
		% [
			produced_quantity,
			target_quantity,
			unit,
			gross_rate,
			unit,
			consumption_rate,
			unit,
			net_rate,
			unit,
			_format_eta(remaining, gross_rate)
		]
	)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	diagnosis.text = _get_bottleneck_text(resource_id, gross_rate)
	diagnosis.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_WARNING
	)
	content.add_child(diagnosis)


func _on_remove_target_pressed(target_id: int) -> void:
	if factory != null:
		factory.remove_production_target(target_id)


func _get_resource_rate(resource_id: String, production: bool) -> float:
	var total := 0.0

	if factory == null:
		return total

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		var rates: Dictionary = (
			machine.production_rates_per_second
			if production
			else machine.consumption_rates_per_second
		)
		total += float(rates.get(resource_id, 0.0))

	return total


func _get_bottleneck_text(resource_id: String, gross_rate: float) -> String:
	var producers: Array[MachineModel] = []

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine != null and _machine_outputs(machine, resource_id):
			producers.append(machine)

	if producers.is_empty():
		return "Bottleneck: no installed machine produces this resource"

	for machine: MachineModel in producers:
		if machine.is_failed():
			return "Bottleneck: %s has failed" % machine.display_name
		if machine.is_under_maintenance():
			return "Bottleneck: %s is under maintenance" % machine.display_name
		if not machine.enabled:
			return "Bottleneck: %s is disabled" % machine.display_name
		if machine.state == MachineModel.State.BLOCKED_INPUT:
			return "Bottleneck: %s is waiting for input" % machine.display_name
		if machine.state == MachineModel.State.BLOCKED_OUTPUT:
			return "Bottleneck: %s has blocked output" % machine.display_name

	if gross_rate <= 0.0:
		return "Bottleneck: installed producers currently have no measured output"

	var limiting := producers[0]

	for machine: MachineModel in producers:
		if machine.actual_operating_rate < limiting.actual_operating_rate:
			limiting = machine

	return "Limiting producer: %s at %.0f%% actual speed" % [
		limiting.display_name,
		limiting.actual_operating_rate * 100.0
	]


func _machine_outputs(machine: MachineModel, resource_id: String) -> bool:
	var outputs: Array = machine.definition.get("outputs", [])

	for value: Variant in outputs:
		if str((value as Dictionary).get("resource", "")) == resource_id:
			return true

	return false


func _format_eta(remaining: float, gross_rate: float) -> String:
	if remaining <= 0.0:
		return "Complete"
	if gross_rate <= 0.000001:
		return "No current output"

	var seconds := remaining / gross_rate
	var total_seconds := maxi(0, int(ceil(seconds)))
	var hours := floori(float(total_seconds) / 3600.0)
	var minutes := floori(float(total_seconds % 3600) / 60.0)
	var remaining_seconds := total_seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]
