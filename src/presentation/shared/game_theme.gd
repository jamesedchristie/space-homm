class_name GameTheme
extends RefCounted
## The game's UI theme, built in code (no .tres to hand-edit): dark translucent
## panels with a soft cyan glow. Kenvector Future is used for short titles only
## (its stylised V/K glyphs make longer text hard to read).
## Set `theme = GameTheme.get_theme()` on a HUD root; children inherit it.

const HEADER_FONT_PATH := "res://assets/kenney_space_shooter/fonts/kenvector_future.ttf"

const ACCENT := Color("3fb8d8")
const BUTTON_BG := Color(0.07, 0.11, 0.18, 0.95)
const BUTTON_HOVER := Color(0.10, 0.19, 0.29, 0.98)
const BUTTON_PRESSED := Color(0.05, 0.25, 0.33, 1.0)

static var _theme: Theme
static var _header_font: Font


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 14

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(BUTTON_BG, Color(ACCENT, 0.45), 1, 0))
		t.set_stylebox("hover", type, _box(BUTTON_HOVER, ACCENT, 1, 6))
		t.set_stylebox("pressed", type, _box(BUTTON_PRESSED, ACCENT.lightened(0.3), 2, 8))
		t.set_stylebox("disabled", type, _box(Color(0.05, 0.07, 0.1, 0.8), Color(1, 1, 1, 0.08), 1, 0))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font_size("font_size", type, 14)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Palette.ACTIVE)
		t.set_color("font_disabled_color", type, Color(Palette.TEXT_DIM, 0.45))

	# Tabs (Empire panel)
	t.set_stylebox("tab_selected", "TabContainer", _box(BUTTON_PRESSED, ACCENT, 1, 4))
	t.set_stylebox("tab_unselected", "TabContainer", _box(BUTTON_BG, Color(ACCENT, 0.25), 1, 0))
	t.set_stylebox("tab_hovered", "TabContainer", _box(BUTTON_HOVER, Color(ACCENT, 0.6), 1, 0))
	t.set_stylebox("panel", "TabContainer", _box(Color(0.03, 0.05, 0.09, 0.6), Color(ACCENT, 0.2), 1, 0))
	t.set_font_size("font_size", "TabContainer", 15)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", Palette.TEXT_DIM)

	# Drop-down menus and tooltips
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.04, 0.06, 0.11, 0.98), Color(ACCENT, 0.6), 1, 8))
	t.set_stylebox("hover", "PopupMenu", _box(BUTTON_HOVER, ACCENT, 0, 0))
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_disabled_color", "PopupMenu", Color(Palette.TEXT_DIM, 0.6))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.03, 0.05, 0.09, 0.97), Color(ACCENT, 0.7), 1, 6))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)

	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	_theme = t
	return _theme


## Bold sci-fi display font for titles.
static func header_font() -> Font:
	if _header_font == null:
		_header_font = load(HEADER_FONT_PATH)
	return _header_font


## Flat box with a border and an optional outer glow.
static func _box(bg: Color, border: Color, border_width: int, glow: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	if glow > 0:
		sb.shadow_color = Color(border, 0.35)
		sb.shadow_size = glow
	return sb
