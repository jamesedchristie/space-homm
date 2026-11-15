class_name GalaxyEvents
extends RefCounted
## Event types emitted by GalaxyEngine. Each event is a Dictionary with "type".

const CAMPAIGN_STARTED := "campaign_started"    # {seed}
const TURN_STARTED := "galaxy_turn_started"     # {turn, faction}
const TURN_ENDED := "galaxy_turn_ended"         # {turn, faction}
const FLEET_MOVED := "fleet_moved"              # {fleet, path: [Vector2i], moves_left}
const FLEET_REPAIRED := "fleet_repaired"        # {fleet, amount, planet}
const PLANET_CAPTURED := "planet_captured"      # {planet, faction, previous_owner, fleet}
const BATTLE_TRIGGERED := "battle_triggered"    # {attacker, defender, cell, ambush: bool}
const BATTLE_RESOLVED := "battle_resolved"      # {attacker, defender, attacker_name, defender_name, cell, winner, losses: {fleet id: [ship names]}, rounds}
const FLEET_DESTROYED := "fleet_destroyed"      # {fleet, owner, name}
const FACTION_ELIMINATED := "faction_eliminated"  # {faction}
const CAMPAIGN_ENDED := "campaign_ended"        # {winner, reason}
