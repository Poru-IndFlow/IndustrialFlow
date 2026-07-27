class_name StorageBehaviour
extends MachineBehaviour


func tick(machine: MachineModel, _delta_seconds: float) -> void:
	machine.cycle_progress = 0.0
	machine.set_state(MachineModel.State.IDLE)