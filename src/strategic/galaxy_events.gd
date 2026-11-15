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

# Heroes and missions
const HERO_ASSIGNED := "hero_assigned"          # {hero, fleet}
const HERO_UNASSIGNED := "hero_unassigned"      # {hero, planet}
const ITEM_EQUIPPED := "item_equipped"          # {hero, slot, item, previous}
const HERO_LEVELED := "hero_leveled"            # {hero, level, skills: [ability ids]}
const HERO_RETURNED := "hero_returned"          # {hero}
const HERO_INJURED := "hero_injured"            # {hero, until}
const HERO_CAPTURED := "hero_captured"          # {hero}
const HERO_KILLED := "hero_killed"              # {hero}
const HERO_FREED := "hero_freed"                # {hero}
const MISSION_OFFERED := "mission_offered"      # {anomaly, fleet, mission}
const MISSION_DECLINED := "mission_declined"    # {anomaly, fleet}
const MISSION_RESOLVED := "mission_resolved"    # {anomaly, mission, fleet, success, heroes: {id: outcome}, xp, items, loyalty, traits}
const ANOMALY_CHANGED := "anomaly_changed"      # {anomaly, mission, name}
const ANOMALY_REMOVED := "anomaly_removed"      # {anomaly}
