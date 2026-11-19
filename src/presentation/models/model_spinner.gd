class_name ModelSpinner
extends Node3D
## A slowly turning section of a model (ModelFactory parts with "spin"):
## rotating habitat rings and the like. Turns around its local x axis.

## Radians per second.
var speed := 0.5


func _process(delta: float) -> void:
	rotation.x = wrapf(rotation.x + speed * delta, -PI, PI)
