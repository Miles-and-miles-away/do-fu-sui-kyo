# Godot Tutorials — Project Reference for 土風水競 (do-fu-sui-kyo)

Curated notes from the Godot **stable** (4.x) docs, filtered to what this single-player VR
tabletop card game on Meta Quest 3 actually needs (Godot 4.7, GDScript, IoTone/BowleraramaXR-Godot
template, Godot XR Tools + OpenXR). Aggressively YAGNI: 2D/GUI/networking/navigation/shaders/
animation/particles/audio/C# are intentionally omitted.

**Sourcing note:** the docs HTML renders mostly as nav boilerplate via fetch tools, so most facts
below were pulled from the canonical `.rst` sources in `godotengine/godot-docs@stable` (identical
text to docs.godotengine.org). XR Tools API facts come from the actual addon source
(`GodotVR/godot-xr-tools@master`). Version caveats are flagged with **[v?]**.

---

## 0. Version-sensitivity cheat-sheet (read first)

These are the spots most likely to bite when "stable" docs meet Godot 4.7 / current XR Tools:

- **[v?] OpenXR signal names** in the "better start script" (`session_begun` / `session_visible`
  / `session_focussed` / `session_stopping` / `pose_recentered`). Verify exact names on
  `OpenXRInterface` in 4.7 (autocomplete or Editor > Help) before wiring — single most likely
  copy-paste breakage.
- **[v?] Godot XR Tools is a separately-versioned community addon.** Pin the XR Tools release that
  lists your Godot 4.x in its notes; mismatches throw "failed to load script" / import errors.
  The template (BowleraramaXR) ships a specific XR Tools version — treat THAT as the source of
  truth for `XRToolsPickable`'s API, not master. (We pulled API below from master; diff if needed.)
- **[v6] Android vendor plugin optional since Godot 4.6** — you can export a generic APK without it,
  but you need it for Meta passthrough / Quest store release.
- **[v3] Passthrough via Alpha blend mode works from 4.3+** (needs latest vendor plugin). N/A for an
  opaque VR card game (keep blend mode Opaque).
- **Renderer recommendation conflict:** "Setting up XR" says Mobile renderer; "Deploying to Android"
  says Compatibility (OpenGL) for Android XR "for the time being." For Quest 3 today, **Compatibility/
  OpenGL is the conservative default**; test Mobile/Vulkan only if you want its features and confirm
  stability on-device under 4.7.
- **[v0] Per-material texture filter/repeat moved out of the import dock in 4.0** — set Nearest/Linear
  on the StandardMaterial3D, not in Import.
- **[v5] Stencil Outline / X-Ray next-pass modes exist from 4.5+** (handy for "highlight card behind
  hand"); applies to 4.7.

---

## 1. XR — OpenXR + Godot XR Tools (MOST IMPORTANT)

### 1.1 How OpenXR is enabled
Core architecture: **XRServer** is the central hub; each platform registers an **XRInterface**, found
via `XRServer.find_interface(name)` and started with `initialize()`. OpenXR is a *core* interface
(no desktop plugin to install) because with Vulkan it takes over part of the graphics stack and must
be enabled at engine start.

Enable via **Project Settings** (can't change at runtime):
- `xr/openxr/enabled` → **XR > OpenXR > Enabled** (required for the Vulkan backend, and gates the
  XR Action Map editor). CLI override `--xr-mode on`.
- `xr/shaders/enabled` → **XR > Shaders > Enabled**, then **Save & Restart**.

> Warning: initialization can fail legitimately (headset unplugged, runtime missing). You MUST handle
> `is_initialized() == false` gracefully. Many post-process effects aren't stereo-aware yet — avoid
> glow/bloom/DOF (also required for foveation, see 1.6).
Source: tutorials/xr/setting_up_xr.html, openxr_settings.html

### 1.2 Canonical minimal start script (on the `XROrigin3D` root)
```gdscript
extends Node3D

var xr_interface: XRInterface

func _ready():
    xr_interface = XRServer.find_interface("OpenXR")
    if xr_interface and xr_interface.is_initialized():
        print("OpenXR initialized successfully")
        # Turn off v-sync! OpenXR does its own sync; a 60Hz monitor would otherwise cap output.
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        # Route the main viewport to the HMD
        get_viewport().use_xr = true
    else:
        print("OpenXR not initialized, please check if your headset is connected")
```
The three load-bearing calls: `find_interface("OpenXR")`, `is_initialized()`, `get_viewport().use_xr = true`.
Also raise `Engine.physics_ticks_per_second` (default 60 is too low for a 72–144Hz HMD; see 1.6).
Source: tutorials/xr/setting_up_xr.html

### 1.3 XR rig node structure
Camera and controllers MUST be children of the origin:
```
XROrigin3D          # play-space center; everything tracked is relative to this; holds start script
├── XRCamera3D      # the stereo HMD camera; pose driven automatically by the runtime
├── XRController3D  # rename "LeftHand"; exposes button/axis/pose state, emits input signals
└── XRController3D  # rename "RightHand"
```
- **XROrigin3D** = origin of physical play space. **XRCamera3D** = auto-positioned HMD camera.
  **XRController3D** = per-hand controller, auto-positioned from its `pose`, emits button signals.
- **XRNode3D** = base node that positions itself from a tracker pose (class ref; tutorials build the
  rig from the three nodes above). Attach card-grab visuals/areas under the LeftHand/RightHand.
- Dev-time placement (auto-corrected at runtime): camera y=1.7; hands ~±0.5, 1.0, -0.5.
- Don't call `initialize()` more than once across scene changes — undefined behavior. Prefer one
  persistent XR scene.
Source: tutorials/xr/setting_up_xr.html

### 1.4 Production "better" start script (recommended)
Handles focus/visibility, refresh-rate matching, and foveation. Quits on failure (fine for a
VR-only app). Key behaviors:
- **`session_begun`**: query `get_available_display_refresh_rates()`, pick the highest ≤
  `maximum_refresh_rate` (export, default 90), apply via `set_display_refresh_rate()`, then
  `Engine.physics_ticks_per_second = current_refresh_rate` (avoids choppy physics).
- **`session_visible`**: game visible but unfocused (startup, system menu, headset removed) →
  `get_tree().paused = true`, emit `focus_lost`. While visible-only, controller/hand tracking is
  disabled; keep paused so it doesn't suddenly re-enable on refocus.
- **`session_focussed`**: gained focus → unpause, emit `focus_gained`.
- **`pose_recentered`**: re-orient player; often `XRServer.center_on_hmd(...)` (but obey the
  reference-space rules in 1.7).
- **VRS/foveation**: `if RenderingServer.get_rendering_device(): vp.vrs_mode = Viewport.VRS_XR`
  (Mobile/Forward+); else recommend project setting `xr/openxr/foveation_level = High` (Compatibility).
- **[v?]** verify signal names (`session_*`) against 4.7's `OpenXRInterface`.
Source: tutorials/xr/a_better_xr_start_script.html

### 1.5 Godot XR Tools — XRToolsPickable (grab + throw component)  ← CORE MECHANIC
XR Tools is a **separate addon** (repo `GodotVR/godot-xr-tools`, hyphen — distinct from the
`godot_openxr_vendors` underscore repo). It supplies hand scenes, locomotion, and object/UI
interaction on top of core XR. Use **low-poly** hand scenes on Quest.

**`XRToolsPickable extends RigidBody3D`** — so the card script can `extends XRToolsPickable` (or
attach it) and it IS a RigidBody3D; all of §2 applies. It's picked up by an `XRToolsFunctionPickup`
on the controller; optionally snaps into `XRToolsSnapZone` areas; grab locations defined by child
`XRToolsGrabPoint` nodes.

**Signals (emitted args):**
| Signal | Args | Fires when |
|---|---|---|
| `picked_up` | `(pickable)` | held by player or snap-zone |
| `dropped` | `(pickable)` | released entirely (no longer held) |
| `grabbed` | `(pickable, by)` | a hand grabs (primary or secondary) |
| `released` | `(pickable, by)` | a hand releases (primary or secondary) |
| `action_pressed` | `(pickable)` | action button pressed while held |
| `action_released` | `(pickable)` | action button released while held |
| `highlight_updated` | `(pickable, enable)` | highlight state changes |

**Exported (tunable) properties:**
- `enabled: bool = true` — can it be picked up.
- `press_to_hold: bool = true` — must keep grip held vs toggle.
- `picked_up_layer: int` (`@export_flags_3d_physics`, default layer 17 "held-object") — collision
  layer while held.
- `release_mode: ReleaseMode = ORIGINAL` — enum `{ORIGINAL=-1, UNFROZEN=0, FROZEN=1}`: freeze state
  to restore on drop. For a thrown card you want it **UNFROZEN** so physics flies it.
- `ranged_grab_method: RangedMethod = SNAP` — enum `{NONE, SNAP, LERP}` (grab-at-distance).
- `second_hand_grab: SecondHandGrab = IGNORE` — enum `{IGNORE, SWAP, SECOND}`.
- `ranged_grab_speed: float = 20.0`.
- `picked_by_exclude: String`, `picked_by_require: String` — group gating for who may grab.

**How throw velocity is imparted (critical):** While held, the object is `freeze = true`,
`collision_layer = picked_up_layer`, `collision_mask = 0` (no collisions while in hand). On release,
`let_go(by, p_linear_velocity, p_angular_velocity)` runs:
```gdscript
freeze = restore_freeze            # back to unfrozen for a throw
collision_mask = original_collision_mask
collision_layer = original_collision_layer
linear_velocity = p_linear_velocity     # <-- throw velocity injected here
angular_velocity = p_angular_velocity
dropped.emit(self)
```
The **velocity values come from the `XRToolsFunctionPickup` grabber**, which tracks the controller's
motion and passes the hand's measured linear/angular velocity at release. So "throw feel" is governed
by (a) controller motion tracking, (b) the card's RigidBody mass/shape, and (c) the FunctionPickup's
velocity-averaging. Tune throw feel on the FunctionPickup + RigidBody, not by setting velocity
yourself.

Useful methods: `pick_up(by)`, `drop()`, `drop_and_free()`, `is_picked_up()`,
`get_picked_up_by_controller() -> XRController3D`, `request_highlight(from, on)`.
Source: GodotVR/godot-xr-tools addons/godot-xr-tools/objects/pickable.gd (master)

### 1.6 Quest 3 deployment & performance constraints
**Renderer:** Compatibility/OpenGL is the safe default for Android XR right now (Mobile Vulkan
"still working out the kinks"); Forward+ "isn't well optimized for XR." Re-test under 4.7.
**V-sync:** always `VSYNC_DISABLED` (OpenXR syncs).
**Refresh + physics:** query/raise refresh rate; set `Engine.physics_ticks_per_second` to match it
(also helps CCD reliability — see §2). Avoid the 60-physics default on a 72–144Hz HMD.
**Foveated rendering:** Mobile/Forward+ → `Viewport.vrs_mode = Viewport.VRS_XR`. Compatibility →
project setting `xr/openxr/foveation_level` (High recommended) + optional Foveation Dynamic.
⚠ **Foveation is disabled if post effects (glow/bloom/DOF) are used** — another reason to skip them.
**Hand tracking:** `xr/openxr/extensions/hand_tracking` is on by default "for legacy reasons"; this
is a controller-only card game → **turn it off** to save overhead.
**Submit Depth Buffer:** improves reprojection but disables stencil; leave off unless it clearly helps.
**Frame Synthesis:** reprojection-frame injection; Forward+-incompatible, stereo-only.
**Perf hot-path rules (general, doubly true at 2× render):** avoid per-frame allocations (don't
`.new()` in `_process`/`_physics_process`), reuse cached Texture2D/material refs, keep draw calls
low (a few cards + table + opponent = fine), prefer Unshaded materials (see §3), low-poly hands.

**Android build steps:**
- Prereqs: **OpenJDK 17**, **Android Studio / SDK** (Platform-Tools 35+, Build-Tools 35.0.1,
  Platform 35, cmdline-tools latest; NDK r28b + CMake 3.10.2.x). Set **Editor Settings > Android >
  Java SDK Path** and **Android SDK Path** (the latter must contain `platform-tools/adb`).
- **Project > Install Android Build Template…** → creates an editable `android/` folder (custom
  Gradle build), required to bundle a vendor OpenXR loader.
- **Vendor plugin** (`godot_openxr_vendors`): Asset Store "OpenXR vendors" or copy
  `assets/addons/godotopenxrvendors` into `addons/`. **[v6] Optional since 4.6** but needed for
  Meta-specific features / store. (The BowleraramaXR template likely already wires this — check
  before adding a second copy.)
- **Export preset** (Project > Export > Add > Android): rename "Meta Quest"; enable **Use Gradle
  Build**; **XR Mode = OpenXR**; mark **Runnable** for one-click deploy; under **XR Features** pick
  the headset (or Khronos plugin); configure **Meta XR Features** for Quest.
- **Quest device:** enable Developer Mode on the headset + USB debugging; Windows needs Meta ADB
  drivers. `adb devices` to confirm; one-click deploy icon (top-right of editor) does
  export→install→run in debug. Manual sideload: `adb install -r build.apk`.
- ⚠ "Could not install to device" = same package name signed with a different key already installed
  → uninstall from headset first.
Source: tutorials/xr/deploying_to_android.html, export/exporting_for_android.html, one-click_deploy.html

### 1.7 Reference space (seated/standing card game)
Set under **XR > OpenXR**. Form Factor = Head Mounted, View Config = Stereo (mismatch → init fails).
**Reference Space** — for a player who stays put at a table:
- **Local** (origin at head) or **Local Floor** (origin at player, floor preserved) are typical for
  seated/standing. In these modes **do NOT call `center_on_hmd`** — the runtime handles recenter and
  emits `pose_recentered`.
- **Stage** (default, room-scale) — runtime does NOT move origin on recenter; **you must handle
  `pose_recentered`** (e.g. `XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)`), or stores
  may reject the app.
For 土風水競, **Local Floor** is the natural pick (stand at a virtual table, floor height correct).
Source: tutorials/xr/openxr_settings.html

### 1.8 XR Action Map (controller input to grab/throw)
Separate from Godot's normal Input system; lives in the OpenXR module (needs OpenXR enabled). Open
the **XR Action Map** panel (bottom of editor). Start blank (the auto-generated default is a bad
example). Action types: **Bool** (buttons), **Float** (analog triggers), **Vector2** (sticks),
**Pose** (`aim`/`grip`/`palm` — drives XRController3D position), **Haptic** (output).
> ⚠ For grip/trigger used to grab a card, prefer the **Float** type + your own threshold — some
> runtimes don't apply sensible Bool conversion thresholds. Bool is fine for A/B/X/Y.
Set up the **Touch controller** interaction profile (Quest) + **Simple controller** fallback, and
**test on the actual Quest 3**. Newer controller profiles may require a newer Godot **[v?]**.
Source: tutorials/xr/xr_action_map.html

---

## 2. Physics — RigidBody3D + Area3D (throw + landing detection)

### 2.1 Body types
- **Area3D** — detection/influence region; emits enter/exit signals; can override gravity/damp.
  → **the play zone.**
- **StaticBody3D** — doesn't move; collides. → table/floor/walls.
- **RigidBody3D** — fully simulated; you apply forces/impulses, engine moves it. → **the card**
  (via `XRToolsPickable`, which extends RigidBody3D).
- **CharacterBody3D** — collision but no physics; code-driven. (Not needed.)
- `PhysicsMaterial` on static/rigid bodies tunes friction/bounce — relevant for how the card slides/
  settles on landing.
> ⚠ Physics is **not deterministic** in Godot — the same throw won't land identically every time.
Source: tutorials/physics/physics_introduction.html

### 2.2 RigidBody3D — control, forces, impulses
**Never drive a RigidBody every frame via `set_global_transform()`/`look_at()`** — it breaks the
simulation. Set launch velocity once and let physics run. For the card, XR Tools already injects
`linear_velocity`/`angular_velocity` on release (§1.5) — don't fight it.

Force/impulse API:
- `apply_central_impulse(impulse: Vector3)` — instantaneous velocity change at center of mass
  (one-shot). **This is the idiomatic call for the robot opponent's throw** — call once toward the
  zone. Impulses = instantaneous; forces = continuous push.
- `apply_impulse(impulse, position)`, `apply_central_force(force)`, `apply_force(force, position)`,
  `apply_torque_impulse(impulse)`.
- Inside `_integrate_forces(state: PhysicsDirectBodyState3D)` use `state.apply_force(...)`,
  `state.apply_torque(...)`, or set `state.linear_velocity` / `state.angular_velocity`. This is the
  *only* safe place to alter physics-related properties (not `_physics_process`).
- Properties (class ref): `mass`, `gravity_scale`, `freeze`/`freeze_mode`, `lock_rotation`,
  `axis_lock_angular_*` / `axis_lock_linear_*`, `continuous_cd`, `can_sleep`, `sleeping`,
  `linear_velocity`, `angular_velocity`, `custom_integrator`.

**Axis lock** (`axis_lock_angular_x/y/z`, `lock_rotation`): consider locking some rotation axes to
tame a flat card's tumbling if free-tumble lands too many edge-cases — but locking removes natural
spin, so prototype both.

**Contact monitoring on the RigidBody itself:** to get `body_entered` ON the card you must set
`contact_monitor = true` AND `max_contacts_reported > 0`. For landing detection, prefer the Area3D
(§2.3) — simpler, no contact-monitor cost on the card.
Source: tutorials/physics/rigid_body.html, physics_introduction.html, RigidBody3D class ref

### 2.3 Area3D — the play zone
Detects `CollisionObject3D` overlap; respects collision layer/mask. Signals:
- **`body_entered(body)` / `body_exited(body)`** — fire for PhysicsBody nodes (your card is a
  RigidBody3D → **use `body_entered`** to resolve a round). The callback hands you `body` so you can
  identify which card landed.
- `area_entered(area)` / `area_exited(area)` — for other Areas.
- `monitoring` must be ON for the area to detect. `monitorable` = whether other areas can see it.
- Optional **Space Override** (Combine/Replace/…) can apply extra gravity / **Linear Damp** /
  **Angular Damp** / point-gravity inside the zone — useful to make the card *settle gently* in the
  zone instead of bouncing out.
```gdscript
extends Area3D
func _ready():
    body_entered.connect(_on_body_entered)
func _on_body_entered(body: Node3D) -> void:
    if body.is_in_group("cards"):
        resolve_round(body)
```
Source: tutorials/physics/using_area_2d.html (Area3D identical), physics_introduction.html

### 2.4 Collision layers & masks
32 layers. `collision_layer` = which layers the object IS in; `collision_mask` = which layers it
SCANS. **Detection is one-directional via mask:** the Area3D's *mask* must include the card's
*layer*. Name layers in **Project Settings > Layer Names > 3D Physics** (e.g. "card", "play_zone",
"table"). Per-bit setters: `set_collision_layer_value(n, true)`, `set_collision_mask_value(n, true)`.
Editor export: `@export_flags_3d_physics var layers`.
> ⚠ XRToolsPickable swaps the card to `picked_up_layer` (default 17) and `collision_mask = 0` while
> held, restoring originals on drop. Make sure the play-zone's mask includes the card's *dropped*
> layer, not the held layer.
Source: physics_introduction.html

### 2.5 Collision shapes (flat card)
`CollisionShape3D` must be a **direct child**; assign a `Shape3D`. **Use a thin `BoxShape3D`** for the
card — primitives are the most reliable/performant for dynamic bodies. Convex (`ConvexPolygonShape3D`)
is OK but unnecessary; **concave/trimesh cannot be used on a moving RigidBody** (StaticBody only).
> ⚠ **Never scale a CollisionShape3D node** — keep Node scale (1,1,1); resize via the shape resource's
> `size`/extents. Scaling causes unexpected collisions. Also: thin shapes report contacts less
> precisely than primitives, and a thin resting card can jitter.
Source: tutorials/physics/collision_shapes_3d.html

### 2.6 Continuous CD & tunneling (THE flat-card risk)
A fast-thrown thin card can **tunnel** through a thin trigger Area / floor. Mitigations (do all):
1. Enable **`continuous_cd`** on the card RigidBody3D.
2. **Make the play-zone Area3D's box (and floor collider) THICKER than the visual** — a flat trigger
   is exactly what a fast card passes through. Give the Area a tall/deep box even if the zone *looks*
   flat. This is the most robust safeguard for `body_entered`.
3. Raise **Physics Ticks per Second** to 120/180/240 (also reduces VR latency — you want this anyway).
4. Optionally enlarge the card's collision box slightly beyond its mesh while moving fast.
5. Backstop: a forward **RayCast3D** / `space_state.intersect_ray(query)` with
   `query.collide_with_areas = true` to catch a single-tick overshoot of the zone.
> Note: CCD prevents tunneling through *solid* colliders; reliable `body_entered` against a thin
> *trigger* Area at speed is less certain → #2 (thick Area) matters most.
Source: tutorials/physics/troubleshooting_physics_issues.html, ray-casting.html

### 2.7 Sleeping bodies
A resting RigidBody **sleeps** (acts static, no force calc, `_integrate_forces` not called) — good,
saves CPU after the card settles. It **wakes automatically** when a force/impulse/collision hits it,
so re-throwing or the next round wakes it. Only disable `can_sleep` if you need continuous
`_integrate_forces` at rest (costs perf — usually don't).
Source: physics_introduction.html

---

## 3. 3D — StandardMaterial3D & texture import (sprite-face system)

### 3.1 StandardMaterial3D & albedo swapping
`StandardMaterial3D` (← `BaseMaterial3D`) is the built-in PBR material. For the card face:
- `albedo_color` — base tint, multiplied with texture. Set to opaque white `Color(1,1,1,1)` so it
  doesn't tint faces.
- `albedo_texture` — **the hot-swap target.** Preload all four frames once, reassign at runtime:
```gdscript
# Cache once (no per-frame disk/alloc); reassign to swap face:
const NEUTRAL := preload("res://faces/neutral.png")
const BLINK   := preload("res://faces/blink.png")
const SMILE   := preload("res://faces/smile.png")
const CRY     := preload("res://faces/cry.png")
# material is a StandardMaterial3D unique to THIS card (see 3.2):
material.albedo_texture = SMILE
```
- **Transparency** (`transparency`): Disabled (opaque, fastest) / **Alpha Scissor** (hard-edged
  cutout, keeps shadows, no sort glitches — best for cutout faces) / Alpha (soft, slow, no shadows,
  sort issues) / Alpha Hash / Depth Pre-Pass. If faces are opaque rectangles → **Disabled**. If they
  have transparent borders → **Alpha Scissor** with `alpha_scissor_threshold` (default 0.5).
- `texture_filter` — **Nearest** for pixel-art faces (crisp), **Linear[/w Mipmaps]** for smooth art
  (no shimmer in VR at oblique angles). Set on the material, NOT the import dock **[v0]**.
- `shading_mode` — **set `SHADING_MODE_UNSHADED`** for card faces: consistent brightness regardless
  of scene light, and cheapest path (good for 2× VR render). Faces read like 2D-in-3D.
- `billboard_mode` — **keep Disabled** in VR (billboard faces "the camera plane," ambiguous in stereo,
  looks swimmy). Orient cards via Transform3D.
- `cull_mode` — **Back** (cheap, single-sided). For a different card back, use a second QuadMesh /
  surface, don't disable culling.
Source: tutorials/3d/standard_material_3d.html

### 3.2 Shared vs per-instance material (THE swap gotcha)
Resources are shared by reference. A material on a **Mesh resource** is "used every time that mesh is
used" → editing it changes **all** cards at once. Each card needs its **own** material so smile/cry can
coexist. Override priority: mesh material < node surface material < **`material_override`** < overlay.
Fixes (pick one):
```gdscript
# A) Build a unique material per card in code (most robust for spawned cards):
var face_mat := StandardMaterial3D.new()
face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
face_mat.albedo_texture = NEUTRAL
$CardFace.material_override = face_mat

# B) Per-surface override:
$CardFace.set_surface_override_material(0, face_mat)   # QuadMesh = surface 0

# C) Break a shared ref at runtime:
var m := $CardFace.get_active_material(0).duplicate()
$CardFace.material_override = m
m.albedo_texture = SMILE
```
- D) Editor: right-click material → **Make Unique**; or for instanced `card.tscn`, enable **Local to
  Scene** on the material resource so each instance auto-copies at load. ← cleanest if cards are
  PackedScene instances.
> ⚠ If cards are `card.tscn` instances sharing one material and it's NOT Local to Scene / overridden,
> swapping one face swaps every card. This is the #1 trap for the sprite-face system.
Source: tutorials/3d/standard_material_3d.html (concept); set_surface_override_material / Local to
Scene are MeshInstance3D class ref / scene-instancing behavior.

### 3.3 Texture import for faces
- **Filter/repeat are per-material in 3D since 4.0** — not in Import **[v0]**.
- **Mipmaps > Generate**: recommended in 3D (no graininess at distance), +~33% memory. (`Mipmaps >
  Limit` is documented but **not implemented** — ignore.)
- **Compression Mode**: Lossless = "recommended for pixel art"; VRAM Compressed = 3D default but
  **bad for pixel-art / low-res** (artifacts).
- ⚠ **Detect 3D trap:** assigning a PNG to `albedo_texture` auto-switches it to **VRAM Compressed +
  mipmaps**, adding artifacts to crisp faces. Fix: set **Detect 3D > Compress To = Disabled/Lossless**
  *before first use*, or reset **Compress Mode = Lossless** after. Pixel-art explicitly should have
  VRAM compression OFF.
- **Format:** PNG (8-bit RGBA) or WebP for alpha. **JPEG has no transparency** — don't use it for
  cutout faces.
- **Process > Fix Alpha Border** (on by default): prevents a dark outline around cutouts under Linear
  filtering — leave on if faces have transparency + Linear filter.
Source: tutorials/assets_pipeline/importing_images.html

### 3.4 Card geometry
**QuadMesh** = flat 1×1 quad on XY facing **+Z** → natural upright card face; set `size` (Vector2) to
card dims; single surface (index 0). **PlaneMesh** = flat on XZ facing +Y (lies flat like a floor) —
needs a 90° rotation to stand up. For a held/thrown card, **QuadMesh** matches the transform's forward
(`-transform.basis.z`). Don't use the Euler `rotation` property for logic — use `Transform3D`/`Basis`;
slerp `Quaternion`s for smooth card-flip animation.
Source: tutorials/3d/standard_material_3d.html, using_transforms.html

---

## 4. Scripting — signals, groups, Timer, @export

### 4.1 Signals (Godot 4 syntax)
Declare `signal name(args)` (name = **past-tense verb**, e.g. `round_resolved`). Emit with
`name.emit(args)`. Connect with `obj.signal.connect(callable)` (bare method ref, **no quotes** — the
Godot-3 string form is dead):
```gdscript
signal round_resolved(winner)

func _ready():
    $PlayZone.body_entered.connect(_on_zone_body_entered)   # built-in signal
func _on_zone_body_entered(body): ...
func resolve(): round_resolved.emit(winning_card)            # custom emit
```
Awaited signal values: 1 arg → that value; >1 → Array; 0 → null. Editor-generated handlers are named
`_on_<node>_<signal>`.
Source: getting_started/step_by_step/signals.html, gdscript_basics.html

### 4.2 Groups (tagging cards/zones)
`add_to_group("cards")` / `remove_from_group(...)` / `is_in_group(...)`. Operate via SceneTree:
`get_tree().get_nodes_in_group("cards")`, `get_tree().call_group("cards", "reset")`,
`get_first_node_in_group("play_zone")`. Use to tag all cards and the play zone(s).
Source: tutorials/scripting/groups.html

### 4.3 Timer — blink loop & delays
- **Timer NODE** (for the **blink loop** and any restartable clock): props `wait_time` (float),
  `one_shot` (false = repeating, the blink case), `autostart`, `paused`, `time_left` (read-only),
  `process_callback` (`TIMER_PROCESS_IDLE` default / `TIMER_PROCESS_PHYSICS` — use physics if it must
  align with VR physics). Methods `start(sec=-1)`, `stop()`; signal `timeout`.
```gdscript
@onready var blink_timer: Timer = $BlinkTimer
func _ready():
    blink_timer.wait_time = 3.0
    blink_timer.one_shot = false        # repeating blink loop
    blink_timer.timeout.connect(_on_blink)
    blink_timer.start()
func _on_blink():
    material.albedo_texture = BLINK
    await get_tree().create_timer(0.12).timeout   # eyes closed briefly
    material.albedo_texture = NEUTRAL
```
- **SceneTreeTimer** one-liner (one-shot, no node, auto-frees) for fire-and-forget delays:
  `await get_tree().create_timer(0.5).timeout`. Always one-shot; not restartable. Ideal for the
  brief blink-closed delay, deal pacing, robot "think" pause.
Source: signals.html (Timer node demo), gdscript_basics.html (await), Timer/SceneTree class ref

### 4.4 @export (tunable constants — no recompile)
`@export var` exposes a member in the Inspector. Useful annotations for tuning throw/scoring/blink:
```gdscript
@export var win_score: int = 3
@export_range(0.0, 30.0, 0.1) var robot_throw_impulse: float = 8.0
@export_range(1.0, 6.0, 0.1, "suffix:s") var blink_interval: float = 3.0
@export_enum("Neutral", "Blink", "Smile", "Cry") var debug_face: int
@export var play_zone: Area3D            # drag-drop node ref in inspector
@export var smile_tex: Texture2D         # drag-drop texture
@export_flags_3d_physics var card_layers
```
Other: `@export_group`/`@export_subgroup` (inspector organization), `@export_file("*.png")`,
typed arrays `@export var frames: Array[Texture2D] = []` (drag multiple at once).
> ⚠ Reading an `@export` var in `_init()` returns the **default** (inspector value applied after
> construction) — read in `_ready()` or the setter.
Source: tutorials/scripting/gdscript/gdscript_exports.html

### 4.5 GDScript style (quick)
snake_case funcs/vars/signals (signals past-tense), PascalCase classes/nodes, CONSTANT_CASE consts,
`_private` prefix. Tabs; 2 blank lines around functions; <100 cols; `and`/`or`/`not`. Static typing
encouraged (`var hp: int = 0`, `-> void`, `:=` when obvious; annotate `get_node()`). `@onready` to
cache child deps. Member order: `class_name`/`extends`/doc, then signals, enums, consts, `@export`,
vars, `@onready`, then `_init`/`_ready`/`_process`/`_physics_process`, then methods.
Source: gdscript_styleguide.html

---

## 5. Best practices — communication, autoloads, scenes, node alternatives

### 5.1 Node communication: "call down, signal up"
Design scenes with **no hard external dependencies**. Parent provides deps to child (dependency
injection); child stays decoupled. Mechanisms: connect a **signal** (child *responds* to env —
extremely safe), **call a method** (start behavior), inject a **Callable**, inject a **Node ref**, or
a **NodePath**. **Siblings shouldn't reference each other** — an ancestor mediates. If a node needs an
external dep, make it a `@tool` script with `_get_configuration_warnings()` so the editor self-
documents it.
Source: tutorials/best_practices/scene_organization.html

### 5.2 Autoload (singleton) vs node
Costs of autoloads: global state, global access (bugs searchable anywhere), global allocation. Use an
autoload only when a system (1) manages its OWN data, (2) needs global access, (3) exists in isolation
(docs' examples: quest/dialogue system). **Systems that modify other systems' data → regular
scripts/scenes, not autoloads.**
→ For 土風水競: a `GameManager`/`ScoreManager` that owns score/round state and **broadcasts via
signals** is a legitimate autoload. Anything reaching into card/zone internals should be a node.
Since 4.1, `static var`/`static func` can share data without a full autoload. Access an autoload via
`get_node("/root/GameManager")` (it's a node at root, not necessarily a singleton class).
Source: tutorials/best_practices/autoloads_versus_regular_nodes.html

### 5.3 Scene organization
Have a single **Main** entry point (`main.gd`) controlling a World (3D) + (optional) GUI. Split a
branch into its own scene when it can stand alone without hard refs to its environment; re-use breaks
when a sub-scene depends on editor-wired NodePaths/signals to outside nodes — fix with the DI patterns
above. Parent-child only when children are truly *elements of* the parent (removing parent should
remove children); otherwise make them siblings. Node trees are aggregation, not composition.
Suggested: a reusable **`card.tscn`** (RigidBody3D/XRToolsPickable + CollisionShape3D thin box +
MeshInstance3D quad + BlinkTimer), instanced for player/robot; the play zone and score manager mediate.
Source: tutorials/best_practices/scene_organization.html

### 5.4 Node alternatives (don't make everything a Node)
- **`RefCounted`** — auto-freed when unreferenced; default for custom data/logic classes (deck state,
  shuffle/RNG helper, scoring math).
- **`Resource`** — RefCounted + serialize + Inspector-editable; model **card *definitions*** (suit/
  value/face-set refs, rules) as `card_data.gd extends Resource` (`.tres`), far lighter than a Node
  each. Only spawn a Node/scene for cards physically present in the 3D scene.
- **`Object`** — lightest, **manual memory** (refs can go invalid) — avoid unless you must.
Source: tutorials/best_practices/node_alternatives.html

---

## 6. Gotchas / risks for this project

1. **Flat-card throw physics (KNOWN RISK).** Thin BoxShape3D tumbles / lands on edge / jitters at
   rest. Mitigate: thicker floor & zone colliders; raise physics tick rate (120–240); tune mass +
   PhysicsMaterial friction/bounce; consider axis-locking some rotation to reduce wild tumble (test —
   it kills natural spin). Physics is non-deterministic, so don't depend on a fixed landing pose.
2. **Fast card tunneling through the Area3D (§2.6).** Enable `continuous_cd`, **make the play-zone box
   thick** (not a flat trigger), raise physics ticks, optional RayCast backstop with
   `collide_with_areas = true`. A flat trigger is the worst case for a fast flat object.
3. **XRToolsPickable layer swap.** While held: `freeze=true`, layer→`picked_up_layer` (17), `mask=0`;
   restored on drop. Ensure the play-zone's mask targets the card's *dropped* layer, and that
   `release_mode` leaves it **UNFROZEN** so the throw flies.
4. **Shared vs per-instance material (§3.2).** If cards share one non-Local-to-Scene material,
   swapping one face swaps ALL. Use `material_override`/`set_surface_override_material(0, ...)` or
   Local to Scene + a unique StandardMaterial3D per card.
5. **Detect 3D compresses face PNGs (§3.3).** Auto VRAM-compresses on first 3D use → artifacts on
   crisp faces. Set Detect 3D > Compress To = Disabled/Lossless before use.
6. **Sleeping bodies (§2.7).** Fine after settle; wake automatically on impulse. Don't disable
   `can_sleep` without reason.
7. **Per-frame allocation in hot paths.** Don't `.new()` materials/textures/arrays or `load()` in
   `_process`/`_physics_process` — preload/cache. Doubly costly at 2× VR render. Avoid post effects
   (also disables foveation).
8. **OpenXR signal-name drift [v?]** and **XR Tools version coupling [v?]** — verify against 4.7 +
   the template's pinned XR Tools.
9. **Don't drive the card's transform per-frame** while physics owns it; let velocity/impulse work.

---

## 7. Relevance to 土風水競 (concept → where used)

| Concept | Source § | Where in project |
|---|---|---|
| OpenXR enable + start script | 1.1–1.2 | XROrigin3D root script / project settings |
| XR rig (origin/camera/controllers) | 1.3 | Main XR scene |
| Better start script (focus/refresh/foveation) | 1.4, 1.6 | XR boot autoload/root |
| **XRToolsPickable grab+throw** (signals/exports/velocity) | 1.5 | `card.tscn` root (extends/uses it) |
| Quest export + adb deploy | 1.6 | Meta Quest export preset; build pipeline |
| Local Floor reference space | 1.7 | OpenXR project settings (seated/standing table) |
| Action map (Float trigger threshold) | 1.8 | XR Action Map; grab/throw input |
| RigidBody3D + thin BoxShape3D | 2.1–2.2, 2.5 | card collider; R: throw mechanic |
| `apply_central_impulse` | 2.2 | Robot opponent throw |
| Area3D `body_entered` | 2.3 | Play-zone landing → resolve round |
| Layers/masks (card vs zone, held-layer caveat) | 2.4 | card + play-zone collision config |
| CCD / thick zone / physics ticks | 2.6 | anti-tunneling for fast throw |
| Sleeping bodies | 2.7 | card settle / re-throw |
| StandardMaterial3D `albedo_texture` swap, Unshaded | 3.1 | card face frames neutral/blink/smile/cry |
| Per-instance material (override/Local to Scene) | 3.2 | each card's unique face material |
| Texture import (Nearest, Detect 3D, alpha) | 3.3 | face PNG import settings |
| QuadMesh face | 3.4 | card MeshInstance3D |
| Signals (`round_resolved`, `body_entered`) | 4.1 | round flow / scoring |
| Groups ("cards", "play_zone") | 4.2 | tagging cards/zones |
| **Timer node (repeating)** + SceneTreeTimer | 4.3 | **blink loop**; deal/think delays |
| `@export` tunables | 4.4 | win_score=3, robot_throw_impulse, blink_interval |
| GameManager/ScoreManager autoload (signal-broadcast) | 5.2 | first-to-3 scoring |
| `card.tscn` sub-scene; Resource for card data | 5.3–5.4 | scene structure; card definitions |
