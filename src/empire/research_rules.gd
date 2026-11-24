class_name ResearchRules
extends RefCounted
## The tech tree (data/empire/techs.json): which techs a faction knows, can
## research now, or hasn't unlocked yet. Techs belong to eras
## (data/empire/eras.json); an era opens once the faction knows enough techs
## of the era before it, on top of each tech's own prerequisites.

const KNOWN := "known"
const AVAILABLE := "available"
const LOCKED := "locked"


static func era_of(engine: GalaxyEngine, tech_id: String) -> int:
	return int(engine.data.techs[tech_id].get("era", 1))


## How many techs of `era` the faction knows.
static func known_in_era(engine: GalaxyEngine, faction_id: String, era: int) -> int:
	var n := 0
	for tech_id: String in engine.state.known_techs(faction_id):
		if engine.data.techs.has(tech_id) and era_of(engine, tech_id) == era:
			n += 1
	return n


## Whether the faction may research techs of this era yet.
static func era_open(engine: GalaxyEngine, faction_id: String, era: int) -> bool:
	var need: Dictionary = engine.data.eras.get(str(era), {}).get("requires", {})
	if need.is_empty():
		return true
	return known_in_era(engine, faction_id, int(need["era"])) >= int(need["count"])


## The highest era the faction has opened.
static func current_era(engine: GalaxyEngine, faction_id: String) -> int:
	var best := 1
	for id: String in engine.data.eras:
		if era_open(engine, faction_id, int(id)):
			best = maxi(best, int(id))
	return best


static func era_name(engine: GalaxyEngine, era: int) -> String:
	return engine.data.eras.get(str(era), {}).get("name", "Era %d" % era)


static func status(engine: GalaxyEngine, faction_id: String, tech_id: String) -> String:
	var known := engine.state.known_techs(faction_id)
	if tech_id in known:
		return KNOWN
	if not offered(engine, tech_id):
		return LOCKED
	if not era_open(engine, faction_id, era_of(engine, tech_id)):
		return LOCKED
	for req: String in engine.data.techs[tech_id].get("requires", []):
		if req not in known:
			return LOCKED
	return AVAILABLE


## Why a locked tech is locked (prerequisites and/or era), for tooltips and rows.
static func lock_reason(engine: GalaxyEngine, faction_id: String, tech_id: String) -> String:
	var known := engine.state.known_techs(faction_id)
	var parts := PackedStringArray()
	var missing := PackedStringArray()
	for req: String in engine.data.techs[tech_id].get("requires", []):
		if req not in known:
			missing.append(engine.data.techs[req]["name"])
	if not missing.is_empty():
		parts.append("Requires " + ", ".join(missing))
	var era := era_of(engine, tech_id)
	if not era_open(engine, faction_id, era):
		var need: Dictionary = engine.data.eras[str(era)]["requires"]
		parts.append("%s needs %d %s techs (%d known)" % [era_name(engine, era), int(need["count"]),
				era_name(engine, int(need["era"])), known_in_era(engine, faction_id, int(need["era"]))])
	return "; ".join(parts)


static func available(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in engine.data.techs:
		if offered(engine, tech_id) and status(engine, faction_id, tech_id) == AVAILABLE:
			out.append(tech_id)
	return out


## Whether the campaign has this tech at all: a tech with a "scale" (e.g. "system": Hyperdrive, the
## end of Act 1) only exists in campaigns of that scale.
static func offered(engine: GalaxyEngine, tech_id: String) -> bool:
	var tech_scale: String = engine.data.techs.get(tech_id, {}).get("scale", "")
	return tech_scale.is_empty() or tech_scale == engine.scale()


## The campaign's techs (every tech it offers), in data order.
static func tech_ids(engine: GalaxyEngine) -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in engine.data.techs:
		if offered(engine, tech_id):
			out.append(tech_id)
	return out


## Research points a tech costs: its base cost times its era's multiplier (and the campaign's
## "research_cost_mul", which tunes the shared tree for a shorter or slower campaign).
static func cost(engine: GalaxyEngine, tech_id: String) -> int:
	var mul := float(engine.data.eras.get(str(era_of(engine, tech_id)), {}).get("cost_mul", 1.0))
	mul *= float(engine.campaign.get("research_cost_mul", 1.0))
	return roundi(float(engine.data.techs[tech_id].get("cost", 50)) * mul)


## Resources a tech burns when it completes ("cost_resources", e.g. Hyperdrive's exotic matter), as the
## campaign charges them. Research finishes only once they are in store; points keep banking meanwhile.
static func resource_cost(engine: GalaxyEngine, tech_id: String) -> Dictionary:
	return EmpireRules.cost_of(engine, engine.data.techs.get(tech_id, {}).get("cost_resources", {}))
