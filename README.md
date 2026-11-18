# space-homm (working title)

Turn-based sci-fi strategy: a Civ-style galaxy map, Heroes-style tactical battles
and Mass Effect-style hero missions, all built on **one shared tactical engine**.

**Status:**
- **Step 1 (done):** tactical battles. Two ship types, six abilities, four status effects,
  terrain, line of sight, a rule-based AI and auto-resolve.
- **Step 2 (done):** the galaxy map. Fleets with persistent ships, fog of war, planets to
  capture and repair at, hidden-fleet ambushes, a strategic AI, and moving into an enemy
  fleet to start a battle you can **Fight** (battle screen) or **Auto-resolve**. Hull
  damage carries over between battles.
- **Step 3 (done):** heroes and the first mission. Named heroes with classes, levels, skills,
  gear, traits, loyalty, injuries and optional permadeath. Heroes command fleets (a doctrine
  bonus in fleet battles) and lead away teams. Anomalies on the galaxy map launch missions:
  ground missions on a square grid with fog of war, dormant enemy groups, story choices,
  reinforcements and objectives. A failed mission turns into a rescue mission for captured heroes.
  *The Drift* has two: the **Derelict Station** (reach the data core) and the **Silent Relay**
  (hold the relay room for 8 rounds against raider waves), each with its own rescue follow-up.
  Three more squad missions add variety: **Smuggler's Freighter** (board a cargo ship, fight
  through its holds, and choose between a hostage and the cargo), **Plague Lab** (a quarantined
  station run mostly on Tech checks, with infected drones breaking out in timed waves while you
  reach the evacuation lock) and **Ambush at the Wreck** (survive raiders arriving from every
  side of a crash site; failure leaves a rescue mission at the raiders' salvage camp).
- **Step 4 (done):** empire systems. Credits, alloys and research from planets and buildings;
  build queues for buildings and ships; a tech tree (ship upgrades, faster fleets, sensors,
  yields, defense platforms, the Destroyer, and colony techs that deepen the body economy:
  Terraforming, Orbital Habitats, Asteroid Refining, Deep Core Taps, Cryogenic Labs); a third faction, the Ceres Free Traders, with
  war/peace, opinion, peace proposals and gifts; defended planets that fight back.

## Running it

1. Install **Godot 4.5** (standard build, not .NET): <https://godotengine.org/download>.
   On a Mac, drag it into Applications. It runs natively on Apple Silicon.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button). On the title screen, pick **New campaign** (choose the
   campaign, your species, permadeath and an optional seed), or **Continue** the latest save.

**Settings** (title screen, or the in-game menu): fullscreen (also `F11` / `Alt+Enter`),
volume, and whether the galaxy map and battles open in 3D or 2D. They're remembered between runs.

Saving: the game autosaves at the start of each of your turns. `Esc` (with nothing selected)
or the **Menu** button opens the in-game menu with Save (three slots), Load, Main menu and
Quit. `F5` quicksaves and `F9` loads the quicksave. Saves live in Godot's user data folder
(`user://saves/`; on a Mac that's `~/Library/Application Support/Godot/app_userdata/space-homm/`).

To jump straight into a single battle, open `src/presentation/tactical/battle_screen.tscn`
and press **F6** (run current scene).

### Galaxy controls

| Input | Action |
| --- | --- |
| Click your fleet | Select it (blue hexes = move, red = attack) |
| Click a blue / red hex | Move there / attack the fleet there |
| Click a planet or visible enemy | Show info (click your own system to open it) |
| Click your selected fleet again / `S` | Open the system it's parked in |
| `Tab` / **Next Fleet** | Next fleet with moves left (the button counts them; fleets that can still move have a bouncing arrow, spent ones fade) |
| Click your other fleet | Merge into it (asks first; up to 6 ships, one commander) |
| `D` | Detach ships into a new fleet on a neighbouring system |
| Right-click / `Esc` | Deselect (`Esc` with nothing selected opens the menu) |
| `F5` / `F9` | Quicksave / load the quicksave |
| `Space` / `Enter` | End turn |
| `E` | Empire panel: colonies and build queues, research, diplomacy |
| `H` | Heroes panel: gear, levels, assign/relieve fleet commanders |
| `A` | Toggle autoplay (AI plays your faction too) |
| `V` | Switch between the 2.5D (3D) and top-down (2D) galaxy map |
| Mouse wheel / `Q` `R` / right-drag / arrows / middle-drag | 3D map: zoom / rotate / rotate and tilt / pan / pan |

The 3D map opens on the area you've explored; zoom out with the wheel to see the whole sector.

Battle and mission offers show the **auto-resolve odds** (from a dozen simulated runs) so you
can decide whether to fight it yourself.

Two campaigns:
- **Random Sector** (the main game): a new generated sector every game. You and two AI empires
  (the Vel'tari Concord and the Kesh Dominion) compete for the stars; raiders prey on everyone;
  the Free Traders deal with whoever treats them well. Enter a seed to replay a sector.
- **The Drift (scenario)**: a short hand-made scenario: clear the raider dens out of the Drift.

**Species.** Pick who you play on the New Campaign screen. All are humanoid; the differences
are deliberately subtle:

| Species | Empire | Bonus | Ships | Squad ability |
| --- | --- | --- | --- | --- |
| Human | Terran Alliance | +10% credits, +1 sensor range | standard | Mark Target (enemy takes +25% damage) |
| Vel'tari | Vel'tari Concord | +20% research | +15% shields; pearl hulls, crystal fins | Mind Ward (you and adjacent allies: shields and -25% damage) |
| Kesh | Kesh Dominion | +15% alloys | +10% damage; bronze hulls, rams | Blood Oath (heal and +20% damage) |
| Sorn | Sorn Directorate | +1 fleet speed | 8% less damage; slate hulls, dorsal ridges | Shadow Veil (-50% damage for a turn) |

Each species also has its own names (`names` in `data/strategic/species.json`): your home
system, starting fleets, ships and heroes are renamed to match the species you pick, and the AI
power that would have had your species gets the human names instead.

**Other powers.** The raiders are **barbarians**: their dens launch new raider fleets every few
turns; they plunder systems (stealing credits and wrecking a building) rather than holding
them, never negotiate and can't win, and clearing a den pays loot. The Free Traders are a
**minor power**: they stay near home and don't compete for victory, and pay trade income
(+3 credits at opinion 30, +6 at 60) to empires at peace with them. Only the major powers win.

**Every game is different:** the seed scatters one-time **discoveries** across the sector
(derelict hulks to salvage, strange signals, smugglers' caches, escape pods). Fly a fleet in to
find out what's there: resources, research, a free ship, star charts, an item, or now and then
a trap. Bodies in unclaimed systems may roll **traits** (rich deposits, ancient ruins, rare
gases, vast continents, subsurface ocean, hostile biosphere) that pay once you develop them.

**Star systems.** The map's systems each have a star and a few bodies: habitable worlds
(terran, ocean, desert, arctic), rocks (barren, volcanic), asteroid belts, gas giants and ice
moons. Move a fleet in to claim a system; enemy systems are captured the same way (defended
ones fight back). Then develop it body by body: click your system (or select one and press
**S**) to open the **system view**. Habitable worlds take a **colony** (taxes, some research,
and slots for a shipyard, trade hub and defenses), rocks and belts a **mining base**, ice moons
and gas giants a **research station** (gas giants also a **gas refinery**). Undeveloped worlds
produce nothing, so a system with a habitable world and rich rocks is worth fighting over.
One build at a time per system; ships need a shipyard. Friendly fleets in your systems repair
25% hull per turn. Nebulae and asteroid fields cost 2 moves, and battles there are fought on
matching battle maps.

Empire (E): every system's output, research (points flow into the tech you pick) and
diplomacy. The Free Traders start at peace with you and at war with
the raiders. At peace you can't attack each other or take each other's planets. Propose peace,
declare war or send gifts in the Diplomacy tab. The raiders never negotiate. The war ends when
nobody left is at war (the highest score wins) or when one faction stands alone.

Heroes: a hero commanding a fleet gives its ships a doctrine bonus in battle (Vanguard: -10%
damage taken, Marksman: +10% damage, Technician: shield regeneration) and earns XP. To pick
up a hero waiting at a planet, bring a fleet there and assign them in the Heroes panel.
Anomalies (purple **?**): end a move on one with a commanded fleet to get a mission briefing.
Launch it, auto-resolve it, or leave it for later. The hero is away for a couple of turns
afterwards, and the fleet loses its doctrine bonus meanwhile.

### Battle controls

| Input | Action |
| --- | --- |
| Click a blue hex | Move (costs AP; nebula hexes cost 2) |
| `1`–`3` or ability button | Select ability, then click a red hex |
| Right-click / `Esc` | Cancel targeting (`Esc` otherwise opens the menu: settings, let the AI finish, quit) |
| `Space` / `Enter` | End turn |
| `A` | Toggle autoplay |
| `R` | Restart (standalone battles only) |
| `V` | Switch between the 2.5D (3D) and top-down (2D) battle view |
| Mouse wheel / `Q` `E` / right-drag / arrows / middle-drag | 3D view: zoom / rotate / rotate and tilt / pan / pan |

Hover over targets to see the expected damage before you commit. In missions, the green ★
marks the objective, yellow **?** marks something to investigate, and enemies stay hidden
(and mostly asleep) until your squad can see them.

Squad missions play like XCOM with story beats like a tabletop RPG:
- **Cover is directional.** Walls next to you are full cover (-50% damage) and crates half
  cover (-30%) against attacks from that side; get hit from an open side while hugging cover
  and you're **flanked** (+25%). Hovering a move shows the cover you'd have against each
  visible enemy; the attack preview shows the target's. Grenades and other area attacks ignore
  cover.
- **Hand to hand.** Everyone close to an enemy can fight: marines carry a **Combat Knife** and
  raiders a **Vibro-Blade** (2 AP, adjacent only), the infected tear with **Rending Claws**, and
  heroes have a signature move (Vanguard **Shield Bash** staggers, Technician **Stun Baton**,
  Marksman a knife). Melee **ignores cover**, so it is how you dig out someone behind a wall; the
  attacker visibly lunges in. Raiders and the infected like to rush you.
- **Overwatch** (1 AP, ends your turn): the first enemy that moves within range and sight
  takes a reaction shot (75% damage). Raiders use it too.
- **Skill checks.** Some story choices test Combat, Tech or Command. The button shows the odds,
  from your squad's best aptitude (hero class + level; marines have a little Combat and Tech);
  failure has its own consequences. Bring the right hero for the job.
- **Loot.** Each mission hides a couple of random supply lockers (gold **$**): credits, parts,
  research data, gear or raider intel. Completing a mission also rolls a bonus. Intel charts
  the systems around enemy planets on the galaxy map.

## Art and credits

- Ships, lasers, meteors, effect sprites, the Kenvector fonts and sound effects:
  **Kenney** "Space Shooter Redux" (CC0, `assets/kenney_space_shooter/`, see its README/LICENSE).
- Planets (2D and 3D), atmospheres, the fog of unexplored space and the space backdrop are
  procedural shaders (`src/presentation/shaders/`).
- 3D models are procedural: each is a recipe of parts (bevelled hulls, boxes, cylinders, cones,
  spheres, rocks) in `data/models/models.json`, built at load time by
  `src/presentation/models/model_factory.gd`. Units pick one with `visual.model`; the `accent`
  material takes the team color. Engine parts get team-tinted exhaust plumes automatically;
  `light_red` / `light_green` / `beacon` parts blink and `stripe` parts glow. A model can name a `base` whose parts come first: the
  trooper, hero and boarder all build on `humanoid`. Add or reshape a model by editing JSON.
- The UI theme is built in code (`src/presentation/shared/game_theme.gd`); colors live in `palette.gd`.
- Ship sprites are set per unit in JSON (`visual.sprite`, with `{team}` replaced by the team's
  color variant). Battle maps can set `backdrop` colors and `floor: "deck"` for interiors.
  Body types set `surface` colors for the planet shader.

## Tests and tools (headless, no editor needed)

```bash
# one-time: build Godot's class cache (also done automatically by opening the editor)
godot --headless --path . --import

# unit + integration tests (exit code 1 on failure)
godot --headless --path . -s res://tests/run_tests.gd

# balance: auto-resolve a battle scenario N times
godot --headless --path . -s res://tools/simulate_battles.gd -- --scenario=first_skirmish --runs=200

# balance: play whole campaigns AI-vs-AI
godot --headless --path . -s res://tools/simulate_campaign.gd -- --campaign=the_drift --runs=50

# smoke tests of the real screens (AI on all sides)
godot --headless --path . -s res://tools/smoke_battle_screen.gd
godot --headless --path . -s res://tools/smoke_campaign.gd
```

On macOS the binary is `/Applications/Godot.app/Contents/MacOS/Godot`; alias it to `godot`.
CI runs the tests and both smoke tests on every push (`.github/workflows/tests.yml`).

## Adding content (no code)

- **New ship:** add `data/tactical/units/<id>.json` (including `strategic.speed` / `sensor`).
- **New ability:** add `data/tactical/abilities/<id>.json`, composing existing effect types
  (`damage`, `heal`, `apply_status`), then list it on a unit.
- **New status:** `data/tactical/statuses/<id>.json` with `modifiers`, `flags` and/or `on_turn_start` effects.
- **New battle map:** `data/tactical/maps/<id>.json`, with `deployment.west`/`east` if galaxy battles use it.
- **New campaign:** `data/strategic/campaigns/<id>.json` (map, factions, planets, fleets).
- **Galaxy terrain, stars, bodies:** `data/strategic/terrain.json`, `star_types.json`,
  `body_types.json` (category, size, colony slots, bonus yields, shader colours), `planet_traits.json`.
- **Heroes:** classes, items, traits and XP thresholds in `data/heroes/`; named heroes, starting
  inventory and anomalies in the campaign file.
- **Economy:** `data/empire/` (resources, buildings with `on: [body categories]` or
  `needs: "colony"`, techs); ship `strategic.cost`/`build_turns`/`requires_tech` in unit files;
  campaign `resources`, `relations`, `techs`, system `bodies` with `buildings`.
- **New mission:** `data/missions/<id>.json` (map, enemies, objectives, story triggers with choices,
  rewards, follow-up on failure), plus a square-grid map with `deployment.squad`.

The content test catches broken references (unknown ability, status, map, unit, ...).
Field reference: [docs/architecture.md](docs/architecture.md#content-schema).

## Layout

```
data/                    content only (JSON)
src/core/                data registry, JSON loading
src/tactical/            shared tactical engine: pure logic, no nodes
src/strategic/           galaxy engine: pure logic, no nodes
src/heroes/              hero state, unit building, XP/levels
src/empire/              economy, research and diplomacy rules
src/missions/            mission -> tactical scenario factory
src/presentation/        scenes and visuals (read engines, never change rules)
  game.gd, main.tscn     top-level flow: galaxy ⇄ battle
  shared/                hex map view (with fog), fx, starfield, palette, UI kit
  board3d/               shared 2.5D pieces: camera rig, board geometry and lighting
  models/                procedural 3D models from data/models/models.json
  tactical/              battle screen (2D and 3D boards)
  strategic/             galaxy screen (2D and 3D boards)
assets/                  sprites, fonts, audio (one folder + LICENSE per asset pack)
tests/                   headless tests
tools/                   balance simulators, smoke tests
```

See [docs/architecture.md](docs/architecture.md) for how the pieces fit together.

## Builds and exports

Every push runs the **builds** workflow, which exports the game for Linux, Windows, macOS and
the Web (presets in `export_presets.cfg`). Download them from the repository's **Actions** tab:
open the latest *builds* run and scroll to **Artifacts**.

- **Windows**: unzip, run `space-homm.exe`. SmartScreen may warn about an unknown publisher
  ("More info" -> "Run anyway").
- **macOS** (Intel and Apple Silicon): unzip twice to get `space-homm.app`. It isn't notarized,
  so macOS will say it's damaged or from an unidentified developer. Clear the download
  quarantine once in Terminal, then open it normally:

  ```bash
  xattr -dr com.apple.quarantine /path/to/space-homm.app
  ```
- **Linux**: unzip, `chmod +x space-homm.x86_64`, run it.
- **Web**: unzip and serve the folder over HTTP (browsers won't load it from `file://`), e.g.
  `python3 -m http.server` in that folder, then open <http://localhost:8000>. Saves go to the
  browser's storage. It's a single-threaded build, so it also works on hosts like itch.io that
  don't send cross-origin isolation headers.

To export locally: Editor -> Project -> Export (install the 4.5.1 export templates when asked), or
headless: `godot --headless --path . --export-release "Linux"` (also `Windows`, `macOS`, `Web`;
create `build/<platform>/` and an empty `build/.gdignore` first).

Notes:
- Renderer is **GL Compatibility** so the same project runs on all four targets.
- The presets include `data/*` as non-resource files so the JSON content ships with the build;
  keep that filter if you add presets.
- macOS builds are universal and ad-hoc signed (needed on Apple Silicon); that's why ETC2/ASTC
  texture import is enabled in the project settings.
