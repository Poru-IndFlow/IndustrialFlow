extends PanelContainer


func _ready() -> void:
	var title := Label.new()
	title.text = "Machine Inspector"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)