class_name BattleBoard
extends Node
## What the battle screen needs from a view of the battlefield. The screen
## keeps all turn, input and HUD logic and talks to the board only in terms of
## cells and unit ids, so 2D (BattleBoard2D) and 3D (BattleBoard3D) views are
## interchangeable, even mid-battle.
## Methods returning void may be awaited (animations).

var engine: BattleEngine
var data: DataRegistry


func setup(p_engine: BattleEngine, p_data: DataRegistry, _floor_style: String) -> void:
	engine = p_engine
	data = p_data


## Removes everything this board created (before switching views).
func teardown() -> void:
	pass


func add_unit(_u: BattleUnit) -> void:
	pass


## path: cells from start to end. animate=false just places the unit.
func move_unit(_unit_id: String, _path: Array, _animate: bool) -> void:
	pass


func face_unit(_unit_id: String, _cell: Vector2i) -> void:
	pass


## Ignores units the board hasn't been given yet.
func refresh_unit(_u: BattleUnit, _visible: bool) -> void:
	pass


func set_unit_values(_unit_id: String, _hull: int, _shields: int) -> void:
	pass


func set_unit_visible(_unit_id: String, _visible: bool) -> void:
	pass


func set_active_unit(_unit_id: String) -> void:
	pass


func unit_hit(_unit_id: String, _source_id: String, _shield_hit: bool) -> void:
	pass


func destroy_unit(_unit_id: String, _big: bool) -> void:
	pass


## Floating text above a unit; `rise` lifts it further (stacked messages).
func float_text(_unit_id: String, _text: String, _color: Color, _rise: float = 0.0) -> void:
	pass


## kind: projectile | beam | torpedo | pulse | self | melee (lunge at an adjacent target). radius in cells.
func play_ability(_kind: String, _source_id: String, _target: Vector2i, _color: Color, _radius: int, _laser: String) -> void:
	pass


func play_sound(_key: String) -> void:
	pass


func shake(_strength: float) -> void:
	pass


func set_highlights(_reach: Array[Vector2i], _targets: Array[Vector2i], _area: Array[Vector2i], _path: Array[Vector2i]) -> void:
	pass


func set_hover(_cell: Variant) -> void:
	pass


func set_active_cell(_cell: Variant) -> void:
	pass


func set_fog(_explored: Dictionary, _visible: Dictionary) -> void:
	pass


func set_markers(_markers: Dictionary) -> void:
	pass


## Grid cell under the mouse, or null.
func cell_at_mouse() -> Variant:
	return null


## Frame the battlefield inside this screen rectangle (the area not covered by HUD).
func fit(_area: Rect2) -> void:
	pass


## Camera controls etc. Return true if the event was used.
func handle_input(_event: InputEvent) -> bool:
	return false
