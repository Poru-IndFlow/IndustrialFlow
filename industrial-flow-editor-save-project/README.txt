INDUSTRIAL FLOW — EDITOR, INSPECTOR AND SAVE/LOAD BUILD

OPENING
1. Extract this ZIP.
2. Import IndustrialFlowEditor/project.godot into Godot 4.
3. Run the main scene.

NEW FEATURES
- Select GraphNodes to inspect machines.
- Live property inspector for identity, state, position and inventory.
- Enable or disable a selected machine.
- Delete selected machines with the toolbar, inspector or Delete key.
- Machine deletion supports undo and restores its previous connections.
- Ctrl+Z and Ctrl+Y perform undo and redo.
- Ctrl+S saves the complete factory to user://factory_save.json.
- Ctrl+L loads the saved factory.
- Save data includes:
  machine types and instance IDs
  graph positions
  enabled states
  inventories
  connections and transfer capacities
- Loaded factories rebuild generated instance counters.
- Machine palette remains fully data-driven.

CURRENT LIMITATIONS
- Enabled-state and position changes are saved, but are not command objects.
- Save/load uses one fixed save slot.
- No confirmation dialog before loading or deleting.
- Graph zoom and scroll position are not saved.

NEXT RECOMMENDED MILESTONE
Add economy, utility consumption and a production statistics panel.
