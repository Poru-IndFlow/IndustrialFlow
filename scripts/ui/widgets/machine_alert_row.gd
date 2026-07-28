class_name MachineAlertRow
extends PanelContainer


signal machine_requested(machine_id: String)

var machine_id := ""

@onready var machine_name_label := %MachineNameLabel as Label
@onready var detail_label := %DetailLabel as Label
@onready var show_button := %ShowButton as Button


func _ready() -> void:
	show_button.pressed.connect(_on_show_pressed)


func configure(
	machine: MachineModel,
	detail: String,
	alert_color: Color
) -> void:
	if machine == null:
		return

	machine_id = machine.instance_id
	machine_name_label.text = machine.display_name
	detail_label.text = detail
	detail_label.add_theme_color_override(
		"font_color",
		alert_color
	)
	add_theme_stylebox_override(
		"panel",
		ThemeManager.make_badge_style(alert_color)
	)


func _on_show_pressed() -> void:
	if not machine_id.is_empty():
		machine_requested.emit(machine_id)
