extends Node


@onready var editor_toolbar := get_node(
	"../RootVBox/Toolbar"
) as EditorToolbar

@onready var factory_graph := get_node(
	"../RootVBox/Workspace/EditorSplit/FactoryGraph"
)

@onready var machine_palette := get_node(
	"../RootVBox/Workspace/MachinePalette"
)

@onready var machine_inspector := get_node(
	"../RootVBox/Workspace/EditorSplit/MachineInspector"
)

@onready var theme_manager := get_node(
	"../ThemeManager"
) as ThemeManager

@onready var refresh_manager := get_node(
	"../RefreshManager"
) as RefreshManager

@onready var editor_history := get_node(
	"../EditorHistory"
) as EditorHistory

var event_bus: EventBus
var factory: FactoryModel
var clock: SimulationClock
var save_dialog: FileDialog
var load_dialog: FileDialog
var current_project_path := ""


func _ready() -> void:
	theme_manager.apply_to(get_parent() as Control)
	factory_graph.bind_refresh_manager(refresh_manager)
	factory_graph.bind_history(editor_history)
	machine_inspector.bind_refresh_manager(refresh_manager)

	editor_toolbar.undo_requested.connect(editor_history.undo)
	editor_toolbar.redo_requested.connect(editor_history.redo)
	editor_toolbar.save_requested.connect(_on_save_requested)
	editor_toolbar.load_requested.connect(_on_load_requested)
	editor_toolbar.delete_requested.connect(
		_on_delete_requested
	)
	editor_history.history_changed.connect(
		_on_history_changed
	)
	editor_history.action_completed.connect(
		_on_history_action_completed
	)

	machine_palette.machine_requested.connect(
		_on_machine_requested
	)

	factory_graph.machine_selected.connect(
		_on_machine_selected
	)
	factory_graph.selection_changed.connect(
		_on_selection_changed
	)
	factory_graph.machines_deleted.connect(
		_on_machines_deleted
	)

	event_bus = EventBus.new()
	_create_project_dialogs()
	set_factory(PrototypeFactoryBuilder.build(event_bus))

	clock = SimulationClock.new()
	clock.name = "SimulationClock"
	add_child(clock)
	clock.tick_advanced.connect(_on_tick_advanced)
	editor_history.clear()
	editor_toolbar.set_command_availability(
		true,
		true,
		false,
		false
	)


func set_factory(new_factory: FactoryModel) -> void:
	factory = new_factory
	factory_graph.bind_factory(factory)
	machine_inspector.bind_factory(factory)

	if editor_history != null:
		editor_history.clear()


func _on_tick_advanced(delta_seconds: float) -> void:
	if factory != null:
		factory.tick(delta_seconds)

func _on_machine_requested(definition_id: String) -> void:
	factory_graph.request_machine(definition_id)
	editor_toolbar.show_status(
		"Added %s" % definition_id.replace("_", " ").capitalize(),
		ThemeManager.COLOR_SUCCESS
	)

func _on_machine_selected(machine: MachineModel) -> void:
	machine_inspector.show_machine(machine)


func _on_selection_changed(selected_count: int) -> void:
	editor_toolbar.set_selection_count(selected_count)


func _on_delete_requested() -> void:
	factory_graph.delete_selected_machines()


func _on_machines_deleted(deleted_count: int) -> void:
	var noun := "machine" if deleted_count == 1 else "machines"
	editor_toolbar.show_status(
		"Deleted %d %s" % [deleted_count, noun],
		ThemeManager.COLOR_SUCCESS
	)


func _on_history_changed(
	can_undo: bool,
	can_redo: bool,
	undo_label: String,
	redo_label: String
) -> void:
	editor_toolbar.set_history_state(
		can_undo,
		can_redo,
		undo_label,
		redo_label
	)


func _on_history_action_completed(label: String) -> void:
	editor_toolbar.show_status(
		label.capitalize(),
		ThemeManager.COLOR_SUCCESS
	)


func _create_project_dialogs() -> void:
	save_dialog = _create_project_dialog(
		FileDialog.FILE_MODE_SAVE_FILE,
		"Save IndustrialFlow Project"
	)
	save_dialog.current_file = "factory.iflow"
	save_dialog.file_selected.connect(_on_save_file_selected)

	load_dialog = _create_project_dialog(
		FileDialog.FILE_MODE_OPEN_FILE,
		"Load IndustrialFlow Project"
	)
	load_dialog.file_selected.connect(_on_load_file_selected)


func _create_project_dialog(
	file_mode: int,
	title: String
) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = file_mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = title
	dialog.filters = PackedStringArray([
		"*.iflow ; IndustrialFlow Project"
	])
	dialog.current_dir = ProjectSettings.globalize_path("user://")
	add_child(dialog)
	return dialog


func _on_save_requested() -> void:
	if current_project_path.is_empty():
		save_dialog.popup_centered_ratio(0.7)
		return

	_save_to_path(current_project_path)


func _on_load_requested() -> void:
	load_dialog.popup_centered_ratio(0.7)


func _on_save_file_selected(path: String) -> void:
	var save_path := path

	if not save_path.ends_with(".iflow"):
		save_path += ".iflow"

	_save_to_path(save_path)


func _save_to_path(path: String) -> void:
	var error := FactoryPersistence.save_factory(path, factory)

	if error != OK:
		editor_toolbar.show_status(
			"Save failed: %s" % error_string(error),
			ThemeManager.COLOR_DANGER,
			5.0
		)
		return

	current_project_path = path
	editor_toolbar.show_status(
		"Saved %s" % path.get_file(),
		ThemeManager.COLOR_SUCCESS
	)
	get_window().title = "IndustrialFlow Editor — %s" % path.get_file()


func _on_load_file_selected(path: String) -> void:
	var loaded_event_bus := EventBus.new()
	var result := FactoryPersistence.load_factory(
		path,
		loaded_event_bus
	)
	var error := int(result.get("error", FAILED))

	if error != OK:
		editor_toolbar.show_status(
			"Load failed: %s" % str(result.get("message", "")),
			ThemeManager.COLOR_DANGER,
			6.0
		)
		return

	var loaded_factory := result.get("factory") as FactoryModel

	if loaded_factory == null:
		editor_toolbar.show_status(
			"Load failed: no factory was created.",
			ThemeManager.COLOR_DANGER,
			6.0
		)
		return

	current_project_path = path
	event_bus = loaded_event_bus
	set_factory(loaded_factory)
	editor_toolbar.show_status(
		"Loaded %s" % path.get_file(),
		ThemeManager.COLOR_SUCCESS
	)
	get_window().title = "IndustrialFlow Editor — %s" % path.get_file()
