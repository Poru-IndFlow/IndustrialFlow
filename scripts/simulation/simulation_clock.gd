class_name SimulationClock
extends Node

signal tick_advanced(delta_seconds: float)

@export var ticks_per_second := 5.0
@export var simulation_speed := 1.0
var paused := false
var elapsed_simulation_seconds := 0.0
var _accumulator := 0.0


func _process(delta: float) -> void:
	if paused or ticks_per_second <= 0.0:
		return

	var tick_duration := 1.0 / ticks_per_second
	_accumulator += delta * simulation_speed

	while _accumulator >= tick_duration:
		_accumulator -= tick_duration
		elapsed_simulation_seconds += tick_duration
		tick_advanced.emit(tick_duration)


func set_paused(value: bool) -> void:
	paused = value


func set_simulation_speed(value: float) -> void:
	simulation_speed = clampf(value, 0.1, 100.0)


func set_elapsed_simulation_seconds(value: float) -> void:
	elapsed_simulation_seconds = maxf(value, 0.0)
	_accumulator = 0.0
