class_name ThemeManager
extends Node


const COLOR_BACKGROUND := Color("#151922")
const COLOR_SURFACE := Color("#202632")
const COLOR_SURFACE_RAISED := Color("#29313f")
const COLOR_BORDER := Color("#3b4658")
const COLOR_TEXT := Color("#e7ebf2")
const COLOR_TEXT_MUTED := Color("#9aa6b8")
const COLOR_ACCENT := Color("#55a6ff")
const COLOR_ACCENT_HOVER := Color("#75b7ff")
const COLOR_SUCCESS := Color("#57c785")
const COLOR_WARNING := Color("#e6b85c")
const COLOR_DANGER := Color("#e36d6d")

const SPACING_SMALL := 4
const SPACING_MEDIUM := 8
const SPACING_LARGE := 12
const CORNER_RADIUS := 4


var current_theme: Theme


func _ready() -> void:
	current_theme = create_editor_theme()


func apply_to(control: Control) -> void:
	if current_theme == null:
		current_theme = create_editor_theme()

	control.theme = current_theme


func create_editor_theme() -> Theme:
	var editor_theme := Theme.new()
	editor_theme.default_font_size = 14

	editor_theme.set_color("font_color", "Label", COLOR_TEXT)
	editor_theme.set_color("font_disabled_color", "Label", COLOR_TEXT_MUTED)
	editor_theme.set_color("font_color", "Button", COLOR_TEXT)
	editor_theme.set_color("font_hover_color", "Button", COLOR_TEXT)
	editor_theme.set_color("font_pressed_color", "Button", COLOR_TEXT)
	editor_theme.set_color("font_focus_color", "Button", COLOR_TEXT)

	editor_theme.set_constant(
		"separation",
		"VBoxContainer",
		SPACING_MEDIUM
	)
	editor_theme.set_constant(
		"separation",
		"HBoxContainer",
		SPACING_MEDIUM
	)
	editor_theme.set_constant(
		"separation",
		"HSplitContainer",
		SPACING_SMALL
	)

	editor_theme.set_stylebox(
		"panel",
		"PanelContainer",
		_make_stylebox(COLOR_SURFACE, COLOR_BORDER, 1, SPACING_LARGE)
	)
	editor_theme.set_stylebox(
		"normal",
		"Button",
		_make_stylebox(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, SPACING_MEDIUM)
	)
	editor_theme.set_stylebox(
		"hover",
		"Button",
		_make_stylebox(COLOR_ACCENT, COLOR_ACCENT_HOVER, 1, SPACING_MEDIUM)
	)
	editor_theme.set_stylebox(
		"pressed",
		"Button",
		_make_stylebox(COLOR_ACCENT.darkened(0.15), COLOR_ACCENT, 1, SPACING_MEDIUM)
	)
	editor_theme.set_stylebox(
		"focus",
		"Button",
		_make_stylebox(Color.TRANSPARENT, COLOR_ACCENT, 2, SPACING_MEDIUM)
	)
	editor_theme.set_stylebox(
		"disabled",
		"Button",
		_make_stylebox(
			COLOR_SURFACE.darkened(0.12),
			COLOR_BORDER.darkened(0.15),
			1,
			SPACING_MEDIUM
		)
	)

	_configure_workspace_tabs(editor_theme)
	return editor_theme


static func make_badge_style(color: Color) -> StyleBoxFlat:
	return _make_stylebox(
		color.darkened(0.55),
		color.darkened(0.15),
		1,
		SPACING_SMALL
	)


static func _configure_workspace_tabs(editor_theme: Theme) -> void:
	editor_theme.set_color(
		"font_selected_color",
		"TabContainer",
		COLOR_TEXT
	)
	editor_theme.set_color(
		"font_unselected_color",
		"TabContainer",
		COLOR_TEXT_MUTED
	)
	editor_theme.set_color(
		"font_hovered_color",
		"TabContainer",
		COLOR_TEXT
	)
	editor_theme.set_font_size("font_size", "TabContainer", 13)
	editor_theme.set_constant("side_margin", "TabContainer", SPACING_SMALL)
	editor_theme.set_constant("tab_separation", "TabContainer", 2)
	editor_theme.set_stylebox(
		"tab_selected",
		"TabContainer",
		_make_tab_stylebox(COLOR_SURFACE_RAISED, COLOR_ACCENT, 2)
	)
	editor_theme.set_stylebox(
		"tab_hovered",
		"TabContainer",
		_make_tab_stylebox(COLOR_SURFACE, COLOR_ACCENT_HOVER, 1)
	)
	editor_theme.set_stylebox(
		"tab_unselected",
		"TabContainer",
		_make_tab_stylebox(COLOR_BACKGROUND, COLOR_BORDER, 1)
	)
	editor_theme.set_stylebox(
		"tab_focus",
		"TabContainer",
		_make_tab_stylebox(Color.TRANSPARENT, COLOR_ACCENT, 1)
	)


static func _make_stylebox(
	background_color: Color,
	border_color: Color,
	border_width: int,
	padding: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style


static func _make_tab_stylebox(
	background_color: Color,
	border_color: Color,
	bottom_border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_bottom = bottom_border_width
	style.corner_radius_top_left = CORNER_RADIUS
	style.corner_radius_top_right = CORNER_RADIUS
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	return style
