class_name EconomyTrends
extends VBoxContainer


var factory: FactoryModel
var status_label: Label
var cash_value_label: Label
var revenue_value_label: Label
var expenses_value_label: Label
var net_value_label: Label
var plot: EconomyTrendPlot


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_interface()
	_update_display()


func bind_factory(new_factory: FactoryModel) -> void:
	var callback := Callable(self, "_on_economy_changed")

	if factory != null and factory.event_bus != null:
		if factory.event_bus.economy_changed.is_connected(callback):
			factory.event_bus.economy_changed.disconnect(callback)

	factory = new_factory

	if factory != null and factory.event_bus != null:
		if not factory.event_bus.economy_changed.is_connected(callback):
			factory.event_bus.economy_changed.connect(callback)

	_update_display()


func _build_interface() -> void:
	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = "Economy Trends"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(clear_button)

	status_label = Label.new()
	status_label.modulate = ThemeManager.COLOR_TEXT_MUTED
	status_label.text = (
		"Rolling 120-second history • 1-second simulation samples"
	)
	add_child(status_label)

	var values := HBoxContainer.new()
	values.add_theme_constant_override("separation", 18)
	add_child(values)

	cash_value_label = _add_value(values, "Cash Balance")
	revenue_value_label = _add_value(values, "Revenue")
	expenses_value_label = _add_value(values, "Expenses")
	net_value_label = _add_value(values, "Net Cash Flow")

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 18)
	add_child(legend)
	_add_legend(legend, "Cash", EconomyTrendPlot.COLOR_CASH)
	_add_legend(legend, "Revenue", EconomyTrendPlot.COLOR_REVENUE)
	_add_legend(legend, "Expenses", EconomyTrendPlot.COLOR_EXPENSES)
	_add_legend(legend, "Net", EconomyTrendPlot.COLOR_NET)

	plot = EconomyTrendPlot.new()
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
	value.text = "$0.00"
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


func _on_economy_changed(_value: Variant) -> void:
	_update_display()


func _on_clear_pressed() -> void:
	if factory != null:
		factory.clear_economy_samples()


func _update_display() -> void:
	if not is_node_ready() or plot == null:
		return

	if factory == null:
		cash_value_label.text = "$0.00"
		revenue_value_label.text = "$0.00/s"
		expenses_value_label.text = "$0.00/s"
		net_value_label.text = "$0.00/s"
		var empty_samples: Array[Dictionary] = []
		plot.set_samples(empty_samples)
		return

	cash_value_label.text = _format_currency(factory.cash_balance)
	revenue_value_label.text = "%s/s" % _format_currency(
		factory.revenue_per_second
	)
	expenses_value_label.text = "%s/s" % _format_currency(
		factory.expenses_per_second
	)
	net_value_label.text = "%s/s" % _format_signed_currency(
		factory.net_cash_flow_per_second
	)
	plot.set_samples(factory.economy_samples)


func _format_currency(amount: float) -> String:
	if amount < 0.0:
		return "-$%.2f" % absf(amount)

	return "$%.2f" % amount


func _format_signed_currency(amount: float) -> String:
	if amount > 0.0:
		return "+%s" % _format_currency(amount)

	return _format_currency(amount)
