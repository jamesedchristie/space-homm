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
| A new victory condition (escort, hack terminals) | Subclass `BattleObjective`, register it in `ObjectiveFactory` (see `ReachCellsObjective`) |
| A new grid shape | Subclass `TacticalGrid`, add it to `GridFactory` (`HexGrid` and `SquareGrid` exist). Pathfinding, LOS, abilities, AI and `GridMapView` work through the interface |
| A new trigger effect (open doors, hack, reveal map) | Add a case to `BattleEngine._apply_trigger_effects` and to `DataRegistry.TRIGGER_EFFECTS` |
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
- **AI** (`GalaxyAI`): per fleet, attack a visible fleet it can beat (counting the defense
  platforms of a planet the target sits on), otherwise retreat to repair when below 50% hull,
  otherwise head for the nearest planet it doesn't own. Factions can have a personality
  (campaign `ai` entry, see the content schema).
  `CampaignAutoRunner` plays whole campaigns headlessly, for tests and `tools/simulate_campaign.gd`.

### Screens

`main.tscn` runs `game.gd`, which shows the title screen (`MainMenu`) and then owns the
galaxy screen (`skip_menu`, or the `--new-campaign` user argument, goes straight to a new
campaign; the smoke test uses it). When the player picks **Fight**,
the galaxy screen emits `battle_requested(scenario, seed)`. `game.gd` takes the galaxy out
of the tree (keeping its state), shows a `BattleScreen` set up via `configure()`, and on
`battle_finished(engine)` puts the galaxy back and calls `on_battle_finished(engine)`.
The galaxy screen's coroutine, which was waiting on that, then resolves the battle into
the campaign. Both screens share `GridMapView` (with fog support), `FxLayer`, `Starfield`,
`Palette` and `UiKit`.

Player preferences (fullscreen, volume, 2D/3D per screen) live in `GameSettings`
(`user://settings.cfg`), edited through `SettingsPanel` on the title screen and in game.
A campaign's optional `briefing` (BBCode) is shown when a new game starts.

### Saving and loading

`GalaxySave` (`src/strategic/galaxy_save.gd`) snapshots the whole `GalaxyState` as plain data
(dictionaries, arrays, numbers, strings, `Vector2i`) plus the campaign id and display info
(campaign name, turn, time). The grid isn't stored: it's rebuilt from the campaign, since
galaxy terrain never changes. The RNG state is stored, so a loaded game continues exactly as
the original would have (a test plays both to the end and compares). Files go to
`user://saves/<slot>.save` via `FileAccess.store_var` and are read with objects disallowed, so
a save can only hold data. Saves are only taken between turns (no pending battle or mission);
the galaxy screen autosaves at the start of each human turn. Bump `GalaxySave.VERSION` and
migrate in `from_dict()` when the state's shape changes.

### Battle views (2D and 2.5D)

`battle_screen.gd` holds the turn, input and HUD logic and draws only through a `BattleBoard`
(`src/presentation/tactical/battle_board.gd`). The interface is in terms of unit ids and cells:
add, move or destroy units, play ability effects, highlights, fog, markers, cell under the mouse,
and fitting the view to the HUD-free area. There are two implementations:

- `BattleBoard2D`: the top-down view (`GridMapView`, `UnitView`, `FxLayer`).
- `BattleBoard3D`: a lit 3D board seen through a tilted, zoomable and rotatable camera. Grid
  pixel coordinates map onto the XZ plane, and mouse picking ray-casts to the floor plane.
  Tiles, deck plates and bulkheads are generated meshes. Units are procedural models
  (`Unit3D` + `ModelFactory`) and effects are 3D (`Fx3D`). Bars, names and floating text are
  drawn in 2D on top (`BoardOverlay3D`). The nebula backdrop shows behind the scene via
  `Environment.BG_CANVAS`.

The view is chosen per screen (`BattleScreen.view_mode`, toggled with V, even mid-battle) and is
rebuilt from engine state, so the views can never disagree about the game. On big maps the 3D
camera starts zoomed in on the player's units (closer still in missions, on `floor: "deck"`
maps) instead of framing everything from far away.

### Galaxy views (2D and 2.5D)

The galaxy screen works the same way through a `GalaxyBoard`
(`src/presentation/strategic/galaxy_board.gd`): `sync()` brings fleets, planets, anomalies and
fog in line with the engine (as the player sees it), plus fleet moves and explosions, floating
text, a ping for battles, highlights, the cell under the mouse and fitting the view.

- `GalaxyBoard2D` wraps the original top-down map (`GridMapView`, `PlanetView`, `FleetView`,
  `AnomalyView`, `FxLayer`).
- `GalaxyBoard3D` builds translucent hex tiles over the nebula, terrain props (asteroids,
  nebula glow, dark rifts), spinning planet spheres (`Planet3D`: `planet_3d.gdshader` surface,
  `atmosphere.gdshader` glow shell, an orbit ring in the owner's color), fleets as small models
  of their biggest ships (`Fleet3D`) and anomaly crystals (`Anomaly3D`). Unexplored space is a
  low slab with drifting dark clouds (`fog_3d.gdshader`); charted planets rest on top of it.
  Names, hull bars and move pips are 2D (`GalaxyOverlay3D`). The camera opens on the explored
  area. Q/R rotate here because E opens the Empire panel.

Both 3D boards share `src/presentation/board3d/`: `BoardCamera3D` (tilted orbit camera:
fit to a screen rectangle, zoom, pan, rotate, shake, ray-plane picking; it takes the view back
when its screen re-enters the tree) and `BoardGeometry` (lighting/environment, materials,
extruded tiles, overlay buffers for highlights and fog, rocks and nebula puffs).

## Heroes and missions (step 3)

**Heroes** (`src/heroes/`) are persistent `Hero` records in `GalaxyState.heroes`: class, level/XP,
traits, gear, loyalty, status (`ready`, `on_mission`, `injured`, `captured`, `dead`), and either a
fleet they command or a planet they wait at.

- `HeroBuilder.unit_def(hero)` turns a hero into a tactical unit definition: class stats, plus
  growth per level, plus gear and trait modifiers. Abilities are the gear abilities (weapon
  first) and the class skills unlocked so far. It goes into a scenario entry as `"unit_def"`,
  so heroes fight through the same engine as everything else.
- **Fleet command:** a *ready* commander adds the class's `command_status` (a `permanent`
  status) to every ship in that fleet's battles, and earns battle XP. Heroes away, injured or
  captured give no bonus. That is the cost of sending them on missions.
- `HeroProgression` handles XP thresholds and level-ups (`data/heroes/progression.json`).
- Galaxy commands: `AssignHeroCommand`, `UnassignHeroCommand`, `EquipItemCommand` (from the
  faction's inventory). The Heroes panel (`HeroRoster`) only emits these commands.

**Missions** (`data/missions/`, built by `MissionFactory`) are tactical battles that use these
engine features, all available to fleet battles too:

| Feature | How |
| --- | --- |
| Square grid | `SquareGrid` (8-way moves, Chebyshev distance, no cutting wall corners) behind `TacticalGrid` |
| Fog of war | scenario `"fog": true`. `BattleState.visible_cells(team)` uses each unit's `sight` stat plus LOS, cached by `state.version`. You can't target what your side can't see |
| Dormant groups | unit entry `"dormant": true, "group": "aft"`. Skips its turns until it sees an enemy, is damaged or is alerted, and then wakes its whole group |
| Triggers | scenario `"triggers"`: entering one of the cells (or reaching `"round": n`) fires text, immediate `effects` and optional `choices`. While a choice is pending, only `ChooseOptionCommand` is accepted (the AI picks option 0) |
| Trigger effects | `effect` (any BattleEffect on the unit or squad), `spawn` (reinforcements), `alert` (a group or team), `reward` (xp/items/trait/loyalty, recorded in `state.rewards` for the campaign) |
| Objectives | `reach_cells` (stand on a cell) alongside `eliminate_all` |
| Cover | terrain `"damage_taken": 0.7` multiplies damage to whoever stands in it |
| Friendly targets | ability `"target": "friendly"`: an ally or yourself |

**Galaxy flow:** anomalies (`campaign.anomalies`) sit on cells. A fleet that ends a move on one,
with a ready commander (or any fleet if the mission has `requires_hero: false`), sets
`state.pending_mission`. Like a battle, it is resolved by
`pending_mission_scenario()` → `BattleEngine` → `resolve_pending_mission(battle)`, or by
`auto_resolve_pending_mission()` / `decline_pending_mission()`. Results:

- **Success:** mission and trigger rewards (XP to every hero in the squad, items to the faction
  inventory, traits, loyalty); heroes who fell are injured (or killed with permadeath); the
  anomaly is cleared. A rescue success (`free_captives`) also frees captured heroes.
- **Failure:** heroes who fell are captured (or killed with permadeath). The anomaly becomes the
  mission's `on_failure` follow-up, a rescue that only the captives' faction can take.
- **Either way:** surviving heroes are away (`on_mission`) for `duration` turns.

The AI only takes a mission when its commander meets the mission's `recommended_level`, and
never retries an anomaly it has already been offered. The player sees the recommendation in
the briefing.

## Empire (step 4)

Empire rules live in `src/empire/` as static helpers over `GalaxyEngine`, so the engine, UI and AI
always agree:

- `EmpireRules`: planet yields (type + buildings, times tech multipliers), income, costs, build
  options per planet (slots, shipyard, unlocks), defense units, tech effects, and the score.
- `ResearchRules`: tech status (known / available / locked by `requires`).
- `DiplomacyRules`: opinions, peace acceptance, military strength.

**Turn start** (`GalaxyEngine._run_economy`): add income to the stockpiles. Research points
go into the current tech (unspent points are banked). Each planet's build queue advances, and
finished ships join the fleet in orbit or form a new one. Opinions of factions at peace drift up.

**Commands:** `SetResearchCommand`, `QueueBuildCommand` (paid up front, one item per planet),
`DiplomacyCommand` (`propose_peace`, `declare_war`, `gift`).

**Tech effects** (`data/empire/techs.json`):

| Effect | Meaning |
| --- | --- |
| `ship_status` | a (hidden, permanent) status every ship starts battles with |
| `empire_modifier` | `fleet_speed`, `sensor`, `field_repair` bonuses |
| `yield` | multiplies a resource's output |
| `unlock_building` / `unlock_unit` | makes a building or ship buildable (matching `requires_tech`) |

**Diplomacy:** relations default to war unless the campaign says otherwise. At peace, fleets
can't attack or pass through each other and planets can't be captured. An AI accepts peace if
its opinion of you is at least 10 or it's clearly losing, but never within 3 turns of the war
starting, and never if it's `always_hostile`. Being attacked (−15), losing a planet (−20) or
having war declared on you (−30) lowers opinion. Gifts (+10) and time at peace (+1/turn) raise it.

**Planet defenses:** buildings with a `defense_unit` put immobile units (`"immobile"` tag) into
any battle at that planet. A fleet entering a defended enemy planet with no fleet on it fights
the platforms; if it wins and none survive, it moves in and captures the planet. Destroyed
platforms are removed.

**End of the war:** the last faction standing wins. If every survivor is at peace with every
other, the highest `EmpireRules.score` wins (planets, techs, fleet hull, hero levels).

**AI:** each turn it picks the cheapest available tech, gives idle planets a build order
(ships when outgunned or when it has no shipyard; otherwise economy buildings in priority
order), makes peace with AI factions that would accept, and declares war on hated, weaker
neighbours. Small fleets wait at their shipyard for ships under construction. Fleets only hunt
enemy fleets within 5 jumps; beyond that they go for planets.

### How later layers plug in

- **More mission types:** exploration missions are the same pieces (fog, triggers, reach
  objectives, few enemies). Single-ship or small-fleet missions are a mission whose map is a
  hex map and whose squad entries are ships. Interactable objects (terminals to hack, doors)
  would be a new trigger effect type or command.
- **Hero abilities in fleet battles** (HoMM-style spells) would be a hero "unit" with no grid
  presence, or abilities granted to the flagship via the doctrine status.
- **Mission rewards into the economy:** add `credits`/`alloys`/`tech` to `reward` trigger effects
  and apply them in `resolve_pending_mission`.
- **Governors:** heroes waiting at a planet (`planet_id`) could add yields to it.

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

**Hero class** (`data/heroes/classes.json`, keyed by id)
```jsonc
"vanguard": {
  "name": "Vanguard", "description": "...",
  "stats": { "max_hull": 80, "max_shields": 35, "armor": 2, "initiative": 6, "max_ap": 5, "sight": 6 },
  "growth": { "max_hull": 8, "max_shields": 4 },          // per level above 1
  "skills": { "1": ["bulwark"], "2": ["shockwave"], "4": ["rally"] },
  "command_status": "cmd_vanguard"                        // doctrine for the fleet it commands
}
```

**Items** (`data/heroes/items.json`): `name`, `slot` (`weapon` | `armor` | `gadget`), `description`,
`abilities` (granted), `modifiers` (`{stat: {add, mul}}`, folded into the hero's stats).
**Traits** (`data/heroes/traits.json`): `name`, `description`, `modifiers`.
**Progression** (`data/heroes/progression.json`): `xp_thresholds`, `battle_xp` (`win`/`loss`), `injury_turns`.

**Mission** (`data/missions/*.json`)
```jsonc
{
  "id": "derelict_station", "name": "...", "description": "...",
  "map": "derelict_deck",               // square map with deployment.squad slots
  "squad_size": 3, "marine_unit": "marine", "requires_hero": true, "recommended_level": 2,
  "duration": 2, "max_rounds": 25, "enemy_name": "Station Boarders",
  "enemies": [ { "unit": "boarder", "at": [6, 2], "group": "mid" } ],   // dormant unless "alert": true
  "objectives": [ { "type": "reach_cells", "cells": [[13, 4]], "description": "Reach the data core" } ],
  "triggers": [ {
    "id": "terminal", "cells": [[2, 8]], "title": "...", "text": "...",
    "effects": [ ... ],                                    // applied on entry
    "choices": [ { "label": "Download the logs", "text": "result text",
                   "effects": [ { "type": "reward", "xp": 30 }, { "type": "alert", "group": "aft" } ] } ]
  } ],
  "rewards": { "xp": 120, "items": ["plasma_rifle"] },     // on success; "free_captives": true for rescues
  "on_failure": { "mission": "derelict_rescue", "name": "Distress Beacon" }
}
```

Timed triggers use `"round": n` instead of `cells` and fire at the start of that round (no
choices; `"effect"` entries need `"to": "squad"`). They're how hold-out missions send waves:
*Silent Relay* is `{"type": "survive_rounds", "rounds": 8}` with skiffs and drones arriving on
rounds 3, 5 and 7, and `"eliminate_all_wins": false` so clearing the first wave doesn't end it
(a battle also doesn't end by elimination while timed triggers are still pending).

**Campaign additions:** `"permadeath": false`,
`"heroes": [{ "id", "name", "class", "owner", "fleet": "<fleet name>" | "planet": "<planet id>", "level"?, "traits"?, "gear"?, "loyalty"? }]`,
`"inventory": { "<faction>": ["item ids"] }`,
`"anomalies": [{ "id", "name", "at": [c, r], "mission" }]`.

**Status additions:** `"permanent": true` (never expires). Unit additions: `"sight"` stat,
`"stat_names": {"hull": "Health"}` for display. Scenario unit entries also take
`"unit_def"`, `"statuses": [{status, duration}]`, `"dormant"`, `"group"`.

**Empire data** (`data/empire/`):
- `resources.json`: `name`, `description`, `color` per resource (`credits`, `alloys`, `research`).
- `buildings.json`: `name`, `description`, `cost`, `turns`, and optionally `yields`, `shipyard: true`,
  `defense_unit`, `requires_tech`.
- `techs.json`: `name`, `description`, `cost`, `requires`, `effects` (see the table above).

Planet types gain `yields` and `slots`. Units gain `strategic.cost`, `build_turns` and `requires_tech`.
Campaigns gain `resources: {faction: {credits, alloys}}`,
`relations: [{factions: [a, b], status: "peace"|"war", opinion}]`, `techs: {faction: [ids]}`,
planet `buildings`, faction `always_hostile`, and faction `ai` (personality overrides for
`GalaxyAI`: `attack_ratio`, how much stronger than the target a fleet must be to attack,
default 0.9; `hunt_range`, default 5; `retreat_hull_ratio`, default 0.5). In *The Drift* the
traders are cautious (1.4, range 3) and the raiders only take even-or-better fights (1.0).

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
