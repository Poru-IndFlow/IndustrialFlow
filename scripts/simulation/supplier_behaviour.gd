class_name SupplierBehaviour
extends MachineBehaviour


func tick(machine: MachineModel, delta_seconds: float) -> void:
	var outputs := _calculate_outputs(machine)

	for output: Dictionary in outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))

		if not machine.inventory.can_add(resource_id, amount):
			machine.set_state(MachineModel.State.BLOCKED_OUTPUT)
			return

	machine.set_state(MachineModel.State.RUNNING)
	machine.cycle_progress += delta_seconds

	while machine.cycle_progress >= machine.recipe.cycle_time:
		for output: Dictionary in outputs:
			var resource_id := str(output.get("resource", ""))
			var amount := float(output.get("amount", 0.0))
			machine.inventory.add(resource_id, amount)

		machine.cycle_progress -= machine.recipe.cycle_time
		machine.notify_inventory_changed()


func _calculate_outputs(machine: MachineModel) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	for output: Dictionary in machine.recipe.outputs:
		var resource_id := str(output.get("resource", ""))
		var amount := float(output.get("amount", 0.0))

		if output.has("formula"):
			amount = FormulaEvaluator.evaluate(
				str(output.get("formula", "0")),
				machine.recipe.variables
			)

		results.append({
			"resource": resource_id,
			"amount": maxf(amount, 0.0)
		})

	return results