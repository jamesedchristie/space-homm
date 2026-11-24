class_name SystemView
extends PanelContainer
## The system map: a star system up close. A big 3D view (SystemMap) whose bodies
## you click, with your civilian ships drawn at the bodies they sit at or work on,
## and a side panel for the selected body (what it is, what's built, the actions your
## Colony Ships and Constructors can take there), the ships in the system and the
## system's build queue. Emits commands only.
##
## Keys (while open): Tab / Left / Right or 1-9 pick a body, F founds a colony there
## with a Colony Ship, Esc or S closes.

signal command_requested(cmd: GalaxyCommand)
## "Send..." on an idle civilian ship: the galaxy screen lets you click a destination world.
signal send_ship_requested(ship_uid: String)
signal closed

const SIDE_W := 400.0

var _map: SystemMap
var _title: Label
var _subtitle: RichTextLabel
var _summary: RichTextLabel
var _scroll: ScrollContainer
var _side: VBoxContainer
var _planet_id := ""
var _engine: GalaxyEngine
var _viewer := ""
var _interactive := false
## Selected body id and civilian ship uid.
var _body := ""
var _ship := ""


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.PANEL_BG, 1.0)
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	box.add_child(header)
	_title = UiKit.header("System", 22, Palette.ACTIVE)
	header.add_child(_title)
	_subtitle = UiKit.rich_text(13)
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_subtitle)
	header.add_child(UiKit.button("Close  [Esc]", close))

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_map = SystemMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.body_clicked.connect(_select_body)
	_map.ship_clicked.connect(_select_ship)
	left.add_child(_map)
	_summary = UiKit.rich_text(13)
	_summary.fit_content = true
	_summary.scroll_active = false
	left.add_child(_summary)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(SIDE_W, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 8)
	_scroll.add_child(_side)


func close() -> void:
	visible = false
	_planet_id = ""
	closed.emit()


func shown_planet() -> String:
	return _planet_id if visible else ""


## Shows (or refreshes) a system. `interactive` is false while the AI moves or an animation plays.
func show_system(engine: GalaxyEngine, planet: Planet, viewer: String, interactive: bool) -> void:
	var first := _planet_id != planet.id
	_engine = engine
	_viewer = viewer
	_interactive = interactive
	_planet_id = planet.id
	if first:
		_body = _default_body(planet)
		_ship = ""
	elif planet.body(_body).is_empty():
		_body = _default_body(planet)
	if not _ship.is_empty() and SystemRules.find_ship(engine, planet, viewer, _ship).is_empty():
		_ship = ""
	_map.show_planet(planet, engine)
	_refresh()
	visible = true


func _planet() -> Planet:
	return _engine.state.planets[_planet_id]


## The first thing worth looking at: a habitable world to settle if a Colony Ship is here, else the colony.
func _default_body(planet: Planet) -> String:
	var ships := SystemRules.ships_here(_engine, planet, _viewer)
	var has_colony_ship := ships.any(func(e: Dictionary) -> bool: return e["role"] == "colony")
	if has_colony_ship:
		var targets := SystemRules.colony_targets(_engine, planet, _viewer)
		if not targets.is_empty():
			var best := targets[0]
			for b in targets:
				if EmpireRules.pop_cap(_engine, b, _viewer) > EmpireRules.pop_cap(_engine, best, _viewer):
					best = b
			return best["id"]
	for b in planet.colonies():
		return b["id"]
	return planet.bodies[0]["id"] if not planet.bodies.is_empty() else ""


func _select_body(body_id: String) -> void:
	_body = body_id
	_refresh()


func _select_ship(uid: String) -> void:
	_ship = "" if _ship == uid else uid
	var planet := _planet()
	var entry := SystemRules.find_ship(_engine, planet, _viewer, _ship)
	if not entry.is_empty():
		var loc: String = entry["ship"].get("loc", "")
		if not loc.is_empty():
			_body = loc
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var planet := _planet()
	var ids: Array[String] = []
	for b in planet.bodies:
		ids.append(b["id"])
	var index := ids.find(_body)
	var handled := true
	match event.keycode:
		KEY_TAB, KEY_RIGHT, KEY_DOWN:
			_select_body(ids[(index + (-1 if event.shift_pressed else 1) + ids.size()) % ids.size()])
		KEY_LEFT, KEY_UP:
			_select_body(ids[(index - 1 + ids.size()) % ids.size()])
		KEY_F:
			var colony := _pick("colony")
			if not colony.is_empty() and _interactive:
				_found_colony(colony)
			handled = not colony.is_empty()
		_:
			var n: int = event.keycode - KEY_1
			if n >= 0 and n < mini(ids.size(), 9):
				_select_body(ids[n])
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	var planet := _planet()
	var data := _engine.data
	var mine := planet.owner == _viewer
	var star: Dictionary = data.star_types.get(planet.star, {})
	var owner_text := UiKit.color_tag("Unclaimed: a colony or an outpost claims it; flying a fleet in doesn't", Palette.TEXT_DIM)
	if not planet.owner.is_empty():
		var f := _engine.state.faction(planet.owner)
		owner_text = UiKit.color_tag(f["name"], Palette.team_color(f["team"]))
	_title.text = planet.name
	_subtitle.clear()
	_subtitle.append_text("%s  ·  %s" % [UiKit.color_tag(star.get("name", planet.star), Color(star.get("color", "#ffffff"))), owner_text])

	var ships := SystemRules.ships_here(_engine, planet, _viewer)
	_map.selected_body = _body
	_map.labels = _body_labels(planet)
	_map.markers = _ship_markers(planet, ships)
	_map.banner = ""
	if planet.is_blockaded():
		var holder := _engine.state.faction(planet.blockade)
		_map.banner = "BLOCKADED by %s: no production, no growth" % holder.get("name", "an enemy fleet")
	_summary.clear()
	_summary.append_text(_summary_text(planet, mine, ships))

	var scroll_to := _scroll.scroll_vertical
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	var body := planet.body(_body)
	if not body.is_empty():
		_side.add_child(_body_card(planet, body, ships))
	if mine or not ships.is_empty():
		_side.add_child(_ships_card(planet, ships))
	if mine:
		_side.add_child(_production_card(planet))
	_scroll.set_deferred("scroll_vertical", scroll_to)


func _body_labels(planet: Planet) -> Dictionary:
	var data := _engine.data
	var out := {}
	for b in planet.bodies:
		var def: Dictionary = data.body_types.get(b["type"], {})
		var info := ""
		var color := Palette.TEXT_DIM
		if "colony" in b["buildings"]:
			info = "Colony  ·  pop %d/%d" % [EmpireRules.pop(b), EmpireRules.pop_cap(_engine, b, planet.owner)]
			color = Palette.GOOD
		elif not b["buildings"].is_empty():
			info = data.buildings[b["buildings"][0]]["name"]
			color = Palette.SHIELDS
		else:
			var worker := SystemRules.job_on_body(planet, b["id"])
			if not worker.is_empty():
				info = "Building %s" % data.buildings[worker["job"]["building"]]["name"]
				color = Palette.ACTIVE
			elif EmpireRules.is_habitable(_engine, b):
				info = "Habitable  ·  unsettled"
				color = Color(0.55, 0.9, 0.6)
			else:
				info = def.get("name", b["type"])
		out[b["id"]] = {"name": b["name"], "info": info, "color": color}
	return out


func _ship_markers(planet: Planet, ships: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var color := Palette.team_color(_engine.state.faction(_viewer)["team"])
	var species: String = _engine.state.faction(_viewer).get("species", "")
	for e in ships:
		var s: Dictionary = e["ship"]
		var job: Dictionary = s.get("job", {})
		var at: String = job.get("body", s.get("loc", "")) if e["deployed"] else ""
		out.append({"uid": s["uid"], "body": at, "role": e["role"], "name": s["name"],
				"progress": (1.0 - float(job["turns_left"]) / maxf(float(job["turns"]), 1.0)) if not job.is_empty() else -1.0,
				"color": color, "selected": s["uid"] == _ship, "unit": s.get("unit", ""), "style": species,
				"deployed": e["deployed"]})
	return out


func _summary_text(planet: Planet, mine: bool, ships: Array[Dictionary]) -> String:
	var data := _engine.data
	var lines := PackedStringArray()
	if planet.owner.is_empty():
		lines.append(UiKit.color_tag("Unclaimed: nothing is produced until you settle or develop a body here.", Palette.TEXT_DIM))
	else:
		lines.append("Yields %s per turn" % EmpirePanel._resource_text(_engine, EmpireRules.planet_yields(_engine, planet), true)
				+ ("   ·   population %d" % planet.population() if planet.population() > 0 else ""))
	for mp_id in planet.megaprojects:
		lines.append(UiKit.color_tag("Wonder: %s. %s" % [data.megaprojects[mp_id]["name"], data.megaprojects[mp_id].get("description", "")], Palette.ACTIVE))
	if not planet.owner.is_empty():
		var garrison := EmpireRules.garrison_units(_engine, planet).size()
		var platforms := EmpireRules.building_defense_units(_engine, planet).size()
		var parts := PackedStringArray()
		if garrison > 0:
			parts.append("%d orbital batter%s" % [garrison, "y" if garrison == 1 else "ies"])
		if platforms > 0:
			parts.append("%d defense platform%s" % [platforms, "" if platforms == 1 else "s"])
		if not parts.is_empty():
			lines.append(UiKit.color_tag("Defenses: " + ", ".join(parts) + (" (any attacker has to beat them)" if not mine else ""), Palette.BAD if not mine else Palette.TEXT_DIM))
	return "\n".join(lines)


# --- Cards ---------------------------------------------------------------------------

func _card(title: String, accent: Color = Palette.TEXT) -> VBoxContainer:
	var card := UiKit.panel(Color(0.08, 0.1, 0.16, 0.95))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)
	if not title.is_empty():
		box.add_child(UiKit.label(title, 15, accent))
	return box


## The finished card (the panel a card's content box sits in).
func _finish(box: VBoxContainer) -> Control:
	return box.get_parent()


func _text(box: Control, text: String, size: int = 13) -> RichTextLabel:
	var l := UiKit.rich_text(size)
	l.fit_content = true
	l.scroll_active = false
	l.append_text(text)
	box.add_child(l)
	return l


func _body_card(planet: Planet, b: Dictionary, ships: Array[Dictionary]) -> Control:
	var data := _engine.data
	var def: Dictionary = data.body_types.get(b["type"], {})
	var box := _card("")
	var surface := Color(def.get("surface", {}).get("accent", "#aaaaaa"))
	var known := _engine.known_traits(_viewer, planet, b)
	var text := "%s [b]%s[/b]   %s" % [UiKit.color_tag("●", surface), b["name"], UiKit.color_tag(def.get("name", b["type"]), Palette.TEXT_DIM)]
	_text(box, text, 16)
	if not _engine.is_surveyed(_viewer, planet):
		_text(box, UiKit.color_tag("Not surveyed: fly a ship to it (or next to it) to learn its traits and deposits.", Palette.TEXT_DIM), 12)
	elif not known.is_empty():
		var trait_lines := PackedStringArray()
		for t: String in known:
			trait_lines.append("%s: %s" % [UiKit.color_tag(data.planet_traits[t]["name"], Palette.ACTIVE), data.planet_traits[t].get("description", "")])
		_text(box, "\n".join(trait_lines), 12)
	_text(box, deposit_lines(_engine, _viewer, planet, b), 12)
	if EmpireRules.is_offline(_engine, b):
		_text(box, UiKit.color_tag("Raided: offline for %d more turn(s), no yields or extraction." % EmpireRules.offline_turns(_engine, b), Palette.BAD), 12)
	var built := PackedStringArray()
	for building_id: String in b["buildings"]:
		built.append(data.buildings[building_id]["name"])
	if built.is_empty():
		_text(box, UiKit.color_tag(def.get("description", ""), Palette.TEXT_DIM), 12)
	else:
		_text(box, "%s  ·  %s" % [", ".join(built), EmpirePanel._resource_text(_engine, EmpireRules.body_yields(_engine, b, planet.owner), true)])
	if "colony" in b["buildings"]:
		_text(box, _population_text(_engine, b, planet.owner) + UiKit.color_tag("\nColony slots %d/%d" % [
				b["buildings"].size() - 1, EmpireRules.colony_slots(_engine, b, planet.owner)], Palette.TEXT_DIM), 12)
	_body_actions(box, planet, b, ships)
	if planet.owner == _viewer and "colony" in b["buildings"]:
		var options := EmpireRules.build_options(_engine, planet).filter(
				func(o: Dictionary) -> bool: return o["kind"] == "building" and o["body"] == b["id"])
		if not options.is_empty():
			box.add_child(UiKit.label("Colony buildings (built by the colony)", 12, Palette.TEXT_DIM))
			box.add_child(_option_row(planet, options))
	return _finish(box)


## The orders your civilian ships can carry out on this body.
func _body_actions(box: VBoxContainer, planet: Planet, b: Dictionary, ships: Array[Dictionary]) -> void:
	var data := _engine.data
	var worker := SystemRules.job_on_body(planet, b["id"])
	var may_work := SystemRules.may_work_in(planet, _viewer)
	var any_actions := false
	if not worker.is_empty():
		var job: Dictionary = worker["job"]
		var line := "%s is building %s here: %d turn%s left" % [worker["name"], data.buildings[job["building"]]["name"],
				job["turns_left"], "" if int(job["turns_left"]) == 1 else "s"]
		_text(box, UiKit.color_tag(line, Palette.ACTIVE), 13)
		if worker["owner"] == _viewer:
			var cancel := UiKit.button("Cancel the job (half the cost back)", func() -> void:
				command_requested.emit(CivilianCommand.new(_viewer, planet.id, worker["uid"], CivilianCommand.CANCEL)))
			cancel.disabled = not _interactive
			box.add_child(cancel)
		return
	if ships.is_empty() or not may_work:
		if may_work and b["buildings"].is_empty() and planet.owner == _viewer:
			_text(box, UiKit.color_tag("Undeveloped. A Constructor builds here; a colony of 2+ population can build one.", Palette.TEXT_DIM), 12)
		return
	var colony := _pick("colony")
	if not colony.is_empty() and EmpireRules.is_habitable(_engine, b):
		var error := SystemRules.found_error(_engine, planet, b, _viewer)
		var btn := UiKit.button("%s: found a colony here  [F]" % colony["ship"]["name"], func() -> void: _found_colony(colony))
		btn.disabled = not _interactive or not error.is_empty()
		btn.tooltip_text = error if not error.is_empty() else "The ship is used up. The colony starts at 1 population%s." % (
				" and becomes your capital" if not planet.capital.is_empty() and planet.capital.get("faction", "") == _viewer else "")
		box.add_child(btn)
		any_actions = true
	var ctor := _pick("constructor")
	if not ctor.is_empty():
		var options := EmpireRules.constructor_options(_engine, _viewer, b)
		if not options.is_empty():
			box.add_child(UiKit.label("%s can build here" % ctor["ship"]["name"], 12, Palette.TEXT_DIM))
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			for o: Dictionary in options:
				var label := "%s  ·  %s, %dt" % [o["name"], EmpireRules.cost_text(_engine, o["cost"]), o["turns"]]
				var btn := UiKit.button(label, func() -> void:
					command_requested.emit(CivilianCommand.new(_viewer, planet.id, ctor["ship"]["uid"], CivilianCommand.JOB, b["id"], o["id"])))
				var tip: String = data.buildings[o["id"]].get("description", "")
				var taps := DepositRules.extraction(data, {"buildings": [o["id"]], "deposits": _engine.known_deposits(_viewer, planet, b)})
				for k: String in taps:
					tip += "\nHere it would extract %+d %s a turn." % [int(taps[k]), DepositRules.resource_name(data, k).to_lower()]
				if not taps.is_empty():
					btn.text = "%s  ·  +%s" % [label, ", ".join(taps.keys().map(func(k: String) -> String: return "%d %s" % [int(taps[k]), DepositRules.resource_name(data, k).to_lower()]))]
				if planet.owner.is_empty() and o["ok"]:
					tip += "\nFinishing it claims %s for you as an outpost." % planet.name
				btn.tooltip_text = tip + ("" if o["ok"] else "\n(%s)" % o["reason"])
				btn.disabled = not _interactive or not o["ok"]
				row.add_child(btn)
			box.add_child(row)
			any_actions = true
	if not any_actions and b["buildings"].is_empty():
		var hint := "Nothing your ships here can do on this body."
		if EmpireRules.is_habitable(_engine, b):
			hint = "Only a Colony Ship can settle this world."
		_text(box, UiKit.color_tag(hint, Palette.TEXT_DIM), 12)


## The ship to use for a role: the selected one if it fits, else the first idle one.
func _pick(role: String) -> Dictionary:
	var planet := _planet()
	var first: Dictionary = {}
	for e in SystemRules.ships_here(_engine, planet, _viewer):
		if e["role"] != role or not e["ship"].get("job", {}).is_empty():
			continue
		if e["ship"]["uid"] == _ship:
			return e
		if first.is_empty():
			first = e
	return first


func _found_colony(entry: Dictionary) -> void:
	command_requested.emit(CivilianCommand.new(_viewer, _planet_id, entry["ship"]["uid"], CivilianCommand.FOUND, _body))


func _ships_card(planet: Planet, ships: Array[Dictionary]) -> Control:
	var data := _engine.data
	var box := _card("Ships here" if _engine.is_system_scale() else "Ships in the system", Palette.TEXT)
	if ships.is_empty():
		_text(box, UiKit.color_tag("No civilian ships here. A colony of 2+ population builds Colony Ships; any colony builds Constructors (see Production).", Palette.TEXT_DIM), 12)
	for e in ships:
		var s: Dictionary = e["ship"]
		var job: Dictionary = s.get("job", {})
		var status := "in orbit"
		if not job.is_empty():
			status = "building %s at %s, %d turn%s left" % [data.buildings[job["building"]]["name"], planet.body(job["body"]).get("name", "?"),
					job["turns_left"], "" if int(job["turns_left"]) == 1 else "s"]
		elif e["deployed"] and not s.get("loc", "").is_empty():
			status = "idle at %s" % planet.body(s["loc"]).get("name", "?")
		elif e["deployed"]:
			status = "idle in the system"
		var role_name: String = data.units[s["unit"]]["name"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var select := UiKit.button("%s%s" % ["> " if s["uid"] == _ship else "", s["name"]], func() -> void: _select_ship(s["uid"]))
		select.tooltip_text = "Select (its orders show on the bodies)"
		row.add_child(select)
		var info := UiKit.rich_text(12)
		info.fit_content = true
		info.scroll_active = false
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.append_text("%s\n%s" % [role_name, UiKit.color_tag(status, Palette.ACTIVE if not job.is_empty() else Palette.TEXT_DIM)])
		row.add_child(info)
		if e["deployed"] and job.is_empty():
			var depart := UiKit.button("Depart", func() -> void:
				command_requested.emit(CivilianCommand.new(_viewer, planet.id, s["uid"], CivilianCommand.DEPART)))
			depart.tooltip_text = "Leave the system: joins the fleet in orbit or forms a new fleet to fly on the galaxy map"
			depart.disabled = not _interactive or SystemRules.command_error(_engine, CivilianCommand.new(_viewer, planet.id, s["uid"], CivilianCommand.DEPART)) != ""
			row.add_child(depart)
			if e["role"] in ["colony", "constructor"]:
				var uid: String = s["uid"]
				var send := UiKit.button("Send to...", func() -> void: send_ship_requested.emit(uid))
				send.tooltip_text = "Click a world on the map: the ship flies there on its own and gets to work"
				send.disabled = not _interactive
				row.add_child(send)
		box.add_child(row)
	return _finish(box)


func _production_card(planet: Planet) -> Control:
	var data := _engine.data
	var box := _card("Production", Palette.TEXT)
	if not planet.queue.is_empty():
		var text := "Building %s (%d/%d turns)" % [_queue_name(data, planet), planet.queue["progress"], planet.queue["turns"]]
		if planet.is_blockaded():
			text += "  -  PAUSED by the blockade"
		_text(box, UiKit.color_tag(text, Palette.BAD if planet.is_blockaded() else Palette.ACTIVE), 13)
	var options := EmpireRules.build_options(_engine, planet)
	var groups := [["Civilian ships", options.filter(func(o: Dictionary) -> bool: return o["kind"] == "unit" and Fleet.is_civilian_unit(data, o["id"]))],
			["Warships", options.filter(func(o: Dictionary) -> bool: return o["kind"] == "unit" and not Fleet.is_civilian_unit(data, o["id"]))],
			["Megaprojects", options.filter(func(o: Dictionary) -> bool: return o["kind"] == "megaproject")]]
	for g: Array in groups:
		if g[1].is_empty():
			continue
		box.add_child(UiKit.label(g[0], 12, Palette.TEXT_DIM))
		box.add_child(_option_row(planet, g[1]))
	if EmpireRules.has_shipyard(_engine, planet) == false and planet.colonies().size() > 0:
		_text(box, UiKit.color_tag("Warships need a shipyard (built on a colony).", Palette.TEXT_DIM), 12)
	return _finish(box)


func _option_row(planet: Planet, options: Array) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	for o: Dictionary in options:
		var label := "%s  ·  %s, %dt" % [o["name"], EmpireRules.cost_text(_engine, o["cost"]), o["turns"]]
		# Warships say what they are for: "Bomber (strike craft, vs capital ships) · ...".
		var role := RoleRules.hint(_engine.data, _engine.data.units.get(o["id"], {})) if o["kind"] == "unit" else ""
		if not role.is_empty() and RoleRules.class_of(_engine.data.units[o["id"]]) != "civilian":
			label = "%s (%s)  ·  %s, %dt" % [o["name"], role, EmpireRules.cost_text(_engine, o["cost"]), o["turns"]]
		var b := UiKit.button(label, func() -> void:
			command_requested.emit(QueueBuildCommand.new(planet.owner, planet.id, o["kind"], o["id"], o["body"])))
		var desc := ""
		match o["kind"]:
			"building":
				desc = _engine.data.buildings[o["id"]].get("description", "")
			"megaproject":
				desc = _engine.data.megaprojects[o["id"]].get("description", "")
			_:
				desc = _engine.data.units[o["id"]].get("description", "")
				var summary := RoleRules.summary(_engine.data, _engine.data.units[o["id"]])
				if not summary.is_empty() and RoleRules.class_of(_engine.data.units[o["id"]]) != "civilian":
					desc = "%s: %s\n%s" % [RoleRules.profile(_engine.data, _engine.data.units[o["id"]])["name"], summary, desc]
				var pop_cost := int(_engine.data.units[o["id"]].get("strategic", {}).get("pop_cost", 0))
				if pop_cost > 0:
					desc += "\nCosts %d population." % pop_cost
		b.tooltip_text = desc + ("" if o["ok"] else "\n(%s)" % o["reason"])
		b.disabled = not _interactive or not o["ok"]
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


## A deposit as a short tag: a diamond in the resource's colour, its name and richness pips
## ("◆ Rare Elements ●●○").
static func deposit_tag(data: DataRegistry, resource: String, richness: int) -> String:
	var pips := "●".repeat(richness) + "○".repeat(maxi(3 - richness, 0))
	return UiKit.color_tag("◆ %s %s" % [DepositRules.resource_name(data, resource), pips], DepositRules.color(data, resource))


## A body's deposits as the viewer knows them, one line each, with what taps them (or would):
## "Deposits: ?" until surveyed.
static func deposit_lines(engine: GalaxyEngine, viewer: String, planet: Planet, b: Dictionary) -> String:
	var data := engine.data
	if not engine.is_surveyed(viewer, planet):
		return UiKit.color_tag("Deposits: ?", Palette.TEXT_DIM)
	var deposits := engine.known_deposits(viewer, planet, b)
	if deposits.is_empty():
		return UiKit.color_tag("No strategic deposits.", Palette.TEXT_DIM)
	var lines := PackedStringArray()
	var extraction := DepositRules.extraction(data, b)
	for k: String in deposits:
		var richness := int(deposits[k])
		var line := "%s  %s" % [deposit_tag(data, k, richness), UiKit.color_tag("(%s)" % DepositRules.richness_word(richness), Palette.TEXT_DIM)]
		if extraction.has(k):
			var by: Array = b["buildings"].filter(func(x: String) -> bool: return k in data.buildings[x].get("extracts", []))
			line += "  tapped by %s: %s" % [data.buildings[by[0]]["name"], UiKit.color_tag("%+d a turn" % int(extraction[k]), Palette.GOOD)]
			if planet.is_blockaded():
				line += UiKit.color_tag(" (halted by the blockade)", Palette.BAD)
		else:
			var names := PackedStringArray()
			for id in DepositRules.extractors_for(engine, b, k):
				var req: String = data.buildings[id].get("requires_tech", "")
				var locked := not req.is_empty() and req not in engine.state.known_techs(viewer)
				names.append(data.buildings[id]["name"] + (" (needs %s)" % data.techs[req]["name"] if locked else ""))
			line += UiKit.color_tag("  untapped%s" % ((": " + " or ".join(names) + " would extract %d a turn" % richness) if not names.is_empty() else ""), Palette.TEXT_DIM)
		lines.append(line)
	return "\n".join(lines)


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
