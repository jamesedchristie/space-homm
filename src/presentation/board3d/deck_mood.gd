class_name DeckMood
extends RefCounted
## How a station deck looks on the high-quality renderer (Forward+): the map
## JSON's optional "mood" object, with defaults for a plain station interior.
## The classic look (Compatibility renderer) ignores it.
##
##   "mood": {
##     "ambient": "#2a3550", "ambient_energy": 0.3,   fill light in the shadows
##     "light": "#cfe0ff", "light_energy": 1.0,       ceiling lamps (colour, brightness scale)
##     "accent": "#4ad8ff", "accent2": "#ffb347",     light strips, screens, status lights
##     "haze": "#6a7a90", "haze_density": 0.05,       volumetric haze in the rooms (light shafts)
##     "shadows": "#06101c", "highlights": "#fff4e6", colour grade: tint of the darks / the brights
##     "exposure": 1.0, "saturation": 1.0,
##     "emergency": 0.0,   0..1: share of rooms with a pulsing red emergency light
##     "flicker": 0.0,     0..1: share of ceiling lamps that stutter (failing power)
##     "fires": 0,         small fires burning on the deck (wrecks)
##     "grime": 0.4, "scorch": 0.0,   floor dirt; share of cells with blast scorch marks
##     "props": "cargo"    cover dressing: cargo, lab, industrial, derelict, wreck
##   }

var ambient := Color(0.24, 0.3, 0.42)
var ambient_energy := 0.2
var light := Color(0.85, 0.92, 1.0)
var light_energy := 1.0
var accent := Color(0.3, 0.85, 1.0)
var accent2 := Color(1.0, 0.7, 0.3)
var haze := Color(0.45, 0.52, 0.62)
var haze_density := 0.025
var shadows := Color(0.03, 0.05, 0.09)
var highlights := Color(1.0, 0.97, 0.93)
var exposure := 1.0
var saturation := 1.0
var emergency := 0.0
var flicker := 0.0
var fires := 0
var grime := 0.4
var scorch := 0.0
var props := "cargo"


static func from_map(map_def: Dictionary) -> DeckMood:
	var m := DeckMood.new()
	var d: Dictionary = map_def.get("mood", {})
	m.ambient = _color(d, "ambient", m.ambient)
	m.ambient_energy = float(d.get("ambient_energy", m.ambient_energy))
	m.light = _color(d, "light", m.light)
	m.light_energy = float(d.get("light_energy", m.light_energy))
	m.accent = _color(d, "accent", m.accent)
	m.accent2 = _color(d, "accent2", m.accent2)
	m.haze = _color(d, "haze", m.haze)
	m.haze_density = float(d.get("haze_density", m.haze_density))
	m.shadows = _color(d, "shadows", m.shadows)
	m.highlights = _color(d, "highlights", m.highlights)
	m.exposure = float(d.get("exposure", m.exposure))
	m.saturation = float(d.get("saturation", m.saturation))
	m.emergency = clampf(float(d.get("emergency", m.emergency)), 0.0, 1.0)
	m.flicker = clampf(float(d.get("flicker", m.flicker)), 0.0, 1.0)
	m.fires = int(d.get("fires", m.fires))
	m.grime = clampf(float(d.get("grime", m.grime)), 0.0, 1.0)
	m.scorch = clampf(float(d.get("scorch", m.scorch)), 0.0, 1.0)
	m.props = str(d.get("props", m.props))
	return m


static func _color(d: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = d.get(key)
	return Color(str(v)) if v is String and Color.html_is_valid(str(v)) else fallback


## The colour grade as a per-channel curve (Environment.adjustment_color_correction):
## the darks lean toward `shadows`, the brights toward `highlights`.
func grade_texture() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0))
	g.set_color(1, highlights)
	var lift := shadows * 2.2
	g.add_point(0.18, Color(0.18, 0.18, 0.18).lerp(lift, 0.45))
	g.add_point(0.55, Color(0.55, 0.55, 0.55).lerp(highlights * 0.55, 0.3))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	tex.use_hdr = false
	return tex
