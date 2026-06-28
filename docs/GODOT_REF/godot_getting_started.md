# Godot "Getting Started" — Project Notes for 土風水競

Distilled from the official Godot docs (en/stable, Godot 4.x) and filtered to what a
single-player VR card game on Godot 4.7 / GDScript actually needs. C#, GDExtension,
2D-game tutorials, and mobile-touch UI are deliberately omitted (YAGNI).

Source index: <https://docs.godotengine.org/en/stable/getting_started/index.html>

> **Version note up front.** The docs are served from the `stable` channel (currently
> Godot 4.x). Every API below is confirmed for 4.x and the modern `Signal.connect()`
> idiom is the 4.x form. Godot 4.7 is forward-compatible with all of this; the
> only things that shift between 4.x minor versions are noted in **Gotchas**.

---

## 1. Core mental model: Nodes, Scenes, the Scene Tree

Source: <https://docs.godotengine.org/en/stable/getting_started/step_by_step/nodes_and_scenes.html>
and <https://docs.godotengine.org/en/stable/getting_started/introduction/key_concepts_overview.html>

- **Node** = the smallest building block (e.g. `Sprite2D`, `RigidBody3D`, `Area3D`,
  `Timer`). Nodes have a name, properties, and inherit behavior from their base class.
- **Scene** = a *tree* of nodes with a single **root** node, saved to a `.tscn`
  ("text scene") file. A scene is a reusable blueprint ("Packed Scene").
- **Scene Tree** = the running game is one big tree assembled from instanced scenes.
- Properties shown in the Inspector in "Title Case" are accessed in code as
  `snake_case` (e.g. Inspector "Angular Speed" → `angular_speed`). Hover a property
  in the Inspector to see its code identifier.

**Editor ↔ files mapping (important for git):**

| In the editor              | On disk        | Notes                                  |
|----------------------------|----------------|----------------------------------------|
| A scene (tab in Scene dock)| `*.tscn`       | Plain text; diff-able, merge-able      |
| A script attached to a node| `*.gd`         | Plain text GDScript                    |
| A resource (material, etc.)| `*.tres`/`*.res`| Text (`.tres`) or binary (`.res`)     |
| Project config / Autoloads | `project.godot`| Text; Autoloads live in `[autoload]`   |

Set the **main scene** via Project → Project Settings (or it prompts on first run).

---

## 2. GDScript basics

Source: <https://docs.godotengine.org/en/stable/getting_started/step_by_step/scripting_first_script.html>

Every `.gd` file is **implicitly a class**. `extends` declares its base node/class:

```gdscript
extends Sprite2D     # script gains all Sprite2D (and its parents') props/methods
```

> If you omit `extends`, the class implicitly extends `RefCounted` (a plain
> reference-counted object, no node, no scene-tree presence). **This is exactly what
> a pure-logic Autoload like `GameState.gd` does NOT want to be a Node for** — see §5.

**Variables & members.** `var` at the top of the file = a member property (one copy
per instance); `var` inside a function = a local. GDScript is indent-based (tabs
matter — a missing indent is a hard error, not a warning).

```gdscript
var speed = 400
var angular_speed = PI        # angles are radians by default in Godot
```

**Functions.** `func name(args):` then an indented block. Leading-underscore names
are Godot **virtual callbacks** you override (`_ready`, `_process`, `_init`).

```gdscript
func _process(delta):
    rotation += angular_speed * delta
```

**Typing (idioms this project should adopt).** The Getting Started lesson uses
untyped vars for brevity, but typed GDScript is strongly recommended for a
logic-heavy Autoload — it catches errors at parse time and documents intent:

```gdscript
var score_p1: int = 0
var hand: Array[int] = []                 # typed array
const WIN_TARGET: int = 3
@export var blink_interval: float = 0.5   # editable in Inspector

func resolve(a: int, b: int) -> int:      # typed params + return
    ...
```

- `@export var x = ...` exposes `x` as an Inspector field and (importantly) **saves
  it into the `.tscn`**, so designers tweak values without touching code.
- `@onready var n = $Path` defers the assignment until the node is in the tree
  (see §4). `$Timer` is shorthand for `get_node("Timer")`.

---

## 3. Lifecycle callbacks (`_init`, `_ready`, `_process`)

Source: scripting_first_script.html and signals.html (verbatim examples below).

- **`_init()`** — constructor; runs when the object is created in memory, **before**
  it is in the scene tree. No child-node access here.
- **`_ready()`** — runs once, when the node *and all its children* are fully in the
  tree. **This is where you wire up `get_node()` references and connect signals.**
- **`_process(delta)`** — runs every rendered frame; `delta` = seconds since last
  frame, so motion is frame-rate independent. The docs explicitly call out VR:
  > "you might find figures like 30 FPS on slower mobile devices or 90 to 240 for
  > virtual reality games." Quest 3 targets ~72–120 Hz — keep `_process` cheap.
- **`_physics_process(delta)`** — fixed-timestep loop; use this for anything that
  reads/writes physics state (RigidBody forces, etc.). Not shown in Getting Started
  but it's the right loop for physics work — see Gotchas.

Toggle the per-frame loop at runtime:

```gdscript
func _on_button_pressed():
    set_process(not is_processing())   # pause/resume _process()
```

---

## 4. Instancing scenes

Source (editor): <https://docs.godotengine.org/en/stable/getting_started/step_by_step/instancing.html>

A saved `.tscn` is a **blueprint** you can reproduce ("instance") many times. Each
instance is independent: editing one instance's properties overrides the packed
scene *for that instance only*; editing the source `.tscn` updates **all** instances
that haven't overridden that value. In the editor you instance via the **chain/link
icon** in the Scene dock (or drag the `.tscn` from FileSystem onto a parent node).

**Instancing from code** (the docs page covers only editor instancing and points to
"Nodes and scene instances" for code — this is the form the card game needs to spawn
cards/decks at runtime):

```gdscript
# Preferred: preload at parse time (path resolved when the script loads)
const CardScene = preload("res://scenes/Card.tscn")

func deal_card() -> void:
    var card = CardScene.instantiate()   # 4.x name (was .instance() in Godot 3)
    add_child(card)                      # nothing exists in-game until added to tree
    card.global_position = spawn_point.global_position
```

- `preload(path)` loads at script-parse time (fails fast if the path is wrong).
- `load(path)` loads at runtime (use for things you may not always need).
- `PackedScene.instantiate()` creates the node subtree; it is inert until you
  `add_child()` it into the scene tree.
- Paths use the `res://` virtual prefix (project root), not OS paths.

---

## 5. Autoload / Singletons → this is where `GameState.gd` lives

Source: <https://docs.godotengine.org/en/stable/getting_started/introduction/key_concepts_overview.html>
and best-practice page
<https://docs.godotengine.org/en/stable/tutorials/best_practices/autoloads_versus_regular_nodes.html>

An **Autoload** is a script/scene Godot loads once at startup and keeps alive for the
whole game, accessible globally by name. Set it up in:

**Project → Project Settings → Globals → Autoload** → pick the `.gd`/`.tscn`, give it
a **Node Name** (e.g. `GameState`), enable. It is then referenceable anywhere as
`GameState.whatever`. (Older versions label the tab just "Autoload".)

```gdscript
# res://GameState.gd  — registered as Autoload name "GameState"
extends Node          # Autoloads are instantiated as nodes at the tree root

signal round_resolved(winner: int)   # broadcast results to VR scene scripts

var score_p1: int = 0
var score_ai: int = 0
const WIN_TARGET: int = 3

func resolve_throw(player_choice: int, ai_choice: int) -> void:
    var winner := _rps(player_choice, ai_choice)
    if winner == 1: score_p1 += 1
    elif winner == 2: score_ai += 1
    round_resolved.emit(winner)
```

> **Design tension to flag for this project.** The brief says `GameState.gd` is
> *pure logic, no nodes, runs headless*. An Autoload **registered in Project Settings
> is always instantiated as a Node** at the root of the tree (so it can use signals
> and `_ready`). That's fine and idiomatic — "no nodes" should be read as "creates no
> nodes / manipulates no scene geometry", not "isn't a Node". Keep all *rendering /
> VR* concerns out of it. If you genuinely want a non-Node logic object you'd
> `extends RefCounted` and instantiate it manually, but then you lose Autoload's
> global access and built-in signal/`_ready` convenience. Recommendation: keep
> `GameState extends Node`, just never give it visual children.

For headless desktop tests, an Autoload that touches no rendering runs fine under
`godot --headless`. See §8.

---

## 6. Signals — the project's nervous system

Source: <https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html>

Signals are Godot's observer pattern: a node **emits** an event; other code
**connects** a callback. Decouples emitter from listener.

### Connect in code (the 4.x idiom — do this for runtime-created nodes)

The docs' verbatim Timer example — **this is structurally identical to the card
blink loop** (a `Timer` toggling `visible`):

```gdscript
func _ready():
    var timer = get_node("Timer")
    timer.timeout.connect(_on_timer_timeout)   # 4.x: Signal object .connect(Callable)

func _on_timer_timeout():
    visible = not visible        # the card "blink" — toggle each timeout
```

Naming convention for callbacks: `_on_<node>_<signal>` (e.g. `_on_button_pressed`,
`_on_timer_timeout`). The editor's Signals dock auto-generates these names.

### Custom signals

```gdscript
extends Node
signal health_depleted               # no-arg signal

func take_damage(amount):
    health -= amount
    if health <= 0:
        health_depleted.emit()       # 4.x: SignalName.emit()
```

With arguments:

```gdscript
signal health_changed(old_value, new_value)
...
health_changed.emit(old_health, health)
```

> The docs note (verbatim): "As signals represent events that just occurred, we
> generally use an action verb in the **past tense** in their names" → e.g.
> `card_landed`, `round_resolved`, `match_won`.

### Physics signals this project depends on

The Summary section explicitly calls out the pattern the **play zone** uses:
> "an Area2D representing a coin emits a `body_entered` signal whenever the player's
> physics body enters its collision shape."

The 3D equivalent: an **`Area3D`** emits **`body_entered(body)`** / **`body_exited(body)`**
when a `RigidBody3D` (the thrown card) enters/leaves it.

```gdscript
# On the PlayZone (Area3D) script, or wired in the editor's Signals dock:
func _ready():
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
    if body.is_in_group("cards"):
        GameState.register_throw(body)   # hand off to the logic singleton
```

(For an `Area3D` to detect a body, **Monitoring** must be on and the layers/masks
must overlap — see Gotchas.)

---

## 7. Relevance to 土風水競 (concept → where this project uses it)

| Godot concept                       | Where it lands in this project |
|-------------------------------------|--------------------------------|
| **Autoload singleton** (§5)         | `GameState.gd` — RPS resolution, first-to-3 scoring, all pure logic. Registered Project Settings → Autoload as `GameState`. |
| **`extends Node` vs `RefCounted`**  | `GameState` extends `Node` (for signals + Autoload); keeps zero visual children so it stays headless-safe. |
| **Scenes & `.tscn`**                | `Card.tscn` (RigidBody3D + mesh + CollisionShape3D), `PlayZone.tscn` (Area3D), main VR scene. |
| **Instancing from code** (§4)       | `preload("res://.../Card.tscn").instantiate()` + `add_child()` to deal/spawn cards at runtime. |
| **`RigidBody3D` + XRToolsPickable** | The throwable card; grabbed & thrown by the player (template provides the pickable). |
| **`Area3D` + `body_entered`** (§6)  | `PlayZone` detects a card landing → fires callback → calls `GameState`. The single most important signal in the game. |
| **`Timer` + `timeout` signal** (§6) | Card face **blink loop**: `timer.timeout.connect(...)` toggling visibility / swapping the active face — mirrors the docs' blink example exactly. |
| **`StandardMaterial3D.albedo_texture`** | Card face sprite-swap among 4 frames; set `material.albedo_texture = frames[i]` in code (not in the Getting Started scope, but driven by the Timer callback above). |
| **`_ready()`** (§3)                 | Wire up `get_node()` refs and `signal.connect()` on each scene; never in `_init()`. |
| **`_process(delta)` / `_physics_process`** (§3) | Keep light for Quest framerate; physics reads belong in `_physics_process`. |
| **`@export`** (§2)                  | Designer-tunable knobs: `blink_interval`, `throw_force_threshold`, win target — surfaced in Inspector, saved in `.tscn`. |
| **Typed GDScript** (§2)             | `GameState` logic: `Array[int]` hands, `int` scores, typed `-> int` resolution fns for parse-time safety. |
| **Headless run** (§8)              | `godot --headless --script` to unit-test `GameState` RPS/scoring on desktop with no VR/HMD. |
| **Export workflow** (§8)           | Android/Quest export preset to deploy the APK to the Meta Quest 3. |

---

## 8. Beyond Getting Started: headless tests & export (project-critical, brief outside the GS section)

These aren't in the Getting Started lesson body but the project depends on them, so
noted here with the canonical reference.

**Headless / script run** —
<https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html>

```bash
# Run a standalone script (no window, no rendering) — for GameState unit tests
godot --headless --path /path/to/project --script res://tests/test_gamestate.gd
```

A script run this way typically `extends SceneTree` (or `MainLoop`) and Godot calls
its `_initialize()` / `_process()`; from there you can `print()` assertions and
`quit()`. Because `GameState` touches no rendering, it imports and runs cleanly under
`--headless`. (If `GameState` is an Autoload you can also boot a tiny test scene
headless and assert against `GameState.*`.)

**Export to Quest (Android/OpenXR)** —
<https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html>
and the XR export notes. You need: Android SDK + JDK installed and pointed-to in
Editor Settings, an Android export template, an export preset with the OpenXR/Meta
features enabled, then export an APK and `adb install` (or one-click deploy) to the
headset. The IoTone/BowleraramaXR-Godot template should already carry an Android
preset — diff against it before hand-rolling one.

---

## 9. Gotchas / version notes

- **`instantiate()` not `instance()`.** Godot 4 renamed `PackedScene.instance()` →
  `instantiate()`. Any 3.x tutorial/snippet using `.instance()` is wrong for 4.7.
- **Signal connect syntax changed in 4.x.** Use `node.signal_name.connect(callable)`.
  The old `node.connect("signal_name", self, "_method")` string form is Godot 3 and
  is removed/deprecated — don't copy it from older blog posts.
- **`emit()` on the signal object** (`my_signal.emit(args)`) is the 4.x idiom;
  `emit_signal("name", args)` still works but is the older style.
- **Area3D detection requires Monitoring on + overlapping collision layers/masks.**
  A silent "`body_entered` never fires" is almost always a layer/mask mismatch or
  the card's `CollisionShape3D` being disabled/empty. Not covered in Getting Started.
- **`RigidBody3D` state must be driven in `_physics_process`, not `_process`.**
  Reading/writing `linear_velocity`, applying impulses, or moving a body outside the
  physics step causes jitter. The GS lesson only shows `_process` (it moves a
  non-physics Sprite2D) — don't generalize that to the card's RigidBody.
- **Autoload is always a Node instance.** "Pure logic, no nodes" = no *scene
  geometry*, not "not a Node". See §5.
- **`@onready` / `$NodeName` only resolve once the node is in the tree.** Using `$X`
  in `_init()` returns null; do it in `_ready()`.
- **Radians by default.** `rotation`, `angular_speed`, etc. are radians; use
  `deg_to_rad()` / `rad_to_deg()` if you think in degrees.
- **`res://` paths, case-sensitive on export.** Desktop (macOS/Windows) is often
  case-insensitive but the exported Quest (Android) build is **case-sensitive** —
  a `Card.tscn` vs `card.tscn` mismatch passes in-editor and fails on-device.
- **4.x minor-version drift to watch (4.0 → 4.7):** the Getting Started GDScript API
  here is stable across 4.x. The things that *do* shift between minors are mostly
  outside GS — **XR/OpenXR** breaking changes (several per release), **physics**, and
  **rendering** defaults. Before bumping the editor's Godot version, skim the
  relevant "Upgrading from 4.x to 4.y" migration page
  (<https://docs.godotengine.org/en/stable/tutorials/migrating/index.html>), focusing
  on the **XR** and **Physics** subsections, since this project leans on both.
- **`stable` docs ≠ pinned 4.7.** The docs site tracks the latest stable release. If
  4.7 is not the latest stable when you read this, switch the version selector
  (top-left of any docs page) to the matching version to be safe on edge details.
