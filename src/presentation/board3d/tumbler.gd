class_name Tumbler
extends Node
## Slowly spins its parent Node3D (drifting asteroids).

var spin := Vector3(0.0, 0.2, 0.0)


func _process(delta: float) -> void:
	var p := get_parent() as Node3D
	if p != null:
		p.rotation += spin * delta
