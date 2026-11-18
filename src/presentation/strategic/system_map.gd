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
const BODY_SCALE := 1.45
const BODY_PICK_MIN := 24.0

## Per body id: {"name": String, "info": String, "color": Color}: the label under the body.
var labels: Dictionary = {}
## Ships to draw: [{"uid", "body": body id or "" (in orbit), "role", "name", "progress": -1 idle .. 1 done,
## "color": Color, "selected": bool}].
var markers: Array[Dictionary] = []
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


func _process(_delta: float) -> void:
	if is_visible_in_tree():
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
	_scene_root = Node3D.new()
	_viewport.add_child(_scene_root)
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


# --- Geometry -------------------------------------------------------------------

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
	var world_radius := Planet3D._body_radius(b, _data) * SYSTEM_SCALE * BODY_SCALE
	if b["type"] == "asteroid_belt":
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
			var y := pos.y + r + 20.0
			_text(c, font, name_text, Vector2(pos.x, y), 14, Palette.ACTIVE if id == selected_body else Palette.TEXT)
			if not info_text.is_empty():
				_text(c, font, info_text, Vector2(pos.x, y + 16.0), 12, col)
		# Ships stack up beside the body.
		for m in markers:
			if m["body"] != id:
				continue
			var k: int = int(counts.get(id, 0))
			counts[id] = k + 1
			_ship_icon(c, font, m, pos + Vector2(r + 16.0 + k * 22.0, -r * 0.5 - 6.0))
	# Ships waiting in orbit (still in their fleet, or deployed but not sent anywhere).
	var orbit := Vector2(34.0, c.size.y - 38.0)
	var orbiting := markers.filter(func(m: Dictionary) -> bool: return m["body"] == "")
	if not orbiting.is_empty():
		_text(c, font, "In orbit", Vector2(orbit.x + 8.0, orbit.y - 26.0), 12, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		for i in orbiting.size():
			_ship_icon(c, font, orbiting[i], orbit + Vector2(i * 24.0, 0.0))
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
func _ship_icon(c: Control, font: Font, m: Dictionary, at: Vector2) -> void:
	var role: String = m["role"]
	var col: Color = m["color"]
	var fill := Color(0.55, 0.9, 0.6) if role == "colony" else Color(1.0, 0.8, 0.35)
	var outline := Color(0.02, 0.04, 0.08)
	var points := PackedVector2Array()
	if role == "colony":
		for k in 6:
			points.append(at + Vector2(cos(k * TAU / 6.0 + PI / 6.0), sin(k * TAU / 6.0 + PI / 6.0)) * 9.0)
	else:
		points = PackedVector2Array([at + Vector2(0, -10), at + Vector2(9, 0), at + Vector2(0, 10), at + Vector2(-9, 0)])
	c.draw_circle(at, 13.0, Color(0, 0, 0, 0.5))
	c.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	c.draw_polyline(closed, outline, 1.5, true)
	c.draw_circle(at, 3.0, col)
	var progress: float = m.get("progress", -1.0)
	if progress >= 0.0:
		c.draw_arc(at, 15.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(progress, 0.02, 1.0), 24, Color(1, 0.85, 0.3), 3.0, true)
	if m.get("selected", false):
		c.draw_arc(at, 17.0, 0.0, TAU, 28, Palette.ACTIVE, 2.0, true)
	elif m["uid"] == _hover_ship:
		c.draw_arc(at, 17.0, 0.0, TAU, 28, Color(1, 1, 1, 0.6), 1.5, true)
		_text(c, font, m["name"], at + Vector2(0, -22.0), 12, Palette.TEXT)
	_ship_rects[m["uid"]] = Rect2(at - Vector2(13, 13), Vector2(26, 26))


class _Overlay:
	extends Control
	var map: SystemMap

	func _draw() -> void:
		if map != null:
			map._draw_overlay(self)
