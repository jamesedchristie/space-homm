class_name Starfield
extends Node2D
## Cheap procedural star backdrop. Swap for a parallax background later.

var _stars: Array[Dictionary] = []


func _ready() -> void:
	get_viewport().size_changed.connect(_generate)
	_generate()


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var area := get_viewport_rect().size
	_stars.clear()
	for i in 260:
		_stars.append({
			"pos": Vector2(rng.randf() * area.x, rng.randf() * area.y),
			"r": rng.randf_range(0.4, 1.6),
			"a": rng.randf_range(0.15, 0.8),
		})
	queue_redraw()


func _draw() -> void:
	for s in _stars:
		draw_circle(s["pos"], s["r"], Color(0.8, 0.86, 1.0, s["a"]))
