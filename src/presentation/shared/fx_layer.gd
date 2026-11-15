class_name FxLayer
extends Node2D
## Placeholder combat effects: beams, projectiles, blasts, floating numbers.
## Which effect an ability plays comes from its JSON "fx" field.


## Plays an ability effect and returns when it has finished.
func play(kind: String, from: Vector2, to: Vector2, color: Color, blast_radius: float = 0.0) -> void:
	match kind:
		"beam":
			await _beam(from, to, color)
		"torpedo":
			await _projectile(from, to, color, 6.0, 520.0)
			await _burst(to, maxf(blast_radius, 24.0), color)
		"pulse":
			await _beam(from, to, color, 1.5)
			await _burst(to, 30.0, color)
		"self":
			await _burst(from, 34.0, color)
		_:
			await _projectile(from, to, color, 4.0, 1000.0)


func float_text(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(140, 22)
	label.position = at + Vector2(-70, -46)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 34.0, 1.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.chain().tween_callback(label.queue_free)


func _beam(from: Vector2, to: Vector2, color: Color, width: float = 3.0) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = width
	line.default_color = color
	add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.3)
	await tw.finished
	line.queue_free()


func _projectile(from: Vector2, to: Vector2, color: Color, size: float, speed: float) -> void:
	var dot := Polygon2D.new()
	dot.polygon = _circle(size)
	dot.color = color
	dot.position = from
	add_child(dot)
	var tw := create_tween()
	tw.tween_property(dot, "position", to, maxf(0.12, from.distance_to(to) / speed))
	await tw.finished
	dot.queue_free()


func _burst(at: Vector2, radius: float, color: Color) -> void:
	var ring := Polygon2D.new()
	ring.polygon = _circle(radius)
	ring.color = Color(color, 0.55)
	ring.position = at
	ring.scale = Vector2(0.2, 0.2)
	add_child(ring)
	var tw := create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector2.ONE, 0.25)
	tw.tween_property(ring, "modulate:a", 0.0, 0.32)
	await tw.finished
	ring.queue_free()


func _circle(radius: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		pts.append(Vector2.from_angle(TAU * i / segments) * radius)
	return pts
