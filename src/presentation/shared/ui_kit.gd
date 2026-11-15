class_name UiKit
extends RefCounted
## Shared helpers for code-built UI so every screen looks the same. Colors and
## fonts come from Palette and GameTheme.


static func panel(bg: Color = Palette.PANEL_BG, border: Color = Palette.PANEL_BORDER, border_width: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(border, 0.18)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


## A label in the display font, for titles.
static func header(text: String, font_size: int, color: Color) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_font_override("font", GameTheme.header_font())
	return l


static func label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b


static func rich_text(font_size: int = 12) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_following = true
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size + 1)
	r.add_theme_font_size_override("italics_font_size", font_size)
	r.add_theme_font_size_override("bold_italics_font_size", font_size + 1)
	return r


## Sets anchors (0..1 of parent) and pixel offsets in one call.
static func anchor(c: Control, left: float, top: float, right: float, bottom: float,
		off_left: float, off_top: float, off_right: float, off_bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
	c.offset_left = off_left
	c.offset_top = off_top
	c.offset_right = off_right
	c.offset_bottom = off_bottom


static func color_tag(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [Palette.hex(color), text]
