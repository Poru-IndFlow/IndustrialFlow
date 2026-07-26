class_name UIWidgets
extends RefCounted


static func create_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_TEXT
	)
	return label


static func create_empty_label(text := "None") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_TEXT_MUTED
	)
	return label


static func create_labeled_value(
	label_text: String,
	value_text: String
) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row


static func get_value_label(row: HBoxContainer) -> Label:
	if row.get_child_count() < 2:
		return null

	return row.get_child(1) as Label


static func create_action_button(
	text: String,
	tooltip := ""
) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


static func create_status_badge(
	text: String,
	color: Color
) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override(
		"normal",
		ThemeManager.make_badge_style(color)
	)
	badge.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_TEXT
	)
	return badge


static func update_status_badge(
	badge: Label,
	text: String,
	color: Color
) -> void:
	badge.text = text
	badge.add_theme_stylebox_override(
		"normal",
		ThemeManager.make_badge_style(color)
	)


static func clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		child.queue_free()
