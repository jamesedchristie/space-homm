class_name LeaderPortrait
extends Control
## A procedural 3D bust of a faction leader, rendered in its own SubViewport (GL
## Compatibility friendly: no shadows, no post effects needed). Built from smooth
## primitives: a displaced-sphere head with eyes, brows, nose, lips and ears, a neck,
## a costume (PortraitCostume), per-species prosthetics, a painted backdrop
## (PortraitBackdrop) and three-point lighting in the empire's colours.
##
## Idle animation: breathing, head sway, blinking, glances; the mouth moves while
## `speaking` is set (the diplomacy screen turns it on during the typewriter reveal).
##
##   var portrait := LeaderPortrait.new()
##   portrait.setup(data.leaders["kesh"], empire_color)
##   portrait.set_speaking(true); portrait.set_mood("angry")

const LOOKS := {
	"human": {"head": Vector3(1.0, 1.0, 1.0), "jaw": 0.55, "brow": 0.2, "cheek": 0.3, "chin": 0.6, "eye_r": 0.0165,
			"iris_r": 0.0095, "eye_x": 0.035, "eye_y": 0.008, "lid": -27.0, "nose_len": 0.5, "nose_w": 1.0,
			"mouth_w": 1.15, "lip": 0.0053, "brow_hair": true, "ear": "round", "irid": 0.0},
	"veltari": {"head": Vector3(0.93, 1.07, 0.95), "jaw": 0.1, "brow": 0.0, "cheek": 0.6, "chin": 0.3, "eye_r": 0.0158,
			"iris_r": 0.0125, "eye_x": 0.033, "eye_y": 0.014, "lid": -19.0, "nose_len": 0.35, "nose_w": 0.7,
			"mouth_w": 0.8, "lip": 0.0035, "brow_hair": false, "ear": "pointed", "irid": 1.0},
	"kesh": {"head": Vector3(1.1, 1.0, 1.07), "jaw": 0.9, "brow": 0.9, "cheek": 0.85, "chin": 0.9, "eye_r": 0.0115,
			"iris_r": 0.0068, "eye_x": 0.034, "eye_y": 0.006, "lid": -11.0, "nose_len": 0.5, "nose_w": 1.2,
			"mouth_w": 1.2, "lip": 0.0055, "brow_hair": true, "ear": "small", "irid": 0.0, "brow_tilt": 12.0},
	"sorn": {"head": Vector3(0.9, 1.0, 0.95), "jaw": 0.25, "brow": 0.15, "cheek": 0.2, "chin": 0.2, "eye_r": 0.0185,
			"iris_r": 0.0158, "eye_x": 0.034, "eye_y": 0.012, "lid": -10.0, "nose_len": 0.1, "nose_w": 0.6,
			"mouth_w": 0.9, "lip": 0.0035, "brow_hair": false, "ear": "fin", "irid": 0.0},
}

const VIEW_SIZE := Vector2i(512, 640)
const MOODS := {
	"neutral": {"brow_roll": 0.0, "brow_lift": 0.0, "smile": 0.0},
	"angry": {"brow_roll": 24.0, "brow_lift": -0.004, "smile": -0.6},
	"pleased": {"brow_roll": -6.0, "brow_lift": 0.003, "smile": 0.9},
	"grim": {"brow_roll": 12.0, "brow_lift": -0.002, "smile": -0.25},
}

var leader: Dictionary = {}
var team_color := Color("3fb8d8")

var _viewport: SubViewport
var _container: SubViewportContainer
var _world: Node3D
var _camera: Camera3D
var _head: Node3D
var _torso: Node3D
var _backdrop: Node3D
var _lids: Array[Node3D] = []
var _gazes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _brow_sides: Array[float] = []
var _lip_halves: Array[Node3D] = []
var _lip_sides: Array[float] = []
var _lower_lip: Node3D
var _mouth_inside: Node3D
var _lid_open := -20.0
var _time := 0.0
var _blink_in := 2.0
var _blink_t := -1.0
var _glance_in := 1.5
var _glance := Vector2.ZERO
var _glance_target := Vector2.ZERO
var _speaking := false
var _mouth := 0.0
var _mood := "neutral"
var _mood_brow_roll := 0.0
var _mood_brow_lift := 0.0
var _mood_smile := 0.0
var _rng := RandomNumberGenerator.new()
var _shake := 0.0


## Head and shoulders only (small portraits such as hero cards). Set before setup().
var close_up := false


func _init() -> void:
	custom_minimum_size = Vector2(240, 300)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)
	# The bust fades into darkness at the bottom edge.
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.01, 0.015, 0.03, 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.0)
	gt.fill_to = Vector2(0, 1.0)
	gt.width = 4
	gt.height = 64
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_left = 0.0
	fade.anchor_right = 1.0
	fade.anchor_top = 0.72
	fade.anchor_bottom = 1.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	_rng.seed = 7


## Builds the bust from a leader definition (data/strategic/leaders.json).
## `empire_color` tints the rim lights and costume trim a little.
func setup(def: Dictionary, empire_color: Color = Color("3fb8d8")) -> void:
	leader = def
	team_color = empire_color
	if _world != null:
		_world.queue_free()
	_lids.clear()
	_gazes.clear()
	_brows.clear()
	_brow_sides.clear()
	_lip_halves.clear()
	_lip_sides.clear()
	_world = Node3D.new()
	_viewport.add_child(_world)
	var p: Dictionary = def.get("portrait", {})
	var look: String = p.get("look", "human")
	var shape: Dictionary = LOOKS.get(look, LOOKS["human"]).duplicate()
	for key: String in ["jaw", "brow", "crest"]:
		if p.has(key):
			shape[key] = float(p[key])
	var glow_color := PortraitKit.col(p, "glow", Color("5aa8ff"))
	_build_environment(p, glow_color)
	_backdrop = PortraitBackdrop.build(_world, p.get("backdrop", "bridge"), p)
	_torso = Node3D.new()
	_torso.position = Vector3(0, -0.215, 0)
	_world.add_child(_torso)
	_head = Node3D.new()
	_world.add_child(_head)
	_build_head(p, look, shape)
	PortraitCostume.build(_torso, _head, look, p, team_color)
	_camera = Camera3D.new()
	_camera.fov = 13.0 if close_up else 22.0
	_world.add_child(_camera)
	_camera.position = Vector3(0, -0.02 if close_up else -0.085, 2.05)
	_camera.rotation = Vector3.ZERO
	_set_mood("neutral", true)
	_blink_in = _rng.randf_range(1.5, 3.5)


func set_speaking(on: bool) -> void:
	_speaking = on


## "neutral", "angry", "pleased" or "grim".
func set_mood(mood: String) -> void:
	_set_mood(mood, false)


func _set_mood(mood: String, instant: bool) -> void:
	_mood = mood if MOODS.has(mood) else "neutral"
	if instant:
		var m: Dictionary = MOODS[_mood]
		_mood_brow_roll = m["brow_roll"]
		_mood_brow_lift = m["brow_lift"]
		_mood_smile = m["smile"]


## A quick nod/flinch used for reactions.
func shake_head() -> void:
	_shake = 1.0


func _build_environment(p: Dictionary, glow_color: Color) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = PortraitKit.col(p, "glow", Color("5aa8ff")).lerp(Color(0.5, 0.52, 0.6), 0.6)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	# Three-point lighting: warm key from the front-left, cool fill, coloured rims behind.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, -32, 0)
	key.light_color = Color(1.0, 0.93, 0.84)
	key.light_energy = 0.8
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 42, 0)
	fill.light_color = Color(0.62, 0.72, 1.0)
	fill.light_energy = 0.32
	_world.add_child(fill)
	var rim_a := DirectionalLight3D.new()
	rim_a.rotation_degrees = Vector3(-18, 148, 0)
	rim_a.light_color = glow_color
	rim_a.light_energy = 1.1
	_world.add_child(rim_a)
	var rim_b := DirectionalLight3D.new()
	rim_b.rotation_degrees = Vector3(-18, -148, 0)
	rim_b.light_color = team_color.lerp(glow_color, 0.4)
	rim_b.light_energy = 0.85
	_world.add_child(rim_b)


func _build_head(p: Dictionary, look: String, shape: Dictionary) -> void:
	var skin := PortraitKit.col(p, "skin", Color("d29a7c"))
	var lips := PortraitKit.col(p, "lips", Color("b4695f"))
	var eye_col := PortraitKit.col(p, "eyes", Color("4f7f9c"))
	var hair_col := PortraitKit.col(p, "hair", Color("3a2a1c"))
	var glow_color := PortraitKit.col(p, "glow", Color("5aa8ff"))
	var shade := Color(skin.r * 0.5, skin.g * 0.3, skin.b * 0.35).lerp(Color(0.3, 0.1, 0.12), 0.3)
	if look == "sorn":
		shade = Color(skin.r * 0.4, skin.g * 0.5, skin.b * 0.6)
	elif look == "veltari":
		shade = Color(0.5, 0.38, 0.7)
	var blush := Color(1.0, 0.82, 0.8) if look != "sorn" else Color(0.9, 0.95, 1.0)
	var hv := Node3D.new()
	hv.scale = shape["head"] * 1.1
	_head.add_child(hv)
	var built := PortraitHead.build(shape, blush, Color(0.6, 0.55, 0.6))
	var front: PackedVector3Array = built["front"]
	var skin_mat := PortraitKit.skin_material(skin, shade, glow_color.lerp(Color.WHITE, 0.35), float(shape["irid"]),
			0.5 if look == "veltari" else 0.28)
	if look == "sorn":
		skin_mat.set_shader_parameter("spec", 0.02)
		skin_mat.set_shader_parameter("rim_amount", 0.18)
	elif look == "kesh":
		skin_mat.set_shader_parameter("spec", 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = built["mesh"]
	mi.material_override = skin_mat
	hv.add_child(mi)
	# Neck.
	PortraitKit.cylinder(_head, 0.037, 0.046, 0.14, skin_mat, Vector3(0, -0.125, -0.006))
	var age: float = p.get("age", 0.5)
	var eye_r: float = shape["eye_r"]
	var ex: float = shape["eye_x"]
	var ey: float = shape["eye_y"]
	var sclera := Color(0.93, 0.92, 0.9) if look != "sorn" else Color(0.12, 0.13, 0.18)
	if look == "veltari":
		sclera = Color(0.8, 0.92, 1.0)
	var iris_glow := look == "veltari"
	var sclera_mat := PortraitKit.mat(sclera, 0.25)
	var iris_mat: Material = PortraitKit.glow(eye_col, 1.6) if iris_glow else PortraitKit.mat(eye_col, 0.35)
	var pupil_mat := PortraitKit.mat(Color(0.02, 0.02, 0.03), 0.2)
	var glint_mat := PortraitKit.glow(Color.WHITE, 3.0)
	_lid_open = float(shape["lid"])
	var cyber_side := 1.0 if p.get("cyber_eye", false) else 0.0
	for side: float in [-1.0, 1.0]:
		var sz := PortraitHead.surface_z(front, side * ex, ey)
		var eye := Node3D.new()
		eye.position = Vector3(side * ex, ey, sz - eye_r * 0.55)
		hv.add_child(eye)
		var ball := PortraitKit.sphere(eye, eye_r, sclera_mat, Vector3.ZERO, Vector3(1.0, 0.92, 1.0), Vector3.ZERO, 28)
		ball.name = "Ball"
		var gaze := Node3D.new()
		eye.add_child(gaze)
		_gazes.append(gaze)
		var ir: float = shape["iris_r"]
		var cyber: bool = cyber_side > 0.0 and side > 0.0
		var iris_col := Color("ff3a2a") if cyber else eye_col
		var cap_reach := asin(minf(ir / eye_r, 0.95))
		var iris_outer: Material = PortraitKit.glow(iris_col.darkened(0.25), 1.2) if iris_glow else PortraitKit.mat(iris_col.darkened(0.3), 0.4)
		var iris_inner: Material = PortraitKit.glow(iris_col.lightened(0.25), 1.8) if (iris_glow or cyber) else PortraitKit.mat(iris_col.lightened(0.12), 0.4)
		# The iris is a cap hugging the eyeball: a dark limbal ring, a lighter body, then the pupil.
		for layer in [[1.0, 1.004, iris_outer], [0.8, 1.006, iris_inner], [0.2 if iris_glow else 0.38, 1.008, pupil_mat]]:
			var cap := PortraitKit.add(gaze, PortraitKit.dome_mesh(eye_r * float(layer[1]), cap_reach * float(layer[0]), 28, 6), layer[2])
			cap.rotation_degrees = Vector3(90, 0, 0)
		var glint := PortraitKit.sphere(gaze, ir * 0.2, glint_mat, Vector3(-side * ir * 0.3 + ir * 0.25, ir * 0.42, eye_r * 1.004), Vector3(1, 1, 0.5), Vector3.ZERO, 10)
		glint.name = "Glint"
		if cyber:
			PortraitKit.torus(gaze, ir * 1.02, ir * 1.3, PortraitKit.mat(Color(0.3, 0.3, 0.34), 0.35, 0.8),
					Vector3(0, 0, eye_r * 0.96), Vector3(90, 0, 0))
		var lid := Node3D.new()
		eye.add_child(lid)
		PortraitKit.add(lid, PortraitKit.dome_mesh(eye_r * 1.1, PI * 0.5), skin_mat)
		lid.rotation_degrees = Vector3(_lid_open, 0, 0)
		_lids.append(lid)
		# Brow: a hair capsule on a pivot so moods can tilt it.
		var by := ey + 0.0245 + float(shape["brow"]) * 0.003
		var bz := PortraitHead.surface_z(front, side * (ex + 0.002), by)
		var pivot := Node3D.new()
		pivot.position = Vector3(side * (ex + 0.002), by, bz + 0.002)
		hv.add_child(pivot)
		pivot.set_meta("base_y", by)
		_brows.append(pivot)
		_brow_sides.append(side)
		if shape["brow_hair"]:
			var bt := 0.0032 + float(shape["brow"]) * 0.0035
			var bm := PortraitKit.mat(hair_col.lightened(0.05), 0.6)
			var b := PortraitKit.capsule(pivot, bt, 0.05 + float(shape["brow"]) * 0.006, bm, Vector3.ZERO, Vector3(0, 0, 90), Vector3(1, 1, 0.8))
			b.rotation_degrees = Vector3(-8, -side * 8, 90 + side * float(shape.get("brow_tilt", 0.0)))
		# Upper lid line: a dark lash line hugging the top of the eye.
		var lash := PortraitKit.capsule(hv, 0.0016, eye_r * 2.3, PortraitKit.mat(shade.darkened(0.55), 0.8),
				Vector3(side * ex, ey + eye_r * 0.86, sz - eye_r * 0.2), Vector3(-12, -side * 6, 90), Vector3(1, 1, 0.7))
		lash.name = "Lash"
		# Ears.
		_build_ear(hv, String(shape["ear"]), side, skin_mat, shade, p)
	_build_nose(hv, front, shape, skin_mat, shade)
	_build_mouth(hv, front, shape, lips, shade, look)
	_build_hair(hv, p, shape, hair_col, look)
	if look == "veltari":
		_build_crystals(hv, front, p, glow_color)
	if look == "kesh":
		_build_kesh_features(hv, front, p, skin_mat, shade, hair_col)
	if look == "sorn":
		_build_sorn_features(hv, front, p, skin_mat, shade, glow_color)
	if p.get("scar", false):
		var sy := -0.02
		var sc := PortraitKit.mat(Color(skin.r * 0.62, skin.g * 0.42, skin.b * 0.4), 0.5)
		var scar := PortraitKit.capsule(hv, 0.0016, 0.07, sc,
				Vector3(-0.041, sy, PortraitHead.surface_z(front, -0.041, sy) + 0.0008), Vector3(0, 8, 24))
		scar.scale = Vector3(1, 1, 0.5)


func _build_ear(hv: Node3D, style: String, side: float, skin_mat: Material, shade: Color, p: Dictionary) -> void:
	var x := side * PortraitHead.W * 0.985
	match style:
		"round":
			PortraitKit.sphere(hv, 0.021, skin_mat, Vector3(x, -0.006, -0.012), Vector3(0.3, 1.0, 0.62), Vector3(0, -side * 12, 0), 20)
		"pointed":
			var e := PortraitKit.cone(hv, 0.017, 0.09, skin_mat, Vector3(x + side * 0.006, 0.02, -0.014), Vector3(0, 0, -side * 58), 16)
			e.scale = Vector3(0.35, 1.0, 1.0)
		"small":
			PortraitKit.sphere(hv, 0.017, skin_mat, Vector3(x, -0.008, -0.01), Vector3(0.3, 1.0, 0.6), Vector3(0, -side * 12, 0), 18)
			var ring := PortraitKit.torus(hv, 0.0022, 0.0075, PortraitKit.mat(PortraitKit.col(p, "accent", Color("d9b44a")), 0.3, 0.8),
					Vector3(x + side * 0.003, -0.022, -0.01), Vector3(0, 90, 0))
			ring.name = "EarRing"
		"fin":
			for k in 3:
				PortraitKit.capsule(hv, 0.0035, 0.06 - k * 0.012, PortraitKit.mat(shade.lerp(Color(0.5, 0.55, 0.6), 0.5), 0.6),
						Vector3(x + side * 0.001, 0.0 - k * 0.003, -0.012 - k * 0.01), Vector3(0, 0, 0), Vector3(0.7, 1.0, 1.0))


func _build_nose(hv: Node3D, front: PackedVector3Array, shape: Dictionary, skin_mat: Material, shade: Color) -> void:
	var nl: float = shape["nose_len"]
	var nw: float = shape["nose_w"]
	var ty := -0.03
	var tz := PortraitHead.surface_z(front, 0.0, ty) + 0.003 + nl * 0.011
	var top := Vector3(0, 0.002, PortraitHead.surface_z(front, 0.0, 0.002) + 0.001)
	var tip := Vector3(0, ty, tz)
	var dir := (tip - top)
	var bridge := PortraitKit.cylinder(hv, 0.0045 * nw, 0.0098 * nw, dir.length(), skin_mat, (tip + top) * 0.5, Vector3.ZERO, 20)
	bridge.quaternion = Quaternion(Vector3.UP, -dir.normalized())
	PortraitKit.sphere(hv, 0.0108 * nw, skin_mat, tip, Vector3(1.0, 0.85, 1.0), Vector3.ZERO, 24)
	var dark := PortraitKit.mat(Color(0.1, 0.05, 0.06), 0.8)
	for side: float in [-1.0, 1.0]:
		PortraitKit.sphere(hv, 0.0085 * nw, skin_mat, Vector3(side * 0.0115 * nw, ty - 0.003, tz - 0.007), Vector3(1, 0.9, 0.9), Vector3.ZERO, 16)
		PortraitKit.sphere(hv, 0.003, dark, Vector3(side * 0.0068 * nw, ty - 0.0088, tz - 0.0055), Vector3(1.1, 0.6, 1), Vector3.ZERO, 10)


func _build_mouth(hv: Node3D, front: PackedVector3Array, shape: Dictionary, lips: Color, shade: Color, look: String) -> void:
	var my := -0.064
	var mw: float = shape["mouth_w"]
	var lr: float = shape["lip"]
	var lip_mat := PortraitKit.mat(lips, 0.45)
	var dark := PortraitKit.mat(Color(0.14, 0.04, 0.05), 0.9)
	var line_mat := PortraitKit.mat(lips.darkened(0.45), 0.7)
	# Mouth interior, visible only when the jaw drops.
	var mz := PortraitHead.surface_z(front, 0.0, my) - 0.003
	_mouth_inside = PortraitKit.sphere(hv, 0.014 * mw, dark, Vector3(0, my - 0.003, mz), Vector3(1.0, 0.05, 0.6), Vector3.ZERO, 16)
	if look != "sorn":
		var teeth := PortraitKit.capsule(hv, 0.0028, 0.022 * mw, PortraitKit.mat(Color(0.92, 0.9, 0.84), 0.3),
				Vector3(0, my - 0.0025, mz + 0.002), Vector3(0, 0, 90), Vector3(1, 0.7, 0.6))
		teeth.name = "Teeth"
	for side: float in [-1.0, 1.0]:
		var x := side * 0.0105 * mw
		var half := Node3D.new()
		half.position = Vector3(x, my, PortraitHead.surface_z(front, x, my) + 0.0012)
		hv.add_child(half)
		_lip_halves.append(half)
		_lip_sides.append(side)
		var c := PortraitKit.capsule(half, lr, 0.024 * mw, lip_mat, Vector3(side * 0.004 * mw, 0, 0), Vector3(0, -side * 22, 90))
		c.scale = Vector3(1.0, 1.0, 0.85)
	_lower_lip = Node3D.new()
	_lower_lip.position = Vector3(0, my - 0.0075, PortraitHead.surface_z(front, 0.0, my - 0.0075) + 0.0008)
	hv.add_child(_lower_lip)
	var ll := PortraitKit.capsule(_lower_lip, lr * 1.12, 0.034 * mw, lip_mat, Vector3.ZERO, Vector3(0, 0, 90))
	ll.scale = Vector3(1.0, 1.0, 0.85)
	# The mouth line between the lips.
	PortraitKit.capsule(hv, 0.0011, 0.04 * mw, line_mat, Vector3(0, my - 0.0033, PortraitHead.surface_z(front, 0.0, my - 0.0033) + 0.0022),
			Vector3(0, 0, 90), Vector3(1, 1, 0.5))


func _build_hair(hv: Node3D, p: Dictionary, shape: Dictionary, hair_col: Color, look: String) -> void:
	var style: String = p.get("hair_style", "none")
	if style == "none":
		return
	var hm := PortraitKit.hair_material(hair_col)
	var built := PortraitHead.build(shape, Color.WHITE, Color.WHITE)
	var shell := MeshInstance3D.new()
	shell.mesh = built["mesh"]
	shell.material_override = hm
	shell.scale = Vector3(1.04, 1.035, 1.05)
	shell.position = Vector3(0, 0.003, -0.002)
	hv.add_child(shell)
	var solid := PortraitKit.mat(hair_col, 0.4)
	match style:
		"short":
			hm.set_shader_parameter("temple_drop", 0.07)
			hm.set_shader_parameter("front_y", 0.074)
		"bun":
			hm.set_shader_parameter("temple_drop", 0.065)
			hm.set_shader_parameter("front_y", 0.076)
			hm.set_shader_parameter("back_y", -0.03)
			PortraitKit.sphere(hv, 0.042, solid, Vector3(0, 0.03, -0.108), Vector3(1.0, 0.95, 0.8), Vector3.ZERO, 28)
			PortraitKit.torus(hv, 0.0015, 0.0105, PortraitKit.mat(PortraitKit.col(p, "accent", Color("d9b44a")), 0.3, 0.8),
					Vector3(0, 0.03, -0.085), Vector3(90, 0, 0), Vector3(1.9, 1.9, 1.9))
		"long":
			hm.set_shader_parameter("back_y", -0.02)
			hm.set_shader_parameter("temple_drop", 0.02)
			for side: float in [-1.0, 1.0]:
				var strand := PortraitKit.cylinder(hv, 0.026, 0.046, 0.4, solid, Vector3(side * 0.07, -0.2, -0.05), Vector3(4, 0, side * -6), 20)
				strand.scale = Vector3(1.0, 1.0, 0.6)
			var back := PortraitKit.cylinder(hv, 0.07, 0.085, 0.42, solid, Vector3(0, -0.2, -0.075), Vector3(0, 0, 0), 24)
			back.scale = Vector3(1.0, 1.0, 0.55)
		"braids":
			hm.set_shader_parameter("back_y", -0.04)
			hm.set_shader_parameter("temple_drop", 0.02)
			hm.set_shader_parameter("front_y", 0.06)
			_build_braids(hv, solid, PortraitKit.col(p, "accent", Color("d36a2e")))
		"mohawk":
			shell.queue_free()
			for k in 11:
				var a := lerpf(-1.0, 1.0, k / 10.0)
				var side_off := 0.014 * (1 if k % 2 == 0 else -1)
				var spike := PortraitKit.cone(hv, 0.0085, 0.075 + 0.025 * sin(k / 10.0 * PI), solid,
						Vector3(side_off, 0.1 * cos(a) + 0.012, 0.09 * sin(a)), Vector3(a * 57.0, 0, side_off * 600.0), 10)
				spike.name = "Spike"


func _build_braids(hv: Node3D, hair: Material, bead: Color) -> void:
	var gold := PortraitKit.mat(bead, 0.3, 0.8)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var base := Vector3(side * (0.045 + k * 0.012), -0.01 - k * 0.012, -0.075 - k * 0.002)
			var drop := 0.2 + k * 0.06
			var segs := int(drop / 0.024)
			for s in segs:
				var t := float(s) / segs
				var sway := sin(t * 5.0) * 0.004
				var pos := base + Vector3(side * 0.014 * t + sway * side, -drop * t, 0.03 * t + 0.01 * k * t)
				var ball := PortraitKit.sphere(hv, 0.0105 - 0.0035 * t, hair, pos, Vector3(1.0, 0.8, 1.0), Vector3(0, 0, 25 * (1 if s % 2 == 0 else -1)), 12)
				ball.name = "Braid"
			var end := base + Vector3(side * 0.014, -drop, 0.03 + 0.01 * k)
			PortraitKit.torus(hv, 0.0018, 0.0075, gold, end + Vector3(0, 0.012, 0), Vector3(90, 0, 0))


func _build_crystals(hv: Node3D, front: PackedVector3Array, p: Dictionary, glow_color: Color) -> void:
	var cm := PortraitKit.glow(glow_color.lerp(Color.WHITE, 0.35), 1.25, 0.82)
	var core := PortraitKit.glow(Color.WHITE, 2.0, 0.9)
	# A crown of shards fanning up from the brow.
	var shards := [[0.0, 0.07, 0.0, 0.068], [-0.02, 0.064, 14.0, 0.05], [0.02, 0.064, -14.0, 0.05],
			[-0.04, 0.052, 30.0, 0.036], [0.04, 0.052, -30.0, 0.036]]
	for s in shards:
		var z := PortraitHead.surface_z(front, s[0], s[1])
		var c := PortraitKit.cylinder(hv, 0.0, 0.0072, s[3], cm, Vector3(s[0], s[1] + s[3] * 0.4, z + 0.004), Vector3(-12, 0, s[2]), 5)
		c.scale = Vector3(1.0, 1.0, 0.7)
		c.name = "Shard"
	PortraitKit.sphere(hv, 0.0042, core, Vector3(0, 0.054, PortraitHead.surface_z(front, 0.0, 0.054) + 0.003), Vector3.ONE, Vector3.ZERO, 4)
	# Temple ridges: short crystals sweeping back from the eyes.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var x := side * (0.056 + k * 0.006)
			var y := 0.036 - k * 0.011
			var z := PortraitHead.surface_z(front, x, y)
			var r := PortraitKit.cylinder(hv, 0.0, 0.0042, 0.026 - k * 0.004, cm, Vector3(x, y, z + 0.001),
					Vector3(0, -side * 55, -side * 82), 5)
			r.name = "Ridge"
		# Cheek facets.
		var cz := PortraitHead.surface_z(front, side * 0.048, -0.012)
		PortraitKit.sphere(hv, 0.0032, core, Vector3(side * 0.048, -0.012, cz + 0.001), Vector3.ONE, Vector3.ZERO, 4)


func _build_kesh_features(hv: Node3D, front: PackedVector3Array, p: Dictionary, skin_mat: Material, shade: Color, hair_col: Color) -> void:
	var ridge_mat := PortraitKit.mat(shade.lerp(PortraitKit.col(p, "skin", Color.WHITE), 0.55), 0.65)
	# Cheek ridges: short raised ribs along the cheekbone.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var x := side * (0.045 + k * 0.007)
			var y := -0.012 - k * 0.011
			var z := PortraitHead.surface_z(front, x, y)
			PortraitKit.capsule(hv, 0.0034, 0.024 - k * 0.003, ridge_mat, Vector3(x, y, z - 0.0005), Vector3(0, -side * 40, 82 * side), Vector3(1, 1, 0.75))
	# Tusks and horns.
	var bone := PortraitKit.mat(Color(0.86, 0.8, 0.66), 0.45)
	for side: float in [-1.0, 1.0]:
		var tz := PortraitHead.surface_z(front, side * 0.017, -0.074)
		PortraitKit.cone(hv, 0.0042, 0.02, bone, Vector3(side * 0.017, -0.066, tz + 0.001), Vector3(-8, 0, side * 6), 10)
	var horns: float = p.get("horns", 0.0)
	if horns > 0.0:
		for side: float in [-1.0, 1.0]:
			var h := PortraitKit.cone(hv, 0.012, 0.11 * horns, bone, Vector3(side * 0.074, 0.075, -0.012), Vector3(8, 0, -side * 55), 14)
			h.name = "Horn"
			var base := PortraitKit.cylinder(hv, 0.012, 0.015, 0.012, PortraitKit.mat(shade, 0.6), Vector3(side * 0.07, 0.07, -0.012), Vector3(0, 0, -side * 55), 14)
			base.name = "HornBase"


func _build_sorn_features(hv: Node3D, front: PackedVector3Array, p: Dictionary, skin_mat: Material, shade: Color, glow_color: Color) -> void:
	# Neck ridges are on the neck; a jewelled band circles the base of the crest.
	var accent := PortraitKit.col(p, "accent", Color("4dd0c8"))
	if not p.get("goggles", false):
		var band := PortraitKit.torus(hv, 0.0035, 0.0065, PortraitKit.mat(accent.darkened(0.4), 0.3, 0.7), Vector3(0, 0.07, -0.02), Vector3(-18, 0, 0), Vector3(1, 1, 1))
		band.scale = Vector3(14.0, 14.0, 13.0)
		PortraitKit.sphere(hv, 0.005, PortraitKit.glow(accent, 1.8), Vector3(0, 0.083, PortraitHead.surface_z(front, 0, 0.083) + 0.002), Vector3.ONE, Vector3.ZERO, 12)
	for k in 4:
		var r := PortraitKit.torus(_head, 0.0045, 0.0098, PortraitKit.mat(shade.lerp(PortraitKit.col(p, "skin", Color.WHITE), 0.4), 0.55),
				Vector3(0, -0.075 - k * 0.025, -0.006), Vector3.ZERO, Vector3(4.4 - k * 0.12, 4.4 - k * 0.12, 3.6))
		r.name = "NeckRidge"
	if p.get("goggles", false):
		var brass := PortraitKit.mat(Color("b08a3a"), 0.3, 0.85)
		var glass := PortraitKit.glow(Color("ffd27a"), 0.9, 0.6)
		var strap := PortraitKit.mat(Color("3a2418"), 0.7)
		for side: float in [-1.0, 1.0]:
			var gz := PortraitHead.surface_z(front, side * 0.032, 0.073)
			PortraitKit.torus(hv, 0.0026, 0.0135, brass, Vector3(side * 0.032, 0.076, gz + 0.004), Vector3(90, 0, 0))
			PortraitKit.cylinder(hv, 0.0125, 0.0125, 0.003, glass, Vector3(side * 0.032, 0.076, gz + 0.0035), Vector3(90, 0, 0), 20)
		PortraitKit.cylinder(hv, 0.0045, 0.0045, 0.02, brass, Vector3(0, 0.076, PortraitHead.surface_z(front, 0, 0.076) + 0.004), Vector3(0, 0, 90), 12)
		var s := PortraitKit.torus(hv, 0.002, 0.081, strap, Vector3(0, 0.054, -0.012), Vector3(-10, 0, 0), Vector3(1, 1, 1.18))
		s.scale = Vector3(1.0, 1.0, 1.18)


func _process(delta: float) -> void:
	if _head == null or not is_visible_in_tree():
		return
	_time += delta
	var t := _time
	# Breathing and sway.
	_torso.position.y = -0.215 + 0.0035 * sin(t * 1.7)
	_head.position.y = 0.0035 * sin(t * 1.7 - 0.4)
	var nod := 0.0
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.6, 0.0)
		nod = sin(_shake * 14.0) * 0.06 * _shake
	_head.rotation = Vector3(0.018 * sin(t * 0.63) + (0.025 if _speaking else 0.0) * sin(t * 6.0), 0.07 * sin(t * 0.41) + nod, 0.012 * sin(t * 0.53))
	_camera.position.x = 0.012 * sin(t * 0.3)
	if _backdrop != null:
		_backdrop.position.x = -0.02 * sin(t * 0.3)
	# Blink.
	_blink_in -= delta
	if _blink_in <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_in = _rng.randf_range(2.2, 5.5)
	var lid_angle := _lid_open
	if _blink_t >= 0.0:
		_blink_t += delta
		var k := _blink_t / 0.16
		var closed := sin(clampf(k, 0.0, 1.0) * PI)
		lid_angle = lerpf(_lid_open, 82.0, closed)
		if k >= 1.0:
			_blink_t = -1.0
	for lid in _lids:
		lid.rotation_degrees.x = lid_angle
	# Glances.
	_glance_in -= delta
	if _glance_in <= 0.0:
		_glance_in = _rng.randf_range(0.8, 2.6)
		_glance_target = Vector2(_rng.randf_range(-0.07, 0.07), _rng.randf_range(-0.04, 0.04))
	_glance = _glance.lerp(_glance_target, clampf(delta * 8.0, 0.0, 1.0))
	for g in _gazes:
		g.rotation = Vector3(-_glance.y, _glance.x, 0.0)
	# Mood: brows and lip corners.
	var m: Dictionary = MOODS[_mood]
	var kk := clampf(delta * 6.0, 0.0, 1.0)
	_mood_brow_roll = lerpf(_mood_brow_roll, m["brow_roll"], kk)
	_mood_brow_lift = lerpf(_mood_brow_lift, m["brow_lift"], kk)
	_mood_smile = lerpf(_mood_smile, m["smile"], kk)
	for i in _brows.size():
		var b := _brows[i]
		b.rotation_degrees.z = _brow_sides[i] * _mood_brow_roll * -1.0
		b.position.y = float(b.get_meta("base_y")) + _mood_brow_lift
	for i in _lip_halves.size():
		_lip_halves[i].rotation_degrees.z = -_lip_sides[i] * _mood_smile * 14.0
	# Mouth: open and close while speaking.
	var target := 0.0
	if _speaking:
		target = clampf(0.25 + 0.75 * absf(sin(t * 11.0)) * (0.55 + 0.45 * sin(t * 4.3 + 1.0)), 0.0, 1.0)
	_mouth = lerpf(_mouth, target, clampf(delta * 18.0, 0.0, 1.0))
	if _lower_lip != null:
		_lower_lip.position.y = -0.064 - 0.0075 - _mouth * 0.011
		_mouth_inside.scale.y = 0.05 + _mouth * 0.55
		_mouth_inside.position.y = -0.064 - 0.003 - _mouth * 0.0055
