class_name DeckLightAnimator
extends Node
## Animates a station deck's restless lights (DeckKit, high-quality look):
## failing ceiling lamps that stutter, pulsing red emergency beacons and
## flickering fires. Plain arrays, no allocations per frame; hidden lights
## (fog of war) are skipped.

enum { STUTTER, PULSE, FIRE }

var _lights: Array[Light3D] = []
var _base := PackedFloat32Array()
var _mode := PackedInt32Array()
var _phase := PackedFloat32Array()
var _t := 0.0


func add(light: Light3D, mode: int, phase: float) -> void:
	_lights.append(light)
	_base.append(light.light_energy)
	_mode.append(mode)
	_phase.append(phase)


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():
		var light := _lights[i]
		if not light.is_visible_in_tree():
			continue
		var ph := _phase[i]
		var f := 1.0
		match _mode[i]:
			STUTTER:
				# Mostly steady; now and then a burst of rapid drop-outs.
				var cycle := fposmod(_t * 0.23 + ph, 1.0)
				if cycle > 0.86:
					f = 0.08 if sin(_t * 47.0 + ph) * sin(_t * 23.0) > 0.1 else 0.9
				else:
					f = 0.93 + 0.07 * sin(_t * 3.1 + ph)
			PULSE:
				var s := 0.5 + 0.5 * sin(_t * 3.4 + ph)
				f = 0.08 + 0.92 * s * s
			FIRE:
				f = 0.72 + 0.18 * sin(_t * 11.0 + ph) + 0.1 * sin(_t * 23.7 + ph * 1.7)
		light.light_energy = _base[i] * f
