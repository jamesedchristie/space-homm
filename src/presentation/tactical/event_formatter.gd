class_name EventFormatter
extends RefCounted
## Turns engine events into combat-log lines (BBCode).


static func describe(e: Dictionary, engine: BattleEngine) -> String:
	var data := engine.data
	match e["type"]:
		BattleEvents.BATTLE_STARTED:
			return "[color=#%s]Battle begins. %s[/color]" % [Palette.hex(Palette.TEXT_DIM), engine.objective_text()]
		BattleEvents.ROUND_STARTED:
			return "\n[b]Round %d[/b]" % e["round"]
		BattleEvents.UNIT_MOVED:
			return "%s moves (%d AP)" % [unit_name(engine, e["unit"]), e["cost"]]
		BattleEvents.ABILITY_USED:
			return "%s: [b]%s[/b]" % [unit_name(engine, e["unit"]), data.abilities[e["ability"]].get("name", e["ability"])]
		BattleEvents.DAMAGE_DEALT:
			var parts := PackedStringArray()
			if e["shield_damage"] > 0:
				parts.append("[color=#%s]%d shields[/color]" % [Palette.hex(Palette.SHIELDS), e["shield_damage"]])
			if e["hull_damage"] > 0:
				parts.append("[color=#%s]%d hull[/color]" % [Palette.hex(Palette.HULL), e["hull_damage"]])
			if parts.is_empty():
				parts.append("no damage")
			return "   %s takes %s" % [unit_name(engine, e["target"]), " + ".join(parts)]
		BattleEvents.HEALED:
			return "   %s restores %d %s" % [unit_name(engine, e["target"]), e["amount"], e["stat"]]
		BattleEvents.STATUS_APPLIED:
			return "   %s is [i]%s[/i]" % [unit_name(engine, e["target"]), status_name(data, e["status"])]
		BattleEvents.STATUS_RESISTED:
			return "   %s avoids [i]%s[/i]" % [unit_name(engine, e["target"]), status_name(data, e["status"])]
		BattleEvents.STATUS_EXPIRED:
			return "   %s is no longer [i]%s[/i]" % [unit_name(engine, e["target"]), status_name(data, e["status"])]
		BattleEvents.TURN_SKIPPED:
			return "%s is disabled and loses its turn" % unit_name(engine, e["unit"])
		BattleEvents.UNIT_DESTROYED:
			var fallen := engine.state.get_unit(e["unit"])
			var verb := "is down" if "infantry" in fallen.tags else "destroyed"
			return "[color=#%s][b]%s %s![/b][/color]" % [Palette.hex(Palette.BAD), fallen.name, verb]
		BattleEvents.UNIT_SPAWNED:
			return "[color=#%s]Enemy reinforcements: %s[/color]" % [Palette.hex(Palette.BAD), engine.state.get_unit(e["unit"]).name]
		BattleEvents.TRIGGER_FIRED:
			var title: String = e["title"]
			return "[b]%s[/b] %s" % [title + ":" if not title.is_empty() else "", e["text"]]
		BattleEvents.CHOICE_MADE:
			return "   → %s. %s" % [e["label"], e["text"]]
		BattleEvents.REWARD_GAINED:
			return UiKit.color_tag("   Reward recorded for the campaign", Palette.ACTIVE)
		BattleEvents.BATTLE_ENDED:
			return "\n[b]%s[/b]" % result_text(engine)
	return ""


static func unit_name(engine: BattleEngine, unit_id: String) -> String:
	var u := engine.state.get_unit(unit_id)
	if u == null:
		return "?"
	return "[color=#%s]%s[/color]" % [Palette.hex(Palette.team_color(u.team)), u.name]


static func status_name(data: DataRegistry, status_id: String) -> String:
	return data.statuses.get(status_id, {}).get("name", status_id)


static func result_text(engine: BattleEngine) -> String:
	var s := engine.state
	if s.winner == BattleState.DRAW:
		return "Draw"
	var team := s.team_info(s.winner)
	return "%s wins" % team.get("name", "Team %d" % s.winner)
