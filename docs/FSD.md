# 土風水競 — Functional Specification Document (FSD)

> Companion to `docs/DESIGN.md` (the build plan). This document is the **authoritative
> requirements + verification spec**: every shippable behavior is a numbered requirement
> (`R#` / `NFR#`), every requirement is verified by at least one numbered test (`T#`), and
> §10 maps the two. Where this FSD and DESIGN.md disagree on *behavior*, this FSD wins; where
> they disagree on *implementation*, DESIGN.md wins. Source citations `(§n)` refer to DESIGN.md.

---

## 1. Overview

**土風水競** (read *do · fū · sui · kyō* — earth–wind–water–compete) is a **2-day, single-player
VR tabletop card game** for **Meta Quest 3**, built **from scratch** in **Godot 4.7 / GDScript**
using the **Godot XR Tools** addon (MIT) for the XR rig and grab/throw. Target event:
**XR VisionDevCamp, Fukuoka 2026**, path **P7 — Godot XR**.

The player stands at a VR table holding a hand of three character cards (Fish / Bird / Dino),
physically **grabs** one and **throws** it into an arena. A robot opponent plays one of its own
cards. The two critters land face-up; the winner **smiles**, the loser **cries**, resolved by
rock-paper-scissors. **First to 3** round wins. The charm plus the physical throw is the whole
pitch.

The core reframe that keeps this small: **a card is a grabbable; the play zone is a target
`Area3D`.** Godot XR Tools solves grab + throw; we add a tiny trigger for "did it land in the
zone." We build a *thin, standard* XR rig and confine all complexity to `GameState.gd` (§3).

---

## 2. References

- `docs/DESIGN.md` — build plan, scene structure, GDScript skeletons, day-by-day plan, risks.
- **Godot XR Tools** addon (MIT) — the XR rig + `XRToolsPickable` grab/throw component, installed
  under `addons/godot-xr-tools/` and used as-is. This project's XR foundation. Ships a runnable
  `scenes/pickable_demo/` (grab/throw/snap) — copy its rig + pickup wiring rather than hand-wire.
- `docs/ASSETS.md` — node/scene/asset manifest: REUSE-vs-AUTHOR split, full scene trees, collision
  layers, sprite import settings, build order.
- Godot Engine 4.7 (GDScript, Autoload singletons, `Area3D` / `RigidBody3D` / `StandardMaterial3D`,
  built-in **OpenXR**).
- Meta Quest 3 / OpenXR — immersive VR runtime; `adb` deploy via our own Meta Quest Android
  export preset (built per XR Tools' deploy docs).
- `_dev_notes/` — distilled Godot reference (getting-started, tutorials, engine details) +
  `00_synthesis_and_decisions.md` (build order, edge cases, findings F1–F4).

---

## 3. Functional Requirements

Priority: **MUST** = ships (DESIGN §1 IN-scope / §12 done) · **SHOULD** = expected within scope ·
**STRETCH** = only if Day-2-PM has slack (DESIGN §9). "SHALL" = mandatory for its priority tier.

### 3.1 Cards & VR interaction

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R1 | The game SHALL present the player a hand of three grabbable character cards in VR, using **Godot XR Tools'** `XRToolsPickable` grab component (on a `RigidBody3D`) **as provided by the addon** — no custom grab logic. | MUST | §1,§3 | T11 |
| R2 | A grabbed card SHALL be throwable using **XR Tools'** release-velocity throw physics, with no re-implementation of grab/throw logic. | MUST | §1,§3 | T11 |
| R3 | A card thrown into the `PlayZone` `Area3D` SHALL be detected on `body_entered` and trigger round resolution **exactly once** per round. | MUST | §1,§7 | T12 |
| R4 | Every card SHALL be exactly one of three types: **WATER** (Fish), **SKY** (Bird), **EARTH** (Dino). | MUST | §2 | T2,T3 |

### 3.2 Card faces (2D sprite swap)

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R5 | Each card's front face SHALL be a 2D sprite shown by swapping the material `albedo_texture` among **exactly four frames** — `neutral`, `blink`, `smile`, `cry`. No skeletal rigging, blend shapes, or 3D facial animation. | MUST | §1,§6 | T13,T14 |
| R6 | At rest, each card SHALL **blink**: swap to the blink frame for ~150 ms at a randomized interval of ~3.0–4.5 s, then return to neutral. | SHOULD | §1,§6 | T14 |
| R7 | On round resolution the winning card SHALL show `smile`, the losing card SHALL show `cry`, and on a draw both SHALL remain neutral/blinking. A card that shows smile/cry SHALL **lock** and stop blinking. | MUST | §2,§6,§7 | T13 |
| R8 | The art set SHALL be exactly **3 critters × 4 frames = 12 sprites**, addressable by a `type → {neutral,blink,smile,cry}` lookup. | MUST | §6 | T20 |

### 3.3 Deck & hand (the one place complexity is allowed — §1)

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R9 | A **single shared deck** SHALL hold the three types, shuffled, with enough copies to outlast a first-to-3 game (default **6 of each = 18**). | MUST | §1,§2,§5 | T1,T2 |
| R10 | Each side (player, robot) SHALL begin a game holding **exactly one of each type**. | MUST | §1,§5 | T2 |
| R11 | A played card SHALL be **consumed** (removed from that hand); after each round both hands SHALL **refill to 3** by drawing from the shared deck. | MUST | §2,§5 | T5 |
| R12 | Hands MAY drift away from one-of-each from round 2 onward as a consequence of draw order — this is **intended** behavior and the core of the game, not a defect. | MUST | §1 | T6 |
| R13 | When the deck is empty, drawing SHALL **rebuild + reshuffle** the deck so it never runs dry mid-game (no crash, always returns a card). | MUST | §2,§5 | T1,T7 |

### 3.4 Robot opponent

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R14 | Each round the robot SHALL select a **random legal card from its OWN hand** and play it. It SHALL NOT read or react to the player's hand. | MUST | §1,§8 | T8 |
| R15 | The robot's chosen card SHALL be **presented in the play area** each round (spawned at `RobotThrowPoint`, then thrown toward or directly placed in the `PlayZone`). Both robot and player cards always land in-zone by design. | MUST | §1,§8 | T15 |

### 3.5 Resolution, scoring & game flow

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R16 | Round outcome SHALL be computed by the RPS rules in §4 and reported as `1` (player wins), `-1` (robot wins), or `0` (draw). | MUST | §2,§5 | T3 |
| R17 | A non-draw round SHALL award **exactly one** point to the winner; a draw SHALL award **no** points. Scores SHALL never change by more than 1 per round. | MUST | §2 | T4 |
| R18 | A score panel SHALL display the current score as **"You N — M Robot"** and update after every round. | MUST | §1,§4,§7 | T16 |
| R19 | The **first** side to reach **3** points SHALL end the game and trigger a win/lose end state showing "YOU WIN!" or "ROBOT WINS". | MUST | §1,§2,§12 | T9,T17 |
| R20 | The end state SHALL offer a **restart** that begins a fresh game: new shuffled deck, scores reset to 0, both hands back to one-of-each. | SHOULD | §2,§7 | T17 |
| R21 | A round SHALL proceed in order: player throws one card → robot plays one card → resolve → award point → consume both played cards → refill hands → if not game-over, begin the next round after a brief reveal pause (~2 s). | MUST | §2,§5,§7 | T18 |
| R22 | While a round is resolving, further `PlayZone` entries SHALL be **ignored** until the next round begins (single resolution per round). | MUST | §7 | T12 |

### 3.6 Architecture constraints

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R23 | All deck / hand / score / resolution logic SHALL live in a single **Autoload singleton `GameState.gd`** of **pure logic with no 3D node dependencies**, so it is runnable headless on desktop. | MUST | §1,§5 | T1 |
| R24 | The XR rig (`XROrigin3D` / `XRCamera3D` / two `XRController3D`) SHALL be a **thin, conventional XR Tools setup**; no game/deck/score logic SHALL live in the rig or its scripts (all such logic lives in `GameState.gd`, R23). | MUST | §3 | T10,T11 |

### 3.7 Stretch (STRETCH — never before Day-2-PM slack)

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R25 | Optional one-shot **win/lose audio sting** via an `AudioStreamPlayer`. | STRETCH | §9 | T21 |
| R26 | Optional **card glow and/or controller haptic** on a win (XR Tools haptics). | STRETCH | §9 | T21 |
| R27 | Optional **robot heuristic**: bias toward the counter to the player's most-played type, still chosen from the robot's own hand (one-line bias over random). | STRETCH | §9 | T22 |
| R28 | Optional **physical draw beat**: player grabs the refill card from `DrawPile` instead of auto-refill visuals. | STRETCH | §9 | T23 |

### 3.8 Room environment & ambiance

> **Priority (revised):** the room *shell* (R29) is SHOULD; the *animated motifs* (R30, R31) are
> **STRETCH / cut-first** — default to a static dark shell, animate only with Day-2-PM slack
> (DESIGN §4.5, §11). T25/T26 apply only if the animation is built.

| ID | Requirement | Pri | Src | Verified |
|----|-------------|-----|-----|----------|
| R29 | The play table SHALL be enclosed by a **circular room** (a cylindrical shell) whose walls **rise above the player's head height**, framing the play space. | SHOULD | §4.5 | T24 |
| R30 | The walls SHALL render three stylized **elemental motifs — Fire, Waves, Wind** — in flat block / SVG-like shapes, each **animated continuously**: Fire flickers, Waves pulse/swell, Wind drifts. Motion SHALL be **constant but subtle (non-distracting)**, keeping the cards the visual focus. | STRETCH | §4.5 | T24,T25 |
| R31 | Wall animation SHALL be **GPU-driven** (shader / `TIME`-based) with **no per-frame GDScript** and no measurable framerate cost (holds NFR6). The walls are **ambiance only** — no game logic and no coupling to the card types (WATER/SKY/EARTH). | STRETCH | §4.5 | T25,T26 |

---

## 4. Game rules (authoritative)

- **Types:** `WATER` (Fish), `SKY` (Bird), `EARTH` (Dino).
- **Beats table** (cyclic, each beats exactly one and loses to exactly one):

  | Card | Beats | Loses to |
  |------|-------|----------|
  | WATER (Fish) | SKY (Bird) | EARTH (Dino) |
  | SKY (Bird) | EARTH (Dino) | WATER (Fish) |
  | EARTH (Dino) | WATER (Fish) | SKY (Bird) |

- **Same type = draw.** No points; both critters stay neutral/blink.
- **Round:** player throws one card; robot plays one card; resolve; award one point to the
  winner (none on a draw); both played cards are consumed (discarded).
- **Refill:** after each round both hands draw back up to 3 from the shared deck.
- **Deck empties:** rebuild (reshuffle) — never run dry mid-game.
- **Win:** first side to **3** round wins; show win/lose end state; offer restart.

> `resolve(p, r)`: `0` if `p == r`; else `1` if `beats[p] == r` else `-1`. This nine-cell truth
> table (§3 combinations of two types) is the single most important correctness surface — T3.

---

## 5. Data model

Authoritative shapes owned by `GameState.gd` (Autoload, pure logic):

```
enum Type { WATER, SKY, EARTH }          # WATER=Fish, SKY=Bird, EARTH=Dino

deck:          Array[Type]               # shared, shuffled; rebuilt on empty
player_hand:   Array[Type]               # size 3 between rounds
robot_hand:    Array[Type]               # size 3 between rounds
player_score:  int                       # 0..3
robot_score:   int                       # 0..3
TYPE_NAMES:    { Type -> String }        # Fish / Bird / Dino  (display + sprite lookup key)
```

`play_round(player_card: Type) -> Dictionary` (the only call the VR layer needs):

```
{
  "player_card":  Type,    # what the player threw
  "robot_card":   Type,    # what the robot played (random-legal from its hand)
  "outcome":      int,     # 1 player / -1 robot / 0 draw
  "player_score": int,     # post-round
  "robot_score":  int,     # post-round
  "game_over":    bool,    # true once a side reaches 3
}
```

Invariants (all enforced by T1): scores monotonic, step ≤ 1; hands size == 3 between rounds
(unless game over); `deck` never empty when `draw_one()` returns; `game_over` true **iff** a
score == 3.

### 5.1 Godot 4 implementation notes

- **RNG / test determinism.** `Array.shuffle()` / `randi()` use Godot's global RNG. Seed it
  (`seed(<fixed>)`) at the start of the headless test (T1) for reproducibility; leave the shipped
  game default-seeded so each match differs. Determinism is a *test* concern, not a gameplay one.
- **Sprite lookup (optional `.tres`).** R8's `type → {neutral,blink,smile,cry}` set fits a small
  `CardData extends Resource` (four `@export Texture2D`), saved as three `.tres` files assigned in
  the inspector — keeps art out of code. Equivalent to DESIGN §6's per-card `@export` fields;
  either satisfies R5/R8. Per-card runtime state (`_locked`, current frame, blink timer) lives on
  the node (`CardFace.gd`), not the resource, so the shared resource is read-only — no duplication.
- **Deck/hand = Godot `Array` built-ins.** Deck is `Array[Type]` (pure data); `shuffle`/`append`/
  `erase`/`size`/`pop_back`/`randi()` cover every operation. No card framework (§11).
- **Tuning knobs as `@export`, not literals.** Expose physical/timing constants for on-site
  calibration: robot throw impulse (DESIGN §8), reveal pause (~2.0 s, R21), blink interval
  (3.0–4.5 s, R6). A flat collider on a real headset needs the throw magnitude tuned by hand.

---

## 6. UI / UX spec

Defers visual/interaction *implementation* to DESIGN §4/§6/§7; this section is the behavioral spec.

### 6.1 Aesthetic
- **Faces:** 2D sprite-swap only — cute, front-facing critters; 12 frames sharing identical
  crop/size/framing (R8, NFR7). Consistency over polish.
- **Table & rig:** our own — a simple table mesh + the standard XR Tools rig; keep the rig
  conventional, no game logic in it (R24).
- **Room:** a circular shell of stylized elemental walls — **Fire / Waves / Wind** in block/SVG
  shapes, rising above head height, with constant-but-subtle motion (fire flickers, waves pulse,
  wind drifts) that frames without distracting; kept dim/low-contrast so cards stay the focus
  (R29–R31). Ambiance only — decorative, not the card types.

### 6.2 Scene-level UI elements (DESIGN §4)
- **PlayerHandAnchors** — three slots where the player's cards rest, grabbable (R1).
- **RobotHandAnchors** — robot's three slots, cards face away. Render a generic **card-back**
  texture here (a Card may carry a back image, à la a front/back face pattern); only the card the
  robot *plays* flips to show its critter face (R15). Concealing the robot's hand is what makes
  its draw drift feel fair. *Optional polish — informational, not required for the demo.*
- **DrawPile** — where refills appear; physical grab is STRETCH (R28), else auto-refill visual.
- **PlayZone (`Area3D`)** — generous, low, table-sized box; detects any landed card (R3, R22).
- **RobotThrowPoint** — spawn/aim origin for the robot's card (R15).
- **ScorePanel** (`Label3D` or XR Tools 2D UI) — shows **"You N — M Robot"** (R18); switches to
  **"YOU WIN!" / "ROBOT WINS"** on game over (R19), with a restart affordance (R20).
- **Environment / RoomShell** — the circular room enclosing the table; three GPU-animated
  elemental wall bands (Fire / Waves / Wind), ambiance only, no game logic (R29–R31).

### 6.3 Interaction flow (one round)
1. Player grabs a card from a hand slot (R1) and throws it (R2).
2. Card enters `PlayZone` → exactly one resolution fires (R3, R22).
3. Robot's card is presented in the play area (R15).
4. Faces update: winner smiles, loser cries, draw = both neutral (R7).
5. Score panel updates (R18).
6. ~2 s reveal pause, then next round — or end state if a side hit 3 (R19, R21).

---

## 7. Non-functional requirements

| ID | Requirement | Src |
|----|-------------|-----|
| NFR1 | The build SHALL run on **Meta Quest 3** from **our own Meta Quest Android export preset** (Runnable), built per XR Tools' deploy docs. | §3,§12 |
| NFR2 | The experience SHALL be **immersive VR** — no mixed-reality passthrough or surface anchoring. | §1 |
| NFR3 | **Single-player only** — no networking or multiplayer. | §1 |
| NFR4 | Built **from scratch** on **Godot 4.7 + GDScript** with the **Godot XR Tools** addon (installed under `addons/`) + built-in OpenXR. No template fork. | §3 |
| NFR5 | Cards **always fly true and land in-zone** by design; **no miss-handling** path is required or built. | §1 |
| NFR6 | Maintain a **comfortable VR framerate** on Quest 3 across a full game with no nausea-inducing hitches; avoid per-frame allocations in hot paths. | §11 |
| NFR7 | All **12 sprite frames** SHALL share identical crop, size, and framing (no jumpy faces). | §6,§11 |
| NFR8 | **Complexity is confined to `GameState.gd`**; every other script takes the simplest path. | §1 |

---

## 8. Out of scope (do NOT build — DESIGN §1)

Multiplayer / networking · 3D facial rigging / blend shapes / skeletal animation · mixed-reality
passthrough / anchoring · separate decks per player · smart AI that reads the player's hand ·
menus / settings / best-of-N config / tutorials / onboarding · more than 3 character types or any
deckbuilding meta · **miss handling** · sound beyond one optional win/lose sting.

---

## 9. Test plan

Format: `T# | Test | Procedure → Expected | Verifies`. Tests T1–T9 are **headless desktop**
(run before any VR — DESIGN §5); T10–T20 and **T24** (room shell, R29) are **on-device** (Quest 3);
**T21–T23 and T25–T26 cover stretch** (T25/T26 only if the wall animation R30/R31 is built).

| ID | Test | Procedure → Expected | Verifies |
|----|------|----------------------|----------|
| T1 | Headless logic self-test | Run the §5 self-test loop on desktop. → Scores only ever step by 1; hands always refill to 3; deck never errors when emptied; game ends exactly when a side hits 3. | R9,R11,R13,R17,R19,R23 |
| T2 | New-game start state | `new_game()`. → Both hands = exactly one of each type; scores 0; deck non-empty (18 default). | R4,R9,R10 |
| T3 | Resolution truth table | Call `resolve()` for all 9 `(p,r)` pairs. → Correct `1`/`-1`/`0` for every cell per §4. | R4,R16 |
| T4 | Scoring | Force a player-win, a robot-win, a draw. → Winner +1, draw +0; no step > 1. | R17 |
| T5 | Refill | After `play_round`. → Both hands size == 3 (unless game over). | R11 |
| T6 | Hand drift | Play several rounds. → A hand may hold duplicates or be missing a type (drift occurs, no error). | R12 |
| T7 | Deck exhaustion | Drain the deck via many `draw_one()` calls. → Deck rebuilds, never returns empty, no crash. | R13 |
| T8 | Robot legality | Call `robot_pick()` repeatedly. → Returned card was in `robot_hand` and is removed; never reads player hand. | R14 |
| T9 | Game-over boundary | Drive a score to 3. → `game_over` true exactly at 3, false at 2; ends immediately. | R19 |
| T10 | Toolchain (bring-up) | Deploy a **minimal XR bring-up build** (XR Tools rig + one grabbable test cube, no game code) to Quest 3 from our Meta Quest preset. → Rig renders in-headset, the cube is grabbable, `adb devices` lists the Quest. | NFR1,NFR4,R24 |
| T11 | Grab & throw | In headset, grab a card and throw it. → Uses XR Tools grab/throw; card releases and flies. | R1,R2,R24 |
| T12 | Play-zone single fire | Throw a card into `PlayZone`; throw a second mid-resolution. → Exactly one resolution per round; extra entries ignored. | R3,R22 |
| T13 | Faces on resolve | Win, lose, and draw a round. → Winner smiles, loser cries, draw neutral; emoting card stops blinking. | R5,R7 |
| T14 | Blink at rest | Observe an idle card. → Blinks ~every 3.0–4.5 s for ~150 ms, returns to neutral. | R5,R6 |
| T15 | Robot card presented | Play a round. → Robot's card appears in the play area and lands in-zone. | R15 |
| T16 | Score panel | Play rounds. → Panel reads "You N — M Robot" and updates each round. | R18 |
| T17 | End + restart | Reach 3. → "YOU WIN!" / "ROBOT WINS" shown; restart yields a fresh game (deck/score/hands reset). | R19,R20 |
| T18 | Full round flow | Play a complete first-to-3 game in-headset. → Order & ~2 s reveal pacing per R21; no stuck rounds. | R21 |
| T19 | Performance | Play a full game on Quest 3. → Comfortable framerate sustained; no nausea-inducing hitches. | NFR6 |
| T20 | Sprite consistency | View all 12 frames side by side. → Identical crop/size/framing; faces don't jump. | R8,NFR7 |
| T21 | Stretch — juice | If built: a win triggers the audio sting and/or glow/haptic once. | R25,R26 |
| T22 | Stretch — heuristic | If built: robot biases toward the counter to the player's most-played type, still from its own hand. | R27 |
| T23 | Stretch — draw beat | If built: player can grab a refill card from `DrawPile`. | R28 |
| T24 | Room & walls present | In headset, look around. → A circular room encloses the table; walls rise above head height; three elemental motifs (Fire/Waves/Wind) are visible. | R29,R30 |
| T25 | Wall animation | Observe the walls during play. → Fire flickers, waves pulse, wind drifts; motion is continuous yet subtle — doesn't pull focus from the cards. | R30,R31 |
| T26 | Ambiance performance | Play a full game with walls active. → Comfortable framerate sustained; animated walls add no measurable hitch (GPU-only). | R31,NFR6 |

Tests **T1–T9** live as assert checks in `tests/test_game_state.gd`, run headless
(`godot --headless --script ...`); see DESIGN §5 "Tests folder". GUT is optional, not required.

**Pass gate (demo-ready):** T1–T9 green on desktop **before** VR wiring; T10 green **before**
any custom code on device; T11–T20 green for the Definition of Done (DESIGN §12). Stretch tests
only apply to features actually built.

---

## 10. Traceability matrix (requirement → tests)

| Req | Tests | Req | Tests | Req | Tests |
|-----|-------|-----|-------|-----|-------|
| R1 | T11 | R11 | T5 | R21 | T18 |
| R2 | T11 | R12 | T6 | R22 | T12 |
| R3 | T12 | R13 | T1,T7 | R23 | T1 |
| R4 | T2,T3 | R14 | T8 | R24 | T10,T11 |
| R5 | T13,T14 | R15 | T15 | R25 | T21 |
| R6 | T14 | R16 | T3 | R26 | T21 |
| R7 | T13 | R17 | T1,T4 | R27 | T22 |
| R8 | T20 | R18 | T16 | R28 | T23 |
| R9 | T1,T2 | R19 | T1,T9,T17 | NFR1 | T10 |
| R10 | T2 | R20 | T17 | NFR4 | T10 |
| R29 | T24 | R30 | T24,T25 | R31 | T25,T26 |

*(NFR6 → T19,T26; NFR7 → T20. NFR2/NFR3/NFR5/NFR8 are design constraints, satisfied by construction
and confirmed at review rather than a discrete test.)*

Every MUST/SHOULD requirement above maps to ≥1 test; every non-stretch test maps to ≥1 requirement.

---

## 11. Decisions & open items

**Decided**

- **From-scratch XR, no template fork.** Our own Godot 4.7 project + **Godot XR Tools** addon for
  the rig + `XRToolsPickable`; we build the Quest export ourselves (DESIGN §3). The addon ships the
  full rig + a runnable `pickable_demo` to copy — "from scratch" ≠ from zero (`docs/ASSETS.md` §1).
- **Card is one node.** `Card.tscn`'s root **extends `XRToolsPickable`** (a `RigidBody3D`) and
  carries `CardFace.gd`, so the same node is grabbable *and* owns its face, and `PlayZone` reads
  `card_type`/`show_smile()` off the entering body (DESIGN §4, §6). Not two scripts on two nodes.
- **`GameRoot.gd` presenter** spawns/clears the player's hand cards from `GameState.player_hand` —
  the one logic→scene bridge (initial deal + post-round refill; DESIGN §4, §7, §10).
- **Restart (R20)** = a grabbable "play again" card thrown into `PlayZone` → `GameState.new_game()`;
  `GameRoot` respawns hands (a reveal-timer auto-restart is the fallback).
- **No third-party card framework.** `chun92/card-framework` (MIT) and `db0/godot-card-game-framework`
  (AGPL) are both 2D `Control` / mouse-drag systems that don't fit a `RigidBody3D` + `XRToolsPickable`
  VR table; their data ops map 1:1 to Godot `Array` built-ins, and we have zero per-card abilities.
  Deck/hand stays hand-rolled in `GameState.gd` (~8 lines); faces are a 4-frame swap (R5) + optional `.tres`.

**Open / verify in editor**

- **Robot card: physics throw vs direct placement** — decide Day-2-AM from how the player throw
  tunes; either satisfies R15 (T15 passes for both).
- **Physical draw beat vs auto-refill** — STRETCH R28; default is auto-refill.
- **`XRToolsPickable` API** — confirm actual props/signals against the installed XR Tools version;
  confirm OpenXR + Meta vendor bring-up in-headset and flat-card `continuous_cd` behavior (DESIGN §3, §7).
