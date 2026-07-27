class_name PlantOverview
extends ScrollContainer


const REFRESH_KEY := &"plant_overview"

var factory: FactoryModel
var refresh_manager: RefreshManager

@onready var status_banner := %StatusBanner as StatusBanner
@onready var total_card := %TotalCard as KpiCard
@onready var running_card := %RunningCard as KpiCard
@onready var idle_card := %IdleCard as KpiCard
@onready var blocked_card := %BlockedCard as KpiCard
@onready var disabled_card := %DisabledCard as KpiCard
@onready var connections_card := %ConnectionsCard as KpiCard
@onready var inventory_list := %InventoryList as VBoxContainer


func _ready() -> void:
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
