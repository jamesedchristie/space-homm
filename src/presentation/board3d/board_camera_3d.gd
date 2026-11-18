class_name BoardCamera3D
extends Node3D
## Camera rig for 2.5D boards: looks down at `pivot` from `pitch`, orbiting
## by `yaw` at `distance`. Mouse wheel zooms, middle-drag or arrow keys pan,
## right-drag or the rotate keys turn the view. fit() frames a board inside the
## part of the screen the HUD leaves free.

var camera: Camera3D
var pivot := Vector3.ZERO
var pitch := deg_to_rad(52.0)
var yaw := 0.0
var distance := 14.0
var min_distance := 4.0
var max_distance := 70.0
var rotate_left_key := KEY_Q
var rotate_right_key := KEY_E

var _area := Rect2()
var _base_offset := Vector2.ZERO
var _panning := false
var _rotating := false


func _enter_tree() -> void:
	# Screens leave and re-enter the tree (galaxy <-> battle): take the view back.
	camera.make_current.call_deferred()


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 300.0
	add_child(camera)


## Frames the box lo..hi (world XZ) inside `area` (screen pixels).
## margin is extra world units around the board (perspective makes near rows wider).
func fit(lo: Vector3, hi: Vector3, area: Rect2, margin: Vector2 = Vector2(3.5, 2.5)) -> void:
	_area = area
	pivot = Vector3((lo.x + hi.x) / 2.0, 0.0, (lo.z + hi.z) / 2.0)
	var screen := camera.get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(camera.fov) / 2.0)
	var width := (hi.x - lo.x) + margin.x
	var depth := (hi.z - lo.z) + margin.y
	var d_w := (width * screen.x / area.size.x) / (2.0 * tan_half * screen.x / screen.y)
	# Near rows are closer to the camera and take more height than sin(pitch) suggests.
	var d_h := (depth * sin(pitch) * 1.3 * screen.y / area.size.y) / (2.0 * tan_half)
	distance = clampf(maxf(d_w, d_h) * 1.12, min_distance, max_distance)
	update()


## The screen rectangle the board is framed in (last fit()).
func get_area() -> Rect2:
	return _area


func update() -> void:
	if not camera.is_inside_tree():
		return
	var offset := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance
	camera.look_at_from_position(pivot + offset, pivot, Vector3.UP)
	# Shift the view so the pivot sits in the middle of the HUD-free area.
	if _area.size != Vector2.ZERO:
		var screen := camera.get_viewport().get_visible_rect().size
		var world_per_px := 2.0 * distance * tan(deg_to_rad(camera.fov) / 2.0) / screen.y
		var d := _area.get_center() - screen / 2.0
		_base_offset = Vector2(-d.x, d.y) * world_per_px
		camera.h_offset = _base_offset.x
		camera.v_offset = _base_offset.y


## World point on the horizontal plane y = plane_y under the mouse, or null.
func pick(plane_y: float = 0.0) -> Variant:
	var mp := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return null
	var t := (plane_y - origin.y) / dir.y
	return origin + dir * t if t >= 0.0 else null


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = maxf(distance * 0.9, min_distance)
					update()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = minf(distance * 1.1, max_distance)
					update()
				return true
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				return true
			MOUSE_BUTTON_RIGHT:
				# Don't consume: screens still use right-click to cancel.
				_rotating = event.pressed
	elif event is InputEventMouseMotion:
		if _panning:
			_pan(-event.relative * distance * 0.0016)
			return true
		if _rotating and event.relative != Vector2.ZERO:
			# Sideways turns the view, up/down tilts it.
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.005, deg_to_rad(22.0), deg_to_rad(80.0))
			update()
			return true
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			rotate_left_key:
				_turn(-PI / 4.0)
				return true
			rotate_right_key:
				_turn(PI / 4.0)
				return true
			KEY_LEFT:
				_pan(Vector2(-0.8, 0))
				return true
			KEY_RIGHT:
				_pan(Vector2(0.8, 0))
				return true
			KEY_UP:
				_pan(Vector2(0, -0.8))
				return true
			KEY_DOWN:
				_pan(Vector2(0, 0.8))
				return true
	return false


func shake(strength: float) -> void:
	var tw := create_tween()
	for i in 6:
		var o := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(camera, "h_offset", _base_offset.x + o.x, 0.035)
		tw.parallel().tween_property(camera, "v_offset", _base_offset.y + o.y, 0.035)
	tw.tween_property(camera, "h_offset", _base_offset.x, 0.04)
	tw.parallel().tween_property(camera, "v_offset", _base_offset.y, 0.04)


func _pan(screen_delta: Vector2) -> void:
	pivot += Vector3.RIGHT.rotated(Vector3.UP, yaw) * screen_delta.x + Vector3.BACK.rotated(Vector3.UP, yaw) * screen_delta.y
	update()


func _turn(amount: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(y: float) -> void:
		yaw = y
		update(), yaw, yaw + amount, 0.25).set_trans(Tween.TRANS_SINE)
