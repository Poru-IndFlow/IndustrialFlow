class_name RecipeDefinition
extends RefCounted

var cycle_time := 1.0
var inputs: Array[Dictionary] = []
var outputs: Array[Dictionary] = []
var variables: Dictionary = {}

static func from_machine_definition(definition: Dictionary) -> RecipeDefinition:
	var recipe := RecipeDefinition.new()
	recipe.cycle_time = maxf(0.001, float(definition.get("cycle_time", 1.0)))
	recipe.variables = definition.get("variables", {}).duplicate(true)

	for item: Variant in definition.get("inputs", []):
		if item is Dictionary:
			recipe.inputs.append(item.duplicate(true))

	for item: Variant in definition.get("outputs", []):
		if item is Dictionary:
			recipe.outputs.append(item.duplicate(true))

	return recipe
