class_name FormulaEvaluator
extends RefCounted

static func evaluate(formula: String, variables: Dictionary) -> float:
	var names := PackedStringArray()
	var values: Array = []

	for key: Variant in variables.keys():
		names.append(str(key))
		values.append(variables[key])

	var expression := Expression.new()
	if expression.parse(formula, names) != OK:
		push_error("Formula parse error '%s': %s" % [
			formula, expression.get_error_text()
		])
		return 0.0

	var result: Variant = expression.execute(values, null, false, true)
	if expression.has_execute_failed():
		push_error("Formula execution failed: %s" % formula)
		return 0.0

	if not result is int and not result is float:
		push_error("Formula did not return a number: %s" % formula)
		return 0.0

	return float(result)
