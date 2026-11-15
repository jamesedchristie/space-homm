# Architecture

## Goals

1. **One tactical engine** for fleet battles, ground and space-station squad missions,
   exploration missions and single-ship missions. Only the map, the scale, the units
   and the objectives change.
2. **Content is data.** Units, abilities, statuses, terrain, maps and scenarios are JSON.
   Mechanics are a small set of code primitives that content composes.
3. **Rules are testable without the game running.** The engine is plain GDScript objects
   (`RefCounted`), not scene nodes, so it runs headless in tests, in auto-resolve and in
   balance simulations.

## The tactical engine in one picture

```
            commands                         events
 Player UI ──────────┐                ┌──────────────► BattleScreen (animate, log)
 RuleBasedAI ────────┼──► BattleEngine ┤
 AutoResolver ───────┘   (validate,    └──────────────► tests / replays / stats
                          apply rules)
                              │
                         BattleState  (grid, units, turn queue, seeded RNG, objectives)
```

If you know Redux, it works the same way: `BattleState` is the store, commands are
actions, `BattleEngine.submit()` is the reducer, and the returned events are what
subscribers render. The differences:

- `submit()` validates first and returns `CommandResult { ok, error, events }`.
- **Queries** (`reachable_cells`, `ability_targets`, `preview_ability`, ...) are the
  selectors. UI and AI use the same ones, so the AI can never see more than the player.
- **All randomness comes from `state.rng`**, seeded per battle. Seed plus command list
  replays a battle exactly (`test_same_seed_same_battle` checks this).

### Turn structure

- **Rounds and initiative:** each round, every living unit acts once, highest
  `initiative` first. Ties are broken by the seeded RNG. (`rules/turn_order.gd`)
- **Action points:** a unit refills to `max_ap` at the start of its turn. Moving costs
  the terrain's `move_cost` per cell (1 by default). Abilities cost `ap_cost`.
- **Turn start, in order:** refill AP, tick cooldowns, run status `on_turn_start`
  effects, check objectives, then decrement status durations. If the unit has a
  `skip_turn` flag, it loses the turn. So a duration of 1 means "until my next turn",
  and `disabled` with duration 1 skips exactly one turn.
- **Cooldowns:** a cooldown of 3 means the ability is usable again on the user's 3rd turn
  after using it.

### Damage

```
raw    = roll(amount) × attacker.damage_dealt × defender.damage_taken
shields absorb first, scaled by damage_type.vs_shields
overflow → hull, scaled by damage_type.vs_hull, minus armor (minimum 1)
```

Damage types (`data/tactical/damage_types.json`) create the rock-paper-scissors:
energy strips shields, kinetic and explosive punish hull. `bypass_shields` and
`ignore_armor` exist for hull breaches, boarding and similar effects.

### Extension points

| To add... | Do this |
| --- | --- |
| A new mechanic (push, teleport, summon, AP drain) | Subclass `BattleEffect`, register it in `EffectRegistry` |
| A new victory condition (reach exit, escort, hack terminals) | Subclass `BattleObjective`, register it in `ObjectiveFactory` |
| A new grid shape (square grid for ground missions) | Subclass `TacticalGrid`, add it to `GridFactory`. Pathfinding, LOS, abilities, AI and `HexMapView` already work through the interface |
| Heroes on units | `BattleUnit.hero_id` exists. Step 3 merges hero abilities and stat modifiers into the unit at battle setup |
| Smarter AI | Swap or extend `RuleBasedAI`. It already scores any ability through `preview_ability()`, so new content needs no AI code |

## The strategic layer (galaxy)

`src/strategic/` mirrors the tactical engine: `GalaxyEngine` + `GalaxyState`, commands
(`MoveFleetCommand`, `EndFactionTurnCommand`) in, events (`GalaxyEvents`) out, pure logic.
It reuses `HexGrid` and `Pathfinding`. A galaxy is just a hex map with galaxy terrain.

- **Turns:** factions move in order (player, then AI). At the start of a faction's turn
  its fleets get `speed` moves (the slowest ship's `strategic.speed`) and fleets at friendly
  planets repair 25% hull.
- **Fleets** hold persistent ships `{uid, unit, name, hull}`. Hull damage carries over
  between battles, and shields recharge.
- **Fog of war:** each faction sees cells within `sensor` range of its fleets (best ship
  sensor) and planets. `explored` remembers everything it has ever seen. Every query that
  plans movement uses only the mover's knowledge, so the AI plays fair too.
- **Movement and battles:** visible enemy fleets can be attacked but not passed. A hidden
  enemy on your path intercepts you (an "ambush"). Either way the mover stops next to the
  enemy and `state.pending_battle` is set. The engine refuses commands until it is resolved:
  ```
  scenario = galaxy.pending_battle_scenario()        # attacker west, defender east
  battle   = BattleEngine.from_scenario(data, scenario, galaxy.next_battle_seed())
  ...play it on BattleScreen, or AutoResolver.resolve(battle)...
  galaxy.resolve_pending_battle(battle)              # write hull/losses back via unit.ref
  ```
  `auto_resolve_pending_battle()` does all of that in one call. The battle map comes from
  the location: planet type, then galaxy terrain (`battle_map`), then the campaign default.
- **Planets** are captured by ending a move on them. A faction with no fleets and no planets
  is eliminated, and the last faction standing wins.
- **AI** (`GalaxyAI`): per fleet, attack a visible fleet it can beat, otherwise retreat to
  repair when below 50% hull, otherwise head for the nearest planet it doesn't own.
  `CampaignAutoRunner` plays whole campaigns headlessly, for tests and `tools/simulate_campaign.gd`.

### Screens

`main.tscn` runs `game.gd`, which owns the galaxy screen. When the player picks **Fight**,
the galaxy screen emits `battle_requested(scenario, seed)`. `game.gd` takes the galaxy out
of the tree (keeping its state), shows a `BattleScreen` set up via `configure()`, and on
`battle_finished(engine)` puts the galaxy back and calls `on_battle_finished(engine)`.
The galaxy screen's coroutine, which was waiting on that, then resolves the battle into
the campaign. Both screens share `HexMapView` (with fog support), `FxLayer`, `Starfield`,
`Palette` and `UiKit`.

### How later layers plug in

- **Missions (step 3):** same engine, square grid, squad-sized units, and objectives such
  as `reach_cell` / `survive_rounds` / `interact`. Fog of war is a presentation and query
  filter on top of the same state. Failed missions are just a result the mission layer
  turns into a follow-up rescue mission.

## Content schema

Coordinates in content are `[column, row]` from the top-left of the map (odd rows are
shifted right on hex maps). The engine converts them internally.

**Unit** (`data/tactical/units/*.json`)
```jsonc
{
  "id": "frigate", "name": "Frigate", "description": "...",
  "tags": ["ship", "medium"],
  "stats": { "max_hull": 120, "max_shields": 60, "armor": 3, "initiative": 4, "max_ap": 4 },
  "abilities": ["railgun", "torpedo_salvo", "brace_shields"],
  "visual": { "placeholder": "frigate", "sprite": "res://assets/ships/frigate.png", "size": 1.0 }
}
```
`visual.sprite` is optional. When it is set and the file exists, it replaces the placeholder shape.

**Ability** (`data/tactical/abilities/*.json`)
```jsonc
{
  "id": "torpedo_salvo", "name": "...", "description": "...",
  "ap_cost": 3, "cooldown": 3,
  "target": "cell",          // self | enemy | ally | any_unit | cell
  "range": [2, 6],           // min, max grid distance
  "radius": 1,               // 0 = single target
  "affects": "all",          // enemies | allies | all (default follows target)
  "requires_los": false,
  "effects": [
    { "type": "damage", "amount": [18, 26], "damage_type": "explosive" },
    { "type": "apply_status", "status": "hull_breach", "duration": 2, "chance": 0.5 },
    { "type": "heal", "stat": "shields", "amount": 20, "to": "self" }   // "to": "self" targets the user
  ],
  "fx": "torpedo"            // presentation hint: projectile | beam | torpedo | pulse | self
}
```

**Status** (`data/tactical/statuses/*.json`)
```jsonc
{
  "id": "braced", "name": "Braced", "description": "...",
  "modifiers": { "damage_taken": { "mul": 0.75 }, "armor": { "add": 2 } },
  "flags": ["skip_turn"],
  "on_turn_start": [ { "type": "damage", "amount": 5, "damage_type": "kinetic", "bypass_shields": true } ],
  "ai_value": 8              // how good it is for whoever has it (negative = debuff)
}
```

**Terrain** (`data/tactical/terrain.json`): `passable`, `blocks_sight`, `move_cost`, `color`.

**Map** (`data/tactical/maps/*.json`): `grid` ("hex"), `width`, `height`, and `terrain: { id: [[c, r], ...] }`.

**Map** deployment (needed for galaxy battles): `"deployment": { "west": [[c, r], ...6], "east": [...] }`.

**Scenario** (`data/scenarios/*.json`, or generated by the galaxy): `map`, `max_rounds` (draw after that),
`teams: [{ team, name, controller: "player" | "ai", units: [{ unit, name, at: [c, r], hull?, ref?, hero? }] }]`,
`objectives: [{ type: "eliminate_all" } | { type: "survive_rounds", team, rounds }]`.
`hull` starts a unit damaged. `ref` ties it back to whatever it represents (a fleet's ship).

**Unit, strategic part:** `"strategic": { "speed": 3, "sensor": 2 }` (galaxy moves per turn, sensor radius).

**Galaxy terrain** (`data/strategic/terrain.json`): `passable`, `move_cost`, `color`,
`decoration` ("rocks"), `battle_map`.

**Planet types** (`data/strategic/planet_types.json`): `name`, `description`, `color`, `size`, optional `battle_map`.

**Campaign** (`data/strategic/campaigns/*.json`)
```jsonc
{
  "id": "the_drift", "name": "...", "description": "...",
  "max_turns": 150, "battle_max_rounds": 30, "default_battle_map": "open_space",
  "map": { "grid": "hex", "width": 16, "height": 11, "terrain": { "nebula": [[7, 1]], ... } },
  "factions": [ { "id": "patrol", "name": "...", "controller": "player" }, { "id": "raiders", "controller": "ai" } ],
  "planets": [ { "id": "haven", "name": "Haven", "type": "terran", "at": [1, 5], "owner": "patrol", "sensor": 3 } ],
  "fleets": [ { "name": "1st Patrol", "owner": "patrol", "at": [2, 4],
                "ships": [ { "unit": "frigate", "name": "Vigilant", "hull": 100 } ] } ]
}
```
The faction's position in `factions` is its team number (and color) in battles.

## Conventions

- Typed GDScript everywhere (`var x: int`, `-> void`). The editor catches more errors that way.
- `class_name` on every reusable script, so there are no `preload` paths to maintain.
- Engine code never references nodes, scenes or `Input`. Presentation code never changes `BattleState`.
- Events are dictionaries with a `type` from `BattleEvents`. Add new fields freely; renderers ignore what they don't know.
- Tests use the fixed-number units in `tests/fixtures.gd`, so rebalancing real content doesn't break rules tests.
