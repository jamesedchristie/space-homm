class_name FxLayer
extends Node2D
## Combat effects: laser bolts, glowing beams, torpedoes, additive explosions
## with particle sparks, impact flashes, floating numbers and sound.
## Which effect an ability plays comes from its JSON "fx" field; its color
## from the damage type (Palette.DAMAGE_LASERS picks the laser sprite).

const ASSETS := "res://assets/kenney_space_shooter/"
const FLASH_TEXTURE := preload("res://assets/kenney_space_shooter/effects/star2.png")
const SPARK_TEXTURE := preload("res://assets/kenney_space_shooter/effects/star1.png")
const SOUNDS := {
	"projectile": "sfx/sfx_laser1.ogg",
	"beam": "sfx/sfx_laser2.ogg",
	"torpedo": "sfx/sfx_zap.ogg",
	"pulse": "sfx/sfx_zap.ogg",
	"self": "sfx/sfx_shieldUp.ogg",
	"explosion": "sfx/sfx_shieldDown.ogg",
}
const SOUND_VOLUME_DB := -12.0

var _additive := CanvasItemMaterial.new()
var _streams := {}


func _init() -> void:
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


## Plays an ability effect and returns when the shot lands.
## laser: "Blue" | "Green" | "Red" sprite set (see Palette.DAMAGE_LASERS).
func play(kind: String, from: Vector2, to: Vector2, color: Color, blast_radius: float = 0.0, laser: String = "Blue") -> void:
	play_sound(kind)
	match kind:
		"beam":
			await _beam(from, to, color, 4.0)
			_impact(to, color, 0.6, laser)
		"torpedo":
			await _bolt(from, to, laser, 1.6, 420.0)
			explode(to, maxf(blast_radius, 24.0) / 28.0, color)
			await _ring(to, maxf(blast_radius, 24.0), color)
		"pulse":
			await _beam(from, to, color, 2.0)
			await _ring(to, 30.0, color)
		"self":
			_flash(from, 1.2, color)
			await _ring(from, 36.0, color)
		_:
			await _bolt(from, to, laser, 1.0, 900.0)
			_impact(to, color, 0.5, laser)


## Fiery burst with sparks: ships destroyed, torpedo detonations.
func explode(at: Vector2, size: float = 1.0, tint: Color = Color(1.0, 0.6, 0.25)) -> void:
	_flash(at, 2.2 * size, Color(1.0, 0.85, 0.6))
	var sparks := CPUParticles2D.new()
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = int(28 * clampf(size, 0.6, 2.0))
	sparks.lifetime = 0.8
	sparks.spread = 180.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 50.0 * size
	sparks.initial_velocity_max = 170.0 * size
	sparks.damping_min = 60.0
	sparks.damping_max = 120.0
	sparks.texture = SPARK_TEXTURE
	sparks.scale_amount_min = 0.10
	sparks.scale_amount_max = 0.35
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
	ramp.set_color(1, Color(tint.darkened(0.5), 0.0))
	ramp.add_point(0.35, Color(tint, 0.9))
	sparks.color_ramp = ramp
	sparks.material = _additive
	sparks.position = at
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.5).timeout.connect(sparks.queue_free)
	_ring(at, 34.0 * size, tint)


func float_text(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(160, 24)
	label.position = at + Vector2(-80, -48)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 34.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.chain().tween_callback(label.queue_free)


func play_sound(key: String) -> void:
	if not SOUNDS.has(key):
		return
	if not _streams.has(key):
		_streams[key] = load(ASSETS + SOUNDS[key])
	var player := AudioStreamPlayer.new()
	player.stream = _streams[key]
	player.volume_db = SOUND_VOLUME_DB
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# --- Pieces -------------------------------------------------------------------

func _bolt(from: Vector2, to: Vector2, laser: String, size: float, speed: float) -> void:
	var bolt := Sprite2D.new()
	bolt.texture = load(ASSETS + "lasers/laser%s01.png" % laser)
	bolt.scale = Vector2(0.6, 0.6) * size
	bolt.rotation = (to - from).angle() + PI / 2.0
	bolt.position = from
	bolt.material = _additive
	add_child(bolt)
	var tw := create_tween()
	tw.tween_property(bolt, "position", to, maxf(0.12, from.distance_to(to) / speed))
	await tw.finished
	bolt.queue_free()


func _beam(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var glow := Line2D.new()
	glow.points = PackedVector2Array([from, to])
	glow.width = width * 3.0
	glow.default_color = Color(color, 0.35)
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.material = _additive
	var core := Line2D.new()
	core.points = glow.points
	core.width = width * 0.6
	core.default_color = color.lightened(0.6)
	core.material = _additive
	add_child(glow)
	add_child(core)
	var tw := create_tween().set_parallel()
	tw.tween_property(glow, "modulate:a", 0.0, 0.35)
	tw.tween_property(core, "modulate:a", 0.0, 0.25)
	tw.tween_property(glow, "width", width * 1.2, 0.35)
	await tw.finished
	glow.queue_free()
	core.queue_free()


func _impact(at: Vector2, color: Color, size: float, laser: String) -> void:
	var hit := Sprite2D.new()
	hit.texture = load(ASSETS + "lasers/laser%s08.png" % laser)
	hit.position = at
	hit.scale = Vector2(0.5, 0.5) * size
	hit.rotation = randf() * TAU
	hit.material = _additive
	add_child(hit)
	var tw := hit.create_tween().set_parallel()
	tw.tween_property(hit, "scale", Vector2(1.1, 1.1) * size, 0.25)
	tw.tween_property(hit, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(hit.queue_free)


func _flash(at: Vector2, size: float, color: Color) -> void:
	var f := Sprite2D.new()
	f.texture = FLASH_TEXTURE
	f.position = at
	f.scale = Vector2(0.4, 0.4) * size
	f.modulate = color
	f.material = _additive
	add_child(f)
	var tw := f.create_tween().set_parallel()
	tw.tween_property(f, "scale", Vector2(1.2, 1.2) * size, 0.3)
	tw.tween_property(f, "rotation", 0.8, 0.3)
	tw.tween_property(f, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(f.queue_free)


func _ring(at: Vector2, radius: float, color: Color) -> void:
	var ring := Line2D.new()
	ring.points = _circle(radius, 32)
	ring.closed = true
	ring.width = 3.0
	ring.default_color = Color(color, 0.8)
	ring.material = _additive
	ring.position = at
	ring.scale = Vector2(0.2, 0.2)
	add_child(ring)
	var tw := create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	await tw.finished
	ring.queue_free()


func _circle(radius: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		pts.append(Vector2.from_angle(TAU * i / segments) * radius)
	return pts
