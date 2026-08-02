class_name ScadaWorkspace
extends VBoxContainer


signal machine_requested(machine: MachineModel)

const ALARM_ROW_SCENE := preload(
	"res://scenes/ui/scada_alarm_row.tscn"
)
const SEVERITY_CRITICAL := 0
const SEVERITY_WARNING := 1
const SEVERITY_INFORMATION := 2
const ALARM_VIEW_CURRENT := 0
const ALARM_VIEW_ALL_HISTORY := 1
const ALARM_VIEW_ACTIVE_HISTORY := 2
const ALARM_VIEW_CLEARED_HISTORY := 3
const ALARM_VIEW_ACKNOWLEDGED_HISTORY := 4
const ALARM_VIEW_CRITICAL_HISTORY := 5

var factory: FactoryModel
var input_ports: Dictionary = {}
var output_ports: Dictionary = {}
var state_labels: Dictionary = {}
var metrics_labels: Dictionary = {}
var resource_labels: Dictionary = {}
var alarm_active_seconds: Dictionary = {}
var alarm_severity_by_key: Dictionary = {}
var active_alarm_records: Dictionary = {}
var cleared_unacknowledged_alarms: Dictionary = {}
var acknowledged_alarms: Dictionary = {}
var alarm_history: Array[Dictionary] = []
var history_record_by_key: Dictionary = {}
var alarm_refresh_elapsed := 0.0
var scada_elapsed_seconds := 0.0
var selected_machine: MachineModel
var updating_operator_controls := false

@onready var build_label := %BuildLabel as Label
@onready var system_status := %SystemStatus as Label
@onready var fit_plant_button := %FitPlantButton as Button
@onready var process_graph := %ProcessGraph as GraphEdit
@onready var alarm_count_label := %AlarmCountLabel as Label
@onready var alarm_list := %AlarmList as VBoxContainer
@onready var alarm_view_filter := %AlarmViewFilter as OptionButton
@onready var equipment_label := %EquipmentLabel as Label
@onready var operator_state_label := %OperatorStateLabel as Label
@onready var enabled_check_box := %EnabledCheckBox as CheckBox
@onready var rate_command_spin_box := %RateCommandSpinBox as SpinBox
@onready var maintenance_action_button := %MaintenanceActionButton as Button
@onready var operator_message := %OperatorMessage as Label


func _ready() -> void:
	build_label.text = BuildInfo.get_display_string()
	fit_plant_button.pressed.connect(_fit_plant)
	enabled_check_box.toggled.connect(_on_operator_enabled_toggled)
	rate_command_spin_box.value_changed.connect(_on_operator_rate_changed)
	maintenance_action_button.pressed.connect(
		_on_operator_maintenance_pressed
	)
	_setup_alarm_view_filter()
	_update_system_status()
	_update_operator_controls()
	_refresh_alarms()


func bind_factory(new_factory: FactoryModel) -> void:
	_disconnect_factory_events()
	factory = new_factory
	alarm_active_seconds.clear()
	alarm_severity_by_key.clear()
	active_alarm_records.clear()
	cleared_unacknowledged_alarms.clear()
	acknowledged_alarms.clear()
	alarm_history.clear()
	history_record_by_key.clear()
	alarm_refresh_elapsed = 0.0
	scada_elapsed_seconds = 0.0
	selected_machine = null
	_clear_graph()
	_update_operator_controls()

	if factory == null:
		_update_system_status()
		_refresh_alarms()
		return

	_connect_factory_events()

	for value: Variant in factory.machines.values():
		_add_machine_node(value as MachineModel)

	_rebuild_connections()
	_update_system_status()
	_refresh_alarms()
	call_deferred("_fit_plant")


func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	scada_elapsed_seconds += delta_seconds
	var alarms := _collect_alarms()
	_sync_alarm_state(alarms)

	for alarm: Dictionary in alarms:
		var key := str(alarm["key"])
		alarm_active_seconds[key] = (
			float(alarm_active_seconds.get(key, 0.0))
			+ delta_seconds
		)

	alarm_refresh_elapsed += delta_seconds

	if alarm_refresh_elapsed >= 1.0:
		alarm_refresh_elapsed = fmod(alarm_refresh_elapsed, 1.0)
		_refresh_alarms()


func _connect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	factory.event_bus.machine_added.connect(_on_machine_added)
	factory.event_bus.machine_removed.connect(_on_machine_removed)
	factory.event_bus.machine_state_changed.connect(_on_alarm_machine_changed)
	factory.event_bus.machine_inventory_changed.connect(_on_machine_changed)
	factory.event_bus.machine_performance_changed.connect(_on_machine_changed)
	factory.event_bus.machine_power_changed.connect(_on_machine_changed)
	factory.event_bus.machine_condition_changed.connect(_on_alarm_machine_changed)
	factory.event_bus.machine_settings_changed.connect(_on_alarm_machine_changed)
	factory.event_bus.connection_added.connect(_on_connection_added)
	factory.event_bus.connection_removed.connect(_on_connection_removed)
	factory.event_bus.connection_flow_changed.connect(_on_connection_changed)
	factory.event_bus.connection_settings_changed.connect(_on_connection_changed)
	factory.event_bus.economy_changed.connect(_on_economy_changed)


func _disconnect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	_disconnect_signal(
		factory.event_bus.machine_added,
		Callable(self, "_on_machine_added")
	)
	_disconnect_signal(
		factory.event_bus.machine_removed,
		Callable(self, "_on_machine_removed")
	)

	var machine_callback := Callable(self, "_on_machine_changed")
	var machine_signals: Array[Signal] = [
		factory.event_bus.machine_inventory_changed,
		factory.event_bus.machine_performance_changed,
		factory.event_bus.machine_power_changed
	]

	for factory_signal: Signal in machine_signals:
		_disconnect_signal(factory_signal, machine_callback)

	var alarm_machine_callback := Callable(
		self,
		"_on_alarm_machine_changed"
	)
	var alarm_machine_signals: Array[Signal] = [
		factory.event_bus.machine_state_changed,
		factory.event_bus.machine_condition_changed,
		factory.event_bus.machine_settings_changed
	]

	for factory_signal: Signal in alarm_machine_signals:
		_disconnect_signal(factory_signal, alarm_machine_callback)

	_disconnect_signal(
		factory.event_bus.connection_added,
		Callable(self, "_on_connection_added")
	)
	_disconnect_signal(
		factory.event_bus.connection_removed,
		Callable(self, "_on_connection_removed")
	)

	var connection_callback := Callable(self, "_on_connection_changed")
	_disconnect_signal(
		factory.event_bus.connection_flow_changed,
		connection_callback
	)
	_disconnect_signal(
		factory.event_bus.connection_settings_changed,
		connection_callback
	)
	_disconnect_signal(
		factory.event_bus.economy_changed,
		Callable(self, "_on_economy_changed")
	)


func _disconnect_signal(
	factory_signal: Signal,
	callback: Callable
) -> void:
	if factory_signal.is_connected(callback):
		factory_signal.disconnect(callback)


func _clear_graph() -> void:
	if process_graph == null:
		return

	process_graph.clear_connections()
	input_ports.clear()
	output_ports.clear()
	state_labels.clear()
	metrics_labels.clear()
	resource_labels.clear()

	for child: Node in process_graph.get_children():
		if child is GraphNode:
			process_graph.remove_child(child)
			child.queue_free()


func _add_machine_node(machine: MachineModel) -> void:
	if machine == null:
		return

	var node := GraphNode.new()
	node.name = machine.instance_id
	node.title = machine.display_name
	node.position_offset = machine.graph_position
	node.custom_minimum_size = Vector2(245, 145)
	node.draggable = false

	var state_label := Label.new()
	state_label.custom_minimum_size = Vector2(215, 0)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(state_label)
	state_labels[machine.instance_id] = state_label

	var metrics_label := Label.new()
	metrics_label.custom_minimum_size = Vector2(215, 0)
	metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics_label.clip_text = true
	metrics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(metrics_label)
	metrics_labels[machine.instance_id] = metrics_label

	var resources := _get_machine_resources(machine)
	var input_port := 0
	var output_port := 0
	var row := 2

	for resource_id: String in resources:
		var accepts := _has_resource(
			machine.definition.get("inputs", []),
			resource_id
		)
		var produces := _has_resource(
			machine.definition.get("outputs", []),
			resource_id
		)
		var resource_label := Label.new()
		resource_label.custom_minimum_size = Vector2(215, 0)
		resource_label.clip_text = true
		resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_child(resource_label)
		resource_labels[_port_key(machine.instance_id, resource_id)] = resource_label
		var color := ResourceRegistry.get_colour(resource_id)
		var port_type := ResourceRegistry.get_port_type(resource_id)
		node.set_slot(
			row,
			accepts,
			port_type,
			color,
			produces,
			port_type,
			color
		)

		if accepts:
			input_ports[_port_key(machine.instance_id, resource_id)] = input_port
			input_port += 1

		if produces:
			output_ports[_port_key(machine.instance_id, resource_id)] = output_port
			output_port += 1

		row += 1

	node.node_selected.connect(_on_node_selected.bind(machine))
	process_graph.add_child(node)
	_update_machine_node(machine)


func _update_machine_node(machine: MachineModel) -> void:
	if machine == null:
		return

	var state_label := state_labels.get(machine.instance_id) as Label
	var metrics_label := metrics_labels.get(machine.instance_id) as Label

	if state_label != null:
		state_label.text = _state_text(machine.state)
		state_label.add_theme_color_override(
			"font_color",
			_state_color(machine.state)
		)

	if metrics_label != null:
		metrics_label.text = "Rate %.0f%%  •  Power %.2f PU\nCondition %.1f%%" % [
			machine.actual_operating_rate * 100.0,
			machine.power_demand,
			machine.condition * 100.0
		]

	for resource_id: String in _get_machine_resources(machine):
		var label := resource_labels.get(
			_port_key(machine.instance_id, resource_id)
		) as Label

		if label != null:
			label.text = "%s  %.1f %s" % [
				ResourceRegistry.get_display_name(resource_id),
				machine.inventory.get_amount(resource_id),
				ResourceRegistry.get_unit(resource_id)
			]


func _rebuild_connections() -> void:
	process_graph.clear_connections()

	if factory == null:
		return

	for connection: ConnectionModel in factory.connections:
		_draw_connection(connection)


func _draw_connection(connection: ConnectionModel) -> void:
	if connection == null:
		return

	var from_key := _port_key(
		connection.from_machine.instance_id,
		connection.resource_id
	)
	var to_key := _port_key(
		connection.to_machine.instance_id,
		connection.resource_id
	)

	if not output_ports.has(from_key) or not input_ports.has(to_key):
		return

	process_graph.connect_node(
		connection.from_machine.instance_id,
		int(output_ports[from_key]),
		connection.to_machine.instance_id,
		int(input_ports[to_key])
	)
	_update_connection_activity(connection)


func _update_connection_activity(connection: ConnectionModel) -> void:
	if connection == null:
		return

	var from_key := _port_key(
		connection.from_machine.instance_id,
		connection.resource_id
	)
	var to_key := _port_key(
		connection.to_machine.instance_id,
		connection.resource_id
	)

	if not output_ports.has(from_key) or not input_ports.has(to_key):
		return

	var activity := 0.0

	if connection.enabled and connection.capacity_per_second > 0.0:
		activity = clampf(
			connection.current_rate_per_second
			/ connection.capacity_per_second,
			0.0,
			1.0
		)

	process_graph.set_connection_activity(
		connection.from_machine.instance_id,
		int(output_ports[from_key]),
		connection.to_machine.instance_id,
		int(input_ports[to_key]),
		activity
	)


func _fit_plant() -> void:
	if process_graph == null or factory == null or factory.machines.is_empty():
		return

	var bounds := Rect2()
	var first := true

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		var machine_rect := Rect2(
			machine.graph_position,
			Vector2(245, 170)
		)
		bounds = machine_rect if first else bounds.merge(machine_rect)
		first = false

	if first:
		return

	bounds = bounds.grow(80.0)
	var available := process_graph.size - Vector2(80, 80)
	var target_zoom := minf(
		available.x / maxf(bounds.size.x, 1.0),
		available.y / maxf(bounds.size.y, 1.0)
	)
	process_graph.zoom = clampf(
		target_zoom,
		process_graph.zoom_min,
		process_graph.zoom_max
	)
	process_graph.scroll_offset = (
		bounds.get_center()
		- process_graph.size * 0.5 / process_graph.zoom
	)


func _update_system_status() -> void:
	if system_status == null:
		return

	if factory == null or factory.machines.is_empty():
		system_status.text = "No equipment"
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_TEXT_MUTED
		)
		return

	var failed := 0
	var alarms := 0

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		if machine.is_failed():
			failed += 1
		elif (
			machine.is_maintenance_due()
			or machine.is_breakdown_risk_warning()
			or machine.state in [
				MachineModel.State.BLOCKED_INPUT,
				MachineModel.State.BLOCKED_OUTPUT,
				MachineModel.State.DISABLED
			]
		):
			alarms += 1

	if failed > 0:
		system_status.text = "%d FAILED  •  %d additional alarms" % [
			failed,
			alarms
		]
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_DANGER
		)
	elif alarms > 0:
		system_status.text = "%d active alarm%s" % [
			alarms,
			"" if alarms == 1 else "s"
		]
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_WARNING
		)
	else:
		system_status.text = "Plant operating normally"
		system_status.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_SUCCESS
		)


func _collect_alarms() -> Array[Dictionary]:
	var alarms: Array[Dictionary] = []

	if factory == null:
		return alarms

	for value: Variant in factory.machines.values():
		var machine := value as MachineModel

		if machine == null:
			continue

		if machine.is_under_maintenance():
			continue

		if machine.is_failed():
			alarms.append(_make_alarm(
				machine,
				"failed",
				SEVERITY_CRITICAL,
				"Machine failed — emergency repair required"
			))
			continue

		if machine.state == MachineModel.State.DISABLED:
			alarms.append(_make_alarm(
				machine,
				"disabled",
				SEVERITY_WARNING,
				"Machine disabled"
			))

		match machine.state:
			MachineModel.State.BLOCKED_INPUT:
				alarms.append(_make_alarm(
					machine,
					"blocked_input",
					SEVERITY_WARNING,
					"Blocked — waiting for input"
				))
			MachineModel.State.BLOCKED_OUTPUT:
				alarms.append(_make_alarm(
					machine,
					"blocked_output",
					SEVERITY_WARNING,
					"Blocked — output has nowhere to go"
				))

		if _is_policy_waiting_for_funds(machine):
			alarms.append(_make_alarm(
				machine,
				"maintenance_funds",
				SEVERITY_WARNING,
				"Automatic maintenance waiting for funds"
			))

		if machine.is_breakdown_risk_critical():
			alarms.append(_make_alarm(
				machine,
				"breakdown_risk",
				SEVERITY_CRITICAL,
				"Breakdown risk %.1f%% per operating hour" % (
					machine.get_breakdown_chance_per_hour() * 100.0
				)
			))
		elif machine.is_breakdown_risk_warning():
			alarms.append(_make_alarm(
				machine,
				"breakdown_risk",
				SEVERITY_WARNING,
				"Breakdown risk %.1f%% per operating hour" % (
					machine.get_breakdown_chance_per_hour() * 100.0
				)
			))

		if machine.is_maintenance_critical():
			alarms.append(_make_alarm(
				machine,
				"maintenance_due",
				SEVERITY_CRITICAL,
				"Critical condition — %.1f%%" % (
					machine.condition * 100.0
				)
			))
		elif machine.is_maintenance_due():
			alarms.append(_make_alarm(
				machine,
				"maintenance_due",
				SEVERITY_WARNING,
				"Maintenance due — %.1f%% condition" % (
					machine.condition * 100.0
				)
			))

	alarms.sort_custom(_sort_alarms)
	return alarms


func _make_alarm(
	machine: MachineModel,
	cause: String,
	severity: int,
	message: String
) -> Dictionary:
	return {
		"key": "%s:%s" % [machine.instance_id, cause],
		"machine_id": machine.instance_id,
		"equipment": machine.display_name,
		"severity": severity,
		"message": message
	}


func _sort_alarms(left: Dictionary, right: Dictionary) -> bool:
	var left_cleared := bool(left.get("cleared", false))
	var right_cleared := bool(right.get("cleared", false))

	if left_cleared != right_cleared:
		return not left_cleared

	var left_severity := int(left["severity"])
	var right_severity := int(right["severity"])

	if left_severity != right_severity:
		return left_severity < right_severity

	var equipment_comparison := str(left["equipment"]).naturalnocasecmp_to(
		str(right["equipment"])
	)

	if equipment_comparison != 0:
		return equipment_comparison < 0

	return str(left["message"]) < str(right["message"])


func _refresh_alarms() -> void:
	if alarm_list == null or alarm_count_label == null:
		return

	var alarms := _collect_alarms()
	_sync_alarm_state(alarms)

	if alarm_view_filter != null and alarm_view_filter.selected != ALARM_VIEW_CURRENT:
		_refresh_alarm_history(alarms)
		return

	var acknowledged_count := 0

	for alarm: Dictionary in alarms:
		var key := str(alarm["key"])
		if bool(acknowledged_alarms.get(key, false)):
			acknowledged_count += 1

	var displayed_alarms: Array[Dictionary] = []

	for alarm: Dictionary in alarms:
		displayed_alarms.append(alarm.duplicate(true))

	for value: Variant in cleared_unacknowledged_alarms.values():
		displayed_alarms.append((value as Dictionary).duplicate(true))

	displayed_alarms.sort_custom(_sort_alarms)
	UIWidgets.clear_container(alarm_list)
	alarm_count_label.text = "%d active • %d cleared • %d acknowledged" % [
		alarms.size(),
		cleared_unacknowledged_alarms.size(),
		acknowledged_count
	]

	if displayed_alarms.is_empty():
		alarm_list.add_child(
			UIWidgets.create_empty_label("No SCADA alarms.")
		)
		return

	for alarm: Dictionary in displayed_alarms:
		var row := ALARM_ROW_SCENE.instantiate() as ScadaAlarmRow

		if row == null:
			continue

		alarm_list.add_child(row)
		var key := str(alarm["key"])
		var severity := int(alarm["severity"])
		var is_cleared := bool(alarm.get("cleared", false))
		var duration := (
			float(alarm.get("duration_seconds", 0.0))
			if is_cleared
			else float(alarm_active_seconds.get(key, 0.0))
		)
		row.configure(
			key,
			str(alarm["machine_id"]),
			str(alarm["equipment"]),
			"CLEARED" if is_cleared else _severity_text(severity),
			(
				"Returned to normal — %s" % str(alarm["message"])
				if is_cleared
				else str(alarm["message"])
			),
			duration,
			(
				false
				if is_cleared
				else bool(acknowledged_alarms.get(key, false))
			),
			(
				ThemeManager.COLOR_TEXT_MUTED
				if is_cleared
				else _severity_color(severity)
			)
		)
		row.view_requested.connect(_focus_machine)
		row.acknowledge_requested.connect(_on_alarm_acknowledged)


func _setup_alarm_view_filter() -> void:
	if alarm_view_filter == null:
		return

	alarm_view_filter.clear()
	alarm_view_filter.add_item("Current", ALARM_VIEW_CURRENT)
	alarm_view_filter.add_item("All history", ALARM_VIEW_ALL_HISTORY)
	alarm_view_filter.add_item("Active history", ALARM_VIEW_ACTIVE_HISTORY)
	alarm_view_filter.add_item("Cleared history", ALARM_VIEW_CLEARED_HISTORY)
	alarm_view_filter.add_item(
		"Acknowledged history",
		ALARM_VIEW_ACKNOWLEDGED_HISTORY
	)
	alarm_view_filter.add_item("Critical history", ALARM_VIEW_CRITICAL_HISTORY)
	alarm_view_filter.select(ALARM_VIEW_CURRENT)
	alarm_view_filter.item_selected.connect(_on_alarm_view_selected)


func _refresh_alarm_history(current_alarms: Array[Dictionary]) -> void:
	var active_keys: Dictionary = {}

	for alarm: Dictionary in current_alarms:
		active_keys[str(alarm["key"])] = true

	var filtered_records: Array[Dictionary] = []
	var selected_view := alarm_view_filter.selected

	for index in range(alarm_history.size() - 1, -1, -1):
		var record := alarm_history[index]
		var is_active := active_keys.has(str(record["key"])) and not record.has(
			"cleared_at"
		)
		var include := false

		match selected_view:
			ALARM_VIEW_ALL_HISTORY:
				include = true
			ALARM_VIEW_ACTIVE_HISTORY:
				include = is_active
			ALARM_VIEW_CLEARED_HISTORY:
				include = record.has("cleared_at")
			ALARM_VIEW_ACKNOWLEDGED_HISTORY:
				include = record.has("acknowledged_at")
			ALARM_VIEW_CRITICAL_HISTORY:
				include = int(record["severity"]) == SEVERITY_CRITICAL

		if include:
			filtered_records.append(record)

	UIWidgets.clear_container(alarm_list)
	alarm_count_label.text = "%d shown • %d session records" % [
		filtered_records.size(),
		alarm_history.size()
	]

	if filtered_records.is_empty():
		alarm_list.add_child(
			UIWidgets.create_empty_label("No matching alarm history.")
		)
		return

	for record: Dictionary in filtered_records:
		var row := ALARM_ROW_SCENE.instantiate() as ScadaAlarmRow

		if row == null:
			continue

		alarm_list.add_child(row)
		var is_cleared := record.has("cleared_at")
		var duration := (
			float(record["duration_seconds"])
			if is_cleared
			else maxf(
				scada_elapsed_seconds - float(record["raised_at"]),
				0.0
			)
		)
		var timeline := "Raised %s" % _format_journal_time(
			float(record["raised_at"])
		)

		if record.has("acknowledged_at"):
			timeline += " • Acknowledged %s" % _format_journal_time(
				float(record["acknowledged_at"])
			)

		if is_cleared:
			timeline += " • Cleared %s" % _format_journal_time(
				float(record["cleared_at"])
			)

		var severity := int(record["severity"])
		row.configure_history(
			str(record["machine_id"]),
			str(record["equipment"]),
			"CLEARED" if is_cleared else _severity_text(severity),
			"%s • %s" % [str(record["message"]), timeline],
			duration,
			record.has("acknowledged_at"),
			ThemeManager.COLOR_TEXT_MUTED if is_cleared else _severity_color(
				severity
			)
		)
		row.view_requested.connect(_focus_machine)


func _format_journal_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(floor(seconds)))
	var hours := floori(float(total_seconds) / 3600.0)
	var minutes := floori(float(total_seconds % 3600) / 60.0)
	var remaining_seconds := total_seconds % 60
	return "T+%02d:%02d:%02d" % [hours, minutes, remaining_seconds]


func _on_alarm_view_selected(_index: int) -> void:
	_refresh_alarms()


func _sync_alarm_state(alarms: Array[Dictionary]) -> void:
	var active_keys: Dictionary = {}

	for alarm: Dictionary in alarms:
		var key := str(alarm["key"])
		var severity := int(alarm["severity"])
		active_keys[key] = true
		var is_new_occurrence := not active_alarm_records.has(key)

		if cleared_unacknowledged_alarms.has(key):
			cleared_unacknowledged_alarms.erase(key)
			alarm_active_seconds[key] = 0.0
			acknowledged_alarms.erase(key)

		if (
			alarm_severity_by_key.has(key)
			and int(alarm_severity_by_key[key]) != severity
		):
			acknowledged_alarms.erase(key)

		alarm_severity_by_key[key] = severity
		active_alarm_records[key] = alarm.duplicate(true)

		if is_new_occurrence:
			var history_on_raise := alarm.duplicate(true)
			history_on_raise["raised_at"] = scada_elapsed_seconds
			alarm_history.append(history_on_raise)
			history_record_by_key[key] = history_on_raise
		elif history_record_by_key.has(key):
			var current_history := history_record_by_key[key] as Dictionary
			current_history["severity"] = severity
			current_history["message"] = str(alarm["message"])

		if not alarm_active_seconds.has(key):
			alarm_active_seconds[key] = 0.0

	for value: Variant in active_alarm_records.keys():
		var key := str(value)

		if active_keys.has(key):
			continue

		if not bool(acknowledged_alarms.get(key, false)):
			var cleared_record := (
				active_alarm_records[key] as Dictionary
			).duplicate(true)
			cleared_record["cleared"] = true
			cleared_record["duration_seconds"] = float(
				alarm_active_seconds.get(key, 0.0)
			)
			cleared_unacknowledged_alarms[key] = cleared_record

		if history_record_by_key.has(key):
			var history_on_clear := history_record_by_key[key] as Dictionary
			history_on_clear["cleared_at"] = scada_elapsed_seconds
			history_on_clear["duration_seconds"] = maxf(
				scada_elapsed_seconds - float(history_on_clear["raised_at"]),
				0.0
			)

		active_alarm_records.erase(key)
		alarm_active_seconds.erase(key)
		alarm_severity_by_key.erase(key)
		acknowledged_alarms.erase(key)


func _severity_text(severity: int) -> String:
	match severity:
		SEVERITY_CRITICAL:
			return "CRITICAL"
		SEVERITY_WARNING:
			return "WARNING"
		_:
			return "INFO"


func _severity_color(severity: int) -> Color:
	match severity:
		SEVERITY_CRITICAL:
			return ThemeManager.COLOR_DANGER
		SEVERITY_WARNING:
			return ThemeManager.COLOR_WARNING
		_:
			return ThemeManager.COLOR_ACCENT


func _is_policy_waiting_for_funds(machine: MachineModel) -> bool:
	return (
		factory != null
		and machine.maintenance_policy_enabled
		and not machine.is_under_maintenance()
		and not machine.is_failed()
		and machine.condition <= machine.maintenance_policy_condition
		and (
			factory.cash_balance - machine.maintenance_cost
			< machine.maintenance_policy_cash_reserve
		)
	)


func _focus_machine(machine_id: String) -> void:
	if factory == null:
		return

	var node := process_graph.get_node_or_null(
		NodePath(machine_id)
	) as GraphNode
	var machine := factory.get_machine(machine_id)

	if node == null or machine == null:
		return

	for child: Node in process_graph.get_children():
		var graph_node := child as GraphNode

		if graph_node != null:
			graph_node.selected = graph_node == node

	process_graph.scroll_offset = (
		node.position_offset
		+ node.size * 0.5
		- process_graph.size * 0.5 / process_graph.zoom
	)
	_select_operator_machine(machine)
	machine_requested.emit(machine)


func _select_operator_machine(machine: MachineModel) -> void:
	selected_machine = machine
	_update_operator_controls()


func _update_operator_controls() -> void:
	if equipment_label == null:
		return

	updating_operator_controls = true

	if selected_machine == null:
		equipment_label.text = "Select equipment"
		operator_state_label.text = "No selection"
		operator_state_label.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_TEXT_MUTED
		)
		enabled_check_box.button_pressed = false
		enabled_check_box.disabled = true
		rate_command_spin_box.value = 0.0
		rate_command_spin_box.editable = false
		maintenance_action_button.text = "Maintenance unavailable"
		maintenance_action_button.disabled = true
		operator_message.text = "Select equipment to issue runtime commands."
		operator_message.add_theme_color_override(
			"font_color",
			ThemeManager.COLOR_TEXT_MUTED
		)
		updating_operator_controls = false
		return

	var machine := selected_machine
	var unavailable := machine.is_failed() or machine.is_under_maintenance()
	var manual_control := (
		machine.control_mode == MachineModel.ControlMode.MANUAL
	)
	equipment_label.text = machine.display_name
	operator_state_label.text = _state_text(machine.state)
	operator_state_label.add_theme_color_override(
		"font_color",
		_state_color(machine.state)
	)
	enabled_check_box.button_pressed = machine.enabled
	enabled_check_box.disabled = unavailable
	rate_command_spin_box.value = machine.manual_operating_rate * 100.0
	rate_command_spin_box.editable = (
		machine.enabled and manual_control and not unavailable
	)
	_update_maintenance_action(machine)
	_update_operator_message(machine, manual_control)
	updating_operator_controls = false


func _update_maintenance_action(machine: MachineModel) -> void:
	if not machine.supports_maintenance():
		maintenance_action_button.text = "No maintenance plan"
		maintenance_action_button.disabled = true
		return

	if machine.is_under_maintenance():
		maintenance_action_button.text = "Maintenance in progress — %.0fs" % (
			machine.maintenance_remaining_seconds
		)
		maintenance_action_button.disabled = true
		return

	var cost := machine.get_current_maintenance_cost()
	maintenance_action_button.text = "%s — $%.2f" % [
		"Begin Emergency Repair" if machine.is_failed() else "Begin Maintenance",
		cost
	]
	maintenance_action_button.disabled = (
		factory == null
		or not machine.can_start_maintenance()
		or factory.cash_balance < cost
	)


func _update_operator_message(
	machine: MachineModel,
	manual_control: bool
) -> void:
	var message := "Operator controls available"
	var color := ThemeManager.COLOR_SUCCESS

	if machine.is_failed():
		message = "Interlock: failed — emergency repair required"
		color = ThemeManager.COLOR_DANGER
	elif machine.is_under_maintenance():
		message = "Interlock: maintenance in progress"
		color = ThemeManager.COLOR_ACCENT
	elif not machine.enabled:
		message = "Interlock: equipment disabled"
		color = ThemeManager.COLOR_WARNING
	elif not manual_control:
		message = "Automatic inventory controller owns the speed command"
		color = ThemeManager.COLOR_ACCENT
	elif machine.state == MachineModel.State.BLOCKED_INPUT:
		message = "Process hold: waiting for input"
		color = ThemeManager.COLOR_WARNING
	elif machine.state == MachineModel.State.BLOCKED_OUTPUT:
		message = "Process hold: output has nowhere to go"
		color = ThemeManager.COLOR_WARNING

	if (
		machine.supports_maintenance()
		and not machine.is_under_maintenance()
		and machine.can_start_maintenance()
		and factory != null
		and factory.cash_balance < machine.get_current_maintenance_cost()
	):
		message += " • Maintenance blocked: insufficient funds"
		color = ThemeManager.COLOR_WARNING
	elif (
		machine.supports_maintenance()
		and not machine.is_under_maintenance()
		and not machine.can_start_maintenance()
	):
		message += " • Service not required at current condition"

	operator_message.text = message
	operator_message.add_theme_color_override("font_color", color)


func _on_operator_enabled_toggled(value: bool) -> void:
	if updating_operator_controls or selected_machine == null:
		return

	if selected_machine.is_failed() or selected_machine.is_under_maintenance():
		_update_operator_controls()
		return

	selected_machine.set_enabled(value)
	_update_operator_controls()


func _on_operator_rate_changed(value: float) -> void:
	if updating_operator_controls or selected_machine == null:
		return

	if (
		not selected_machine.enabled
		or selected_machine.is_failed()
		or selected_machine.is_under_maintenance()
		or selected_machine.control_mode != MachineModel.ControlMode.MANUAL
	):
		_update_operator_controls()
		return

	selected_machine.set_operating_rate(value / 100.0)


func _on_operator_maintenance_pressed() -> void:
	if factory == null or selected_machine == null:
		return

	factory.start_machine_maintenance(selected_machine)
	_update_operator_controls()


func _on_alarm_acknowledged(alarm_key: String) -> void:
	if history_record_by_key.has(alarm_key):
		var history_record := history_record_by_key[alarm_key] as Dictionary

		if not history_record.has("acknowledged_at"):
			history_record["acknowledged_at"] = scada_elapsed_seconds

	if cleared_unacknowledged_alarms.has(alarm_key):
		cleared_unacknowledged_alarms.erase(alarm_key)
		_refresh_alarms()
		return

	acknowledged_alarms[alarm_key] = true
	_refresh_alarms()


func _get_machine_resources(machine: MachineModel) -> Array[String]:
	var result: Array[String] = []

	for section_name: String in ["inputs", "outputs"]:
		var entries: Array = machine.definition.get(section_name, [])

		for entry: Variant in entries:
			var resource_id := str(
				(entry as Dictionary).get("resource", "")
			)

			if not resource_id.is_empty() and not result.has(resource_id):
				result.append(resource_id)

	result.sort()
	return result


func _has_resource(entries: Array, resource_id: String) -> bool:
	for entry: Variant in entries:
		if str((entry as Dictionary).get("resource", "")) == resource_id:
			return true

	return false


func _port_key(machine_id: String, resource_id: String) -> String:
	return "%s:%s" % [machine_id, resource_id]


func _state_text(state: MachineModel.State) -> String:
	return (MachineModel.State.keys()[state] as String).capitalize()


func _state_color(state: MachineModel.State) -> Color:
	match state:
		MachineModel.State.RUNNING:
			return ThemeManager.COLOR_SUCCESS
		MachineModel.State.BLOCKED_INPUT, MachineModel.State.BLOCKED_OUTPUT:
			return ThemeManager.COLOR_WARNING
		MachineModel.State.DISABLED, MachineModel.State.FAILED:
			return ThemeManager.COLOR_DANGER
		MachineModel.State.MAINTENANCE:
			return ThemeManager.COLOR_ACCENT
		_:
			return ThemeManager.COLOR_TEXT_MUTED


func _on_machine_added(machine: MachineModel) -> void:
	_add_machine_node(machine)
	_update_system_status()
	_refresh_alarms()
	call_deferred("_fit_plant")


func _on_machine_removed(machine_id: String) -> void:
	var node := process_graph.get_node_or_null(NodePath(machine_id)) as GraphNode

	if node != null:
		process_graph.remove_child(node)
		node.queue_free()

	if selected_machine != null and selected_machine.instance_id == machine_id:
		selected_machine = null
		_update_operator_controls()

	_rebuild_connections()
	_update_system_status()
	_refresh_alarms()


func _on_machine_changed(machine: MachineModel) -> void:
	_update_machine_node(machine)

	if machine == selected_machine:
		_update_operator_controls()


func _on_alarm_machine_changed(machine: MachineModel) -> void:
	_update_machine_node(machine)

	if machine == selected_machine:
		_update_operator_controls()

	_update_system_status()
	_refresh_alarms()


func _on_economy_changed(_value: Variant) -> void:
	_update_operator_controls()
	_refresh_alarms()


func _on_connection_added(connection: ConnectionModel) -> void:
	_draw_connection(connection)


func _on_connection_removed(_connection: ConnectionModel) -> void:
	_rebuild_connections()


func _on_connection_changed(connection: ConnectionModel) -> void:
	_update_connection_activity(connection)


func _on_node_selected(machine: MachineModel) -> void:
	_select_operator_machine(machine)
	machine_requested.emit(machine)
