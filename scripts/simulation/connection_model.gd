class_name ConnectionModel
extends RefCounted

var from_machine: MachineModel
var to_machine: MachineModel
var resource_id := ""
var capacity_per_second := 1.0
var enabled := true

func _init(
	source: MachineModel,
	destination: MachineModel,
	resource: String,
	capacity := 1.0
) -> void:
	from_machine = source
	to_machine = destination
	resource_id = resource
	capacity_per_second = maxf(capacity, 0.0)

func tick(delta_seconds: float) -> float:
	if not enabled or from_machine == null or to_machine == null:
		return 0.0

	var amount := minf(
		capacity_per_second * delta_seconds,
		minf(
			from_machine.inventory.get_amount(resource_id),
			to_machine.inventory.get_free_capacity(resource_id)
		)
	)

	if amount <= 0.0:
		return 0.0

	var removed := from_machine.inventory.remove(resource_id, amount)
	var accepted := to_machine.inventory.add(resource_id, removed)

	if accepted < removed:
		from_machine.inventory.add(resource_id, removed - accepted)

	from_machine.notify_inventory_changed()
	to_machine.notify_inventory_changed()
	return accepted
