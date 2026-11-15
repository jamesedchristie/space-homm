class_name HeroRoster
extends PanelContainer
## Hero management overlay: level/XP, status, traits, loyalty, gear slots and
## fleet postings. Emits commands for the galaxy screen to submit; it never
## changes state itself.

signal command_requested(cmd: GalaxyCommand)
signal closed

var _list: VBoxContainer
var _title: Label


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
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UiKit.header("Heroes", 20, Palette.ACTIVE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(UiKit.button("Close  [H]", func() -> void:
		visible = false
		closed.emit()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)


## Rebuilds the roster for `faction_id`. Controls are disabled unless `interactive`.
func show_roster(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	for c in _list.get_children():
		c.queue_free()
	var s := engine.state
	var data := engine.data
	var inv: Array = s.inventory.get(faction_id, [])
	_title.text = "Heroes  ·  %d item(s) in stores" % inv.size()
	for hero in s.heroes_of(faction_id):
		_list.add_child(_hero_card(engine, hero, inv, interactive))
	visible = true


func _hero_card(engine: GalaxyEngine, hero: Hero, inv: Array, interactive: bool) -> Control:
	var s := engine.state
	var data := engine.data
	var cls: Dictionary = data.hero_classes[hero.class_id]
	var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
	var box := VBoxContainer.new()
	card.add_child(box)

	var next_xp := HeroProgression.xp_for_level(data, hero.level + 1)
	var xp_text := "XP %d / %d" % [hero.xp, next_xp] if next_xp > 0 else "XP %d (max level)" % hero.xp
	var info := UiKit.rich_text(13)
	info.fit_content = true
	info.scroll_following = false
	var traits := PackedStringArray()
	for t in hero.traits:
		traits.append(data.traits.get(t, {}).get("name", t))
	var skills := PackedStringArray()
	for ability_id in HeroBuilder.skills_at(cls, hero.level):
		skills.append(data.abilities[ability_id].get("name", ability_id))
	info.append_text("[b]%s[/b]  %s\n%s   ·   %s\n%s\nSkills: %s\nTraits: %s   ·   Loyalty %d\n%s" % [
			hero.name, UiKit.color_tag("%s, level %d" % [cls.get("name", ""), hero.level], Palette.TEXT_DIM),
			xp_text, _status_text(engine, hero),
			UiKit.color_tag("Fleet doctrine (%s): %s" % [data.statuses.get(cls.get("command_status", ""), {}).get("name", "none"),
				data.statuses.get(cls.get("command_status", ""), {}).get("description", "")], Palette.TEXT_DIM),
			", ".join(skills) if not skills.is_empty() else "none",
			", ".join(traits) if not traits.is_empty() else "none", hero.loyalty,
			_next_skill_text(data, hero, cls)])
	box.add_child(info)

	var can_manage := interactive and hero.can_be_managed()
	var gear_row := HBoxContainer.new()
	gear_row.add_theme_constant_override("separation", 8)
	for slot in DataRegistry.ITEM_SLOTS:
		gear_row.add_child(UiKit.label(slot.capitalize() + ":", 12, Palette.TEXT_DIM))
		gear_row.add_child(_slot_picker(data, hero, slot, inv, can_manage))
	box.add_child(gear_row)

	var posting := HBoxContainer.new()
	posting.add_theme_constant_override("separation", 8)
	if not hero.fleet_id.is_empty() and s.fleets.has(hero.fleet_id):
		var fleet: Fleet = s.fleets[hero.fleet_id]
		var planet := s.planet_at(fleet.cell)
		var at_home := planet != null and planet.owner == hero.owner
		var relieve := UiKit.button("Relieve command at %s" % planet.name if at_home else "Relieve (fleet must be at a friendly planet)",
				func() -> void: command_requested.emit(UnassignHeroCommand.new(hero.owner, hero.id)))
		relieve.disabled = not can_manage or not at_home
		posting.add_child(relieve)
	elif s.planets.has(hero.planet_id):
		var planet: Planet = s.planets[hero.planet_id]
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		picker.add_item("Assign to a fleet at %s..." % planet.name)
		var fleet_ids: Array[String] = [""]
		for f in s.fleets_of(hero.owner):
			if f.cell == planet.cell and f.hero_id.is_empty():
				picker.add_item(f.name)
				fleet_ids.append(f.id)
		picker.disabled = not can_manage or fleet_ids.size() == 1
		if fleet_ids.size() == 1:
			picker.set_item_text(0, "No free fleet at %s" % planet.name)
		picker.item_selected.connect(func(index: int) -> void:
			if index > 0:
				command_requested.emit(AssignHeroCommand.new(hero.owner, hero.id, fleet_ids[index])))
		posting.add_child(picker)
	box.add_child(posting)
	return card


func _slot_picker(data: DataRegistry, hero: Hero, slot: String, inv: Array, enabled: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	var current: String = hero.gear.get(slot, "")
	var choices: Array[String] = [current]
	picker.add_item(data.items[current]["name"] if not current.is_empty() else "(empty)")
	for item_id: String in inv:
		if data.items.get(item_id, {}).get("slot", "") == slot and item_id not in choices:
			choices.append(item_id)
			picker.add_item(data.items[item_id]["name"])
	if not current.is_empty():
		choices.append("")
		picker.add_item("(unequip)")
	for i in choices.size():
		if not choices[i].is_empty():
			picker.set_item_tooltip(i, data.items[choices[i]].get("description", ""))
	picker.disabled = not enabled or choices.size() == 1
	picker.item_selected.connect(func(index: int) -> void:
		if index > 0:
			command_requested.emit(EquipItemCommand.new(hero.owner, hero.id, slot, choices[index])))
	return picker


func _status_text(engine: GalaxyEngine, hero: Hero) -> String:
	var s := engine.state
	match hero.status:
		Hero.READY:
			if s.fleets.has(hero.fleet_id):
				return UiKit.color_tag("Commanding %s" % s.fleets[hero.fleet_id].name, Palette.GOOD)
			return UiKit.color_tag("Waiting at %s" % s.planets.get(hero.planet_id, Planet.new()).name, Palette.TEXT)
		Hero.ON_MISSION:
			return UiKit.color_tag("Away on a mission until turn %d" % hero.busy_until, Palette.ACTIVE)
		Hero.INJURED:
			return UiKit.color_tag("Injured until turn %d" % hero.busy_until, Palette.BAD)
		Hero.CAPTURED:
			return UiKit.color_tag("Captured: a rescue mission is waiting", Palette.BAD)
		Hero.DEAD:
			return UiKit.color_tag("Killed in action", Palette.BAD)
	return hero.status


func _next_skill_text(data: DataRegistry, hero: Hero, cls: Dictionary) -> String:
	for lvl: String in cls.get("skills", {}):
		if int(lvl) > hero.level:
			var names := PackedStringArray()
			for ability_id: String in cls["skills"][lvl]:
				names.append(data.abilities[ability_id].get("name", ability_id))
			return UiKit.color_tag("Level %s unlocks: %s" % [lvl, ", ".join(names)], Palette.TEXT_DIM)
	return ""
