class_name ScadaAlarmRow
extends PanelContainer


signal view_requested(machine_id: String)
signal acknowledge_requested(alarm_key: String)

var alarm_key := ""
var machine_id := ""

@onready var severity_label := %SeverityLabel as Label
@onready var equipment_label := %EquipmentLabel as Label
@onready var message_label := %MessageLabel as Label
@onready var duration_label := %DurationLabel as Label
@onready var view_button := %ViewButton as Button
@onready var acknowledge_button := %AcknowledgeButton as Button


func _ready() -> void:
	view_button.pressed.connect(_on_view_pressed)
	acknowledge_button.pressed.connect(_on_acknowledge_pressed)


func configure(
	key: String,
	new_machine_id: String,
	equipment_name: String,
	severity_text: String,
	message: String,
	active_seconds: float,
	acknowledged: bool,
	color: Color
) -> void:
	alarm_key = key
	machine_id = new_machine_id
	severity_label.text = severity_text
	severity_label.add_theme_color_override("font_color", color)
	equipment_label.text = equipment_name
	message_label.text = message
	duration_label.text = _format_duration(active_seconds)
	acknowledge_button.text = (
		"Acknowledged" if acknowledged else "Acknowledge"
	)
	acknowledge_button.disabled = acknowledged


func _format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(floor(seconds)))
	var hours := floori(float(total_seconds) / 3600.0)
	var minutes := floori(float(total_seconds % 3600) / 60.0)
	var remaining_seconds := total_seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]


func _on_view_pressed() -> void:
	view_requested.emit(machine_id)


func _on_acknowledge_pressed() -> void:
	acknowledge_requested.emit(alarm_key)
