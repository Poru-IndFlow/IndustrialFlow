class_name ControllerTrends
extends VBoxContainer


const SAMPLE_INTERVAL_SECONDS := 0.5
const MAX_SAMPLES := 240

var factory: FactoryModel
var selected_machine: MachineModel
var samples: Array[Dictionary] = []
var sample_elapsed := 0.0
var total_elapsed := 0.0
var paused := false

var machine_label: Label
var status_label: Label
var pause_button: Button
var plot: ControllerTrendPlot
var inventory_value_label: Label
var setpoint_value_label: Label
var error_value_label: Label
var output_value_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_interface()
	_update_selection_display()


func bind_factory(new_factory: FactoryModel) -> void:
	factory = new_factory
	show_machine(null)


func show_machine(machine: MachineModel) -> void:
	selected_machine = machine
	_clear_samples()
	_update_selection_display()


func advance(delta_seconds: float) -> void:
	if (
		selected_machine != null
		and (
			factory == null
			or (
				factory.get_machine(selected_machine.instance_id)
				!= selected_machine
			)
		)
	):
		show_machine(null)
		return

	if (
		paused
		or selected_machine == null
		or not selected_machine.supports_inventory_control()
		or delta_seconds <= 0.0
	):
		return

	sample_elapsed += delta_seconds
	total_elapsed += delta_seconds

	if sample_elapsed < SAMPLE_INTERVAL_SECONDS:
		return

	sample_elapsed = fmod(
		sample_elapsed,
		SAMPLE_INTERVAL_SECONDS
	)
	samples.append({
		"time": total_elapsed,
		"inventory": selected_machine.controlled_inventory_amount,
		"setpoint": selected_machine.inventory_setpoint,
		"error": selected_machine.controller_error,
		"output": selected_machine.operating_rate * 100.0
	})

	if samples.size() > MAX_SAMPLES:
		samples.pop_front()

	_update_live_values()
	_update_plot()


func _build_interface() -> void:
	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = "Controller Trends"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.toggle_mode = true
	pause_button.toggled.connect(_on_pause_toggled)
	header.add_child(pause_button)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(clear_button)

	machine_label = Label.new()
	machine_label.add_theme_font_size_override("font_size", 15)
	add_child(machine_label)

	status_label = Label.new()
	status_label.modulate = ThemeManager.COLOR_TEXT_MUTED
	add_child(status_label)

	var values := HBoxContainer.new()
	values.add_theme_constant_override("separation", 18)
	add_child(values)

	inventory_value_label = _add_value(values, "Inventory")
	setpoint_value_label = _add_value(values, "Setpoint")
	error_value_label = _add_value(values, "Error")
	output_value_label = _add_value(values, "Output")

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 18)
	add_child(legend)
	_add_legend(
		legend,
		"Inventory",
		ControllerTrendPlot.COLOR_INVENTORY
	)
	_add_legend(
		legend,
		"Setpoint",
		ControllerTrendPlot.COLOR_SETPOINT
	)
	_add_legend(
		legend,
		"Error",
		ControllerTrendPlot.COLOR_ERROR
	)
	_add_legend(
		legend,
		"Output",
		ControllerTrendPlot.COLOR_OUTPUT
	)

	plot = ControllerTrendPlot.new()
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(plot)


func _add_value(parent: HBoxContainer, label_text: String) -> Label:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(group)

	var label := Label.new()
	label.text = label_text
	label.modulate = ThemeManager.COLOR_TEXT_MUTED
	group.add_child(label)

	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", 16)
	group.add_child(value)
	return value


func _add_legend(
	parent: HBoxContainer,
	label_text: String,
	color: Color
) -> void:
	var label := Label.new()
	label.text = "● %s" % label_text
	label.modulate = color
	parent.add_child(label)


func _update_selection_display() -> void:
	if selected_machine == null:
		machine_label.text = "No machine selected"
		status_label.text = (
			"Select a machine with inventory control."
		)
		_reset_live_values()
		_update_plot()
		return

	machine_label.text = selected_machine.display_name

	if not selected_machine.supports_inventory_control():
		status_label.text = (
			"This machine does not have an inventory controller."
		)
		_reset_live_values()
		_update_plot()
		return

	status_label.text = _get_active_status_text()
	_update_live_values()
	_update_plot()


func _update_live_values() -> void:
	if selected_machine == null:
		_reset_live_values()
		return

	var unit := ResourceRegistry.get_unit(
		selected_machine.control_resource
	)
	inventory_value_label.text = "%.1f %s" % [
		selected_machine.controlled_inventory_amount,
		unit
	]
	setpoint_value_label.text = "%.1f %s" % [
		selected_machine.inventory_setpoint,
		unit
	]
	error_value_label.text = "%.1f %s" % [
		selected_machine.controller_error,
		unit
	]
	output_value_label.text = "%.0f%%" % (
		selected_machine.operating_rate * 100.0
	)


func _reset_live_values() -> void:
	inventory_value_label.text = "—"
	setpoint_value_label.text = "—"
	error_value_label.text = "—"
	output_value_label.text = "—"


func _update_plot() -> void:
	var unit := ""

	if selected_machine != null:
		unit = ResourceRegistry.get_unit(
			selected_machine.control_resource
		)

	plot.set_samples(samples, unit)


func _clear_samples() -> void:
	samples.clear()
	sample_elapsed = 0.0
	total_elapsed = 0.0


func _on_pause_toggled(value: bool) -> void:
	paused = value
	pause_button.text = "Resume" if paused else "Pause"
	status_label.text = _get_active_status_text()


func _on_clear_pressed() -> void:
	_clear_samples()
	_update_plot()


func _get_active_status_text() -> String:
	return (
		"Trend paused."
		if paused
		else "Rolling 120-second history • 0.5-second samples"
	)
