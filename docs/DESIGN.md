<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Siegefall: design document

> **Working title.** The name *Siegefall* is already used by a 2015 Gameloft
> mobile strategy game (iOS/Android/Windows Phone). See
> [§10 Naming](#10-naming) for alternatives. The name and app ID live only in
> [`app.env`](../app.env), so a rename touches one file plus
> `make sync-identity`.

This document is the source of truth for *what* we are building and *why* the
technical choices were made. It is updated whenever a decision changes, and
each change gets a dated entry in [§11 Decision log](#11-decision-log).

---

## 1. Research summary

**Lineage.** *Castle Clout* (Liam Bowmers, Oct 2008, Flash) introduced the
"fling a trebuchet at a castle" toy. Armor Games got Bowmers' permission and
built *Crush the Castle* (Flash, April 2009; iPhone/iPod Touch, January 2010),
which is widely credited with popularising the physics-flinging genre that
*Angry Birds* later took mainstream. A *Players Pack* (Sept 2009) gathered
user-built castles, and *Crush the Castle 2* added new materials, ammo and a
better castle editor. Later releases include *Siege Master* and a *Legacy
Collection*.

**How the originals play** (from reviews and walkthroughs; the
Wikipedia page itself was unreachable from the build environment, so these
come from secondary sources):

| Aspect | Original behaviour | What we keep / change |
|---|---|---|
| Aiming | Click once to start the trebuchet swing, click again to release. The timing of the release is the whole aim. | **Keep.** It is the heart of the game. We add an optional ghost of the last shot's arc and a swing gauge, so timing can be learned. |
| Shots | Unlimited. Each level states how many shots earn gold/silver/bronze before you start. | **Keep.** Pars are computed by a bot (see §6.4) instead of hand-tuned. |
| Win condition | Kill every royal in the castle. | **Keep**, and add knights (armoured, tougher). Hostages arrive in realm 2. |
| Progression | Conquering towns upgrades/unlocks ammo. Bronze medals across a kingdom unlock the next kingdom. | Ammo unlocks at fixed campaign points and can be used everywhere afterwards. Finishing a level always unlocks the next one, because we never want to gate on skill. Medals are about mastery. |
| Ammo (CtC2) | Ever-sillier ammo handed out by quirky characters, from logs and bombs to an eel jar. | Eight original ammo types with clear roles (§3.3), several with a mid-air tap action. |
| Editor | CtC2: build castles from all materials, set time of day and weather, finer terrain control. Share via the portal. | Castle builder with test-play, local save, and **offline** share codes (§7). |
| Criticism | "Unlimited throws make it too easy"; "breakable blocks don't matter if you only need one shot"; levels sometimes "very puzzly". | Medals carry the challenge. Gold usually needs 1–2 perfect shots, and levels are tuned so that clever ammo plus a good release beats brute force. Materials break believably and differently, so *where* you hit matters. |

**Things we deliberately do not take:** any names (no "Arcturia", "Skull
Island", or "Crush"), characters, art, sounds, UI layouts or level layouts.
All of our content is designed from scratch.

## 2. Pillars

1. **The release is the aim.** Two taps. The moment of release decides
   everything, and it must feel crisp, readable and fair.
2. **Satisfying collapse.** Each material breaks in its own believable way.
   Dust hangs in the air afterwards. The camera shows you what you did.
3. **Short and kind.** Levels last seconds to a couple of minutes. Retry is
   instant (one key / one tap), with no fail screens and no punishment.
4. **Slapstick, not gore.** Royals get squashed flat or vanish in a poof of
   smoke, and their crowns and helmets go flying.
5. **Free forever.** No ads, IAP, analytics, telemetry or network access, ever.

## 3. Mechanics

### 3.1 Premise and tone

*King Grumbold the Petty* of the Greenmantle Hills is offended by everyone:
a neighbour's moat is wider, a baron's banners are brighter, a duchess didn't
laugh at his joke. You are his Royal Siege Engineer. Each level opens with a
one-line grievance (data-driven, translatable) and ends with Grumbold's verdict.

### 3.2 The trebuchet (two-tap)

* **Tap 1** releases the counterweight. The arm swings and the sling whips
  around, taking `swing_duration` seconds at normal speed (≈1.4 s).
* **Tap 2** releases the projectile. If you don't tap, the sling lets go by
  itself at the end of the swing and sends a comical, nearly vertical lob.
* The release is captured as a **swing phase** `p ∈ [0, 1]`, measured from
  the input event's own timestamp and not from the frame or physics tick, so
  the input resolution is sub-frame. The launch position and velocity are
  **pure functions of `p`** and the ammo type (see §8.3).
* Feedback: the arm, sling and counterweight animate from the same curve. A
  slim **swing gauge** next to the trebuchet shows the arm angle and marks
  where you released last time. The last shot's arc stays as a faint dotted
  **ghost trail**.
* **Swing-speed assist** (accessibility) slows the animation to 75% or 50%.
  Because the launch depends only on `p`, the assist does not change
  physics outcomes, and medals stay valid.

### 3.3 Ammo

All ammo is fired by the same trebuchet. Mass and drag change the arc, and
each type's material interactions give it a role. Unlocks are listed in
`game/data/ammo.json` and can be changed there.

| Ammo | Unlocks | Role | Mid-air tap |
|---|---|---|---|
| **Boulder** | start | Reliable all-rounder. | none |
| **Scatter-stones** | Greenmantle 4 | A bundle of 5 stones for wide, shallow damage, such as thatch roofs and exposed royals. | **Burst**: splits into a fan of stones. Bursts on impact if you don't tap. |
| **Iron ball** | Greenmantle 9 | Heavy and dense. Punches straight through wood (×3 damage to wood), clangs off iron. | none |
| **Powder keg** | Saffron 1 | Radial blast that shoves and damages. | **Detonate** early. Otherwise it explodes 0.25 s after impact. |
| **Firepot** | Saffron 5 | Sets wood, thatch and cloth burning. Burning blocks lose HP over time and spread fire to flammable blocks they touch. | none |
| **Chain shot** | Saffron 9 | Two spinning balls joined by a chain. Sweeps through thin supports and cloth. | **Snap**: breaks the chain so the balls fly apart. |
| **Frost flask** | Frostfang 1 | Freezes blocks in a radius. Frozen blocks turn **brittle**: low impact threshold, ×2.5 damage, and they shatter like glass. | none |
| **Void flask** | Frostfang 7 | A mini black hole that pulls nearby bodies inward for 1.5 s, crushes small debris, then pops. | **Open** early. Otherwise it opens on impact. |

### 3.4 Materials

Defined in `game/data/materials.json`. Values are per square metre of
block area, so a block's HP and mass scale with its size.

| Material | Density (kg/m²) | HP/m² | Impact threshold | Breaks into | Special | Sounds |
|---|---|---|---|---|---|---|
| Wood | 600 | 120 | low | long splinters along the grain, plus planks | flammable; iron ball ×3 | creak, crack, thunk |
| Stone | 2400 | 420 | high | chunky irregular blocks, plus lots of dust | ignores fire | grind, crunch, thud |
| Glass | 2500 | 40 | very low | many small sharp shards, plus a sparkle | n/a | tink, shatter |
| Ice | 900 | 90 | low | angular shards | already brittle; slippery (low friction) | crackle, shatter |
| Iron | 7800 | 1400 | very high | dents first, then 2–3 heavy pieces at most | sparks on hit; immune to fire | clang, ring |
| Thatch | 200 | 35 | very low | straw tufts (mostly particles) | very flammable; burns fast | rustle, whump |
| Cloth | 150 | 20 | very low | torn strips | flammable; can't carry load (soft, low friction) | rip, flap |

Damage model (§8.5) turns contact impulses into HP loss. Blocks show **three
crack stages** at 66%, 33% and 10% HP, then fracture into physical pieces.

### 3.5 Enemies

| Type | HP | Notes | Elimination |
|---|---|---|---|
| **King** | low | Required target. Crown flies off. | squash + poof |
| **Queen** | low | Required target. Tiara flies off. | squash + poof |
| **Knight** | high, ×0.4 damage taken | Required target. Armour clangs, and the helmet pops off at half HP. | squash + poof |
| **Hostage** (realm 2+) | low | Not a target. Hitting one costs points (−750) and shows a sad face, but never fails the level. | gets knocked out comically, with stars circling |

Falling out of the world or into a hazard also counts as elimination.
Every elimination is cartoonish: a vertical squash, a cloud poof, and a
headgear prop that tumbles away as a physics body. There is no blood and
no corpses.

### 3.6 Scoring and medals

* The **shot count** is the main metric. Each level has
  `par = {gold, silver, bronze}`, computed by the validator bot (§6.4) and
  stored in the level file. A designer can pin it with `par_override`.
* Winning with `shots ≤ gold` earns gold, and so on. Winning above bronze par
  still completes the level and unlocks the next, but earns no medal.
* **Points** are secondary and used only for a personal best: blocks
  destroyed (by material value), royals, and knights, minus hostage
  penalties.
* The level is won when every required target is eliminated **and** the scene
  has settled (all bodies asleep, or 2.5 s have passed).

### 3.7 Campaign

Three realms with 12 levels each. Each realm has its own palette, music mood
and a sequence of times of day. A new mechanic or material arrives every
2–4 levels:

| Realm | Setting | Introduces |
|---|---|---|
| **Greenmantle Hills** | rolling meadows, timber and stone keeps | L1 wood · L2 stone · L3 king+queen · L4 scatter-stones · L5 knights · L6 thatch · L8 cloth · L9 iron ball · L12 boss keep |
| **Saffron Reach** | sandstone desert fortress, awnings, glass lanterns | L1 powder keg · L2 glass · L4 hostages · L5 firepot · L7 iron gates · L9 chain shot · L12 boss |
| **Frostfang Peaks** | icy cliffs, iron-bound towers | L1 ice + frost flask · L3 brittle combos · L5 hanging/cantilevered builds · L7 void flask · L9 mixed fortresses · L12 final citadel |

Times of day go from dawn through morning, noon, afternoon, golden hour and
dusk to night (aurora in Frostfang). The level data picks one per level.

### 3.8 Session flow

Title → realm map → level card (grievance, medal pars, best) → play. The
**restart** key or button resets instantly with no confirmation. Pause pauses.
The win card shows the medal stamp, shot count, points and *Next* /
*Retry* / *Map*.

## 4. Art direction: "modern storybook"

**Goal.** Clean, chunky shapes that read instantly on a phone, with
painterly depth. Think of a pop-up book lit by late-afternoon sun.

* **Sky.** A procedural shader with a time-of-day gradient (zenith, horizon,
  ground haze), a sun or moon disc with bloom-like glow, and soft "painted"
  clouds from FBM noise posterised into 3–4 bands with dithered edges, so
  they read as brush strokes. Stars and aurora appear at night.
* **Parallax.** 4–6 layers of procedurally generated silhouettes (far
  mountains, hills, tree lines, mid-ground props), tinted by atmospheric
  perspective toward the horizon colour. Wind sways foliage through a vertex
  shader.
* **Blocks.** Procedurally shaded in one canvas shader per material family:
  wood grain, stone bricks with mortar, glass sheen, ice facets, iron plates
  with rivets, thatch strands, cloth weave. The shader outputs `NORMAL_MAP`
  from a bevel SDF, so 2D lights give real form shading. A **rim light** term
  catches the key light on edges, and **soft shadows** come from
  `LightOccluder2D` with PCF filtering. Cracks are a procedural mask driven by
  damage.
* **Characters** are hand-written SVGs: big heads, round bodies, tiny legs,
  and expressive brows that read at 48 px tall.
* **Palette.** Each realm has a 12-colour palette (ink, paper, three
  foliage/ground tones, sky stops, accent, danger) in
  `game/data/realms/<realm>.json`. Every procedural shader takes its colours
  from the realm palette and the time-of-day grade, so the scene stays
  cohesive.
* **UI.** Clean modern layout with light medieval touches: parchment-toned
  panels with soft shadows, ink-stroke underlines, wax-seal medal stamps.
  Fonts are OFL: a characterful storybook serif for headings and a highly
  legible rounded sans for body text and numbers. Animations are eased
  slides and fades of 150–250 ms. Touch targets are at least 48 dp.

**Drop-in art pipeline.** Each material and character can name optional
texture overrides (`albedo`, `normal`) in its JSON definition. When a texture
exists, the shader samples it instead of the procedural pattern. SVGs live in
`game/art/` and are imported by Godot at the right scale, so an artist can
replace a file and the game picks it up. See `game/art/README.md`.

**Graceful degradation.** The quality preset is chosen automatically by
renderer and adjustable by the player:

| Feature | High (Mobile/Vulkan/Metal) | Low (Compatibility/GL) |
|---|---|---|
| 2D lights + normal maps | yes | yes, 1 light |
| Soft shadows | PCF13 | off (baked contact shadow sprite) |
| Particles | GPU, full count | CPU, ½ count |
| Sky clouds | 5-octave FBM | 3-octave, half-res |
| Parallax layers | 6 | 4 |

## 5. Juice

* **Camera:** an intro flyover (skippable) → aim framing → follow the
  projectile with velocity look-ahead and speed-based zoom-out → impact hold →
  **collapse framing**, which smoothly fits the bounding box of awake bodies →
  ease back to aim. Players can pan and zoom by hand when idle.
* **Slow motion** on big hits (impulse above a threshold, or a royal
  eliminated): time is scaled to 30% for 0.35 s of real time. It is cosmetic
  only and must never change the physics step size (§8.2). **Screen shake**
  uses trauma-based noise. Both have settings and are off in reduced-motion
  mode.
* **Particles:** splinters (wood), sparks (iron), dust puffs (stone, which
  **hang and drift** for several seconds), glitter (glass and ice), straw
  (thatch), embers and smoke (fire), and impact decals (scuffs and dents)
  painted onto blocks.
* **Audio:** layered and procedural. Each impact plays a material *body*
  layer (thud or crunch) plus a *texture* layer (crack, tink or clang)
  chosen by impulse, with random pitch and gain. Big collapses add a low rumble
  bed. All SFX are synthesised by our own script (`tools/sfx/`) into WAVs,
  so they are original and CC BY-SA.

## 6. Content pipeline

### 6.1 Data-driven everything

Levels, realms, ammo, materials and enemies are JSON files with JSON Schemas
(`game/data/schemas/`). Scripts contain behaviour, never content. CI validates
every data file against its schema. At runtime the loader also validates and
reports friendly errors (vital for user-made levels).

### 6.2 Level format

See [LEVEL_FORMAT.md](LEVEL_FORMAT.md). Coordinates are in metres
(1 m = 100 px), with y pointing up in the data and converted at load. A realm
file lists its levels in order, so adding a realm means adding one realm JSON,
one folder of level JSONs, and strings.

### 6.3 Localisation

All UI strings go through `tr()`, with English source strings as msgids
(classic gettext). Catalogues are in `game/locale/*.po`, and the template
`messages.pot` is regenerated by `make pot`. Level names and grievances are
extracted from the data files too. Layouts use containers and never assume
string length.

### 6.4 Validator bot and automatic par

`make validate-levels` runs a headless Godot build at a fixed tick
(`--fixed-fps 60`, which runs faster than real time). For each campaign level
it:

1. **Searches** release phases `p` (coarse-to-fine sweep) × ammo
   (boulder, the ammo first available at that level, and every other
   unlocked type) with a beam search over shot sequences, waiting for the
   scene to settle between shots.
2. **Proves** the best sequence by replaying it from a fresh load and checking
   for a win.
3. **Writes** `par` and the proof `solution` back to the level file:
   `gold` = the fewest shots with any ammo; `silver` = max(gold+1, the fewest
   with first-available ammo); `bronze` = silver+2.

CI replays every stored proof (fast) and fails if any level is no longer
beatable. A full re-search runs when a level's content hash changes.

## 7. Castle editor and sharing

* Place, rotate, scale and delete blocks (any material and shape), enemies,
  hostages and terrain control points. Snap to a 0.25 m grid, plus 15° rotation
  snapping, toggleable. Undo/redo.
* **Test-play** drops you straight into the level, and *Back to editor*
  returns with the editor state intact.
* Saved locally under `user://levels/*.json`. **Share code**: canonical,
  quantised JSON → DEFLATE → base64url, wrapped as `SF1-<payload>-<check>`,
  where the check is 4 bytes of SHA-256. The prefix is versioned so the format
  can evolve. Codes can also be exported and imported as `.json` files.

## 8. Technical choices

### 8.1 Engine

* **Godot 4.7.2-stable**, the latest stable release in Nov 2026 (4.8 is in
  beta), pinned in [`toolchain.lock`](../toolchain.lock) with SHA-512 sums
  copied from the official `SHA512-SUMS.txt`. `scripts/bootstrap.sh` refuses
  any download that doesn't match.
* **GDScript with static typing everywhere.** `untyped_declaration`,
  `inferred_declaration` and `unsafe_*` warnings are raised to errors in
  `project.godot`. No C#.
* The Godot project lives in `game/`, so packaging, scripts and docs stay out
  of the import scan.

### 8.2 Physics

* **Fixed 60 Hz tick** with **physics interpolation** on (the camera runs in
  the physics tick, as interpolation requires), so motion is smooth
  on 90/120/144/165/240 Hz displays and the simulation is identical
  everywhere.
* Slow motion is implemented by **running fewer fixed steps per real second**,
  never by changing the step size, so slow-mo never changes outcomes. A
  unit test checks this.
* Engine choice: **godot-rapier 2D**, after a benchmark against Godot
  Physics 2D (`benchmarks/physics2d/`, results in
  [benchmarks/physics2d.md](benchmarks/physics2d.md)). Godot Physics could
  not hold a 20-box tower or a 300-body castle even when tuned. Rapier held
  both, put them to sleep, and ran about 8× faster. Its solver runs on one
  thread (`physics/rapier/solver/num_threads=1`) for determinism. 1 m =
  100 px matches Rapier's default `length_unit_2d`.
* **Damage needs approach speed, not just impulse:** Rapier reports
  contact impulses (`get_contact_impulse`), but resting contacts carry their
  static load too. A contact only damages when the two bodies were closing
  faster than the material's `impact_speed` at the start of the step.
* Body budget: ~300 dynamic bodies. Small debris below an area threshold
  becomes particles. Settled debris sleeps, then fades out after a while.

### 8.3 Trebuchet: animated rig with analytic release

**Decision:** an **animated (kinematic) rig** whose launch state is computed
analytically, instead of a fully simulated counterweight/arm/sling joint
chain.

* *Determinism:* the release velocity is a pure function of `p`. Same input,
  same shot, on every machine, every frame rate and every physics engine. A
  simulated joint chain depends on solver iterations, warm-starting and tick
  alignment, so it drifts between platforms and engine versions.
* *Feel:* the swing curve can be shaped by hand (a slow wind-up, a fast whip
  and a long readable release window), which matters more for "feels great"
  than physical accuracy. The visuals use the same curve, so what you see is
  what you shoot.
* *Tooling:* the validator bot and the ghost trail evaluate `launch(p)`
  directly, with no need to simulate the rig.
* The curve is physically *plausible*: arm angle θ(p) follows a
  counterweight-driven ease-in; the sling angle φ(p) lags θ with a damped
  whip; launch velocity = analytic d/dt of the sling-tip position. Parameters
  live in `game/data/trebuchet.json`.

### 8.4 Rendering

* **Mobile renderer** (Vulkan on Linux/Windows, Metal on iOS), with
  `rendering_device/fallback_to_opengl3=true`, so machines without Vulkan
  drop to **Compatibility (OpenGL 3.3 / ES 3.0)** automatically. At startup
  the game reads the active renderer and picks the quality preset (§4).
* Target **60 fps on low-end iGPUs and older iPhones**. Physics interpolation
  plus an uncapped/VSync frame rate supports high-refresh displays.
* The screenshot harness renders through **Compatibility on Mesa llvmpipe
  under Xvfb**, so the CI-visible look is the *low* tier. If that looks good,
  high will look better.

### 8.5 Damage and destruction

* Blocks and enemies enable contact monitoring and read impulses in
  `_integrate_forces`. `damage = max(0, impulse − threshold) × material
  sensitivity × ammo multiplier`. Crack stages are shader uniforms.
* **Fracture: runtime Voronoi** (benchmark in
  [benchmarks/fracture.md](benchmarks/fracture.md)). Cells come from our own
  half-plane clipping (about 2× faster than `Geometry2D`), with seeds biased
  toward the impact point and minimum spacing against slivers. Each material
  has its own style: wood **splinters** along its grain (anisotropic metric),
  stone breaks into **chunks**, glass and ice into **shards**, iron **dents**
  into 2–3 heavy pieces, thatch into **tufts**, and cloth **tears** in two.
  Pieces keep the parent's motion and surface pattern (a continued UV
  transform). Splitting costs 70–250 µs against 650–1300 µs for spawning
  the bodies, so pre-broken shards would save little and repeat visibly.
* Fire and frost are per-block status effects driven by the materials data.

### 8.6 Input

Godot InputMap actions (`fire`, `ammo_next`, `ammo_prev`, `pause`,
`restart`, `camera_pan_*`, `zoom_*`, `ui_*`), with defaults for keyboard,
mouse, touch and gamepad. **All are remappable** in Settings and saved with
the config. Tapping anywhere outside HUD buttons fires.

### 8.7 Saves and settings

* **Save:** `user://save.json`, written atomically (temp file + rename) with a
  `.bak` copy. Shape: `{"format": "<slug>-save", "version": N, ...}`.
  `SaveMigrator` upgrades version *k* → *k+1* step by step. Every historical
  version has a fixture and a unit test.
* **Settings:** on Linux, `$XDG_CONFIG_HOME/<slug>/settings.cfg`
  (`~/.config/siegefall/`). Elsewhere, `user://settings.cfg`.
* `application/config/use_custom_user_dir=true` with
  `custom_user_dir_name=<slug>`, so on Linux `user://` is
  `$XDG_DATA_HOME/<slug>` (`~/.local/share/siegefall/`), not Godot's
  generic `godot/app_userdata/...` path.

### 8.8 Platforms

* **Linux (primary):** Wayland-native (`display_server/driver.linuxbsd =
  wayland`, which falls back to X11 automatically), HiDPI with fractional
  scaling (`allow_hidpi`, `canvas_items` stretch with `expand` aspect from a
  1280×720 base). Builds for x86_64 and arm64. Tested on NVIDIA, AMD, Intel
  and Asahi (Honeykrisp Vulkan / OpenGL fallback).
* **Windows:** x86_64 portable zip plus an NSIS installer built on Linux. Godot
  exports are per-monitor-DPI-aware. Gamepads go through Godot's SDL3 input.
* **iOS:** touch-first, safe areas (`DisplayServer.get_display_safe_area()`),
  haptics (`Input.vibrate_handheld`) on big impacts, auto-pause on
  `NOTIFICATION_APPLICATION_PAUSED`. Platform code sits behind
  `OS.has_feature()`. Built by a macOS GitHub Actions job (unsigned
  archive). See `docs/IOS.md`.

### 8.9 Tooling and quality

* `make` wraps everything: `dev`, `run`, `test`, `lint`, `fmt`, `build`,
  `package`, `install`, `screenshots`, `validate-levels`.
* Tests use **GUT 9.7.1** (pinned commit, fetched by bootstrap, never
  exported).
* Lint: **gdtoolkit 4.5** (`gdlint`, `gdformat --check`), **shellcheck
  0.11**, **reuse lint**, JSON Schema validation of all data. Python dev tools
  are pinned in `requirements-dev.txt` and live in `.venv/`.
* The **screenshot harness** (`make screenshots`) renders key scenes to PNG
  with Xvfb + Mesa llvmpipe + Compatibility. Screenshots are reviewed by eye on
  every art change.
* CI runs on every push. Container jobs run bootstrap, install and a headless
  smoke test on Arch, Ubuntu LTS, Debian stable, Fedora, openSUSE Tumbleweed
  and Void. Tagged releases attach all packages, but a release is never
  published without the maintainer's go-ahead.

## 9. Assumptions

Decisions made without asking, which are cheap to revisit:

1. **Name:** *Siegefall* is kept as a working title despite the 2015
   Gameloft game. It is a one-line change (§10).
2. **Godot 4.7.2-stable** is the newest stable. 4.8 is in beta, so we won't
   chase it before release.
3. **Units:** 1 m = 100 px; gravity 9.8 m/s² (980 px/s²); design viewport
   1280×720, expanding to any aspect ratio.
4. **Progress is never gated on medals.** Finishing a level unlocks the next.
   Realms unlock when the previous realm's level 12 is finished.
5. **Hostages** first appear in Saffron Reach (realm 2), as the brief asks
   for "later realms".
6. **Par is bot-computed** (§6.4); designers may pin `par_override`.
7. **Music:** gentle procedural ambient loops per realm are a stretch goal for
   v1.0. SFX are required.
8. **Fonts** are fetched from the official `google/fonts` repository (OFL),
   vendored with their licence, and listed in CREDITS.md.
9. **The castle editor** is available from the main menu from the start.
   Editor ammo is limited to what you have unlocked.
10. **Text-scaling** range is 80%–160%. The UI reflows using containers.
11. **One-button mode:** a single key/tap does fire, release and the mid-air
    action. Holding it while idle opens an ammo wheel that auto-cycles and
    selects on release. Menus get scanning focus.
12. **Points** are shown but don't affect medals.
13. **Score/save data never leaves the device.** Share codes are copied
    to the clipboard by the player, never sent anywhere.
14. **Licences:** code MIT; original assets CC BY-SA 4.0; third-party assets
    keep their own licence (OFL fonts). REUSE-compliant.

## 10. Naming

The name lives only in [`app.env`](../app.env) (`APP_NAME`, `APP_ID`,
`APP_SLUG`). `make sync-identity` propagates it to `project.godot` and all
packaging templates, and CI fails if they drift.

*Siegefall* conflicts with Gameloft's *Siegefall* (2015, iOS/Android/Windows
Phone, a base-building strategy MMO). Candidate replacements (a web search in
Nov 2026 found no game using them, though the Flathub, itch.io, Steam and App
Store sites themselves were blocked from the build environment, so please
double-check before deciding):

* **Rampartfall**: keeps the "-fall" ring.
* **Trebuchet Tantrum**: says exactly what it is, with the petty-king tone.
* **Crowntoppler**: what you do to every royal.
* **Petty Kings**: the premise. (*Petty Kingdoms*, a js13k browser game,
  exists, so this is close but not identical.)

## 11. Decision log

| Date | Decision |
|---|---|
| 2026-11-09 | Godot 4.7.2-stable pinned; project in `game/`; animated trebuchet rig (§8.3); GUT for tests; English-msgid gettext. |
| 2026-11-09 | Physics engine: **godot-rapier 2D v0.36.1** (benchmark: stable tall stacks, sleeps, ~8× faster at 300 bodies). |
| 2026-11-09 | Trebuchet tuned: 2.1 s swing, 22 m/s peak launch. The useful release window spans about 0.3 s, from high lobs to flat shots. Launch speed is decoupled from the animation length. |
| 2026-11-09 | Fracture: **runtime Voronoi** with impact-biased, spaced seeds; 3 fractures per tick, 320-body budget, settled debris retired. |
| 2026-11-09 | Slow motion: `time_scale` and `physics_ticks_per_second` scale together, so the physics step stays 1/60 s. |
