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
const MISSION_RESOLVED := "mission_resolved"    # {anomaly, mission, fleet, success, heroes: {id: outcome}, xp, items, loyalty, traits, credits, alloys, research, intel: [planet names], loot_text}
const ANOMALY_CHANGED := "anomaly_changed"      # {anomaly, mission, name}
const ANOMALY_REMOVED := "anomaly_removed"      # {anomaly}

# Empire
const INCOME := "income"                        # {faction, income: {credits, alloys, research}}
const RESEARCH_SET := "research_set"            # {faction, tech}
const TECH_RESEARCHED := "tech_researched"      # {faction, tech}
const RESEARCH_WAITING := "research_waiting"    # {faction, tech, reason}: researched, but its cost_resources (exotic matter...) aren't in store yet
const BUILD_QUEUED := "build_queued"            # {planet, kind, item, turns}
const BUILDING_COMPLETED := "building_completed"  # {planet, building}
const SHIP_COMPLETED := "ship_completed"        # {planet, unit, fleet, ship}
const FLEET_CREATED := "fleet_created"          # {fleet, planet}
const FLEETS_MERGED := "fleets_merged"          # {fleet, into, name, into_name}: `fleet` joined `into` and is gone
const SYSTEM_PLUNDERED := "system_plundered"    # {planet, faction, previous_owner, credits, building, razed}
const DEN_CLEARED := "den_cleared"              # {planet, faction, loot: {credits, alloys}}
const DISCOVERY_FOUND := "discovery_found"      # {discovery, kind, name, fleet, faction, text, rewards}
const FLEET_SPLIT := "fleet_split"              # {fleet, new_fleet, ships: [names]}
const WAR_DECLARED := "war_declared"            # {faction, target}
const PEACE_SIGNED := "peace_signed"            # {factions: [a, b]}
const PEACE_REFUSED := "peace_refused"          # {faction, target, reason}
const GIFT_SENT := "gift_sent"                  # {faction, target, credits}
const FIRST_CONTACT := "first_contact"          # {factions: [a, b]}: each can now see the other for the first time
const PEACE_OFFERED := "peace_offered"          # {faction, target}: an AI faction offers a player-run one peace
const PEACE_OFFER_REFUSED := "peace_offer_refused"  # {faction: the answerer, target: the offerer}

# Empire depth
const POP_GREW := "pop_grew"                    # {planet, body, pop}
const MEGAPROJECT_STARTED := "megaproject_started"      # {planet, megaproject, faction}
const MEGAPROJECT_COMPLETED := "megaproject_completed"  # {planet, megaproject, faction}
const BUDGET_CRISIS := "budget_crisis"          # {faction, credits}: upkeep drove the treasury negative
const EVENT_OFFERED := "event_offered"          # {faction, event, planet}
const EVENT_RESOLVED := "event_resolved"        # {faction, event, choice, label, success, text, lines: [String]}
const MODIFIER_EXPIRED := "modifier_expired"    # {faction, modifier, name}

# The system layer: civilian ships, claiming, blockades
const CIVILIAN_DEPLOYED := "civilian_deployed"  # {planet, ship, fleet}: a ship left its fleet to work in the system
const FLEET_DISBANDED := "fleet_disbanded"      # {fleet, owner}: its last ship was deployed in a system
const CIVILIAN_MOVED := "civilian_moved"        # {planet, ship, body}
const CIVILIAN_DEPARTED := "civilian_departed"  # {planet, ship, fleet}
const ORDER_SET := "order_set"                  # {fleet, ship, planet, body, action, item}
const ORDER_FAILED := "order_failed"            # {fleet, ship, planet, reason}
const JOB_STARTED := "job_started"              # {planet, ship, body, building, turns}
const JOB_COMPLETED := "job_completed"          # {planet, ship, body, building, faction, claimed: bool}
const JOB_CANCELLED := "job_cancelled"          # {planet, ship, building, refund: {resource: n}, reason}
const COLONY_FOUNDED := "colony_founded"        # {planet, body, faction, claimed: bool, capital: bool}
const SYSTEM_CLAIMED := "system_claimed"        # {planet, faction, how: "colony"|"outpost"}
const CIVILIANS_LOST := "civilians_lost"        # {planet, faction, ships: [names]}: deployed ships lost with their system
const SYSTEM_INVADED := "system_invaded"        # {planet, faction, previous_owner, fleet}: troops landed
const BLOCKADE_STARTED := "blockade_started"    # {planet, faction, owner}
const BLOCKADE_LIFTED := "blockade_lifted"      # {planet, faction}

# System-scale campaigns (one star system on the map, every body its own Planet)
const BODY_SURVEYED := "body_surveyed"          # {faction, planet, traits: [ids]}: a ship of the faction came close
