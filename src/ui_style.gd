extends RefCounted
class_name TrumanUIStyle

const FONT_PATH: String = "res://assets/ui/BoutiqueBitmap9x9_Bold_1.9.ttf"
const CYAN: Color = Color("00f0ff")
const GOLD: Color = Color("e0a96d")
const TEXT: Color = Color("eef3e9")
const MUTED_TEXT: Color = Color("aeb9a9")


static func make_theme() -> Theme:
	var result: Theme = Theme.new()
	var ui_font: Font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null
	if ui_font != null:
		result.default_font = ui_font
	result.default_font_size = 14
	return result


static func panel_style(kind: String, margin: float = 12.0) -> StyleBoxFlat:
	var colors: Array[Color] = _panel_colors(kind)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colors[0]
	style.border_color = colors[1]
	style.set_border_width_all(8 if kind == "hotbar" else 6)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(margin)
	style.shadow_color = colors[2]
	style.shadow_size = 2
	style.shadow_offset = Vector2(3, 3)
	style.anti_aliasing = false
	return style


static func apply_panel(panel: PanelContainer, kind: String, margin: float = 12.0) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(kind, margin))


static func apply_button(button: BaseButton, selected: bool = false) -> void:
	button.add_theme_stylebox_override("normal", _button_box(Color("232a1f"), CYAN if selected else Color("374034")))
	button.add_theme_stylebox_override("hover", _button_box(Color("1e383c"), CYAN))
	button.add_theme_stylebox_override("pressed", _button_box(Color("14282b"), Color("8af8ff")))
	button.add_theme_stylebox_override("focus", _button_box(Color("1e383c"), CYAN))
	button.add_theme_stylebox_override("disabled", _button_box(Color("161a15"), Color("2b3029")))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("667063"))
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 36.0)


static func apply_title(label: Label, size: int = 20, color: Color = GOLD) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)


static func apply_muted(label: Label) -> void:
	label.add_theme_color_override("font_color", MUTED_TEXT)


static func slot_colors(kind: String) -> Array[Color]:
	match kind:
		"hotbar", "wood":
			return [Color("2b1d12"), Color("4a3420"), Color("cc8e52")]
		"obsidian":
			return [Color("160d21"), Color("3f225c"), Color("864ec2")]
		"bronze":
			return [Color("241808"), Color("78531e"), Color("d9a041")]
		_:
			return [Color("1c1f19"), Color("2d352b"), Color("889c83")]


static func overlay_style(alpha: float = 0.65) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, alpha)
	style.set_corner_radius_all(0)
	return style


static func _panel_colors(kind: String) -> Array[Color]:
	match kind:
		"wood":
			return [Color("211913"), Color("6b4423"), Color("4d3019")]
		"hotbar":
			return [Color("2b1f15"), Color("7d4d23"), Color("523114")]
		"obsidian":
			return [Color("160d21"), Color("3f225c"), Color("251238")]
		"bronze":
			return [Color("241808"), Color("78531e"), Color("422b0c")]
		_:
			return [Color("1a1d18"), Color("374034"), Color("242b22")]


static func _button_box(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8.0)
	style.anti_aliasing = false
	return style
