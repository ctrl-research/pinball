# AGENTS.md

## Purpose

**TILT** — an arcade pixel-art pinball roguelike in Godot 4.6.3. Balatro's run
structure (antes, score-gated blinds, trinkets, a shop) on a real pinball
playfield. Exports to web and deploys to GitHub Pages.

Design lives in [docs/game-design.md](docs/game-design.md), build order in
[docs/roadmap.md](docs/roadmap.md), and how the code is arranged in
[README.md](README.md).

## Tech stack

- **Godot 4.6.3**, GDScript, GL Compatibility renderer, 640×360 base viewport
- **GitHub Actions** for the web export, tests, and Pages deploy
- No third-party addons, no binary assets — sound is synthesised at boot and
  the playfield is drawn from its own collision geometry

## Structure

```
.
├── docs/game-design.md
├── project.godot            # 120Hz physics, 480px/s^2 gravity, input map
├── export_presets.cfg       # Web preset; committed, CI exports from it
├── scenes/                  # root node + script only, deliberately trivial
├── src/
│   ├── autoload/run.gd      # run state + ALL scoring arithmetic ("Run")
│   ├── autoload/sfx.gd      # procedural audio ("Sfx")
│   ├── run/catalog.gd       # trinkets, mods, bosses, blind curve -- data only
│   ├── table/layout.gd      # the machine, as numbers
│   ├── table/*.gd           # table build + individual playfield parts
│   ├── ui/cabinet.gd        # rails, lockdown, backbox + screen layout
│   ├── ui/perspective.gdshader  # the trapezoid warp
│   ├── ui/hud.gd            # both panels + between-stage screens
│   ├── game.gd              # the run as a state machine
│   └── main_menu.gd
├── tests/
│   ├── run_test.tscn        # scoring engine unit test -> RUN_TEST_OK
│   ├── containment_test.tscn # the ball cannot escape -> CONTAINMENT_OK
│   ├── inlane_test.tscn     # lane routing -> INLANE_TEST_OK
│   └── headless_sim.tscn    # bot plays the real scene -> SIM_OK
└── tools/                   # dev only; excluded from the export
    ├── dump_layout.tscn     # prints the generated playfield as JSON
    └── preview_table.py     # renders that JSON to a PNG
```

## Conventions

- `.tool-versions` is the single source of truth for tool versions. Godot has
  no asdf/mise plugin, so its version is pinned there as a comment and must be
  kept in sync with `GODOT_VERSION` in `.github/workflows/build.yml` and
  `config/features` in `project.godot`. Never assume a globally installed
  version.
- **The playfield is data.** Add or move geometry in `src/table/layout.gd`, not
  in a scene. Collision and rendering both read it, so they cannot drift. After
  changing geometry, *look* at it — `tools/dump_layout.tscn` plus
  `tools/preview_table.py` renders what the game will build (see README). Both
  ball traps found so far were visible in that picture first.
- **The table decides nothing.** Playfield parts report what was hit by calling
  `Run.register_hit(source)`; every number lives in `run.gd`. A new trinket is a
  data entry in `catalog.gd` plus a branch at a named hook in `run.gd` — if a
  trinket needs a change in `table.gd`, it is a *table mod*, not a trinket.
- **Inventory vocabulary**: **trinkets** are passive and permanent (5 slots, no
  duplicates); **consumables** are one-shot, stage-scoped and spent at the
  stage intro (3 slots, duplicates fine). A consumable's effect is a key in
  `Run.effects`, which `begin_stage()` clears — that clearing is the only thing
  making it a consumable rather than a second trinket rack.
- **Building a Button in code: it grows to fit its text and will not wrap.** Set
  `clip_text` and a `custom_minimum_size`, and put any long description in a
  wrapped Label beneath it — otherwise one long item name widens its column and
  pushes the layout off the side of the screen.
- **Scene files stay trivial** — a root node and a script. UI is built in code.
- **Perspective is a rendering step, never a simulation one.** The playfield
  renders flat into `Cabinet`'s SubViewport and is warped by a shader on the way
  to the screen. Never let a gameplay value depend on a screen position: if the
  physics ever needs to know where something is *drawn*, the design is wrong.
- **Screen layout lives in `cabinet.gd`.** Panels are positioned relative to the
  machine, so there is one source for it. `Cabinet.TOP_SCALE` is shared with the
  shader and the two must agree, or the rails stop lining up with the playfield.
- **Font sizes should be multiples of 8.** Silkscreen is drawn on an 8px grid;
  off-grid sizes resample and lose columns (at 7px the W reads as a different
  glyph). The typeface is set once on the default theme in
  `src/autoload/style.gd` — note that `ThemeDB.fallback_font` alone does
  nothing, because the default theme ships its own `default_font` and a theme
  always wins over the fallback.
- **Building a Label in code: set `autowrap_mode` before `size`.** A Label grows
  to its own minimum size, and an unwrapped Label's minimum width is the full
  width of its text — setting autowrap afterwards is too late, and a long line
  runs off the screen.
- Both tests must keep printing their sentinel (`RUN_TEST_OK` / `SIM_OK`). CI
  greps for them, so a test that exits early silently fails the build rather
  than passing it. Adding a scoring rule means adding a case to `run_test.gd`.
- **Browser-level input hardening lives in `export_presets.cfg`**, as
  `html/head_include`. It blocks pinch-zoom (ctrl+wheel and `gesture*`),
  overscroll, and page scroll, and puts focus back on the canvas if it drifts.
  Godot only preventDefaults keys that reach the canvas, so anything that moves
  focus or the visual viewport hands the keyboard back to the browser. If the
  view ever seems to pan or zoom on its own, start there.
- Versioning: bare `X.Y.Z`, no `v` prefix. `MAJOR.MINOR` from `./VERSION`.
- Branch protection: never push directly to `main`; all changes via PR.
- Commit style: conventional commits, see `CONTRIBUTING.md`.

## Physics invariants

Change these only deliberately, and re-run the headless sim afterwards:

- **`physics_ticks_per_second = 120`.** At 60Hz the ball tunnels through walls
  and misses flipper sweeps. Everything else is taste; this is correctness.
- **Ball CCD is `CCD_MODE_CAST_SHAPE` and `MAX_SPEED` is 900px/s** — just under
  a ball diameter per tick at 120Hz. Raising the speed without raising the tick
  rate is how balls escape the table.
- **Do not use a thin stroked wall where the ball arrives head-on at speed.**
  The arch was one, and the ball could punch through the apex and leave the
  cabinet. Thickening the stroke made it *worse*: `Geometry2D.offset_polyline`
  with a large delta along a tight curve folds the ribbon over itself, and a
  self-intersecting polygon collides with less than a thin one. Where there is
  nothing playable behind a boundary, make the whole region a solid polygon
  instead — no thickness to tunnel, no offset geometry to degenerate, and no
  pocket behind it for a ball to get stuck in. `arch_cap_polygon()` is the
  pattern.
- **`tests/containment_test.tscn` must keep passing.** It fires a ball at every
  wall from every angle at the speed clamp with the flippers hammering. The
  flippers are not incidental: a solenoid-speed kinematic body squeezing a ball
  against a wall is the classic way a pinball escapes, and the same test without
  them found nothing.
- **The ball's own restitution is 0.0.** Godot combines bounce by taking the
  maximum, so a bouncy ball makes every surface as lively as the liveliest one
  and the table reads as a uniform trampoline.
