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

var event_bus: EventBus
var factory: FactoryModel
var clock: SimulationClock


func _ready() -> void:
	theme_manager.apply_to(get_parent() as Control)
	factory_graph.bind_refresh_manager(refresh_manager)
	machine_inspector.bind_refresh_manager(refresh_manager)

	editor_toolbar.delete_requested.connect(
		_on_delete_requested
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
	set_factory(PrototypeFactoryBuilder.build(event_bus))

	clock = SimulationClock.new()
	clock.name = "SimulationClock"
	add_child(clock)
	clock.tick_advanced.connect(_on_tick_advanced)


func set_factory(new_factory: FactoryModel) -> void:
	factory = new_factory
	factory_graph.bind_factory(factory)
	machine_inspector.bind_factory(factory)


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
