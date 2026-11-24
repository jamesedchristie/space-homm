class_name DeckKit
extends RefCounted
## Dresses a square-grid station interior for the 3D battle board: paneled
## deck plates with grates and floor lights, bulkhead walls with ribs, trim,
## pipes and light strips on the faces you can see, framed sliding doors with
## hazard stripes, cargo containers and barrels, and a few cool room lights.
## Everything is seeded per cell, so a map always looks the same.
##
## High-quality look (Forward+, `hq`): the map's DeckMood sets the palette.
## Walls stand taller with lit caps; surfaces use deck_surface.gdshader
## (grime, tread, seams, scorch marks, and the fog-of-war mask: unexplored
## cells are not drawn, explored ones out of sight are dimmed); cover is
## themed (cargo, lab, industrial, derelict, wreck) with glowing consoles;
## each room gets ceiling lamps (a few cast soft shadows), with emergency
## beacons, stuttering lamps and fires as the mood asks; a haze volume over
## the board catches the lamp light. All static geometry is merged into a
## handful of meshes (one per material).

const WALL_H := 0.95
const HQ_WALL_H := 1.4
const DECK_H := 0.06
const HALF := 0.9          # half a square cell in world units
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Ceiling lamps that cast shadows (the rest light without): keeps the M1 at 60 fps.
const MAX_SHADOWED := 7
const LAMP_HEIGHT := 3.4
const SURFACE := preload("res://src/presentation/shaders/deck_surface.gdshader")
const HAZE := preload("res://src/presentation/shaders/deck_haze.gdshader")
const GRID := preload("res://src/presentation/shaders/deck_grid.gdshader")

var hq := false
var mood: DeckMood
var wall_h := WALL_H
## Every material reading the fog-of-war mask (high quality).
var materials: Array[ShaderMaterial] = []

var _board: BattleBoard3D
var _grid: TacticalGrid
var _plate := SurfaceTool.new()
var _metal := SurfaceTool.new()
var _dark := SurfaceTool.new()
var _cyan := SurfaceTool.new()
var _amber := SurfaceTool.new()
var _hazard := SurfaceTool.new()
var _k := 1.0  # wall height scale (1 on the classic look)
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_size := Vector2i.ONE
var _animator: DeckLightAnimator
var _parent: Node3D


static func build(board: BattleBoard3D, parent: Node3D, p_hq: bool = false, p_mood: DeckMood = null) -> DeckKit:
	var kit := DeckKit.new()
	kit._board = board
	kit._parent = parent
	kit._grid = board.engine.state.grid
	kit.hq = p_hq
	kit.mood = p_mood if p_mood != null else DeckMood.new()
	if p_hq:
		kit.wall_h = HQ_WALL_H
		kit._k = HQ_WALL_H / WALL_H
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
				if p_hq:
					kit._cover(c)
				else:
					kit._cargo(c)
			_:
				kit._floor(c)
				open_cells.append(c)
	if p_hq:
		kit._setup_fog_mask()
		kit._animator = DeckLightAnimator.new()
		parent.add_child(kit._animator)
		var rooms := kit._rooms()
		kit._stencils(rooms)
		kit._lamps(parent, rooms)
		kit._commit(parent)
		kit._haze(parent)
		kit._underlay(parent)
	else:
		kit._commit(parent)
		kit._room_lights(parent, open_cells)
	return kit


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


## Light strip colours: the classic cyan / amber, or the mood's accents.
func _accent(classic: Color) -> Color:
	return classic if not hq else mood.accent * (0.35 + classic.get_luminance() * 0.75)


func _accent2(classic: Color) -> Color:
	return classic if not hq else mood.accent2 * (0.35 + classic.get_luminance() * 0.75)


# --- Floor ----------------------------------------------------------------------

func _floor(c: Vector2i) -> void:
	var o := _board.world(c)
	var r := _rng(c)
	var tone := r.randf_range(-0.02, 0.02)
	var base := Color(0.13 + tone, 0.15 + tone, 0.19 + tone)
	if hq:
		base = Color(0.12 + tone, 0.13 + tone, 0.15 + tone)
	# Sub-plating under the panels.
	_box(_dark, o + Vector3(0, 0.01, 0), Vector3(HALF * 2.0, 0.02, HALF * 2.0), Color(0.05, 0.06, 0.08))
	if r.randf() < 0.09:
		# A grate: dark slats over a faintly lit pit.
		for i in 6:
			var z := -HALF * 0.8 + i * HALF * 0.32
			_box(_metal, o + Vector3(0, DECK_H - 0.01, z), Vector3(HALF * 1.7, 0.03, 0.08), Color(0.1, 0.11, 0.13))
		_box(_cyan, o + Vector3(0, 0.025, 0), Vector3(HALF * 1.4, 0.005, HALF * 1.4),
				Color(0.06, 0.22, 0.3) if not hq else mood.accent * 0.12)
	else:
		# Four panels with seams between them.
		for qx in [-1.0, 1.0]:
			for qz in [-1.0, 1.0]:
				var shade := base.lightened(r.randf_range(0.0, 0.06 if not hq else 0.1))
				_box(_plate, o + Vector3(qx * HALF * 0.5, DECK_H / 2.0, qz * HALF * 0.5),
						Vector3(HALF * 0.94, DECK_H, HALF * 0.94), shade)
		# Rivets / bolt heads at the centre.
		_box(_metal, o + Vector3(0, DECK_H + 0.005, 0), Vector3(0.08, 0.02, 0.08), Color(0.3, 0.32, 0.36))
	# Floor light strip along any edge that meets a wall.
	for d: Vector2i in DIRS:
		if _is_wall(c + d):
			var along := Vector3(absf(d.y), 0, absf(d.x)) * HALF * 1.6 + Vector3(0.04, 0.01, 0.04)
			var edge := Vector3(d.x, 0, d.y) * HALF * 0.86
			if hq:
				along = Vector3(absf(d.y), 0, absf(d.x)) * HALF * 1.6 + Vector3(0.025, 0.01, 0.025)
			_box(_cyan, o + edge + Vector3(0, DECK_H + 0.006, 0), along, _accent(Color(0.25, 0.8, 1.0)))


# --- Walls ----------------------------------------------------------------------

func _wall(c: Vector2i) -> void:
	var o := _board.world(c)
	var r := _rng(c, 1)
	var k := _k
	var h := wall_h
	_box(_metal, o + Vector3(0, h / 2.0, 0), Vector3(HALF * 2.0, h, HALF * 2.0),
			Color(0.16, 0.18, 0.22) if not hq else Color(0.2, 0.215, 0.24))
	# Top cap: dark armour plate, an inset panel and vent slits (the camera
	# mostly sees wall tops, so keep them dark and busy rather than bright).
	_box(_dark, o + Vector3(0, h + 0.01, 0), Vector3(HALF * 2.0, 0.02, HALF * 2.0), Color(0.07, 0.08, 0.1))
	_box(_plate, o + Vector3(0, h + 0.025, 0), Vector3(HALF * 1.55, 0.02, HALF * 1.55), Color(0.12, 0.13, 0.16))
	if r.randf() < 0.6:
		for i in 4:
			_box(_dark, o + Vector3(0, h + 0.04, -HALF * 0.45 + i * HALF * 0.3), Vector3(HALF * 0.9, 0.01, 0.06), Color(0.04, 0.05, 0.06))
	else:
		_box(_metal, o + Vector3(r.randf_range(-0.3, 0.3), h + 0.07, r.randf_range(-0.3, 0.3)), Vector3(0.3, 0.08, 0.22), Color(0.2, 0.22, 0.26))
	for d: Vector2i in DIRS:
		if _is_wall(c + d):
			continue
		# Detail only on faces that look onto open deck.
		var n := Vector3(d.x, 0, d.y)
		var across := Vector3(absf(d.y), 0, absf(d.x))  # along the face
		var face := o + n * HALF
		if hq:
			# A raised lip along the top edge so the wall's outline reads from above,
			# with a thin lit line under it.
			_box(_metal, face - n * 0.06 + Vector3(0, h + 0.035, 0), across * HALF * 2.0 + n.abs() * 0.12 + Vector3(0, 0.05, 0), Color(0.3, 0.32, 0.36))
			_box(_cyan, face + n * 0.012 + Vector3(0, h - 0.06, 0), across * HALF * 1.9 + n.abs() * 0.01 + Vector3(0, 0.018, 0), mood.accent * 0.5)
		# Trim band and a lit strip near the floor.
		_box(_dark, face + n * 0.02 + Vector3(0, 0.38 * k, 0), across * HALF * 1.9 + n.abs() * 0.04 + Vector3(0, 0.07, 0), Color(0.09, 0.1, 0.12))
		var light := _amber if r.randf() < 0.3 else _cyan
		_box(light, face + n * 0.025 + Vector3(0, 0.16, 0), across * HALF * 1.6 + n.abs() * 0.02 + Vector3(0, 0.025, 0),
				_accent2(Color(1.0, 0.7, 0.3)) if light == _amber else _accent(Color(0.3, 0.85, 1.0)))
		# Vertical ribs.
		for s in [-0.62, 0.0, 0.62]:
			_box(_metal, face + n * 0.04 + across * s * HALF * 1.1 + Vector3(0, h / 2.0, 0),
					across * 0.08 + n.abs() * 0.08 + Vector3(0, h, 0), Color(0.21, 0.23, 0.28))
		# Sometimes a run of pipes or a wall panel with a status light.
		if r.randf() < 0.45:
			for i in 2:
				_box(_dark, face + n * 0.09 + Vector3(0, (0.62 + i * 0.1) * k, 0),
						across * HALF * 1.9 + n.abs() * 0.06 + Vector3(0, 0.06, 0), Color(0.12, 0.13, 0.15))
		elif r.randf() < 0.6:
			var at := across * r.randf_range(-0.4, 0.4) * HALF
			_box(_dark, face + n * 0.03 + at + Vector3(0, 0.6 * k, 0), across * 0.36 + n.abs() * 0.04 + Vector3(0, 0.26, 0), Color(0.07, 0.08, 0.1))
			_box(_cyan if r.randf() < 0.5 else _amber, face + n * 0.055 + at + Vector3(0, 0.6 * k + 0.06, 0),
					across * 0.22 + n.abs() * 0.01 + Vector3(0, 0.08, 0), Color(0.4, 1.0, 0.8) if not hq else mood.accent * 0.8)
		elif hq and r.randf() < 0.5:
			# A wall screen: a dark bezel and a lit display with a few readout bars.
			var at := across * r.randf_range(-0.35, 0.35) * HALF
			var y := h * 0.62
			_box(_dark, face + n * 0.03 + at + Vector3(0, y, 0), across * 0.5 + n.abs() * 0.05 + Vector3(0, 0.34, 0), Color(0.05, 0.06, 0.07))
			_box(_cyan, face + n * 0.058 + at + Vector3(0, y, 0), across * 0.42 + n.abs() * 0.01 + Vector3(0, 0.26, 0), mood.accent * 0.22)
			for i in 3:
				_box(_cyan, face + n * 0.064 + at + across * (-0.08 + r.randf_range(-0.04, 0.04)) + Vector3(0, y + 0.07 - i * 0.07, 0),
						across * r.randf_range(0.12, 0.3) + n.abs() * 0.01 + Vector3(0, 0.025, 0), mood.accent * 0.9)


# --- Doors ----------------------------------------------------------------------

func _door(c: Vector2i) -> void:
	var o := _board.world(c)
	var h := wall_h
	# The door runs between the two wall neighbours; pick the axis.
	var along_x := _is_wall(c + Vector2i(0, 1)) or _is_wall(c + Vector2i(0, -1))
	var axis := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)    # the wall line
	var thick := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)   # through the door
	# Frame posts and lintel with hazard stripes.
	for s in [-1.0, 1.0]:
		_box(_metal, o + axis * s * HALF * 0.88 + Vector3(0, h / 2.0, 0), axis * 0.18 + thick * 0.5 + Vector3(0, h, 0), Color(0.2, 0.22, 0.26))
		for i in 4:
			var col := Color(0.9, 0.7, 0.12) if i % 2 == 0 else Color(0.08, 0.08, 0.08)
			for side in ([1.0] if not hq else [1.0, -1.0]):
				_box(_hazard, o + axis * s * HALF * 0.88 + thick * 0.26 * side + Vector3(0, (0.12 + i * 0.2) * _k, 0),
						axis * 0.19 + thick * 0.01 + Vector3(0, 0.2 * _k, 0), col)
	_box(_metal, o + Vector3(0, h - 0.08, 0), axis * HALF * 2.0 + thick * 0.5 + Vector3(0, 0.16, 0), Color(0.2, 0.22, 0.26))
	# Two sliding leaves, parted to show it's open.
	for s in [-1.0, 1.0]:
		_box(_dark, o + axis * s * HALF * 0.55 + Vector3(0, (h - 0.16) / 2.0, 0),
				axis * HALF * 0.5 + thick * 0.12 + Vector3(0, h - 0.16, 0), Color(0.14, 0.15, 0.17))
	# Status light over the door, and hazard paint on the threshold.
	for side in ([1.0] if not hq else [1.0, -1.0]):
		_box(_amber, o + Vector3(0, h - 0.08, 0) + thick * 0.26 * side, axis * 0.3 + thick * 0.01 + Vector3(0, 0.05, 0), _accent2(Color(1.0, 0.75, 0.3)))
	for i in 5:
		var col := Color(0.85, 0.66, 0.1) if i % 2 == 0 else Color(0.1, 0.1, 0.1)
		_box(_hazard, o + axis * (-HALF * 0.64 + i * HALF * 0.32) + Vector3(0, DECK_H + 0.006, 0),
				axis * HALF * 0.32 + thick * 0.25 + Vector3(0, 0.01, 0), col)
	if hq:
		# The door's own lamp, washing the frame in its status colour.
		var lamp := OmniLight3D.new()
		lamp.light_color = mood.accent2
		lamp.light_energy = 1.1
		lamp.omni_range = 2.4
		lamp.light_specular = 0.4
		lamp.light_volumetric_fog_energy = 0.6
		lamp.position = o + Vector3(0, h + 0.1, 0)
		_parent.add_child(lamp)
		_board.register_prop(c, lamp)


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
		_parent.add_child(b)
		_board.register_prop(c, b)


# --- Themed cover (high quality) ------------------------------------------------

const PAINTS := {
	"cargo": [Color(0.62, 0.3, 0.12), Color(0.14, 0.38, 0.44), Color(0.34, 0.4, 0.22), Color(0.48, 0.48, 0.5), Color(0.6, 0.5, 0.14)],
	"lab": [Color(0.75, 0.77, 0.78), Color(0.55, 0.6, 0.62), Color(0.3, 0.42, 0.4)],
	"industrial": [Color(0.62, 0.36, 0.1), Color(0.55, 0.45, 0.12), Color(0.3, 0.3, 0.32), Color(0.42, 0.2, 0.12)],
	"derelict": [Color(0.3, 0.34, 0.38), Color(0.42, 0.24, 0.16), Color(0.26, 0.32, 0.26), Color(0.4, 0.4, 0.42)],
	"wreck": [Color(0.32, 0.3, 0.28), Color(0.45, 0.28, 0.16), Color(0.25, 0.27, 0.3)],
}
## What a cover cell can hold, per theme (picked per cell, repeats weight the pick).
const COVER := {
	"cargo": ["crates", "crates", "crates", "barrels", "console"],
	"lab": ["bench", "bench", "tank", "console", "crates"],
	"industrial": ["barrels", "ore", "pipes", "crates", "generator"],
	"derelict": ["crates", "lockers", "console", "debris", "barrels"],
	"wreck": ["debris", "debris", "crates", "barrels", "lockers"],
}


func _cover(c: Vector2i) -> void:
	var o := _board.world(c, DECK_H)
	var r := _rng(c, 2)
	var theme: String = mood.props if COVER.has(mood.props) else "cargo"
	var paints: Array = PAINTS[theme]
	var kinds: Array = COVER[theme]
	var kind: String = kinds[r.randi() % kinds.size()]
	var yaw := float(r.randi() % 4) * PI / 2.0 + r.randf_range(-0.12, 0.12)
	match kind:
		"crates":
			_crate_stack(o, r, paints)
		"barrels":
			_barrels(o, r, paints, r.randi_range(3, 5))
		"console":
			_console(o, r, yaw)
			var side := Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.5)
			_crate(o + side + Basis(Vector3.UP, yaw) * Vector3(-0.3, 0, 0), r, paints, 0.85)
			_crate(o + side + Basis(Vector3.UP, yaw) * Vector3(0.35, 0, 0.05), r, paints, 0.7)
		"bench":
			_bench(o, r, yaw)
		"tank":
			_tank(o + Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25)), r)
			_barrels(o + Vector3(0.45, 0, 0.45), r, paints, 1)
		"ore":
			_ore_bin(o, r, yaw)
		"pipes":
			_pipe_stack(o, r, yaw)
		"generator":
			_generator(o, r, yaw)
		"lockers":
			_lockers(o, r, yaw, paints)
		"debris":
			_debris(o, r, paints)


## A box turned by `yaw` around its centre (all six faces; sides a little darker).
func _obox(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size / 2.0
	var faces := [
		[Vector3.UP, color], [Vector3.DOWN, color.darkened(0.5)],
		[Vector3.RIGHT, color.darkened(0.2)], [Vector3.LEFT, color.darkened(0.2)],
		[Vector3.BACK, color.darkened(0.28)], [Vector3.FORWARD, color.darkened(0.28)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u := Vector3(n.y, n.z, n.x)  # a perpendicular axis
		var v := n.cross(u)
		var corners: Array[Vector3] = []
		for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
			corners.append(center + b * ((n + u * s[0] + v * s[1]) * h))
		var wn := b * n
		for i in [0, 2, 1, 0, 3, 2]:  # clockwise seen from outside (Godot's front face)
			st.set_normal(wn)
			st.set_color(f[1])
			st.add_vertex(corners[i])


## An upright cylinder (side and top) standing on `base`.
func _cyl(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, segments: int = 10) -> void:
	var top := base + Vector3(0, height, 0)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var side := color.darkened(0.15)
		for v in [[base + d0 * radius, d0], [base + d1 * radius, d1], [top + d1 * radius, d1],
				[base + d0 * radius, d0], [top + d1 * radius, d1], [top + d0 * radius, d0]]:
			st.set_normal(v[1])
			st.set_color(side)
			st.add_vertex(v[0])
		for v in [top, top + d0 * radius, top + d1 * radius]:
			st.set_normal(Vector3.UP)
			st.set_color(color)
			st.add_vertex(v)


## A horizontal cylinder along `dir` (pipes), centred on `center`.
func _hcyl(st: SurfaceTool, center: Vector3, dir: Vector3, radius: float, length: float, color: Color, segments: int = 8) -> void:
	var ax := dir.normalized()
	var u := Vector3.UP
	var v := ax.cross(u).normalized()
	var a := center - ax * length / 2.0
	var b := center + ax * length / 2.0
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		for p in [[a + d0 * radius, d0], [b + d0 * radius, d0], [b + d1 * radius, d1],
				[a + d0 * radius, d0], [b + d1 * radius, d1], [a + d1 * radius, d1]]:
			st.set_normal(p[1])
			st.set_color(color)
			st.add_vertex(p[0])


func _crate(o: Vector3, r: RandomNumberGenerator, paints: Array, scale: float = 1.0) -> void:
	var size := Vector3(r.randf_range(0.6, 0.8), r.randf_range(0.42, 0.6), r.randf_range(0.48, 0.62)) * scale
	var yaw := float(r.randi() % 2) * PI / 2.0 + r.randf_range(-0.1, 0.1)
	var paint: Color = paints[r.randi() % paints.size()]
	_crate_at(o + Vector3(0, size.y / 2.0, 0), size, yaw, paint, r)


func _crate_at(center: Vector3, size: Vector3, yaw: float, paint: Color, r: RandomNumberGenerator) -> void:
	_obox(_plate, center, size, yaw, paint)
	var b := Basis(Vector3.UP, yaw)
	# Reinforced corner frame bands and a stencil label.
	for s in [-1.0, 1.0]:
		_obox(_dark, center + b * Vector3(s * size.x * 0.45, 0, 0), Vector3(size.x * 0.09, size.y * 1.03, size.z * 1.04), yaw, Color(0.09, 0.09, 0.1))
	_obox(_metal, center + b * Vector3(0, size.y * 0.12, size.z * 0.505), Vector3(size.x * 0.32, size.y * 0.22, 0.012), yaw, Color(0.8, 0.8, 0.74))
	if r.randf() < 0.35:
		_obox(_hazard, center + b * Vector3(0, -size.y * 0.3, -size.z * 0.505), Vector3(size.x * 0.7, size.y * 0.1, 0.012), yaw, Color(0.85, 0.66, 0.1))


func _crate_stack(o: Vector3, r: RandomNumberGenerator, paints: Array) -> void:
	var count := r.randi_range(2, 3)
	for i in count:
		var size := Vector3(r.randf_range(0.62, 0.9), r.randf_range(0.4, 0.62), r.randf_range(0.5, 0.68))
		var at := Vector3(r.randf_range(-0.35, 0.35), size.y / 2.0, r.randf_range(-0.35, 0.35))
		if i == count - 1 and r.randf() < 0.55:
			at.y += 0.42
			size *= 0.8
		var yaw := float(r.randi() % 2) * PI / 2.0 + r.randf_range(-0.12, 0.12)
		_crate_at(o + at, size, yaw, paints[r.randi() % paints.size()], r)
	if r.randf() < 0.5:
		_barrels(o + Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5)), r, paints, r.randi_range(1, 2))


func _barrels(o: Vector3, r: RandomNumberGenerator, paints: Array, count: int) -> void:
	var colors := [Color(0.7, 0.55, 0.12), Color(0.55, 0.15, 0.12), Color(0.25, 0.3, 0.35), paints[0]]
	for i in count:
		var at := o + Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
		var col: Color = colors[r.randi() % colors.size()]
		_cyl(_plate, at, 0.14, 0.42, col, 12)
		# Rolled rims.
		_cyl(_dark, at + Vector3(0, 0.12, 0), 0.145, 0.03, col.darkened(0.4), 12)
		_cyl(_dark, at + Vector3(0, 0.28, 0), 0.145, 0.03, col.darkened(0.4), 12)


## A slanted terminal: a dark pedestal with a glowing screen facing along `yaw`.
func _console(o: Vector3, r: RandomNumberGenerator, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var at := o + b * Vector3(r.randf_range(-0.2, 0.2), 0, -0.15)
	_obox(_metal, at + Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.36), yaw, Color(0.22, 0.24, 0.27))
	_obox(_dark, at + b * Vector3(0, 0.63, 0.04), Vector3(0.66, 0.07, 0.42), yaw, Color(0.07, 0.08, 0.09))
	_obox(_cyan, at + b * Vector3(0, 0.672, 0.04), Vector3(0.5, 0.012, 0.3), yaw, mood.accent * 0.25)
	# Readout lines and a couple of status pips.
	for i in 3:
		_obox(_cyan, at + b * Vector3(r.randf_range(-0.1, 0.1), 0.68, -0.06 + i * 0.07), Vector3(r.randf_range(0.12, 0.34), 0.008, 0.025), yaw, mood.accent * 1.4)
	_obox(_amber, at + b * Vector3(0.24, 0.45, 0.185), Vector3(0.05, 0.05, 0.012), yaw, Color(1.0, 0.25, 0.15))
	_obox(_cyan, at + b * Vector3(0.16, 0.45, 0.185), Vector3(0.05, 0.05, 0.012), yaw, Color(0.3, 1.0, 0.45))


## Lab bench: a steel table on legs with sample racks glowing in the mood's accent.
func _bench(o: Vector3, r: RandomNumberGenerator, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_obox(_plate, o + Vector3(0, 0.52, 0), Vector3(1.3, 0.05, 0.6), yaw, Color(0.62, 0.65, 0.67))
	_obox(_dark, o + Vector3(0, 0.25, 0), Vector3(1.2, 0.4, 0.5), yaw, Color(0.16, 0.17, 0.19))
	for i in r.randi_range(3, 6):
		var at := o + b * Vector3(r.randf_range(-0.5, 0.5), 0.545, r.randf_range(-0.2, 0.2))
		_cyl(_cyan, at, 0.035, r.randf_range(0.1, 0.2), mood.accent * 0.45, 6)
	if r.randf() < 0.6:
		_obox(_metal, o + b * Vector3(0.35, 0.65, 0.0), Vector3(0.3, 0.2, 0.3), yaw, Color(0.3, 0.32, 0.35))
		_obox(_cyan, o + b * Vector3(0.35, 0.68, 0.152), Vector3(0.22, 0.1, 0.01), yaw, mood.accent * 0.3)


## A specimen tank: a glowing column of fluid between steel caps.
func _tank(o: Vector3, r: RandomNumberGenerator) -> void:
	_cyl(_metal, o, 0.36, 0.16, Color(0.3, 0.32, 0.35), 14)
	_cyl(_cyan, o + Vector3(0, 0.16, 0), 0.28, 0.72, mood.accent * r.randf_range(0.1, 0.15), 14)
	_cyl(_metal, o + Vector3(0, 0.88, 0), 0.34, 0.1, Color(0.3, 0.32, 0.35), 14)
	for a in 4:
		var d := Vector3(cos(a * PI / 2.0 + 0.4), 0, sin(a * PI / 2.0 + 0.4))
		_box(_dark, o + d * 0.31 + Vector3(0, 0.55, 0), Vector3(0.05, 0.75, 0.05), Color(0.12, 0.13, 0.15))


func _ore_bin(o: Vector3, r: RandomNumberGenerator, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var paint := Color(0.55, 0.42, 0.12)
	# Four walls of an open skip, heaped with rock.
	_obox(_plate, o + b * Vector3(0, 0.25, 0.3), Vector3(1.1, 0.5, 0.06), yaw, paint)
	_obox(_plate, o + b * Vector3(0, 0.25, -0.3), Vector3(1.1, 0.5, 0.06), yaw, paint)
	_obox(_plate, o + b * Vector3(0.53, 0.25, 0), Vector3(0.06, 0.5, 0.6), yaw, paint.darkened(0.1))
	_obox(_plate, o + b * Vector3(-0.53, 0.25, 0), Vector3(0.06, 0.5, 0.6), yaw, paint.darkened(0.1))
	_obox(_hazard, o + b * Vector3(0, 0.42, 0.335), Vector3(1.0, 0.06, 0.01), yaw, Color(0.1, 0.1, 0.1))
	for i in 7:
		var at := o + b * Vector3(r.randf_range(-0.38, 0.38), r.randf_range(0.38, 0.52), r.randf_range(-0.18, 0.18))
		_obox(_dark, at, Vector3.ONE * r.randf_range(0.12, 0.22), r.randf() * TAU, Color(0.24, 0.2, 0.17).lightened(r.randf_range(0.0, 0.15)))


func _pipe_stack(o: Vector3, r: RandomNumberGenerator, yaw: float) -> void:
	var dir := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var side := dir.cross(Vector3.UP)
	var col := Color(0.42, 0.4, 0.36)
	for i in 3:
		_hcyl(_metal, o + side * (i - 1) * 0.24 + Vector3(0, 0.12, 0), dir, 0.12, 1.4, col.darkened(r.randf_range(0.0, 0.3)))
	for i in 2:
		_hcyl(_metal, o + side * (i - 0.5) * 0.24 + Vector3(0, 0.33, 0), dir, 0.12, 1.3, col.darkened(r.randf_range(0.0, 0.3)))
	for s in [-0.5, 0.5]:
		_obox(_hazard, o + dir * s + Vector3(0, 0.22, 0), Vector3(0.08, 0.45, 0.8), yaw, Color(0.85, 0.66, 0.1))


func _generator(o: Vector3, r: RandomNumberGenerator, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_obox(_metal, o + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 0.7), yaw, Color(0.45, 0.32, 0.12))
	_obox(_dark, o + Vector3(0, 0.62, 0), Vector3(0.8, 0.06, 0.5), yaw, Color(0.1, 0.1, 0.11))
	for i in 5:
		_obox(_dark, o + b * Vector3(-0.3 + i * 0.15, 0.32, 0.355), Vector3(0.06, 0.4, 0.01), yaw, Color(0.06, 0.06, 0.07))
	_obox(_amber, o + b * Vector3(0.38, 0.45, 0.355), Vector3(0.1, 0.06, 0.012), yaw, mood.accent2 * 1.2)
	_cyl(_dark, o + b * Vector3(-0.25, 0.64, 0), 0.09, 0.3, Color(0.2, 0.2, 0.22), 8)
	if r.randf() < 0.5:
		_barrels(o + b * Vector3(0, 0, 0.6), r, [Color(0.55, 0.15, 0.12)], 1)


func _lockers(o: Vector3, r: RandomNumberGenerator, yaw: float, paints: Array) -> void:
	var b := Basis(Vector3.UP, yaw)
	var paint: Color = paints[r.randi() % paints.size()]
	if r.randf() < 0.5:
		# Toppled on its back.
		_obox(_plate, o + b * Vector3(0, 0.2, 0), Vector3(1.2, 0.4, 0.55), yaw + r.randf_range(-0.3, 0.3), paint)
		_obox(_dark, o + b * Vector3(0, 0.41, 0), Vector3(1.0, 0.02, 0.4), yaw, Color(0.08, 0.08, 0.09))
	else:
		for i in 2:
			var at := o + b * Vector3(-0.28 + i * 0.56, 0.45, 0)
			_obox(_plate, at, Vector3(0.52, 0.9, 0.45), yaw, paint.darkened(i * 0.1))
			for k in 3:
				_obox(_dark, at + b * Vector3(0, 0.3 - k * 0.06, 0.228), Vector3(0.3, 0.02, 0.01), yaw, Color(0.06, 0.06, 0.07))
	_crate(o + b * Vector3(r.randf_range(-0.3, 0.3), 0, 0.6), r, paints, 0.6)


func _debris(o: Vector3, r: RandomNumberGenerator, paints: Array) -> void:
	# Twisted plating and a broken beam: slabs at odd angles.
	for i in r.randi_range(3, 5):
		var size := Vector3(r.randf_range(0.3, 0.9), r.randf_range(0.06, 0.4), r.randf_range(0.2, 0.5))
		var at := o + Vector3(r.randf_range(-0.45, 0.45), size.y * 0.5 + r.randf_range(0.0, 0.2), r.randf_range(-0.45, 0.45))
		var col: Color = (paints[r.randi() % paints.size()] as Color).darkened(r.randf_range(0.2, 0.5))
		_obox(_metal if i % 2 == 0 else _plate, at, size, r.randf() * TAU, col)
	_hcyl(_dark, o + Vector3(0, 0.35, 0), Vector3(cos(r.randf() * TAU), 0.25, sin(r.randf() * TAU)), 0.07, 1.3, Color(0.2, 0.19, 0.18))


# --- Rooms, paint and lights (high quality) -------------------------------------

## Open floor split by bulkheads and doors: [{"cells": Array[Vector2i], "open": Array[Vector2i]}],
## largest first. "open" are the cells without cover.
func _rooms() -> Array[Dictionary]:
	var seen := {}
	var out: Array[Dictionary] = []
	var cells := _grid.cells()
	cells.sort()
	for start in cells:
		if seen.has(start) or _is_wall(start) or _deco(start) == "hazard":
			continue
		var room: Array[Vector2i] = []
		var open: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			room.append(c)
			if _deco(c) == "":
				open.append(c)
			for d: Vector2i in DIRS:
				var nb: Vector2i = c + d
				if _grid.has_cell(nb) and not seen.has(nb) and not _is_wall(nb) and _deco(nb) != "hazard":
					seen[nb] = true
					queue.append(nb)
		room.sort()
		open.sort()
		out.append({"cells": room, "open": open if not open.is_empty() else room})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["cells"] as Array).size() > (b["cells"] as Array).size())
	return out


## Spread-out cells of a room: the one nearest its middle, then each next the farthest from those placed.
func _spread(cells: Array[Vector2i], count: int) -> Array[Vector2i]:
	var mid := Vector2.ZERO
	for c in cells:
		mid += Vector2(c)
	mid /= float(cells.size())
	var first := cells[0]
	for c in cells:
		if Vector2(c).distance_to(mid) < Vector2(first).distance_to(mid):
			first = c
	var out: Array[Vector2i] = [first]
	while out.size() < count:
		var best := cells[0]
		var best_d := -1.0
		for c in cells:
			var d := INF
			for p in out:
				d = minf(d, Vector2(c).distance_to(Vector2(p)))
			if d > best_d:
				best_d = d
				best = c
		if best_d < 2.5:
			break
		out.append(best)
	return out


func _lamps(parent: Node3D, rooms: Array[Dictionary]) -> void:
	var r := _rng(Vector2i(17, 3), 5)
	# Rooms on emergency power: a pulsing red beacon, and their lamps run dim.
	var emergency := {}
	for room in rooms:
		if r.randf() < mood.emergency:
			emergency[room["cells"][0]] = true
	var plans: Array = []  # [cell, rank in its room, room key]
	for room in rooms:
		var cells: Array[Vector2i] = room["open"]
		var count := clampi(roundi(float((room["cells"] as Array).size()) / 14.0), 1, 4)
		var spots := _spread(cells, count)
		for i in spots.size():
			plans.append([spots[i], i, room["cells"][0]])
	# The first lamp of the biggest rooms casts shadows, then second lamps, within budget.
	var order := plans.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) < int(b[1]))
	var shadowed := {}
	for p in order:
		if shadowed.size() >= MAX_SHADOWED:
			break
		shadowed[p[0]] = true
	for p in plans:
		var c: Vector2i = p[0]
		var lamp := SpotLight3D.new()
		lamp.light_color = mood.light
		lamp.light_energy = 6.0 * mood.light_energy * (0.35 if emergency.has(p[2]) else 1.0)
		lamp.spot_range = 7.5
		lamp.spot_angle = 64.0
		lamp.spot_angle_attenuation = 2.2
		lamp.spot_attenuation = 1.4
		lamp.light_specular = 0.7
		lamp.light_volumetric_fog_energy = 3.0
		lamp.shadow_enabled = shadowed.has(c)
		lamp.shadow_blur = 1.6
		lamp.shadow_bias = 0.04
		lamp.shadow_normal_bias = 1.2
		lamp.position = _board.world(c, LAMP_HEIGHT)
		lamp.rotation_degrees = Vector3(-90, 0, 0)
		parent.add_child(lamp)
		_board.register_prop(c, lamp)
		if r.randf() < mood.flicker:
			_animator.add(lamp, DeckLightAnimator.STUTTER, r.randf() * 10.0)
	# There is no ceiling: a lamp shows as its pool of light and its beam in the haze.
	for room in rooms:
		if not emergency.has(room["cells"][0]):
			continue
		var cells: Array[Vector2i] = room["open"]
		var spot: Variant = null
		var face := Vector2i.ZERO
		for c in cells:
			for d: Vector2i in DIRS:
				if _is_wall(c + d) and _grid.has_cell(c + d):
					spot = c
					face = d
					break
			if spot != null:
				break
		if spot == null:
			continue
		var cell: Vector2i = spot
		var n := Vector3(face.x, 0, face.y)
		var at := _board.world(cell) + n * (HALF - 0.04) + Vector3(0, wall_h * 0.78, 0)
		_box(_amber, at, Vector3(0.14, 0.1, 0.14) + n.abs() * -0.06, Color(1.0, 0.12, 0.08) * 1.6)
		var beacon := OmniLight3D.new()
		beacon.light_color = Color(1.0, 0.16, 0.1)
		beacon.light_energy = 2.2
		beacon.omni_range = 4.2
		beacon.light_volumetric_fog_energy = 2.0
		beacon.position = at - n * 0.3
		parent.add_child(beacon)
		_board.register_prop(cell, beacon)
		_animator.add(beacon, DeckLightAnimator.PULSE, r.randf() * 3.0)
	# Fires burning on the deck.
	var fire_cells: Array[Vector2i] = []
	for room in rooms:
		fire_cells.append_array(room["open"] as Array[Vector2i])
	for i in mini(mood.fires, fire_cells.size()):
		var c: Vector2i = fire_cells[r.randi() % fire_cells.size()]
		_fire(parent, c, r)


func _fire(parent: Node3D, c: Vector2i, r: RandomNumberGenerator) -> void:
	var at := _board.world(c, DECK_H) + Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
	var flames := CPUParticles3D.new()
	var mote := SphereMesh.new()
	mote.radius = 0.07
	mote.height = 0.14
	mote.radial_segments = 6
	mote.rings = 3
	var mat := BoardGeometry.additive_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mote.material = mat
	flames.mesh = mote
	flames.amount = 36
	flames.lifetime = 0.8
	flames.preprocess = 1.0
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.18
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 0.6, 0)
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 0.7
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(2.4, 1.3, 0.4))
	ramp.add_point(0.4, Color(1.4, 0.4, 0.08))
	ramp.set_color(ramp.get_point_count() - 1, Color(0, 0, 0))
	flames.color_ramp = ramp
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.position = at
	parent.add_child(flames)
	_board.register_prop(c, flames)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.18)
	light.light_energy = 2.0
	light.omni_range = 3.2
	light.light_volumetric_fog_energy = 1.2
	light.position = at + Vector3(0, 0.45, 0)
	parent.add_child(light)
	_board.register_prop(c, light)
	_animator.add(light, DeckLightAnimator.FIRE, r.randf() * 10.0)


## Stencilled bay numbers on the floor of the bigger rooms (seven-segment paint).
const SEGMENTS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
	"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcfgd",
}


func _stencils(rooms: Array[Dictionary]) -> void:
	var r := _rng(Vector2i(5, 11), 9)
	var paint := Color(0.62, 0.6, 0.5)
	var number := r.randi_range(1, 6)
	for room in rooms:
		var open: Array[Vector2i] = room["open"]
		if (room["cells"] as Array).size() < 10:
			continue
		var c: Vector2i = open[r.randi() % open.size()]
		var text := "%02d" % number
		number += r.randi_range(1, 3)
		var o := _board.world(c) + Vector3(-0.32, DECK_H + 0.004, 0.0)
		for i in text.length():
			_digit(o + Vector3(i * 0.42, 0, 0), text[i], paint)


func _digit(o: Vector3, ch: String, color: Color) -> void:
	var w := 0.28
	var h := 0.5
	var t := 0.07
	var segs: String = SEGMENTS.get(ch, "")
	var spec := {
		"a": [Vector3(0, 0, -h / 2.0), Vector3(w, 0.004, t)],
		"g": [Vector3(0, 0, 0), Vector3(w, 0.004, t)],
		"d": [Vector3(0, 0, h / 2.0), Vector3(w, 0.004, t)],
		"f": [Vector3(-w / 2.0, 0, -h / 4.0), Vector3(t, 0.004, h / 2.0)],
		"b": [Vector3(w / 2.0, 0, -h / 4.0), Vector3(t, 0.004, h / 2.0)],
		"e": [Vector3(-w / 2.0, 0, h / 4.0), Vector3(t, 0.004, h / 2.0)],
		"c": [Vector3(w / 2.0, 0, h / 4.0), Vector3(t, 0.004, h / 2.0)],
	}
	for s in segs:
		var part: Array = spec[s]
		_box(_hazard, o + part[0], part[1], color)


# --- Fog of war (high quality) ------------------------------------------------------

func _setup_fog_mask() -> void:
	var hi := Vector2i.ZERO
	for c in _grid.cells():
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	_fog_size = hi + Vector2i.ONE
	_fog_image = Image.create_empty(_fog_size.x, _fog_size.y, false, Image.FORMAT_RG8)
	_fog_image.fill(Color(1, 1, 0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)


## The fog-of-war mask the deck materials and the haze read: unexplored cells vanish,
## explored ones out of sight dim. enabled false shows everything.
func set_fog(explored: Dictionary, visible_now: Dictionary, enabled: bool) -> void:
	if _fog_image == null:
		return
	for c in _grid.cells():
		_fog_image.set_pixel(c.x, c.y, Color(1.0 if explored.has(c) else 0.0, 1.0 if visible_now.has(c) else 0.0, 0.0))
	_fog_texture.update(_fog_image)
	for m in materials:
		m.set_shader_parameter("fog_on", 1.0 if enabled else 0.0)


func _bind_fog(m: ShaderMaterial) -> void:
	var cell := _board.world(Vector2i(1, 0)).x - _board.world(Vector2i.ZERO).x
	var origin := _board.world(Vector2i.ZERO)
	m.set_shader_parameter("fog_mask", _fog_texture)
	m.set_shader_parameter("fog_origin", Vector2(origin.x, origin.z))
	m.set_shader_parameter("fog_size", Vector2(_fog_size))
	m.set_shader_parameter("cell_size", cell)
	m.set_shader_parameter("fog_on", 0.0)
	materials.append(m)


## The grid lines' material: faint lines that stay out of unexplored cells.
func grid_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GRID
	m.set_shader_parameter("color", Color(mood.accent.lerp(Color(0.6, 0.75, 0.9), 0.6), 0.1))
	_bind_fog(m)
	return m


## A dark slab under the whole deck: unexplored cells (not drawn) read as darkness,
## not as holes onto the stars.
func _underlay(parent: Node3D) -> void:
	var lo := _board.world(Vector2i.ZERO)
	var hi := _board.world(_fog_size - Vector2i.ONE)
	var slab := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(hi.x - lo.x + HALF * 2.0, hi.z - lo.z + HALF * 2.0)
	slab.mesh = plane
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = mood.shadows * 0.35
	m.disable_fog = true
	slab.material_override = m
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slab.position = Vector3((lo.x + hi.x) / 2.0, -0.04, (lo.z + hi.z) / 2.0)
	parent.add_child(slab)


func _haze(parent: Node3D) -> void:
	if mood.haze_density <= 0.0:
		return
	var lo := _board.world(Vector2i.ZERO)
	var hi := _board.world(_fog_size - Vector2i.ONE)
	var vol := FogVolume.new()
	vol.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	vol.size = Vector3(hi.x - lo.x + HALF * 2.0, LAMP_HEIGHT, hi.z - lo.z + HALF * 2.0)
	vol.position = Vector3((lo.x + hi.x) / 2.0, LAMP_HEIGHT / 2.0, (lo.z + hi.z) / 2.0)
	var m := ShaderMaterial.new()
	m.shader = HAZE
	m.set_shader_parameter("albedo", mood.haze)
	m.set_shader_parameter("density", mood.haze_density)
	m.set_shader_parameter("height", LAMP_HEIGHT * 0.8)
	_bind_fog(m)
	vol.material = m
	parent.add_child(vol)


# --- Output -----------------------------------------------------------------------

func _commit(parent: Node3D) -> void:
	var specs := [
		[_plate, _lit(0.55, 0.45)], [_metal, _lit(0.4, 0.7)], [_dark, _lit(0.7, 0.3)],
		[_hazard, _lit(0.6, 0.2)], [_cyan, _glow()], [_amber, _glow()],
	]
	if hq:
		specs = [
			[_plate, _surface(0.5, 0.3, {"tread": 1.0, "grime": mood.grime, "scorch": mood.scorch, "wear": 0.25})],
			[_metal, _surface(0.45, 0.3, {"seams": 1.0, "grime": mood.grime * 0.8, "wear": 0.2})],
			[_dark, _surface(0.65, 0.4, {"grime": mood.grime * 0.6, "wear": 0.15})],
			[_hazard, _surface(0.6, 0.1, {"grime": mood.grime, "scorch": mood.scorch * 0.5, "wear": 0.8})],
			[_cyan, _surface(0.4, 0.0, {"glow": 1.0, "glow_energy": 3.0})],
			[_amber, _surface(0.4, 0.0, {"glow": 1.0, "glow_energy": 3.0})],
		]
	for spec in specs:
		var st: SurfaceTool = spec[0]
		var mesh := st.commit()
		if mesh.get_surface_count() > 0:
			var mi := BoardGeometry.mesh_node(parent, spec[1])
			mi.mesh = mesh
			if hq and (st == _cyan or st == _amber or st == _hazard):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _surface(roughness: float, metallic: float, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", metallic)
	for key: String in params:
		m.set_shader_parameter(key, params[key])
	_bind_fog(m)
	return m


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
