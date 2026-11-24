class_name ApplyStatusEffect
extends BattleEffect
## {"type": "apply_status", "status": "braced", "duration": 1, "chance": 1.0}


func apply(engine: BattleEngine, source: BattleUnit, target: BattleUnit, params: Dictionary) -> void:
	var status_id: String = params.get("status", "")
	var chance: float = params.get("chance", 1.0)
	if chance < 1.0 and engine.state.rng.randf() >= chance:
		engine.emit({"type": BattleEvents.STATUS_RESISTED, "target": target.id, "status": status_id})
		return
	engine.add_status(target, status_id, int(params.get("duration", 1)), source)


func preview(_engine: BattleEngine, _source: BattleUnit, target: BattleUnit, params: Dictionary, p: Dictionary) -> void:
	var status_id: String = params.get("status", "")
	if target.blocks_status(status_id):
		p["statuses"].append({"status": status_id, "chance": 0.0, "immune": true})
		return
	p["statuses"].append({"status": status_id, "chance": float(params.get("chance", 1.0))})
