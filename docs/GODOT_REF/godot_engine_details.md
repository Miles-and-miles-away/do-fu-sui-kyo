# Godot Engine Details — Project Notes (土風水競)

> Distilled from the Godot 4.x **stable** docs, filtered for a small, headless-testable,
> single-player VR card game on Quest 3 (Godot 4.7 / GDScript). Where the docs say "stable"
> they target 4.x broadly; items that could shift for **4.7** are flagged **[ver]**.
> YAGNI: engine-internals topics with no bearing on this project get a one-line "out of scope".
>
> Sources (cited inline below):
> - SceneTree / MainLoop: https://docs.godotengine.org/en/stable/getting_started/step_by_step/scene_tree.html
> - Idle vs physics processing: https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html
> - Notifications (best practices): https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html
> - Object/RefCounted/Resource (node alternatives): https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html
> - Resources (sharing/loading/freeing): https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html
> - Command line tutorial: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html

---

## 1. SceneTree & the main loop

The runtime stack, top to bottom (src: scene_tree):

```
OS  ->  MainLoop  ->  SceneTree  ->  root Viewport  ->  your scene tree
(low-level)            (the game engine's own MainLoop, auto-instanced)
```

- `OS` boots first, loads drivers/servers/scripting, then is handed a **`MainLoop`** to run.
  `MainLoop` exposes init / idle (frame) / physics (fixed) / input callbacks. You **rarely** write
  your own — **except a headless `--script` test, which MUST be a `MainLoop`/`SceneTree`** (see §5).
- `SceneTree` is the `MainLoop` Godot supplies automatically when you run a *scene*. It owns:
  - the **root `Viewport`** (`get_tree().root`, path `/root`) — everything visible is under it;
  - **groups** (`call_group`, get nodes in a group);
  - **global state**: pause, `quit()`, `change_scene_to_*`.
- From any node: `get_tree()` -> the `SceneTree` singleton. Autoloads (like `GameState`) are
  children of `/root`, so they are *in* the tree once the game runs (relevant to §5 caveat).
- A node "becomes active" only once connected (directly/indirectly) to the root viewport — that's
  when `_enter_tree` / `_ready` fire and it can process, draw, get input. (src: scene_tree)

### Tree order (matters for deterministic face/score updates)
- **Process, draw, most notifications**: **top-to-bottom** (pre-order) — parent's `_process`
  before its children. (src: scene_tree)
- **`_ready` is the exception**: a parent's `_ready` runs **after all children's `_ready`**
  (post-order) — so a parent can safely touch fully-initialized children.
- **`_exit_tree`**: bottom-to-top (reverse). (src: scene_tree)
- Override ordering with the node `process_priority` property (lower = called first). Useful if a
  manager node must `_process` before/after the cards it drives.

---

## 2. Idle (`_process`) vs physics (`_physics_process`)

(src: idle_and_physics_processing, notifications)

| | `_process(delta)` | `_physics_process(delta)` |
|---|---|---|
| Rate | **Every rendered frame** — varies with framerate / device | **Fixed step**, default **60 Hz** (Physics FPS in Project Settings) |
| `delta` | Real seconds since last call (variable) | Constant `1/physics_fps` (e.g. ~0.01667 s) |
| Use for | Visuals, timers/cooldowns, UI text, "as often as possible" logic | Anything touching the physics engine — moving bodies, reading collisions |
| Notification | `NOTIFICATION_PROCESS` | `NOTIFICATION_PHYSICS_PROCESS` |

- `_process` is **not** synchronized with physics; in single-threaded games it runs **after** the
  physics step. Its rate is hardware/optimization dependent.
- Toggle with `set_process(bool)` / `set_physics_process(bool)`. **Defining the method is what
  enables it** — an empty `_process` still costs a per-frame call.
- **Always multiply rates by `delta`** so behavior is framerate-independent.
- **Inputs**: prefer `_unhandled_input(event)` / `_input(event)` over polling inside `_process`/
  `_physics_process`. `*_input` fires **only on frames where input occurred**; the process
  callbacks fire every frame and never "rest" — a cheap perf win. (src: notifications)
- **Don't-need-every-frame trick** (recommended in the docs): a `Timer` + `timeout` signal instead
  of per-frame checks. (src: notifications)

```gdscript
# Recurring work without a per-frame callback (docs' recommended pattern)
func _ready() -> void:
    var t := Timer.new()
    t.autostart = true
    t.wait_time = 0.5
    add_child(t)
    t.timeout.connect(func(): print("every 0.5 s"))
```

### Relevance to 土風水競
- **Throw + `PlayZone` detection** is physics: the card is a `RigidBody3D` and the zone is an
  `Area3D` — detection arrives via the `body_entered` signal, which fires off the **physics**
  step. The single-resolution guard (one resolution per round) is a plain boolean flag flipped in
  that handler, not a per-frame poll. No need to put detection in `_physics_process` yourself — the
  signal does it.
- **Blink (~150 ms blink, randomized 3.0–4.5 s interval)** should be a **`Timer`**, not a
  `delta` accumulator in `_process`. Two timers (or one re-armed with a random `wait_time`) keep it
  off the per-frame path and make the no-per-frame-allocations goal trivial to honor. A locked
  smiling/crying card just stops/ignores the timer.
- The **reveal pause (~2 s)** is likewise a `Timer` or `await get_tree().create_timer(2.0).timeout`,
  not a frame counter.

---

## 3. Object lifecycle & memory model

The four core base types, lightest to heaviest (src: node_alternatives, resources):

| Type | Memory mgmt | Frees when | Inspector? | Use it for |
|------|-------------|-----------|-----------|------------|
| `Object` | **Manual** (`free()`) | You call `free()`; refs can go **dangling without warning** | no | Rarely; lowest-level custom structures |
| `RefCounted` | **Auto** (ref counting) | Last reference drops | no | Most plain data/helper classes (default `extends` for non-Node scripts) |
| `Resource` | Auto (extends RefCounted) | Last reference drops | **yes** + save/load to `.tres`/`.res` | Data containers you want in the Inspector / on disk |
| `Node` | Tree-owned | `queue_free()` / `free()` / parent freed | yes (as scene) | Anything in the scene that *does* something |

### Freeing nodes
- **`queue_free()`** — defers deletion to the **end of the current frame**. Safe default; use it
  while signals/physics may still touch the node (e.g. a consumed card after a round). (general)
- **`free()`** — immediate. Dangerous mid-signal/mid-physics; can leave dangling references.
- A freed `Object`/`Node` that something still holds a bare reference to → **error on next access**
  (no GC safety net for raw `Object`). `RefCounted`/`Resource` avoid this by counting refs.
- `Object::NOTIFICATION_PREDELETE` is the "destructor" callback fired before the engine deletes an
  object; `NOTIFICATION_POSTINITIALIZE` fires during init (not script-accessible). (src: notifications)

### Why `GameState` (Autoload `Node`) persists
- An **Autoload is a `Node` parented to `/root`** by the engine at startup and **never freed** for
  the life of the process — so its `deck`/`hand`/`score` state survives every `change_scene_to_*`
  and every round. That persistence is exactly what the pure-logic brain leans on. It is in the
  SceneTree (so `get_tree()` works), but it carries **no 3D dependencies** — pure logic.
- Caveat: because it's a `Node`, headless `--script` runs do **not** auto-load it (see §5).

### Resource sharing & duplication (the `.tres` `CardData` decision)
- **A resource loaded from disk loads exactly once.** `load("res://x.tres")` returns **the same
  shared instance** every subsequent call; instancing a scene N times still shares one copy of each
  texture/mesh/resource. (src: resources) Good: 12 face sprites cost one load, shared across all card
  nodes (keeps memory down).
- **`preload(const_path)`** loads at compile-time (constant path only). **`load(path)`** loads at
  runtime (variable path allowed). Prefer `preload` for the fixed face/`CardData` assets.
- **Shared-mutable-resource gotcha:** because the copy is shared, if you store **per-instance
  mutable state inside the resource** and edit it on one node, **every** node sees the change. The
  fix is `resource.duplicate()` per instance.
  - **In this project this gotcha does not bite** (confirmed): `CardData` (if used) holds
    only **read-only** `Texture2D` lookups (`neutral/blink/smile/cry`). All per-card runtime state
    (`_locked`, current frame, blink timer) lives on the **node** (`CardFace.gd`), not on the
    resource. So **no `.duplicate()` needed** — the shared read-only `.tres` is correct as-is.
- **Why `Resource` over JSON/Dictionary** for `CardData`: defines typed `@export` properties
  (data guaranteed to exist), can hold constants/methods/signals, auto-serializes to a
  VCS-friendly `.tres`, and renders in the Inspector for no-recompile art edits. (src: resources)
  This is the upside the optional `CardData extends Resource` is buying.
- Resources free themselves automatically when unused; a freed node frees the resources it owns
  **only if no other node still uses them** (ref-counted). (src: resources)

```gdscript
# Optional CardData — shared, read-only, no per-instance state, so no duplicate().
class_name CardData
extends Resource
@export var neutral: Texture2D
@export var blink:   Texture2D
@export var smile:   Texture2D
@export var cry:     Texture2D
# Saved as three .tres (Fish/Bird/Dino), assigned in the Inspector. Type -> 4 frames.
```

---

## 4. Notifications & callback ordering

Every `Object` implements `_notification(what)`; many notifications have dedicated virtuals.
(src: notifications)

Common ones (virtual ⇄ `NOTIFICATION_*`):
- `_ready()` ⇄ `NOTIFICATION_READY`
- `_enter_tree()` ⇄ `NOTIFICATION_ENTER_TREE`
- `_exit_tree()` ⇄ `NOTIFICATION_EXIT_TREE`
- `_process(delta)` ⇄ `NOTIFICATION_PROCESS`
- `_physics_process(delta)` ⇄ `NOTIFICATION_PHYSICS_PROCESS`
- `_draw()` ⇄ `NOTIFICATION_DRAW`
- No-virtual but useful: `NOTIFICATION_PARENTED` / `NOTIFICATION_UNPARENTED` (fire on add/remove
  child, regardless of whether in the active scene), `NOTIFICATION_PREDELETE` (destructor).

### Lifecycle ordering (instantiating a scene vs a standalone node/script)
1. **`_init()`** — constructor. Runs after the script's properties get their initial values, and
   **before** `_enter_tree`/`_ready`. Put scene-independent setup here. **Setter caveat:** initial
   value assignment does **not** trigger setters; assignments in `_init()` **do**; Inspector/exported
   values are applied **after** `_init` and also trigger setters. (src: notifications)
2. **`_enter_tree()`** — cascades **top-down** as the tree is built.
3. **`_ready()`** — fires **once**, **bottom-up** (children before parents).
- **Standalone instancing** (e.g. `Card.new()` or a `.instantiate()` not yet added to the tree):
  only **`_init`** runs. `_enter_tree`/`_ready` wait until `add_child` puts it in the SceneTree.
  This is why the headless test (§5) sees `_init` but not `_ready` unless it adds nodes to the tree.

### Signals (relevant to round flow)
- `Area3D.body_entered` drives round resolution — connect once, set a `resolving` flag in the handler, clear
  it when the next round begins. Disconnect/guard so a second card mid-resolution is ignored.
- Connect with `signal.connect(callable)`; signals are synchronous (handlers run inline when
  emitted) — ordering among multiple connections is connection order. For a single-player game this
  is simple; no need to reason about deferred emission unless you pass `CONNECT_DEFERRED`.

---

## 5. Headless / command-line (CRITICAL — the unit-test gate)

(src: command_line_tutorial)

### macOS invocation note
The `godot` binary on macOS lives inside the `.app` bundle. Either add it to `PATH` (Homebrew:
`brew install godot` puts `godot` on `PATH`) or call:
```
/Applications/Godot.app/Contents/MacOS/Godot  [args...]
```
Below, `godot` = a **Godot editor binary** (not an export template) on `PATH`.

### (a) Run a GDScript headless for unit tests  ← the project's unit-test path
**The script run via `-s/--script` MUST `extend SceneTree` (or `MainLoop`).** A regular `Node`
script will not run this way. (src: command_line_tutorial)

```bash
# From the project root (dir containing project.godot):
godot --headless --script res://tests/test_game_state.gd

# Equivalent with an explicit project path (CI-friendly, run from anywhere):
godot --headless --path <project-root>/do-fu-sui-kyo --script res://tests/test_game_state.gd

# Parse-only sanity check (no execution) — fast pre-commit lint:
godot --headless --script res://tests/test_game_state.gd --check-only
```
- `--headless` = `--display-driver headless --audio-driver Dummy`; required where there's no GPU
  (CI) and harmless locally (just no window).
- A bare relative path like `test_game_state.gd` is interpreted as `res://test_game_state.gd`;
  prefer the explicit `res://tests/...` form. Absolute filesystem paths also work.
- The test script controls its own lifetime: do work in `_initialize()` / `_init()` and call
  `quit(<exit_code>)`. Return a non-zero code on failure so CI fails.

> **Autoload / SceneTree caveat (important for `GameState`):** when you run a script with
> `--script`, **that script *is* the MainLoop** — the normal game `SceneTree` and its **Autoloads
> are NOT loaded**. So `GameState` (an Autoload Node) is *not* auto-available inside the test.
> Because `GameState.gd` is pure logic, the test should `preload` / `load` and instantiate it
> directly rather than expect the singleton:
>
> ```gdscript
> # tests/test_game_state.gd
> extends SceneTree
> func _init() -> void:
>     var gs = preload("res://scripts/GameState.gd").new()  # adjust path
>     gs.new_game()
>     assert(gs.player_hand.size() == 3)
>     # ... assertions ...
>     print("ALL TESTS PASSED")
>     quit(0)
> ```
> Because `GameState` has no 3D/node deps, `.new()` works without a tree. If a future
> version needs the tree, add nodes via `get_root()` (the SceneTree's own root) — but YAGNI for now.

### (b) Import assets headless (CI, before tests/export)
```bash
# Imports all resources then quits. Implies --editor --quit. Needed once in a fresh CI checkout
# so .godot/imported/ exists before headless runs/exports.
godot --headless --import --path <project-root>/do-fu-sui-kyo
# (Older muscle-memory: `godot --headless --editor --quit` also triggers an import pass.)
```

### (c) Export a build from CLI (Quest 3 / Android)
```bash
# Preset name must EXACTLY match one in export_presets.cfg (quote if it has spaces).
# Output path is relative to the project dir (NOT cwd); the target directory must already exist.
godot --headless --path <project-root>/do-fu-sui-kyo \
      --export-release "Meta Quest" builds/dofusuikyo.apk

# Debug template instead (implies --import):
godot --headless --path <project-root>/do-fu-sui-kyo \
      --export-debug "Meta Quest" builds/dofusuikyo-debug.apk

# Pack only (.pck/.zip by extension):
godot --headless --export-pack "Meta Quest" builds/game.pck
```
- Export needs the matching **export templates installed** (or a valid custom template in the
  preset). The Android/Meta Quest preset comes from the BowleraramaXR-Godot template; use
  its exact preset name — verify it in `export_presets.cfg`.
- For Android you may also need `--install-android-build-template` once (used with
  `--export-release/-debug`) if using the custom Gradle build.

### Other handy flags
- `--upwards` — find `project.godot` by searching parent dirs (run from a subfolder).
- `-d` / `--debug` — local stdout debugger when running a scene (`godot -d scene.tscn`).
- `--verbose` — device list for `--gpu-index`, plus general diagnostics.
- Unknown CLI args are **silently ignored** (no warning) — typos fail quietly. (src: command_line_tutorial)

---

## 6. Performance & memory notes for Quest 3

Quest 3 is mobile-class standalone; comfortable framerate is non-functional-mandatory.

- **Servers (conceptual).** Godot is a high-level scene engine over low-level **servers**:
  `RenderingServer` and `PhysicsServer3D` do the actual work; nodes are thin handles that issue
  commands to them. (src: scene_tree — "high-level engine over low-level middleware"). Practical
  takeaway: a node is cheap, but **per-frame churn** (creating/freeing nodes or resources every
  frame, reassigning materials needlessly) pushes work through the servers and costs frames.
- **No per-frame allocations:** keep the throw/blink/resolve hot paths
  allocation-free. Concretely — drive blink/reveal with **`Timer`s** (§2), not per-frame `delta`
  bookkeeping; **`preload`** the 12 face textures and the optional `CardData` once (§3) so swapping
  a face is just `material.albedo_texture = card_data.smile` (a pointer swap on a **shared** texture,
  no load, no allocation, no new material); never `load()` inside `_process`/signal handlers.
- **`StringName`/string churn.** Avoid building strings every frame (the score panel updates only
  **per round**, so that's fine). `--debug-stringnames` can audit StringName allocations if needed.
- **Renderer:** Quest 3 should use the **Mobile** renderer (`--rendering-method mobile`); the
  template's Meta Quest preset already targets this. Forward+ is desktop-class; Compatibility
  (GLES) is the fallback. **[ver]** confirm the template's chosen renderer in project settings.
- **Physics tick:** default 60 Hz is plenty for a thrown card; don't raise Physics FPS. The card's
  flight + `Area3D` detection is event-driven (signal), not a polled loop.
- **Lightweight types over nodes** where data has no scene behavior: the deck/hand are `Array[Type]`
  on a single Autoload (already the design) — no node-per-card data structures. (src: node_alternatives)
- Out of scope for tuning here: multithreaded rendering modes, GPU profiler flags
  (`--gpu-profile`, `--gpu-validation`) — available, reach for them only if profiling shows hitches.

---

## 7. Gotchas / version notes

- **[ver] Docs are "stable" (currently 4.x), project is 4.7.** Everything above is stable-4.x API
  and is expected to hold for 4.7, but verify against the 4.7 editor for: exact CLI export preset
  names, default renderer, and Physics FPS default. The CLI **reference table** can gain/lose flags
  between minor versions — re-check `godot --help` on the actual 4.7 binary.
- **`--script` ≠ game run.** A `--script` target must be `SceneTree`/`MainLoop`; **Autoloads and
  the game SceneTree are absent** in that mode (§5). Instantiate `GameState` directly in tests.
- **`project.godot` always opens the editor.** Passing the `.godot` file (or `-e`) launches the
  editor, not the game. To *run* the game/scene, pass a scene or nothing — not the project file.
- **Export paths are relative to the project dir**, not the shell's cwd. Target dir must pre-exist.
- **`queue_free` vs `free`:** default to `queue_free()` around signals/physics; `free()` only when
  you're certain nothing else references the object this frame.
- **Setter timing:** `@export`/Inspector values overwrite `_init()` assignments and **do** trigger
  setters; initial defaults do **not**. Don't rely on a setter running for a plain default value.
- **Empty `_process`/`_physics_process` still cost a call** — remove them or `set_process(false)`.
- **Shared resource = shared mutation** *if* you mutate it. We don't, so safe — but if
  `CardData` ever gains per-card mutable fields, switch to `.duplicate()` per instance.
- **Out of scope (exist, not needed):** writing a custom `MainLoop` for the game, custom C++
  modules, GDExtension internals, compiling the engine from source, multithreaded scene/render
  tuning. One-liners — ignore unless a concrete need appears.

---

## 8. Relevance map → 土風水競

| Engine concept (source) | Where it lands in the project |
|---|---|
| `SceneTree` owns root + persists Autoloads (scene_tree) | `GameState` Autoload survives rounds/scene changes |
| `_physics_process` / physics-step signals (idle_and_physics) | `RigidBody3D` throw → `Area3D.body_entered` → resolve |
| `Timer` + `timeout` over per-frame polling (notifications) | Blink ~150 ms / 3.0–4.5 s; ~2 s reveal pause |
| Tree order: `_ready` bottom-up, `_process` top-down (scene_tree) | Manager/card init order; face & score updates |
| Object/RefCounted/Resource/Node tiers (node_alternatives) | Deck/hand as `Array[Type]` on one Autoload, not node-per-card |
| Resource loads once / shared, no per-instance state ⇒ no `duplicate()` (resources) | Optional `CardData extends Resource` `.tres`, 12 shared textures |
| `preload` const path; face swap = `albedo_texture` pointer set (resources) | Allocation-free face swap |
| `--headless --script` must be `SceneTree`; Autoloads absent (command_line) | `tests/test_game_state.gd` instantiates `GameState` directly |
| `--headless --import` / `--export-release "<preset>"` (command_line) | CI import + Meta Quest APK build |
| Servers + no-per-frame-alloc + Mobile renderer (scene_tree, perf) | Comfortable Quest 3 framerate, no hitches |
