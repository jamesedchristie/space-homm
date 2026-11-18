class_name MissionFactory
extends RefCounted
## Builds a tactical scenario from a mission definition (data/missions/*.json)
## and an away team. Missions are ordinary battles to the engine: square map,
## fog of war, dormant enemy groups, scripted triggers and a reach-the-goal
## objective. Losing the whole squad is always a defeat.

## Mission hostiles fight as their own team (and color), apart from galaxy factions.
const HOSTILE_TEAM := 3


## squad: scenario unit entries without positions, e.g.
##   {"unit_def": HeroBuilder.unit_def(...), "ref": "hero:reyes"} or {"unit": "marine"}
## They are placed on the map's deployment.squad slots in order.
static func scenario(data: DataRegistry, mission: Dictionary, squad: Array[Dictionary], squad_team: int,
		squad_name: String = "Away Team", controller: String = "player") -> Dictionary:
	var slots: Array = data.maps[mission["map"]].get("deployment", {}).get("squad", [])
	var squad_units: Array = []
	for i in mini(squad.size(), slots.size()):
		var entry := squad[i].duplicate()
		entry["at"] = slots[i]
		squad_units.append(entry)

	var enemies: Array = []
	for e: Dictionary in mission.get("enemies", []):
		var entry := e.duplicate()
		entry["dormant"] = not e.get("alert", false)
		enemies.append(entry)

	var triggers: Array = []
	for t: Dictionary in mission.get("triggers", []):
		var trigger := t.duplicate(true)
		trigger["team"] = squad_team
		_set_spawn_team(trigger.get("effects", []))
		for choice: Dictionary in trigger.get("choices", []):
			_set_spawn_team(choice.get("effects", []))
		triggers.append(trigger)

	var objectives: Array = []
	for o: Dictionary in mission.get("objectives", []):
		var objective := o.duplicate(true)
		if not objective.has("team"):
			objective["team"] = squad_team
		objectives.append(objective)
	# Wiping out the hostiles also wins (unless the mission says otherwise,
	# e.g. a hold-out with waves still to come); losing the squad loses.
	if mission.get("eliminate_all_wins", true):
		objectives.append({"type": "eliminate_all", "description": "or eliminate all hostiles"})

	return {
		"id": "mission_" + mission["id"],
		"mission": mission["id"],
		"name": mission.get("name", mission["id"]),
		"map": mission["map"],
		"max_rounds": int(mission.get("max_rounds", 25)),
		"fog": mission.get("fog", true),
		"teams": [
			{"team": squad_team, "name": squad_name, "controller": controller, "units": squad_units},
			{"team": HOSTILE_TEAM, "name": mission.get("enemy_name", "Hostiles"), "controller": "ai", "units": enemies},
		],
		"triggers": triggers,
		"objectives": objectives,
		"caches": _caches(mission, squad_team),
	}


## The mission's random lockers, if any, for the squad's team.
static func _caches(mission: Dictionary, squad_team: int) -> Dictionary:
	var spec: Dictionary = mission.get("caches", {}).duplicate(true)
	if not spec.is_empty():
		spec["team"] = squad_team
	return spec


## Away team: the given heroes plus marines up to the mission's squad size.
## Everyone gets the species' squad ability (data/strategic/species.json).
static func squad_for(data: DataRegistry, mission: Dictionary, heroes: Array[Hero], species_id: String = "") -> Array[Dictionary]:
	var squad: Array[Dictionary] = []
	var extra: String = data.species.get(species_id, {}).get("squad_ability", "")
	for h in heroes:
		var def := HeroBuilder.unit_def(h, data)
		if not extra.is_empty() and extra not in def["abilities"]:
			def["abilities"].insert(mini(2, def["abilities"].size()), extra)
		squad.append({"unit_def": def, "ref": "hero:" + h.id})
	var marine: String = mission.get("marine_unit", "marine")
	var marine_def: Dictionary = data.units[marine].duplicate(true)
	if not extra.is_empty() and extra not in marine_def["abilities"]:
		marine_def["abilities"].insert(mini(1, marine_def["abilities"].size()), extra)
	var n := 1
	while squad.size() < int(mission.get("squad_size", 4)):
		squad.append({"unit_def": marine_def, "name": "Marine %d" % n})
		n += 1
	return squad


static func _set_spawn_team(effects: Array) -> void:
	for fx: Dictionary in effects:
		if fx.get("type", "") == "spawn":
			for entry: Dictionary in fx.get("units", []):
				if not entry.has("team"):
					entry["team"] = HOSTILE_TEAM
