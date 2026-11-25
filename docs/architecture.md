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
  A battle in a star system's hex instead uses a generated system map (below).
- **Systems** are not claimed by entering them: colonies and outposts claim them, and conquest
  takes them (see [The system layer](#the-system-layer-civilian-ships-claiming-conquest)).
  A faction with no fleets, no systems and no deployed civilian ships is eliminated, and the last
  faction standing wins.
- **Fleets merge and split.** A fleet can move into another of its owner's fleets if the ships
  fit (`EmpireRules.MAX_FLEET_SIZE`) and there's at most one commander: it joins and is removed
  (`FLEETS_MERGED`; the merged fleet keeps the lower moves left). `SplitFleetCommand` detaches
  ships into a new fleet on a free neighbouring system, paying that move from the fleet's
  moves left (`split_targets()`); the commander stays.
- **AI** (`GalaxyAI`): per fleet, attack a visible fleet it can beat (counting the defenses of a
  system the target sits on), otherwise retreat to repair when below 50% hull, otherwise head for
  the nearest enemy system it can take (picking up a Troop Transport first for a colony); small
  fleets scout unexplored space. Civilian ships have their own rules (see the system layer).
  Factions can have a personality
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

`OddsEstimator` (`src/tactical/odds_estimator.gd`) plays copies of a pending battle or
mission with `AutoResolver` (12 seeds) to show auto-resolve odds in the offer dialog. It uses
`WorkerThreadPool` on desktop (engines are independent RefCounted objects; the shared effect
table is built before threads start) and one run per frame on the single-threaded Web build.

### Species and faction roles

`data/strategic/species.json`: each species has `effects` in the tech effect format (`yield`,
`empire_modifier`, `ship_status`), which `EmpireRules.tech_effects` adds to the faction's tech
effects, so species bonuses flow through the same code as research. `squad_ability` is added to
every hero and marine of that species on missions (`MissionFactory.squad_for`). Each species
flies its own ship designs (see "Ship models" below); `style` repaints models (`hull` / `dark` /
`glass` / `trim` / `glow` / `engine` colours, a `finish` of metallic / roughness per material) and
adds `extra` parts per model id or base (`humanoid`) (`ModelFactory.build(..., style)`; battle
teams carry `species` and `role`). Campaign factions set `species` and `role`:
- `major` (default) plays to win. Victory and the "everyone at peace" ending consider majors
  only; a campaign can instead set `"victory": {"eliminate": faction}` (The Drift).
- `barbarian`: always hostile; `barbarian: {spawn_every, max_fleets, fleet, den_loot}`: each den
  (system they hold) launches a raider fleet every `spawn_every` turns; captures become
  `_plunder` (credits stolen, a building wrecked, a pop lost; the system stays with its owner
  unless nothing is left standing); winning the battle at a den takes it with no troops and pays
  `den_loot`. The AI only targets systems others hold and builds no civilian ships.
- `minor`: stays near home (AI expands within 4 of its capital); `EmpireRules.trade_income`
  pays friendly majors at peace.
The New Campaign screen's species choice rewrites the player's faction (and swaps an AI major
of that species to the player's original one) via `SpeciesNaming.with_player_species`
(`src/strategic/species_naming.gd`). Each species has `names`: `{home, home_description,
fleets: [...], heroes: [...], ship_names: [...]}`. `SpeciesNaming.apply(def, faction_id,
species_id, data)` renames that faction's home system (the `generate.homes` entry, or the first
owned planet of a hand-made campaign, plus a body of the same name), its starting fleets (in
order) and their ships, and its heroes (in order; ids, class and gear stay), and rewrites heroes'
`fleet` references to the new fleet names. It works on the campaign definition before the engine
is built, so it is testable without the UI. Ships built later are named from the owner species'
`ship_names` (`GalaxyEngine._launch_ship`).

### Leaders and diplomacy screens

`data/strategic/leaders.json` has one entry per species (`human`, `veltari`, `kesh`, `sorn`) plus
`raider_warlord` (role `barbarian`) and `trader_factor` (role `minor`); `LeaderRules.leader_id`
maps a faction to its leader (role first, then species, so a species swap in the New Campaign
screen also swaps leaders). An entry holds `name`, `title`, `personality`, a `portrait` block
(`look`: which species model; skin/lips/eyes/hair colours, `hair_style`, costume colours
`primary`/`secondary`/`accent`, `glow`, `backdrop`, and shape knobs like `jaw`, `brow`, `crest`,
`horns`) and `lines`: 2 or 3 variants for each of `LeaderRules.LINE_KEYS` (`first_contact`,
`greeting`, `hail_war`, `war_on_you`, `you_declare_war`, `peace_accepted`, `peace_refused`,
`peace_offer`, `offer_declined`, `gift`, `farewell`), with `{player}` (the addressed empire),
`{empire}` and `{leader}` placeholders. `DataRegistry` validates that every species and every
shipped campaign faction resolves to a complete leader.

Engine side (small, confined to diplomacy): `GalaxyState.met` ("a|b" -> turn) records first
contact; `GalaxyEngine._detect_contacts` emits `FIRST_CONTACT {factions}` once per pair when a
fleet or system of one is within the other's vision (after each move and in
`_update_explored`). AI-to-player peace uses `GalaxyState.peace_offers` ("from>to" -> {turn,
status}): the AI issues `DiplomacyCommand` `offer_peace` (see
`DiplomacyRules.wants_to_offer_peace`: at war 3+ turns, losing or war-weary, 8-turn
cooldown) which emits `PEACE_OFFERED`; the player answers on their turn with `accept_peace`
(`PEACE_SIGNED`) or `refuse_peace` (`PEACE_OFFER_REFUSED`); offers lapse after
`DiplomacyRules.OFFER_TTL` turns, and an AI-driven player faction (autoplay) answers them in
`GalaxyAI._diplomacy`. `met` and `peace_offers` are saved in `GalaxySave` without a version bump
(older saves count everyone as met).

Presentation: `LeaderPortrait` (`src/presentation/portrait/`) renders a procedural bust in its own
`SubViewport`: a displaced-sphere head (`PortraitHead`: jaw, brow ridge, cheekbones, crest) with
a soft wrap-lit skin shader, eyes with iris caps and blinking lids, brows, nose, lips, ears,
species prosthetics (Vel'tari crystal crown and temple ridges, Kesh cheek ridges, tusks, horns
and braids, Sorn crest and neck ridges), a costume per look (`PortraitCostume`), a painted
backdrop (`PortraitBackdrop`), and three-point lighting with coloured rims. Idle animation:
breathing, sway, blinks, glances; `set_speaking` moves the mouth, `set_mood` changes brows and
smile. It needs no shadows or post effects, so it runs on GL Compatibility / Web.
`DiplomacyScreen` (`src/presentation/strategic/diplomacy_screen.gd`) is the full-screen modal
(modes `first_contact`, `hail`, `war_on_you`, `peace_offer`): it reads the engine, types out the
leader's line, offers replies and emits `DiplomacyCommand`s; `GalaxyScreen` submits them and
passes the events back with `show_result` so the leader answers. First contacts and offers that
arrive during AI turns wait until the player's turn; autoplay skips all screens.

### Randomness: discoveries and planet traits

A campaign's `"random"` entry adds seeded variety (`GalaxyEngine._roll_random_features`, using
the campaign RNG so a seed always gives the same sector):
- `"planet_traits": chance`: undeveloped bodies in unowned systems may roll a trait that
  suits their category (`on`) from `data/strategic/planet_traits.json` (`yields`, `slots`).
- `"discoveries": {"count", "kinds"?, "min_distance"?}`: one-time finds placed on free cells
  away from planets and fleets (or listed explicitly as `"discoveries": [{"kind", "at"}]`).
  The first fleet to enter one claims it: a weighted roll on its `outcomes` in
  `data/strategic/discoveries.json`, rewards `credits`, `alloys`, `research` (progress),
  `ship`, `item`, `intel` (reveal radius), `xp` (commander) or `damage` (hull fraction),
  reported as `DISCOVERY_FOUND`. The AI grabs known finds within 4 systems unless a stronger
  enemy is near them.

**Generated sectors** (`GalaxyGenerator`): a campaign with a `"generate"` block (see
`random_sector.json`) is turned into an ordinary campaign definition from the seed before the
engine reads it: homes spread apart by farthest-point picks (the player's on the west side),
neutral planets with random types and names, terrain blobs (rifts are dropped if they'd cut a
planet, fleet or mission site off from the player's home), starting fleets beside their homes
and mission sites in the contested middle. Saves of generated campaigns store the generated
definition (`campaign_def`). Content validation runs the generator for two seeds.

**Hyperlanes.** A `"lanes": {"extra", "max_length", "relic_gates"}` entry in the generate block
makes the sector a lane network (`GalaxyGenerator._make_lanes`): the relative neighbourhood graph of
the systems (connected, planar, mostly short hops) plus extra non-crossing lanes up to `max_length`
hexes (chance `extra` each) for loops. The hexes on each lane's line stay open; every other cell
becomes `void` terrain (impassable, not drawn), so movement, pathfinding, fog, battles and the AI
need no lane-specific code. Fleets and mission sites are placed on lane cells; terrain blobs only
land on lanes (slow lanes) and rifts are skipped. The output's `"lanes"` (`[[planet id, planet id]]`)
is for the presentation (`GalaxyEngine.has_lanes()` / `lanes()`). Every system cell starts explored
for everyone (charted). **Gates:** `Planet.gate == "relic"` (`relic_gate` on the generated planet,
`_place_relic_gates` spreads them far from homes) or a `jump_gate` building (tech
`gate_engineering`, scale `galaxy`); `GalaxyEngine.gate_kind()` / `gate_destinations(fleet)`: from a
relic gate to every other relic gate, from a Jump Gate to every other gate of the same owner, if the
far side is free (or holds a fleet to merge with), not hostile and not defended against the fleet.
`MoveFleetCommand` to such a cell jumps (`_do_jump`: all remaining moves, `FLEET_MOVED` with
`"jump": true`). The AI jumps when the far gate is clearly closer to its goal (`_step_towards`) and
builds up to four spread-out Jump Gates.

**Act 1 -> Act 2** (`ActTransition`, pure): after a Solar Age win (`can_continue`), `act2_campaign`
builds a campaign definition from the Random Sector template with the player's empire carried over:
the home system named after the old one with its bodies (owned ones with buildings and pop first, up
to `MAX_BODIES`), deployed civilians, warfleets, heroes (level, xp, gear), items, galaxy-scale techs and
the treasury capped by `CARRY_CAP`. Every major power is `"founded"` (starts with its capital instead of a
colony ship) and knows the same techs. The galaxy screen offers "Continue to Act 2" in the game-over
dialog and starts the definition through `campaign_override`.

Missions get their own randomness: `"caches": {"count", "loot": [...]}` places that many
supply lockers (one-cell reward triggers, marker `"loot"`) on random free cells away from the
squad, rolled from the battle seed in `BattleEngine._place_caches`; `"loot": [...]` is a
weighted table rolled once on success by `resolve_pending_mission`. Mission rewards may hold
`credits`, `alloys`, `research` (progress) and `intel` (chart the surroundings of that many
unexplored enemy planets, nearest first) as well as `xp`, `items`, `loyalty`, `trait`.

### Saving and loading

`GalaxySave` (`src/strategic/galaxy_save.gd`) snapshots the whole `GalaxyState` as plain data
(dictionaries, arrays, numbers, strings, `Vector2i`) plus the campaign id and display info
(campaign name, turn, time). The grid isn't stored: it's rebuilt from the campaign, since
galaxy terrain never changes. The RNG state is stored, so a loaded game continues exactly as
the original would have (a test plays both to the end and compares). Files go to
`user://saves/<slot>.save` via `FileAccess.store_var` and are read with objects disallowed, so
a save can only hold data. Saves are only taken between turns (no pending battle or mission;
a pending galactic event is saved with the state); the galaxy screen autosaves at the start of
each human turn. Bump `GalaxySave.VERSION` and migrate in `from_dict()` when the state's shape
changes. Version 3 added colony population and growth (inside the bodies), megaprojects on
systems, temporary modifiers, the event log and pending event, and why the game ended. Version 4
adds the system layer: `Planet.civilians` (deployed ships with their jobs), `blockade` and `capital`;
older saves are refused. Version 5 adds `surveyed` (system-scale campaigns). Version 6 adds strategic resources:
`deposits` on bodies and strategic stockpiles (version 5 saves load with no deposits and empty strategic stocks).

### The system layer: civilian ships, claiming, conquest

Below the galaxy map is a second level, the **system map**: what happens inside one star system.
Rules live in `GalaxyEngine` and `SystemRules` (`src/empire/system_rules.gd`); the presentation is
`SystemView` + `SystemMap` (`src/presentation/strategic/`).

**Civilian ships** are ordinary units with `strategic.civilian: true` and a `role`:
`colony` (Colony Ship), `constructor` (Constructor) and `transport` (Troop Transport); they are weak
in battle and `Fleet.is_civilian_only()` fleets can't fight. A ship is *in a fleet* on the galaxy map or
*deployed* in a system (`Planet.civilians`: `{uid, unit, name, hull, owner, loc: body id or "", job: {} or
{body, building, turns_left, turns}}`). Colony ships and constructors built by a colony start out
deployed (`SHIP_COMPLETED` with `deployed: true`); transports launch like warships. One order type drives
the system map, `CivilianCommand(faction, planet, ship_uid, action, body_id, item_id)`:

| Action | Rule |
| --- | --- |
| `move` | to a body of the system, instantly (deploys the ship if it was in a fleet in orbit) |
| `job` | a constructor starts building `item_id` (a development: a building with `"on"`, not `founded`) on `body_id`. Allowed in a system the faction owns or an unclaimed one; the body must fit and be free; cost is paid up front. It ticks at the start of its owner's turn (paused while blockaded); when done the building is added (replacing an `outpost`), and an unclaimed system becomes the owner's (`SYSTEM_CLAIMED`, `how: "outpost"`). The ship stays and can take another job; a job is cancelled (refunded) if the system changes hands |
| `found` | a colony ship founds a colony on a habitable body without buildings (unclaimed or own system). The ship is consumed; the colony starts at 1 pop and claims the system (`how: "colony"`). In a power's undeveloped home system (`Planet.capital`, set by the generator for `"start": "colony_ship"`), the faction's first colony is the **capital**: it gets the capital's pop and buildings |
| `depart` | a deployed idle ship leaves: joins the own fleet in orbit (room permitting) or forms a new fleet |
| `cancel` | drops a job, refunding `economy.jobs.refund` (half) |

The build queue (`QueueBuildCommand`, one item per system) builds colony buildings, megaprojects and
ships. `EmpireRules.build_options` no longer lists body developments; `EmpireRules.constructor_options`
does, for a body. Civilian ships need a colony in the system; a unit with `min_pop`/`pop_cost`
(Colony Ship) also needs a colony of that size, and the biggest colony gives up the population when the
item is queued. Deployed ships cost upkeep like fleet ships.

**Claiming.** Entering a system never claims it. A system becomes owned by a colony founded there or a
constructor job finished there. Discoveries and anomalies work as before.

**Convoys.** A civilian-only fleet treats enemy fleets and hostile systems as walls
(`reachable_for`), can't attack, and is destroyed without a battle (`FLEET_DESTROYED` with `by`) when an
enemy warfleet enters its hex or when it flies into a hidden warfleet. Civilian ships inside a warfleet
fight as weak ships in its battles.

**Conquest.** `GalaxyEngine.is_defended_against(system, faction)`: any system claimed by someone at war
with the mover, with no fleet of theirs on it, fights: `EmpireRules.defense_units` = the defense buildings
plus the **base garrison** (`garrison_units`, `economy.garrison`: `base` orbital batteries plus one per
`pop_per_extra` population of its colonies, up to `max`; none for unclaimed systems). The pending
assault battle uses the existing flow; a fleet at a system fights alongside its system's defenses.
After an attacker's win `_conquer` runs: a system with no colony, or a barbarian den, is captured
(`PLANET_CAPTURED`); a colony needs a Troop Transport in the fleet (`_try_invade`: one transport is
consumed, `SYSTEM_INVADED`, then the usual capture and pop loss); otherwise the fleet **blockades** it
(`Planet.blockade = attacker`, `BLOCKADE_STARTED`). Blockaded systems yield nothing, don't grow, don't
advance their queue or jobs, don't repair fleets and have no garrison; a warfleet of the blockader
entering (or a transport merging into it) may still invade. `_update_blockades` lifts it when the
blockader's warfleet is no longer there or the war ends. Raiders (barbarians) beaten at a den lose it
without troops; raiders winning an assault plunder.

**AI.** Majors only: colony ships found the capital on turn 1 (the best habitable world: pop cap, slots,
traits), then settle the best world within `CIVILIAN_RANGE` of their systems; constructors take the
best job (yield value, scarcity-weighted) in the systems they hold or empty explored ones nearby; both
build when there is work for them (`_choose_civilian_build`), transports when at war with someone who
has colonies. Civilian-only fleets travel to their goal (`_civilian_goal`), avoid visible warships and
fall back home when threatened; a warfleet that took a settler along splits it off towards its goal.
Every command is validated with the engine before it is submitted.

### System-scale campaigns (Act 1: Solar Age)

The game is being restructured into acts: Act 1 is the player's home star system, Acts 2 and 3 a
galaxy of systems joined by hyperlanes. Map levels: galaxy (later: a lane graph) -> **system map** (a
hex map of one system) -> battles fought on the system map where the ships are -> squad missions on
bodies. Phase 1 delivers the system map for the home system only, by reusing `GalaxyEngine` as it is
with a **system-scale campaign**: the campaign's hex grid *is* the system's space and **every body is
its own `Planet` with exactly one body**. So bodies are claimed one by one (Civ tiles), and every
existing mechanic (colony ships, constructor jobs, queues, growth, upkeep, events, research, the AI,
saves, assaults, plunder) works per body without new rules.

- **Flag.** `"scale": "system"` on the campaign (`GalaxyEngine.scale()` / `is_system_scale()`). A few
  rules read it: battles use `LocalBattleMap`, the star and corona are charted for everyone from the start,
  techs with a `"scale"` are only offered in matching campaigns (`ResearchRules.offered`), and the AI
  treats every body as in reach (`SYSTEM_CIVILIAN_RANGE`), settles marginal worlds
  (`SYSTEM_COLONY_SCORE`) and sends idle warfleets to survey (`_unsurveyed_target`).
- **Layout generator.** `SystemLayout` (`src/strategic/system_layout.gd`, pure, deterministic) turns a
  template's `"system_generate"` block into an ordinary campaign definition (like `GalaxyGenerator` for
  sectors; `GalaxyEngine.from_campaign` picks it, saves keep the generated definition). The star sits in
  the centre cell (`star` terrain, impassable) ringed by `corona` (3 moves). Orbits are circles in hex
  widths from the star (`pixel_distance`): each orbit picks a free cell within half a hex of its circle,
  keeps `GAP` steps from every other body group and places moons on free neighbours of their planet; a
  belt orbit is an arc of `asteroid_belt` terrain with belt bodies spread along it. Optional orbits roll
  `chance`; a failed attempt retries (then with a smaller gap). Bodies are named after the home star
  (`species.names.home_star` / `homeworld` via `SpeciesNaming`): numerals outwards, moons lettered after
  their planet (`"moon_of"` in the planet def), belt bodies lettered. Then: the homeworld (owned, settled,
  starting buildings, first in the planet list so it is the owner's home planet), dens for the barbarian
  factions (`"where": "moon" | "belt" | "outermost"`, as far from home as possible, at least
  `DEN_HOME_DISTANCE`), dormant `jump_point` terrain on edge cells spread round the system, fleets (`"at":
  "home" | "near_home" | "den"`), deployed civilians (`"home_moon"`), heroes, anomalies (`"outer_moon"` /
  `"outer_space"`) and discoveries. The output's `"system"` entry (`star`, `name`, `at`, `orbits`,
  `belt`) is for the presentation. Content validation generates two seeds.
- **Survey.** With `"survey": true`, a major power learns a body's traits once one of its ships has been
  at or next to it, it holds the body or has ships working there (`GalaxyEngine._update_survey`, run from
  `_reveal_around` and `_update_explored`; `GalaxyState.surveyed` per faction, `BODY_SURVEYED` events).
  `is_surveyed()` / `known_traits()` answer for the UI and the AI (which only values traits it knows).
- **Tech victory.** `"victory": {"tech": "hyperdrive", "tech_reason": "act1"}`: the first major power to
  research it wins (`GalaxyEngine._run_economy`). With a tech goal a lone major power doesn't win by
  default (`_check_eliminations` only ends the game when no major power is left). `VictoryRules.tech_goal`,
  `tech_progress` (research spent along the road) and a `tech` entry in `progress()`. Hyperdrive is a
  final-era tech with `"scale": "system"`; `"research_cost_mul"` scales the shared tree per campaign
  (`ResearchRules.cost`) instead of rebalancing it, and the AI researches the economy, then the road to
  the goal (`GalaxyAI.GOAL_ECONOMY`, `VictoryRules.tech_path`).
- **Hostiles.** Separatists and scavengers are ordinary barbarian factions (dens, `spawn_every`,
  plunder, den loot) at peace with each other. `barbarian.fleet_name` names their raider packs; a faction's
  `"ship_variant": "species"` makes a barbarian fly its species' own designs instead of the salvaged
  `raider` variant (`Fleet.model_variant`, used by `Fleet3D` and battle teams' `model_variant`).
- **Saves.** Version 5 adds `surveyed`; older saves load with nothing surveyed.

**Presentation.** `GalaxyBoard3D` on a system-scale campaign builds a `SolarSystem3D` (the sun in the
centre cell: high quality, `star_surface` with two billboard coronas and a shadow-casting `OmniLight3D`;
classic, an emissive core with additive halos and an unshadowed light; faint orbit circles through the
bodies and round the giants for their moons, drawn just above the fog so the layout always reads; a dusty
band along the belt; dormant `JumpGate3D`s facing the sun at the jump points) and draws each Planet as a
`Body3D` (a `Planet3D` subclass: one sphere sized by the body type, atmosphere shell, finer gas-giant
rings, city lights on colonies, a rock cluster for belt bodies, the owner's ring; `aim_light()` points
the shader's night side away from the sun). Orbital structures for buildings come from
`OrbitalStructures` (shared with `Planet3D` and the system view), the jump gate from `JumpGate3D`
(shared with `SystemMap`). Environment kind `"solar"` dims the board's sun so the star does the
lighting. Fleets sit at `SYSTEM_FLEET_OFFSET` beside the bodies. Banners, territory, fog, the high-quality
cloud cover and nebula layers (the belt shows as asteroid dust) work unchanged. `SystemMap` opens a
one-body Planet of a system-scale map as a close-up of that world (`_build_body_scene`: the body big in
the middle, lit from the side its sun lies on, no gate; ships hold station round it). `PlanetView` (2D)
draws a single body. Galaxy screen strings switch "system" to "body" where cheap; the body card hides
traits until surveyed.

### Strategic resources and deposits

Civ-style strategic resources make places matter: different bodies (and later, systems) have different
advantages, which drives expansion, trade, raiding and war. Rules: `DepositRules`
(`src/empire/deposit_rules.gd`) plus a few hooks in `EmpireRules`, `ResearchRules`, `GalaxyEngine`.

- **Resources.** `data/empire/resources.json` entries have a `kind`: `basic` (credits, alloys), `flow` (research:
  not stockpiled) or `strategic` (volatiles, rare elements, exotic matter; also `found` and `extracted_by` text
  for tooltips). `DepositRules.strategic()` / `stockpiled()` list them; every stockpiled resource is a key in
  `GalaxyState.resources[faction]`. Major powers start with `economy.json` `deposits.start_stock` unless the
  campaign's `resources` give an amount.
- **Deposits.** A body carries `"deposits": {resource: richness 1-3}`. `GalaxyEngine._roll_deposits` fills every
  body that has none from its type's table (`body_types.json` `deposits: {"chance": [first, second], "table":
  {resource: weight}}`, richness weighted by `deposits.richness_weights`), with its own RNG seeded from the
  campaign seed, so the rest of the campaign's dice don't change. Home systems (owned, or a capital-to-be) get no
  rolls, only one rare-elements 1 on their first rock or belt and one volatiles 1 on their first ice moon or giant.
  Campaign bodies may list `deposits` (kept as given). `SystemLayout._place_deposits` rolls them for a
  system-scale map and shapes the spread: nothing on the homeworld and no rare elements on its moons, volatiles
  within 5 steps of home (added to the nearest ice moon, giant, belt body, cold or wet world or airless rock if
  none rolled), rare elements on at least two rocks or belt bodies 3+ steps out, and exotic matter in exactly
  one place: a non-habitable body 6+ steps from home, as close to a hostile den as possible (richness 2).
- **Extraction.** A building's `"extracts": [resources]` taps those deposits on its body: `DepositRules.extraction`
  yields richness x `deposits.per_richness` per turn, added to `EmpireRules.body_yields` (so blockades stop it,
  and `income()` / `_run_economy` stockpile it). Extractors: colony (volatiles, rare elements of its own world),
  mining base (rare elements, volatiles), gas refinery (volatiles), Ice Mine (volatiles; `"needs_deposit"`),
  Exotic Containment (exotic matter; `needs_deposit`, `requires_tech: exotic_physics`, and `"replaces"`: it may
  be built over the developments it lists, which go when it is finished). `constructor_options` lists a
  `needs_deposit` development only where the deposit is. `SystemRules.default_job` (one-click orders, hints)
  prefers the option that taps the richest known deposit, rarer resources first.
- **Costs.** Any `cost` (units' `strategic.cost`, buildings, megaprojects) may name strategic resources; a tech's
  `"cost_resources"` is paid when it completes. `EmpireRules.cost_of(engine, cost)` scales the strategic part by
  the campaign's `"strategic_cost_mul"` (0.5 in the galaxy-scale campaigns; at least 1); build options, jobs,
  queues, refunds and tech completion all go through it. `EmpireRules.afford_error` names the first missing
  resource ("Not enough rare elements (8 needed, 3 in store)"); `lacks_resources(reason)` recognises those reasons
  (the AI and standing orders wait or save on them).
- **Techs that burn resources.** `_run_economy`: when the current tech's research is complete but its
  `ResearchRules.resource_cost` isn't in store, it waits (points keep banking; `RESEARCH_WAITING {faction, tech,
  reason}` the turn it stalls) and completes, paying, on the first turn they are. Hyperdrive needs exotic matter
  and volatiles, and Exotic Physics.
- **Surveys.** `GalaxyEngine.known_deposits(faction, planet, b)` is empty until the body is surveyed (always known in
  campaigns without surveys). The UI shows "Deposits: ?"; the AI only values what it knows.
- **AI.** `YIELD_WEIGHTS` value strategic output; `strategic_need` multiplies resources the goal tech (Hyperdrive) or
  the next wanted wonder needs and the faction lacks by `NEED_WEIGHT` (rare elements a bit while the store is low).
  Constructor jobs and colony sites count the deposits they would tap (a replacing development counts only its
  gain over what it replaces). Once the goal tech's era is open, `strategic_reserve` keeps its `cost_resources`
  back from other spending (`_spends_reserve`); strategic shortfalls the faction has no income for don't make it
  hoard (`_hopeless`). Exotic Physics is on Hyperdrive's road and in `RESEARCH_PRIORITY`.
- **Presentation.** Top bar chips with diamond pips for strategic resources the player has or produces
  (`GalaxyHUD.set_resource_chip(..., diamond, shown)`; tooltip: stock, sources, untapped deposits, where found,
  extractors, uses from `DepositRules.uses`). `SystemView.deposit_lines` / `deposit_tag` on the body card and in
  the system info; constructor buttons show what they would extract; the hover hint names deposits; on a
  system-scale map `GalaxyOverlay3D` draws a diamond per known deposit after a body's name or tag (filled =
  tapped). Tech cards and the Victory tab show `cost_resources` against the stock; the research chip turns red
  while a tech waits for resources.

### Local battle maps (system-scale campaigns)

`LocalBattleMap` (`src/tactical/maps/local_battle_map.gd`) builds the tactical map of a battle in a
system-scale campaign from the **local area** round the battle cell. `describe(engine, cell, from_cell,
defended)` collects the strategic cells within 3 (terrain, the body on each, the star's offset, the cell
the attacker came from, the defended body); `build(data, desc)` (pure, deterministic, testable without an
engine) expands it onto an 18x13 tactical hex grid: every tactical cell maps to the strategic hex it lies
in at `PATCH` tactical hexes per strategic hex (same orientation), so the battle cell's patch is the
middle of the map and its neighbours ring it.

- A body becomes a disc in the middle of its patch (1, 3 or 7 `planet` hexes by size; a belt body is
  three `asteroid` hexes), with open space cleared round it.
- The star and corona (other than at the battle cell) become impassable `glare` (blocks sight).
- Belt cells become `asteroid` and `debris`; nebulae and storms patches of `nebula`; off-map cells open.
- Deployment: the attacker's six slots are the open cells nearest the map edge in the direction it came
  from (west by default); a defender holding the battle cell's body deploys in a crescent round it facing
  the attacker, otherwise near the centre. Pockets nobody can reach are filled in; the result passes
  `SystemBattleMap.check` (with `MIN_OPEN`, as glare and planets take more room) or another layout is
  tried (thinner belts, then bodies only, then open space).
- Output is the `SystemBattleMap` format (`bodies` for `SystemScenery3D`, `star.dir` towards the real sun,
  `deployment.west`/`east`), plus `"local": true`. `GalaxyEngine.pending_battle_scenario` uses it for every
  battle when `is_system_scale()`; other campaigns keep `SystemBattleMap` and the terrain maps.
  `BattleBoard3D` draws glare as hot plasma puffs.

### System battle maps

`SystemBattleMap` (`src/tactical/maps/system_battle_map.gd`) is a pure, deterministic builder:
a system's star type and bodies (and which body holds the defender's colony) in, a tactical map
Dictionary out, in the same format as `data/tactical/maps/*.json` plus presentation extras. The
layout depends only on the system id, so a system always looks the same.

- Bodies become `planet` terrain discs (impassable, blocks sight) of 1, 3 or 7 hexes by body
  `size` (< 0.65, < 1.0, larger); a gas giant also gets a broken `debris` ring (passable, 2 AP,
  half cover). A belt is a curved band of `asteroid` (impassable) and `debris` cells.
- `bodies` (id, type, `cells`, `center`, `radius` in hex sizes, `colony`) and `star`
  (type, `dir`: unit vector in grid space towards the off-grid star) carry the scenery.
  `BattleEngine.from_scenario` copies them to `BattleState.scenery` for the boards.
- Deployment: the attacker takes six slots on the west edge. A defender owning a colony gets six
  cells in a crescent around the colony disc (facing west), else the east edge.
- `check()` validates every layout (slots inside the grid, free and distinct, every passable
  cell connected to the attacker's slots, at least 70% open). Failing layouts are retried with
  other positions and smaller discs; the last resort is an obstacle-free map.
- Hook: `GalaxyEngine.pending_battle_scenario()` builds the map when the battle cell holds a
  system and puts it in the scenario as an inline `map_def` (`map` is its id). Scenarios without
  `map_def` use `data.maps[map]`; `BattleEngine.map_def_for()` resolves either. Standalone
  scenarios may pass `SystemBattleMap.build_for(...)` output the same way.
- Presentation: `BattleBoard3D` skips the generic backdrop planet and calls `SystemScenery3D`:
  `planet_3d.gdshader` spheres with the body type's surface colours (sunk a little into the
  plane, atmosphere shell, gas giant rings, city lights on the colony, `light_dir` for the night
  side), a glowing star with halos beyond the far edge, and the scene's sun light re-aimed and
  tinted from the star. `debris` cells get small floating rocks. `BattleBoard2D` draws discs
  (`GridMapView.set_scenery`).

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

**Ship models.** Recipes live in `data/models/models.json` (see "Model recipe" in the content
schema). Each ship class has a shared design (the Terran one: `frigate`, `cruiser`, `station`, ...)
and per-species designs named `<model>_<species>` (`frigate_veltari`, `cruiser_kesh`,
`station_sorn`, ...); `ModelFactory.model_for(data, model, species)` picks the species' own design
when there is one, else the shared one. Raider (barbarian) teams and fleets ask for the
`<model>_raider` variant first (scrappy salvage: interceptor, frigate, destroyer). Silhouettes
carry the identity: Terran long spines, boxy blocks, engine banks and rotating rings; Vel'tari
smooth pearl blades and crescents with crystal veins; Kesh bronze birds of prey (a head on a neck,
forward-swept wings, weapon pods, crimson plates); Sorn slate triangular monoliths through level
rings with teal light strips. `Unit3D.model_id_for()` and `Fleet3D` (a lead ship and up to four
escorts in a V on the galaxy map) both go through it.

**Squadrons.** A unit with `visual.squadron` > 1 is drawn on the 3D board as that many craft in
formation inside its hex (`Squadron`: interceptors 5, frigates 3, destroyers 2), each scaled by
`visual.craft_size`; capital ships (cruisers) and stations are one larger model that may overhang
its hex (gameplay stays one hex). Like a Heroes stack, the craft shown follow the hull:
`ceil(n * hull / max_hull)`, at least one while the unit lives; `Unit3D.sync_craft()` breaks up
lost craft (the board plays a small explosion at each) and brings repaired ones back. `Unit3D`
keeps a short history of the formation's transform: each craft takes the formation's place from
a moment ago (its lag in `Squadron.LAGS`) plus its slot, then bobs and rolls on its own, so wings
bank, wheel into broadsides and fly strafing runs slightly staggered without per-craft animation
code. Broadsides ripple down a squadron's craft, every ship of a squadron charges and fires its
spinal gun, and incoming fire lands on a craft (`hit_point()`). Small craft cast no shadows and
get light engine trails; meshes and materials (plumes included) are shared per model, so a
squadron costs draw calls but no extra resources. The 2D board shows a craft-count badge.

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
extruded tiles, overlay buffers for highlights and fog, rocks and nebula puffs, engine
trails, and `space_scenery()`: a deep MultiMesh starfield under the board for parallax,
drifting dust and a distant planet; station interiors only get the stars).

## The mission layer: tactics and story

Reference points: XCOM for the fighting (cover, flanking, overwatch; no hit-chance rolls,
damage stays predictable like the rest of the engine), and tabletop RPGs / Mass Effect for the
story beats (choices with skill checks that depend on who you brought).

- **Cover** (`CoverRules`): terrain with `"cover": "half" | "full"` protects a unit next to it
  from attacks coming from that side (square grids: the orthogonal neighbours toward the
  attacker, both when it's roughly diagonal; hex grids: the first cell on the line). Unit in
  reach of cover but none facing the attacker: flanked. `DamageEffect` applies the multiplier
  unless the ability has a radius. `preview_ability()` reports it (`p["cover"]`) and can preview
  from a hypothetical cell, which the AI uses to find flanks; the AI also prefers firing
  positions with cover (`cover_safety()`). Only deck terrain (walls, crates) has cover, so fleet
  battles are unchanged.
- **Melee**: an ability with `"melee": true` (and `"fx": "melee"`, `"range": [1, 1]`) is hand to
  hand. `DamageEffect` and `preview_ability()` skip directional cover and flanking for it, and
  overwatch reaction shots never use it. Units tagged `"rusher"` (raiders, the infected) get
  `RuleBasedAI.RUSHER_MELEE_BONUS` on melee scores so they close in; the AI otherwise scores melee
  like any ability (it wins when the target is behind cover or only 1 AP is left). Presentation:
  `battle_screen._play_ability` turns a melee ability into the `"melee"` play kind;
  `BattleBoard3D` runs `Unit3D.play_melee()` (lean back, lunge to a stand-off cell, impact
  callback: `Fx3D.melee_impact()` flash, sparks, slash streaks, target `recoil()`, sound `melee`)
  and `BattleBoard2D` does the same with a plain position tween.
- **Overwatch**: an ability with `"ends_turn": true` applying the `overwatch` status. Moves are
  walked cell by cell; when an enemy on overwatch can hit the mover (first enemy-targeted
  damaging, non-area ability in range and sight), it fires at `REACTION_DAMAGE` and the move is
  reported in segments around the shot (`ABILITY_USED` with `reaction: true`). The AI only
  takes turn-ending abilities as a last resort, when an enemy is near.
- **Skill checks**: a choice may have `"check": {"skill": "combat" | "tech" | "command",
  "difficulty": n}` plus `fail_text` / `fail_effects`. Chance = 50% + 15% per point of the
  team's best aptitude over the difficulty (5..95%). Units get `aptitudes` from their JSON;
  heroes from the class (`classes.json`), +1 per two levels. `TRIGGER_FIRED` carries the odds
  per choice and `CHOICE_MADE` the roll. The AI avoids checks it'll probably fail.

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
- `ResearchRules`: tech status (known / available / locked by `requires` and by era), era gating, costs.
- `DiplomacyRules`: opinions, peace acceptance, military strength.
- `EventRules`: galactic events (conditions, rolling, choices, applying outcomes).
- `VictoryRules`: which victories a campaign uses and how close each major power is.

**Turn start** (`GalaxyEngine._run_economy`): add income (net of ship upkeep) to the stockpiles.
Research points go into the current tech (unspent points are banked). Each planet's build queue
advances, and finished ships join the fleet in orbit or form a new one; finished megaprojects
are added to the system. Colonies grow (unless the treasury is in debt), temporary modifiers
tick down, and opinions of factions at peace drift up. Then fleets repair, commanders earn
Fleet Academy XP and, for a major power in a campaign with events, a galactic event may be offered.

**Commands:** `SetResearchCommand`, `QueueBuildCommand` (paid up front, one item per planet),
`DiplomacyCommand` (`propose_peace`, `declare_war`, `gift`; `offer_peace`, `accept_peace`,
`refuse_peace` for AI offers to the player, see Leaders and diplomacy screens).

**Tech effects** (`data/empire/techs.json`):

| Effect | Meaning |
| --- | --- |
| `ship_status` | a (hidden, permanent) status every ship starts battles with |
| `empire_modifier` | `fleet_speed`, `sensor`, `field_repair`, `growth` (added to every colony's growth per turn), `upkeep` (added to the upkeep multiplier, e.g. -0.2), `trade_income` (extra credits per friendly minor power), `opinion_drift` (extra opinion per turn at peace), `hero_xp` (XP per turn for fleet commanders) |
| `yield` | multiplies a resource's output |
| `body_bonus` | per-body bonus: `body_types` and/or `categories` (neither = every body), optional `building` the body must hold, `yields` added to that body's output (before `yield` multipliers), `colony_slots` added to its colony slots, `pop_cap` added to its population cap and/or `growth` added to its growth rate. Applied by `EmpireRules.body_yields` / `colony_slots` / `pop_cap` / `growth_rate` for the owner |
| `unlock_building` / `unlock_unit` / `unlock_megaproject` | informational: what the tech opens (the real gate is the `requires_tech` on the building, unit or megaproject) |

Species effects, megaproject effects and active event modifiers use the same effect types, and
`EmpireRules.tech_effects` merges all four sources.

The colony techs use `body_bonus`: Terraforming (+1 colony slot on desert and arctic worlds),
Orbital Habitats (+1 credits per colony), Asteroid Refining (+2 alloys per belt mining base),
Deep Core Taps (+2 alloys per volcanic mining base) and Cryogenic Labs (+2 research per research
station on ice moons and gas giants).

**Diplomacy:** relations default to war unless the campaign says otherwise. At peace, fleets
can't attack or pass through each other and planets can't be captured. An AI accepts peace if
its opinion of you is at least 10 or it's clearly losing, but never within 3 turns of the war
starting, and never if it's `always_hostile`. Being attacked (−15), losing a planet (−20) or
having war declared on you (−30) lowers opinion. Gifts (+10) and time at peace (+1/turn) raise it.
Events: `WAR_DECLARED`, `PEACE_SIGNED`, `PEACE_REFUSED`, `GIFT_SENT`, `FIRST_CONTACT`,
`PEACE_OFFERED`, `PEACE_OFFER_REFUSED`.

**System defenses:** buildings with a `defense_unit` put immobile units (`"immobile"` tag) into
any battle at that system, and so does the base garrison (`orbital_battery`). A fleet entering an enemy system with no fleet on it fights
the platforms and the base garrison; if it wins and none survive, it moves in and takes the system as
described under conquest above. Destroyed platforms are removed; the garrison is simply beaten while the
attacker stays.

**Victory** (`VictoryRules`, `GalaxyEngine._check_eliminations` / `_complete_megaproject` /
`_end_faction_turn`). A campaign ends when:
- *conquest*: the last major power stands (or the scenario's `victory.eliminate` target is gone:
  `reason` "objective");
- *treaty* ("peace"): every surviving major is at peace with every other, and the highest
  `EmpireRules.score` wins (switch off with `"victory": {"peace": false}`; random_sector does);
- *science*: a megaproject flagged `"victory": "science"` (the Ascension Gate) completes;
- *score*: the turn limit passes and the highest score wins; without it ("max_turns") nobody does.

The campaign's `victory` block turns kinds on or off (`science`, `score`, `peace`). A campaign with
an `eliminate` objective has science and score off unless the block says otherwise, so The Drift
keeps its objective ending. `state.victory_reason` records which one ended the game. The empire
panel's Victory tab renders `VictoryRules.progress(engine)`.
`EmpireRules.score` = 100/system + 25/tech + 8/pop + 150/megaproject + hull/10 + 10/hero level.

**AI:** each turn it first answers a pending galactic event (scoring every choice), then researches
along a priority road (`GalaxyAI.RESEARCH_PRIORITY`: growth and economy, then the eras, then the
road to Ascension), gives idle planets a build order (a megaproject when unlocked and the system is
among its most populous; ships when outgunned, or when rich, as long as `income` stays above the
upkeep margin; otherwise economy buildings in priority order, skipping buildings that would do
nothing yet, and holding back to save for a megaproject), makes peace with AI factions that would
accept, and declares war on hated weaker neighbours, on a rival close to the Ascension Gate, on a
runaway score leader, or on a much weaker neighbour (`war_ratio` personality). Small fleets wait at
their shipyard for ships under construction. Fleets only hunt enemy fleets within 5 jumps; beyond
that they go for planets.

### Empire depth: population, upkeep, eras, megaprojects, events

**Population.** A colony body has `pop` (1..cap) and `growth` (progress). Cap = the body type's
`pop_cap` + trait `pop_cap` + building `pop_cap` (Orbital Habitat +4) + `body_bonus` techs.
Growth per turn = (`economy.growth.base` + building `growth` + `growth` techs/modifiers) x
(1 - `slowdown` x pop/cap): it slows as the colony fills and stops at the cap. A pop costs
`cost_base + cost_per_pop x pop` progress. Buildings yield their flat `yields` plus `pop_yields`
for each pop above the first, so a new colony pays exactly what it always did. Capturing a system
costs each colony `capture_pop_loss` (25%, rounded up) of its people; barbarian plunder costs
`plunder_pop_loss`; never below 1. New colonies start at 1 (`SystemBuilder`: `"pop"` on a body def
overrides it, and the generator gives home worlds 3).

**Upkeep.** Units' `strategic.upkeep` is the credits a ship costs per turn. A major power's colonies
carry `free_base + free_per_colony x colonies` credits of it for free; `upkeep_mul` techs
(`empire_modifier` stat `upkeep`) scale the rest. `EmpireRules.income()["credits"]` is net;
`gross_credits` and `upkeep` are returned alongside. If the treasury goes negative
(`BUDGET_CRISIS`): colonies stop growing, fleets stop repairing, and every ship loses
`debt.hull_loss` of its max hull (never below 1) each turn, until it is positive again.

**Eras.** Techs carry `era` (1-3). `data/empire/eras.json` gives each era a `name`, a
`cost_mul` (research cost multiplier) and `requires: {era, count}`: it opens once the faction knows
`count` techs of that earlier era. `ResearchRules.status` is LOCKED until the era is open and the
`requires` prerequisites are known.

**Megaprojects** (`data/empire/megaprojects.json`). Built like buildings (`QueueBuildCommand` with
kind `"megaproject"`, paid up front, one item per system) in a system with a colony, once the
`requires_tech` is known. `scope: "empire"` allows one per empire (also blocked while it is being
built elsewhere); `scope: "galaxy"` allows one in the whole galaxy: nobody can start it once it
stands anywhere or while another empire is building it. They are stored on the system
(`Planet.megaprojects`) and pass to whoever captures it; their `yields` go to the system and their
`effects` to the owner. `MEGAPROJECT_STARTED` and `MEGAPROJECT_COMPLETED` are galaxy-wide events.
One flagged `"victory": "science"` ends the game when it completes (hidden when the campaign has
science victory off).

**Galactic events** (`data/strategic/events.json`, campaigns opt in with `"events": true`). At a
major power's turn start, once `first_turn` has passed and `every` turns after its last event, there
is a `chance` it is offered a random eligible event (`EventRules.roll`, from the campaign RNG:
weighted, conditions met, not seen within `repeat_cooldown`). The pending event
(`state.pending_event`) blocks all other commands until a `ResolveEventCommand(faction, choice)`
answers it; the galaxy screen shows a dialog, the AI scores the choices
(`GalaxyAI.choose_event_choice`).

**Tools.** `tools/simulate_campaign.gd` prints win shares, how games end, and the majors' economy;
add `--verbose` for a line per run.

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
`visual.model` names the 3D model (data/models/models.json; species fly `<model>_<species>` when
it exists). `visual.attack_style` sets how a ship delivers its direct-fire (projectile/beam)
weapons on the 3D board: `run` (strafing pass and loop back, fighters), `broadside` (turns side-on
and ripple-fires), `spinal` (charge, one heavy slug, recoil). `visual.squadron` (1-8, default 1)
draws the unit as that many craft in formation and `visual.craft_size` scales each craft (or the
single ship) on the 3D board; `visual.size` still scales the 2D sprite and galaxy models.

**Model recipe** (`data/models/models.json`, built by `ModelFactory`; +x is forward, +y up, one
unit is a hex radius)
```jsonc
"frigate_kesh": {
  "plating": true,            // hull-plating shader + greebles ("greebles": false, "windows": 0-1, "panels": scale)
  "base": "",                 // optional: another model whose parts come first (people build on "humanoid")
  "parts": [
    {"type": "hull", "outline": [[x, z], ...], "height": 0.2, "bevel": 0.3, "taper": 0.15, "material": "hull"},
    {"type": "sweep", "path": [[x, y, z, half_width, half_height], ...], "shape": "hex", "subdiv": 3,
     "smooth": true, "material": "trim", "mirror": true},
    {"type": "ring", "radius": 0.4, "tube": [0.05, 0.03], "axis": "y", "arc": 250, "start": 55,
     "taper": true, "material": "hull"},
    {"type": "cylinder", "radius": 0.06, "length": 0.03, "axis": "x", "at": [-0.7, 0.15, 0.1], "material": "engine"}
  ]
}
```
Part types: `hull` (extruded, bevelled top-view polygon), `box`, `cylinder`, `cone`, `sphere`, `rock`,
`sweep` (a cross-section, `diamond` / `box` / `oct` / `hex` / `lens` / `blade` / `tri` / `keel` / `wedge` /
`round` or custom, swept along a Catmull-Rom path; zero size makes a tip) and `ring` (a torus or a
tapered arc: crescents). Any part takes `at`, `mirror` (copy across z), `rot` / `pitch` / `roll`
(degrees), and `spin` (degrees per second around x through `pivot`: rotating sections).
Materials: `hull`, `dark`, `trim`, `glass`, `glow`, `accent` (team colour), `stripe` (glowing team
colour), `engine` (glowing; cylinders along x get exhaust plumes), `gold`, `visor`, `rock`,
`hazard`, and the blinking `light_red` / `light_green` / `beacon`. Triangles are wound to match
their normals. Ship recipes are authored with mirrored parts and kept symmetric except for raiders.

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
  "melee": false,            // true: hand to hand, ignores cover, plays a lunge (use "fx": "melee", range [1, 1])
  "fx": "torpedo"            // presentation hint: projectile | beam | torpedo | pulse | self | melee
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
  "squad_size": 4, "marine_unit": "marine", "requires_hero": true, "recommended_level": 2,
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
- `resources.json`: `name`, `description`, `color` and `kind` per resource: `basic` (`credits`, `alloys`), `flow`
  (`research`) or `strategic` (`volatiles`, `rare_elements`, `exotic_matter`, with `found` / `extracted_by` text).
- `buildings.json`: `name`, `description`, `cost` (may include strategic resources), `turns`, and optionally
  `yields`, `shipyard: true`, `defense_unit`, `requires_tech`, `extracts: [resources]` (taps those deposits on its
  body), `needs_deposit: resource` (only where there is one), `replaces: [building ids]` (may be built over them).
- `techs.json`: `name`, `description`, `cost`, `requires`, `effects` (see the table above), and optionally
  `cost_resources: {resource: n}` (paid when the research completes; it waits until they are in store).

Units gain `strategic.cost`, `build_turns` and `requires_tech`. Civilian ships (`data/tactical/units/colony_ship.json`,
`constructor.json`, `troop_transport.json`) add `civilian: true`, `role` (`colony` | `constructor` | `transport`) and,
for the Colony Ship, `min_pop` / `pop_cost`. `orbital_battery` is the base garrison unit (no `strategic` block);
`economy.json` has a `garrison` block (`unit`, `base`, `pop_per_extra`, `max`) and `jobs.refund`.
Campaigns gain `resources: {faction: {credits, alloys}}`,
`relations: [{factions: [a, b], status: "peace"|"war", opinion}]`, `techs: {faction: [ids]}`,
system `bodies` (with `buildings`), faction `always_hostile`, and faction `ai` (personality overrides for
`GalaxyAI`: `attack_ratio`, how much stronger than the target a fleet must be to attack,
default 0.9; `hunt_range`, default 5; `retreat_hull_ratio`, default 0.5). In *The Drift* the
traders are cautious (1.4, range 3) and the raiders only take even-or-better fights (1.0).

**Galaxy terrain** (`data/strategic/terrain.json`): `passable`, `move_cost`, `color`,
`decoration` ("rocks"), `battle_map`.

**Star systems.** `Planet` (the class keeps its historical name) is a star system: `star`
(`star_types.json`) and `bodies: [{id, name, type, traits, buildings}]`. Body types
(`body_types.json`) have a `category` (habitable / rock / belt / gas / ice), `size`,
`colony_slots`, a `bonus` paid once the body is developed and shader `surface` colours.
Buildings (`data/empire/buildings.json`) are either developments (`"on": [categories]`, one per body:
colony, mining base, research station, gas refinery, outpost) built by Constructors (the colony is
`"founded": true`, made by a Colony Ship) or colony buildings (`"needs": "colony"`, up to the colony's
slots: shipyard, trade hub, defense platform) built from the queue. `EmpireRules.build_options()` lists
what the queue can build; `EmpireRules.constructor_options()` what a Constructor can build on a body;
yields come only from developed bodies (buildings + bonus + traits) times tech multipliers. Campaign systems list `bodies` explicitly or omit them for a seeded random set
(`SystemBuilder`; `"home": true` guarantees a terran world). Galaxy views draw a system as its
star with bodies on tilted orbits (`Planet3D`, `PlanetView`); the **system view**
(`SystemView`: a big `SystemMap` with clickable bodies and the ships drawn at them, and a side panel
with the selected body's actions, the ships in the system and the build queue) is where the player
works a system.

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

System-layer campaign keys: `"start": "owned"` (default: homes belong to their powers) or `"colony_ship"`
(generated campaigns only: every major power's home system starts unclaimed with `Planet.capital =
{faction, buildings, pop}` and the template's home `buildings` become the capital's; its first fleet starts
in the home system), `"start_ships": [unit ids]` (deployed in each such home system), and a system entry
may list `"civilians": [{unit, name?, owner?}]` (ships deployed in it at the start).

### Empire depth content

**Economy tuning** (`data/empire/economy.json`)
```jsonc
{ "growth": { "base": 1.0, "cost_base": 5.0, "cost_per_pop": 1.5, "slowdown": 0.5, "capture_pop_loss": 0.25, "plunder_pop_loss": 1 },
  "upkeep": { "free_base": 3, "free_per_colony": 2 },
  "debt": { "hull_loss": 0.05 },
  "events": { "every": 5, "chance": 0.75, "first_turn": 6, "repeat_cooldown": 30 },
  "hero_names": ["..."], "megaproject_score": 150, "pop_score": 8 }
```

**Eras** (`data/empire/eras.json`): `{"2": {"name", "description", "requires": {"era": 1, "count": 5}, "cost_mul": 1.6}}`.
A tech's `"era"` (default 1) puts it in one; a tech can't require one of a later era.

**Buildings** (`data/empire/buildings.json`) gained: `pop_yields` (per pop above the first, like
`yields`), `pop_cap`, `growth`, `sensor` (system sensor range), `hero_xp` (XP per turn for fleet
commanders), next to `yields`, `cost`, `turns`, `needs`/`on`, `requires_tech`, `shipyard`,
`defense_unit`. Body types have `pop_cap`; traits may have `pop_cap`; units may have
`strategic.upkeep`.

**Megaprojects** (`data/empire/megaprojects.json`)
```jsonc
{ "stellar_forge": { "name": "...", "description": "...", "requires_tech": "stellar_engineering",
    "scope": "empire",            // or "galaxy": one in the whole galaxy
    "victory": "science",         // optional: completing it wins the game (needs science victory on)
    "cost": {"credits": 120, "alloys": 220}, "turns": 8,
    "yields": {"alloys": 8},      // added to the system
    "effects": [{"type": "yield", "resource": "alloys", "mul": 1.1}] } }  // tech-style effects for the owner
```

**Galactic events** (`data/strategic/events.json`)
```jsonc
{ "market_boom": { "name": "Market Boom", "weight": 3, "min_turn": 8, "max_turn": 999,
    "conditions": [ {"type": "has_colony"} ],
    "text": "... {planet} ...",
    "choices": [   // 2-3
      { "label": "Invest in the boom", "hint": "shown under the label", "cost": {"alloys": 20},
        "requires": [ {"type": "has_building", "building": "mining_base"} ],
        "chance": 0.6,                       // optional (default 1): else fail_effects / fail_result
        "effects": [ {"type": "modifier", "id": "market_boom", "name": "Market boom", "turns": 8,
                      "effects": [ {"type": "yield", "resource": "credits", "mul": 1.25} ]} ],
        "result": "...", "fail_effects": [], "fail_result": "..." } ] } }
```
Conditions (`EventRules.CONDITIONS`): `has_colony`, `growing_colony`, `pop_min {n}`, `min_colonies {n}`,
`turn_min {n}`, `turn_max {n}`, `at_war`, `at_war_major`, `at_peace_minor`, `barbarians`,
`has_building {building}`, `has_shipyard`, `has_fleet`, `researching`, `credits_min {n}`,
`credits_max {n}`, `tech_known {tech}`, `has_hero`.
Effects (`EventRules.EFFECTS`): `resources {credits, alloys}`, `research {amount}`,
`pop {amount, target: context|random|all|largest}`, `damage_building`, `free_building {building}`,
`repair_fleets {amount}`, `damage_fleets {amount}`, `opinion {with: minor|random_major|war_target|all_majors, amount}`,
`raiders {count}`, `free_ship {unit}`, `free_hero`, `modifier {id, name, turns, effects}` (effects
of type `yield`, `empire_modifier` or `body_bonus`), `item {item}`. The content test rejects unknown
types, resources, units and buildings.

**Campaign** additions: `"events": true`, `"victory": {"eliminate": faction, "science": bool, "score": bool, "peace": bool}`,
faction `"ai": {"war_ratio": n}`, and a body's `"pop": n` for starting colonies.
System-scale campaigns add `"scale": "system"`, `"system_generate"` (see SystemLayout), `"survey": true`,
`"research_cost_mul"`, `"victory": {"tech": id, "tech_reason": text}`, faction `"ship_variant": "species"`
and barbarian `"fleet_name"`. Techs may carry `"scale"`; discoveries `"listed_only": true` (only placed where
a campaign names them, not in random sectors).

## Conventions

- Typed GDScript everywhere (`var x: int`, `-> void`). The editor catches more errors that way.
- `class_name` on every reusable script, so there are no `preload` paths to maintain.
- Engine code never references nodes, scenes or `Input`. Presentation code never changes `BattleState`.
- Events are dictionaries with a `type` from `BattleEvents`. Add new fields freely; renderers ignore what they don't know.
- Tests use the fixed-number units in `tests/fixtures.gd`, so rebalancing real content doesn't break rules tests.


## Rendering tiers and imported models (graphics proof of concept)

- `BoardGeometry.build_environment(parent, hq)`: with `hq` and when `high_quality()` (Forward+ renderer
  and `GameSettings.battle_look == "high"`), boards get `_build_hq_environment`: a procedural sky
  (`shaders/space_sky.gdshader`, used for background, ambient light and reflections), AgX tone
  mapping, SSAO, glow, light volumetric fog and a soft-shadowed sun. The battle board uses it; the
  2D canvas backdrop is hidden then (a background canvas layer would draw over a sky). On the
  Compatibility renderer nothing changes. Board tiles are matte and open space has no tile fill in
  this mode.
- Imported models: a `data/models/models.json` entry with `"mesh"` (OBJ/glTF resource), `"texture"`,
  `"forward"` (the nose axis in the source: `+z`/`-z`/`+x`/`-x`), `"length"` (model units) and
  `"engines"` (`[[x, y, z, radius]]`, normalised space: +X forward) is turned, centred and scaled
  into recipe model space by `ModelFactory._build_imported`, so squadrons, banking, attack styles and
  plumes work unchanged.
- A battle team may name `"model_variant"`: its ships use `<model>_<variant>` (e.g. `frigate_qt`)
  where that exists. The showcase scenarios (`data/scenarios/showcase_*.json`) use `qt` / `qtr`.

- Galaxy map (high quality): `GalaxyBoard3D._build_hq_layers` paints world-space masks over the map
  (terrain: R nebula, G ion storm, B asteroid dust; explored: R explored, G visible now, repainted on
  fog changes) at `MASK_PPU` pixels per unit. `galaxy_cloud_cover.gdshader` (one quad at fog height)
  draws uncharted space as cloud banks and a dark veil over charted space out of sensor range;
  `galaxy_nebula_layer.gdshader` draws three stacked additive slices of nebula / storm / dust. Terrain
  tiles, the old fog slab and nebula puffs are skipped. Stars use `star_surface.gdshader` plus a
  billboard `star_corona.gdshader` (also in system battles); the system view uses
  `build_environment(..., "system")` and a shadowed point light at the star.
- Desktop builds pick Forward+ (`rendering_method.pc`); the base setting stays Compatibility for the
  web. On the classic look (Compatibility, or `battle_look == "classic"`) station decks keep the
  classic environment and dressing, dimmed on Forward+ to match.
- Station decks (high quality): `build_environment(parent, true, "deck", mood)` builds
  `_build_deck_environment`: a dark void, low tinted ambient, AgX, strong SSAO, light SSIL, bloom
  for light strips and screens, volumetric fog (only the deck's haze volume adds density) and a
  per-channel colour grade. `DeckKit.build(board, parent, hq, mood)` then raises the walls
  (`HQ_WALL_H`) with lit caps, adds wall screens, themed cover (`mood.props`: cargo, lab,
  industrial, derelict, wreck; consoles, benches, specimen tanks, ore bins, pipes, lockers, debris,
  all merged into one mesh per material), stencilled bay numbers, door lamps, and per-room ceiling
  spot lamps (rooms = floor flood-filled between bulkheads and doors; at most `MAX_SHADOWED` cast
  soft shadows), red pulsing emergency beacons with dimmed lamps, stuttering lamps and fires
  (`DeckLightAnimator`, no allocations per frame). Surfaces use `deck_surface.gdshader`
  (world-space grime, tread, seams, scuffs, scorch marks; `glow` for strips and screens), the haze
  is one `FogVolume` with `deck_haze.gdshader`, grid lines use `deck_grid.gdshader`.
- Deck fog of war (high quality): all three shaders read one RG8 mask texel per cell (R explored,
  G visible now), written by `DeckKit.set_fog` from `BattleBoard3D.set_fog`. Unexplored cells are
  discarded (nothing leaks from any camera angle; a dark slab under the deck fills the holes),
  explored ones out of sight are dimmed; lamps, fires and door lamps are board props (hidden while
  their cell is unexplored). The classic fog slab is not drawn. Reachable cells show as a faint
  wash with a lit outer border (`_reach_area`) over explored floor only.
- People on decks (high quality): `Unit3D.add_deck_light()` adds a soft team-tinted light over
  each person and a glowing team ring. `Fx3D` (any high-quality board) flashes light at the muzzle
  and gives bolts a brighter, wider light.
- Map `"mood"` (deck maps, read by `DeckMood.from_map`, ignored by the classic look): `ambient`,
  `ambient_energy`, `light` / `light_energy` (ceiling lamps), `accent` / `accent2` (strips,
  screens, door lamps), `haze` / `haze_density`, `shadows` / `highlights` (colour grade),
  `exposure`, `saturation`, `emergency` and `flicker` (0..1 shares of rooms / lamps), `fires`
  (count), `grime`, `scorch` (share of cells), `props` (cover theme). Every key is optional.
