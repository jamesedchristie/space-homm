class_name SystemView
extends PanelContainer
## A star system up close: the star and its bodies in a small 3D view (the
## same Planet3D as the galaxy map, scaled up and seen from nearer), and a
## card per body with its type, traits, what's built there and what it
## yields, plus the build options that fit it. Emits commands only.

signal command_requested(cmd: GalaxyCommand)
signal closed

var _viewport: SubViewport
var _scene_root: Node3D
var _camera: Camera3D
var _cards: VBoxContainer
var _title: Label
var _summary: RichTextLabel
var _planet_id := ""


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
	_title = UiKit.header("System", 20, Palette.ACTIVE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(UiKit.button("Close  [Esc]", close))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	row.add_child(left)
	var view_container := SubViewportContainer.new()
	view_container.stretch = true
	view_container.custom_minimum_size = Vector2(330, 250)
	left.add_child(view_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	view_container.add_child(_viewport)
	_summary = UiKit.rich_text(13)
	_summary.scroll_following = false
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 8)
	scroll.add_child(_cards)


func close() -> void:
	visible = false
	_planet_id = ""
	closed.emit()


func shown_planet() -> String:
	return _planet_id if visible else ""


func show_system(engine: GalaxyEngine, planet: Planet, viewer: String, interactive: bool) -> void:
	var data := engine.data
	var first := _planet_id != planet.id
	_planet_id = planet.id
	_title.text = planet.name
	if first:
		_build_scene(planet, engine)
	var star: Dictionary = data.star_types.get(planet.star, {})
	var owner_text := UiKit.color_tag("Unclaimed: move a fleet here to claim it", Palette.TEXT_DIM)
	if not planet.owner.is_empty():
		var f := engine.state.faction(planet.owner)
		owner_text = UiKit.color_tag(f["name"], Palette.team_color(f["team"]))
	var lines := PackedStringArray(["%s  ·  %s" % [UiKit.color_tag(star.get("name", planet.star), Color(star.get("color", "#ffffff"))), owner_text]])
	lines.append("Yields %s per turn" % EmpirePanel._resource_text(engine, EmpireRules.planet_yields(engine, planet), true))
	if planet.population() > 0:
		lines.append("Population %d" % planet.population())
	for mp_id in planet.megaprojects:
		lines.append(UiKit.color_tag("Wonder: %s. %s" % [data.megaprojects[mp_id]["name"], data.megaprojects[mp_id].get("description", "")], Palette.ACTIVE))
	if not planet.queue.is_empty():
		lines.append(UiKit.color_tag("Building: %s (%d/%d turns)" % [_queue_name(data, planet), planet.queue["progress"], planet.queue["turns"]], Palette.ACTIVE))
	var defenses := EmpireRules.defense_units(engine, planet).size()
	if defenses > 0:
		lines.append(UiKit.color_tag("%d defense platform(s)" % defenses, Palette.BAD))
	if planet.owner == viewer:
		lines.append("")
		lines.append(UiKit.color_tag("Habitable worlds take a colony; rocks and belts a mining base; ice and gas giants a research station or refinery. Colonies hold a shipyard, trade hub and defenses. One build at a time per system.", Palette.TEXT_DIM))
	_summary.clear()
	_summary.append_text("\n".join(lines))

	for c in _cards.get_children():
		c.queue_free()
	var options := EmpireRules.build_options(engine, planet) if planet.owner == viewer else ([] as Array[Dictionary])
	for b in planet.bodies:
		_cards.add_child(_body_card(engine, planet, b, options.filter(func(o: Dictionary) -> bool: return o["body"] == b["id"]), interactive))
	var wonders := options.filter(func(o: Dictionary) -> bool: return o["kind"] == "megaproject")
	if not wonders.is_empty():
		var wonder_card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var wonder_box := VBoxContainer.new()
		wonder_card.add_child(wonder_box)
		wonder_box.add_child(UiKit.label("Megaprojects", 15, Palette.ACTIVE))
		wonder_box.add_child(_option_row(engine, planet, wonders, interactive))
		_cards.add_child(wonder_card)
	var ships := options.filter(func(o: Dictionary) -> bool: return o["kind"] == "unit")
	if not ships.is_empty():
		var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(UiKit.label("Shipyard", 15, Palette.TEXT))
		box.add_child(_option_row(engine, planet, ships, interactive))
		_cards.add_child(card)
	visible = true


func _body_card(engine: GalaxyEngine, planet: Planet, b: Dictionary, options: Array, interactive: bool) -> Control:
	var data := engine.data
	var def: Dictionary = data.body_types.get(b["type"], {})
	var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.scroll_active = false
	var surface := Color(def.get("surface", {}).get("accent", "#aaaaaa"))
	var built := PackedStringArray()
	for building_id: String in b["buildings"]:
		built.append(data.buildings[building_id]["name"])
	var traits := PackedStringArray()
	for t: String in b["traits"]:
		traits.append(UiKit.color_tag(data.planet_traits[t]["name"], Palette.ACTIVE))
	var text := "%s [b]%s[/b]  %s" % [UiKit.color_tag("●", surface), b["name"], UiKit.color_tag(def.get("name", b["type"]), Palette.TEXT_DIM)]
	if not traits.is_empty():
		text += "  ·  " + ", ".join(traits)
	text += "\n" + (", ".join(built) + "  ·  " + EmpirePanel._resource_text(engine, EmpireRules.body_yields(engine, b, planet.owner), true)
			if not built.is_empty() else UiKit.color_tag(def.get("description", ""), Palette.TEXT_DIM))
	if EmpireRules.is_habitable(engine, b) and "colony" in b["buildings"]:
		text += UiKit.color_tag("  ·  colony slots %d/%d" % [b["buildings"].size() - 1, EmpireRules.colony_slots(engine, b, planet.owner)], Palette.TEXT_DIM)
		text += "\n" + _population_text(engine, b, planet.owner)
	head.append_text(text)
	box.add_child(head)
	if not options.is_empty():
		box.add_child(_option_row(engine, planet, options, interactive))
	return card


func _option_row(engine: GalaxyEngine, planet: Planet, options: Array, interactive: bool) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	for o: Dictionary in options:
		var label := "%s  ·  %s, %dt" % [o["name"], EmpireRules.cost_text(engine, o["cost"]), o["turns"]]
		var b := UiKit.button(label, func() -> void:
			command_requested.emit(QueueBuildCommand.new(planet.owner, planet.id, o["kind"], o["id"], o["body"])))
		var desc := ""
		match o["kind"]:
			"building":
				desc = engine.data.buildings[o["id"]].get("description", "")
			"megaproject":
				desc = engine.data.megaprojects[o["id"]].get("description", "")
			_:
				desc = engine.data.units[o["id"]].get("description", "")
		b.tooltip_text = desc + ("" if o["ok"] else "\n(%s)" % o["reason"])
		b.disabled = not interactive or not o["ok"]
		row.add_child(b)
	return row


static func _queue_name(data: DataRegistry, planet: Planet) -> String:
	var q := planet.queue
	match q["kind"]:
		"building":
			return data.buildings[q["item"]]["name"]
		"megaproject":
			return data.megaprojects[q["item"]]["name"]
	return data.units[q["item"]]["name"]


## "Population 5 / 8   ·   growth +0.8/turn, next in 4 turns" for a colony body.
static func _population_text(engine: GalaxyEngine, b: Dictionary, faction_id: String) -> String:
	var cap := EmpireRules.pop_cap(engine, b, faction_id)
	var current := EmpireRules.pop(b)
	var text := "Population [b]%d / %d[/b]" % [current, cap]
	if current >= cap:
		return text + UiKit.color_tag("   ·   full", Palette.TEXT_DIM)
	var rate := EmpireRules.growth_rate(engine, b, faction_id)
	var progress := "%d/%d" % [floori(float(b.get("growth", 0.0))), ceili(EmpireRules.growth_cost(engine, current))]
	return text + UiKit.color_tag("   ·   growth %+.1f/turn (%s), next pop in %d turns" % [rate, progress,
			EmpireRules.turns_to_grow(engine, b, faction_id)], Palette.GOOD)


func _build_scene(planet: Planet, engine: GalaxyEngine) -> void:
	if _scene_root != null:
		_scene_root.queue_free()
	_scene_root = Node3D.new()
	_viewport.add_child(_scene_root)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.45)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env_node.environment = env
	_scene_root.add_child(env_node)
	BoardGeometry.space_scenery(_scene_root, Vector3.ZERO, Vector2(1.0, 1.0), absi(hash(planet.id)), true)
	var system := Planet3D.new()
	_scene_root.add_child(system)
	system.setup(planet, engine.data)
	system.refresh(planet, engine.state)
	system.scale = Vector3.ONE * 2.2
	system.show_floor(false)
	_camera = Camera3D.new()
	_camera.fov = 38
	_scene_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 2.1, 2.5), Vector3(0, 0.62, 0), Vector3.UP)
