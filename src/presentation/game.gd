extends Node
## Top-level flow. Owns the galaxy screen and swaps in a tactical battle screen
## when the player chooses to fight, then hands the result back.
## Later: main menu, save/load and mission screens hang off here too.

const GALAXY_SCENE := preload("res://src/presentation/strategic/galaxy_screen.tscn")
const BATTLE_SCENE := preload("res://src/presentation/tactical/battle_screen.tscn")

var galaxy: Node
var battle: Node


func _ready() -> void:
	galaxy = GALAXY_SCENE.instantiate()
	galaxy.battle_requested.connect(func(scenario: Dictionary, battle_seed: int) -> void:
		_show_battle.call_deferred(scenario, battle_seed))
	add_child(galaxy)


func _show_battle(scenario: Dictionary, battle_seed: int) -> void:
	remove_child(galaxy)  # keeps it alive with all its state, just off-screen
	battle = BATTLE_SCENE.instantiate()
	battle.configure(scenario, battle_seed)
	battle.autoplay = galaxy.autoplay
	battle.battle_finished.connect(func(engine: BattleEngine) -> void:
		_return_to_galaxy.call_deferred(engine), CONNECT_ONE_SHOT)
	add_child(battle)


func _return_to_galaxy(engine: BattleEngine) -> void:
	remove_child(battle)
	battle.queue_free()
	battle = null
	add_child(galaxy)
	galaxy.on_battle_finished(engine)
