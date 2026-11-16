class_name GalaxyBoard
extends Node
## What the galaxy screen needs from a view of the galaxy map. The screen keeps
## all turn, input and HUD logic and talks to the board in terms of cells and
## ids, so the 2D (GalaxyBoard2D) and 3D (GalaxyBoard3D) maps are
## interchangeable. Methods returning void may be awaited (animations).

var engine: GalaxyEngine
var data: DataRegistry
var player_faction := ""


func setup(p_engine: GalaxyEngine, p_data: DataRegistry, p_player_faction: String) -> void:
	engine = p_engine
	data = p_data
	player_faction = p_player_faction


## Removes everything this board created (before switching views).
func teardown() -> void:
	pass


## Brings fleets, planets, anomalies and fog in line with the engine state, as
## seen by the player (visible_now: cells in sensor range; explored: ever seen).
func sync(_visible_now: Dictionary, _explored: Dictionary, _selected_fleet: String) -> void:
	pass


## Whether the fleet's marker is currently shown.
func is_fleet_shown(_fleet_id: String) -> bool:
	return false


## path: cells from start to end. Shows the fleet while it moves.
func move_fleet(_fleet_id: String, _path: Array) -> void:
	pass


## Explodes the fleet's marker if it is shown.
func destroy_fleet(_fleet_id: String) -> void:
	pass


func refresh_planet(_planet_id: String) -> void:
	pass


func float_text_at_fleet(_fleet_id: String, _text: String, _color: Color) -> void:
	pass


func float_text_at_planet(_planet_id: String, _text: String, _color: Color) -> void:
	pass


## A ping on the map (e.g. where a battle starts).
func pulse(_cell: Vector2i, _color: Color) -> void:
	pass


func set_highlights(_move: Array[Vector2i], _attack: Array[Vector2i], _path: Array[Vector2i]) -> void:
	pass


func set_hover(_cell: Variant) -> void:
	pass


func set_active_cell(_cell: Variant) -> void:
	pass


func set_selected_fleet(_fleet_id: String) -> void:
	pass


## Grid cell under the mouse, or null.
func cell_at_mouse() -> Variant:
	return null


## Frame the map inside this screen rectangle (the area not covered by HUD).
func fit(_area: Rect2) -> void:
	pass


## Camera controls etc. Return true if the event was used.
func handle_input(_event: InputEvent) -> bool:
	return false
