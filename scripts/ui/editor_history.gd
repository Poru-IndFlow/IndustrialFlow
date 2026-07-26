class_name EditorHistory
extends Node


signal history_changed(
	can_undo: bool,
	can_redo: bool,
	undo_label: String,
	redo_label: String
)
signal action_completed(label: String)


const MAX_HISTORY_SIZE := 100


var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_replaying := false


func execute(
	label: String,
	do_action: Callable,
	undo_action: Callable
) -> void:
	if not do_action.is_valid() or not undo_action.is_valid():
		return

	do_action.call()

	if _is_replaying:
		return

	_record_action(label, do_action, undo_action)


func record_completed(
	label: String,
	redo_action: Callable,
	undo_action: Callable
) -> void:
	if (
		_is_replaying
		or not redo_action.is_valid()
		or not undo_action.is_valid()
	):
		return

	_record_action(label, redo_action, undo_action)


func undo() -> void:
	if _undo_stack.is_empty():
		return

	var action: Dictionary = _undo_stack.pop_back()
	var undo_action: Callable = action["undo"]
	_is_replaying = true
	undo_action.call()
	_is_replaying = false
	_redo_stack.append(action)
	action_completed.emit("Undid %s" % str(action["label"]))
	_emit_history_changed()


func redo() -> void:
	if _redo_stack.is_empty():
		return

	var action: Dictionary = _redo_stack.pop_back()
	var redo_action: Callable = action["redo"]
	_is_replaying = true
	redo_action.call()
	_is_replaying = false
	_undo_stack.append(action)
	action_completed.emit("Redid %s" % str(action["label"]))
	_emit_history_changed()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_history_changed()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func get_undo_label() -> String:
	if _undo_stack.is_empty():
		return ""

	return str(_undo_stack.back()["label"])


func get_redo_label() -> String:
	if _redo_stack.is_empty():
		return ""

	return str(_redo_stack.back()["label"])


func _record_action(
	label: String,
	redo_action: Callable,
	undo_action: Callable
) -> void:
	_undo_stack.append({
		"label": label,
		"redo": redo_action,
		"undo": undo_action
	})
	_redo_stack.clear()

	if _undo_stack.size() > MAX_HISTORY_SIZE:
		_undo_stack.pop_front()

	action_completed.emit(label)
	_emit_history_changed()


func _emit_history_changed() -> void:
	history_changed.emit(
		can_undo(),
		can_redo(),
		get_undo_label(),
		get_redo_label()
	)
