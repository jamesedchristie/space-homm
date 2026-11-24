class_name StoryRules
extends RefCounted
## Story arcs (a campaign's "story"): an ordered list of milestones each major power works
## through, Civ-advisor style. A milestone has a goal (survey N bodies, hold a development,
## beat the separatists, tap exotic matter, ...), a small reward, briefing and debriefing text,
## and may set things in motion when it starts (a raid, a new mission site on the map).
## Milestones never block anything: they guide, pay a little and tell the story.
##
## State: GalaxyState.story[faction] = {"step": index of the current milestone, "active": bool
## (started; false while it waits for its "min_turn"), "done": {step id: turn}, "flags": {key: count}}.
## Flags are noted from engine events (note()): "beat:<faction>" (a battle won against them),
## "den:<faction>" (one of their bases taken), "mission:<mission id>" (completed),
## "plundered" (raided). update() runs after every engine call (GalaxyEngine._flush): it starts
## the next milestone when it is due and completes the current one when its goal is met
## (at most one completion per call, so the story never skips a beat on screen).
##
## "story": {
##   "steps": [{"id", "title", "objective": short goal text, "briefing": shown when it starts,
##              "done_text": shown when it is complete, "hint"?: an advisor's nudge,
##              "min_turn"?: n (doesn't start before), "goal": {goal}, "reward"?: {reward},
##              "on_start"?: [{"type": "raid", "faction", "count"?}]}],
##   "ending": {"title", "text"}   // shown when the act is won
## }
## Goals: {"type": "surveyed", "n"}, {"type": "developed", "n"} (bodies held besides the homeworld),
## {"type": "colonies", "n"}, {"type": "extracting", "resource"}, {"type": "stock", "resource", "n"},
## {"type": "tech", "tech"}, {"type": "flag", "flag", "n"?}, {"type": "any" | "all", "goals": [...]}.
## Rewards: any stockpiled resource, "research" (progress), "xp" (every hero of the faction),
## "items": [ids].
## Campaign "story_anomalies" (SystemLayout places them): [{"id", "name", "mission", "at", "story": step id}]
## appear on the map when that milestone starts.

const GOALS := ["surveyed", "developed", "colonies", "extracting", "stock", "tech", "flag", "any", "all"]
const ON_START := ["raid"]


static func steps(engine: GalaxyEngine) -> Array:
	return engine.campaign.get("story", {}).get("steps", [])


static func enabled(engine: GalaxyEngine) -> bool:
	return not steps(engine).is_empty()


static func state_of(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	return engine.state.story.get_or_add(faction_id, {"step": -1, "active": false, "done": {}, "flags": {}})


## The faction's current milestone (started or waiting for its turn), or {} once the story is told.
static func current(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	var st := state_of(engine, faction_id)
	var list := steps(engine)
	var i := int(st["step"])
	return list[i] if i >= 0 and i < list.size() else {}


static func is_active(engine: GalaxyEngine, faction_id: String) -> bool:
	return bool(state_of(engine, faction_id)["active"]) and not current(engine, faction_id).is_empty()


static func step_index(engine: GalaxyEngine, step_id: String) -> int:
	var list := steps(engine)
	for i in list.size():
		if list[i].get("id", "") == step_id:
			return i
	return -1


static func flag_count(engine: GalaxyEngine, faction_id: String, key: String) -> int:
	return int(state_of(engine, faction_id)["flags"].get(key, 0))


# --- Flags from engine events -------------------------------------------------

## Called by GalaxyEngine.emit for every event: records what the story goals count.
static func note(engine: GalaxyEngine, e: Dictionary) -> void:
	var s := engine.state
	match e.get("type", ""):
		GalaxyEvents.BATTLE_RESOLVED:
			var winner: String = e.get("winner", "")
			var attacker: Fleet = s.fleets.get(e.get("attacker", ""))
			if winner.is_empty() or attacker == null:
				return
			var defender_owner := ""
			var defender: Fleet = s.fleets.get(e.get("defender", ""))
			if defender != null:
				defender_owner = defender.owner
			else:
				var p := s.planet_at(e.get("cell", Vector2i(-999, -999)))
				defender_owner = p.owner if p != null else ""
			var loser := defender_owner if winner == attacker.owner else attacker.owner
			if not loser.is_empty() and loser != winner:
				_flag(engine, winner, "beat:" + loser)
		GalaxyEvents.DEN_CLEARED:
			var p: Planet = s.planets.get(e.get("planet", ""))
			if p != null and not p.owner.is_empty():
				_flag(engine, e["faction"], "den:" + p.owner)
		GalaxyEvents.MISSION_RESOLVED:
			var fleet: Fleet = s.fleets.get(e.get("fleet", ""))
			if fleet != null and e.get("success", false):
				_flag(engine, fleet.owner, "mission:" + str(e.get("mission", "")))
		GalaxyEvents.SYSTEM_PLUNDERED:
			if not str(e.get("previous_owner", "")).is_empty():
				_flag(engine, e["previous_owner"], "plundered")


static func _flag(engine: GalaxyEngine, faction_id: String, key: String) -> void:
	if engine.state.faction(faction_id).get("role", "major") != "major":
		return
	var flags: Dictionary = state_of(engine, faction_id)["flags"]
	flags[key] = int(flags.get(key, 0)) + 1


# --- Progress -----------------------------------------------------------------

## Starts and completes milestones for every major power (see the class comment).
static func update(engine: GalaxyEngine) -> void:
	if engine.state.is_over:
		return
	var list := steps(engine)
	for f in engine.state.factions:
		var fid: String = f["id"]
		if f.get("role", "major") != "major" or engine.state.is_eliminated(fid):
			continue
		var st := state_of(engine, fid)
		if int(st["step"]) < 0:
			st["step"] = 0
			st["active"] = false
		var i := int(st["step"])
		if i >= list.size():
			continue
		if not st["active"]:
			if engine.state.turn_number >= int(list[i].get("min_turn", 0)):
				_start(engine, fid, i)
			continue
		if goal_met(engine, fid, list[i].get("goal", {})):
			_complete(engine, fid, i)
			if i + 1 < list.size() and engine.state.turn_number >= int(list[i + 1].get("min_turn", 0)):
				_start(engine, fid, i + 1)


static func _start(engine: GalaxyEngine, faction_id: String, i: int) -> void:
	var st := state_of(engine, faction_id)
	var def: Dictionary = steps(engine)[i]
	st["step"] = i
	st["active"] = true
	st["since"] = engine.state.turn_number
	engine.emit({"type": GalaxyEvents.STORY_STEP_STARTED, "faction": faction_id, "step": def.get("id", ""),
			"index": i, "first": i == 0})
	for a_def: Dictionary in engine.campaign.get("story_anomalies", []):
		if a_def.get("story", "") == def.get("id", "") and not engine.state.anomalies.has(a_def["id"]) \
				and not _revealed(engine, a_def["id"]):
			var cell := engine.state.grid.cell_from_layout(Vector2i(int(a_def["at"][0]), int(a_def["at"][1])))
			engine.state.anomalies[a_def["id"]] = {"id": a_def["id"], "name": a_def.get("name", a_def["id"]),
					"cell": cell, "mission": a_def["mission"]}
			st.get_or_add("revealed", {})[a_def["id"]] = true
			# Whoever got the signal knows where it came from.
			for c in engine.state.grid.cells_within(cell, 1):
				engine.state.explored[faction_id][c] = true
			engine.emit({"type": GalaxyEvents.ANOMALY_ADDED, "anomaly": a_def["id"], "name": a_def.get("name", a_def["id"]),
					"mission": a_def["mission"], "faction": faction_id})
	for fx: Dictionary in def.get("on_start", []):
		match fx.get("type", ""):
			"raid":
				var raider: String = fx.get("faction", "")
				if engine.state.faction(raider).get("role", "") == "barbarian" and not engine.state.is_eliminated(raider):
					EventRules.spawn_raiders(engine, faction_id, int(fx.get("count", 1)), _raid_anchor(engine, faction_id, raider), raider)


static func _revealed(engine: GalaxyEngine, anomaly_id: String) -> bool:
	for fid: String in engine.state.story:
		if engine.state.story[fid].get("revealed", {}).has(anomaly_id):
			return true
	return false


## The raid's target: the faction's holding nearest the raiders' base (their exposed flank).
static func _raid_anchor(engine: GalaxyEngine, faction_id: String, raider: String) -> String:
	var s := engine.state
	var dens := s.planets_of(raider)
	var best := ""
	var best_d := 1 << 20
	for p in s.planets_of(faction_id):
		var d := 1 << 20
		for den in dens:
			d = mini(d, s.grid.distance(p.cell, den.cell))
		if best.is_empty() or d < best_d:
			best_d = d
			best = p.id
	return best


static func _complete(engine: GalaxyEngine, faction_id: String, i: int) -> void:
	var st := state_of(engine, faction_id)
	var def: Dictionary = steps(engine)[i]
	var lines := apply_reward(engine, faction_id, def.get("reward", {}))
	st["done"][def.get("id", str(i))] = engine.state.turn_number
	st["step"] = i + 1
	st["active"] = false
	var next: Dictionary = steps(engine)[i + 1] if i + 1 < steps(engine).size() else {}
	engine.emit({"type": GalaxyEvents.STORY_STEP_COMPLETED, "faction": faction_id, "step": def.get("id", ""),
			"index": i, "reward": lines, "next": next.get("id", "")})


## Pays a milestone's reward; returns what was gained, one line each.
static func apply_reward(engine: GalaxyEngine, faction_id: String, reward: Dictionary) -> Array[String]:
	var s := engine.state
	var lines: Array[String] = []
	var stock: Dictionary = s.resources[faction_id]
	for k in DepositRules.stockpiled(engine.data):
		if reward.has(k):
			stock[k] = int(stock.get(k, 0)) + int(reward[k])
			lines.append("+%d %s" % [int(reward[k]), DepositRules.resource_name(engine.data, k).to_lower()])
	if reward.has("research"):
		var r: Dictionary = s.research[faction_id]
		r["progress"] = int(r["progress"]) + int(reward["research"])
		lines.append("+%d research" % int(reward["research"]))
	if reward.has("xp"):
		var any := false
		for h in s.heroes_of(faction_id):
			if h.status != Hero.DEAD and h.status != Hero.CAPTURED:
				engine._grant_xp(h, int(reward["xp"]))
				any = true
		if any:
			lines.append("+%d XP for your heroes" % int(reward["xp"]))
	for item_id: String in reward.get("items", []):
		s.inventory[faction_id].append(item_id)
		lines.append(engine.data.items.get(item_id, {}).get("name", item_id))
	return lines


static func goal_met(engine: GalaxyEngine, faction_id: String, goal: Dictionary) -> bool:
	var p := progress(engine, faction_id, goal)
	return int(p["have"]) >= int(p["need"])


## How far the faction is towards a goal: {"have", "need"} (counts; 0/1 for yes-or-no goals).
static func progress(engine: GalaxyEngine, faction_id: String, goal: Dictionary) -> Dictionary:
	var s := engine.state
	var need := maxi(int(goal.get("n", 1)), 1)
	var have := 0
	match goal.get("type", ""):
		"surveyed":
			have = s.surveyed.get(faction_id, {}).size()
		"developed":
			var home := s.home_planet(faction_id)
			for p in s.planets_of(faction_id):
				if p != home and not p.buildings.is_empty():
					have += 1
		"colonies":
			have = EmpireRules.colony_count(engine, faction_id)
		"extracting":
			need = 1
			for p in s.planets_of(faction_id):
				for b in p.bodies:
					if DepositRules.is_tapped(engine.data, b, goal.get("resource", "")):
						have = 1
		"stock":
			have = mini(int(s.resources[faction_id].get(goal.get("resource", ""), 0)), need)
		"tech":
			need = 1
			have = 1 if goal.get("tech", "") in s.known_techs(faction_id) else 0
		"flag":
			have = flag_count(engine, faction_id, goal.get("flag", ""))
		"any":
			var best := {"have": 0, "need": 1}
			for g: Dictionary in goal.get("goals", []):
				var p := progress(engine, faction_id, g)
				if float(p["have"]) / float(p["need"]) > float(best["have"]) / float(best["need"]):
					best = p
			return best
		"all":
			for g: Dictionary in goal.get("goals", []):
				var p := progress(engine, faction_id, g)
				if int(p["have"]) < int(p["need"]):
					return p
			return {"have": 1, "need": 1}
	return {"have": mini(have, need), "need": need}


## "Survey the system (4/7)": the objective with its count, for the HUD.
static func objective_text(engine: GalaxyEngine, faction_id: String, def: Dictionary) -> String:
	var p := progress(engine, faction_id, def.get("goal", {}))
	var text: String = def.get("objective", def.get("title", ""))
	if int(p["need"]) > 1:
		text += " (%d/%d)" % [int(p["have"]), int(p["need"])]
	return text


## Every milestone with its state for the faction: [{"def", "state": "done" | "active" | "waiting" | "later"}].
static func overview(engine: GalaxyEngine, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := state_of(engine, faction_id)
	var list := steps(engine)
	for i in list.size():
		var state := "later"
		if st["done"].has(list[i].get("id", "")):
			state = "done"
		elif i == int(st["step"]):
			state = "active" if st["active"] else "waiting"
		out.append({"def": list[i], "state": state})
	return out


# --- Content checks -----------------------------------------------------------

static func validate(data: DataRegistry, owner: String, def: Dictionary) -> void:
	var story: Dictionary = def.get("story", {})
	var ids := {}
	for step: Dictionary in story.get("steps", []):
		var label := "%s: story step '%s'" % [owner, step.get("id", "")]
		if step.get("id", "").is_empty() or step.get("title", "").is_empty() or step.get("objective", "").is_empty():
			data._err("%s: needs an id, a title and an objective" % label)
		if ids.has(step.get("id", "")):
			data._err("%s: duplicate id" % label)
		ids[step.get("id", "")] = true
		_validate_goal(data, label, step.get("goal", {}))
		var reward: Dictionary = step.get("reward", {})
		for k: String in reward:
			if k == "items":
				for item_id: String in reward[k]:
					if not data.items.has(item_id):
						data._err("%s: unknown reward item '%s'" % [label, item_id])
			elif k not in ["research", "xp"] and k not in DepositRules.stockpiled(data):
				data._err("%s: unknown reward '%s'" % [label, k])
		for fx: Dictionary in step.get("on_start", []):
			if fx.get("type", "") not in ON_START:
				data._err("%s: unknown on_start effect '%s'" % [label, fx.get("type", "")])
	for a: Dictionary in def.get("story_anomalies", []):
		if not data.missions.has(a.get("mission", "")):
			data._err("%s: story anomaly '%s' has unknown mission '%s'" % [owner, a.get("id", ""), a.get("mission", "")])
		if not ids.has(a.get("story", "")):
			data._err("%s: story anomaly '%s' names unknown story step '%s'" % [owner, a.get("id", ""), a.get("story", "")])


static func _validate_goal(data: DataRegistry, label: String, goal: Dictionary) -> void:
	var kind: String = goal.get("type", "")
	if kind not in GOALS:
		data._err("%s: unknown goal '%s'" % [label, kind])
		return
	match kind:
		"any", "all":
			if goal.get("goals", []).is_empty():
				data._err("%s: '%s' needs goals" % [label, kind])
			for g: Dictionary in goal.get("goals", []):
				_validate_goal(data, label, g)
		"extracting", "stock":
			if not DepositRules.stockpiled(data).has(goal.get("resource", "")):
				data._err("%s: unknown resource '%s'" % [label, goal.get("resource", "")])
		"tech":
			if not data.techs.has(goal.get("tech", "")):
				data._err("%s: unknown tech '%s'" % [label, goal.get("tech", "")])
		"flag":
			if str(goal.get("flag", "")).is_empty():
				data._err("%s: a flag goal needs a flag" % label)
