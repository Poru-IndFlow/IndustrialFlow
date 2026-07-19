class_name Inventory
extends RefCounted

var amounts: Dictionary = {}
var capacities: Dictionary = {}

func _init(initial_capacities: Dictionary = {}) -> void:
	for key: Variant in initial_capacities.keys():
		var id := str(key)
		capacities[id] = float(initial_capacities[key])
		amounts[id] = 0.0

func get_amount(id: String) -> float:
	return float(amounts.get(id, 0.0))

func get_capacity(id: String) -> float:
	return float(capacities.get(id, INF))

func get_free_capacity(id: String) -> float:
	return maxf(0.0, get_capacity(id) - get_amount(id))

func add(id: String, amount: float) -> float:
	var accepted := minf(maxf(amount, 0.0), get_free_capacity(id))
	amounts[id] = get_amount(id) + accepted
	return accepted

func remove(id: String, amount: float) -> float:
	var removed := minf(maxf(amount, 0.0), get_amount(id))
	amounts[id] = get_amount(id) - removed
	return removed

func can_add(id: String, amount: float) -> bool:
	return get_free_capacity(id) >= amount

func can_remove(id: String, amount: float) -> bool:
	return get_amount(id) >= amount
