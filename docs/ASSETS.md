# 土風水競 — Asset & Scene Manifest (ASSETS.md)

> The build manifest companion to `docs/DESIGN.md` (plan) and `docs/FSD.md` (requirements).
> This lists **every node, scene, script, and art asset** the game needs, split into
> **REUSE** (ships with the Godot XR Tools addon — do not build) and **AUTHOR** (we make it).
> Requirement tags `(R#)` refer to FSD; `(§n)` to DESIGN. Verified against XR Tools `master`
> source on 2026-06-27 (see §8).
>
> **The lazy headline:** "from scratch" does **not** mean from zero. The addon hands us the
> entire XR rig, the grab/throw, hands, snap zones, and a runnable grab demo. We author ~4
> scenes and ~5 scripts; everything else is REUSE. Build the rig by copying addon scenes, not
> by wiring `XROrigin3D` by hand.

---

## 0. Status legend

| Mark | Meaning |
|---|---|
| ✅ DONE | Exists and verified (logic + tests) |
| 🟡 STUB | File exists, parses, wired in-headset later |
| ⬜ TODO | Not created yet |
| ♻️ REUSE | Provided by `addons/godot-xr-tools/` — instance it, don't write it |
| ✂️ CUT-FIRST | Ambiance only; first to drop if Day 2 is tight (R29–R31) |

---

## 1. REUSE — comes with Godot XR Tools (do NOT build these)

Install the addon under `addons/godot-xr-tools/`, enable the plugin, enable OpenXR. Then these
are available to instance. This is the bulk of the "XR from scratch" work — already written.

| Component | Addon path | Used for |
|---|---|---|
| ♻️ StartXR | `xr/start_xr.tscn` / `start_xr.gd` | OpenXR init, vsync-off, refresh-rate match, foveation. Put at the rig root (replaces the hand-rolled start script in `_dev_notes/godot_tutorials.md §1.2`). |
| ♻️ Function Pickup | `functions/function_pickup.tscn` | The grabber. **One per controller.** Tracks hand velocity → injects throw velocity on release (R1, R2). |
| ♻️ Pickable (base class) | `objects/pickable.gd` (`XRToolsPickable`, extends `RigidBody3D`) | **Base script of `Card.tscn`'s root** (see §4.2). Grab + throw physics. |
| ♻️ Grab points | `objects/grab_points/grab_point_hand_left.tscn` / `_right.tscn` / `grab_point.gd` | Optional: define where/how the hand snaps to the card. YAGNI for a flat card — add only if grab pose looks wrong. |
| ♻️ Snap Zone | `objects/snap_zone.tscn` / `snap_zone.gd` | Optional: hand-slot snapping (R1 "rest in slots"). Cheaper alt = plain `Position3D` anchors (§4.4). |
| ♻️ Hands | `hands/` (low-poly hand scenes + pose animations) | Optional visible hands. Quest: use low-poly. Stretch polish; controllers alone work. |
| ♻️ Player body | `player/player_body.tscn` | NOT needed — player stands still at a table, no locomotion (NFR2). Skip. |
| ♻️ Staging | `staging/staging.tscn` + `scene_base.tscn` | NOT needed — single level, no scene switching. **Skip (YAGNI).** Use one `main.tscn`. |

### Reference to borrow wiring from (the example project)
The addon ships a **runnable grab/throw demo** — copy its rig + pickup setup instead of guessing:

- `scenes/pickable_demo/pickable_demo.tscn` — full grab/throw/snap scene.
- `scenes/pickable_demo/objects/grab_cube.tscn` + `grab_cube.gd` — minimal pickable (the T10
  bring-up "grab cube" is literally this).
- `scenes/pickable_demo/objects/saucer.tscn` — **a thrown flat disc**: closest analog to a thrown
  card; copy its mass / collision / CCD tuning as the starting point for `Card.tscn`.
- `scenes/pickable_demo/objects/snap_tray.tscn` / `belt_snap_zone.tscn` — snap-zone hand slots.

> Borrowing the demo's rig is **using the addon as intended**, not "forking a template." It
> collapses most of DESIGN §11's top risk (toolchain) into copy-paste.

---

## 2. Autoloads (Project Settings → Autoload)

| Node name | Script | Status | Notes |
|---|---|---|---|
| `GameState` | `res://GameState.gd` | ✅ DONE | Pure-logic brain (R23). Tests T1–T9 green. The only place complexity lives (NFR8). |

No other autoload. A "GameRoot presenter" (§3) is a scene node, **not** an autoload — it touches
scene geometry, so per best-practice (`_dev_notes/godot_tutorials.md §5.2`) it stays a node.

---

## 3. Scripts inventory

| Script | Attaches to | Status | Change needed |
|---|---|---|---|
| `GameState.gd` | Autoload | ✅ DONE | — |
| `tests/test_game_state.gd` | headless `SceneTree` | ✅ DONE | — |
| `game/CardFace.gd` | `Card.tscn` root | ✅ WIRED | Now `extends pickable.gd` with `super()` in `_ready()`. Verify in-headset (T11/T13/T14). |
| `game/PlayZone.gd` | `PlayZone` (Area3D) | ✅ WIRED | Calls GameRoot to clear/re-deal between rounds; auto-restart on game over. |
| `game/RobotPlayer.gd` | `RobotPlayer` (Node3D) | ✅ WIRED | Delegates card creation to `GameRoot.make_card()`; keeps only throw vs place. |
| `game/GameRoot.gd` | `GameRoot` (Node3D) | ✅ DONE | The logic→scene bridge **and** the single Card factory (12 frames assigned here once, used by player deal + robot). Spawns/clears hands; `clear_table()` frees the `card` group each round. |

> **Why GameRoot.gd is needed:** `GameState` is headless and holds only `Array[Type]`. Something
> must turn `player_hand = [WATER, SKY, EARTH]` into three grabbable `Card.tscn` at the slots, and
> remove a card once thrown/consumed. That bridge is currently unwritten. It is the only
> logic→scene gap in the plan.

---

## 4. AUTHOR — scenes we build

### 4.1 `main.tscn` — the one scene (root)

```
Main (Node3D)                                   # main scene; set run/main_scene
│
├── XROrigin3D                                  # ♻️ build from addon; holds StartXR
│   ├── (StartXR)                               # ♻️ start_xr.gd attached here (OpenXR boot)
│   ├── XRCamera3D                              # the HMD camera
│   ├── LeftHand (XRController3D, tracker=left_hand)
│   │   └── FunctionPickup                      # ♻️ function_pickup.tscn — grabber (R1/R2)
│   │   └── (Hand)                              # ♻️ optional low-poly hand model
│   └── RightHand (XRController3D, tracker=right_hand)
│       └── FunctionPickup                      # ♻️ function_pickup.tscn — grabber
│       └── (Hand)                              # ♻️ optional
│
├── Table (StaticBody3D)                        # our mesh; box/plane + collider (R6.1)
│   ├── MeshInstance3D                          # simple box/plane
│   └── CollisionShape3D (BoxShape3D)           # thick — also a card-landing backstop (F3/E9)
│
├── GameRoot (Node3D)  ← GameRoot.gd            # ⬜ presenter: spawns player hand, clears cards
│   ├── PlayerHandAnchors (Node3D)              # 3 rest slots, grabbable cards spawned here (R1)
│   │   ├── Slot0 (Marker3D)
│   │   ├── Slot1 (Marker3D)
│   │   └── Slot2 (Marker3D)
│   ├── RobotHandAnchors (Node3D)               # OPTIONAL — only if rendering card-backs (R6.2).
│   │   ├── Slot0/1/2 (Marker3D)                #   Cut if not showing the robot's hand. (YAGNI)
│   ├── DrawPile (Marker3D)                     # OPTIONAL — STRETCH R28 physical draw. Default: skip.
│   ├── PlayZone (Area3D)  ← PlayZone.gd        # detects landed cards (R3, R22)
│   │   └── CollisionShape3D (BoxShape3D)       # GENEROUS + THICK, not paper-thin (F3/E9)
│   ├── RobotThrowPoint (Marker3D)              # spawn/aim origin for robot card (R15)
│   ├── RobotPlayer (Node3D)  ← RobotPlayer.gd  # spawns + throws the robot's card (R15)
│   └── ScorePanel (Label3D)                    # "You N — M Robot" / end state (R18–R20)
│
└── Environment (Node3D)                        # ✂️ CUT-FIRST ambiance (R29–R31)
    ├── WorldEnvironment                        # dark, low-contrast so cards stay the focus
    ├── DirectionalLight3D                      # (faces are UNSHADED, so lighting is minimal)
    └── RoomShell (MeshInstance3D)              # ✂️ inverted cylinder + Fire/Waves/Wind shader
```

Node-path contract (already encoded in the stubs — keep these sibling relationships):
- `PlayZone.gd` reads `$"../ScorePanel"` and `$"../RobotPlayer"` → both siblings under `GameRoot`.
- `RobotPlayer.gd` reads `$"../RobotThrowPoint"` and `$"../PlayZone"` → both siblings under `GameRoot`.

> `Marker3D` (not `Position3D`) is the Godot 4 name for a transform-only anchor — use it for
> slots / throw point / draw pile.

### 4.2 `game/Card.tscn` — one per physical card (instanced)

```
Card  ← game/CardFace.gd  (extends XRToolsPickable, i.e. a RigidBody3D)   # grab+throw+face (R1,R5)
├── CollisionShape3D (BoxShape3D — thin, card-shaped; continuous_cd = true on the body) # F3/E9
└── MeshInstance3D (QuadMesh, faces +Z)                                   # the card face
    └── surface-override material (StandardMaterial3D, unique per instance)  # F2/E11
        • shading_mode = UNSHADED                                         # crisp 2D-in-3D (§3.1)
        • transparency = ALPHA_SCISSOR (if faces have alpha) else DISABLED
        • texture_filter = Nearest (pixel) / Linear (smooth) — consistent across all 12 (NFR7)
        • albedo_texture = current frame (hot-swapped at runtime)
```

Key build facts (from §8 verification + dev notes):
- **Root = `XRToolsPickable`.** `CardFace.gd` must `extends` the addon's `pickable.gd` (a
  `RigidBody3D` subclass). One node can't carry two `RigidBody3D` scripts — this is why CardFace
  lives on the pickable root, and why PlayZone can read `body.card_type` / `body.show_smile()`
  off the body that enters the Area3D.
- **`release_mode = UNFROZEN`** on the pickable so the throw actually flies (§8).
- **Per-instance material**: tick `resource_local_to_scene = true` on the material in `Card.tscn`,
  or duplicate in `_ensure_unique_material()` (CardFace already does the code fallback). Without
  it, one face swap changes every card (F2/E11).
- **Collision layers** (§6): card's *dropped* layer in `collision_layer`; while held, the pickable
  swaps to layer 17 + mask 0. The PlayZone's mask must target the *dropped* layer, not the held
  one (gotcha from §8).

### 4.3 `ScorePanel` — `Label3D` (no own scene needed)

A plain `Label3D` node under `GameRoot`. `PlayZone.gd` already drives `.text`. No viewport-based
2D UI (YAGNI vs XR Tools 2D-in-3D panel). Billboard OFF in VR (swimmy in stereo, §3.1).

### 4.4 Hand slots — `Marker3D` anchors, not snap zones (default)

Default: three `Marker3D` under `PlayerHandAnchors`; `GameRoot.gd` parents a spawned `Card.tscn`
at each. **Skip XR Tools `snap_zone.tscn`** unless cards need to magnetically return to slots —
that's polish (R1 is satisfied by "cards rest at slots, grabbable"). Add snap zones only if the
plain anchors feel loose in-headset.

---

## 5. Art assets

| Asset | Count | Spec | For |
|---|---|---|---|
| Character face frames | **12** (3 critters × 4) | identical crop/size/framing; square; PNG/WebP RGBA | R5, R8, NFR7, T20 |
| — Fish (WATER) | 4 | neutral · blink · smile · cry | |
| — Bird (SKY) | 4 | neutral · blink · smile · cry | |
| — Dino (EARTH) | 4 | neutral · blink · smile · cry | |
| (optional) Card-back texture | 1 | generic back; only if rendering RobotHandAnchors (R6.2) | ✂️ optional |
| (optional) Table texture | 1 | simple; or flat color | optional |

**Import settings for the 12 frames** (F4/E15 — get this right or faces blur/halo on device):
- Compress Mode = **Lossless** (pixel art / crisp), **not** VRAM.
- **Detect 3D > Compress To = Disabled** (stops auto VRAM-compress on first 3D use).
- Mipmaps **off** (cards are near-camera, fixed size).
- Same settings on all 12 (NFR7).

**Lookup (R8):** `type → {neutral, blink, smile, cry}`. Two equivalent options (DESIGN §6 / FSD §5.1):
- (a) Per-card `@export var tex_*` on `CardFace.gd` (current stub) — assign in inspector.
- (b) `CardData extends Resource` with 4 `@export Texture2D`, saved as **3 `.tres`**
  (`fish.tres` / `bird.tres` / `dino.tres`). Cleaner; keeps art out of code. `RobotPlayer.gd`
  already groups frames per type as `Array[Texture2D]` — either feeds it.

> Generate the 12 sprites with an image tool (on-ethos for the event). `environment.yml` ships
> Python + Pillow for the one scripted task: normalizing all 12 to an identical crop/size.

---

## 6. Project settings (non-scene config)

| Setting | Value | Why |
|---|---|---|
| `[autoload] GameState` | `*res://GameState.gd` | ✅ set |
| `[physics] common/physics_ticks_per_second` | 90 (match HMD refresh) | ✅ set; anti-tunnel (F3) |
| `[xr] openxr/enabled` | `true` | ✅ set |
| `[xr] shaders/enabled` | `true` | ✅ set |
| `xr/openxr/reference_space` | **Local Floor** | ⬜ set via dropdown in editor (enum not hard-coded) |
| `xr/openxr/foveation_level` | High | ✅ set (=3) + dynamic; tune on device (NFR6) |
| `xr/openxr/extensions/hand_tracking` | **off** | ⬜ confirm off in editor; controller-only game |
| `[editor_plugins] enabled` | + `godot-xr-tools/plugin.cfg` | ✅ set (addon vendored) |
| `rendering/renderer/rendering_method` | mobile (Quest) | ✅ set; re-test vs Compatibility on-device |
| `run/main_scene` | `res://main.tscn` | ✅ set |
| Layer names (3D physics) | name layers: `card`, `play_zone`, `table` | mask config (§4.2 gotcha) |

**Collision layer/mask plan** (the held-layer trap, §8):
- `Card` (dropped): layer = `card`. PlayZone: mask includes `card`. Table: layer `table`.
- XR Tools swaps a held card to layer 17 / mask 0 automatically — PlayZone won't fire on a held
  card, only on a thrown (dropped) one. That's the behavior we want (R3, R22).

**Export preset (NFR1, ⬜):** Android + Gradle build + XR Mode OpenXR + Meta XR features, named
"Meta Quest", Runnable. Needs: Android Build Template installed, OpenXR vendor (Meta) plugin,
JDK 17 + Android SDK. Build the minimal bring-up APK (rig + grab cube) **first** (T10) before any
game code.

---

## 7. Build/borrow order (smallest path to each gate)

1. ✅ **Brain** — `GameState.gd` + tests (DONE, T1–T9 green).
2. 🟡 **Toolchain** — addon vendored + OpenXR/plugin enabled in `project.godot`; `bringup.tscn`
   (rig + grab cube, no game code) ready to deploy for T10. ⬜ Export preset + adb on the day.
3. ✅ **Card.tscn** — authored (pickable root, thin box + CCD, per-instance material). Tune
   mass/collider feel in-headset (T11). `CardFace.gd` flipped to `extends pickable.gd`.
4. 🟡 **Faces** — `CardFace` + GameRoot frame wiring done; ⬜ user supplies 12 PNGs + F4 import
   settings, then assign to `GameRoot.frames_*` (T13, T14, T20).
5. ✅ **PlayZone + GameRoot.gd** — Area3D fires → `GameState.play_round()`; GameRoot spawns/clears
   the player hand; smile/cry swap; round flow wired (T12, T13). Verify in-headset.
6. ✅ **RobotPlayer** — presents robot card via the GameRoot factory; ScorePanel + reveal pause +
   first-to-3 + auto-restart wired. Tune throw on the day (T15–T18), then **stop adding features**.
7. ✂️ **RoomShell** — only with Day-2-PM slack (R29–R31, T24–T26). Cut first if framerate dips.

> New scenes this pass: `game/xr_rig.tscn` (thin rig, instanced by both below), `bringup.tscn`
> (T10), `main.tscn` (the game). All **hand-authored as text** — open in Godot 4.7 once to
> validate (UIDs + ExtResource links). See `_dev_notes/01_vr_layer_buildout.md` for the full
> in-editor verify list + the in-headset bring-up checklist.

---

## 8. Verification log (what was confirmed, 2026-06-27)

Confirmed against `GodotVR/godot-xr-tools@master` source (DeepWiki renders client-side and only
returned a loading shell via fetch, so verified against the authoritative addon source it indexes):

- **`XRToolsPickable extends RigidBody3D`** ✅ — so `Card.tscn` root is both grabbable and a body
  that triggers the Area3D.
- **Signals** ✅ `picked_up(pickable)`, `dropped(pickable)`, `grabbed(pickable, by)`,
  `released(pickable, by)`, `action_pressed/released`, `highlight_updated`.
- **Exports** ✅ `enabled`, `press_to_hold`, `picked_up_layer` (`@export_flags_3d_physics`),
  `release_mode: ReleaseMode {ORIGINAL=-1, UNFROZEN=0, FROZEN=1}`,
  `ranged_grab_method: {NONE, SNAP, LERP}`, `second_hand_grab: {IGNORE, SWAP, SECOND}`.
- **Throw velocity** ✅ — `let_go()` sets `linear_velocity = p_linear_velocity` /
  `angular_velocity = p_angular_velocity` and restores `freeze`; the velocity values come from the
  controller's `FunctionPickup`. Use `release_mode = UNFROZEN`. Don't set velocity yourself.
- **Components present** ✅ `functions/function_pickup.tscn`, `objects/snap_zone.tscn`,
  `objects/grab_points/grab_point_*.tscn`, `xr/start_xr.tscn`, `staging/staging.tscn`,
  `player/player_body.tscn`, `hands/`.
- **Example project** ✅ `scenes/pickable_demo/` with `grab_cube`, `grab_ball`, **`saucer`**
  (thrown flat disc ≈ thrown card), `snap_tray`, `belt_snap_zone` — the reference to copy.
- **Godot core** (Area3D `body_entered`, RigidBody3D `apply_central_impulse` / `continuous_cd`,
  StandardMaterial3D `albedo_texture` swap, `Timer`) — standard 4.x API, already documented in
  `_dev_notes/godot_tutorials.md` §2–§4; no surprises.

> **Re-verify in-editor against the *installed* XR Tools version** (the addon's API drifts across
> Godot minors): exact `function_pickup` export names, `release_mode` behavior for a flat card,
> and the Meta OpenXR vendor bring-up rendering in-headset (FSD §11, DESIGN §3).
</content>
