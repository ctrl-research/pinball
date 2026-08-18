# TILT — Game Design (working title)

An arcade **pixel-art pinball roguelike**. One silver ball, a table you rebuild
between rounds, and a score target that grows faster than you do.

Think **Balatro's run structure poured into a pinball cabinet**: every stage is
a score you have to beat with a limited number of balls, and the way you beat it
is the pile of relics, table mods, and target upgrades you've bolted onto the
machine along the way. The direct ancestors are Balatro (score gates, escalating
antes, build-defining jokers, a shop between everything) and Pegfinity (physics
toy as the scoring engine), sat on top of the tactile layer of *3D Pinball:
Space Cadet* — flippers, plunger, nudge, tilt.

## Why pinball is the right physics toy for this

Balatro works because a hand of cards is a **small, repeatable, high-variance
event** that a stack of modifiers can hook into. A pinball **ball** is the same
shape of thing: it starts, it does an unpredictable amount of work, it drains.
Three balls per stage is three hands per blind.

Better still, pinball already invented Balatro's core arithmetic decades
earlier. Real machines have a **playfield multiplier** that builds during a ball
and resets when it drains, applied to the base value of everything you hit. That
is chips × mult, and it is native vocabulary here — no reskinning required.

## The screen

The machine is centred and drawn as a machine: a backbox above the playfield, a
lockdown bar at the near edge, and rails down both sides that converge with the
playfield as it recedes. A panel brackets it on each side.

```
 640 x 360 viewport
┌────────────────┬────────────────────────┬────────────────┐
│ POWER-UPS      │   ┌────────────────┐   │ SCORE          │
│ ┌────────────┐ │   │  ANTE 3 / 8    │   │ 12,480         │
│ │BRASS BUMPER│ │   │  BOSS BLIND    │   │ TARGET  20,000 │
│ ├────────────┤ │   └────────────────┘   │ ▓▓▓▓▓▓░░░░░░░  │
│ │COMBO COIL  │ │      ___________       │                │
│ ├────────────┤ │     /  ▁▁    ▁▁  \     │ BALLS   ***    │
│ │BALL SAVER  │ │    /  (◉)   (◉)   \    │ NUDGE   **     │
│ ├────────────┤ │   │        ▁▁       │  │ $14            │
│ │            │ │   │       (◉)       │  │                │
│ ├────────────┤ │   │                 │  │                │
│ │            │ │   │    ◣▁     ▁◢    │  │                │
│ └────────────┘ │   └─────────────────┘  │ A / D flippers │
│ MULTIPLIER     │   ═══ lockdown bar ═══ │ SPACE plunge   │
│ x4             │                        │ Q / W / E nudge│
└────────────────┴────────────────────────┴────────────────┘
```

The split follows what the player is asking at the time. **Left is what they
have** — the relics and the MULT those relics are feeding. It is the build, and
it changes slowly. **Right is where they are** — score against target, balls,
nudges, money, all of which move while the ball is alive. Putting a number that
changes every frame next to one that almost never does trains you to stop
reading either.

Ante and blind live in the **backbox**, because that is what a backbox is for
and it sits above the playfield where the player is already looking.

Base resolution is 640×360 with `canvas_items` stretch, so the layout survives
any window size — same setup as `rogue-like`.

### 2.5D

The playfield is rendered flat into a SubViewport and warped onto a trapezoid by
`src/ui/perspective.gdshader`: full width at the near edge, narrower and
vertically compressed as it recedes.

Doing it at the last step before the screen, rather than in the drawing code, is
the point. **The simulation stays a plain top-down 2D world that has never heard
of perspective**, so no ball can ever behave differently because of how it is
being drawn — which is the one property a pinball game cannot afford to lose.
It also means every part gets foreshortened for free, including the extrusions
below.

The warp is *projective*, not a linear squash. A linear trapezoid reads as a
picture someone has skewed; dividing the vertical coordinate by the same
interpolant that narrows each row is what makes the far end compress and the
near end stretch, and that is the part the eye reads as depth.

On top of that, every solid part is drawn twice — a dark side face offset toward
the player, then the lit top face over it. Because the camera is at the near
edge, the only side face you can ever see is the near one, so the offset is
always +y and never needs to know about the part's shape. Lamp inserts
deliberately get no side face: they are flush with the wood, and half of what
sells everything else as raised is that these are not.

The ball's cast shadow is the cheapest depth cue on the table and the one doing
the most work — it is what separates a ball resting *on* the playfield from a
disc painted on it, and the only thing that makes a ball airborne off a
slingshot read as airborne.

**The trade**: foreshortening shrinks the bumper cluster exactly where a lot of
the scoring happens. If it ever costs readability, `Cabinet.TOP_SCALE` is the
number that gives, not the layout.

## The run

**8 antes × 3 stages.** Small blind, big blind, boss blind, then the ante
advances and the numbers get worse. Lose a stage and the run is over.

| | |
| --- | --- |
| **Stage** | Beat a score target using 3 balls. |
| **Ball** | Plunge, play, drain. The playfield MULT resets between balls. |
| **Clear** | Bank tokens, take a reward, visit the shop. |
| **Fail** | Balls exhausted below target → run over. |

Score targets follow Balatro's ante curve, because it is a curve that is known
to work — it roughly triples early and then stretches:

| Ante | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Base | 300 | 800 | 2,000 | 5,000 | 11,000 | 20,000 | 35,000 | 50,000 |

Small blind = base ×1, big blind = ×1.5, boss blind = ×2.

### Scoring

Every scoring element carries a **value**. The playfield carries a **MULT**.

```
score += value × MULT        (banked on the hit, not on the drain)
```

Banking on the hit rather than at ball-end is a deliberate departure from
Balatro. Balatro reveals chips × mult as a punchline because a hand is a
discrete, instant event. A ball is *continuous* — twenty seconds of live
physics — and a score that only resolves on the drain would mean the player
spends that entire time unable to read whether they are winning. Real pinball
scores as you hit things, the readout climbing while the ball is alive, and that
running climb is most of the drama. So: bank immediately, and let MULT be the
thing that carries the tension of keeping the ball alive.

MULT starts each ball at ×1 and only ever goes up during that ball. Draining
loses it. That is the whole risk curve of the game in one sentence: **the ball
that has been alive longest is worth the most and is the one you can least
afford to lose.**

### Balls, nudges, tilt

Three balls per stage. Two **nudges** per ball — a table bump that shoves the
ball a few pixels and is the only tool you have against a bad bounce. A third
nudge in quick succession **tilts**: flippers die, the ball drains, MULT is
lost. Nudge is this game's discard — a scarce, skill-expressive way to buy back
a mistake, with a hard punishment for greed.

### Economy

Tokens (`$`) are earned on a stage clear and spent in the shop.

- Base reward per blind: small `$3`, big `$4`, boss `$5`
- `$1` per unused ball — do not need the third ball, get paid for it
- Interest: `$1` per `$5` held, capped at `$5`

The unused-ball payout is the same lever as Balatro's unused hands: it makes
overshooting a small blind on one ball an actual strategy rather than a waste.

## The build — five layers of modifier

Balatro works because its categories are not five flavours of the same thing.
Jokers bend **rules**, planets raise the **scoring table**, tarots edit the
**deck**, vouchers change the **run**. Each answers a different question, so
owning one never feels like a worse version of owning another.

Pinball has its own natural set of objects to hang categories on, and they fall
out of the machine rather than being invented: **the ball** in play, **the
flippers** you control with, **the parts** you hit, and **the machine** itself.
So:

| Layer | Acts on | Answers |
| --- | --- | --- |
| **Relics** | Events | *What rule is bent?* |
| **Levels** | Part classes | *What is my best shot worth?* |
| **Coils** | The flippers | *How long do I keep the ball alive?* |
| **Ball mods** | One ball | *What is **this** ball?* |
| **Table mods** | The playfield | *What does the machine look like?* |

The load-bearing split is the last two columns against the first two. Relics and
levels make a good ball **worth more**. Coils and ball mods make good balls
**more likely**. A run that only buys score dies at ante 4 with a huge MULT it
never got to use; a run that only buys survival keeps the ball alive for a
minute and still misses the target. That tension is the build decision, and it
is the thing a naive Balatro clone leaves out.

**Relics stay the primary axis.** Balatro is a game about jokers with four
supporting systems, not a game about five equal systems — spreading power evenly
across categories is how this ends up with five shallow ones. The rule of thumb:
if an effect could be a relic, it should be a relic.

### Relics (jokers)

Up to **5 slots** on the panel. Passive, always-on, and the primary axis of a
build. They hook a small set of events: `on_hit`, `on_score`, `on_ball_start`,
`on_drain`, `on_stage_start`.

| Relic | Effect |
| --- | --- |
| Brass Bumper | Pop bumpers score ×3 value |
| Combo Coil | Each hit within 1.5s of the last: +0.2 MULT |
| Slingshot Savant | Slingshots score +25 value |
| Skill Shot | First target hit each ball scores ×5 |
| Ball Saver | First drain each stage returns the ball |
| Deadhead | MULT no longer resets between balls |
| Tilt Gremlin | +2 MULT while you have no nudges left |
| Drop Devotion | Clearing a drop bank: +1 MULT for the rest of the stage |
| Spinner Fever | Each spin this ball raises spinner value by 5 |
| Outlane Insurance | Draining down an outlane pays `$3` |
| Penny Slot | `$1` per 1,000 points scored |
| Magnet Coil | Every 10 bumper hits spawns a second ball |
| Jackpot Lamp | Every 8th target hit scores a flat 500 × MULT |
| Cold Solder | −1 ball per stage, but all values ×2 |

`Deadhead` is the deliberate build-breaker, the way Balatro keeps one joker that
invalidates a core rule. It converts the game from "three separate attempts" to
"one long accumulating attempt", and it should be rare and expensive.

### Table mods (vouchers)

Permanent changes to the **physical playfield** — the roguelike lever that
pinball has and card games do not. Because the table is generated from a data
layout rather than hand-placed in a scene, a mod is just an edit to that data.

- **Extra Bumper** — a fourth pop bumper joins the cluster
- **Wide Flippers** — +4px flipper length, narrowing the drain gap
- **Post Rubber** — a centre post between the flippers; catches some drains
- **Outlane Guards** — narrows both outlanes
- **Second Spinner** — a spinner on the left orbit
- **Kicker** — the left outlane kicks the ball back into play once per ball

### Target levels (planet cards)

Level up a *class* of target rather than an instance. `Bumpers Lv3` raises the
base value of every bumper on the table. This is the flat-power axis that keeps
pace with the score curve when the relic pool goes dry, and it is what makes a
table mod that adds a fourth bumper worth more later than it was early.

| Class | Base value | Per level |
| --- | --- | --- |
| Pop bumper | 10 | +8 |
| Slingshot | 15 | +10 |
| Drop target | 50 | +35 |
| Standup target | 30 | +20 |
| Spinner (per rev) | 5 | +4 |
| Rollover lane | 25 | +15 |
| Orbit | 100 | +60 |

### Coils (flipper powerups)

Upgrades to the flippers and the machinery around them. This is the **survival**
axis, and it is the only layer that changes how the game *feels* in the hand
rather than what a hit is worth. Deliberately kept off the score sheet: a coil
never adds a point, it only buys you more chances to score.

| Coil | Effect |
| --- | --- |
| Hot Winding | Flipper sweep is 20% faster — a later flip still connects |
| Heavy Bat | The flipper imparts more speed; harder shots, less control |
| Long Bat | +4px flipper length, narrowing the drain gap *(exists as a mod)* |
| Magna-Hold | Hold a flipper to catch and cradle the ball for up to 2s |
| Post Save | A centre post between the flippers, once per ball |
| Kickback | The left outlane fires the ball back into play, once per stage |
| Dead Bounce | A ball landing on a *lowered* flipper bounces up instead of rolling to the tip |
| Second Coil | An upper-left flipper, for shots that are otherwise unreachable |

`Magna-Hold` is the one that changes the skill ceiling rather than the floor.
Cradling is the single biggest technique in real pinball — it converts a chaotic
ball into an aimed shot — and it is currently impossible here because a resting
flipper rolls the ball straight to its tip. Adding it is the difference between
*reacting* and *playing*.

`Heavy Bat` is deliberately double-edged. More speed is more scoring and less
control, and a player who buys both it and `Hot Winding` should find the table
genuinely harder to hold. Not every coil should be a straight upgrade.

### Ball mods

Applied to **one ball**, chosen before it is plunged. Everything else in the
build is decided in the shop, minutes before it matters; this is the only layer
that asks the player a question *during* a stage — "I have two balls left and
I'm 4,000 short: do I spend the Heavy Ball now or save it?"

That per-ball decision point is worth more than the effects themselves. Right
now the only choices in a stage are which target to shoot at, and the game is
thinner for it.

| Ball mod | Effect |
| --- | --- |
| Heavy Ball | Ball is 2× the size — cannot fit down the drain gap, but also cannot enter the orbits or lanes |
| Light Ball | Smaller and faster; reaches shots a normal ball cannot, drains more easily |
| Gilded Ball | This ball's hits score ×2 |
| Slow Ball | Time runs at 60% for this ball's first 10 seconds |
| Ghost Ball | Survives its first drain |
| Split Ball | Becomes two balls on the first bumper hit |

`Heavy Ball` is the clearest example of why the playfield being *data* pays off.
Doubling the ball's radius is one number, and the consequences are entirely
geometric and entirely honest: an 8px drain gap will not pass a 16px ball, and
neither will an 11px outlane or a 22px orbit. The upgrade protects you and locks
you out of half the table in the same stroke, and nobody had to write a rule
saying so.

`Slow Ball` needs care. Slowing time is the most powerful thing you can hand a
player in a real-time game — it makes *everything* easier, including the parts
that are supposed to be hard. So it is strictly limited: a few seconds, once per
ball, never permanent. If it becomes a general difficulty setting it will
quietly replace skill, and the feel gate stops meaning anything.

### What these categories are *not*

Two of the obvious ideas already exist under other names, and giving them their
own layer would be the mistake that turns five categories into five shallow
ones:

- **"Score multipliers from hitting components"** is what `Relics` and `Levels`
  already are — `Brass Bumper` is a component multiplier, and `Bumpers Lv3` is
  the flat version of the same thing.
- **"Bumper multipliers"** is exactly `Target levels`. The bumper is one of
  seven part classes that already level.

If an idea can be expressed as an existing layer, it should be. New layers earn
their place by acting on a **new object** (the flippers, one ball) or at a **new
time** (mid-stage rather than in the shop) — not by being a new number.

## Boss blinds

The boss blind is a **hazard applied to the machine**, not a bigger number. Each
one attacks a different part of the build, so a run that has leaned entirely on
one axis meets a wall.

| Boss | Effect |
| --- | --- |
| The Governor | MULT is capped at ×4 |
| The Dead Bumper | Pop bumpers score nothing |
| The Drain | Outlanes are twice as wide |
| The Short Ball | 2 balls instead of 3 |
| The Warp | The left flipper dies for 3s at a time |
| The Tilt | Nudges disabled |
| The Reset | Every 5th hit resets MULT to ×1 |
| The Fog | The upper third of the playfield is not drawn |

`The Fog` is the one that is about the player rather than the build — it takes
away information, not power, and a player who knows the table by feel beats it.

## The table

One machine for now. Variety comes from mods and relics rather than from a table
pool; a second table is worth building only once the modifier layers are proven,
because every table has to be balanced against all of them.

Playfield, in table-local pixels (280 × 344):

- **Plunger lane** down the right edge, with a one-way gate at the top
- **Top arch** with two **rollover lanes**
- **Pop bumper cluster** — three, upper middle
- **Drop target bank** — three, upper left
- **Standup targets** — two, upper right
- **Spinner** on the right orbit
- **Slingshots** above each flipper
- **Two flippers**, pivots at (92, 300) and (170, 300), a ~19px drain gap
- **Outlanes and inlanes** either side

### Physics

Tuned rather than simulated, but anchored to real numbers so the tuning has a
starting point that is not a guess.

- Physics tick is **120 Hz**. Pinball at 60 Hz produces missed flipper contacts
  and tunnelling through thin walls; this is the single most important setting
  in the project.
- Ball is a `RigidBody2D` with **cast-shape CCD** and a hard speed clamp.
- Gravity: a real table is inclined ~6.5°, so the in-plane acceleration is
  `g·sin(6.5°) ≈ 1.11 m/s²`. A 42" playfield mapped to 344px gives ~322 px/m,
  so ~357 px/s². The project runs at **480 px/s²** — faster than real, because
  a faithful table feels sluggish on a screen.
- Flippers are `AnimatableBody2D` with `sync_to_physics`, sweeping 60° in ~48ms.
  Kinematic bodies transfer momentum through the physics server, so the ball is
  launched by the flipper's actual motion rather than by a scripted impulse.
- Restitution is low on walls (0.25) and high on rubbers (0.75), which is what
  makes slingshots and bumpers read as *live* against a dead outer wall.

## Look and sound

The cabinet should read as **late-80s solid-state**: dark playfield, saturated
inserts, a segmented-LED score readout on the panel.

- **Sound is real already** and fully procedural — `src/autoload/sfx.gd`
  synthesises every effect into an `AudioStreamWAV` at boot from a
  pitch-sweep-plus-noise generator. A solid-state cabinet's whole voice is
  decaying tones and bursts of noise, which is about twenty lines of
  arithmetic, and it keeps binary blobs that cannot be diffed out of the repo.
- **Art is not pixel art yet.** Everything on the playfield is currently drawn
  from the same `TableLayout` numbers that generate its collision, at 640×360
  with nearest filtering. That is chunky and readable and it cannot drift out
  of sync with the physics, which is exactly what milestone 1 needs — but it is
  vector shapes at a low resolution, not a pixel grid.

  The sprite pass (milestone 4) replaces the drawn parts with a generated
  16-colour sheet, following `rogue-like`'s `tools/gen_pixel_art.py` approach:
  ASCII grids and a palette in a stdlib-only Python script, so placeholder art
  stays editable in a diff rather than in a paint program. Walls stay drawn —
  they are generated geometry and a mod can move them.

## Milestones

1. **Vertical slice** — one table, real flipper feel, score/MULT, 3 balls, a
   stage target, win/lose. *No roguelike layer.* If the flippers are not fun
   with nothing bolted on, nothing bolted on will save them.
2. **Run loop** — antes, blinds, tokens, shop, 6–8 relics.
3. **Full modifier set** — table mods, target levels, all boss blinds.
4. **Feel pass** — sound, screen shake, insert lighting, score popcorn.
5. **Meta** — unlocks, seeded runs, daily.

Milestone 1 is the gate. Everything after it is arithmetic; milestone 1 is the
part that is actually a game.
