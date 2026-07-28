class_name PlantOverview
extends ScrollContainer


signal machine_requested(machine_id: String)

const REFRESH_KEY := &"plant_overview"
const ALERT_ROW_SCENE := preload(
	"res://scenes/ui/machine_alert_row.tscn"
)
const THROUGHPUT_ROW_SCENE := preload(
	"res://scenes/ui/resource_throughput_row.tscn"
)

var factory: FactoryModel
var refresh_manager: RefreshManager
var alert_signature := ""
var throughput_signature := ""

@onready var build_label := %BuildLabel as Label
@onready var status_banner := %StatusBanner as StatusBanner
@onready var total_card := %TotalCard as KpiCard
@onready var running_card := %RunningCard as KpiCard
@onready var idle_card := %IdleCard as KpiCard
@onready var blocked_card := %BlockedCard as KpiCard
@onready var disabled_card := %DisabledCard as KpiCard
@onready var connections_card := %ConnectionsCard as KpiCard
@onready var alert_count_label := %AlertCountLabel as Label
@onready var alerts_list := %AlertsList as VBoxContainer
@onready var throughput_list := %ThroughputList as VBoxContainer
@onready var inventory_list := %InventoryList as VBoxContainer


func _ready() -> void:
	build_label.text = BuildInfo.get_display_string()
	total_card.set_accent(ThemeManager.COLOR_ACCENT)
	running_card.set_accent(ThemeManager.COLOR_SUCCESS)
	idle_card.set_accent(ThemeManager.COLOR_TEXT_MUTED)
	blocked_card.set_accent(ThemeManager.COLOR_WARNING)
	disabled_card.set_accent(ThemeManager.COLOR_DANGER)
	connections_card.set_accent(ThemeManager.COLOR_ACCENT)
	_request_refresh()


func bind_refresh_manager(manager: RefreshManager) -> void:
	refresh_manager = manager
	_request_refresh()


func bind_factory(new_factory: FactoryModel) -> void:
	_disconnect_factory_events()
	factory = new_factory
	alert_signature = ""
	throughput_signature = ""
	_connect_factory_events()
	_request_refresh()


func _connect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	var callback := Callable(self, "_on_factory_changed")
	var signals: Array[Signal] = [
		factory.event_bus.machine_added,
		factory.event_bus.machine_removed,
		factory.event_bus.connection_added,
		factory.event_bus.connection_removed,
		factory.event_bus.connection_flow_changed,
		factory.event_bus.machine_state_changed,
		factory.event_bus.machine_inventory_changed
	]

	for factory_signal: Signal in signals:
		if not factory_signal.is_connected(callback):
			factory_signal.connect(callback)


func _disconnect_factory_events() -> void:
	if factory == null or factory.event_bus == null:
		return

	var callback := Callable(self, "_on_factory_changed")
	var signals: Array[Signal] = [
		factory.event_bus.machine_added,
		factory.event_bus.machine_removed,
		factory.event_bus.connection_added,
		factory.event_bus.connection_removed,
		factory.event_bus.connection_flow_changed,
		factory.event_bus.machine_state_changed,
		factory.event_bus.machine_inventory_changed
	]

	for factory_signal: Signal in signals:
		if factory_signal.is_connected(callback):
			factory_signal.disconnect(callback)


func _on_factory_changed(_value: Variant) -> void:
	_request_refresh()


func _request_refresh() -> void:
	if not is_node_ready():
		return

	if refresh_manager == null:
		_refresh()
		return

	refresh_manager.request_refresh(
		REFRESH_KEY,
		Callable(self, "_refresh")
	)


func _refresh() -> void:
	var total := 0
	var running := 0
	var idle := 0
	var blocked := 0
	var disabled := 0
	var connection_count := 0
	var inventory_totals: Dictionary = {}

	if factory != null:
		total = factory.machines.size()
		connection_count = factory.connections.size()

		for value: Variant in factory.machines.values():
			var machine := value as MachineModel

			if machine == null:
				continue

			match machine.state:
				MachineModel.State.RUNNING:
					running += 1
				MachineModel.State.IDLE:
					idle += 1
				MachineModel.State.BLOCKED_INPUT, MachineModel.State.BLOCKED_OUTPUT:
					blocked += 1
				MachineModel.State.DISABLED:
					disabled += 1

			for key: Variant in machine.inventory.amounts.keys():
				var resource_id := str(key)
				inventory_totals[resource_id] = (
					float(inventory_totals.get(resource_id, 0.0))
					+ machine.inventory.get_amount(resource_id)
				)

	total_card.set_value(str(total))
	running_card.set_value(str(running))
	idle_card.set_value(str(idle))
	blocked_card.set_value(str(blocked))
	disabled_card.set_value(str(disabled))
	connections_card.set_value(str(connection_count))

	_update_status(total, running, blocked, disabled)
	_update_alerts()
	_update_throughput()
	_update_inventory(inventory_totals)


func _update_status(
	total: int,
	running: int,
	blocked: int,
	disabled: int
) -> void:
	if total == 0:
		status_banner.set_status(
			"No machines in this plant yet.",
			ThemeManager.COLOR_TEXT_MUTED
		)
	elif disabled > 0:
		status_banner.set_status(
			"%d disabled machine%s need attention." % [
				disabled,
				"" if disabled == 1 else "s"
			],
			ThemeManager.COLOR_DANGER
		)
	elif blocked > 0:
		status_banner.set_status(
			"%d blocked machine%s need attention." % [
				blocked,
				"" if blocked == 1 else "s"
			],
			ThemeManager.COLOR_WARNING
		)
	elif running > 0:
		status_banner.set_status(
			"Plant operating normally.",
			ThemeManager.COLOR_SUCCESS
		)
	else:
		status_banner.set_status(
			"Plant ready. All machines are idle.",
			ThemeManager.COLOR_ACCENT
		)


func _update_inventory(totals: Dictionary) -> void:
	UIWidgets.clear_container(inventory_list)

	if totals.is_empty():
		inventory_list.add_child(
			UIWidgets.create_empty_label("No inventory recorded.")
		)
		return

	var resource_ids: Array[String] = []

	for key: Variant in totals.keys():
		resource_ids.append(str(key))

	resource_ids.sort()

	for resource_id: String in resource_ids:
		var amount := float(totals.get(resource_id, 0.0))
		var unit := ResourceRegistry.get_unit(resource_id)
		inventory_list.add_child(
			UIWidgets.create_labeled_value(
				ResourceRegistry.get_display_name(resource_id),
				"%s %s" % [_format_amount(amount), unit]
			)
		)


func _format_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(int(roundf(amount)))

	return "%.2f" % amount


func _update_throughput() -> void:
	if factory == null or factory.connections.is_empty():
		if throughput_signature == "none":
			return

		throughput_signature = "none"
		UIWidgets.clear_container(throughput_list)
		throughput_list.add_child(
			UIWidgets.create_empty_label(
				"No material connections available."
			)
		)
		return

	var resource_rates: Dictionary = {}
	var resource_capacities: Dictionary = {}
	var resource_line_counts: Dictionary = {}
	var active_line_counts: Dictionary = {}
	var saturated_line_counts: Dictionary = {}

	for connection: ConnectionModel in factory.connections:
		if not connection.enabled:
			continue

		var resource_id := connection.resource_id
		resource_rates[resource_id] = (
			float(resource_rates.get(resource_id, 0.0))
			+ connection.current_rate_per_second
		)
		resource_capacities[resource_id] = (
			float(resource_capacities.get(resource_id, 0.0))
			+ connection.capacity_per_second
		)
		resource_line_counts[resource_id] = (
			int(resource_line_counts.get(resource_id, 0)) + 1
		)

		if connection.current_rate_per_second > 0.0:
			active_line_counts[resource_id] = (
				int(active_line_counts.get(resource_id, 0)) + 1
			)

		if (
			connection.capacity_per_second > 0.0
			and connection.current_rate_per_second
			/ connection.capacity_per_second >= 0.95
		):
			saturated_line_counts[resource_id] = (
				int(saturated_line_counts.get(resource_id, 0)) + 1
			)

	if resource_rates.is_empty():
		if throughput_signature == "disabled":
			return

		throughput_signature = "disabled"
		UIWidgets.clear_container(throughput_list)
		throughput_list.add_child(
			UIWidgets.create_empty_label(
				"No enabled material connections available."
			)
		)
		return

	var resource_ids: Array[String] = []

	for key: Variant in resource_rates.keys():
		resource_ids.append(str(key))

	resource_ids.sort()
	var signature_parts: PackedStringArray = []

	for resource_id: String in resource_ids:
		signature_parts.append(
			"%s:%.6f:%.6f:%d:%d:%d" % [
				resource_id,
				float(resource_rates.get(resource_id, 0.0)),
				float(resource_capacities.get(resource_id, 0.0)),
				int(active_line_counts.get(resource_id, 0)),
				int(resource_line_counts.get(resource_id, 0)),
				int(saturated_line_counts.get(resource_id, 0))
			]
		)

	var new_signature := "|".join(signature_parts)

	if new_signature == throughput_signature:
		return

	throughput_signature = new_signature
	UIWidgets.clear_container(throughput_list)

	for resource_id: String in resource_ids:
		var rate := float(resource_rates.get(resource_id, 0.0))
		var capacity := float(
			resource_capacities.get(resource_id, 0.0)
		)
		var active_lines := int(
			active_line_counts.get(resource_id, 0)
		)
		var total_lines := int(
			resource_line_counts.get(resource_id, 0)
		)
		var saturated_lines := int(
			saturated_line_counts.get(resource_id, 0)
		)
		var utilization := (
			rate / capacity
			if capacity > 0.0
			else 0.0
		)
		var unit := ResourceRegistry.get_unit(resource_id)
		var row := (
			THROUGHPUT_ROW_SCENE.instantiate()
			as ResourceThroughputRow
		)

		if row == null:
			continue

		throughput_list.add_child(row)
		row.configure(
			ResourceRegistry.get_display_name(resource_id),
			"%.2f / %.2f %s/s · %.0f%% · %d/%d lines flowing" % [
				rate,
				capacity,
				unit,
				utilization * 100.0,
				active_lines,
				total_lines
			],
			_throughput_status_text(
				active_lines,
				total_lines,
				saturated_lines,
				utilization
			),
			_throughput_status_color(
				active_lines,
				total_lines,
				saturated_lines,
				utilization
			)
		)


func _throughput_status_text(
	active_lines: int,
	total_lines: int,
	saturated_lines: int,
	utilization: float
) -> String:
	if active_lines == 0:
		return "No flow"

	if saturated_lines > 0:
		return (
			"At capacity"
			if saturated_lines == total_lines
			else "%d saturated" % saturated_lines
		)

	if active_lines < total_lines:
		return "Partial flow"

	if utilization >= 0.8:
		return "High load"

	return "Flowing"


func _throughput_status_color(
	active_lines: int,
	total_lines: int,
	saturated_lines: int,
	utilization: float
) -> Color:
	if active_lines == 0:
		return ThemeManager.COLOR_TEXT_MUTED

	if (
		saturated_lines > 0
		or active_lines < total_lines
		or utilization >= 0.8
	):
		return ThemeManager.COLOR_WARNING

	return ThemeManager.COLOR_SUCCESS


func _update_alerts() -> void:
	var alert_machines: Array[MachineModel] = []

	if factory != null:
		for value: Variant in factory.machines.values():
			var machine := value as MachineModel

			if machine != null and _is_alert_state(machine.state):
				alert_machines.append(machine)

	alert_machines.sort_custom(_sort_alert_machines)
	var new_signature := _build_alert_signature(alert_machines)

	if new_signature == alert_signature:
		return

	alert_signature = new_signature
	UIWidgets.clear_container(alerts_list)
	alert_count_label.text = str(alert_machines.size())

	if alert_machines.is_empty():
		alerts_list.add_child(
			UIWidgets.create_empty_label(
				"No operational alerts."
			)
		)
		return

	for machine: MachineModel in alert_machines:
		var row := ALERT_ROW_SCENE.instantiate() as MachineAlertRow

		if row == null:
			continue

		alerts_list.add_child(row)
		row.configure(
			machine,
			_alert_detail(machine.state),
			_alert_color(machine.state)
		)
		row.machine_requested.connect(_on_machine_requested)


func _build_alert_signature(
	machines: Array[MachineModel]
) -> String:
	if machines.is_empty():
		return "none"

	var parts: PackedStringArray = []

	for machine: MachineModel in machines:
		parts.append(
			"%s:%d" % [machine.instance_id, machine.state]
		)

	return "|".join(parts)


func _is_alert_state(state: MachineModel.State) -> bool:
	return state in [
		MachineModel.State.BLOCKED_INPUT,
		MachineModel.State.BLOCKED_OUTPUT,
		MachineModel.State.DISABLED
	]


func _sort_alert_machines(
	left: MachineModel,
	right: MachineModel
) -> bool:
	var left_priority := _alert_priority(left.state)
	var right_priority := _alert_priority(right.state)

	if left_priority == right_priority:
		return left.display_name.naturalnocasecmp_to(
			right.display_name
		) < 0

	return left_priority < right_priority


func _alert_priority(state: MachineModel.State) -> int:
	return 0 if state == MachineModel.State.DISABLED else 1


func _alert_detail(state: MachineModel.State) -> String:
	match state:
		MachineModel.State.DISABLED:
			return "Disabled"
		MachineModel.State.BLOCKED_INPUT:
			return "Blocked — waiting for input"
		MachineModel.State.BLOCKED_OUTPUT:
			return "Blocked — output has nowhere to go"
		_:
			return "Needs attention"


func _alert_color(state: MachineModel.State) -> Color:
	if state == MachineModel.State.DISABLED:
		return ThemeManager.COLOR_DANGER

	return ThemeManager.COLOR_WARNING


func _on_machine_requested(machine_id: String) -> void:
	machine_requested.emit(machine_id)
