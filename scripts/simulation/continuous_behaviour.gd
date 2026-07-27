class_name ContinuousBehaviour
extends MachineBehaviour


func tick(machine: MachineModel, delta_seconds: float) -> void:
	if not _has_required_inputs(machine):
		machine.cycle_progress = 0.0
		machine.set_state(MachineModel.State.BLOCKED_INPUT)
		return

	var outputs := _calculate_outputs(machine)
	if not _has_output_capacity(machine, outputs):
		machine.set_state(MachineModel.State.BLOCKED_OUTPUT)
		return

	machine.set_state(MachineModel.State.RUNNING)
	machine.cycle_progress += delta_seconds

	if machine.cycle_progress < machine.recipe.cycle_time:
		return

	for input: Dictionary in machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		var amount := float(input.get("amount", 0.0))
		machine.inventory.remove(resource_id, amount)

	for output: Dictionary in outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))
		machine.inventory.add(resource_id, amount)

	machine.cycle_progress -= machine.recipe.cycle_time
	machine.notify_inventory_changed()


func _has_required_inputs(machine: MachineModel) -> bool:
	for input: Dictionary in machine.recipe.inputs:
		var resource_id := str(input.get("resource", ""))
		var amount := float(input.get("amount", 0.0))

		if not machine.inventory.can_remove(resource_id, amount):
			return false

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