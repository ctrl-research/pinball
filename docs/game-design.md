# TILT — Game Design (working title)

An arcade **pixel-art pinball roguelike**. One silver ball, a table you rebuild
between rounds, and a score target that grows faster than you do.

Think **Balatro's run structure poured into a pinball cabinet**: every stage is
a score you have to beat with a limited number of balls, and the way you beat it
is the pile of trinkets, table mods, and target upgrades you've bolted onto the
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
have** — the trinkets and the MULT those trinkets are feeding. It is the build, and
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
| **Stage** | Play all 3 balls. Beat the score target by the end of them. |
| **Ball** | Plunge, play, drain. The playfield MULT resets between balls. |
| **Judged** | Once, when the last ball is gone: **victory** or **defeat**. |
| **Clear** | Bank tokens, take a reward, visit the shop. |
| **Fail** | Last ball drained below target → run over. |

**A stage always runs its full complement of balls.** Crossing the target does
not end it; it only means the rest of the stage is played for the payout
multiplier instead of for survival.

An earlier version ended the stage the instant the target fell, on the argument
that crossing it mid-ball is the moment of victory and making the player wait
throws away the best beat in the stage. That reasoning is not wrong, but it
costs more than it buys. Ending early means a good ball is *punished* — the
better you are, the sooner the machine takes the ball off you — and it makes the
stage length unpredictable, so the player can never plan across balls. Playing
all three makes a stage a fixed, complete arc: you always know how much runway
is left, and a great first ball buys you two balls of pure upside instead of
ending the round.

The cost of that choice is that the balls after the target is met would be a
chore — the stage is decided and nothing you do matters. The payout multiplier
below exists to answer that, and it is the reason the rule works at all.

Score targets follow Balatro's ante curve, because it is a curve that is known
to work — it roughly triples early and then stretches:

| Ante | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Base | 300 | 800 | 2,000 | 5,000 | 11,000 | 20,000 | 35,000 | 50,000 |

Small blind = base ×1, big blind = ×1.5, boss blind = ×2.

### Fever

A second multiplier, stacked on top of MULT rather than folded into it:

```
score += value x MULT x FEVER
```

Fever climbs by ×0.25 on every scoring contact, caps at ×5, and **falls all the
way back to ×1 after two seconds without one**. MULT is the ball you have built
over twenty seconds and lose on the drain; fever is the last two seconds.

Two multipliers rather than one because they answer different questions and are
earned in different ways. MULT rewards *keeping the ball alive*; fever rewards
*hitting things quickly*, which is what makes a bumper nest feel different from
a slow, careful ball that has been in play a while. Folded together, a player
could not tell which of the two things they were being paid for.

It decays as a cliff rather than a slope. A slow bleed would mean the number is
always slightly wrong and never worth reading; falling off after two silent
seconds is a rule you can play around — and it makes the orbit, which takes
about that long, a genuine gamble with a combo in hand.

The cap is load-bearing. Uncapped, a bumper nest on a stacked MULT would produce
numbers that make the ante curve meaningless.

`Combo Coil` was a trinket that granted +0.2 MULT on quick hits, which is the
same problem fever solves. It now builds fever twice as fast instead — two
systems for "you are hitting things quickly" is one more than a player can read.

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
- **Overkill multiplier**: the base reward is multiplied by how many times over
  you beat the target — ×2 for double, ×3 for triple, capped at **×5**
- `$1` per ball you never needed — cross the target on ball one, get paid for
  the two that follow
- Interest: `$1` per `$5` held, capped at `$5`

The overkill multiplier is what makes the balls after the target worth playing.
Without it a stage would be decided halfway through and then continue anyway;
with it, every ball after the target is a push-your-luck bet — keep shooting for
a bigger multiplier, with a tilt still able to take away the MULT you were doing
it with.

It multiplies rather than adds because the reward should scale with the build.
An ante 8 boss beaten twice over is a far harder thing than an ante 1 small
blind beaten twice over, and a flat bonus pays them the same. It is capped
because the tail is unbounded: one good ball on a stacked MULT can exceed an
early target by an order of magnitude, and paying for all of it would let ante 1
fund the entire run.

The balls-not-needed payout is the same lever as Balatro's unused hands. It
survives the "play all the balls" rule because what it counts is the balls you
did not *need*, recorded at the moment the target fell — not the balls left
over, which is now always zero.

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
| **Trinkets** | Events | *What rule is bent?* |
| **Levels** | Part classes | *What is my best shot worth?* |
| **Coils** | The flippers | *How long do I keep the ball alive?* |
| **Consumables** | One stage | *What does **this** stage need?* |
| **Table mods** | The playfield | *What does the machine look like?* |

The load-bearing split is the last two columns against the first two. Trinkets and
levels make a good ball **worth more**. coils and consumables make good balls
**more likely**. A run that only buys score dies at ante 4 with a huge MULT it
never got to use; a run that only buys survival keeps the ball alive for a
minute and still misses the target. That tension is the build decision, and it
is the thing a naive Balatro clone leaves out.

**Trinkets stay the primary axis.** Balatro is a game about jokers with four
supporting systems, not a game about five equal systems — spreading power evenly
across categories is how this ends up with five shallow ones. The rule of thumb:
if an effect could be a trinket, it should be a trinket.

### Trinkets (jokers)

Up to **5 slots** on the panel. Passive, always-on, and the primary axis of a
build. They hook a small set of events: `on_hit`, `on_score`, `on_ball_start`,
`on_drain`, `on_stage_start`.

| Trinket | Effect |
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
pace with the score curve when the trinket pool goes dry, and it is what makes a
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

### Consumables

One-shot items, held **up to three** at a time, bought and sold in the shop and
fired **mid-ball with the 1-3 keys**. Most run on a timer and then stop.

That timing is the whole design. A consumable spent on a menu is just a slower
shop purchase; a consumable spent with the ball live is a read — pop Ball Polish
now, or hold it in case this ball reaches the bumpers? An earlier version had
these chosen on the stage intro screen, and it was exactly the boring version of
this.

| Consumable | Effect | Cost |
| --- | --- | --- |
| Steady Hand | 30s: nudges recharge 3× faster | `$3` |
| Ball Polish | 20s: all values ×2 | `$5` |
| Second Wind | 30s: a drain returns the ball | `$5` |
| Jackpot Charge | 12s: every hit also pays a flat 500 | `$5` |
| Overclock | 20s: MULT gains are doubled | `$6` |
| Surge | MULT jumps to at least ×3, now | `$6` |
| Extra Ball | One more ball this stage | `$6` |
| Slow Ball | 6s: everything runs at 55% speed | `$7` |

The strongest are the shortest. `Slow Ball` is the one the scheme was worth
building for: slowing time is the most powerful thing you can hand a player in a
real-time game, so six seconds is enough to save one ball you had already lost
and not enough to play the game in.

**Slots are fixed, not a list that closes up.** Firing slot 1 leaves slot 1
empty rather than sliding slot 2 down into it. These are bound to keys and fired
under pressure — if the rack shuffled, a panicked double-tap would burn two
items, and "my Slow Ball is 2" would never become muscle memory. A hole is the
price of a stable binding.

**Duplicates stack.** Buying a second Ball Polish adds to the slot you already
have rather than taking a second one, and firing spends exactly one — the rest
stay on the same key. So the three-slot limit is a limit on **kinds**, not on
items: you can hold three Ball Polish and two Slow Ball across two slots.

Stacks are capped at **5** per slot. Purely a balance number — it keeps the
readout single-digit and stops three slots becoming unbounded storage — and
nothing breaks if it moves. Past the cap, a further copy takes a fresh slot if
one is free.

Trinkets do not stack, because two of the same trinket is not a thing anyone
wants: a second Brass Bumper would either do nothing or silently square itself,
and neither reads.

Refiring an effect that is already running restarts its timer rather than
stacking, because two overlapping Ball Polish would be ×4 and nothing in the
shop says so. Stacking is about how many you *hold*, not how many can run at
once.

#### Two that act on the table

Most consumables change the arithmetic. Two change where the ball goes, which is
what earns them their price.

**Bumper Gravity** gives each pop bumper a short-range pull for 30 seconds. It
is deliberately weak: a force strong enough to visibly yank the ball is strong
enough to hold it in the nest until the stage ends, and a power-up that ends the
ball is not a power-up. The effect is "the nest is sticky", not "the table is
tilted" — it bends the ball's path toward the cluster and lets the bumpers do
the rest.

**Wormhole** is the expensive one. For 30 seconds the bottom of the table stops
being the end of the ball: anything that would drain instead comes back up the
plunger lane to be re-plunged. Portals are drawn at both mouths — across the
drain and at the plunger — and only while it is open, because a portal that is
always there stops reading as something you spent money on.

Wormhole is priced as the most expensive consumable because it removes the
game's only real threat. Thirty seconds of not being able to lose is worth more
than any multiplier, and it should cost accordingly.

#### Why Heavy Ball is not here

An earlier draft had a consumable that doubled the ball's radius, and it was the
best illustration of what the playfield-as-data buys: one number, and an 18px
drain gap will not pass a 16px ball.

It cannot survive being fired mid-ball. The ball is frequently *inside* an 11px
outlane or a 22px orbit, and growing a collision shape inside solid geometry
either ejects it violently or wedges it. The idea is sound and the timing is
not, so it belongs to a layer that applies between balls — a table mod, or a
coil — and it is parked there rather than dropped.

### The shop

Four offers, weighted toward trinkets and consumables. Trinkets lead because
they are the axis players build around; consumables are second because they are
the only thing that answers a boss already in view. Table mods and levels are
the long tail.

**Your inventory is shown in the shop, with a price on it.** Anything owned can
be sold back for **75% of its shelf price, rounded down**.

That the inventory is *in* the shop is the point. Selling is only a real
decision if you can see the thing you would be giving up next to the thing you
would be buying with it; a sell button on some other screen is just a refund.
The 25% loss is what stops the shop being a place to park money rather than a
place to make a choice.

An offer you have no room for is shown greyed with *no room*, and one you cannot
afford with *too dear* — two different reasons a thing is unavailable, and the
player should not have to work out which applies. Selling immediately re-enables
anything that was blocked on space.

### What these categories are *not*

Two of the obvious ideas already exist under other names, and giving them their
own layer would be the mistake that turns five categories into five shallow
ones:

- **"Score multipliers from hitting components"** is what `Trinkets` and `Levels`
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

One machine for now. Variety comes from mods and trinkets rather than from a table
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
- **The whole screen sits behind a CRT.** `src/ui/crt.gdshader` adds curvature,
  scanlines, an aperture grille, chromatic fringing and a vignette as a
  full-screen pass — over the cabinet and both panels, not just the playfield,
  because a monitor is in front of everything. Applying it to the playfield
  alone would put the panels outside the glass, which reads as a filter on part
  of a game rather than as a game on a CRT.

  Every parameter is deliberately understated, and it is toggled with **F1**.
  The panels carry 7pt text, and a shader that makes the score unreadable has
  bought atmosphere with the one thing the player actually needs. The curvature
  is the mildest setting of all, because it sits on top of the playfield's own
  perspective warp and two distortions arguing with each other look like a bug.

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
2. **Run loop** — antes, blinds, tokens, shop, 6–8 trinkets.
3. **Full modifier set** — table mods, target levels, all boss blinds.
4. **Feel pass** — sound, screen shake, insert lighting, score popcorn.
5. **Meta** — unlocks, seeded runs, daily.

Milestone 1 is the gate. Everything after it is arithmetic; milestone 1 is the
part that is actually a game.
