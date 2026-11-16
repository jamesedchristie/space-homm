class_name GameSettings
extends RefCounted
## Player preferences, stored in user://settings.cfg and applied at startup:
## fullscreen, master volume, and whether the galaxy map and battles open in
## 3D or 2D (V still toggles in game, and the choice is remembered).

const PATH := "user://settings.cfg"

static var fullscreen := false
## 0..1
static var volume := 0.8
static var galaxy_view := "3d"
static var battle_view := "3d"
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	volume = clampf(float(cfg.get_value("audio", "volume", volume)), 0.0, 1.0)
	galaxy_view = _view(cfg.get_value("display", "galaxy_view", galaxy_view))
	battle_view = _view(cfg.get_value("display", "battle_view", battle_view))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "galaxy_view", galaxy_view)
	cfg.set_value("display", "battle_view", battle_view)
	cfg.set_value("audio", "volume", volume)
	cfg.save(PATH)


## Pushes the settings into the engine (window mode, audio bus).
static func apply() -> void:
	ensure_loaded()
	if OS.get_name() != "Web" and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


static func toggle_fullscreen() -> void:
	ensure_loaded()
	fullscreen = not fullscreen
	apply()
	save()


static func _view(value: Variant) -> String:
	return "2d" if str(value) == "2d" else "3d"
