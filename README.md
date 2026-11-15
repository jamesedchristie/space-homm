# space-homm (working title)

Turn-based sci-fi strategy: a Civ-style galaxy map, Heroes-style tactical battles
and Mass Effect-style hero missions, all built on **one shared tactical engine**.

**Status:** step 1 of the build order is done: a tactical grid prototype. It has
two ship types, six abilities, four status effects, terrain, line of sight, a
rule-based AI, auto-resolve and a headless test suite.

## Running it

1. Install **Godot 4.5** (standard build, not .NET): <https://godotengine.org/download>.
   On a Mac, drag it into Applications. It runs natively on Apple Silicon.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button). The skirmish starts with you controlling the blue ships.

| Input | Action |
| --- | --- |
| Click a blue hex | Move (costs AP; nebula hexes cost 2) |
| `1`–`3` or ability button | Select ability, then click a red hex |
| Right-click / `Esc` | Cancel targeting |
| `Space` / `Enter` | End turn |
| `A` | Toggle autoplay (AI controls your side too) |
| `R` | Restart with a new seed |

Hover over targets to see the expected damage before you commit.

## Tests and tools (headless, no editor needed)

```bash
# one-time: build Godot's class cache (also done automatically by opening the editor)
godot --headless --path . --import

# unit + integration tests (exit code 1 on failure)
godot --headless --path . -s res://tests/run_tests.gd

# balance: auto-resolve a scenario N times, print win rates / battle length / ability usage
godot --headless --path . -s res://tools/simulate_battles.gd -- --scenario=first_skirmish --runs=200

# smoke-test the real battle screen with AI on both sides
godot --headless --path . -s res://tools/smoke_battle_screen.gd
```

On macOS the binary is `/Applications/Godot.app/Contents/MacOS/Godot`; alias it to `godot`.
CI runs the tests on every push (`.github/workflows/tests.yml`).

## Adding content (no code)

- **New ship:** add `data/tactical/units/<id>.json` and reference it in a scenario.
- **New ability:** add `data/tactical/abilities/<id>.json`, composing existing effect types
  (`damage`, `heal`, `apply_status`), then list it on a unit.
- **New status:** `data/tactical/statuses/<id>.json` with `modifiers`, `flags` and/or `on_turn_start` effects.
- **New battle:** `data/tactical/maps/<id>.json` and `data/scenarios/<id>.json`.

The content test catches broken references (unknown ability, status, map, ...).
Field reference: [docs/architecture.md](docs/architecture.md#content-schema).

## Layout

```
data/            content only (JSON)
src/core/        data registry, JSON loading
src/tactical/    the shared tactical engine: pure logic, no nodes
src/presentation scenes and visuals (reads engine, never changes rules)
src/strategic/   step 2: galaxy hex map (empty)
src/missions/    step 3: hero missions (empty)
assets/          sprites, fonts, audio (one LICENSE per asset pack)
tests/           headless tests
tools/           balance simulation, smoke tests
```

See [docs/architecture.md](docs/architecture.md) for how the pieces fit and how later layers plug in.

## Notes for exports

- Renderer is **GL Compatibility** so the same project exports to Mac, Windows, Linux and Web.
- Web export: Godot 4.3+ can export single-threaded, which avoids the SharedArrayBuffer headers
  most hosts (e.g. itch.io) don't send. Tick "Thread Support: off" in the Web export preset.
- When you create export presets, add `data/*` to **Resources → Filters to export non-resource
  files** so the JSON content ships with the build.
