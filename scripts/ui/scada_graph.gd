class_name ScadaGraph
extends GraphEdit


const CONNECTION_STUB := 20.0
const MIN_CONNECTION_STUB := 4.0
const STUB_GAP_RATIO := 0.20
const REVERSE_ROUTE_CLEARANCE := 56.0
const UTILITY_BUS_CLEARANCE := 54.0
const UTILITY_BUS_SPACING := 34.0
const UTILITY_BRANCH_SPACING := 18.0
const PORT_MATCH_TOLERANCE := 2.0
const UTILITY_RESOURCES: Array[String] = ["water", "steam", "gas"]


func _get_connection_line(
	from_position: Vector2,
	to_position: Vector2
) -> PackedVector2Array:
	var horizontal_gap := to_position.x - from_position.x
	var stub_length := CONNECTION_STUB
	if horizontal_gap > 0.0:
		stub_length = minf(
			CONNECTION_STUB,
			maxf(MIN_CONNECTION_STUB, horizontal_gap * STUB_GAP_RATIO)
		)
	var from_stub := from_position + Vector2(stub_length, 0.0)
	var to_stub := to_position - Vector2(stub_length, 0.0)
	var resource_id := _resource_for_output_position(from_position)
	if UTILITY_RESOURCES.has(resource_id):
		return _build_utility_bus_route(
			from_position,
			to_position,
			from_stub,
			to_stub,
			resource_id
		)

	return _build_direct_route(from_position, to_position, from_stub, to_stub)


func _build_direct_route(
	from_position: Vector2,
	to_position: Vector2,
	from_stub: Vector2,
	to_stub: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()

	points.append(from_position)
	points.append(from_stub)

	if from_stub.x <= to_stub.x:
		var middle_x := (from_stub.x + to_stub.x) * 0.5
		points.append(Vector2(middle_x, from_stub.y))
		points.append(Vector2(middle_x, to_stub.y))
	else:
		var detour_y := minf(from_stub.y, to_stub.y) - REVERSE_ROUTE_CLEARANCE
		points.append(Vector2(from_stub.x, detour_y))
		points.append(Vector2(to_stub.x, detour_y))

	points.append(to_stub)
	points.append(to_position)
	return _remove_duplicate_points(points)


func _build_utility_bus_route(
	from_position: Vector2,
	to_position: Vector2,
	from_stub: Vector2,
	to_stub: Vector2,
	resource_id: String
) -> PackedVector2Array:
	var bus_y := _utility_bus_y(resource_id)
	var lane_index := maxi(UTILITY_RESOURCES.find(resource_id), 0)
	var branch_offset := (
		float(lane_index + 1)
		* UTILITY_BRANCH_SPACING
		* zoom
	)
	var source_riser_x := from_stub.x + branch_offset
	var destination_riser_x := to_stub.x - branch_offset
	var points := PackedVector2Array([
		from_position,
		from_stub,
		Vector2(source_riser_x, from_stub.y),
		Vector2(source_riser_x, bus_y),
		Vector2(destination_riser_x, bus_y),
		Vector2(destination_riser_x, to_stub.y),
		to_stub,
		to_position
	])
	return _remove_duplicate_points(points)


func _utility_bus_y(resource_id: String) -> float:
	var bottom := -INF
	for child: Node in get_children():
		var node := child as GraphNode
		if node == null:
			continue
		var rect := _graph_node_rect(node)
		bottom = maxf(bottom, rect.end.y)

	if is_inf(bottom):
		return 0.0

	var lane_index := UTILITY_RESOURCES.find(resource_id)
	if lane_index < 0:
		lane_index = 0
	return (
		bottom
		+ UTILITY_BUS_CLEARANCE * zoom
		+ float(lane_index) * UTILITY_BUS_SPACING * zoom
	)


func _resource_for_output_position(from_position: Vector2) -> String:
	for child: Node in get_children():
		var node := child as GraphNode
		if node == null or not node.has_meta("scada_output_resources"):
			continue

		var resource_value: Variant = node.get_meta("scada_output_resources")
		if not resource_value is Array:
			continue
		var resources: Array = resource_value as Array
		var output_count := mini(node.get_output_port_count(), resources.size())
		for port_index: int in range(output_count):
			var port_position := (
				node.position_offset
				+ node.get_output_port_position(port_index)
			) * zoom
			if port_position.distance_to(from_position) <= PORT_MATCH_TOLERANCE:
				return str(resources[port_index])

	return ""


func _graph_node_rect(node: GraphNode) -> Rect2:
	var node_size := Vector2(
		maxf(node.size.x, node.custom_minimum_size.x),
		maxf(node.size.y, node.custom_minimum_size.y)
	)
	# GraphEdit passes connection points to _get_connection_line() in graph
	# coordinates scaled by zoom. Its connection layer applies scroll_offset
	# separately, so obstacle rectangles must use the same unscrolled space.
	return Rect2(node.position_offset * zoom, node_size * zoom)


func _remove_duplicate_points(points: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for point: Vector2 in points:
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_to(point) > 0.01:
			cleaned.append(point)
	return cleaned
