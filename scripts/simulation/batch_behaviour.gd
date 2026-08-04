class_name BatchBehaviour
extends MachineBehaviour


func tick(machine: MachineModel, delta_seconds: float) -> void:
	if machine.batch_held:
		machine.set_state(MachineModel.State.IDLE)
		return

	if not machine.batch_active:
		if not _start_batch(machine):
			return

	if not _has_output_capacity(machine, machine.batch_outputs):
		machine.set_state(MachineModel.State.BLOCKED_OUTPUT)
		return

	machine.set_state(MachineModel.State.RUNNING)
	machine.cycle_progress = minf(
		machine.recipe.cycle_time,
		machine.cycle_progress
		+ delta_seconds * machine.get_effective_production_rate()
	)
	if machine.event_bus != null:
		machine.event_bus.machine_performance_changed.emit(machine)

	if machine.cycle_progress < machine.recipe.cycle_time:
		return

	for output: Dictionary in machine.batch_outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))
		var produced := machine.inventory.add(resource_id, amount)
		machine.record_produced(resource_id, produced)

	machine.batch_active = false
	machine.batch_outputs.clear()
	machine.cycle_progress = 0.0
	machine.batch_count += 1
	machine.batch_held = machine.hold_after_batch
	machine.notify_inventory_changed()
	machine.notify_settings_changed()


func _start_batch(machine: MachineModel) -> bool:
	for input: Dictionary in machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		var amount := float(input.get("amount", 0.0))

		if not machine.inventory.can_remove(resource_id, amount):
			machine.cycle_progress = 0.0
			machine.set_state(MachineModel.State.BLOCKED_INPUT)
			return false

	var outputs := _calculate_outputs(machine)

	if not _has_output_capacity(machine, outputs):
		machine.set_state(MachineModel.State.BLOCKED_OUTPUT)
		return false

	for input: Dictionary in machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		var amount := float(input.get("amount", 0.0))
		var consumed := machine.inventory.remove(resource_id, amount)
		machine.record_consumed(resource_id, consumed)

	machine.batch_outputs = outputs
	machine.batch_active = true
	machine.cycle_progress = 0.0
	machine.notify_inventory_changed()
	return true


func _has_output_capacity(
	machine: MachineModel,
	outputs: Array[Dictionary]
) -> bool:
	for output: Dictionary in outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))

		if not machine.inventory.can_add(resource_id, amount):
			return false

	return true


func _calculate_outputs(machine: MachineModel) -> Array[Dictionary]:
	var variables := machine.recipe.variables.duplicate(true)
	var results: Array[Dictionary] = []

	for input: Dictionary in machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		variables[resource_id] = float(input.get("amount", 0.0))

	for output: Dictionary in machine.recipe.outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))

		if output.has("formula"):
			amount = FormulaEvaluator.evaluate(
				str(output.get("formula", "0")),
				variables
			)

		results.append({
			"resource": resource_id,
			"amount": maxf(amount, 0.0)
		})

	return results
