# TILT — Manual

Every mechanic in the game, as it currently behaves.

This is the **reference**: what the rules are. [game-design.md](game-design.md) is
the **rationale**: why they are that way, and what was rejected. When the two
disagree, this one is right — the tables below are generated from the same
`catalog.gd` the game runs on, and CI fails if they drift.

> Sections between `BEGIN GENERATED` markers are produced by
> `tools/build_manual.py`. Edit `src/run/catalog.gd` and re-run it; editing the
> table directly will be overwritten and the check will fail.

---

## Controls

Keyboard and controller both work at once, and the panel shows whichever you
have plugged in.

| Does | Keyboard | Controller |
| --- | --- | --- |
| Left flipper | **A** / **←** | **L1** |
| Right flipper | **D** / **→** | **R1** |
| Plunger — hold to charge | **SPACE** | **A** |
| Nudge left / up / right | **Q** / **W** / **E** | d-pad left / up / right |
| Fire the consumable in a slot | **1** / **2** / **3** | **X** / **Y** / **B** |
| Toggle the CRT effect | **F1** | **Back** |
| The button on any between-stage screen | **Enter** | **A** |

Menus and the shop take the d-pad to move between items and **A** to choose —
the same **A** that plunges, because the affirmative button should mean the same
thing in both places.

Holding the plunger longer fires harder. Even a tap clears the arch — the charge
controls *where* the ball ends up, not whether it gets into play.

---

## A run

Eight antes, three stages each: small blind, big blind, boss blind. Clear all
twenty-four and you have beaten the machine. Fail one and the run is over.

A stage gives you a **score target** and **three balls**. You always play all
three — beating the target early does not end the stage, it means the rest is
played for money instead of survival. Win or lose is decided once, when the last
ball drains.

### Leaving and coming back

A run is saved at the start of every stage. Quit and the title screen offers
**CONTINUE**, which picks up at the beginning of the stage you were on — you
keep your money, trinkets, coils, balls, mods and target levels, and replay the
stage itself from its first ball.

Starting a new run from the title screen discards the saved one.

The CRT toggle (**F1**) is remembered between sessions.

### When the run ends

Victory or defeat, the last screen carries a summary of the run:

| Line | What it is |
| --- | --- |
| Best stage | The highest single stage you scored, and which one it was |
| Longest combo | The most scoring contacts you strung together without a 2s gap |
| Most-used ball | The ball type served most often, and how many times |

The combo count is not the fever level: it keeps counting past the ×5 cap, so it
is a record of how long you kept the ball working rather than of what the meter
was worth.

### Score targets

<!-- BEGIN GENERATED: blinds -->
| Ante | Small Blind (x1) | Big Blind (x1.5) | Boss Blind (x2) |
| --- | --- | --- | --- |
| 1 | 300 | 450 | 600 |
| 2 | 800 | 1,200 | 1,600 |
| 3 | 2,000 | 3,000 | 4,000 |
| 4 | 5,000 | 7,500 | 10,000 |
| 5 | 11,000 | 16,500 | 22,000 |
| 6 | 20,000 | 30,000 | 40,000 |
| 7 | 35,000 | 52,500 | 70,000 |
| 8 | 50,000 | 75,000 | 100,000 |
<!-- END GENERATED: blinds -->

---

## Scoring

Every scoring element has a **value**. The playfield has a **MULT**. A hit banks:

```
score += value x MULT
```

immediately — not at the end of the ball.

**MULT starts each ball at ×1**, only ever climbs during that ball, and is lost
when the ball drains. The ball that has been alive longest is worth the most and
is the one you can least afford to lose.

### Fever

A second multiplier, on top of MULT:

```
score += value x MULT x FEVER
```

- Starts each ball at **×1**
- **5 scoring contacts** raise it one level
- Each level is worth **+0.25**
- Caps at **×5**
- Drops **straight back to ×1** after **2 seconds** without a contact, and takes
  any part-built level with it

MULT is the ball you have built and lose on the drain. Fever is the last two
seconds. The contact that *starts* a combo scores at ×1 — only the ones after it
are worth more.

The right-hand panel shows the current fever above a meter of **five segments** —
one per contact needed for the next level — with a hairline under them counting
down the two seconds you have left to keep the chain alive. At the cap all five
turn gold, because there is no next level to fill.

Combo Coil and the Ember ball make fever build **twice as fast**. Both work on
the contacts needed — three instead of five — rather than on the size of a
level, so a level is worth the same 0.25 to everyone.

### What each target is worth

Value is `base + per_level x (level - 1)`, where level is bought in the shop and
applies to that whole class of target, not one instance of it.

<!-- BEGIN GENERATED: levels -->
| Target class | Base value | Per level |
| --- | --- | --- |
| Pop Bumpers | 10 | +8 |
| Slingshots | 15 | +10 |
| Drop Targets | 50 | +35 |
| Standup Targets | 30 | +20 |
| Spinner | 5 | +4 |
| Rollover Lanes | 25 | +15 |
| Orbits | 100 | +60 |
| Ramp | 90 | +55 |
| Saucer | 120 | +70 |
| Jackpot | 500 | +0 |
<!-- END GENERATED: levels -->

---

## The ramp, the saucer, and the top lanes

Three elements that do more than bounce the ball back.

**The ramp** — the mouth on the right, level with the bumpers. A ball that
enters it is lifted off the playfield, carried over the top of the table, and
dropped into the **left orbit**, where it runs down past the spinner and into
the left inlane. It scores on entry and then hands you the orbit and the spinner
for free, so it is worth more than its own number suggests.

Nothing on the playfield can touch the ball while it is up there. It passes over
the bumpers and the lanes rather than through them.

**The saucer** — the orange-rimmed hole on the left, beside the bumpers. It is
a cross-table shot off the right flipper, where the ramp is a shot off the left. It swallows the
ball, holds it for just under a second, and kicks it back down towards the
flippers. It is the only place on this table where the ball stops, which makes
it the moment to read your score. It will not take another ball straight away.

**The top lanes** — three of them, under the arch. Each lights as the ball rolls
through it, and lighting all three pays a bonus worth several more lanes and
resets them all. They stay lit across balls, so a lane you caught early is still
lit when you come back to it.

---

## Nudging and tilt

Nudging shoves the ball a few pixels — the only tool against a bad bounce. The
meter holds two and refills one at a time.

**Nudge with the meter empty and the machine tilts**: the flippers die, the ball
drains, and the MULT you were building is gone.

---

## The economy

Tokens (`$`) are earned by clearing a stage and spent in the shop.

- The blind's base reward, multiplied by how many times over you beat the target
  (×2 for double, ×3 for triple, capped)
- `$1` for each ball you never needed — beat the target on ball one and the two
  that follow still pay
- Interest: `$1` per `$5` held, capped at `$5`

Anything you own can be sold back in the shop. Consumables sell one at a time.

---

## The shop

Four offers between stages. An offer you have no room for reads **no room**; one
you cannot afford reads **too dear**. Selling something immediately re-enables
anything that was blocked on space.

---

## Trinkets

Passive and permanent. The axis you build around. No duplicates.

<!-- BEGIN GENERATED: trinkets -->
| Trinket | Effect | Buy | Sell |
| --- | --- | --- | --- |
| Brass Bumper | Pop bumpers score x3 value | $4 | $3 |
| Outlane Insurance | Draining down an outlane pays $3 | $4 | $3 |
| Slingshot Savant | Slingshots score +25 value | $4 | $3 |
| Skill Shot | The first hit of each ball scores x5 | $5 | $3 |
| Spinner Fever | Each spin this ball raises spinner value by 5 | $5 | $3 |
| Tilt Gremlin | +2 MULT while you have no nudges left | $5 | $3 |
| Ball Saver | The first drain each stage returns the ball | $6 | $4 |
| Combo Coil | Fever builds twice as fast | $6 | $4 |
| Drop Devotion | Clearing the drop bank: +1 MULT for the stage | $6 | $4 |
| Penny Slot | $1 per 1,000 points scored | $6 | $4 |
| Cold Solder | -1 ball per stage, but all values x2 | $7 | $5 |
| Jackpot Lamp | Every 8th hit scores a flat 500 x MULT | $7 | $5 |
| Magnet Coil | Every 10 bumper hits spawns a second ball | $8 | $6 |
| Deadhead | MULT no longer resets between balls | $10 | $7 |
<!-- END GENERATED: trinkets -->

---

## Consumables

One-shot, fired **mid-ball** with the 1-3 keys. Most run on a timer and stop.

Slots are **fixed**: firing slot 1 leaves slot 1 empty rather than sliding slot 2
into it, so a key always means the same thing. Duplicates **stack** into one
slot, and firing spends exactly one. Re-firing something already running restarts
its timer rather than stacking the effect.

<!-- BEGIN GENERATED: consumables -->
| Consumable | Effect | Lasts | Buy | Sell |
| --- | --- | --- | --- | --- |
| Steady Hand | 30s: nudges recharge 3x faster | 30s | $3 | $2 |
| Ball Polish | 20s: all values x2 | 20s | $5 | $3 |
| Jackpot Charge | 12s: every hit also pays a flat 500 | 12s | $5 | $3 |
| Second Wind | 30s: a drain returns the ball | 30s | $5 | $3 |
| Bumper Gravity | 30s: the bumpers pull the ball towards them | 30s | $6 | $4 |
| Extra Ball | One more ball this stage | instant | $6 | $4 |
| Overclock | 20s: MULT gains are doubled | 20s | $6 | $4 |
| Surge | MULT jumps to at least x3, now | instant | $6 | $4 |
| Slow Ball | 6s: everything runs at 55% speed | 6s | $7 | $5 |
| Wormhole | 30s: a drained ball returns to the plunger | 30s | $8 | $6 |
<!-- END GENERATED: consumables -->

---

## Balls

Five **ball slots**, every one holding a Vanilla ball when a run starts. Buying
a ball fills the first Vanilla slot; selling one puts that slot back to Vanilla.
You may own several of the same ball, and usually should — the slots set a
*ratio*, not a collection.

At the start of each stage the queue is drawn from the slots, one independent
draw per ball you get to play, so three Golds in five slots means a 60% chance
per ball rather than one guaranteed Gold. The right-hand panel shows the queue —
the ball in play, then everything behind it — before you plunge.

<!-- BEGIN GENERATED: balls -->
| Ball | Effect | Buy | Sell |
| --- | --- | --- | --- |
| Ember Ball | Fever builds twice as fast | $6 | $4 |
| Heavy Ball | Larger: fits no outlane, drains less | $6 | $4 |
| Lucky Ball | Pays $1 per 500 points scored | $6 | $4 |
| Gold Ball | Hits score x2 | $7 | $5 |
| Ghost Ball | Survives its first drain | $8 | $6 |
| Vanilla | No bonus | - | - |
<!-- END GENERATED: balls -->

**Upgrades** scale what a ball already does instead of adding a second effect:
Gold Lv2 scores ×3, Ghost Lv2 survives two drains. A ball can only be upgraded
while you own one, and each level costs more than the last.

Only the ball currently in play applies its effect. Owning a Gold ball does
nothing on the stages where you draw a Vanilla.

---

## Coils

Upgrades to the flippers and the machinery around them — up to **3** at a time.
A coil never adds a point. Every other category makes a good ball worth more;
coils make good balls more likely.

<!-- BEGIN GENERATED: coils -->
| Coil | Effect | Buy | Sell |
| --- | --- | --- | --- |
| Heavy Bat | Harder shots, and less control of them | $6 | $4 |
| Hot Winding | Flippers sweep 20% faster | $6 | $4 |
| Dead Bounce | A ball landing on a resting flipper bounces up | $8 | $6 |
| Kickback | The left outlane fires the ball back, once a stage | $9 | $6 |
<!-- END GENERATED: coils -->

They are held like trinkets rather than slotted like balls: there is no such
thing as an empty coil, so selling one closes the list up.

**Heavy Bat is not a straight upgrade.** More speed off the bat is more scoring
and less control of where the ball goes, and a machine wearing it *and* Hot
Winding is genuinely harder to hold. That is deliberate — a category where
everything is an improvement is a shopping list, not a choice.

**Kickback** is a one-use save: it comes back once a stage, not once a ball.

---

## Table mods

Permanent changes to the physical playfield — the one modifier layer that alters
the machine rather than the arithmetic.

<!-- BEGIN GENERATED: mods -->
| Table mod | Effect | Buy |
| --- | --- | --- |
| Outlane Guards | Both outlanes are narrowed | $6 |
| Extra Bumper | A fourth pop bumper joins the cluster | $7 |
| Wide Flippers | +4px flipper length; a narrower drain | $8 |
<!-- END GENERATED: mods -->

---

## Boss blinds

Every third stage. A boss attacks the machine, not the number, so a run leaning
entirely on one axis meets a wall.

<!-- BEGIN GENERATED: bosses -->
| Boss blind | Effect |
| --- | --- |
| The Governor | MULT is capped at x4 |
| The Dead Bumper | Pop bumpers score nothing |
| The Drain | Outlanes are twice as wide |
| The Short Ball | You get one fewer ball |
| The Warp | The left flipper dies for 3s at a time |
| The Tilt | Nudging is disabled |
| The Reset | Every 5th hit resets MULT to x1 |
| The Fog | The upper playfield is not drawn |
<!-- END GENERATED: bosses -->

---

## Limits

<!-- BEGIN GENERATED: limits -->
| Limit | Value |
| --- | --- |
| Trinket slots | 5 |
| Consumable slots | 3 |
| Consumables per slot | 5 |
| Balls per stage | 3 |
| Ball slots | 5 |
| Coil slots | 3 |
| Ball upgrade | $5, +$2 per level owned |
| Fever: contacts per level | 5 |
| Fever: per level | +0.25x |
| Fever: cap | x5 |
| Fever: chain window | 2s |
| Nudges held | 2 |
| Nudge recharge | 5s each |
| Payout multiplier cap | x5 |
| Sell price | 75% of buy, rounded down |
| Blind rewards | Small Blind $3, Big Blind $4, Boss Blind $5 |
<!-- END GENERATED: limits -->

---

## The table

One machine. Variety comes from trinkets, consumables and mods rather than from a
table pool.

- **Plunger lane** down the right, with a one-way gate at its mouth
- **Top arch** with two rollover lanes
- **Three pop bumpers**, upper middle
- **Drop target bank** of three, upper left — clearing all three scores the bank
- **Two standup targets**, upper right
- **Spinner** in the left orbit, worth more the faster the ball is travelling
- **Two slingshots** above the flippers
- **Two flippers** with a ~19px drain gap
- **Inlanes and outlanes** either side: the inlane returns the ball to a flipper,
  the outlane drains it

### Physics

| | |
| --- | --- |
| Physics rate | 120 Hz |
| Gravity | 480 px/s² |
| Ball speed cap | 900 px/s |
| Flipper sweep | 58° in ~48 ms |
| Restitution | 0.25 outer walls, 0.75 slingshot rubbers |

The ball itself has zero restitution; each surface declares its own, and Godot
combines by taking the maximum.
