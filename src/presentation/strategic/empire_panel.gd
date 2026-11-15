class_name EmpirePanel
extends PanelContainer
## Empire management overlay with three tabs: Colonies (yields, buildings,
## build queue), Research (tech tree) and Diplomacy (war/peace, opinion,
## gifts). Like the hero roster, it only emits commands.

signal command_requested(cmd: GalaxyCommand)
signal closed

const TABS := ["Colonies", "Research", "Diplomacy"]

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
	visible = true


# --- Colonies -----------------------------------------------------------------

func _build_colonies(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	var list := _lists[0]
	var data := engine.data
	var income := EmpireRules.income(engine, faction_id)
	list.add_child(_text("Income per turn: %s" % _resource_text(engine, income, true)))
	for planet in engine.state.planets_of(faction_id):
		var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var box := VBoxContainer.new()
		card.add_child(box)
		var names := PackedStringArray()
		for b in planet.buildings:
			names.append(data.buildings[b]["name"])
		box.add_child(_text("[b]%s[/b]  %s   ·   buildings %d/%d   ·   %s\n%s" % [planet.name,
				UiKit.color_tag(data.planet_types[planet.type]["name"], Palette.TEXT_DIM),
				planet.buildings.size(), EmpireRules.slots(engine, planet),
				_resource_text(engine, EmpireRules.planet_yields(engine, planet), true),
				", ".join(names) if not names.is_empty() else UiKit.color_tag("No buildings yet", Palette.TEXT_DIM)]))
		if not planet.queue.is_empty():
			var q := planet.queue
			var item_name: String = data.buildings[q["item"]]["name"] if q["kind"] == "building" else data.units[q["item"]]["name"]
			box.add_child(_text(UiKit.color_tag("Building %s: %d/%d turns" % [item_name, q["progress"], q["turns"]], Palette.ACTIVE)))
		else:
			box.add_child(_build_picker(engine, planet, interactive))
		list.add_child(card)


func _build_picker(engine: GalaxyEngine, planet: Planet, interactive: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.add_item("Build...")
	var options := EmpireRules.build_options(engine, planet)
	for i in options.size():
		var o := options[i]
		var label := "%s%s — %s, %d turns" % ["Ship: " if o["kind"] == "unit" else "", o["name"],
				EmpireRules.cost_text(engine, o["cost"]), o["turns"]]
		picker.add_item(label if o["ok"] else "%s (%s)" % [label, o["reason"].to_lower()])
		picker.set_item_disabled(i + 1, not o["ok"])
		var desc: String = engine.data.buildings[o["id"]].get("description", "") if o["kind"] == "building" \
				else engine.data.units[o["id"]].get("description", "")
		picker.set_item_tooltip(i + 1, desc)
	picker.disabled = not interactive or options.is_empty()
	picker.item_selected.connect(func(index: int) -> void:
		if index > 0:
			var o := options[index - 1]
			command_requested.emit(QueueBuildCommand.new(planet.owner, planet.id, o["kind"], o["id"])))
	return picker


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
	for tech_id: String in data.techs:
		var tech: Dictionary = data.techs[tech_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var status := ResearchRules.status(engine, faction_id, tech_id)
		var info := _text("[b]%s[/b]  %s\n%s" % [tech["name"], UiKit.color_tag("%d research" % tech.get("cost", 0), Palette.TEXT_DIM),
				tech.get("description", "")])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		match status:
			ResearchRules.KNOWN:
				row.add_child(UiKit.label("Researched", 13, Palette.GOOD))
			ResearchRules.LOCKED:
				var reqs := PackedStringArray()
				for req: String in tech.get("requires", []):
					reqs.append(data.techs[req]["name"])
				row.add_child(UiKit.label("Requires " + ", ".join(reqs), 12, Palette.TEXT_DIM))
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
	list.add_child(_text(UiKit.color_tag("At peace, fleets can't attack each other or take each other's planets. "
			+ "The war ends when no surviving factions are at war; the highest score wins.", Palette.TEXT_DIM)))
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
		box.add_child(_text("[b]%s[/b]   %s   ·   their opinion of you: %d   ·   score %d%s" % [
				UiKit.color_tag(f["name"], color),
				UiKit.color_tag("WAR", Palette.BAD) if war else UiKit.color_tag("PEACE", Palette.GOOD),
				s.opinion(other, faction_id), EmpireRules.score(engine, other),
				"\n" + UiKit.color_tag("They never negotiate.", Palette.TEXT_DIM) if f.get("always_hostile", false) else ""]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
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


# --- Helpers ------------------------------------------------------------------

func _text(bbcode: String) -> RichTextLabel:
	var t := UiKit.rich_text(13)
	t.fit_content = true
	t.scroll_following = false
	t.append_text(bbcode)
	return t


static func _resource_text(engine: GalaxyEngine, amounts: Dictionary, signed: bool) -> String:
	var parts := PackedStringArray()
	for k: String in EmpireRules.RESOURCES:
		if int(amounts.get(k, 0)) == 0:
			continue
		var res: Dictionary = engine.data.resources.get(k, {})
		var fmt := "%+d %s" if signed else "%d %s"
		parts.append(UiKit.color_tag(fmt % [int(amounts[k]), res.get("name", k).to_lower()], Color(res.get("color", "#ffffff"))))
	return ", ".join(parts) if not parts.is_empty() else UiKit.color_tag("nothing", Palette.TEXT_DIM)
