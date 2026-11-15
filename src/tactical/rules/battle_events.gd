class_name BattleEvents
extends RefCounted
## Names of the events the engine emits. Every event is a Dictionary with a
## "type" key plus the fields listed here. The presentation layer animates them;
## logs, replays and stats can consume the same stream.

const BATTLE_STARTED := "battle_started"      # {}
const ROUND_STARTED := "round_started"        # {round, order: [unit ids]}
const TURN_STARTED := "turn_started"          # {unit, ap}
const TURN_SKIPPED := "turn_skipped"          # {unit, reason}
const TURN_ENDED := "turn_ended"              # {unit}
const UNIT_MOVED := "unit_moved"              # {unit, path: [Vector2i], cost, ap}
const ABILITY_USED := "ability_used"          # {unit, ability, target: Vector2i, affected: [unit ids]}
const DAMAGE_DEALT := "damage_dealt"          # {source, target, damage_type, shield_damage, hull_damage, shields, hull}
const HEALED := "healed"                      # {target, stat, amount, value}
const STATUS_APPLIED := "status_applied"      # {target, status, duration, source}
const STATUS_RESISTED := "status_resisted"    # {target, status}
const STATUS_EXPIRED := "status_expired"      # {target, status}
const UNIT_DESTROYED := "unit_destroyed"      # {unit, by}
const BATTLE_ENDED := "battle_ended"          # {winner, reason}
