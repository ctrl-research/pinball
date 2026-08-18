# TILT (working title)

An arcade **pixel-art pinball roguelike** built with **Godot 4.6.3**. One
silver ball, a score target you have to beat with the balls you are given, and
a machine you keep bolting things onto between rounds.

Balatro's run structure — escalating antes, score gates, build-defining
trinkets, a shop after everything — poured into a pinball cabinet, with the
tactile layer of *3D Pinball: Space Cadet* underneath it: flippers, plunger,
nudge, tilt.

See [docs/game-design.md](docs/game-design.md) for the full design and
[docs/roadmap.md](docs/roadmap.md) for what gets built in what order.

## Controls

| | |
| --- | --- |
| **A / D** or **← / →** | left and right flipper |
| **SPACE** (hold, release) | plunger — how long you hold sets the power |
| **Q / W / E** | nudge left / up / right |
| **SPACE** | confirm, on any between-stage screen |

Nudging buys you back a bad bounce. The meter holds two and recharges one every
five seconds; nudge with it empty and the machine **tilts** — flippers die, the
ball drains, and you lose the MULT you were building.

## How a run works

Eight antes, three stages each: small blind, big blind, boss blind.

- Each stage is a **score target** you have to beat with **3 balls**.
- Every scoring element has a **value**; the playfield has a **MULT**. A hit
  banks `value × MULT` immediately. MULT starts each ball at ×1, only ever
  climbs during that ball, and is lost when the ball drains — so the ball that
  has been alive longest is worth the most and is the one you can least afford
  to lose.
- **A stage always plays all of its balls.** Beating the target does not end it
  — it means the rest is played for money instead of for survival, and win or
  lose is decided once, when the last ball drains.
- Clear the stage and you are paid in tokens: the blind's reward multiplied by
  how many times over you beat the target (capped ×5), `$1` per ball you never
  needed, and interest on what you are holding.
- Spend it on **trinkets** (up to 5, always-on, the axis you build around),
  **consumables** (up to 3, one-shot, spent at a stage intro and lasting that
  stage),
  **table mods** (which physically change the playfield), or **target levels**
  (which raise the base value of a whole class of target).
- The **boss blind** attacks the machine rather than the number — a dead
  flipper, dead bumpers, a capped MULT, a wider drain.

Miss a target with no balls left and the run is over.

## Running locally

Install Godot **4.6.3** (see `.tool-versions`), then:

```sh
godot --path .            # run the game
godot --path . --editor   # open the editor
```

Tests, the same two CI runs:

```sh
godot --headless --path . tests/run_test.tscn                          # expect RUN_TEST_OK
godot --headless --path . --quit-after 5000 tests/headless_sim.tscn    # expect SIM_OK
```

### Seeing the playfield without opening the editor

The table is generated — offset polylines, a computed arch, a mirrored bottom
half — so reading `layout.gd` tells you much less than looking at the result,
and a table mod or a boss blind reshapes it. This renders what the game will
actually build:

```sh
godot --headless --path . tools/dump_layout.tscn > /tmp/layout.json
python3 tools/preview_table.py /tmp/layout.json table.png
```

It draws each flipper twice — at rest and at full sweep — because the swept
volume is where ball traps hide. Both traps found so far were visible in this
picture before they were understood in the code.

## How the project is put together

**The table is data, not a scene.** Every wall, target and lane lives in
`src/table/layout.gd` as plain numbers; `table.gd` turns them into collision
shapes and draws them from the same source. Nothing is hand-placed in a `.tscn`
— the scene files are a root node and a script.

That is not tidiness. Table mods are a core roguelike axis here ("Extra
Bumper", "Wide Flippers", "Outlane Guards"), and a mod is only cheap to build
if the playfield is a *value* you can edit before instantiating it. It also
means collision and rendering cannot drift apart.

**The table decides nothing.** It reports what was hit; `run.gd` owns every
number. A trinket is a branch at a named hook in one file rather than a patch
threaded through a dozen playfield scripts.

```
src/
├── autoload/
│   ├── run.gd        # run state + all scoring arithmetic (autoload "Run")
│   └── sfx.gd        # procedural audio, synthesised at boot (autoload "Sfx")
├── run/catalog.gd    # trinkets, mods, bosses, blind curve -- data only
├── table/
│   ├── layout.gd     # the machine, as numbers
│   ├── table.gd      # builds it; plunger, nudge, drain, boss hazards
│   ├── ball.gd  flipper.gd  bumper.gd  slingshot.gd  target.gd  sensor.gd
├── ui/
│   ├── cabinet.gd            # rails, lockdown bar, backbox, screen layout
│   ├── perspective.gdshader  # the trapezoid warp
│   └── hud.gd                # both panels + every between-stage screen
├── game.gd           # the run as a state machine
└── main_menu.gd
```

### The 2.5D is a rendering trick, on purpose

The playfield is rendered flat into a SubViewport and warped onto a trapezoid by
a shader. **The simulation stays a plain top-down 2D world that has never heard
of perspective** — so no ball can behave differently because of how it is drawn,
which is the one property a pinball game cannot afford to lose. Every part is
foreshortened for free, extrusions included.

Solid parts are drawn twice: a dark side face offset toward the player, then the
lit top face over it. The camera is at the near edge, so the only visible side
face is the near one and the offset is always +y. Lamp inserts get no side face
— they are flush with the wood, and half of what sells everything else as raised
is that these are not.

`Cabinet` owns the screen layout as well as the chrome, because the panel
positions are defined by where the machine is and there should be one answer to
that rather than two that drift.

### Physics notes

- **120Hz physics.** The single most important setting in the project. At 60Hz
  a ball at 600px/s advances 10px per tick — wider than the ball and comparable
  to a wall's thickness, so contacts are missed and flipper sweeps pass through.
- **Flippers are `AnimatableBody2D` with `sync_to_physics`**, not rigid bodies
  on motorised joints and not scripted impulses. The physics server turns the
  body's transform change into a velocity, so the ball is launched by the
  flipper's actual motion — which is why a ball caught near the tip flies
  further than one caught at the root, and why cradling works at all.
- **Gravity is 480px/s².** A real table inclined 6.5° works out to ~357px/s² at
  this scale; we run faster than real because a faithful table feels sluggish
  on a screen.
- **Restitution is per-surface**: 0.25 on outer walls, 0.75 on slingshot
  rubbers. The ball itself is dead (0.0) and Godot combines by taking the
  maximum, so a bouncy ball would make the whole table one uniform trampoline.

## Status

The run loop is complete: one table, the full 8-ante structure, 14 trinkets, 4
table mods, 8 boss blinds, target levels, 8 consumables, and a shop that buys
and sells. One further modifier layer — flipper coils — is designed but not
built. The presentation is
2.5D — perspective playfield, extruded parts, and a drawn cabinet with rails, a
lockdown bar and a backbox.

It has been run: both tests pass under Godot 4.6.3, and the web export has been
loaded in a browser through the menu, a blind intro, a plunge and a ball in
play. That testing, plus one round of actually playing it, found and fixed seven
real bugs — two ball traps that made the
table unable to drain, friction roughly 4× too high, a plunger that ignored a
tap, a menu that could start two runs at once, and a `Label` built in the wrong
order that ran its text off the screen, and an inlane that fed the drain
instead of the flipper — which made losing the ball on either side unavoidable,
and which only playing the game revealed.

See [docs/roadmap.md](docs/roadmap.md) for what comes next. In short:

1. **No human has played it.** Everything above is a bot and a screenshot,
   which proves the table *works* and says nothing about whether it is *fun*.
   That is the roadmap's Phase 0 and the only hard gate in it — flipper sweep,
   plunge power, slingshot kick, gravity and the drain gap are all reasoned
   from real-machine numbers rather than tuned by feel, and the constants are
   at the top of `layout.gd`.
2. **It is not pixel art yet.** Parts are drawn from the same data that
   generates their collision — chunky, readable, guaranteed in sync, but
   low-res vector shapes rather than a pixel grid.
3. **The table is sparse.** Three bumpers, three drop targets, two standups,
   two rollovers, a spinner. Enough to prove the scoring engine, thin for a
   machine you are meant to learn by heart.
4. One table. Variety currently comes from mods and trinkets only.

## CI

`.github/workflows/build.yml` runs on every PR: imports the project, runs the
scoring unit test and a headless bot that plays the real scene, exports the web
build, and greps the log for parse and autoload errors — a Godot export exits 0
even when scripts fail to compile, so a successful export is not on its own
evidence the project is healthy. `main` additionally deploys to GitHub Pages.
