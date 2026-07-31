class_name ControllerTrendPlot
extends Control


const COLOR_INVENTORY := Color("#52b7ff")
const COLOR_SETPOINT := Color("#f4c95d")
const COLOR_ERROR := Color("#ff7b72")
const COLOR_OUTPUT := Color("#7ee787")
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.10)
const COLOR_AXIS := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_TEXT := Color(1.0, 1.0, 1.0, 0.70)

var samples: Array[Dictionary] = []
var resource_unit := ""


func _ready() -> void:
	custom_minimum_size = Vector2(500, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_samples(
	new_samples: Array[Dictionary],
	unit: String
) -> void:
	samples = new_samples
	resource_unit = unit
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("#111820"))

	var plot := Rect2(
		Vector2(64.0, 20.0),
		Vector2(
			maxf(size.x - 124.0, 1.0),
			maxf(size.y - 62.0, 1.0)
		)
	)
	_draw_grid(plot)

	if samples.size() < 2:
		_draw_centered_message(
			plot,
			"Run the simulation to collect trend data."
		)
		return

	var left_range := _get_left_range()
	var first_time := float(samples.front().get("time", 0.0))
	var last_time := float(samples.back().get("time", 1.0))
	var time_span := maxf(last_time - first_time, 1.0)

	_draw_series(
		plot,
		"inventory",
		COLOR_INVENTORY,
		left_range.x,
		left_range.y,
		first_time,
		time_span
	)
	_draw_series(
		plot,
		"setpoint",
		COLOR_SETPOINT,
		left_range.x,
		left_range.y,
		first_time,
		time_span
	)
	_draw_series(
		plot,
		"error",
		COLOR_ERROR,
		left_range.x,
		left_range.y,
		first_time,
		time_span
	)
	_draw_series(
		plot,
		"output",
		COLOR_OUTPUT,
		0.0,
		150.0,
		first_time,
		time_span
	)
	_draw_axis_labels(plot, left_range, time_span)


func _draw_grid(plot: Rect2) -> void:
	draw_rect(plot, Color("#17212b"))

	for index: int in range(6):
		var weight := float(index) / 5.0
		var y := plot.position.y + plot.size.y * weight
		draw_line(
			Vector2(plot.position.x, y),
			Vector2(plot.end.x, y),
			COLOR_GRID
		)

	for index: int in range(7):
		var weight := float(index) / 6.0
		var x := plot.position.x + plot.size.x * weight
		draw_line(
			Vector2(x, plot.position.y),
			Vector2(x, plot.end.y),
			COLOR_GRID
		)

	draw_rect(plot, COLOR_AXIS, false, 1.0)


func _get_left_range() -> Vector2:
	var minimum := 0.0
	var maximum := 1.0

	for sample: Dictionary in samples:
		minimum = minf(
			minimum,
			float(sample.get("error", 0.0))
		)
		maximum = maxf(
			maximum,
			maxf(
				float(sample.get("inventory", 0.0)),
				float(sample.get("setpoint", 0.0))
			)
		)

	if is_equal_approx(minimum, maximum):
		maximum = minimum + 1.0

	var padding := (maximum - minimum) * 0.08
	return Vector2(minimum - padding, maximum + padding)


func _draw_series(
	plot: Rect2,
	key: String,
	color: Color,
	minimum: float,
	maximum: float,
	first_time: float,
	time_span: float
) -> void:
	var points := PackedVector2Array()
	var value_span := maxf(maximum - minimum, 0.001)

	for sample: Dictionary in samples:
		var time_weight := (
			(float(sample.get("time", first_time)) - first_time)
			/ time_span
		)
		var value := float(sample.get(key, 0.0))
		var value_weight := (value - minimum) / value_span
		points.append(Vector2(
			plot.position.x + plot.size.x * time_weight,
			plot.end.y - plot.size.y * value_weight
		))

	if points.size() >= 2:
		draw_polyline(points, color, 2.0, true)


func _draw_axis_labels(
	plot: Rect2,
	left_range: Vector2,
	time_span: float
) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var top_left := "%.0f %s" % [left_range.y, resource_unit]
	var bottom_left := "%.0f %s" % [
		left_range.x,
		resource_unit
	]

	draw_string(
		font,
		Vector2(4.0, plot.position.y + font_size),
		top_left,
		HORIZONTAL_ALIGNMENT_LEFT,
		56.0,
		font_size,
		COLOR_TEXT
	)
	draw_string(
		font,
		Vector2(4.0, plot.end.y),
		bottom_left,
		HORIZONTAL_ALIGNMENT_LEFT,
		56.0,
		font_size,
		COLOR_TEXT
	)
	draw_string(
		font,
		Vector2(plot.end.x + 8.0, plot.position.y + font_size),
		"150%",
		HORIZONTAL_ALIGNMENT_LEFT,
		48.0,
		font_size,
		COLOR_OUTPUT
	)
	draw_string(
		font,
		Vector2(plot.end.x + 8.0, plot.end.y),
		"0%",
		HORIZONTAL_ALIGNMENT_LEFT,
		48.0,
		font_size,
		COLOR_OUTPUT
	)
	draw_string(
		font,
		Vector2(plot.position.x, plot.end.y + 24.0),
		"−%.0f s" % time_span,
		HORIZONTAL_ALIGNMENT_LEFT,
		80.0,
		font_size,
		COLOR_TEXT
	)
	draw_string(
		font,
		Vector2(plot.end.x - 42.0, plot.end.y + 24.0),
		"Now",
		HORIZONTAL_ALIGNMENT_RIGHT,
		42.0,
		font_size,
		COLOR_TEXT
	)


func _draw_centered_message(plot: Rect2, message: String) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	draw_string(
		font,
		Vector2(
			plot.position.x,
			plot.position.y + plot.size.y * 0.5
		),
		message,
		HORIZONTAL_ALIGNMENT_CENTER,
		plot.size.x,
		font_size,
		COLOR_TEXT
	)
