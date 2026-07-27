class_name RefreshManager
extends Node


var _pending_refreshes: Dictionary = {}
var _flush_scheduled := false


func request_refresh(key: StringName, callback: Callable) -> void:
	if not callback.is_valid():
		return

	_pending_refreshes[key] = callback

	if _flush_scheduled:
		return

	_flush_scheduled = true
	call_deferred("_flush")


func cancel_refresh(key: StringName) -> void:
	_pending_refreshes.erase(key)


func flush_now() -> void:
	if _pending_refreshes.is_empty():
		_flush_scheduled = false
		return

	var callbacks := _pending_refreshes.values()
	_pending_refreshes.clear()
	_flush_scheduled = false

	for value: Variant in callbacks:
		var callback: Callable = value

		if callback.is_valid():
			callback.call()


func _flush() -> void:
	flush_now()
