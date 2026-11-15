class_name SpaceBackdrop
extends ColorRect
## Full-screen animated nebula + stars (shaders/nebula.gdshader). Colors can
## come from a map or campaign "backdrop" entry: {"a": "#hex", "b": "#hex", "density": 0.55}.

const SHADER := preload("res://src/presentation/shaders/nebula.gdshader")

var _material := ShaderMaterial.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material.shader = SHADER
	material = _material
	resized.connect(_update_aspect)
	_update_aspect()


func configure(backdrop: Dictionary, seed_value: float = 3.0) -> void:
	_material.set_shader_parameter("color_a", Color(backdrop.get("a", "#1a2e6b")))
	_material.set_shader_parameter("color_b", Color(backdrop.get("b", "#611f6b")))
	_material.set_shader_parameter("density", float(backdrop.get("density", 0.55)))
	_material.set_shader_parameter("seed", seed_value)


func _update_aspect() -> void:
	if size.y > 0.0:
		_material.set_shader_parameter("aspect", size.x / size.y)
