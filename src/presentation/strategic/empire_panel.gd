class_name EmpirePanel
extends PanelContainer
## Empire management overlay with four tabs: Systems (yields, population,
## buildings, build queue), Research (tech tree by era), Diplomacy (war/peace,
## opinion, gifts) and Victory (how close everyone is to winning). Like the
## hero roster, it only emits commands.

signal command_requested(cmd: GalaxyCommand)
signal closed
## "Open" on a system in the Colonies tab.
signal system_requested(planet_id: String)
## "Tech tree" in the Research tab.
signal tech_tree_requested
## "Contact" on a faction in the Diplomacy tab: open the leader's screen.
signal contact_requested(faction_id: String)

const TABS := ["Systems", "Research", "Diplomacy", "Victory"]

var _tabs: TabContainer
var _lists: Array[VBoxContainer] = []


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiKit.header("Empire", 20, Palette.ACTIVE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UiKit.button("Close  [E]", func() -> void:
		visible = false
		closed.emit()))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for tab_name in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		_lists.append(list)


func show_panel(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	for list in _lists:
		for c in list.get_children():
			c.queue_free()
	_build_colonies(engine, faction_id, interactive)
	_build_research(engine, faction_id, interactive)
	_build_diplomacy(engine, faction_id, interactive)
	_build_victory(engine, faction_id)
	visible = true


# --- Colonies -----------------------------------------------------------------

func _build_colonies(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	var list := _lists[0]
	var data := engine.data
	var income := EmpireRules.income(engine, faction_id)
	list.add_child(_text("Income per turn: %s" % _resource_text(engine, income, true)))
	var upkeep := int(income["upkeep"])
	var fleet_cost := EmpireRules.fleet_upkeep(engine, faction_id)
	list.add_child(_text(UiKit.color_tag("Ships cost %d credits a turn to keep; your colonies support %d for free, so you pay %d (already counted in the credits above). Population: %d across %d colonies." % [
			fleet_cost, EmpireRules.free_upkeep(engine, faction_id), upkeep, EmpireRules.total_population(engine, faction_id),
			EmpireRules.colony_count(engine, faction_id)], Palette.TEXT_DIM)))
	if int(engine.state.resources[faction_id]["credits"]) < 0:
		list.add_child(_text(UiKit.color_tag("Budget crisis: the treasury is in debt. Colonies don't grow, fleets don't repair and ships lose hull until you are in the black.", Palette.BAD)))
	var active: Array = engine.state.modifiers.get(faction_id, [])
	for m: Dictionary in active:
		list.add_child(_text(UiKit.color_tag("Active: %s (%d turns left)" % [m["name"], int(m["turns"])], Palette.ACTIVE)))
	for mp_id in EmpireRules.megaprojects_of(engine, faction_id):
		list.add_child(_text(UiKit.color_tag("Wonder: %s. %s" % [engine.data.megaprojects[mp_id]["name"],
				engine.data.megaprojects[mp_id].get("description", "")], Palette.ACTIVE)))
	for planet in engine.state.planets_of(faction_id):
		var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var box := VBoxContainer.new()
		card.add_child(box)
		var developed := planet.bodies.filter(func(b: Dictionary) -> bool: return not b["buildings"].is_empty()).size()
		var names := PackedStringArray()
		for b in planet.buildings:
			names.append(data.buildings[b]["name"])
		var row := HBoxContainer.new()
		box.add_child(row)
		var pops := PackedStringArray()
		for b in planet.colonies():
			var grow := EmpireRules.turns_to_grow(engine, b, faction_id)
			pops.append("%s %d/%d%s" % [b["name"], EmpireRules.pop(b), EmpireRules.pop_cap(engine, b, faction_id),
					(" (+1 in %dt)" % grow) if grow > 0 else ""])
		var info := _text("[b]%s[/b]   ·   %d/%d bodies developed   ·   %s\n%s%s" % [planet.name,
				developed, planet.bodies.size(), _resource_text(engine, EmpireRules.planet_yields(engine, planet), true),
				", ".join(names) if not names.is_empty() else UiKit.color_tag("Nothing built yet", Palette.TEXT_DIM),
				("\n" + UiKit.color_tag("Population: " + ", ".join(pops), Palette.GOOD)) if not pops.is_empty() else ""])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var pid := planet.id
		row.add_child(UiKit.button("Open", func() -> void: system_requested.emit(pid)))
		if not planet.queue.is_empty():
			var q := planet.queue
			var item_name := SystemView._queue_name(data, planet)
			box.add_child(_text(UiKit.color_tag("Building %s: %d/%d turns" % [item_name, q["progress"], q["turns"]], Palette.ACTIVE)))
		else:
			box.add_child(_text(UiKit.color_tag("Idle", Palette.TEXT_DIM)))
		list.add_child(card)


# --- Research -----------------------------------------------------------------

func _build_research(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	var list := _lists[1]
	var data := engine.data
	var r: Dictionary = engine.state.research[faction_id]
	var per_turn := int(EmpireRules.income(engine, faction_id)["research"])
	if r["current"].is_empty():
		list.add_child(_text(UiKit.color_tag("Choose a technology. Research points are banked until you do (%d banked, +%d per turn)." % [r["progress"], per_turn], Palette.ACTIVE)))
	else:
		list.add_child(_text("Researching [b]%s[/b]: %d / %d (+%d per turn)" % [data.techs[r["current"]]["name"],
				r["progress"], ResearchRules.cost(engine, r["current"]), per_turn]))
	list.add_child(UiKit.button("Open the tech tree  [T]", func() -> void: tech_tree_requested.emit()))
	var era := ResearchRules.current_era(engine, faction_id)
	list.add_child(_text(UiKit.color_tag("Current era: %s. Each era opens once enough techs of the one before are known." % ResearchRules.era_name(engine, era), Palette.TEXT_DIM)))
	var shown_era := 0
	for tech_id: String in _tech_order(engine):
		var tech: Dictionary = data.techs[tech_id]
		if ResearchRules.era_of(engine, tech_id) != shown_era:
			shown_era = ResearchRules.era_of(engine, tech_id)
			var need: Dictionary = data.eras.get(str(shown_era), {}).get("requires", {})
			var open := ResearchRules.era_open(engine, faction_id, shown_era)
			var era_text := "%s%s" % [ResearchRules.era_name(engine, shown_era), "" if need.is_empty() else
					("  (needs %d %s techs: %d known)" % [int(need["count"]), ResearchRules.era_name(engine, int(need["era"])),
					ResearchRules.known_in_era(engine, faction_id, int(need["era"]))])]
			list.add_child(UiKit.label(era_text + ("" if open else "  - locked"), 15, Palette.ACTIVE if open else Palette.TEXT_DIM))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var status := ResearchRules.status(engine, faction_id, tech_id)
		var info := _text("[b]%s[/b]  %s\n%s" % [tech["name"], UiKit.color_tag("%d research" % ResearchRules.cost(engine, tech_id), Palette.TEXT_DIM),
				tech.get("description", "")])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		match status:
			ResearchRules.KNOWN:
				row.add_child(UiKit.label("Researched", 13, Palette.GOOD))
			ResearchRules.LOCKED:
				var reason := UiKit.label(ResearchRules.lock_reason(engine, faction_id, tech_id), 12, Palette.TEXT_DIM)
				reason.custom_minimum_size = Vector2(260, 0)
				reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.add_child(reason)
			_:
				var b := UiKit.button("Researching" if r["current"] == tech_id else "Research",
						func() -> void: command_requested.emit(SetResearchCommand.new(faction_id, tech_id)))
				b.disabled = not interactive or r["current"] == tech_id
				row.add_child(b)
		list.add_child(row)


# --- Diplomacy ----------------------------------------------------------------

func _build_diplomacy(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	var list := _lists[2]
	var s := engine.state
	var mine: Dictionary = engine.data.species.get(s.faction(faction_id).get("species", ""), {})
	if not mine.is_empty():
		list.add_child(_text("You are [b]%s[/b]: %s" % [mine["name"], UiKit.color_tag(mine.get("bonus_text", ""), Palette.ACTIVE)]))
	list.add_child(_text(UiKit.color_tag("At peace, fleets can't attack each other or take each other's systems. "
			+ "Only major powers compete for victory: the game ends when one is left, or when none are at war "
			+ "(highest score wins). Minor powers pay trade income to friends at peace (opinion 30+: +3, 60+: +6 credits).", Palette.TEXT_DIM)))
	var trade := EmpireRules.trade_income(engine, faction_id)
	if trade > 0:
		list.add_child(_text(UiKit.color_tag("Trade income: +%d credits per turn" % trade, Palette.GOOD)))
	for f in s.factions:
		var other: String = f["id"]
		if other == faction_id:
			continue
		var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var box := VBoxContainer.new()
		card.add_child(box)
		var color := Palette.team_color(f["team"])
		if s.is_eliminated(other):
			box.add_child(_text("%s: eliminated" % UiKit.color_tag(f["name"], color)))
			list.add_child(card)
			continue
		var war := s.at_war(faction_id, other)
		var sp: Dictionary = engine.data.species.get(f.get("species", ""), {})
		var role_text: String = {"barbarian": "Barbarians: they raid and plunder, never negotiate and can't win. Their dens launch new raiders; clearing one pays loot.",
				"minor": "Minor power: neutral traders who don't compete for victory."}.get(f.get("role", "major"), "Major power")
		box.add_child(_text("[b]%s[/b]   %s   ·   their opinion of you: %d   ·   score %d\n%s%s" % [
				UiKit.color_tag(f["name"], color),
				UiKit.color_tag("WAR", Palette.BAD) if war else UiKit.color_tag("PEACE", Palette.GOOD),
				s.opinion(other, faction_id), EmpireRules.score(engine, other),
				UiKit.color_tag(role_text, Palette.TEXT_DIM),
				("\n" + UiKit.color_tag("%s: %s" % [sp["name"], sp.get("bonus_text", "")], Palette.TEXT_DIM)) if not sp.is_empty() else ""]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var met := s.has_met(faction_id, other)
		var contact := UiKit.button("Contact", func() -> void: contact_requested.emit(other))
		contact.disabled = not met
		contact.tooltip_text = "Speak with their leader" if met else "You haven't met them yet: find one of their fleets or systems first."
		row.add_child(contact)
		var peace := UiKit.button("Propose peace", func() -> void:
			command_requested.emit(DiplomacyCommand.new(faction_id, other, "propose_peace")))
		peace.disabled = not interactive or not war or f.get("always_hostile", false) or f["controller"] == "player"
		row.add_child(peace)
		var declare := UiKit.button("Declare war", func() -> void:
			command_requested.emit(DiplomacyCommand.new(faction_id, other, "declare_war")))
		declare.disabled = not interactive or war
		row.add_child(declare)
		var gift := UiKit.button("Gift %d credits" % DiplomacyRules.GIFT_CREDITS, func() -> void:
			command_requested.emit(DiplomacyCommand.new(faction_id, other, "gift")))
		gift.disabled = not interactive or int(s.resources[faction_id]["credits"]) < DiplomacyRules.GIFT_CREDITS
		row.add_child(gift)
		box.add_child(row)
		list.add_child(card)


# --- Victory ------------------------------------------------------------------

func _build_victory(engine: GalaxyEngine, faction_id: String) -> void:
	var list := _lists[3]
	var s := engine.state
	list.add_child(_text(UiKit.color_tag("Every way this campaign can be won, and how close each major power is. The first to meet a condition wins; you can still stop a rival's Ascension Gate by conquering the system it is built in.", Palette.TEXT_DIM)))
	for entry: Dictionary in VictoryRules.progress(engine):
		var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		var leader: String = entry["leader"]
		var lead_text := ""
		if not leader.is_empty():
			var lf := s.faction(leader)
			lead_text = "   leader: " + UiKit.color_tag(lf["name"] + (" (you)" if leader == faction_id else ""), Palette.team_color(lf["team"]))
		box.add_child(_text("[b]%s[/b]%s\n%s" % [entry["name"], lead_text if entry["enabled"] else "", UiKit.color_tag(entry["text"], Palette.TEXT_DIM)]))
		for row_data: Dictionary in entry["rows"]:
			var f := s.faction(row_data["faction"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var name_label := UiKit.label(f["name"] + (" (you)" if f["id"] == faction_id else ""), 13, Palette.team_color(f["team"]))
			name_label.custom_minimum_size = Vector2(170, 0)
			row.add_child(name_label)
			var bar := ProgressBar.new()
			bar.min_value = 0.0
			bar.max_value = 1.0
			bar.value = float(row_data["value"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(160, 14)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bar)
			var detail := UiKit.label(row_data["text"], 12, Palette.TEXT_DIM)
			detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(detail)
			box.add_child(row)
		list.add_child(card)


# --- Helpers ------------------------------------------------------------------

## Tech ids ordered by era, then cost.
static func _tech_order(engine: GalaxyEngine) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(ResearchRules.tech_ids(engine))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ea := ResearchRules.era_of(engine, a)
		var eb := ResearchRules.era_of(engine, b)
		if ea != eb:
			return ea < eb
		if ResearchRules.cost(engine, a) != ResearchRules.cost(engine, b):
			return ResearchRules.cost(engine, a) < ResearchRules.cost(engine, b)
		return a < b)
	return ids



func _text(bbcode: String) -> RichTextLabel:
	var t := UiKit.rich_text(13)
	t.fit_content = true
	t.scroll_following = false
	t.append_text(bbcode)
	return t


static func _resource_text(engine: GalaxyEngine, amounts: Dictionary, signed: bool) -> String:
	var parts := PackedStringArray()
	for k: String in engine.data.resources:
		if roundi(float(amounts.get(k, 0))) == 0:
			continue
		var res: Dictionary = engine.data.resources.get(k, {})
		var fmt := "%+d %s" if signed else "%d %s"
		parts.append(UiKit.color_tag(fmt % [roundi(float(amounts[k])), res.get("name", k).to_lower()], Color(res.get("color", "#ffffff"))))
	return ", ".join(parts) if not parts.is_empty() else UiKit.color_tag("nothing", Palette.TEXT_DIM)
