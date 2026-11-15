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

### How later layers plug in

- **Strategic map (step 2):** when stacks meet, build a scenario dictionary in code
  (map, both fleets, objectives) and call `BattleEngine.from_scenario(data, dict, seed)`.
  Then show `BattleScreen` for a fought battle, or call `AutoResolver.resolve()` for a
  quick one. Read surviving units' hull/shields back from `engine.state.units`.
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

**Scenario** (`data/scenarios/*.json`): `map`, `max_rounds` (draw after that),
`teams: [{ team, name, controller: "player" | "ai", units: [{ unit, name, at: [c, r], hero? }] }]`,
`objectives: [{ type: "eliminate_all" } | { type: "survive_rounds", team, rounds }]`.

## Conventions

- Typed GDScript everywhere (`var x: int`, `-> void`). The editor catches more errors that way.
- `class_name` on every reusable script, so there are no `preload` paths to maintain.
- Engine code never references nodes, scenes or `Input`. Presentation code never changes `BattleState`.
- Events are dictionaries with a `type` from `BattleEvents`. Add new fields freely; renderers ignore what they don't know.
- Tests use the fixed-number units in `tests/fixtures.gd`, so rebalancing real content doesn't break rules tests.
