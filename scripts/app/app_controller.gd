extends Node


@onready var editor_toolbar := get_node(
	"../RootVBox/Toolbar"
) as EditorToolbar

@onready var factory_graph := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Factory Graph"
)

@onready var plant_overview := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Plant Overview"
) as PlantOverview

@onready var scada_workspace := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/SCADA"
) as ScadaWorkspace

@onready var controller_trends := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Controller Trends"
) as ControllerTrends

@onready var economy_trends := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Economy Trends"
) as EconomyTrends

@onready var research_workspace := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Research"
) as ResearchWorkspace

@onready var production_planning := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs/Production Planning"
) as ProductionPlanning

@onready var workspace_tabs := get_node(
	"../RootVBox/Workspace/EditorSplit/WorkspaceTabs"
) as TabContainer

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
var last_displayed_simulation_second := -1
var factory_graph_selection_count := 0


func _ready() -> void:
	theme_manager.apply_to(get_parent() as Control)
	factory_graph.bind_refresh_manager(refresh_manager)
	factory_graph.bind_history(editor_history)
	machine_inspector.bind_refresh_manager(refresh_manager)
	machine_inspector.bind_history(editor_history)
	plant_overview.bind_refresh_manager(refresh_manager)
	plant_overview.machine_requested.connect(
		_on_overview_machine_requested
	)
	scada_workspace.machine_requested.connect(
		_on_scada_machine_requested
	)
	workspace_tabs.tab_changed.connect(_on_workspace_tab_changed)

	editor_toolbar.undo_requested.connect(editor_history.undo)
	editor_toolbar.redo_requested.connect(editor_history.redo)
	editor_toolbar.save_requested.connect(_on_save_requested)
	editor_toolbar.load_requested.connect(_on_load_requested)
	editor_toolbar.delete_requested.connect(
		_on_delete_requested
	)
	editor_toolbar.simulation_pause_requested.connect(
		_on_simulation_pause_requested
	)
	editor_toolbar.simulation_speed_requested.connect(
		_on_simulation_speed_requested
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
	factory_graph.connection_selected.connect(
		_on_connection_selected
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
	_update_simulation_toolbar(true)
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
	machine_palette.bind_factory(factory)
	machine_inspector.bind_factory(factory)
	plant_overview.bind_factory(factory)
	scada_workspace.bind_factory(factory)
	controller_trends.bind_factory(factory)
	economy_trends.bind_factory(factory)
	research_workspace.bind_factory(factory)
	production_planning.bind_factory(factory)

	if editor_history != null:
		editor_history.clear()


func _on_tick_advanced(delta_seconds: float) -> void:
	if factory != null:
		factory.tick(delta_seconds)
		scada_workspace.advance(delta_seconds)
		controller_trends.advance(delta_seconds)
		production_planning.advance(delta_seconds)
		_update_simulation_toolbar()


func _on_simulation_pause_requested(value: bool) -> void:
	if clock == null:
		return

	clock.set_paused(value)
	_update_simulation_toolbar(true)


func _on_simulation_speed_requested(value: float) -> void:
	if clock == null:
		return

	clock.set_simulation_speed(value)
	_update_simulation_toolbar(true)


func _update_simulation_toolbar(force: bool = false) -> void:
	if clock == null:
		return

	var displayed_second := int(
		floor(clock.elapsed_simulation_seconds)
	)

	if (
		not force
		and displayed_second == last_displayed_simulation_second
	):
		return

	last_displayed_simulation_second = displayed_second
	editor_toolbar.set_simulation_state(
		clock.paused,
		clock.simulation_speed,
		clock.elapsed_simulation_seconds
	)

func _on_machine_requested(definition_id: String) -> void:
	if factory_graph.request_machine(definition_id):
		editor_toolbar.show_status(
			"Purchased %s" % definition_id.replace("_", " ").capitalize(),
			ThemeManager.COLOR_SUCCESS
		)
		return

	editor_toolbar.show_status(
		"Insufficient cash for %s" % definition_id.replace("_", " ").capitalize(),
		ThemeManager.COLOR_DANGER,
		4.0
	)

func _on_machine_selected(machine: MachineModel) -> void:
	machine_inspector.show_machine(machine)
	controller_trends.show_machine(machine)


func _on_connection_selected(connection: ConnectionModel) -> void:
	machine_inspector.show_connection(connection)
	controller_trends.show_machine(null)


func _on_overview_machine_requested(machine_id: String) -> void:
	workspace_tabs.current_tab = 0
	factory_graph.call_deferred(
		"select_and_focus_machine",
		machine_id
	)


func _on_scada_machine_requested(machine: MachineModel) -> void:
	machine_inspector.show_machine(machine)
	controller_trends.show_machine(machine)


func _on_selection_changed(selected_count: int) -> void:
	factory_graph_selection_count = selected_count

	if workspace_tabs.current_tab == 0:
		editor_toolbar.set_selection_count(selected_count)


func _on_workspace_tab_changed(tab_index: int) -> void:
	var selected_workspace := workspace_tabs.get_tab_control(tab_index)
	var is_factory_graph := selected_workspace == factory_graph
	var is_production_planning := selected_workspace == production_planning
	machine_palette.visible = is_factory_graph
	machine_inspector.visible = not is_production_planning
	editor_toolbar.set_selection_count(
		factory_graph_selection_count if is_factory_graph else 0
	)


func _on_delete_requested() -> void:
	if workspace_tabs.current_tab == 0:
		factory_graph.delete_selected_machines()


func _on_machines_deleted(
	deleted_count: int,
	salvage_value: float
) -> void:
	var noun := "machine" if deleted_count == 1 else "machines"
	editor_toolbar.show_status(
		"Sold %d %s for $%.2f" % [
			deleted_count,
			noun,
			salvage_value
		],
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
	var elapsed_seconds := (
		clock.elapsed_simulation_seconds
		if clock != null
		else 0.0
	)
	var error := FactoryPersistence.save_factory(
		path,
		factory,
		elapsed_seconds
	)

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

	if clock != null:
		clock.set_elapsed_simulation_seconds(
			float(
				result.get(
					"elapsed_simulation_seconds",
					0.0
				)
			)
		)
		_update_simulation_toolbar(true)

	editor_toolbar.show_status(
		"Loaded %s" % path.get_file(),
		ThemeManager.COLOR_SUCCESS
	)
	get_window().title = "IndustrialFlow Editor — %s" % path.get_file()
