class_name EditorToolbar
extends HBoxContainer


signal save_requested
signal load_requested
signal undo_requested
signal redo_requested
signal delete_requested
signal simulation_pause_requested(paused: bool)
signal simulation_speed_requested(speed: float)


var save_button: Button
var load_button: Button
var undo_button: Button
var redo_button: Button
var delete_button: Button
var simulation_pause_button: Button
var simulation_speed_option: OptionButton
var simulation_time_label: Label
var status_label: Label
var status_timer: Timer
var updating_simulation_controls := false


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

	add_child(VSeparator.new())

	simulation_pause_button = Button.new()
	simulation_pause_button.text = "Pause"
	simulation_pause_button.tooltip_text = "Pause the simulation"
	simulation_pause_button.toggle_mode = true
	simulation_pause_button.toggled.connect(
		_on_simulation_pause_toggled
	)
	add_child(simulation_pause_button)

	simulation_speed_option = OptionButton.new()
	simulation_speed_option.custom_minimum_size = Vector2(78, 0)
	_add_speed_option("0.5×", 5)
	_add_speed_option("1×", 10)
	_add_speed_option("2×", 20)
	_add_speed_option("5×", 50)
	_add_speed_option("10×", 100)
	simulation_speed_option.select(
		simulation_speed_option.get_item_index(10)
	)
	simulation_speed_option.item_selected.connect(
		_on_simulation_speed_selected
	)
	add_child(simulation_speed_option)

	simulation_time_label = Label.new()
	simulation_time_label.text = "Plant 00:00:00"
	simulation_time_label.tooltip_text = "Elapsed simulation time"
	simulation_time_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	add_child(simulation_time_label)

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
	set_simulation_state(false, 1.0, 0.0)


func set_simulation_state(
	is_paused: bool,
	speed: float,
	elapsed_seconds: float
) -> void:
	updating_simulation_controls = true
	simulation_pause_button.button_pressed = is_paused
	simulation_pause_button.text = (
		"Resume" if is_paused else "Pause"
	)
	simulation_pause_button.tooltip_text = (
		"Resume the simulation"
		if is_paused
		else "Pause the simulation"
	)
	var speed_id := int(roundf(speed * 10.0))
	var speed_index := (
		simulation_speed_option.get_item_index(speed_id)
	)

	if speed_index >= 0:
		simulation_speed_option.select(speed_index)

	simulation_time_label.text = (
		"%sPlant %s"
		% [
			"Paused • " if is_paused else "",
			_format_elapsed_time(elapsed_seconds)
		]
	)
	updating_simulation_controls = false


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


func _add_speed_option(label: String, speed_id: int) -> void:
	simulation_speed_option.add_item(label, speed_id)


func _on_simulation_pause_toggled(value: bool) -> void:
	if updating_simulation_controls:
		return

	simulation_pause_requested.emit(value)


func _on_simulation_speed_selected(index: int) -> void:
	if updating_simulation_controls:
		return

	var speed := (
		float(simulation_speed_option.get_item_id(index))
		/ 10.0
	)
	simulation_speed_requested.emit(speed)


func _format_elapsed_time(elapsed_seconds: float) -> String:
	var total_seconds := maxi(int(floor(elapsed_seconds)), 0)
	var days := int(floor(float(total_seconds) / 86400.0))
	var hours := int(
		floor(float(total_seconds % 86400) / 3600.0)
	)
	var minutes := int(
		floor(float(total_seconds % 3600) / 60.0)
	)
	var seconds := total_seconds % 60

	if days > 0:
		return "Day %d %02d:%02d:%02d" % [
			days + 1,
			hours,
			minutes,
			seconds
		]

	return "%02d:%02d:%02d" % [hours, minutes, seconds]


func _on_status_timeout() -> void:
	show_status("Ready", ThemeManager.COLOR_TEXT_MUTED, 0.0)
