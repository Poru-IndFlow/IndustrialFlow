class_name EditorToolbar
extends HBoxContainer


signal save_requested
signal load_requested
signal undo_requested
signal redo_requested
signal delete_requested


var save_button: Button
var load_button: Button
var undo_button: Button
var redo_button: Button
var delete_button: Button
var status_label: Label
var status_timer: Timer


func _ready() -> void:
	add_theme_constant_override(
		"separation",
		ThemeManager.SPACING_SMALL
	)

	save_button = _add_toolbar_button(
		"Save",
		"Save factory (Ctrl+S)",
		save_requested
	)
	load_button = _add_toolbar_button(
		"Load",
		"Load factory (Ctrl+L)",
		load_requested
	)

	add_child(VSeparator.new())

	undo_button = _add_toolbar_button(
		"Undo",
		"Undo last editor action (Ctrl+Z)",
		undo_requested
	)
	redo_button = _add_toolbar_button(
		"Redo",
		"Redo last editor action (Ctrl+Y)",
		redo_requested
	)

	add_child(VSeparator.new())

	delete_button = _add_toolbar_button(
		"Delete Selected",
		"Delete selected machines (Delete)",
		delete_requested
	)

	status_label = Label.new()
	status_label.text = "Ready"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override(
		"font_color",
		ThemeManager.COLOR_TEXT_MUTED
	)
	add_child(status_label)

	status_timer = Timer.new()
	status_timer.one_shot = true
	status_timer.timeout.connect(_on_status_timeout)
	add_child(status_timer)

	set_command_availability(false, false, false, false)
	set_selection_count(0)


func set_command_availability(
	can_save: bool,
	can_load: bool,
	can_undo: bool,
	can_redo: bool
) -> void:
	save_button.disabled = not can_save
	load_button.disabled = not can_load
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo


func set_history_state(
	can_undo: bool,
	can_redo: bool,
	undo_label: String,
	redo_label: String
) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo

	undo_button.text = "Undo"
	redo_button.text = "Redo"
	undo_button.tooltip_text = "Nothing to undo"
	redo_button.tooltip_text = "Nothing to redo"

	if can_undo:
		undo_button.tooltip_text = "Undo %s (Ctrl+Z)" % undo_label

	if can_redo:
		redo_button.tooltip_text = "Redo %s (Ctrl+Y)" % redo_label


func set_selection_count(count: int) -> void:
	delete_button.disabled = count <= 0

	if count <= 0:
		delete_button.text = "Delete Selected"
	elif count == 1:
		delete_button.text = "Delete 1 Machine"
	else:
		delete_button.text = "Delete %d Machines" % count


func show_status(
	message: String,
	color: Color = ThemeManager.COLOR_TEXT_MUTED,
	duration_seconds: float = 3.0
) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)

	if duration_seconds > 0.0:
		status_timer.start(duration_seconds)
	else:
		status_timer.stop()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("save_factory")
		and not save_button.disabled
	):
		save_requested.emit()
	elif (
		event.is_action_pressed("load_factory")
		and not load_button.disabled
	):
		load_requested.emit()
	elif event.is_action_pressed("undo") and not undo_button.disabled:
		undo_requested.emit()
	elif event.is_action_pressed("redo") and not redo_button.disabled:
		redo_requested.emit()
	elif (
		event.is_action_pressed("delete_selected")
		and not delete_button.disabled
	):
		delete_requested.emit()
	else:
		return

	get_viewport().set_input_as_handled()


func _add_toolbar_button(
	text: String,
	tooltip: String,
	request_signal: Signal
) -> Button:
	var button := UIWidgets.create_toolbar_button(text, tooltip)
	button.pressed.connect(request_signal.emit)
	add_child(button)
	return button


func _on_status_timeout() -> void:
	show_status("Ready", ThemeManager.COLOR_TEXT_MUTED, 0.0)
