class_name MachineBehaviour
extends RefCounted


func tick(_machine: MachineModel, _delta_seconds: float) -> void:
	push_error("MachineBehaviour.tick() must be implemented by a subclass.")