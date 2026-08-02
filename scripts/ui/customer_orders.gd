class_name CustomerOrders
extends VBoxContainer


const FILTER_OPEN := 0
const FILTER_ALL := 1
const FILTER_HISTORY := 2

var factory: FactoryModel
var refresh_elapsed := 0.0

@onready var build_label := %BuildLabel as Label
@onready var cash_label := %CashLabel as Label
@onready var generate_offer_button := %GenerateOfferButton as Button
@onready var order_filter := %OrderFilter as OptionButton
@onready var summary_label := %SummaryLabel as Label
@onready var order_list := %OrderList as VBoxContainer


func _ready() -> void:
	build_label.text = BuildInfo.get_display_string()
	order_filter.add_item("Open orders", FILTER_OPEN)
	order_filter.add_item("All orders", FILTER_ALL)
	order_filter.add_item("Order history", FILTER_HISTORY)
	generate_offer_button.pressed.connect(_on_generate_offer_pressed)
	order_filter.item_selected.connect(_on_filter_selected)
	_refresh()


func bind_factory(new_factory: FactoryModel) -> void:
	_disconnect_factory()
	factory = new_factory
	refresh_elapsed = 0.0

	if factory != null and factory.event_bus != null:
		factory.event_bus.customer_orders_changed.connect(_on_orders_changed)
		factory.event_bus.economy_changed.connect(_on_economy_changed)

	_refresh()


func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	refresh_elapsed += delta_seconds

	if refresh_elapsed >= 1.0:
		refresh_elapsed = fmod(refresh_elapsed, 1.0)

		if not _is_order_button_hovered():
			_refresh()


func _disconnect_factory() -> void:
	if factory == null or factory.event_bus == null:
		return

	var order_callback := Callable(self, "_on_orders_changed")
	var economy_callback := Callable(self, "_on_economy_changed")

	if factory.event_bus.customer_orders_changed.is_connected(order_callback):
		factory.event_bus.customer_orders_changed.disconnect(order_callback)
	if factory.event_bus.economy_changed.is_connected(economy_callback):
		factory.event_bus.economy_changed.disconnect(economy_callback)


func _on_orders_changed(_value: Variant) -> void:
	_refresh()


func _on_economy_changed(_value: Variant) -> void:
	if not _is_order_button_hovered():
		_refresh()


func _on_generate_offer_pressed() -> void:
	if factory != null:
		factory.generate_customer_order()


func _on_filter_selected(_index: int) -> void:
	_refresh()


func _refresh() -> void:
	if order_list == null:
		return

	UIWidgets.clear_container(order_list)
	cash_label.text = "Cash %s" % _format_currency(
		factory.cash_balance if factory != null else 0.0
	)

	if factory == null:
		summary_label.text = "No factory"
		return

	var displayed: Array[Dictionary] = []
	var active_count := 0
	var offer_count := 0

	for order: Dictionary in factory.customer_orders:
		var status := str(order.get("status", ""))

		if status == FactoryModel.ORDER_STATUS_ACTIVE:
			active_count += 1
		elif status == FactoryModel.ORDER_STATUS_OFFERED:
			offer_count += 1

		if _include_order(status):
			displayed.append(order)

	summary_label.text = "%d offers • %d active • %d total" % [
		offer_count,
		active_count,
		factory.customer_orders.size()
	]

	if displayed.is_empty():
		order_list.add_child(
			UIWidgets.create_empty_label(
				"No matching orders. Request a new offer to begin."
			)
		)
		return

	for order: Dictionary in displayed:
		_add_order_card(order)


func _include_order(status: String) -> bool:
	match order_filter.selected:
		FILTER_OPEN:
			return status in [
				FactoryModel.ORDER_STATUS_OFFERED,
				FactoryModel.ORDER_STATUS_ACTIVE
			]
		FILTER_HISTORY:
			return status in [
				FactoryModel.ORDER_STATUS_COMPLETED,
				FactoryModel.ORDER_STATUS_FAILED,
				FactoryModel.ORDER_STATUS_DECLINED
			]
		_:
			return true


func _add_order_card(order: Dictionary) -> void:
	var resource_id := str(order["resource_id"])
	var quantity := float(order["quantity"])
	var status := str(order["status"])
	var order_id := int(order["id"])
	var inventory := factory.get_plant_inventory_amount(resource_id)
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	var content := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	var badge := Label.new()
	var details := Label.new()
	var actions := HBoxContainer.new()

	order_list.add_child(panel)
	panel.add_child(margin)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	margin.add_child(content)
	content.add_child(header)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "Order #%d — %.1f %s of %s" % [
		order_id,
		quantity,
		ResourceRegistry.get_unit(resource_id),
		ResourceRegistry.get_display_name(resource_id)
	]
	header.add_child(title)
	badge.text = status.to_upper()
	badge.add_theme_color_override("font_color", _status_color(status))
	header.add_child(badge)
	details.text = "Reward %s • Late penalty %s • Deadline %s • Plant inventory %.1f / %.1f %s" % [
		_format_currency(float(order["reward"])),
		_format_currency(float(order["late_penalty"])),
		_format_duration(float(order["deadline_remaining_seconds"])),
		inventory,
		quantity,
		ResourceRegistry.get_unit(resource_id)
	]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	content.add_child(actions)

	if status == FactoryModel.ORDER_STATUS_OFFERED:
		_add_action_button(actions, "Accept", _on_accept_pressed.bind(order_id))
		_add_action_button(actions, "Decline", _on_decline_pressed.bind(order_id))
	elif status == FactoryModel.ORDER_STATUS_ACTIVE:
		var deliver := _add_action_button(
			actions,
			"Deliver Order",
			_on_deliver_pressed.bind(order_id)
		)
		deliver.disabled = not factory.can_deliver_customer_order(order_id)
		var shortage := maxf(quantity - inventory, 0.0)
		var hint := Label.new()
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.text = (
			"Ready for delivery"
			if shortage <= 0.0
			else "Need %.1f more %s" % [
				shortage,
				ResourceRegistry.get_unit(resource_id)
			]
		)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		actions.add_child(hint)


func _add_action_button(
	container: HBoxContainer,
	text: String,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	container.add_child(button)
	return button


func _on_accept_pressed(order_id: int) -> void:
	factory.accept_customer_order(order_id)


func _on_decline_pressed(order_id: int) -> void:
	factory.decline_customer_order(order_id)


func _on_deliver_pressed(order_id: int) -> void:
	factory.deliver_customer_order(order_id)


func _is_order_button_hovered() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered is Button and order_list.is_ancestor_of(hovered)


func _status_color(status: String) -> Color:
	match status:
		FactoryModel.ORDER_STATUS_COMPLETED:
			return ThemeManager.COLOR_SUCCESS
		FactoryModel.ORDER_STATUS_FAILED:
			return ThemeManager.COLOR_DANGER
		FactoryModel.ORDER_STATUS_ACTIVE:
			return ThemeManager.COLOR_WARNING
		_:
			return ThemeManager.COLOR_TEXT_MUTED


func _format_currency(value: float) -> String:
	return "$%.2f" % value


func _format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(ceil(seconds)))
	var hours := floori(float(total_seconds) / 3600.0)
	var minutes := floori(float(total_seconds % 3600) / 60.0)
	var remaining_seconds := total_seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]
