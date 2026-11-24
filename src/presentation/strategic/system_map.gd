class_name SystemMap
extends Control
## The system map: a big 3D view of one star system (Planet3D, scaled up) whose
## bodies can be clicked, with a 2D layer on top for names, a selection ring and
## the civilian ships (colony ships, constructors) shown next to the bodies they
## sit at or work on. Read-only: it emits what was clicked and SystemView decides.

signal body_clicked(body_id: String)
signal ship_clicked(ship_uid: String)

const SYSTEM_SCALE := 2.4
## The bodies are drawn bigger than on the galaxy map so they read at a glance.
const BODY_SCALE := 1.15
const BODY_PICK_MIN := 24.0
## The sun is kept small here: the worlds are what matters on this screen.
const STAR_SCALE := 0.45
## Where the system's jump gate stands (world space), and how big ships are drawn.
const GATE_POS := Vector3(-1.62, 0.5, 0.3)
const SHIP_SIZE := 0.16
const SHIP_SPEED := 1.1  # world units per second
## A single body (system-scale maps) is drawn this much bigger than on the map.
const BODY_VIEW_SCALE := 1.35

## Per body id: {"name": String, "info": String, "color": Color}: the label under the body.
var labels: Dictionary = {}
## Ships to draw: [{"uid", "body": body id or "" (in orbit), "role", "name", "progress": -1 idle .. 1 done,
## "color": Color, "selected": bool, "unit", "style", "deployed": false = aboard a fleet in orbit}].
## Deployed ships fly between the bodies (or wait by the jump gate); ships aboard a fleet are
## outside the gate (they fly out through it when they leave, and in through it when deployed).
var markers: Array[Dictionary] = []:
	set(v):
		markers = v
		_sync_ships()
## Big text over the map (e.g. a blockade), "" for none.
var banner := ""
var banner_color := Color(1, 0.4, 0.35)
var selected_body := ""

var _viewport: SubViewport
var _container: SubViewportContainer
var _overlay: Control
var _scene_root: Node3D
var _camera: Camera3D
var _system: Planet3D
var _planet_id := ""
var _bodies: Array[Dictionary] = []
var _data: DataRegistry
var _hover_body := ""
var _hover_ship := ""
## Where each ship marker was drawn last frame (uid -> rect), for picking.
var _ship_rects: Dictionary = {}
## uid -> {"node": Node3D, "trail": CPUParticles3D, "leaving": bool, "t": float}: the 3D ships.
var _ships: Dictionary = {}
var _gate: Node3D
## True right after a scene is built: ships already working somewhere appear there at once
## (only ships that show up later fly in through the gate).
var _fresh_scene := false
## A single body of a system-scale map (Body3D, close up) rather than a whole star system.
var _single := false


func _init() -> void:
	custom_minimum_size = Vector2(520, 360)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchor(_container, 0, 0, 1, 1, 0, 0, 0, 0)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_container.add_child(_viewport)
	_overlay = _Overlay.new()
	_overlay.map = self
	UiKit.anchor(_overlay, 0, 0, 1, 1, 0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_gui_input)
	add_child(_overlay)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_move_ships(delta)
		_overlay.queue_redraw()


## (Re)builds the 3D scene when the system changes, and updates it from the state.
func show_planet(planet: Planet, engine: GalaxyEngine) -> void:
	_data = engine.data
	_bodies = planet.bodies.duplicate()
	if _planet_id != planet.id or _system == null:
		_planet_id = planet.id
		_build_scene(planet, engine)
	_system.refresh(planet, engine.state)


func _build_scene(planet: Planet, engine: GalaxyEngine) -> void:
	if _scene_root != null:
		_scene_root.queue_free()
	_ships.clear()
	_scene_root = Node3D.new()
	_viewport.add_child(_scene_root)
	_single = engine.is_system_scale() and planet.bodies.size() == 1
	if _single:
		_build_body_scene(planet, engine)
		return
	if BoardGeometry.high_quality():
		_build_hq_scene(planet, engine)
		return
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.33, 0.5)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	# Close up the star would bloom into a white disc: glow only the hottest parts.
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	_scene_root.add_child(env_node)
	BoardGeometry.space_scenery(_scene_root, Vector3.ZERO, Vector2(1.0, 1.0), absi(hash(planet.id)), true)
	_system = Planet3D.new()
	_scene_root.add_child(_system)
	_system.setup(planet, engine.data)
	_system.scale = Vector3.ONE * SYSTEM_SCALE
	_system.show_floor(false)
	var nodes: Array = _system.get("_body_nodes")
	for i in mini(nodes.size(), planet.bodies.size()):
		if planet.bodies[i]["type"] != "asteroid_belt":
			(nodes[i] as Node3D).scale = Vector3.ONE * BODY_SCALE
	_camera = Camera3D.new()
	_camera.fov = 34
	_scene_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 3.4, 3.4), Vector3(0, 0.2, -0.45), Vector3.UP)
	_after_scene()


## Forward+ look: a real sky, the star blazing with bloom and lighting its worlds
## (a strong point light with shadows), so each body has a lit day side.
func _build_hq_scene(planet: Planet, engine: GalaxyEngine) -> void:
	BoardGeometry.build_environment(_scene_root, true, "system")
	_system = Planet3D.new()
	_scene_root.add_child(_system)
	_system.setup(planet, engine.data)
	_system.scale = Vector3.ONE * SYSTEM_SCALE
	_system.show_floor(false)
	var nodes: Array = _system.get("_body_nodes")
	for i in mini(nodes.size(), planet.bodies.size()):
		if planet.bodies[i]["type"] != "asteroid_belt":
			(nodes[i] as Node3D).scale = Vector3.ONE * BODY_SCALE
	var star_def: Dictionary = engine.data.star_types.get(planet.star, {})
	var light := OmniLight3D.new()
	light.light_color = Color(star_def.get("color", "#ffd88a")).lerp(Color.WHITE, 0.35)
	light.light_energy = 4.0
	light.omni_range = 9.0
	light.omni_attenuation = 0.8
	light.shadow_enabled = true
	light.position = Vector3(0, 0.32 * SYSTEM_SCALE, 0)
	_scene_root.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 34
	_scene_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 3.4, 3.4), Vector3(0, 0.2, -0.45), Vector3.UP)
	_after_scene()


## One body of a system-scale map, close up: the world (Body3D) fills the view, lit from the side
## its sun lies on (the sun itself is far off-screen), with its moons' and neighbours' light left
## to the imagination. Ships hold station round it; new ones arrive from deep space on the left.
func _build_body_scene(planet: Planet, engine: GalaxyEngine) -> void:
	var hq := BoardGeometry.high_quality()
	var star_def: Dictionary = engine.data.star_types.get(planet.star, {})
	var star_color := Color(star_def.get("color", "#ffd88a"))
	# Where the sun lies, seen from this body (map pixel space: x right, y down = world x, z).
	var to_star := Vector3(-1, 0, -0.3)
	var system: Dictionary = engine.campaign.get("system", {})
	if system.has("at"):
		var grid := engine.state.grid
		var star_cell := grid.cell_from_layout(Vector2i(int(system["at"][0]), int(system["at"][1])))
		var d := grid.to_pixel(star_cell, 1.0) - grid.to_pixel(planet.cell, 1.0)
		if d.length() > 0.01:
			to_star = Vector3(d.x, 0, d.y).normalized()
	to_star = (to_star + Vector3(0, 0.45, 0)).normalized()
	if hq:
		BoardGeometry.build_environment(_scene_root, true, "system")
	else:
		var env_node := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.008, 0.012, 0.03)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.28, 0.33, 0.5)
		env.ambient_light_energy = 0.35
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_hdr_threshold = 1.3
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env_node.environment = env
		_scene_root.add_child(env_node)
		BoardGeometry.space_scenery(_scene_root, Vector3.ZERO, Vector2(1.0, 1.0), absi(hash(planet.id)), true)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color.WHITE.lerp(star_color, 0.4)
	sun.light_energy = 2.2 if hq else 1.5
	sun.shadow_enabled = hq
	_scene_root.add_child(sun)
	sun.look_at_from_position(to_star * 10.0, Vector3.ZERO, Vector3.UP)
	var body := Body3D.new()
	_system = body
	_scene_root.add_child(body)
	body.setup(planet, engine.data)
	body.show_floor(false)
	body.scale = Vector3.ONE * BODY_VIEW_SCALE
	body.position = Vector3(0, -Body3D.LIFT * BODY_VIEW_SCALE, 0)
	body.set_light_dir(to_star)
	# A distant glint of the sun on the far side of the sky.
	var glint := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.12
	gs.height = 0.24
	glint.mesh = gs
	glint.material_override = BoardGeometry.additive_material(star_color * 1.4)
	glint.position = to_star * 9.0
	_scene_root.add_child(glint)
	_camera = Camera3D.new()
	_camera.fov = 34
	_scene_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 1.9, 3.4), Vector3(0.15, 0.1, 0), Vector3.UP)
	_after_scene()


## Shared by both looks: a small sun, the jump gate, and the ships placed at once.
func _after_scene() -> void:
	_system.set_star_scale(STAR_SCALE)
	if not _single:
		_gate = _build_gate()
		_scene_root.add_child(_gate)
	else:
		_gate = null
	_fresh_scene = true
	_sync_ships()
	_fresh_scene = false


## The system's jump gate (JumpGate3D): ships come in and leave the system through it.
func _build_gate() -> Node3D:
	var gate := JumpGate3D.build(false)
	gate.position = GATE_POS
	gate.look_at_from_position(GATE_POS, Vector3(0, 0.4, 0), Vector3.UP)
	return gate


## Matches the 3D ships to the markers: new ones fly in through the gate (or appear at
## once when the screen opens), gone ones fly out through it.
func _sync_ships() -> void:
	if _scene_root == null or _data == null:
		return
	var present := {}
	for m in markers:
		if not m.get("deployed", true):
			continue
		var uid: String = m["uid"]
		present[uid] = true
		if _ships.has(uid):
			_ships[uid]["leaving"] = false
			continue
		var unit_id: String = m.get("unit", "")
		var model_id := "constructor"
		if _data.units.has(unit_id):
			model_id = Unit3D.model_id_for(_data, _data.units[unit_id], m.get("style", ""))
		var node := Node3D.new()
		var body := ModelFactory.build(_data, model_id, m.get("color", Color.WHITE), m.get("style", ""), true)
		var box := ModelFactory.bounds(body)
		body.scale = Vector3.ONE * SHIP_SIZE / maxf(box.size.x, 0.2)
		node.add_child(body)
		var trail := BoardGeometry.engine_trail(m.get("color", Color.WHITE), 0.12)
		node.add_child(trail)
		_scene_root.add_child(node)
		var entry := {"node": node, "trail": trail, "leaving": false, "t": randf() * TAU, "gone": 0.0}
		_ships[uid] = entry
		if _fresh_scene:
			node.position = _target_for(m, uid)
		else:
			# Arrives: out of the gate's far side, through the ring.
			node.position = GATE_POS + (GATE_POS - Vector3(0, 0.4, 0)).normalized() * 0.5
	for uid: String in _ships.keys():
		if not present.has(uid):
			_ships[uid]["leaving"] = true


## Where a ship should be: beside the body it is at or works on, or waiting by the gate.
func _target_for(m: Dictionary, uid: String) -> Vector3:
	var body_id: String = m.get("body", "")
	var slot := 0
	for other in markers:
		if other["uid"] == uid:
			break
		if other.get("body", "") == body_id:
			slot += 1
	if body_id.is_empty():
		# Parked in a little line beside the gate, on the system side.
		var inward := (Vector3(0, 0.4, 0) - GATE_POS).normalized()
		var side := inward.cross(Vector3.UP).normalized()
		return GATE_POS + inward * 0.38 + side * (slot - 0.5) * 0.18 + Vector3(0, -0.05, 0)
	var nodes: Array = _system.get("_body_nodes")
	for i in mini(_bodies.size(), nodes.size()):
		if _bodies[i]["id"] == body_id:
			var n: Node3D = nodes[i]
			var r := _world_radius(_bodies[i])
			if _bodies[i]["type"] == "asteroid_belt" and not _single:
				var a := body_anchor(body_id)
				var inner: Node3D = _system.get("_system")
				var ring := 0.0
				for o: Dictionary in _system.get("_orbiters"):
					if o["node"] == n:
						ring = float(o.get("ring", 0.0))
				return inner.global_transform * Vector3(0.0, 0.0, ring) + Vector3(0.12 + slot * 0.14, 0.1, 0.0)
			# Hold station above and beside the world, a little apart per ship.
			var ang := 0.6 + slot * 1.1
			return n.global_position + Vector3(cos(ang) * (r + 0.14), 0.08 + r * 0.4, sin(ang) * (r + 0.14))
	return GATE_POS


func _move_ships(delta: float) -> void:
	for uid: String in _ships.keys():
		var e: Dictionary = _ships[uid]
		var node: Node3D = e["node"]
		var target: Vector3
		if e["leaving"]:
			# Out through the gate: to its centre, then on through and away.
			var through := GATE_POS + (GATE_POS - Vector3(0, 0.4, 0)).normalized() * 0.6
			target = GATE_POS if node.position.distance_to(GATE_POS) > 0.06 and float(e["gone"]) == 0.0 else through
			if node.position.distance_to(GATE_POS) <= 0.06:
				e["gone"] = 0.01
				_gate_flash()
			if float(e["gone"]) > 0.0:
				e["gone"] = float(e["gone"]) + delta
				node.scale = Vector3.ONE * maxf(1.0 - float(e["gone"]) * 2.0, 0.01)
				if float(e["gone"]) > 0.5:
					node.queue_free()
					_ships.erase(uid)
					continue
		else:
			var m: Dictionary = {}
			for mm in markers:
				if mm["uid"] == uid:
					m = mm
			target = _target_for(m, uid)
		e["t"] = float(e["t"]) + delta
		var to := target - node.position
		var dist := to.length()
		var moving := dist > 0.03
		(e["trail"] as CPUParticles3D).emitting = moving
		if moving:
			var step := minf(dist, SHIP_SPEED * delta * clampf(dist * 3.0, 0.35, 1.0))
			node.position += to / dist * step
			var heading := atan2(to.z, to.x)
			node.rotation.y = lerp_angle(node.rotation.y, -heading, clampf(delta * 6.0, 0.0, 1.0))
		else:
			# On station: drift and bob gently.
			node.position += Vector3(0, sin(float(e["t"]) * 1.7) * 0.0006, 0)
			node.rotation.y += delta * 0.15


func _gate_flash() -> void:
	if _gate == null:
		return
	var field: MeshInstance3D = _gate.get_node_or_null("Field")
	if field == null:
		return
	var mat := field.material_override as StandardMaterial3D
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", Color(0.7, 0.95, 1.0), 0.08)
	tw.tween_property(mat, "albedo_color", Color(0.06, 0.2, 0.32), 0.5)


## Screen position of a 3D ship (for its icon), or null.
func ship_screen_pos(uid: String) -> Variant:
	if not _ships.has(uid) or _camera == null:
		return null
	var node: Node3D = _ships[uid]["node"]
	if _camera.is_position_behind(node.global_position):
		return null
	return _camera.unproject_position(node.global_position)


# --- Geometry -------------------------------------------------------------------

## A body's drawn radius in this view's world units.
func _world_radius(b: Dictionary) -> float:
	if _single:
		return Body3D.body_radius(b, _data) * BODY_VIEW_SCALE
	return Planet3D._body_radius(b, _data) * SYSTEM_SCALE * BODY_SCALE


## Screen position (in this control) and radius of a body, or {} when it can't be placed.
func body_anchor(body_id: String) -> Dictionary:
	if _system == null or _camera == null:
		return {}
	var index := -1
	for i in _bodies.size():
		if _bodies[i]["id"] == body_id:
			index = i
	var nodes: Array = _system.get("_body_nodes")
	if index < 0 or index >= nodes.size():
		return {}
	var node: Node3D = nodes[index]
	var b: Dictionary = _bodies[index]
	var world := node.global_position
	var world_radius := _world_radius(b)
	if b["type"] == "asteroid_belt" and not _single:
		# The belt is a ring: anchor on a fixed point of it.
		var ring := 0.0
		for o: Dictionary in _system.get("_orbiters"):
			if o["node"] == node:
				ring = float(o.get("ring", 0.0))
		var inner: Node3D = _system.get("_system")
		world = inner.global_transform * Vector3(0.0, 0.0, ring)
		world_radius = 0.09 * SYSTEM_SCALE
	if _camera.is_position_behind(world):
		return {}
	var p := _camera.unproject_position(world)
	var edge := _camera.unproject_position(world + _camera.global_transform.basis.x * world_radius)
	return {"pos": p, "radius": maxf(p.distance_to(edge), 7.0)}


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_ship = _ship_at(event.position)
		_hover_body = "" if not _hover_ship.is_empty() else _body_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ship := _ship_at(event.position)
		if not ship.is_empty():
			ship_clicked.emit(ship)
			return
		var body := _body_at(event.position)
		if not body.is_empty():
			body_clicked.emit(body)


func _body_at(pos: Vector2) -> String:
	var best := ""
	var best_d := 1.0e9
	for b in _bodies:
		var a := body_anchor(b["id"])
		if a.is_empty():
			continue
		var d := pos.distance_to(a["pos"])
		if d <= maxf(float(a["radius"]) + 8.0, BODY_PICK_MIN) and d < best_d:
			best_d = d
			best = b["id"]
	return best


func _ship_at(pos: Vector2) -> String:
	for uid: String in _ship_rects:
		if (_ship_rects[uid] as Rect2).grow(3.0).has_point(pos):
			return uid
	return ""


# --- Overlay drawing ------------------------------------------------------------

func _draw_overlay(c: Control) -> void:
	var font := c.get_theme_default_font()
	_ship_rects.clear()
	var counts := {}
	for b in _bodies:
		var id: String = b["id"]
		var a := body_anchor(id)
		if a.is_empty():
			continue
		var pos: Vector2 = a["pos"]
		var r: float = a["radius"]
		if id == selected_body:
			c.draw_arc(pos, r + 9.0, 0.0, TAU, 40, Palette.ACTIVE, 2.5, true)
			for k in 4:
				var ang := k * PI / 2.0 + 0.4
				c.draw_line(pos + Vector2(cos(ang), sin(ang)) * (r + 5.0), pos + Vector2(cos(ang), sin(ang)) * (r + 15.0), Palette.ACTIVE, 2.5, true)
		elif id == _hover_body:
			c.draw_arc(pos, r + 8.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 1.5, true)
		var label: Dictionary = labels.get(id, {})
		if not label.is_empty():
			var name_text: String = label.get("name", "")
			var info_text: String = label.get("info", "")
			var col: Color = label.get("color", Palette.TEXT)
			var y := minf(pos.y + r + 20.0, c.size.y - 40.0)
			_text(c, font, name_text, Vector2(pos.x, y), 14, Palette.ACTIVE if id == selected_body else Palette.TEXT)
			if not info_text.is_empty():
				_text(c, font, info_text, Vector2(pos.x, y + 16.0), 12, col)
	# Each ship's icon floats over its 3D model (selection, progress, picking).
	for m in markers:
		var at: Variant = ship_screen_pos(m["uid"])
		if at != null:
			_ship_icon(c, font, m, (at as Vector2) + Vector2(0, -20.0), 0.7)
	if _gate != null and _camera != null and not _camera.is_position_behind(_gate.global_position):
		var gp := _camera.unproject_position(_gate.global_position)
		_text(c, font, "Jump gate", gp + Vector2(0, 40.0), 12, Color(0.5, 0.85, 1.0))
		var outside := markers.filter(func(m: Dictionary) -> bool: return not m.get("deployed", true))
		if not outside.is_empty():
			_text(c, font, "%d with the fleet outside" % outside.size(), gp + Vector2(0, 56.0), 11, Palette.TEXT_DIM)
	if not banner.is_empty():
		var w := font.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		c.draw_rect(Rect2(Vector2((c.size.x - w) / 2.0 - 14.0, 10.0), Vector2(w + 28.0, 34.0)), Color(0.12, 0.02, 0.02, 0.8))
		_text(c, font, banner, Vector2(c.size.x / 2.0, 34.0), 20, banner_color)


func _text(c: Control, font: Font, text: String, at: Vector2, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := font.get_string_size(text, align, -1, size).x
	var x := at.x - w / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else at.x
	c.draw_string(font, Vector2(x + 1.0, at.y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	c.draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A small icon for a civilian ship: a hexagon for colony ships, a tool diamond for constructors,
## with an arc around it while it works, a ring when selected.
func _ship_icon(c: Control, font: Font, m: Dictionary, at: Vector2, k: float = 1.0) -> void:
	var role: String = m["role"]
	var col: Color = m["color"]
	var fill := Color(0.55, 0.9, 0.6) if role == "colony" else Color(1.0, 0.8, 0.35)
	var outline := Color(0.02, 0.04, 0.08)
	var points := PackedVector2Array()
	if role == "colony":
		for i in 6:
			points.append(at + Vector2(cos(i * TAU / 6.0 + PI / 6.0), sin(i * TAU / 6.0 + PI / 6.0)) * 9.0 * k)
	else:
		points = PackedVector2Array([at + Vector2(0, -10) * k, at + Vector2(9, 0) * k, at + Vector2(0, 10) * k, at + Vector2(-9, 0) * k])
	c.draw_circle(at, 13.0 * k, Color(0, 0, 0, 0.5))
	c.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	c.draw_polyline(closed, outline, 1.5, true)
	c.draw_circle(at, 3.0 * k, col)
	var progress: float = m.get("progress", -1.0)
	if progress >= 0.0:
		c.draw_arc(at, 15.0 * k, -PI / 2.0, -PI / 2.0 + TAU * clampf(progress, 0.02, 1.0), 24, Color(1, 0.85, 0.3), 3.0, true)
	if m.get("selected", false):
		c.draw_arc(at, 17.0 * k, 0.0, TAU, 28, Palette.ACTIVE, 2.0, true)
	elif m["uid"] == _hover_ship:
		c.draw_arc(at, 17.0 * k, 0.0, TAU, 28, Color(1, 1, 1, 0.6), 1.5, true)
	if m.get("selected", false) or m["uid"] == _hover_ship:
		_text(c, font, m["name"], at + Vector2(0, -22.0 * k - 4.0), 12, Palette.TEXT)
	_ship_rects[m["uid"]] = Rect2(at - Vector2(13, 13) * maxf(k, 0.85), Vector2(26, 26) * maxf(k, 0.85))


class _Overlay:
	extends Control
	var map: SystemMap

	func _draw() -> void:
		if map != null:
			map._draw_overlay(self)
