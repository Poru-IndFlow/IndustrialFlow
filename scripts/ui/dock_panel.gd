class_name DockPanel
extends PanelContainer


signal collapsed_changed(is_collapsed: bool)


@export var dock_title := "Panel"
@export var collapsed_width := 42.0

var _content_root: MarginContainer
var _title_label: Label
var _collapse_button: Button
var _expanded_minimum_width := 250.0
var _expanded_split_offset := 250
var _is_collapsed := false


func _ready() -> void:
	_expanded_minimum_width = maxf(
		custom_minimum_size.x,
		collapsed_width
	)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(
		"separation",
		ThemeManager.SPACING_MEDIUM
	)
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	_title_label = Label.new()
	_title_label.text = dock_title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 17)
	header.add_child(_title_label)

	_collapse_button = Button.new()
	_collapse_button.tooltip_text = "Collapse dock"
	_collapse_button.custom_minimum_size = Vector2(30, 30)
	_collapse_button.pressed.connect(toggle_collapsed)
	header.add_child(_collapse_button)
	_update_collapse_button()

	_content_root = MarginContainer.new()
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_content_root)


func get_content_root() -> MarginContainer:
	return _content_root


func set_dock_title(value: String) -> void:
	dock_title = value

	if _title_label != null:
		_title_label.text = dock_title


func is_collapsed() -> bool:
	return _is_collapsed


func toggle_collapsed() -> void:
	set_collapsed(not _is_collapsed)


func set_collapsed(value: bool) -> void:
	if _is_collapsed == value:
		return

	_is_collapsed = value
	_content_root.visible = not value
	_title_label.visible = not value
	var split := get_parent() as HSplitContainer

	if value:
		_expanded_minimum_width = maxf(
			size.x,
			custom_minimum_size.x
		)

		if split != null:
			_expanded_split_offset = split.split_offset

		custom_minimum_size.x = collapsed_width
		_collapse_button.tooltip_text = "Expand dock"
		_set_collapsed_split_offset(split)
	else:
		custom_minimum_size.x = _expanded_minimum_width
		_collapse_button.tooltip_text = "Collapse dock"

		if split != null:
			split.split_offset = _expanded_split_offset

	_update_collapse_button()
	collapsed_changed.emit(value)


func _set_collapsed_split_offset(split: HSplitContainer) -> void:
	if split == null:
		return

	if get_index() == 0:
		split.split_offset = int(collapsed_width)
	else:
		split.split_offset = int(split.size.x - collapsed_width)


func _update_collapse_button() -> void:
	var is_left_dock := get_index() == 0

	if _is_collapsed:
		_collapse_button.text = "▶" if is_left_dock else "◀"
	else:
		_collapse_button.text = "◀" if is_left_dock else "▶"
