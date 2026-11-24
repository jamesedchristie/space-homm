class_name VictoryRules
extends RefCounted
## How a campaign can be won, and how close each major power is.
##
##   conquest:  the last major power standing (or a scenario objective such as
##              {"victory": {"eliminate": "raiders"}}); also ends when no
##              major powers are left at war (the highest score wins: "peace").
##   science:   complete the megaproject flagged "victory": "science" (the
##              Ascension Gate), which needs the final-era technology.
##   score:     at the turn limit the highest score wins.
##   tech:      {"victory": {"tech": id, "tech_reason"?: "act1"}}: the first major power to research
##              that tech wins (Solar Age: Hyperdrive ends Act 1). It replaces conquest: a lone
##              major power doesn't win by default, it only loses by being eliminated.
##
## A campaign's "victory" block can switch kinds on or off ("science": false,
## "score": false, "peace": false). Scenarios with an "eliminate" objective
## default science and score to off, so they stay about their objective.

const KINDS := ["conquest", "science", "score", "peace", "tech"]


## The tech whose discovery wins the campaign ("" if none).
static func tech_goal(engine: GalaxyEngine) -> String:
	return str(engine.campaign.get("victory", {}).get("tech", ""))


## state.victory_reason for a tech victory.
static func tech_reason(engine: GalaxyEngine) -> String:
	return str(engine.campaign.get("victory", {}).get("tech_reason", "tech"))


## 0..1 progress of a faction towards the tech goal: research points spent along its road
## (every tech the goal needs, itself included) against their total cost.
static func tech_progress(engine: GalaxyEngine, faction_id: String) -> float:
	var goal := tech_goal(engine)
	if goal.is_empty() or not engine.data.techs.has(goal):
		return 0.0
	var known := engine.state.known_techs(faction_id)
	var total := 0.0
	var have := 0.0
	for t in tech_path(engine, goal):
		var c := float(ResearchRules.cost(engine, t))
		total += c
		if t in known:
			have += c
		elif engine.state.research.get(faction_id, {}).get("current", "") == t:
			have += minf(float(engine.state.research[faction_id].get("progress", 0)), c)
	return have / maxf(total, 1.0)


static func objective(engine: GalaxyEngine) -> String:
	return str(engine.campaign.get("victory", {}).get("eliminate", ""))


static func enabled(engine: GalaxyEngine, kind: String) -> bool:
	var block: Dictionary = engine.campaign.get("victory", {})
	if kind == "tech":
		return not tech_goal(engine).is_empty()
	if block.has(kind):
		return bool(block[kind])
	if kind == "science" or kind == "score":
		return objective(engine).is_empty()
	return true


## Surviving major powers.
static func majors(engine: GalaxyEngine) -> Array[String]:
	var out: Array[String] = []
	for f in engine.state.factions:
		if f["id"] not in engine.state.eliminated and f.get("role", "major") == "major":
			out.append(f["id"])
	return out


## The surviving major power with the highest score ("" if none; first wins ties).
static func score_leader(engine: GalaxyEngine) -> String:
	var best := ""
	var best_score := -1
	for id in majors(engine):
		var sc := EmpireRules.score(engine, id)
		if sc > best_score:
			best_score = sc
			best = id
	return best


## The megaproject that wins the game by science, or "".
static func science_megaproject(engine: GalaxyEngine) -> String:
	var ids := engine.data.megaprojects.keys()
	ids.sort()
	for id: String in ids:
		if engine.data.megaprojects[id].get("victory", "") == "science":
			return id
	return ""


## Every tech the megaproject's unlocking tech depends on (itself included).
static func tech_path(engine: GalaxyEngine, tech_id: String) -> Array[String]:
	var out: Array[String] = []
	var todo: Array[String] = [tech_id]
	while not todo.is_empty():
		var t: String = todo.pop_back()
		if t in out or not engine.data.techs.has(t):
			continue
		out.append(t)
		for req: String in engine.data.techs[t].get("requires", []):
			todo.append(req)
	return out


## 0..1 progress of a faction towards the Ascension Gate: 70% the road of
## techs, 30% the megaproject itself.
static func science_progress(engine: GalaxyEngine, faction_id: String) -> float:
	var mp_id := science_megaproject(engine)
	if mp_id.is_empty():
		return 0.0
	if EmpireRules.megaproject_site(engine, mp_id, faction_id) != null:
		return 1.0
	var path := tech_path(engine, engine.data.megaprojects[mp_id].get("requires_tech", ""))
	var known := engine.state.known_techs(faction_id)
	var have := 0
	for t in path:
		if t in known:
			have += 1
	var tech_part := float(have) / maxf(path.size(), 1)
	var site := EmpireRules.megaproject_under_construction(engine, mp_id, faction_id)
	var build_part := 0.0
	if site != null:
		build_part = float(site.queue["progress"]) / maxf(float(site.queue["turns"]), 1.0)
	return 0.7 * tech_part + 0.3 * build_part


## A short status line for the faction's road to Ascension.
static func science_status(engine: GalaxyEngine, faction_id: String) -> String:
	var mp_id := science_megaproject(engine)
	if mp_id.is_empty():
		return ""
	var def: Dictionary = engine.data.megaprojects[mp_id]
	if EmpireRules.megaproject_site(engine, mp_id, faction_id) != null:
		return "%s complete" % def["name"]
	var site := EmpireRules.megaproject_under_construction(engine, mp_id, faction_id)
	if site != null:
		return "building %s at %s (%d/%d turns)" % [def["name"], site.name, int(site.queue["progress"]), int(site.queue["turns"])]
	var req: String = def.get("requires_tech", "")
	if req in engine.state.known_techs(faction_id):
		return "%s unlocked, not started" % def["name"]
	var path := tech_path(engine, req)
	var have := path.filter(func(t: String) -> bool: return t in engine.state.known_techs(faction_id)).size()
	return "%d of %d techs on the road to %s" % [have, path.size(), engine.data.techs.get(req, {}).get("name", req)]


## The Victory section of the empire panel: one entry per victory condition,
## [{"id", "name", "text", "enabled", "leader": faction id or "", "rows": [{"faction", "text", "value": 0..1}]}].
static func progress(engine: GalaxyEngine) -> Array[Dictionary]:
	var s := engine.state
	var alive := majors(engine)
	var out: Array[Dictionary] = []

	var goal := tech_goal(engine)
	if not goal.is_empty():
		var tech_name: String = engine.data.techs.get(goal, {}).get("name", goal)
		var entry := {"id": "tech", "name": tech_name, "enabled": true, "rows": [], "leader": "",
				"text": "Research %s to win. %s" % [tech_name, engine.data.techs.get(goal, {}).get("description", "")]}
		var best_tech := -1.0
		for id in alive:
			var v := tech_progress(engine, id)
			var path := tech_path(engine, goal)
			var have := path.filter(func(t: String) -> bool: return t in s.known_techs(id)).size()
			entry["rows"].append({"faction": id, "text": "%d of %d techs on the road to %s" % [have, path.size(), tech_name], "value": v})
			if v > best_tech:
				best_tech = v
				entry["leader"] = id
		out.append(entry)

	var objective_id := objective(engine)
	var conquest := {"id": "conquest", "name": "Conquest", "enabled": goal.is_empty(), "rows": [], "leader": ""}
	if not goal.is_empty():
		conquest["text"] = "Not how this campaign is won: hold on to something, or it ends in defeat."
	elif objective_id.is_empty():
		conquest["text"] = "Be the last major power standing."
	else:
		conquest["text"] = "Scenario objective: destroy %s." % s.faction(objective_id).get("name", objective_id)
	var total_systems := maxi(s.planets.size(), 1)
	var best_systems := -1
	for id in alive:
		var n := s.planets_of(id).size()
		conquest["rows"].append({"faction": id, "text": "%d of %d systems, %d fleets" % [n, s.planets.size(), s.fleets_of(id).size()],
				"value": float(n) / total_systems})
		if n > best_systems:
			best_systems = n
			conquest["leader"] = id
	out.append(conquest)

	var science := {"id": "science", "name": "Science", "enabled": enabled(engine, "science"), "rows": [], "leader": ""}
	var mp_id := science_megaproject(engine)
	science["text"] = "Research Ascension Theory, then complete the %s." % engine.data.megaprojects.get(mp_id, {}).get("name", "Ascension Gate") \
			if science["enabled"] else "Not used in this scenario."
	var best_value := -1.0
	if science["enabled"]:
		for id in alive:
			var v := science_progress(engine, id)
			science["rows"].append({"faction": id, "text": science_status(engine, id), "value": v})
			if v > best_value:
				best_value = v
				science["leader"] = id
	out.append(science)

	var score := {"id": "score", "name": "Score", "enabled": enabled(engine, "score"), "rows": [], "leader": ""}
	score["text"] = ("At turn %d the highest score wins (now turn %d)." % [s.max_turns, s.turn_number]) if score["enabled"] \
			else "Not used in this scenario."
	var scores := {}
	var top := 1
	for id in alive:
		scores[id] = EmpireRules.score(engine, id)
		top = maxi(top, int(scores[id]))
	if score["enabled"]:
		for id in alive:
			score["rows"].append({"faction": id, "text": "score %d" % scores[id], "value": float(scores[id]) / top})
		score["leader"] = score_leader(engine)
	out.append(score)
	return out
