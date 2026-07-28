class_name KpiCard
extends PanelContainer


@export var title_text := "Metric"
@export var value_text := "0"
@export var accent_color := ThemeManager.COLOR_ACCENT

@onready var title_label := %TitleLabel as Label
@onready var value_label := %ValueLabel as Label


func _ready() -> void:
	title_label.text = title_text
	value_label.text = value_text
	value_label.add_theme_color_override("font_color", accent_color)


func set_value(value: String) -> void:
	value_text = value

	if is_node_ready():
		value_label.text = value_text


func set_accent(color: Color) -> void:
	accent_color = color

	if is_node_ready():
		value_label.add_theme_color_override("font_color", accent_color)
