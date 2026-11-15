class_name ResearchRules
extends RefCounted
## The tech tree (data/empire/techs.json): which techs a faction knows, can
## research now, or hasn't unlocked the prerequisites for.

const KNOWN := "known"
const AVAILABLE := "available"
const LOCKED := "locked"


static func status(engine: GalaxyEngine, faction_id: String, tech_id: String) -> String:
	var known := engine.state.known_techs(faction_id)
	if tech_id in known:
		return KNOWN
	for req: String in engine.data.techs[tech_id].get("requires", []):
		if req not in known:
			return LOCKED
	return AVAILABLE


static func available(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in engine.data.techs:
		if status(engine, faction_id, tech_id) == AVAILABLE:
			out.append(tech_id)
	return out


static func cost(engine: GalaxyEngine, tech_id: String) -> int:
	return int(engine.data.techs[tech_id].get("cost", 50))
