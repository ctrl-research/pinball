# Plan — Shipping TILT on Steam

Status: **not started**. TILT is currently a web build on GitHub Pages; the only
export preset in the repo is `Web`.

This plan separates what only **you** can do (accounts, money, legal identity)
from what is **engineering** (the game does not yet have the things a desktop
release needs). The engineering half is larger than it looks, and none of it is
Steam-specific plumbing — it is features a paying player would expect.

---

## 0. What only you can do

I cannot and should not do any of these. They need your legal identity, your
bank details, and your money.

- [ ] **Steamworks account** — company/individual details, identity
      verification.
- [ ] **Steamworks Direct fee** — $100 USD per title, recoupable against the
      first $1,000 of adjusted gross revenue.
- [ ] **Tax and banking** — W-8/W-9 equivalent and payout details. Valve will
      not release the game until these clear, and they can take days.
- [ ] **App ID** — issued once the fee clears; everything below keys off it.
- [ ] Decide **price**, **release date**, and **launch territories**.

Verify current fees and requirements against Steamworks documentation when you
start — these change, and this file will not.

---

## 1. Engineering gaps

Three things the game does not have. All were confirmed by grep, not assumed:

| Gap | Evidence | Why Steam needs it |
| --- | --- | --- |
| ~~No gamepad support~~ | **Done.** `src/autoload/controls.gd` | — |
| ~~No persistence of any kind~~ | **Done.** `src/autoload/save.gd` | — |
| ~~Web-only export~~ | **Done.** macOS, Linux and Windows presets, all three exporting cleanly | — |

### 1a. Gamepad — **done**

The input map has ten actions: `flip_left`, `flip_right`, `plunge`,
`nudge_left/right/up`, `use_consumable_1..3`, `toggle_crt`. A natural mapping:

- Flippers → **left/right shoulder buttons**. This is what every pinball game
  does and what a player will try first.
- Plunge → **A / bottom face**, held, matching the existing charge mechanic.
- Nudge → **left stick** direction, or the three remaining face buttons.
- Consumables → **d-pad**.

**The shop turned out not to need new navigation code.** The claim above --
that its buy and sell rows are mouse-only and that focus navigation would have
to be built -- was wrong: Godot resolves focus neighbours geometrically, and
every row in the shop is already reachable with a d-pad. `click_test` now proves
it by walking all four directions from wherever the shop puts focus and
asserting every button is reached, and it was checked against a deliberate break
(making offer rows mouse-focus-only leaves 4 of 11 unreachable).

### 1b. Persistence — **done**

Minimum for a paid release:

- **Settings** — CRT on/off (already a runtime toggle, currently forgotten on
  quit), volume, window mode.
- **Run resume** — a roguelike run is long. Quitting mid-run and losing it is
  the single most common complaint about early-access roguelikes.
  `Run` is already a single autoload holding all run state, which makes this
  much cheaper than it would otherwise be: serialise that one object.
- **Meta progression / stats** — the end-of-run summary already computes best
  stage, longest combo and most-used ball. Persisting those across runs is a
  small step and is what makes a "best ever" screen possible.

### 1c. Desktop exports — **done**

- Windows, Linux and macOS presets are in `export_presets.cfg` and all three
  export without errors. macOS is universal (x86_64 + arm64); the other two are
  x86_64.
- Universal macOS needs `textures/vram_compression/import_etc2_astc` enabled or
  Godot refuses the arm64 half outright. It is on now; this project has almost
  no textures, so it costs nothing.
- **macOS codesigning is not optional even for local use.** With signing
  disabled the bundle keeps the *export template's* signature, which no longer
  matches once the `.pck` is injected -- `spctl` reports "code has no resources
  but signature indicates they must be present", and an invalid signature is
  fatal on Apple Silicon rather than merely a warning. The preset ad-hoc signs
  (`codesign/codesign=1`), which verifies strictly and launches.
- `spctl -a` still reports "rejected", and that is expected: it assesses against
  the *distribution* policy, which no un-notarised app passes. It does not block
  a locally built app, because Gatekeeper only gates bundles carrying
  `com.apple.quarantine` -- i.e. downloads. Shipping to anyone else is what
  needs a Developer ID and notarisation.
- The project runs the **GL Compatibility** renderer, which is the safest choice
  here — it covers old hardware and the Steam Deck without fuss. The CRT shader
  samples `hint_screen_texture`, which is supported there; verify on each
  platform rather than assuming.
- **macOS** needs notarisation for a warning-free launch, which needs an Apple
  Developer account (~$99/yr). Consider shipping Windows + Linux first.
- **Windows** code signing is optional but reduces SmartScreen warnings.

---

## 2. Steam integration

Only needed if you want achievements, cloud saves or the overlay.

- **GodotSteam** is the usual route — a GDExtension wrapper around the
  Steamworks SDK for Godot 4.x. Check its compatibility against the exact Godot
  version in `.github/workflows/build.yml` before committing to it.
- Keep it **isolated behind one autoload** with no-op fallbacks. The web build
  must keep working, the headless tests must keep running in CI with no
  Steam client present, and neither should know Steam exists. This is the same
  shape as the existing `Crt`/`Sfx` autoloads.
- **Steam Cloud** can be configured to sync a `user://` save path with no code
  at all — do the persistence work in §1b first and cloud may be free.
- Achievements need a list designed against real milestones. The run summary
  stats are the obvious source: longest combo, best stage, beat the machine.

---

## 3. Build and release pipeline

- Builds upload through **SteamPipe** (`steamcmd`), driven by a VDF app/depot
  config committed to the repo.
- CI already exports the web build on every push. Extend it to export the
  desktop targets on a tag, and upload to a Steam **beta branch** — never
  straight to default. A bad build on default is live to customers.
- Keep the six existing gates (`RUN_TEST_OK`, `CLICK_TEST_OK`,
  `INLANE_TEST_OK`, `CONTAINMENT_OK`, `SIM_OK`, manual staleness) as
  release blockers.

---

## 4. Store page

Assets Valve requires, in several sizes (library capsule, header, main capsule,
small capsule, screenshots, and a trailer). **Check current dimensions in
Steamworks documentation** — they have changed more than once and are not worth
recording here.

Everything here is a *design* job, not a code one, and it is usually
underestimated:

- Capsule art that reads at thumbnail size. The game's identity is currently
  primitives-and-shaders; a sprite pass may be worth doing first so the
  screenshots and the game agree.
- A trailer. Pinball demos well — a 30s cut of a long combo with the fever
  meter climbing does most of the work.
- Short and long description, tags, genre.
- **Content survey and age rating.**

---

## 5. Timeline constraints

Two hard ones that catch people out:

- The store page must be **public ("Coming Soon") for at least two weeks**
  before the release date.
- Valve **reviews the build and the store page** before either goes live —
  budget several business days, and longer if something is rejected.

So the earliest realistic release is *engineering complete* → *store page up* →
*two weeks minimum* → *launch*. Plan backwards from a date, not forwards from a
finish.

---

## Suggested order

1. ~~**Desktop export presets**~~ — done. Not wired into CI: the desktop
   templates are a large download and would slow every build, so this belongs on
   a tag rather than on every push.
2. ~~**Gamepad support**~~ — done.
3. ~~**Persistence**~~ — settings and run resume done; cross-run stats still to
   do.
4. **Store page up** (starts the two-week clock running in parallel with the
   rest).
5. **Steam integration** — achievements and cloud, once saves exist.
6. **SteamPipe pipeline**, uploading to a beta branch from CI.
7. **Art and trailer** — the long pole, and the thing that sells it.

Note that steps 1–3 are all things the game would want anyway. Only 5 and 6 are
genuinely Steam-specific.
