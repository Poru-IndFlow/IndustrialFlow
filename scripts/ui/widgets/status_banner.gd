class_name StatusBanner
extends PanelContainer


@export var message := "Plant status unavailable"
@export var status_color := ThemeManager.COLOR_TEXT_MUTED

@onready var message_label := %MessageLabel as Label


func _ready() -> void:
	set_status(message, status_color)


func set_status(text: String, color: Color) -> void:
	message = text
	status_color = color

	if not is_node_ready():
		return

	message_label.text = message
	message_label.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_TEXT
	)
	add_theme_stylebox_override(
		"panel",
		ThemeManager.make_badge_style(status_color)
	)
