class_name ResourceThroughputRow
extends PanelContainer


@onready var resource_label := %ResourceLabel as Label
@onready var detail_label := %DetailLabel as Label
@onready var status_label := %StatusLabel as Label


func configure(
	resource_name: String,
	detail: String,
	status_text: String,
	status_color: Color
) -> void:
	resource_label.text = resource_name
	detail_label.text = detail
	UIWidgets.update_status_badge(
		status_label,
		status_text,
		status_color
	)
