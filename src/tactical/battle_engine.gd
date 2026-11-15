class_name BattleEngine
extends RefCounted
## The shared tactical engine: one ruleset for fleet battles, ground missions
## and exploration missions. Pure logic, no nodes, no rendering.
##
##   var engine := BattleEngine.from_scenario(data, "first_skirmish", seed)
##   var events := engine.start()
##   var result := engine.submit(MoveCommand.new(unit_id, cell))
##   # result.events -> animate them; result.ok / result.error
##
## Controllers (the player's UI, RuleBasedAI, auto-resolve) only ever submit
## commands and read queries. Effects call back into the engine through the
## mutation helpers below (deal_damage, heal, add_status) so every change emits
## an event.

var state: BattleState
var data: DataRegistry
var _events: Array[Dictionary] = []


## Builds a battle from a scenario id or an inline scenario Dictionary.
## seed 0 picks a random seed (recorded in state.seed_value for replays).
static func from_scenario(p_data: DataRegistry, scenario: Variant, p_seed: int = 0) -> BattleEngine:
	var def: Dictionary = scenario if scenario is Dictionary else p_data.scenarios.get(scenario, {})
	if def.is_empty():
		push_error("BattleEngine: unknown scenario '%s'" % str(scenario))
		return null
	var map_def: Dictionary = p_data.maps.get(def.get("map", ""), {})
	if map_def.is_empty():
		push_error("BattleEngine: scenario has unknown map '%s'" % def.get("map", ""))
		return null

	var engine := BattleEngine.new()
	engine.data = p_data
	var s := BattleState.new()
	engine.state = s
	s.seed_value = p_seed if p_seed != 0 else randi()
	s.rng.seed = s.seed_value
	s.grid = GridFactory.from_map(map_def, p_data.terrain)
	s.max_rounds = int(def.get("max_rounds", 50))

	for team_def: Dictionary in def.get("teams", []):
		var team := int(team_def.get("team", s.teams.size()))
		s.teams.append({
			"team": team,
			"name": team_def.get("name", "Team %d" % team),
			"controller": team_def.get("controller", "ai"),
		})
		var index := 0
		for entry: Dictionary in team_def.get("units", []):
			# Heroes bring a generated definition ("unit_def"); everything else references content.
			var unit_def: Dictionary = entry.get("unit_def", p_data.units.get(entry.get("unit", ""), {}))
			if unit_def.is_empty():
				push_error("BattleEngine: unknown unit '%s'" % entry.get("unit", ""))
				continue
			var at: Array = entry.get("at", [0, 0])
			var cell := s.grid.cell_from_layout(Vector2i(int(at[0]), int(at[1])))
			var unit_id := "t%d_%d_%s" % [team, index, unit_def["id"]]
			var u := BattleUnit.from_def(unit_id, unit_def, team, cell, entry.get("name", ""))
			u.hero_id = entry.get("hero", "")
			u.ref = entry.get("ref", "")
			# Damage carried over from earlier fights (shields always start full).
			if entry.has("hull"):
				u.hull = clampi(int(entry["hull"]), 1, u.max_hull())
			u.alert = not entry.get("dormant", false)
			u.group = entry.get("group", "")
			# Statuses present from the start, e.g. a fleet commander's doctrine.
			for st: Dictionary in entry.get("statuses", []):
				var status_def: Dictionary = p_data.statuses.get(st.get("status", ""), {})
				if not status_def.is_empty():
					u.statuses.append(StatusInstance.new(status_def, int(st.get("duration", 1))))
			s.units[unit_id] = u
			index += 1

	s.fog_enabled = def.get("fog", false)
	s.mission_id = def.get("mission", "")
	for t: Dictionary in def.get("triggers", []):
		var trigger := t.duplicate(true)
		var cells: Array[Vector2i] = []
		for pos: Array in trigger.get("cells", []):
			cells.append(s.grid.cell_from_layout(Vector2i(int(pos[0]), int(pos[1]))))
		trigger["_cells"] = cells
		trigger["fired"] = false
		s.triggers.append(trigger)
	s.objectives = ObjectiveFactory.build(def.get("objectives", [{"type": "eliminate_all"}]))
	for o in s.objectives:
		o.setup(s)
	for t in s.teams:
		s.explored[t["team"]] = {}
	engine._update_explored()
	return engine


# =============================================================================
# Flow
# =============================================================================

func start() -> Array[Dictionary]:
	emit({"type": BattleEvents.BATTLE_STARTED, "seed": state.seed_value})
	_advance_turn()
	return _flush()


func submit(cmd: BattleCommand) -> CommandResult:
	var error := validate(cmd)
	if not error.is_empty():
		return CommandResult.failure(error)

	if cmd is MoveCommand:
		_do_move(cmd)
	elif cmd is UseAbilityCommand:
		_do_ability(cmd)
	elif cmd is EndTurnCommand:
		_end_turn()
	elif cmd is ChooseOptionCommand:
		_do_choice(cmd)

	_check_objectives()
	# The active unit may have died during its own action (friendly fire).
	var active := state.active_unit()
	if not state.is_over and active != null and not active.alive:
		_end_turn()
	return CommandResult.success(_flush())


## Why the command would be rejected, or "" if it is legal.
func validate(cmd: BattleCommand) -> String:
	if state.is_over:
		return "The battle is over"
	if cmd == null:
		return "No command"
	var unit := state.active_unit()
	if unit == null or cmd.unit_id != unit.id:
		return "It is not that unit's turn"

	if not state.pending_choice.is_empty():
		if not cmd is ChooseOptionCommand:
			return "Make a choice first"
		var trigger: Dictionary = state.triggers[state.pending_choice["trigger"]]
		if cmd.option < 0 or cmd.option >= trigger.get("choices", []).size():
			return "Invalid option"
		return ""
	if cmd is ChooseOptionCommand:
		return "Nothing to choose"

	if cmd is MoveCommand:
		var to: Vector2i = cmd.to
		if to == unit.cell:
			return "Already there"
		var reach := reachable_cells(unit.id)
		if not reach.has(to):
			return "Cannot reach that cell"
	elif cmd is UseAbilityCommand:
		var ability: Dictionary = data.abilities.get(cmd.ability_id, {})
		if ability.is_empty():
			return "Unknown ability"
		var usable := AbilityRules.usable_error(unit, cmd.ability_id, ability)
		if not usable.is_empty():
			return usable
		if cmd.target not in AbilityRules.target_cells(state, unit, ability, unit.cell):
			return "Invalid target"
	elif not cmd is EndTurnCommand:
		return "Unknown command"
	return ""


# =============================================================================
# Queries (used by UI and AI; never change state)
# =============================================================================

## {cell: {"cost", "from"}} for every cell the unit can reach with its AP.
func reachable_cells(unit_id: String) -> Dictionary:
	var unit := state.get_unit(unit_id)
	return Pathfinding.reachable(state.grid, unit.cell, unit.ap,
			func(c: Vector2i) -> bool: return c != unit.cell and state.is_occupied(c))


func ability_targets(unit_id: String, ability_id: String, from_cell: Variant = null) -> Array[Vector2i]:
	var unit := state.get_unit(unit_id)
	var origin: Vector2i = unit.cell if from_cell == null else from_cell
	return AbilityRules.target_cells(state, unit, data.abilities[ability_id], origin)


func ability_area(unit_id: String, ability_id: String, target_cell: Vector2i) -> Array[Vector2i]:
	return AbilityRules.area_cells(state, state.get_unit(unit_id), data.abilities[ability_id], target_cell)


func ability_error(unit_id: String, ability_id: String) -> String:
	var ability: Dictionary = data.abilities.get(ability_id, {})
	if ability.is_empty():
		return "Unknown ability"
	return AbilityRules.usable_error(state.get_unit(unit_id), ability_id, ability)


## Expected outcome of an ability, one entry per affected unit:
## {unit, shield_damage, hull_damage, heal, statuses: [{status, chance}], lethal}
func preview_ability(unit_id: String, ability_id: String, target_cell: Vector2i) -> Array[Dictionary]:
	var unit := state.get_unit(unit_id)
	var ability: Dictionary = data.abilities[ability_id]
	var affected := AbilityRules.affected_units(state, unit, ability, target_cell)
	var by_unit := {}
	var order: Array[Dictionary] = []
	for effect_def: Dictionary in ability.get("effects", []):
		var effect := EffectRegistry.get_effect(effect_def.get("type", ""))
		if effect == null:
			continue
		var recipients: Array[BattleUnit] = affected
		if effect_def.get("to", "target") == "self":
			recipients = [unit]
		for r in recipients:
			if not by_unit.has(r.id):
				var p := {"unit": r.id, "shields": r.shields, "shield_damage": 0, "hull_damage": 0,
						"heal": 0, "statuses": [], "lethal": false}
				by_unit[r.id] = p
				order.append(p)
			effect.preview(self, unit, r, effect_def, by_unit[r.id])
	for p in order:
		p["lethal"] = p["hull_damage"] >= state.get_unit(p["unit"]).hull
	return order


## True if the unit can still do anything this turn besides ending it.
func has_available_actions(unit_id: String) -> bool:
	var unit := state.get_unit(unit_id)
	if reachable_cells(unit_id).size() > 1:
		return true
	for ability_id in unit.abilities:
		if ability_error(unit_id, ability_id).is_empty() and not ability_targets(unit_id, ability_id).is_empty():
			return true
	return false


func objective_text() -> String:
	var parts := PackedStringArray()
	for o in state.objectives:
		parts.append(o.describe())
	return ", ".join(parts)


# =============================================================================
# Mutation helpers (called by effects; each emits an event)
# =============================================================================

func emit(event: Dictionary) -> void:
	_events.append(event)


func deal_damage(source: BattleUnit, target: BattleUnit, raw: float, params: Dictionary) -> void:
	if not target.alive:
		return
	if not target.alert:
		_alert(target)
	var dtype_id: String = params.get("damage_type", "")
	var result := CombatMath.resolve(raw, target.shields, target.stat_i("armor"),
			data.damage_types.get(dtype_id, {}),
			params.get("bypass_shields", false), params.get("ignore_armor", false))
	target.shields -= int(result["shield_damage"])
	target.hull = maxi(0, target.hull - int(result["hull_damage"]))
	emit({
		"type": BattleEvents.DAMAGE_DEALT,
		"source": source.id if source != null else "",
		"target": target.id,
		"damage_type": dtype_id,
		"shield_damage": result["shield_damage"],
		"hull_damage": result["hull_damage"],
		"shields": target.shields,
		"hull": target.hull,
	})
	if target.hull <= 0:
		_destroy(target, source)


func heal(target: BattleUnit, stat: String, amount: int) -> void:
	if not target.alive:
		return
	var before: int
	var value: int
	if stat == "shields":
		before = target.shields
		target.shields = mini(target.max_shields(), target.shields + amount)
		value = target.shields
	else:
		before = target.hull
		target.hull = mini(target.max_hull(), target.hull + amount)
		value = target.hull
	emit({"type": BattleEvents.HEALED, "target": target.id, "stat": stat, "amount": value - before, "value": value})


## Applying a status the unit already has refreshes its duration.
func add_status(target: BattleUnit, status_id: String, duration: int, source: BattleUnit) -> void:
	if not target.alive:
		return
	var def: Dictionary = data.statuses.get(status_id, {})
	if def.is_empty():
		push_error("BattleEngine: unknown status '%s'" % status_id)
		return
	var existing := target.find_status(status_id)
	if existing != null:
		existing.remaining = maxi(existing.remaining, duration)
	else:
		target.statuses.append(StatusInstance.new(def, duration, source.id if source != null else ""))
	emit({"type": BattleEvents.STATUS_APPLIED, "target": target.id, "status": status_id,
			"duration": duration, "source": source.id if source != null else ""})


# =============================================================================
# Internals
# =============================================================================

func _do_move(cmd: MoveCommand) -> void:
	var unit := state.get_unit(cmd.unit_id)
	var reach := reachable_cells(unit.id)
	var path := Pathfinding.path_to(reach, cmd.to)
	var cost: int = reach[cmd.to]["cost"]
	unit.ap -= cost
	unit.cell = cmd.to
	state.version += 1
	_update_explored()
	emit({"type": BattleEvents.UNIT_MOVED, "unit": unit.id, "path": path, "cost": cost, "ap": unit.ap})
	_check_alerts()
	_check_triggers(unit, path)


func _do_ability(cmd: UseAbilityCommand) -> void:
	var unit := state.get_unit(cmd.unit_id)
	var ability: Dictionary = data.abilities[cmd.ability_id]
	unit.ap -= int(ability.get("ap_cost", 0))
	var cooldown := int(ability.get("cooldown", 0))
	if cooldown > 0:
		unit.cooldowns[cmd.ability_id] = cooldown

	var affected := AbilityRules.affected_units(state, unit, ability, cmd.target)
	var affected_ids: Array[String] = []
	for a in affected:
		affected_ids.append(a.id)
	emit({"type": BattleEvents.ABILITY_USED, "unit": unit.id, "ability": cmd.ability_id,
			"target": cmd.target, "affected": affected_ids})

	for effect_def: Dictionary in ability.get("effects", []):
		var recipients: Array[BattleUnit] = affected
		if effect_def.get("to", "target") == "self":
			recipients = [unit]
		for r in recipients:
			if r.alive:
				_apply_effect(effect_def, unit, r)


func _apply_effect(effect_def: Dictionary, source: BattleUnit, target: BattleUnit) -> void:
	var effect := EffectRegistry.get_effect(effect_def.get("type", ""))
	if effect == null:
		push_error("BattleEngine: unknown effect type '%s'" % effect_def.get("type", ""))
		return
	effect.apply(self, source, target, effect_def)


func _destroy(unit: BattleUnit, by: BattleUnit) -> void:
	unit.alive = false
	unit.hull = 0
	state.version += 1
	state.turn_queue.erase(unit.id)
	emit({"type": BattleEvents.UNIT_DESTROYED, "unit": unit.id, "by": by.id if by != null else ""})


func _end_turn() -> void:
	var unit := state.active_unit()
	if unit != null:
		emit({"type": BattleEvents.TURN_ENDED, "unit": unit.id})
	state.active_unit_id = ""
	_advance_turn()


## Moves to the next unit able to act, starting new rounds as needed.
func _advance_turn() -> void:
	while not state.is_over:
		if state.turn_queue.is_empty():
			_begin_round()
			if state.is_over or state.turn_queue.is_empty():
				return
		var unit_id: String = state.turn_queue.pop_front()
		var unit := state.get_unit(unit_id)
		if not unit.alive:
			continue
		state.active_unit_id = unit_id
		if _begin_turn(unit):
			return
		if not state.is_over:
			emit({"type": BattleEvents.TURN_ENDED, "unit": unit.id})
		state.active_unit_id = ""


func _begin_round() -> void:
	state.round_number += 1
	_check_objectives()
	if state.is_over:
		return
	if state.round_number > state.max_rounds:
		_finish(BattleState.DRAW, "max_rounds")
		return
	state.turn_queue = TurnOrder.build_queue(state)
	emit({"type": BattleEvents.ROUND_STARTED, "round": state.round_number, "order": state.turn_queue.duplicate()})


## Start-of-turn upkeep. Returns false if the unit cannot act this turn.
## Order: refill AP, tick cooldowns, run status ticks, then decrement status
## durations. A status with duration 1 therefore lasts until the owner's next
## turn starts, and "skip_turn" with duration 1 skips exactly one turn.
func _begin_turn(unit: BattleUnit) -> bool:
	if not unit.alert:
		_check_alerts()
		if not unit.alert:
			return false  # dormant: waits silently
	unit.ap = unit.stat_i("max_ap")
	for ability_id: String in unit.cooldowns.keys():
		unit.cooldowns[ability_id] = int(unit.cooldowns[ability_id]) - 1
		if unit.cooldowns[ability_id] <= 0:
			unit.cooldowns.erase(ability_id)
	emit({"type": BattleEvents.TURN_STARTED, "unit": unit.id, "ap": unit.ap})

	for s in unit.statuses.duplicate():
		for effect_def: Dictionary in s.def.get("on_turn_start", []):
			if unit.alive:
				_apply_effect(effect_def, state.get_unit(s.source_id), unit)
	_check_objectives()
	if not unit.alive or state.is_over:
		return false

	var skip := unit.has_flag("skip_turn")
	for s in unit.statuses.duplicate():
		if s.is_permanent():
			continue
		s.remaining -= 1
		if s.remaining <= 0:
			unit.statuses.erase(s)
			emit({"type": BattleEvents.STATUS_EXPIRED, "target": unit.id, "status": s.id})
	if skip:
		emit({"type": BattleEvents.TURN_SKIPPED, "unit": unit.id, "reason": "disabled"})
		return false
	return true


# --- Missions: fog, dormant units, triggers ----------------------------------

func _update_explored() -> void:
	if not state.fog_enabled:
		return
	for t in state.teams:
		var explored: Dictionary = state.explored.get_or_add(t["team"], {})
		for c: Vector2i in state.visible_cells(t["team"]):
			explored[c] = true


## Wakes dormant units that can see an enemy.
func _check_alerts() -> void:
	for u in state.living_units():
		if u.alert:
			continue
		var sight := u.stat_i("sight")
		for e in state.living_enemies_of(u):
			if state.grid.distance(u.cell, e.cell) <= sight and state.grid.has_line_of_sight(u.cell, e.cell):
				_alert(u)
				break


## Wakes a unit and every dormant unit in its group.
func _alert(unit: BattleUnit) -> void:
	for u in state.living_units():
		if u.alert:
			continue
		if u == unit or (not unit.group.is_empty() and u.group == unit.group and u.team == unit.team):
			u.alert = true
			emit({"type": BattleEvents.UNIT_ALERTED, "unit": u.id})


## Fires unfired triggers on cells the unit just entered. A trigger may apply
## effects immediately and/or wait for a choice (state.pending_choice).
func _check_triggers(unit: BattleUnit, path: Array[Vector2i]) -> void:
	for i in state.triggers.size():
		var t: Dictionary = state.triggers[i]
		if t["fired"] or int(t.get("team", 0)) != unit.team:
			continue
		var entered := false
		for c in path.slice(1):
			if c in t["_cells"]:
				entered = true
				break
		if not entered:
			continue
		t["fired"] = true
		var labels: Array[String] = []
		for choice: Dictionary in t.get("choices", []):
			labels.append(choice.get("label", "?"))
		emit({"type": BattleEvents.TRIGGER_FIRED, "trigger": t.get("id", str(i)), "unit": unit.id,
				"title": t.get("title", ""), "text": t.get("text", ""), "choices": labels})
		_apply_trigger_effects(t.get("effects", []), unit)
		if not labels.is_empty():
			state.pending_choice = {"trigger": i, "unit": unit.id}
			return


func _do_choice(cmd: ChooseOptionCommand) -> void:
	var trigger: Dictionary = state.triggers[state.pending_choice["trigger"]]
	var unit := state.get_unit(state.pending_choice["unit"])
	state.pending_choice = {}
	var choice: Dictionary = trigger["choices"][cmd.option]
	emit({"type": BattleEvents.CHOICE_MADE, "trigger": trigger.get("id", ""), "option": cmd.option,
			"label": choice.get("label", ""), "text": choice.get("text", "")})
	_apply_trigger_effects(choice.get("effects", []), unit)


## Trigger effect types:
##   {"type": "effect", "to": "unit"|"squad", "effect": {any BattleEffect}}
##   {"type": "spawn", "units": [{"unit", "at": [c, r], "team", "name"?, "dormant"?, "group"?}]}
##   {"type": "alert", "group": "a"} or {"type": "alert", "team": 1}
##   {"type": "reward", "xp"?, "items"?, "trait"?, "loyalty"?}  (applied by the campaign)
func _apply_trigger_effects(effects: Array, unit: BattleUnit) -> void:
	for fx: Dictionary in effects:
		match fx.get("type", ""):
			"effect":
				var recipients: Array[BattleUnit] = [unit]
				if fx.get("to", "unit") == "squad":
					recipients = state.living_units(unit.team)
				for r in recipients:
					if r.alive:
						_apply_effect(fx.get("effect", {}), null, r)
			"spawn":
				for entry: Dictionary in fx.get("units", []):
					_spawn(entry)
			"alert":
				for u in state.living_units():
					if u.alert:
						continue
					if (fx.has("group") and u.group == fx["group"]) or (fx.has("team") and u.team == int(fx["team"])):
						_alert(u)
			"reward":
				var reward := fx.duplicate(true)
				reward.erase("type")
				state.rewards.append(reward)
				emit({"type": BattleEvents.REWARD_GAINED, "reward": reward})
			_:
				push_error("BattleEngine: unknown trigger effect '%s'" % fx.get("type", ""))


## Adds a unit mid-battle (reinforcements, ambushes). It acts from next round.
func _spawn(entry: Dictionary) -> void:
	var def: Dictionary = entry.get("unit_def", data.units.get(entry.get("unit", ""), {}))
	if def.is_empty():
		push_error("BattleEngine: cannot spawn unknown unit '%s'" % entry.get("unit", ""))
		return
	var at: Array = entry.get("at", [0, 0])
	var cell: Variant = _free_cell_near(state.grid.cell_from_layout(Vector2i(int(at[0]), int(at[1]))))
	if cell == null:
		return
	var unit_id := "spawn%d_%s" % [state.units.size(), def.get("id", "unit")]
	var u := BattleUnit.from_def(unit_id, def, int(entry.get("team", 1)), cell, entry.get("name", ""))
	u.alert = not entry.get("dormant", false)
	u.group = entry.get("group", "")
	state.units[unit_id] = u
	state.version += 1
	_update_explored()
	emit({"type": BattleEvents.UNIT_SPAWNED, "unit": unit_id})


func _free_cell_near(start: Vector2i) -> Variant:
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if state.grid.has_cell(c) and state.grid.is_passable(c) and not state.is_occupied(c):
			return c
		for n in state.grid.cells_within(c, 1):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return null


func _check_objectives() -> void:
	if state.is_over:
		return
	for o in state.objectives:
		var result := o.evaluate(state)
		if result != BattleState.NO_WINNER:
			_finish(result, "objective")
			return
	# Safety net: a battle with no opponents left always ends.
	if state.teams_alive().size() <= 1:
		var alive := state.teams_alive()
		_finish(alive[0] if alive.size() == 1 else BattleState.DRAW, "elimination")


func _finish(winner: int, reason: String) -> void:
	state.is_over = true
	state.winner = winner
	state.active_unit_id = ""
	emit({"type": BattleEvents.BATTLE_ENDED, "winner": winner, "reason": reason})


func _flush() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out
