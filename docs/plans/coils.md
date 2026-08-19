# Plan — Coils (flipper powerups)

Status: **not started**. Design lives in
[`game-design.md`](../game-design.md#coils-flipper-powerups); this is the
implementation plan and it revises that design where the table disagreed with it.

Coils are the fifth modifier layer and the only one on the **survival** axis.
Every other layer makes a good ball worth more; coils make good balls more
likely. Today every purchase in the game is a scoring purchase, which is the
imbalance this closes.

---

## 0. What the table already does

The design doc was written before the flippers were tuned and two of its
premises are now wrong. Both were measured by dropping a ball at (96, 280) —
just above the left flipper — and watching where it went:

| Flipper state | Result |
| --- | --- |
| **Held up** | Ball comes to a complete stop (speed `0.0`) 9.6px from the pivot and is still there at 4s |
| **At rest** | Ball rolls off and drains at **t=1.03s** |

So:

- **Cradling already works.** `flipper.gd` sets `friction = 0.7` precisely for
  this, and it does what it says: a held flipper catches the ball in the crook
  at its root and holds it indefinitely. `Magna-Hold` as designed — "hold a
  flipper to catch and cradle" — is a coil that sells the player something they
  already have.
- **A ball landing on a lowered flipper is dead.** One second from contact to
  drain, with no input that saves it. That is the real gap, and it is what
  `Dead Bounce` addresses.

**Consequence for the layer:** its headline feature changes from Magna-Hold to
Dead Bounce, and Magna-Hold either drops or is re-scoped (see
[Open decisions](#open-decisions)).

---

## 1. The blocker to solve first: shop space

The shop is **already at three columns and near-full** at the current text
scale. A full rack is thirteen inventory rows, and `click_test` asserts the
`NEXT BLIND` button stays on a 640×360 screen. Adding a fifth sellable category
will fail that gate.

This has to be settled before any coil exists, because it decides what the shop
code looks like:

- **(a) Tabs** — `HELD` / `BUY`, or one tab per category. Most room, most new UI.
- **(b) Scroll the inventory column** — a `ScrollContainer`; cheap, but a
  scrollbar in a pixel-art cabinet needs styling and hides items by default.
- **(c) Pair coils with balls in one column** — both are "the hardware", both
  are 5 slots. Cheapest, and probably too cramped at 10 rows in one column.
- **(d) Drop a category from the shop screen** — e.g. move table mods to a
  separate between-ante screen, since they are bought rarely.

**Recommendation: (a) tabs.** It is the only one that still works when a sixth
category appears, and this is now the second time in three features that the
shop has run out of room.

---

## 2. Scaffolding

Mirrors the ball system almost exactly — that path is well trodden, and coils
should not invent a second shape for "a thing you own five of".

- [ ] `Catalog.COILS` — id, name, desc, cost. Data only.
- [ ] `Catalog.sell_price` learns `"coil"`.
- [ ] `Run.coils: Array[String]`, `MAX_COILS := 3`, `has_coil()`, `add_coil()`,
      `sell_coil()`. Three, not five: coils change *feel*, and a player wearing
      five feel-changes at once cannot tell which is doing what.
- [ ] `Run.roll_shop()` offers coils, with a `can_take` guard for a full rack.
- [ ] `Run.new_run()` clears them.
- [ ] HUD: a `COILS` block in the left panel and a shop column (per §1).
- [ ] `tools/dump_catalog.gd` + `tools/build_manual.py` — a generated coils
      table, so the manual cannot drift.
- [ ] `run_test`: a `_coils()` section, registered in `SECTIONS`.

**Gate:** `click_test` still passes with a full rack of *four* categories.

---

## 3. The coils, cheapest first

Ordered by risk deliberately: the constants land the category and prove the
scaffolding before any of them touches the physics.

### Phase A — constants (no new mechanics)

| Coil | Implementation | Test |
| --- | --- | --- |
| **Hot Winding** | `FLIPPER_SWEEP_TIME × 0.8` in `flipper.gd` | A held flip reaches `_t == 1` in fewer ticks |
| **Heavy Bat** | Raise the flipper's `PhysicsMaterial.bounce` (0.2 → ~0.35) | Ball leaves a full sweep faster than baseline |

`Heavy Bat` is deliberately double-edged: more speed is more scoring and less
control, and a player who buys it *and* `Hot Winding` should find the table
harder to hold. A layer where every item is a straight upgrade is a shopping
list, not a build.

`Long Bat` from the design doc is **cut** — it already exists as the
`wide_flippers` table mod, and two names for one effect is a bug in the
catalogue rather than a feature.

### Phase B — behaviours (new logic, no new bodies)

| Coil | Implementation | Test |
| --- | --- | --- |
| **Dead Bounce** | On ball/flipper contact while `_t < 0.1`, apply an upward impulse instead of letting it roll. Needs a contact hook on the flipper. | The 1.03s drain above becomes a survival: ball still alive at 3s |
| **Kickback** | Left outlane fires the ball back up the lane, once per stage. `_retire_ball()` already intercepts for Wormhole — same seam. | An outlane ball survives once and drains the second time |
| **Post Save** | Raise the existing `post_rubber` mod geometry for one ball, then drop it. | A ball aimed down the middle bounces once, then drains |

`Dead Bounce` is the one to build first of these three — it is the coil that
answers the measured gap, and the only one whose absence currently costs balls
to something the player cannot react to.

### Phase C — new hardware (highest risk)

| Coil | Why it is last |
| --- | --- |
| **Second Coil** (upper-left flipper) | A new `AnimatableBody2D`, a new input binding, a new pivot in `TableLayout`, and it changes the shape of the upper playfield — which the containment test covers 156 cases of. Expect to re-run and extend that suite. |

---

## 4. Test plan

Every phase ships with its gate, in the established style — write the failing
test first, then the fix.

- `run_test._coils()` — slots fill and sell, duplicates, `can_take` on a full
  rack, effects only apply when owned.
- `inlane_test` — a `Kickback` case beside the existing Wormhole one; they use
  the same `_retire_ball()` seam and must not interfere.
- A new `flipper_test`, or an extension of `inlane_test`: the two probes in §0
  become permanent assertions. *A ball on a resting flipper drains* is a
  documented behaviour now, and `Dead Bounce` must change it only when owned.
- `containment_test` — re-run after `Second Coil`; extend if the upper
  playfield changes.
- `click_test` — the on-screen gate, at a full rack of every category.

---

## Open decisions

1. **Shop layout** (§1) — blocks everything. Recommendation: tabs.
2. **Magna-Hold** — cut, or re-scope to "cradle on a *lowered* flipper too",
   which would be a genuinely new ability rather than a sold-back one? Cutting
   it leaves six coils, which is a reasonable size for the layer.
3. **`MAX_COILS = 3`** — or 5, to match trinkets and balls? Three is proposed
   because feel-changes are hard to attribute when stacked.
4. **Feel gate.** Coils modify flipper feel, and the current flipper feel has
   never been checked by a human. `Hot Winding` and `Heavy Bat` are tuning
   multipliers on numbers nobody has confirmed are right — if the base sweep is
   wrong, both coils are wrong too, and no test will say so.
