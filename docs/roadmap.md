# TILT — Roadmap

The design doc says what the game *is*. This says what order we build it in, and
what has to be true before each step earns the next one.

One rule runs through all of it: **the feel gate comes before content.** A
pinball roguelike whose flippers are unsatisfying cannot be rescued by relics,
and every hour spent on relics before that is settled is an hour spent on
content we might have to rebalance against a different-feeling table.

## Where we are

Milestone 1 (vertical slice) and most of milestone 2 (run loop) are merged: one
table, the full 8-ante structure, 14 relics, 4 table mods, 8 boss blinds, target
levels, a shop, and procedural audio. CI exports the web build and runs a
scoring unit test plus a headless bot that plays the real scene.

**Verified**: the table works. A bot serves, scores, drains, clears a blind,
shops, and loses a run without errors.

**Not verified**: that any of it is fun. That is the whole content of Phase 0.

## Phase 0 — the feel gate

The only hard gate in this document. Everything after it assumes the answer is
yes.

Play it. Not test it — play it, for a while, with the intent of enjoying it.

Then answer:

1. Is hitting the ball with a flipper satisfying on its own, with the scoring
   ignored?
2. Does a save feel earned, or random?
3. Is a drain your fault?
4. Do you want another ball?

If (1) is no, tune and ask again — the constants are all at the top of
`src/table/layout.gd`, and they are documented with the real-machine numbers
they came from so it is clear what a change is departing from. Likely suspects,
in order: flipper sweep time, gravity, slingshot kick, drain gap, ball speed
clamp.

If (1) is still no after real tuning, that is a finding, not a failure — it
means the physics model needs revisiting before any more is built on it.

**Exit**: the four questions above answered yes, and a list of tuning changes
made. No new features.

## Phase 1 — identity

Making it look and sound like a machine rather than a diagram. Partly underway.

- ~~**2.5D presentation** — perspective playfield, extruded parts, a drawn
  cabinet with rails, a lockdown bar and a backbox.~~ **Done.**
- ~~**Panel layout** — powerups and multipliers left, score right, cabinet
  centred.~~ **Done.**
- **Pixel art pass** — replace the drawn parts with a generated 16-colour
  sheet (`tools/gen_pixel_art.py`, ASCII grids, stdlib Python) so placeholder
  art stays editable in a diff. Walls stay drawn: they are generated geometry
  and a mod moves them.
- **Feedback** — insert lamps that actually light, score popcorn, screen shake
  on a slingshot, a flipper that clunks. The gap between "the number went up"
  and "I did that" is almost entirely here.
- **Backbox display** — the ante, the blind, and the boss, as a segmented-LED
  readout rather than a label.

**Exit**: a screenshot reads as a pinball machine to someone who has not been
told what it is.

## Phase 2 — depth

Only once the machine is worth learning. Right now the table is thin: three
bumpers, three drop targets, two standups, two rollovers, a spinner. That is
enough to prove the scoring engine and not enough to have a favourite shot.

- **Fill the table** — a ramp with a habitrail return, a captive ball, a
  kickback, a second drop bank, upper flipper. Every one is a new shot, and a
  shot is what a player actually builds a relic around.
- **Relic pool to ~30** — enough that two runs diverge. The current 14 all
  read as "more points"; the pool needs relics that change *routing* (rewards
  for orbits, for combos, for keeping a ball above the slingshots).
- **Coils and ball mods** — the two new modifier layers, designed in
  `game-design.md`. Coils are the survival axis (they never add a point, they
  buy chances to score); ball mods are the only layer that asks the player a
  question *during* a stage rather than in the shop. Together they create the
  build tension the game currently lacks: score axes make a good ball worth
  more, survival axes make good balls more likely, and a run that buys only one
  loses.
  `Magna-Hold` (cradling) is the highest-value single item in either list — it
  is the difference between reacting and playing.
- **Second table** — worth building only once the modifier layers are proven,
  because every table has to be balanced against all of them.
- **Boss blinds that use the geometry** — the current eight mostly edit
  numbers. A boss that closes a lane or reverses the flippers is a boss you
  have to *play around*.

**Exit**: two runs of the same ante feel like different runs.

## Phase 3 — the long game

- Unlocks, so a new player meets a smaller pool than a veteran.
- Seeded runs (the field exists; make it shareable) and a daily.
- A run-history screen: best score per ante, most-used relics.
- Balance pass driven by real play data, not by intuition — the score curve is
  borrowed from Balatro and has never been checked against this scoring engine.

## Phase 4 — release

- Desktop exports (macOS + Windows), following `rogue-like`'s `desktop.yml`.
- Controller support. Pinball is two buttons; this should be trivial and is
  the difference between a browser toy and something played on a TV.
- Accessibility: rebindable keys, a colourblind-safe insert palette, and a
  slower-ball option that scales gravity and the speed clamp together.

## Explicit non-goals

Written down so they stop coming up:

- **Multiplayer.** `rogue-like` and `fps` both carry a signalling server and a
  WebRTC stack, and that complexity is load-bearing there. Here it would be
  decoration on a single-player score-attack game.
- **Real 3D.** The 2.5D is a rendering trick over 2D physics, deliberately. 3D
  pinball physics is a different project.
- **A table editor.** The playfield being data makes one tempting. It is a tool
  for us, not a feature.

## Known risks

- **The score curve is unvalidated.** Balatro's antes are tuned for Balatro's
  scoring. Ours banks continuously off physics, so the variance profile is
  completely different — a good ball might overshoot ante 3 entirely. This
  needs real data, and it is the most likely thing to need a rework.
- **MULT is the only interesting axis.** Value is flat and additive; MULT is
  where every decision lives. If Phase 2 relics do not diversify that, the
  build variety is cosmetic.
- **Perspective versus readability.** Foreshortening the top of the playfield
  makes the bumper cluster smaller exactly where a lot of the scoring happens.
  If it hurts play, the perspective is the thing that gives, not the layout.
