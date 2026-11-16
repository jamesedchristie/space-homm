class_name DeckKit
extends RefCounted
## Dresses a square-grid station interior for the 3D battle board: paneled
## deck plates with grates and floor lights, bulkhead walls with ribs, trim,
## pipes and light strips on the faces you can see, framed sliding doors with
## hazard stripes, cargo containers and barrels, and a few cool room lights.
## Everything is seeded per cell, so a map always looks the same.

const WALL_H := 0.95
const DECK_H := 0.06
const HALF := 0.9          # half a square cell in world units
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _board: BattleBoard3D
var _grid: TacticalGrid
var _plate := SurfaceTool.new()
var _metal := SurfaceTool.new()
var _dark := SurfaceTool.new()
var _cyan := SurfaceTool.new()
var _amber := SurfaceTool.new()
var _hazard := SurfaceTool.new()


static func build(board: BattleBoard3D, parent: Node3D) -> void:
	var kit := DeckKit.new()
	kit._board = board
	kit._parent = parent
	kit._grid = board.engine.state.grid
	for st: SurfaceTool in [kit._plate, kit._metal, kit._dark, kit._cyan, kit._amber, kit._hazard]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var open_cells: Array[Vector2i] = []
	for c in kit._grid.cells():
		match kit._deco(c):
			"bulkhead":
				kit._wall(c)
			"hazard":
				kit._floor(c)
				kit._door(c)
			"crates":
				kit._floor(c)
				kit._cargo(c)
			_:
				kit._floor(c)
				open_cells.append(c)
	kit._commit(parent)
	kit._room_lights(parent, open_cells)


func _deco(c: Vector2i) -> String:
	return _grid.terrain_def(c).get("decoration", "") if _grid.has_cell(c) else "bulkhead"


func _is_wall(c: Vector2i) -> bool:
	return not _grid.has_cell(c) or _deco(c) == "bulkhead"


func _rng(c: Vector2i, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(c) + salt * 7919
	return r


func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	BoardGeometry.box(st, center, size, color)


# --- Floor ----------------------------------------------------------------------

func _floor(c: Vector2i) -> void:
	var o := _board.world(c)
	var r := _rng(c)
	var tone := r.randf_range(-0.02, 0.02)
	var base := Color(0.13 + tone, 0.15 + tone, 0.19 + tone)
	# Sub-plating under the panels.
	_box(_dark, o + Vector3(0, 0.01, 0), Vector3(HALF * 2.0, 0.02, HALF * 2.0), Color(0.05, 0.06, 0.08))
	if r.randf() < 0.09:
		# A grate: dark slats over a faintly lit pit.
		for i in 6:
			var z := -HALF * 0.8 + i * HALF * 0.32
			_box(_metal, o + Vector3(0, DECK_H - 0.01, z), Vector3(HALF * 1.7, 0.03, 0.08), Color(0.1, 0.11, 0.13))
		_box(_cyan, o + Vector3(0, 0.025, 0), Vector3(HALF * 1.4, 0.005, HALF * 1.4), Color(0.06, 0.22, 0.3))
	else:
		# Four panels with seams between them.
		for qx in [-1.0, 1.0]:
			for qz in [-1.0, 1.0]:
				var shade := base.lightened(r.randf_range(0.0, 0.06))
				_box(_plate, o + Vector3(qx * HALF * 0.5, DECK_H / 2.0, qz * HALF * 0.5),
						Vector3(HALF * 0.94, DECK_H, HALF * 0.94), shade)
		# Rivets / bolt heads at the centre.
		_box(_metal, o + Vector3(0, DECK_H + 0.005, 0), Vector3(0.08, 0.02, 0.08), Color(0.3, 0.32, 0.36))
	# Floor light strip along any edge that meets a wall.
	for d: Vector2i in DIRS:
		if _is_wall(c + d):
			var along := Vector3(absf(d.y), 0, absf(d.x)) * HALF * 1.6 + Vector3(0.04, 0.01, 0.04)
			var edge := Vector3(d.x, 0, d.y) * HALF * 0.86
			_box(_cyan, o + edge + Vector3(0, DECK_H + 0.006, 0), along, Color(0.25, 0.8, 1.0))


# --- Walls ----------------------------------------------------------------------

func _wall(c: Vector2i) -> void:
	var o := _board.world(c)
	var r := _rng(c, 1)
	_box(_metal, o + Vector3(0, WALL_H / 2.0, 0), Vector3(HALF * 2.0, WALL_H, HALF * 2.0), Color(0.16, 0.18, 0.22))
	# Top cap: dark armour plate, an inset panel and vent slits (the camera
	# mostly sees wall tops, so keep them dark and busy rather than bright).
	_box(_dark, o + Vector3(0, WALL_H + 0.01, 0), Vector3(HALF * 2.0, 0.02, HALF * 2.0), Color(0.07, 0.08, 0.1))
	_box(_plate, o + Vector3(0, WALL_H + 0.025, 0), Vector3(HALF * 1.55, 0.02, HALF * 1.55), Color(0.12, 0.13, 0.16))
	if r.randf() < 0.6:
		for k in 4:
			_box(_dark, o + Vector3(0, WALL_H + 0.04, -HALF * 0.45 + k * HALF * 0.3), Vector3(HALF * 0.9, 0.01, 0.06), Color(0.04, 0.05, 0.06))
	else:
		_box(_metal, o + Vector3(r.randf_range(-0.3, 0.3), WALL_H + 0.07, r.randf_range(-0.3, 0.3)), Vector3(0.3, 0.08, 0.22), Color(0.2, 0.22, 0.26))
	for d: Vector2i in DIRS:
		if _is_wall(c + d):
			continue
		# Detail only on faces that look onto open deck.
		var n := Vector3(d.x, 0, d.y)
		var across := Vector3(absf(d.y), 0, absf(d.x))  # along the face
		var face := o + n * HALF
		# Trim band and a lit strip near the floor.
		_box(_dark, face + n * 0.02 + Vector3(0, 0.38, 0), across * HALF * 1.9 + n.abs() * 0.04 + Vector3(0, 0.07, 0), Color(0.09, 0.1, 0.12))
		var light := _amber if r.randf() < 0.3 else _cyan
		_box(light, face + n * 0.025 + Vector3(0, 0.16, 0), across * HALF * 1.6 + n.abs() * 0.02 + Vector3(0, 0.025, 0),
				Color(1.0, 0.7, 0.3) if light == _amber else Color(0.3, 0.85, 1.0))
		# Vertical ribs.
		for s in [-0.62, 0.0, 0.62]:
			_box(_metal, face + n * 0.04 + across * s * HALF * 1.1 + Vector3(0, WALL_H / 2.0, 0),
					across * 0.08 + n.abs() * 0.08 + Vector3(0, WALL_H, 0), Color(0.21, 0.23, 0.28))
		# Sometimes a run of pipes or a wall panel with a status light.
		if r.randf() < 0.45:
			for k in 2:
				_box(_dark, face + n * 0.09 + Vector3(0, 0.62 + k * 0.1, 0),
						across * HALF * 1.9 + n.abs() * 0.06 + Vector3(0, 0.06, 0), Color(0.12, 0.13, 0.15))
		elif r.randf() < 0.6:
			var at := across * r.randf_range(-0.4, 0.4) * HALF
			_box(_dark, face + n * 0.03 + at + Vector3(0, 0.6, 0), across * 0.36 + n.abs() * 0.04 + Vector3(0, 0.26, 0), Color(0.07, 0.08, 0.1))
			_box(_cyan if r.randf() < 0.5 else _amber, face + n * 0.055 + at + Vector3(0, 0.66, 0),
					across * 0.22 + n.abs() * 0.01 + Vector3(0, 0.08, 0), Color(0.4, 1.0, 0.8))


# --- Doors ----------------------------------------------------------------------

func _door(c: Vector2i) -> void:
	var o := _board.world(c)
	# The door runs between the two wall neighbours; pick the axis.
	var along_x := _is_wall(c + Vector2i(0, 1)) or _is_wall(c + Vector2i(0, -1))
	var axis := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)    # the wall line
	var thick := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)   # through the door
	# Frame posts and lintel with hazard stripes.
	for s in [-1.0, 1.0]:
		_box(_metal, o + axis * s * HALF * 0.88 + Vector3(0, WALL_H / 2.0, 0), axis * 0.18 + thick * 0.5 + Vector3(0, WALL_H, 0), Color(0.2, 0.22, 0.26))
		for k in 4:
			var col := Color(0.9, 0.7, 0.12) if k % 2 == 0 else Color(0.08, 0.08, 0.08)
			_box(_hazard, o + axis * s * HALF * 0.88 + thick * 0.26 + Vector3(0, 0.12 + k * 0.2, 0),
					axis * 0.19 + thick * 0.01 + Vector3(0, 0.2, 0), col)
	_box(_metal, o + Vector3(0, WALL_H - 0.08, 0), axis * HALF * 2.0 + thick * 0.5 + Vector3(0, 0.16, 0), Color(0.2, 0.22, 0.26))
	# Two sliding leaves, parted to show it's open.
	for s in [-1.0, 1.0]:
		_box(_dark, o + axis * s * HALF * 0.55 + Vector3(0, (WALL_H - 0.16) / 2.0, 0),
				axis * HALF * 0.5 + thick * 0.12 + Vector3(0, WALL_H - 0.16, 0), Color(0.14, 0.15, 0.17))
	# Status light over the door, and hazard paint on the threshold.
	_box(_amber, o + Vector3(0, WALL_H - 0.08, 0) + thick * 0.26, axis * 0.3 + thick * 0.01 + Vector3(0, 0.05, 0), Color(1.0, 0.75, 0.3))
	for k in 5:
		var col := Color(0.85, 0.66, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1)
		_box(_hazard, o + axis * (-HALF * 0.64 + k * HALF * 0.32) + Vector3(0, DECK_H + 0.006, 0),
				axis * HALF * 0.32 + thick * 0.25 + Vector3(0, 0.01, 0), col)


# --- Cargo ----------------------------------------------------------------------

func _cargo(c: Vector2i) -> void:
	var o := _board.world(c, DECK_H)
	var r := _rng(c, 2)
	var paints := [Color(0.62, 0.32, 0.14), Color(0.16, 0.42, 0.46), Color(0.36, 0.42, 0.24), Color(0.5, 0.5, 0.52)]
	var count := r.randi_range(2, 3)
	for i in count:
		var size := Vector3(r.randf_range(0.55, 0.8), r.randf_range(0.35, 0.55), r.randf_range(0.45, 0.6))
		if r.randf() < 0.5:
			size = Vector3(size.z, size.y, size.x)
		var at := Vector3(r.randf_range(-0.35, 0.35), size.y / 2.0, r.randf_range(-0.35, 0.35))
		if i == count - 1 and r.randf() < 0.5:
			at.y += 0.4  # stacked on top
			size *= 0.8
		var paint: Color = paints[r.randi() % paints.size()]
		_box(_plate, o + at, size, paint)
		# Dark frame bands around the box ends and a label stripe.
		for s in [-1.0, 1.0]:
			_box(_dark, o + at + Vector3(s * size.x * 0.46, 0, 0), Vector3(size.x * 0.08, size.y * 1.02, size.z * 1.03), Color(0.1, 0.1, 0.11))
		_box(_metal, o + at + Vector3(0, size.y * 0.15, size.z * 0.505), Vector3(size.x * 0.3, size.y * 0.25, 0.01), Color(0.85, 0.85, 0.8))
	# A barrel or two beside the crates.
	for i in r.randi_range(0, 2):
		var b := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13
		cyl.bottom_radius = 0.13
		cyl.height = 0.38
		cyl.radial_segments = 10
		b.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = [Color(0.7, 0.55, 0.12), Color(0.55, 0.15, 0.12), Color(0.25, 0.3, 0.35)][r.randi() % 3]
		m.metallic = 0.4
		m.roughness = 0.5
		b.material_override = m
		b.position = o + Vector3(r.randf_range(-0.6, 0.6), 0.19, r.randf_range(-0.6, 0.6))
		_board_parent().add_child(b)
		_board.register_prop(c, b)


var _parent: Node3D


func _board_parent() -> Node3D:
	return _parent


# --- Output -----------------------------------------------------------------------

func _commit(parent: Node3D) -> void:
	var specs := [
		[_plate, _lit(0.55, 0.45)], [_metal, _lit(0.4, 0.7)], [_dark, _lit(0.7, 0.3)],
		[_hazard, _lit(0.6, 0.2)], [_cyan, _glow()], [_amber, _glow()],
	]
	for spec in specs:
		var st: SurfaceTool = spec[0]
		var mesh := st.commit()
		if mesh.get_surface_count() > 0:
			BoardGeometry.mesh_node(parent, spec[1]).mesh = mesh


static func _lit(roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	return m


## Light strips: their vertex colour, glowing.
static func _glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.6, 1.6)
	return m


func _room_lights(parent: Node3D, open_cells: Array[Vector2i]) -> void:
	# A few soft lights over open floor, spread apart.
	var placed: Array[Vector2i] = []
	var r := _rng(Vector2i(17, 3), 5)
	var cells := open_cells.duplicate()
	for i in cells.size():
		var j := r.randi_range(i, cells.size() - 1)
		var t: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = t
	for c: Vector2i in cells:
		if placed.size() >= 6:
			break
		if placed.any(func(p: Vector2i) -> bool: return _grid.distance(p, c) < 4):
			continue
		placed.append(c)
		var light := OmniLight3D.new()
		light.light_color = Color(0.55, 0.8, 1.0)
		light.light_energy = 0.9
		light.omni_range = 4.5
		light.position = _board.world(c, 1.6)
		parent.add_child(light)
