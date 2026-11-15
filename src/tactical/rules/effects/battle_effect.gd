class_name BattleEffect
extends RefCounted
## One mechanic primitive that abilities and statuses compose from JSON, e.g.
##   {"type": "damage", "amount": [18, 24], "damage_type": "kinetic"}
## To add a mechanic: subclass this, then register it in EffectRegistry.


## Applies the effect. `source` may be null (e.g. a status whose source died).
func apply(_engine: BattleEngine, _source: BattleUnit, _target: BattleUnit, _params: Dictionary) -> void:
	push_error("BattleEffect.apply not implemented")


## Expected outcome without changing state, for UI previews and AI scoring.
## Adds to `preview` keys such as shield_damage, hull_damage, heal, statuses.
func preview(_engine: BattleEngine, _source: BattleUnit, _target: BattleUnit, _params: Dictionary, _preview: Dictionary) -> void:
	pass
