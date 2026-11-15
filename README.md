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

## Running it

1. Install **Godot 4.5** (standard build, not .NET): <https://godotengine.org/download>.
   On a Mac, drag it into Applications. It runs natively on Apple Silicon.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button). The campaign *The Drift* starts with you as the
   Patrol Group (blue).

To jump straight into a single battle, open `src/presentation/tactical/battle_screen.tscn`
and press **F6** (run current scene).

### Galaxy controls

| Input | Action |
| --- | --- |
| Click your fleet | Select it (blue hexes = move, red = attack) |
| Click a blue / red hex | Move there / attack the fleet there |
| Click a planet or visible enemy | Show info |
| `Tab` | Next fleet with moves left |
| Right-click / `Esc` | Deselect |
| `Space` / `Enter` | End turn |
| `A` | Toggle autoplay (AI plays your faction too) |

Planets: move onto one to capture it. Friendly fleets parked at your planets repair
25% hull per turn. Nebulae and asteroid belts cost 2 moves, and battles there are
fought on matching battle maps.

### Battle controls

| Input | Action |
| --- | --- |
| Click a blue hex | Move (costs AP; nebula hexes cost 2) |
| `1`–`3` or ability button | Select ability, then click a red hex |
| Right-click / `Esc` | Cancel targeting |
| `Space` / `Enter` | End turn |
| `A` | Toggle autoplay |
| `R` | Restart (standalone battles only) |

Hover over targets to see the expected damage before you commit.

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

The content test catches broken references (unknown ability, status, map, unit, ...).
Field reference: [docs/architecture.md](docs/architecture.md#content-schema).

## Layout

```
data/                    content only (JSON)
src/core/                data registry, JSON loading
src/tactical/            shared tactical engine: pure logic, no nodes
src/strategic/           galaxy engine: pure logic, no nodes
src/missions/            step 3: hero missions (empty)
src/presentation/        scenes and visuals (read engines, never change rules)
  game.gd, main.tscn     top-level flow: galaxy ⇄ battle
  shared/                hex map view (with fog), fx, starfield, palette, UI kit
  tactical/              battle screen
  strategic/             galaxy screen
assets/                  sprites, fonts, audio (one LICENSE per asset pack)
tests/                   headless tests
tools/                   balance simulators, smoke tests
```

See [docs/architecture.md](docs/architecture.md) for how the pieces fit together.

## Notes for exports

- Renderer is **GL Compatibility** so the same project exports to Mac, Windows, Linux and Web.
- Web export: Godot 4.3+ can export single-threaded, which avoids the SharedArrayBuffer headers
  most hosts (e.g. itch.io) don't send. Tick "Thread Support: off" in the Web export preset.
- When you create export presets, add `data/*` to **Resources → Filters to export non-resource
  files** so the JSON content ships with the build.
