class_name EconomyTrendPlot
extends Control


const COLOR_CASH := Color("#52b7ff")
const COLOR_REVENUE := Color("#7ee787")
const COLOR_EXPENSES := Color("#ff7b72")
const COLOR_NET := Color("#f4c95d")
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.10)
const COLOR_AXIS := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_TEXT := Color(1.0, 1.0, 1.0, 0.70)

var samples: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(500, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_samples(new_samples: Array[Dictionary]) -> void:
	samples = new_samples
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("#111820"))
	var plot := Rect2(
		Vector2(72.0, 20.0),
		Vector2(
			maxf(size.x - 144.0, 1.0),
			maxf(size.y - 62.0, 1.0)
		)
	)
	_draw_grid(plot)

	if samples.size() < 2:
		_draw_centered_message(
			plot,
			"Run the simulation to collect economy data."
		)
		return

	var cash_range := _get_series_range(["cash"], false)
	var flow_range := _get_series_range(
		["revenue", "expenses", "net"],
		true
	)
	var first_time := float(samples.front().get("time", 0.0))
	var last_time := float(samples.back().get("time", 1.0))
	var time_span := maxf(last_time - first_time, 1.0)

	_draw_series(
		plot, "cash", COLOR_CASH, cash_range,
		first_time, time_span
	)
	_draw_series(
		plot, "revenue", COLOR_REVENUE, flow_range,
		first_time, time_span
	)
	_draw_series(
		plot, "expenses", COLOR_EXPENSES, flow_range,
		first_time, time_span
	)
	_draw_series(
		plot, "net", COLOR_NET, flow_range,
		first_time, time_span
	)
	_draw_axis_labels(plot, cash_range, flow_range, time_span)


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


func _get_series_range(keys: Array[String], include_zero: bool) -> Vector2:
	var minimum := 0.0
	var maximum := 0.0
	var initialized := include_zero

	for sample: Dictionary in samples:
		for key: String in keys:
			var value := float(sample.get(key, 0.0))

			if not initialized:
				minimum = value
				maximum = value
				initialized = true
				continue

			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)

	if not initialized:
		return Vector2(0.0, 1.0)

	if is_equal_approx(minimum, maximum):
		var expansion := maxf(absf(minimum) * 0.05, 1.0)
		minimum -= expansion
		maximum += expansion

	var padding := (maximum - minimum) * 0.08
	return Vector2(minimum - padding, maximum + padding)


func _draw_series(
	plot: Rect2,
	key: String,
	color: Color,
	value_range: Vector2,
	first_time: float,
	time_span: float
) -> void:
	var points := PackedVector2Array()
	var value_span := maxf(value_range.y - value_range.x, 0.001)

	for sample: Dictionary in samples:
		var time_weight := (
			(float(sample.get("time", first_time)) - first_time)
			/ time_span
		)
		var value := float(sample.get(key, 0.0))
		var value_weight := (value - value_range.x) / value_span
		points.append(Vector2(
			plot.position.x + plot.size.x * time_weight,
			plot.end.y - plot.size.y * value_weight
		))

	if points.size() >= 2:
		draw_polyline(points, color, 2.0, true)


func _draw_axis_labels(
	plot: Rect2,
	cash_range: Vector2,
	flow_range: Vector2,
	time_span: float
) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	_draw_label(
		font, font_size,
		Vector2(4.0, plot.position.y + font_size),
		"$%.0f" % cash_range.y,
		56.0, HORIZONTAL_ALIGNMENT_LEFT, COLOR_CASH
	)
	_draw_label(
		font, font_size,
		Vector2(4.0, plot.end.y),
		"$%.0f" % cash_range.x,
		56.0, HORIZONTAL_ALIGNMENT_LEFT, COLOR_CASH
	)
	_draw_label(
		font, font_size,
		Vector2(plot.end.x + 8.0, plot.position.y + font_size),
		"$%.2f/s" % flow_range.y,
		62.0, HORIZONTAL_ALIGNMENT_LEFT, COLOR_TEXT
	)
	_draw_label(
		font, font_size,
		Vector2(plot.end.x + 8.0, plot.end.y),
		"$%.2f/s" % flow_range.x,
		62.0, HORIZONTAL_ALIGNMENT_LEFT, COLOR_TEXT
	)
	_draw_label(
		font, font_size,
		Vector2(plot.position.x, plot.end.y + 24.0),
		"−%.0f s" % time_span,
		80.0, HORIZONTAL_ALIGNMENT_LEFT, COLOR_TEXT
	)
	_draw_label(
		font, font_size,
		Vector2(plot.end.x - 42.0, plot.end.y + 24.0),
		"Now",
		42.0, HORIZONTAL_ALIGNMENT_RIGHT, COLOR_TEXT
	)


func _draw_label(
	font: Font,
	font_size: int,
	position: Vector2,
	text: String,
	width: float,
	alignment: HorizontalAlignment,
	color: Color
) -> void:
	draw_string(
		font, position, text, alignment,
		width, font_size, color
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
