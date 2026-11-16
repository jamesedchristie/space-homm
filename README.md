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
- **Step 4 (done):** empire systems. Credits, alloys and research from planets and buildings;
  build queues for buildings and ships; a tech tree (ship upgrades, faster fleets, sensors,
  yields, defense platforms, the Destroyer); a third faction, the Ceres Free Traders, with
  war/peace, opinion, peace proposals and gifts; defended planets that fight back.

## Running it

1. Install **Godot 4.5** (standard build, not .NET): <https://godotengine.org/download>.
   On a Mac, drag it into Applications. It runs natively on Apple Silicon.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button). On the title screen, pick **New campaign** (options:
   permadeath, a fixed seed) to play *The Drift* as the Patrol Group (blue), or **Continue**
   the latest save.

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
| Click a planet or visible enemy | Show info |
| `Tab` | Next fleet with moves left |
| Right-click / `Esc` | Deselect (`Esc` with nothing selected opens the menu) |
| `F5` / `F9` | Quicksave / load the quicksave |
| `Space` / `Enter` | End turn |
| `E` | Empire panel: colonies and build queues, research, diplomacy |
| `H` | Heroes panel: gear, levels, assign/relieve fleet commanders |
| `A` | Toggle autoplay (AI plays your faction too) |
| `V` | Switch between the 2.5D (3D) and top-down (2D) galaxy map |
| Mouse wheel / `Q` `R` / right-drag / arrows / middle-drag | 3D map: zoom / rotate / rotate / pan / pan |

The 3D map opens on the area you've explored; zoom out with the wheel to see the whole sector.

Planets: move onto one to capture it. Friendly fleets parked at your planets repair
25% hull per turn. Nebulae and asteroid belts cost 2 moves, and battles there are
fought on matching battle maps.

Empire: each planet produces credits, alloys and research (by planet type and buildings).
Queue buildings or ships per planet in the Empire panel (E); ships need a shipyard. Research
points flow into the tech you pick. The Free Traders start at peace with you and at war with
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
| Right-click / `Esc` | Cancel targeting |
| `Space` / `Enter` | End turn |
| `A` | Toggle autoplay |
| `R` | Restart (standalone battles only) |
| `V` | Switch between the 2.5D (3D) and top-down (2D) battle view |
| Mouse wheel / `Q` `E` / right-drag / arrows / middle-drag | 3D view: zoom / rotate / rotate / pan / pan |

Hover over targets to see the expected damage before you commit. In missions, the green ★
marks the objective, yellow **?** marks something to investigate, and enemies stay hidden
(and mostly asleep) until your squad can see them. Crates are cover (30% less damage).

## Art and credits

- Ships, lasers, meteors, effect sprites, the Kenvector fonts and sound effects:
  **Kenney** "Space Shooter Redux" (CC0, `assets/kenney_space_shooter/`, see its README/LICENSE).
- Planets (2D and 3D), atmospheres, the fog of unexplored space and the space backdrop are
  procedural shaders (`src/presentation/shaders/`).
- 3D models are procedural: each is a recipe of parts (bevelled hulls, boxes, cylinders, cones,
  spheres, rocks) in `data/models/models.json`, built at load time by
  `src/presentation/models/model_factory.gd`. Units pick one with `visual.model`; the `accent`
  material takes the team color. A model can name a `base` whose parts come first: the
  trooper, hero and boarder all build on `humanoid`. Add or reshape a model by editing JSON.
- The UI theme is built in code (`src/presentation/shared/game_theme.gd`); colors live in `palette.gd`.
- Ship sprites are set per unit in JSON (`visual.sprite`, with `{team}` replaced by the team's
  color variant). Battle maps can set `backdrop` colors and `floor: "deck"` for interiors.
  Planet types set `surface` colors for the planet shader.

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
- **Galaxy terrain / planet types:** `data/strategic/terrain.json`, `data/strategic/planet_types.json`.
- **Heroes:** classes, items, traits and XP thresholds in `data/heroes/`; named heroes, starting
  inventory and anomalies in the campaign file.
- **Economy:** `data/empire/` (resources, buildings, techs); planet `yields`/`slots` in
  `planet_types.json`; ship `strategic.cost`/`build_turns`/`requires_tech` in unit files;
  campaign `resources`, `relations`, `techs`, planet `buildings`.
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
