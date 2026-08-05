extends DockPanel


var factory: FactoryModel
var selected_machine: MachineModel
var selected_connection: ConnectionModel
var refresh_manager: RefreshManager
var history: EditorHistory

var name_label: Label
var id_label: Label
var state_badge: Label
var operator_summary: VBoxContainer
var mode_summary_value_label: Label
var sp_summary_value_label: Label
var pv_summary_value_label: Label
var co_summary_value_label: Label
var operation_section: VBoxContainer
var connection_operation_section: VBoxContainer
var enabled_check_box: CheckBox
var operating_rate_spin_box: SpinBox
var actual_rate_value_label: Label
var effective_rate_value_label: Label
var efficiency_value_label: Label
var power_demand_value_label: Label
var power_mode_value_label: Label
var batch_section: VBoxContainer
var batch_status_value_label: Label
var batch_progress_bar: ProgressBar
var batch_remaining_value_label: Label
var batch_count_value_label: Label
var batch_inputs_value_label: Label
var hold_after_batch_check_box: CheckBox
var maintenance_section: VBoxContainer
var condition_badge: Label
var condition_value_label: Label
var breakdown_risk_value_label: Label
var condition_efficiency_value_label: Label
var wear_power_value_label: Label
var operating_hours_value_label: Label
var maintenance_plan_value_label: Label
var maintenance_policy_check_box: CheckBox
var maintenance_policy_condition_spin_box: SpinBox
var maintenance_policy_cash_reserve_spin_box: SpinBox
var maintenance_policy_status_value_label: Label
var preventive_maintenance_value_label: Label
var emergency_repairs_value_label: Label
var maintenance_spend_value_label: Label
var downtime_value_label: Label
var maintenance_progress_bar: ProgressBar
var maintenance_button: Button
var upgrade_section: VBoxContainer
var upgrade_list: VBoxContainer
var control_section: VBoxContainer
var control_mode_option: OptionButton
var inventory_setpoint_spin_box: SpinBox
var controller_kp_spin_box: SpinBox
var controller_ki_spin_box: SpinBox
var controlled_inventory_value_label: Label
var controller_error_value_label: Label
var controller_integral_value_label: Label
var controller_output_value_label: Label
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
	dock_title = "Machine Control Panel"
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

	operator_summary = VBoxContainer.new()
	operator_summary.add_theme_constant_override("separation", 2)
	operator_summary.visible = false
	root.add_child(operator_summary)

	var mode_summary_row := UIWidgets.create_labeled_value("MODE", "—")
	mode_summary_value_label = UIWidgets.get_value_label(mode_summary_row)
	operator_summary.add_child(mode_summary_row)

	var sp_summary_row := UIWidgets.create_labeled_value("SP", "—")
	sp_summary_value_label = UIWidgets.get_value_label(sp_summary_row)
	operator_summary.add_child(sp_summary_row)

	var pv_summary_row := UIWidgets.create_labeled_value("PV", "—")
	pv_summary_value_label = UIWidgets.get_value_label(pv_summary_row)
	operator_summary.add_child(pv_summary_row)

	var co_summary_row := UIWidgets.create_labeled_value("CO", "—")
	co_summary_value_label = UIWidgets.get_value_label(co_summary_row)
	operator_summary.add_child(co_summary_row)

	root.add_child(HSeparator.new())

	operation_section = VBoxContainer.new()
	root.add_child(operation_section)

	var operation_title := UIWidgets.create_section_header(
		"Operator Controls"
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
		"Overall efficiency",
		"—"
	)
	efficiency_value_label = UIWidgets.get_value_label(
		efficiency_row
	)
	operation_section.add_child(efficiency_row)

	var power_demand_row := UIWidgets.create_labeled_value(
		"Power demand",
		"0.00 PU"
	)
	power_demand_value_label = UIWidgets.get_value_label(
		power_demand_row
	)
	operation_section.add_child(power_demand_row)

	var power_mode_row := UIWidgets.create_labeled_value(
		"Power mode",
		"Off"
	)
	power_mode_value_label = UIWidgets.get_value_label(
		power_mode_row
	)
	operation_section.add_child(power_mode_row)

	batch_section = VBoxContainer.new()
	operation_section.add_child(batch_section)
	batch_section.add_child(HSeparator.new())
	batch_section.add_child(UIWidgets.create_section_header("Batch Operation"))

	var batch_status_row := UIWidgets.create_labeled_value("Phase", "Ready")
	batch_status_value_label = UIWidgets.get_value_label(batch_status_row)
	batch_section.add_child(batch_status_row)

	batch_progress_bar = ProgressBar.new()
	batch_progress_bar.min_value = 0.0
	batch_progress_bar.max_value = 100.0
	batch_progress_bar.show_percentage = true
	batch_section.add_child(batch_progress_bar)

	var batch_remaining_row := UIWidgets.create_labeled_value("Time remaining", "—")
	batch_remaining_value_label = UIWidgets.get_value_label(batch_remaining_row)
	batch_section.add_child(batch_remaining_row)

	var batch_count_row := UIWidgets.create_labeled_value("Completed batches", "0")
	batch_count_value_label = UIWidgets.get_value_label(batch_count_row)
	batch_section.add_child(batch_count_row)

	batch_inputs_value_label = Label.new()
	batch_inputs_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	batch_section.add_child(batch_inputs_value_label)

	hold_after_batch_check_box = CheckBox.new()
	hold_after_batch_check_box.text = "Hold after current batch"
	hold_after_batch_check_box.toggled.connect(_on_hold_after_batch_toggled)
	batch_section.add_child(hold_after_batch_check_box)

	operation_section.add_child(HSeparator.new())

	maintenance_section = VBoxContainer.new()
	operation_section.add_child(maintenance_section)

	maintenance_section.add_child(
		UIWidgets.create_section_header("Condition & Maintenance")
	)

	condition_badge = UIWidgets.create_status_badge(
		"Good",
		ThemeManager.COLOR_SUCCESS
	)
	maintenance_section.add_child(condition_badge)

	var condition_row := UIWidgets.create_labeled_value(
		"Condition",
		"100%"
	)
	condition_value_label = UIWidgets.get_value_label(
		condition_row
	)
	maintenance_section.add_child(condition_row)

	var breakdown_risk_row := UIWidgets.create_labeled_value(
		"Breakdown chance",
		"0% per operating hour"
	)
	breakdown_risk_value_label = UIWidgets.get_value_label(
		breakdown_risk_row
	)
	maintenance_section.add_child(breakdown_risk_row)

	var condition_efficiency_row := UIWidgets.create_labeled_value(
		"Condition efficiency",
		"100%"
	)
	condition_efficiency_value_label = UIWidgets.get_value_label(
		condition_efficiency_row
	)
	maintenance_section.add_child(condition_efficiency_row)

	var wear_power_row := UIWidgets.create_labeled_value(
		"Wear power multiplier",
		"1.00×"
	)
	wear_power_value_label = UIWidgets.get_value_label(
		wear_power_row
	)
	maintenance_section.add_child(wear_power_row)

	var operating_hours_row := UIWidgets.create_labeled_value(
		"Operating hours",
		"0.00 h"
	)
	operating_hours_value_label = UIWidgets.get_value_label(
		operating_hours_row
	)
	maintenance_section.add_child(operating_hours_row)

	var maintenance_plan_row := UIWidgets.create_labeled_value(
		"Maintenance plan",
		"—"
	)
	maintenance_plan_value_label = UIWidgets.get_value_label(
		maintenance_plan_row
	)
	maintenance_section.add_child(maintenance_plan_row)

	maintenance_policy_check_box = CheckBox.new()
	maintenance_policy_check_box.text = "Automatic preventive maintenance"
	maintenance_policy_check_box.toggled.connect(
		_on_maintenance_policy_toggled
	)
	maintenance_section.add_child(maintenance_policy_check_box)

	var policy_condition_row := HBoxContainer.new()
	maintenance_section.add_child(policy_condition_row)

	var policy_condition_label := Label.new()
	policy_condition_label.text = "Service threshold"
	policy_condition_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	policy_condition_row.add_child(policy_condition_label)

	maintenance_policy_condition_spin_box = SpinBox.new()
	maintenance_policy_condition_spin_box.custom_minimum_size = Vector2(135, 0)
	maintenance_policy_condition_spin_box.min_value = 1.0
	maintenance_policy_condition_spin_box.max_value = 99.0
	maintenance_policy_condition_spin_box.step = 1.0
	maintenance_policy_condition_spin_box.suffix = "%"
	maintenance_policy_condition_spin_box.value_changed.connect(
		_on_maintenance_policy_condition_changed
	)
	policy_condition_row.add_child(maintenance_policy_condition_spin_box)

	var policy_reserve_row := HBoxContainer.new()
	maintenance_section.add_child(policy_reserve_row)

	var policy_reserve_label := Label.new()
	policy_reserve_label.text = "Minimum cash reserve"
	policy_reserve_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	policy_reserve_row.add_child(policy_reserve_label)

	maintenance_policy_cash_reserve_spin_box = SpinBox.new()
	maintenance_policy_cash_reserve_spin_box.custom_minimum_size = Vector2(135, 0)
	maintenance_policy_cash_reserve_spin_box.min_value = 0.0
	maintenance_policy_cash_reserve_spin_box.max_value = 1000000000.0
	maintenance_policy_cash_reserve_spin_box.step = 100.0
	maintenance_policy_cash_reserve_spin_box.prefix = "$"
	maintenance_policy_cash_reserve_spin_box.value_changed.connect(
		_on_maintenance_policy_cash_reserve_changed
	)
	policy_reserve_row.add_child(maintenance_policy_cash_reserve_spin_box)

	var policy_status_row := UIWidgets.create_labeled_value(
		"Policy status",
		"Manual"
	)
	maintenance_policy_status_value_label = UIWidgets.get_value_label(
		policy_status_row
	)
	maintenance_section.add_child(policy_status_row)

	var preventive_maintenance_row := UIWidgets.create_labeled_value(
		"Preventive services",
		"0"
	)
	preventive_maintenance_value_label = UIWidgets.get_value_label(
		preventive_maintenance_row
	)
	maintenance_section.add_child(preventive_maintenance_row)

	var emergency_repairs_row := UIWidgets.create_labeled_value(
		"Failures / emergency repairs",
		"0 / 0"
	)
	emergency_repairs_value_label = UIWidgets.get_value_label(
		emergency_repairs_row
	)
	maintenance_section.add_child(emergency_repairs_row)

	var maintenance_spend_row := UIWidgets.create_labeled_value(
		"Maintenance spend",
		"$0.00"
	)
	maintenance_spend_value_label = UIWidgets.get_value_label(
		maintenance_spend_row
	)
	maintenance_section.add_child(maintenance_spend_row)

	var downtime_row := UIWidgets.create_labeled_value(
		"Total downtime",
		"0 s"
	)
	downtime_value_label = UIWidgets.get_value_label(downtime_row)
	maintenance_section.add_child(downtime_row)

	maintenance_progress_bar = ProgressBar.new()
	maintenance_progress_bar.min_value = 0.0
	maintenance_progress_bar.max_value = 100.0
	maintenance_progress_bar.value = 0.0
	maintenance_progress_bar.show_percentage = true
	maintenance_section.add_child(maintenance_progress_bar)

	maintenance_button = Button.new()
	maintenance_button.text = "Perform Maintenance"
	maintenance_button.pressed.connect(
		_on_maintenance_pressed
	)
	maintenance_section.add_child(maintenance_button)

	var control_separator := HSeparator.new()
	operation_section.add_child(control_separator)

	control_section = VBoxContainer.new()
	operation_section.add_child(control_section)

	control_section.add_child(
		UIWidgets.create_section_header("Automatic Control")
	)

	var control_mode_row := HBoxContainer.new()
	control_section.add_child(control_mode_row)

	var control_mode_label := Label.new()
	control_mode_label.text = "Mode"
	control_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_mode_row.add_child(control_mode_label)

	control_mode_option = OptionButton.new()
	control_mode_option.custom_minimum_size = Vector2(135, 0)
	control_mode_option.add_item(
		"Manual",
		MachineModel.ControlMode.MANUAL
	)
	control_mode_option.add_item(
		"Automatic",
		MachineModel.ControlMode.AUTOMATIC
	)
	control_mode_option.item_selected.connect(
		_on_control_mode_selected
	)
	control_mode_row.add_child(control_mode_option)

	var setpoint_row := HBoxContainer.new()
	control_section.add_child(setpoint_row)

	var setpoint_label := Label.new()
	setpoint_label.text = "Inventory setpoint"
	setpoint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setpoint_row.add_child(setpoint_label)

	inventory_setpoint_spin_box = SpinBox.new()
	inventory_setpoint_spin_box.custom_minimum_size = Vector2(135, 0)
	inventory_setpoint_spin_box.min_value = 0.0
	inventory_setpoint_spin_box.max_value = 1000000.0
	inventory_setpoint_spin_box.step = 100.0
	inventory_setpoint_spin_box.value_changed.connect(
		_on_inventory_setpoint_changed
	)
	setpoint_row.add_child(inventory_setpoint_spin_box)

	var kp_row := HBoxContainer.new()
	control_section.add_child(kp_row)

	var kp_label := Label.new()
	kp_label.text = "Proportional gain"
	kp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kp_row.add_child(kp_label)

	controller_kp_spin_box = SpinBox.new()
	controller_kp_spin_box.custom_minimum_size = Vector2(135, 0)
	controller_kp_spin_box.min_value = 0.0
	controller_kp_spin_box.max_value = 10.0
	controller_kp_spin_box.step = 0.05
	controller_kp_spin_box.value_changed.connect(
		_on_controller_kp_changed
	)
	kp_row.add_child(controller_kp_spin_box)

	var ki_row := HBoxContainer.new()
	control_section.add_child(ki_row)

	var ki_label := Label.new()
	ki_label.text = "Integral gain"
	ki_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ki_row.add_child(ki_label)

	controller_ki_spin_box = SpinBox.new()
	controller_ki_spin_box.custom_minimum_size = Vector2(135, 0)
	controller_ki_spin_box.min_value = 0.0
	controller_ki_spin_box.max_value = 1.0
	controller_ki_spin_box.step = 0.001
	controller_ki_spin_box.value_changed.connect(
		_on_controller_ki_changed
	)
	ki_row.add_child(controller_ki_spin_box)

	var controlled_inventory_row := UIWidgets.create_labeled_value(
		"Controlled inventory",
		"0"
	)
	controlled_inventory_value_label = UIWidgets.get_value_label(
		controlled_inventory_row
	)
	control_section.add_child(controlled_inventory_row)

	var controller_error_row := UIWidgets.create_labeled_value(
		"Control error",
		"0"
	)
	controller_error_value_label = UIWidgets.get_value_label(
		controller_error_row
	)
	control_section.add_child(controller_error_row)

	var controller_integral_row := UIWidgets.create_labeled_value(
		"Integral contribution",
		"0%"
	)
	controller_integral_value_label = UIWidgets.get_value_label(
		controller_integral_row
	)
	control_section.add_child(controller_integral_row)

	var controller_output_row := UIWidgets.create_labeled_value(
		"Controller output",
		"0%"
	)
	controller_output_value_label = UIWidgets.get_value_label(
		controller_output_row
	)
	control_section.add_child(controller_output_row)

	# Operator controls belong ahead of live performance and maintenance details.
	operation_section.move_child(control_separator, 3)
	operation_section.move_child(control_section, 4)

	operation_section.add_child(HSeparator.new())

	upgrade_section = VBoxContainer.new()
	operation_section.add_child(upgrade_section)
	upgrade_section.add_child(
		UIWidgets.create_section_header("Installed Upgrades")
	)
	upgrade_list = VBoxContainer.new()
	upgrade_section.add_child(upgrade_list)

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
	factory.event_bus.machine_power_changed.connect(
		_on_machine_power_changed
	)
	factory.event_bus.machine_control_changed.connect(
		_on_machine_control_changed
	)
	factory.event_bus.machine_condition_changed.connect(
		_on_machine_condition_changed
	)
	factory.event_bus.machine_maintenance_changed.connect(
		_on_machine_maintenance_changed
	)
	factory.event_bus.machine_upgrades_changed.connect(
		_on_machine_upgrades_changed
	)
	factory.event_bus.research_changed.connect(
		_on_research_changed
	)
	factory.event_bus.economy_changed.connect(
		_on_economy_changed
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
	var power_callback := Callable(
		self,
		"_on_machine_power_changed"
	)
	var control_callback := Callable(
		self,
		"_on_machine_control_changed"
	)
	var condition_callback := Callable(
		self,
		"_on_machine_condition_changed"
	)
	var maintenance_callback := Callable(
		self,
		"_on_machine_maintenance_changed"
	)
	var upgrades_callback := Callable(
		self,
		"_on_machine_upgrades_changed"
	)
	var research_callback := Callable(
		self,
		"_on_research_changed"
	)
	var economy_callback := Callable(
		self,
		"_on_economy_changed"
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

	if factory.event_bus.machine_power_changed.is_connected(
		power_callback
	):
		factory.event_bus.machine_power_changed.disconnect(
			power_callback
		)

	if factory.event_bus.machine_control_changed.is_connected(
		control_callback
	):
		factory.event_bus.machine_control_changed.disconnect(
			control_callback
		)

	if factory.event_bus.machine_condition_changed.is_connected(
		condition_callback
	):
		factory.event_bus.machine_condition_changed.disconnect(
			condition_callback
		)

	if factory.event_bus.machine_maintenance_changed.is_connected(
		maintenance_callback
	):
		factory.event_bus.machine_maintenance_changed.disconnect(
			maintenance_callback
		)

	if factory.event_bus.machine_upgrades_changed.is_connected(
		upgrades_callback
	):
		factory.event_bus.machine_upgrades_changed.disconnect(
			upgrades_callback
		)

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
		_update_batch_section()


func _on_machine_power_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_power_labels()


func _on_machine_control_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_control_labels()


func _on_machine_condition_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_condition_labels()
		_update_performance_labels()
		_update_power_labels()


func _on_machine_maintenance_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_condition_labels()
		_update_performance_labels()
		_update_power_labels()
		UIWidgets.update_status_badge(
			state_badge,
			_state_text(machine.state),
			_state_color(machine.state)
		)


func _on_machine_upgrades_changed(machine: MachineModel) -> void:
	if machine == selected_machine:
		_update_upgrade_section()
		_update_performance_labels()
		_update_power_labels()


func _on_research_changed(_value: Variant) -> void:
	_update_upgrade_section()


func _on_economy_changed(_value: Variant) -> void:
	_update_upgrade_section()


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
		operator_summary.visible = false
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
		power_demand_value_label.text = "0.00 PU"
		power_mode_value_label.text = "Off"
		batch_section.visible = false
		maintenance_section.visible = false
		control_section.visible = false
		upgrade_section.visible = false
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

	set_dock_title("Machine Control Panel")
	operator_summary.visible = true
	operation_section.visible = true
	connection_operation_section.visible = false
	input_title.text = "Inputs"
	output_title.text = "Outputs"
	inventory_title.text = "Inventory"
	name_label.text = selected_machine.display_name
	var footprint := selected_machine.get_oriented_footprint()
	id_label.text = "ID: %s  •  Footprint: %d × %d  •  %s" % [
		selected_machine.instance_id,
		footprint.x,
		footprint.y,
		"Constructed" if selected_machine.placement_committed else "Awaiting construction"
	]
	updating_controls = true
	enabled_check_box.disabled = false
	enabled_check_box.button_pressed = selected_machine.enabled
	operating_rate_spin_box.editable = (
		selected_machine.control_mode
		== MachineModel.ControlMode.MANUAL
	)
	operating_rate_spin_box.value = (
		selected_machine.manual_operating_rate * 100.0
	)
	maintenance_section.visible = (
		selected_machine.supports_maintenance()
	)
	batch_section.visible = selected_machine.is_batch_machine()
	_update_batch_section()
	control_section.visible = (
		selected_machine.supports_inventory_control()
	)
	upgrade_section.visible = not ResearchRegistry.get_for_machine(
		selected_machine.definition_id
	).is_empty()
	control_mode_option.select(
		control_mode_option.get_item_index(
			selected_machine.control_mode
		)
	)
	inventory_setpoint_spin_box.value = (
		selected_machine.inventory_setpoint
	)
	controller_kp_spin_box.value = selected_machine.controller_kp
	controller_ki_spin_box.value = selected_machine.controller_ki
	inventory_setpoint_spin_box.suffix = " %s" % (
		ResourceRegistry.get_unit(
			selected_machine.control_resource
		)
	)
	_update_performance_labels()
	_update_power_labels()
	_update_condition_labels()
	_update_control_labels()
	_update_operator_summary()
	_update_upgrade_section()
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


func _update_batch_section() -> void:
	if selected_machine == null or not selected_machine.is_batch_machine():
		batch_section.visible = false
		return

	batch_section.visible = true
	batch_status_value_label.text = selected_machine.get_batch_status_text()
	batch_progress_bar.value = selected_machine.get_batch_progress_ratio() * 100.0
	batch_remaining_value_label.text = (
		"%.1f s" % selected_machine.get_batch_remaining_seconds()
		if selected_machine.batch_active
		else "—"
	)
	batch_count_value_label.text = str(selected_machine.batch_count)
	hold_after_batch_check_box.button_pressed = selected_machine.hold_after_batch

	var readiness: PackedStringArray = []
	for input: Dictionary in selected_machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		var required := float(input.get("amount", 0.0))
		var available := selected_machine.inventory.get_amount(resource_id)
		readiness.append("%s %.1f / %.1f %s" % [
			ResourceRegistry.get_display_name(resource_id),
			available,
			required,
			ResourceRegistry.get_unit(resource_id)
		])
	batch_inputs_value_label.text = "Next batch inputs\n%s" % "\n".join(readiness)


func _update_upgrade_section() -> void:
	if upgrade_section == null or upgrade_list == null:
		return

	UIWidgets.clear_container(upgrade_list)

	if selected_machine == null or factory == null:
		upgrade_section.visible = false
		return

	var definitions := ResearchRegistry.get_for_machine(
		selected_machine.definition_id
	)
	upgrade_section.visible = not definitions.is_empty()

	for definition: Dictionary in definitions:
		var research_id := str(definition.get("id", ""))
		var installed := selected_machine.has_upgrade(research_id)
		var researched := factory.is_researched(research_id)
		var installation_cost := maxf(
			0.0,
			float(definition.get("installation_cost", 0.0))
		)
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var effect_summary := ResearchRegistry.get_effect_summary(
			definition
		)

		if installed:
			status.text = "%s — Installed\n%s" % [
				str(definition.get("display_name", research_id)),
				effect_summary
			]
			status.modulate = ThemeManager.COLOR_SUCCESS
		elif not researched:
			status.text = "%s — Research required\n%s" % [
				str(definition.get("display_name", research_id)),
				effect_summary
			]
			status.modulate = ThemeManager.COLOR_TEXT_MUTED
		else:
			status.text = "%s — Available\n%s" % [
				str(definition.get("display_name", research_id)),
				effect_summary
			]
			status.modulate = ThemeManager.COLOR_ACCENT

		upgrade_list.add_child(status)

		var button := Button.new()
		button.text = (
			"Installed"
			if installed
			else "Install — $%.2f" % installation_cost
		)
		button.disabled = (
			installed
			or not researched
			or not factory.can_install_upgrade(
				selected_machine,
				research_id
			)
		)
		button.pressed.connect(
			_on_install_upgrade_pressed.bind(research_id)
		)
		upgrade_list.add_child(button)
		upgrade_list.add_child(HSeparator.new())


func _on_install_upgrade_pressed(research_id: String) -> void:
	if factory != null and selected_machine != null:
		factory.install_machine_upgrade(
			selected_machine,
			research_id
		)


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


func _update_power_labels() -> void:
	if (
		power_demand_value_label == null
		or power_mode_value_label == null
	):
		return

	if selected_machine == null:
		power_demand_value_label.text = "0.00 PU"
		power_mode_value_label.text = "Off"
		return

	power_demand_value_label.text = "%.2f PU" % (
		selected_machine.power_demand
	)
	power_mode_value_label.text = selected_machine.get_power_mode()


func _update_condition_labels() -> void:
	if (
		condition_badge == null
		or condition_value_label == null
		or breakdown_risk_value_label == null
		or condition_efficiency_value_label == null
		or wear_power_value_label == null
		or operating_hours_value_label == null
		or maintenance_plan_value_label == null
		or maintenance_policy_check_box == null
		or maintenance_policy_condition_spin_box == null
		or maintenance_policy_cash_reserve_spin_box == null
		or maintenance_policy_status_value_label == null
		or preventive_maintenance_value_label == null
		or emergency_repairs_value_label == null
		or maintenance_spend_value_label == null
		or downtime_value_label == null
		or maintenance_progress_bar == null
		or maintenance_button == null
	):
		return

	if selected_machine == null:
		condition_value_label.text = "100%"
		breakdown_risk_value_label.text = "0% per operating hour"
		condition_efficiency_value_label.text = "100%"
		wear_power_value_label.text = "1.00×"
		operating_hours_value_label.text = "0.00 h"
		maintenance_plan_value_label.text = "—"
		maintenance_policy_check_box.button_pressed = false
		maintenance_policy_check_box.disabled = true
		maintenance_policy_condition_spin_box.value = 75.0
		maintenance_policy_condition_spin_box.editable = false
		maintenance_policy_cash_reserve_spin_box.value = 0.0
		maintenance_policy_cash_reserve_spin_box.editable = false
		maintenance_policy_status_value_label.text = "Manual"
		preventive_maintenance_value_label.text = "0"
		emergency_repairs_value_label.text = "0 / 0"
		maintenance_spend_value_label.text = "$0.00"
		downtime_value_label.text = "0 s"
		maintenance_progress_bar.value = 0.0
		maintenance_progress_bar.visible = false
		maintenance_button.text = "Perform Maintenance"
		maintenance_button.disabled = true
		UIWidgets.update_status_badge(
			condition_badge,
			"No condition data",
			ThemeManager.COLOR_TEXT_MUTED
		)
		return

	condition_value_label.text = "%.1f%%" % (
		selected_machine.condition * 100.0
	)
	breakdown_risk_value_label.text = _format_breakdown_risk(
		selected_machine.get_breakdown_chance_per_hour()
	)
	condition_efficiency_value_label.text = "%.1f%%" % (
		selected_machine.get_condition_efficiency() * 100.0
	)
	wear_power_value_label.text = "%.2f×" % (
		selected_machine.get_condition_power_multiplier()
	)
	operating_hours_value_label.text = "%.3f h" % (
		selected_machine.operating_hours
	)
	var emergency_repair := (
		selected_machine.maintenance_is_emergency
		or selected_machine.is_failed()
	)
	maintenance_plan_value_label.text = "%s · $%.2f · %.0f s" % [
		"Emergency" if emergency_repair else "Planned",
		selected_machine.get_current_maintenance_cost(),
		selected_machine.get_current_maintenance_duration()
	]
	maintenance_policy_check_box.button_pressed = (
		selected_machine.maintenance_policy_enabled
	)
	maintenance_policy_check_box.disabled = false
	maintenance_policy_condition_spin_box.value = (
		selected_machine.maintenance_policy_condition * 100.0
	)
	maintenance_policy_condition_spin_box.editable = (
		selected_machine.maintenance_policy_enabled
	)
	maintenance_policy_cash_reserve_spin_box.value = (
		selected_machine.maintenance_policy_cash_reserve
	)
	maintenance_policy_cash_reserve_spin_box.editable = (
		selected_machine.maintenance_policy_enabled
	)
	maintenance_policy_status_value_label.text = _maintenance_policy_status(
		selected_machine
	)
	preventive_maintenance_value_label.text = str(
		selected_machine.preventive_maintenance_count
	)
	emergency_repairs_value_label.text = "%d / %d" % [
		selected_machine.failure_count,
		selected_machine.emergency_repair_count
	]
	maintenance_spend_value_label.text = "$%.2f" % (
		selected_machine.maintenance_spend
	)
	downtime_value_label.text = _format_duration(
		selected_machine.get_total_downtime_seconds()
	)
	maintenance_progress_bar.visible = (
		selected_machine.is_under_maintenance()
	)
	maintenance_progress_bar.value = (
		selected_machine.get_maintenance_progress() * 100.0
	)
	if selected_machine.is_under_maintenance():
		maintenance_button.text = "%s — %.1f s remaining" % [
			"Emergency repair" if emergency_repair else "Maintenance",
			selected_machine.maintenance_remaining_seconds
		]
	elif emergency_repair:
		maintenance_button.text = "Begin Emergency Repair — $%.2f" % (
			selected_machine.get_current_maintenance_cost()
		)
	else:
		maintenance_button.text = "Perform Maintenance — $%.2f" % (
			selected_machine.get_current_maintenance_cost()
		)
	maintenance_button.disabled = (
		selected_machine.is_under_maintenance()
		or factory == null
		or not factory.can_start_machine_maintenance(selected_machine)
	)
	UIWidgets.update_status_badge(
		condition_badge,
		_condition_text(selected_machine),
		_condition_color(selected_machine)
	)


func _update_control_labels() -> void:
	if (
		controlled_inventory_value_label == null
		or controller_error_value_label == null
		or controller_integral_value_label == null
		or controller_output_value_label == null
	):
		return

	if selected_machine == null:
		controlled_inventory_value_label.text = "0"
		controller_error_value_label.text = "0"
		controller_integral_value_label.text = "0%"
		controller_output_value_label.text = "0%"
		return

	var unit := ResourceRegistry.get_unit(
		selected_machine.control_resource
	)
	controlled_inventory_value_label.text = "%.1f %s" % [
		selected_machine.controlled_inventory_amount,
		unit
	]
	controller_error_value_label.text = "%.1f %s" % [
		selected_machine.controller_error,
		unit
	]
	controller_integral_value_label.text = "%.0f%%" % (
		selected_machine.controller_integral * 100.0
	)
	controller_output_value_label.text = "%.0f%%" % (
		selected_machine.operating_rate * 100.0
	)
	_update_operator_summary()


func _update_operator_summary() -> void:
	if (
		mode_summary_value_label == null
		or sp_summary_value_label == null
		or pv_summary_value_label == null
		or co_summary_value_label == null
	):
		return

	if selected_machine == null:
		mode_summary_value_label.text = "—"
		sp_summary_value_label.text = "—"
		pv_summary_value_label.text = "—"
		co_summary_value_label.text = "—"
		return

	mode_summary_value_label.text = (
		"AUTO"
		if selected_machine.control_mode == MachineModel.ControlMode.AUTOMATIC
		else "MAN"
	)
	co_summary_value_label.text = "%.0f%%" % (
		selected_machine.operating_rate * 100.0
	)

	if not selected_machine.supports_inventory_control():
		sp_summary_value_label.text = "—"
		pv_summary_value_label.text = "—"
		return

	var unit := ResourceRegistry.get_unit(selected_machine.control_resource)
	sp_summary_value_label.text = "%.1f %s" % [
		selected_machine.inventory_setpoint,
		unit
	]
	pv_summary_value_label.text = "%.1f %s" % [
		selected_machine.controlled_inventory_amount,
		unit
	]


func _refresh_connection() -> void:
	set_dock_title("Connection Inspector")
	operator_summary.visible = false
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
	inventory_list.add_child(
		UIWidgets.create_labeled_value(
			"Routing points",
			str(selected_connection.route_points.size())
		)
	)
	var route_hint := Label.new()
	route_hint.text = "Double-click line: add point  •  Drag: move point  •  Right-click point: remove  •  Right-click line: disconnect"
	route_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route_hint.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	inventory_list.add_child(route_hint)


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


func _on_hold_after_batch_toggled(value: bool) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.hold_after_batch
	_execute_setting_action(
		"set batch hold",
		selected_machine.set_hold_after_batch.bind(value),
		selected_machine.set_hold_after_batch.bind(previous_value)
	)


func _on_control_mode_selected(index: int) -> void:
	if updating_controls or selected_machine == null:
		return

	var mode := control_mode_option.get_item_id(index)
	var previous_mode := selected_machine.control_mode

	if mode == previous_mode:
		return

	_execute_setting_action(
		"set control mode",
		selected_machine.set_control_mode.bind(mode),
		selected_machine.set_control_mode.bind(previous_mode)
	)


func _on_inventory_setpoint_changed(value: float) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.inventory_setpoint

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set inventory setpoint",
		selected_machine.set_inventory_setpoint.bind(value),
		selected_machine.set_inventory_setpoint.bind(
			previous_value
		)
	)


func _on_controller_kp_changed(value: float) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.controller_kp

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set proportional gain",
		selected_machine.set_controller_kp.bind(value),
		selected_machine.set_controller_kp.bind(previous_value)
	)


func _on_controller_ki_changed(value: float) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.controller_ki

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set integral gain",
		selected_machine.set_controller_ki.bind(value),
		selected_machine.set_controller_ki.bind(previous_value)
	)


func _on_maintenance_pressed() -> void:
	if selected_machine == null or factory == null:
		return

	factory.start_machine_maintenance(selected_machine)


func _on_maintenance_policy_toggled(enabled: bool) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.maintenance_policy_enabled

	if previous_value == enabled:
		return

	_execute_setting_action(
		"set automatic maintenance policy",
		selected_machine.set_maintenance_policy_enabled.bind(enabled),
		selected_machine.set_maintenance_policy_enabled.bind(previous_value)
	)


func _on_maintenance_policy_condition_changed(percent: float) -> void:
	if updating_controls or selected_machine == null:
		return

	var value := percent / 100.0
	var previous_value := selected_machine.maintenance_policy_condition

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set maintenance threshold",
		selected_machine.set_maintenance_policy_condition.bind(value),
		selected_machine.set_maintenance_policy_condition.bind(previous_value)
	)


func _on_maintenance_policy_cash_reserve_changed(value: float) -> void:
	if updating_controls or selected_machine == null:
		return

	var previous_value := selected_machine.maintenance_policy_cash_reserve

	if is_equal_approx(previous_value, value):
		return

	_execute_setting_action(
		"set maintenance cash reserve",
		selected_machine.set_maintenance_policy_cash_reserve.bind(value),
		selected_machine.set_maintenance_policy_cash_reserve.bind(previous_value)
	)


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
		MachineModel.State.MAINTENANCE:
			return ThemeManager.COLOR_ACCENT
		MachineModel.State.FAILED:
			return ThemeManager.COLOR_DANGER
		_:
			return ThemeManager.COLOR_ACCENT


func _format_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0f s" % seconds

	if seconds < 3600.0:
		return "%.1f min" % (seconds / 60.0)

	return "%.2f h" % (seconds / 3600.0)


func _format_breakdown_risk(chance_per_hour: float) -> String:
	var percent := chance_per_hour * 100.0

	if percent > 0.0 and percent < 0.01:
		return "<0.01% per operating hour"

	if percent < 1.0:
		return "%.2f%% per operating hour" % percent

	return "%.1f%% per operating hour" % percent


func _maintenance_policy_status(machine: MachineModel) -> String:
	if not machine.maintenance_policy_enabled:
		return "Manual"

	if machine.is_under_maintenance():
		return "Maintenance in progress"

	if machine.is_failed():
		return "Emergency repair required"

	if machine.condition > machine.maintenance_policy_condition:
		return "Armed"

	if factory == null:
		return "Waiting for factory"

	if (
		factory.cash_balance - machine.maintenance_cost
		< machine.maintenance_policy_cash_reserve
	):
		return "Waiting for funds"

	return "Scheduling service"


func _condition_text(machine: MachineModel) -> String:
	if machine.is_under_maintenance():
		return "%s — %.1f s remaining" % [
			"Emergency repair" if machine.maintenance_is_emergency else "Maintenance",
			machine.maintenance_remaining_seconds
		]

	if machine.is_failed():
		return "Failed — emergency repair required"

	if machine.is_maintenance_critical():
		return "Critical — maintenance required"

	if machine.is_maintenance_due():
		return "Maintenance due"

	return "Good"


func _condition_color(machine: MachineModel) -> Color:
	if machine.is_under_maintenance():
		return ThemeManager.COLOR_ACCENT

	if machine.is_failed():
		return ThemeManager.COLOR_DANGER

	if machine.is_maintenance_critical():
		return ThemeManager.COLOR_DANGER

	if machine.is_maintenance_due():
		return ThemeManager.COLOR_WARNING

	return ThemeManager.COLOR_SUCCESS
