# 土風水競 — Design & Build Plan

> **Title:** 土風水競 — coined four-kanji compound, read earth–wind–water–compete
> (土 do · 風 fū · 水 sui · 競 kyō). Chosen for sound.

A 2-day, single-player VR tabletop card game for **Meta Quest 3**, built **from scratch** in
**Godot 4.7** using the **Godot XR Tools** addon for the XR rig and grab/throw. Event:
**XR VisionDevCamp, Fukuoka 2026** (path **P7 — Godot XR**). Headsets (Quest 3 + PICO 4 Ultra)
are provided on-site.

> Built from scratch with the **Godot XR Tools** addon (MIT) for the rig + `XRToolsPickable`
> grab/throw; we build the Quest export ourselves. ⚠️ XR/toolchain setup is the top risk — see §11.

---

## 0. One-paragraph pitch (the demo)

You stand at a table in VR. You hold a hand of three character cards — a Fish, a Bird, a
Dino. You grab one and **throw** it into the arena. A robot opponent tosses one of its own
cards. The two cute critters land face-up, and the winner **smiles** while the loser
**cries** — resolved by rock-paper-scissors rules (water beats sky, sky beats earth, earth
beats water). First to 3 wins. The charm + the physical throw is the whole pitch.

---

## 1. Locked scope (frozen — do not expand)

### IN scope — the only things that ship
- VR table + grabbable/throwable cards (uses Godot XR Tools' `XRToolsPickable` grab + throw).
- A **play-zone `Area3D`** that detects a thrown card landing and triggers resolution.
- **3D Cards** which can be picked up from the central deck and moved to hand. On one facte of the card is a 2D animated image of a sprite.
- **2D sprite-swap faces**: each card has 4 texture frames — neutral / blink / smile / cry.
- **Blink loop** on a timer (swap to blink frame ~every 3–4 s for ~150 ms) to sell "alive."
- **Shared deck** of the 3 types, shuffled.
- **Hand of 3** per side; start with one of each; cards are consumed on play and redrawn.
- Hand **drift**: by round 2+ you may not hold all three types — *this is the game.*
- **Robot**: picks a random-legal card from *its own* hand and throws it.
- RPS resolution → winner smiles, loser cries, draw = both cry.
- **First-to-3** score, shown on a simple panel; round reset; game-over state.
- A fixed **four-button control panel** (Restart / Rules / Track / Language) at the player's right, at
  eyeline and within reach, retro-styled, pressed by fingertip touch or laser; the **Language** toggle
  re-languages all in-game text (EN ⇄ JP), and **Track** cycles the looping background music. (FSD §3.9,
  R32–R37.)

### OUT of scope — do NOT build, even if tempting
- ❌ Multiplayer / networking. Single-player vs robot only.
- ❌ 3D facial rigging, blend shapes, skeletal animation. **Sprite swap only.**
- ❌ Mixed-reality passthrough / surface anchoring. Immersive VR is simpler — use it.
- ❌ Separate decks per player. **One shared deck.** (Decided.)
- ❌ Smart AI that reads the player's hand. **Random-legal only.** (Heuristic = stretch, §9.)
- ❌ Settings menus, best-of-N config, multi-screen tutorials / onboarding. *(The fixed
  Restart/Rules/Language strip + one-screen Rules card is **in** scope — it's not a menu tree.)*
- ❌ More than 3 character types or any deckbuilding meta.
- ❌ Miss handling — **cards always fly true and land in-zone** by design. (Decided.)
- ❌ Sound design beyond the win/lose/draw round stingers (built, §9) and the selectable looping
  background music (Track button, FSD R36–R37) — no ambience or spatialized/positional audio.

> **Rule of thumb:** complexity is allowed to live in exactly one place — the hand/deck
> logic in `GameState.gd`. Everywhere else, take the simplest path.

---

## 2. Game rules (authoritative)

- **Types:** `WATER` (Fish), `SKY` (Bird), `EARTH` (Dino).
- **Beats table:** WATER → beats → SKY; SKY → beats → EARTH; EARTH → beats → WATER.
- **Same type = draw.** No points; both critters **cry** (a draw counts as a loss for both).
- **Round:** player throws one card; robot throws one card; resolve; award a point to the
  winner (none on a draw); both played cards are consumed (discarded).
- **Refill:** after each round, both hands draw back up to 3 from the shared deck.
- **Deck empties:** reshuffle (rebuild) the deck. **Never let it run dry mid-game.**
- **Win:** first side to **3** round wins. Show a win/lose end state, offer restart.

---

## 3. XR foundation — what we use vs build (from scratch)

No fork. We create a **new Godot 4.7 project** (`project.godot` already bootstrapped in-repo)
and add the **Godot XR Tools** addon (MIT) under `addons/godot-xr-tools/`. Godot's built-in
**OpenXR** drives the runtime; XR Tools provides the rig + the `XRToolsPickable` grab/throw
component so we don't hand-roll grab physics. `IoTone/BowleraramaXR-Godot` is **reference-only**
(peek at its folder layout / export settings if stuck) — we do not import its files.

> **"From scratch" ≠ from zero.** XR Tools ships the entire rig as droppable scenes
> (`xr/start_xr.tscn`, `functions/function_pickup.tscn`, hands, `objects/snap_zone.tscn`) **and a
> runnable `scenes/pickable_demo/`**. **Copy that demo's rig + pickup wiring** rather than
> hand-wiring `XROrigin3D` — that's using the addon as intended, not a fork. Its `grab_cube.tscn`
> *is* the Stage 0 bring-up cube; its `saucer.tscn` (a thrown flat disc) is the closest analog to
> a thrown card. Full REUSE-vs-AUTHOR split + node trees: `docs/ASSETS.md` §1.

**The core reframe still holds, minus the inheritance:**
> A **card is a grabbable.** The **play zone is a target `Area3D`.**
> XR Tools solves grab + throw; we solve "did it land in the zone" with a tiny trigger.
> We build a *thin, standard* rig — not a bespoke one — and put all game complexity in `GameState.gd`.

| Need | Source | Action |
|---|---|---|
| XR rig, camera, hands, controllers | **Godot XR Tools** rig: `xr/start_xr.tscn` + `XROrigin3D`/`XRCamera3D`/`XRController3D` ×2 + a `functions/function_pickup.tscn` per controller | **Copy** the addon's `start_xr.tscn` (or lift the `pickable_demo` rig). Keep it conventional — no game logic in the rig (R24). Skip `staging/` (single level, YAGNI). |
| Grab + throw physics | XR Tools **`XRToolsPickable`** (extends `RigidBody3D`; throw velocity injected on release via the controller's `FunctionPickup`) | Use **as-is**. `Card.tscn`'s **root extends `XRToolsPickable`** (so it IS a `RigidBody3D`) + flat mesh/collider; `release_mode = UNFROZEN` so the throw flies. Do not re-implement grab/throw. |
| Quest export / deploy | **We build it:** Android export preset + OpenXR loader (Meta) → "Meta Quest" preset, Runnable | Install Android build template + export templates; configure OpenXR vendor (Meta) per XR Tools deploy docs; `adb` deploy. |
| Play-zone detection | new `Area3D` (`PlayZone.gd`, §7) | Our own trigger; `body_entered`, single-fire latch. ~15 lines incl. the F3 anti-tunnel box. |
| Card face art | `StandardMaterial3D.albedo_texture` swap, **per-instance** override (F2) | Our 2D sprite system; no rigging. |
| AI scene/script generation | (optional) Godot MCP server | Optional, on-ethos; can drive scene wiring via Claude. Not required. |

> ⚠️ **Verify in-editor against the installed XR Tools version** (the addon's API moves between
> Godot minors — see `_dev_notes/godot_tutorials.md`):
> 1. The exact **`XRToolsPickable`** export props + signals (`picked_up`/`dropped`, `enabled`,
>    `release_mode`) in *your* installed addon version. Build `Card.tscn` against what's actually there.
> 2. **OpenXR + Meta vendor plugin** bring-up: enable OpenXR, add the Meta OpenXR vendor (since
>    Godot 4.6 the vendor plugins are optional/separate); confirm a hand/controller renders in-headset.
> 3. **Throw feel for a flat card** — a box collider tumbles differently than a sphere; enable
>    `continuous_cd` and make `PlayZone` generous & not paper-thin (F3, §7, §11).

---

## 4. Scene structure (target)

```
Main (main.tscn — our scene; XR Tools rig at the root)
├── XROrigin3D / XRCamera3D / controllers      # XR Tools standard rig — keep conventional (R24)
│   └── Left/RightHand → FunctionPickup         # pinch-grab cards (existing) +
│                      → Poke                     # NEW — fingertip touch to press the panel (R32)
├── Table (mesh)                                # our mesh (a simple box/plane is fine)
├── GameRoot (Node3D) + GameRoot.gd             # NEW — owns spawning/clearing the player's hand
│   │                                           #   cards from GameState.player_hand (logic→scene glue)
│   ├── PlayerHandAnchors (Node3D)              # 3 slots where player cards rest
│   │   ├── Slot0  ├── Slot1  └── Slot2
│   ├── RobotHandAnchors (Node3D)               # OPTIONAL — only if rendering card-backs; else cut (YAGNI)
│   ├── DrawPile (Node3D)                        # OPTIONAL — STRETCH R28 physical draw; default skip
│   ├── PlayZone (Area3D)                        # NEW — detects landed cards
│   │   └── CollisionShape3D (box, ~table-sized, low)
│   ├── RobotThrowPoint (Node3D)                 # spawn/aim origin for robot's toss
│   └── ScorePanel (Label3D)                      # scoreline / win-lose banner; language per Lang (R18/R35)
├── Hud3D (Viewport2Din3D → game/Hud.tscn)        # NEW — right-side, eyeline, in-reach panel (R32–R35):
│                                                 #   Restart / Rules / Language buttons + Rules overlay,
│                                                 #   clicked by the FunctionPointer laser
├── Environment (Node3D)                          # ✂️ CUT-FIRST ambiance; no game logic (§4.5)
│   └── RoomShell (MeshInstance3D)                # inverted cylinder; STATIC dark shell = default,
│                                                 #   animated Fire/Waves/Wind = STRETCH (R30/R31)
└── AUTOLOADS (not in the tree — Project Settings → Autoload)
    ├── GameState.gd                              # the logic brain (§5)
    ├── Lang.gd                                   # NEW — i18n: jp flag + changed signal + t(en,ja) (R35)
    └── Music.gd                                  # NEW — looping soundtrack + track cycle + jingle duck (R36/R37)
```

> **Control panel — reuse, don't build (§3 ethos).** The buttons are a normal 2D Godot UI built in
> code (`game/Hud.gd` — `Button`s + `StyleBox` retro theme + a side Rules card), shown in 3D by the
> addon's **`Viewport2Din3D`**. The panel sits at the player's right within arm's reach, so the
> primary input is the addon's **`Poke`** (fingertip touch) on each hand; the **`function_pointer`**
> laser also works. Buttons are large and vertically spread; the Rules card opens beside them (never
> covering them) so a second Rules tap closes it. The Restart button reaches `PlayZone.restart()` by
> group call (`"game_control"`); the Language button flips the `Lang` autoload, whose `changed` signal
> every text node (the HUD + `ScorePanel`) re-renders from. **No menu framework, no locale files** —
> two strings per label, two languages, one flag.

`Card.tscn` (instanced, one per physical card):
```
Card  (root extends XRToolsPickable → IS a RigidBody3D)  + CardFace.gd   # grab+throw+face, ONE node
├── CollisionShape3D (BoxShape3D — thin, card-shaped; enable continuous_cd, F3)
└── MeshInstance3D (thin box or quad; front face shows the character)
    └── surface-override material, per-instance, albedo_texture = current frame (F2)
# CardFace.gd extends the addon's pickable.gd, NOT RigidBody3D — one node can't carry two
# RigidBody3D scripts, and PlayZone reads card_type/show_smile() off the body entering the zone.
```

### 4.5 Room environment — circular elemental walls (ambiance)

> **Priority (revised):** the **room shell itself is SHOULD** (a dark inverted cylinder — trivial,
> R29). The **animated Fire/Waves/Wind motifs are STRETCH** (R30/R31) and **cut-first** — default
> to a static low-contrast shell; add the motion only with Day-2-PM slack.

A **circular room** encloses the table: an inverted cylinder shell whose walls carry three
stylized elemental motifs — **Fire, Waves, Wind** — in flat block / SVG-like shapes that move
**constantly but never distract**. Fire **flickers** (mesmerising, irregular), Waves **pulse**
(slow swell + gentle undulation), Wind **drifts** (soft sideways streaks). The walls **rise
above head height** so the motion frames the player without crowding the table.

> Atmosphere only — **no game logic, no game-type coupling.** The wall elements (Fire/Waves/Wind)
> are decorative and intentionally *not* the card types (WATER/SKY/EARTH) — don't imply a mechanic.
> It must not cost framerate (NFR6): GPU-only, and **cut-first** if the headset struggles (§11).

**Lazy build — one cylinder, one shader, three bands, zero GDScript:**
- `RoomShell` = a `CylinderMesh` (or `CSGCylinder3D`) around the table, normals flipped / culling
  off so it's seen from inside, tall enough to clear the camera. Dark, low-contrast base so the
  cards stay the brightest thing in view (non-distracting + face readability).
- One **unshaded spatial shader**, all motion from the built-in `TIME` uniform — no `_process`,
  no per-frame allocation. Three vertical bands keyed off `UV.y`: Fire low (warm reds/oranges),
  Waves mid (blue/teal), Wind high (pale) — the high band is what reaches above the player.
- **Block/SVG look:** build each motif from a few rounded rectangles / bars in the shader
  (stylized, not realistic). No-shader fallback: a small looping sprite-sheet panned on the wall.

Fire is the pattern; Waves/Wind reuse the same `TIME`-driven approach:
```glsl
// wall.gdshader (sketch) — unshaded, emissive, all motion from TIME. Fire band shown.
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float flick_speed = 9.0;   // expose speeds as uniforms → tune "subtle" on-device (§5.1)
void fragment() {
    float flick = 0.85 + 0.15 * sin(TIME*flick_speed + UV.x*40.0) * sin(TIME*5.3); // irregular
    vec3 fire = vec3(1.0, 0.45, 0.1) * flick;
    EMISSION = fire * step(UV.y, 0.33);   // lower third only; ALBEDO dark so it reads as glow
    ALBEDO = vec3(0.02);
}
```
- **Waves pulse:** mid band, EMISSION scaled by a slow swell `0.9 + 0.1*sin(TIME*1.5)` plus a
  gentle vertical UV sine so the bars undulate. Slow = calming, not busy.
- **Wind drift:** high band, faint streaks scrolled sideways `fract(UV.x - TIME*0.05)`, low alpha.
- **Tunable:** expose flicker speed / swell rate / drift speed as shader uniforms so "subtle but
  mesmerising" is dialed in by eye on the headset — same on-site calibration ethos as §5.1.

---

## 5. Core logic — `GameState.gd` (write & test FIRST, headless)

Autoload singleton. **Pure logic, no nodes.** Get this 100% correct on desktop with print
statements *before* touching VR. This is the single highest-leverage hour of the hackathon.

```gdscript
# GameState.gd — Autoload singleton (Project Settings → Autoload → name "GameState").
# Pure logic, no 3D. Unit-test via _ready() print loop on desktop before any VR wiring.
extends Node

enum Type { WATER, SKY, EARTH }   # fish, bird, dino

var deck: Array[Type] = []
var player_hand: Array[Type] = []
var robot_hand: Array[Type] = []
var player_score := 0
var robot_score := 0

const TYPE_NAMES := { Type.WATER: "Fish", Type.SKY: "Bird", Type.EARTH: "Dino" }

func _ready() -> void:
	new_game()

func new_game() -> void:
	player_score = 0
	robot_score = 0
	_build_deck()
	# Both start with one of each, per spec.
	player_hand = [Type.WATER, Type.SKY, Type.EARTH]
	robot_hand  = [Type.WATER, Type.SKY, Type.EARTH]

func _build_deck() -> void:
	deck.clear()
	# 6 copies of each type → 18 cards. Tune if needed; just needs to outlast a 3-win game.
	for _i in 6:
		deck.append_array([Type.WATER, Type.SKY, Type.EARTH])
	deck.shuffle()

func draw_one() -> Type:
	if deck.is_empty():
		_build_deck()                 # reshuffle guard — prevents mid-demo crash
	return deck.pop_back()

func refill_hands() -> void:           # call after each round resolves
	while player_hand.size() < 3: player_hand.append(draw_one())
	while robot_hand.size()  < 3: robot_hand.append(draw_one())

func robot_pick() -> Type:             # random-legal from robot's OWN hand
	var i := randi() % robot_hand.size()
	return robot_hand.pop_at(i)

# Returns: 1 = player wins, -1 = robot wins, 0 = draw
func resolve(p: Type, r: Type) -> int:
	if p == r: return 0
	var beats := { Type.WATER: Type.SKY, Type.SKY: Type.EARTH, Type.EARTH: Type.WATER }
	return 1 if beats[p] == r else -1

# Call when the player's thrown card lands in the PlayZone.
# Returns a dictionary the VR layer uses to drive sprites + score.
func play_round(player_card: Type) -> Dictionary:
	player_hand.erase(player_card)
	var robot_card := robot_pick()
	var outcome := resolve(player_card, robot_card)
	if outcome > 0: player_score += 1
	elif outcome < 0: robot_score += 1
	refill_hands()
	return {
		"player_card": player_card,
		"robot_card": robot_card,
		"outcome": outcome,            # 1 / -1 / 0
		"player_score": player_score,
		"robot_score": robot_score,
		"game_over": game_over(),
	}

func game_over() -> bool:
	return player_score >= 3 or robot_score >= 3
```

### Headless self-test (Day 1 PM — run on desktop, NO VR)
Drop this in a throwaway scene's `_ready()` or a `test.gd` to confirm logic before VR:
```gdscript
func _ready() -> void:
	var gs := GameState
	gs.new_game()
	for round_i in 10:
		if gs.game_over(): break
		# Simulate: player throws first card in hand
		var pick = gs.player_hand[0]
		var res := gs.play_round(pick)
		print("R%d  you:%s robot:%s  -> %s  (%d–%d)  deck:%d" % [
			round_i, gs.TYPE_NAMES[res.player_card], gs.TYPE_NAMES[res.robot_card],
			["DRAW","WIN","LOSE"][res.outcome] if res.outcome >= 0 else "LOSE",
			res.player_score, res.robot_score, gs.deck.size()])
	print("GAME OVER  you:%d robot:%d" % [gs.player_score, gs.robot_score])
```
**Pass criteria:** scores only ever increment by 1; hands always refill to 3; deck never
errors when emptied; game ends exactly when someone hits 3.

### Tests folder — formalize the self-test (`tests/`)
`GameState.gd` is the only non-trivial logic in the game, so it gets the only real tests.
Promote the print-loop above into **assert-based** checks that fail loudly, in a `tests/`
folder (pattern borrowed from `db0/godot-card-game-framework`, which ships a `tests/` dir):

- `tests/test_game_state.gd` — headless script (`godot --headless --script ...`) that asserts:
  - `resolve()` correct for all **9** type pairs (the RPS truth table);
  - after `play_round()`, both hands `== 3` (unless game over);
  - draining the deck never errors and never returns empty (rebuild guard holds);
  - score steps by exactly 1, never on a draw;
  - `game_over()` true **iff** a side has 3.
- `seed(<fixed>)` at the top so runs are reproducible.

This *is* FSD §9 tests **T1–T9**. **GUT** (Godot Unit Test — the addon db0 uses) is optional:
worth it only if you want a runner/report; for a 2-day build one assert script is enough.
Test `GameState.gd` only — do **not** unit-test the VR/scene layer; verify that in-headset (§10).

---

## 6. Card face — sprite swap (`CardFace.gd`)

Each card's front material has its `albedo_texture` swapped among 6 frames. No rigging.

```gdscript
# CardFace.gd — ROOT script of Card.tscn. Holds the 6 expression frames + blink loop.
# Extends the addon's pickable so ONE node is grabbable/throwable AND owns its face — a node
# can't carry two RigidBody3D scripts, and PlayZone reads card_type/show_smile() off the body
# that enters the zone. (Early drafts wrote `extends RigidBody3D`; the pickable IS a RigidBody3D.)
extends "res://addons/godot-xr-tools/objects/pickable.gd"   # XRToolsPickable, a RigidBody3D

@export var card_type: GameState.Type
@export var tex_neutral: Texture2D
@export var tex_blink: Texture2D
@export var tex_determined: Texture2D        # shown while the card is held
@export var tex_determined_blink: Texture2D  # determined, eyes closed (blink while held)
@export var tex_smile: Texture2D
@export var tex_cry: Texture2D

@onready var _mat: StandardMaterial3D = $MeshInstance3D.get_surface_override_material(0)
var _blink_timer: Timer
var _locked := false   # once played + emoting, stop blinking

func _ready() -> void:
	_set(tex_neutral)
	_blink_timer = Timer.new()
	add_child(_blink_timer)
	_blink_timer.timeout.connect(_do_blink)
	_schedule_blink()

func _set(t: Texture2D) -> void:
	if _mat: _mat.albedo_texture = t

func _schedule_blink() -> void:
	_blink_timer.start(randf_range(3.0, 4.5))

func _do_blink() -> void:
	if _locked: return
	_set(tex_blink)
	await get_tree().create_timer(0.15).timeout
	if not _locked: _set(tex_neutral)
	_schedule_blink()

func show_smile() -> void:
	_locked = true
	_set(tex_smile)

func show_cry() -> void:
	_locked = true
	_set(tex_cry)
```

**Art needed:** 3 critters × 6 frames = **18 small images** (front-facing, consistent
framing). Generate with an image tool (on-ethos for the event). Keep them square, same
crop, transparent or solid background — consistency matters more than polish.

---

## 7. Play-zone trigger + round wiring (`PlayZone.gd`)

```gdscript
# PlayZone.gd — attach to the Area3D. Fires when a thrown card enters.
extends Area3D

@onready var score_panel := $"../ScorePanel"   # adjust path
var _round_active := true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not _round_active: return
	if not body.has_method("show_smile"): return     # it's a Card
	_round_active = false

	var result := GameState.play_round(body.card_type)

	# Drive the two played cards' faces.
	var player_card := body
	var robot_card := _spawn_robot_card(result.robot_card)   # see §8
	match result.outcome:
		1:  player_card.show_smile(); robot_card.show_cry()
		-1: player_card.show_cry();   robot_card.show_smile()
		0:  player_card.show_cry(); robot_card.show_cry()   # draw = loss for both

	_update_score(result.player_score, result.robot_score)
	_play_stinger(result.outcome)   # win/lose/draw audio; end state plays its own win/lose (§9)

	if result.game_over:
		_show_end_state(result.player_score >= 3)
	else:
		await get_tree().create_timer(2.0).timeout   # let players see the reaction
		_begin_next_round()

func _update_score(p: int, r: int) -> void:
	score_panel.text = "You %d — %d Robot" % [p, r]

func _begin_next_round() -> void:
	# refill_hands() already ran inside play_round(). GameRoot.gd owns the visuals — call into it
	# here to clear consumed cards and spawn the player's refreshed hand at the slots.
	# Physical draw from DrawPile is STRETCH (R28); default = GameRoot auto-spawns the refill.
	_round_active = true

func _show_end_state(player_won: bool) -> void:
	score_panel.text = Lang.t("YOU WIN", "お前の勝ち") if player_won else Lang.t("YOU LOSE", "お前の負け")
	# Restart (R20/R33): auto-restart after a pause → restart(false); the panel's Restart button
	# calls restart(true) (also recenters the player). One restart() path, reused. A _gen counter
	# lets a mid-round restart cancel this round's in-flight awaits.
```

---

## 8. Robot character (`RobotPlayer.gd`)

The robot is a **wireframe character** standing opposite the player: a glowing line-mesh
body built procedurally from `ArrayMesh` `PRIMITIVE_LINES` (no model file, no rig, no skeletal
animation — fits the headless export loop, every colour/timing an `@export`). The arm and head
are separate pivot nodes that **aim with the built-in `look_at()`** — the lazy distillation of
godot-demo-projects `3d/ik` (its look-at IK boils down to `Transform3D.looking_at`), so there's
**no Skeleton3D / IK solver**. On its turn the arm `look_at()`s its deck, picks a card up, then
`look_at()`s the table spot to lay it — the claw always points where the card goes, no pose
angles to tune. The head continuously `look_at()`s the player for life. The played `Card.tscn`
(built by `GameRoot.make_card`, so frames stay single-sourced) glides deck → table in parallel
with the arm, then `PlayZone` snaps it flat at its spot after the settle window.

```gdscript
# RobotPlayer.present_card(t, lay_pos): make the card, animate the arm laying it at lay_pos,
# return the node immediately so PlayZone can flip its face after settle (R15).
func present_card(t: int, lay_pos: Vector3) -> Node:
	var card: RigidBody3D = _game_root.make_card(t)   # single card factory (frames live there)
	get_tree().current_scene.add_child(card)
	card.freeze = true                                # carried kinematically, no gravity
	card.global_position = deck_point
	_play_card(card, lay_pos)                         # async: arm rest→pick→place + card arc
	return card
```
> Both robot and player cards always end up in-zone (NFR5). The arm is a believable *gesture*
> (no IK) — the card's landing is snapped to `lay_pos`, so the reach never has to be exact;
> the player's throw is the one that must feel good. Tune arm poses/timing in-headset (§5.1).

---

## 9. Stretch goals (only if Day 2 PM has slack — never before)

- **Round audio — BUILT (R25).** Win/lose/draw stingers through one `AudioStreamPlayer`; each
  round plays its outcome, game-over plays win/lose. Synthesized by `tools/gen_sfx.py` (stdlib,
  no deps) → `art/{win,lose,draw}.wav`; re-run after tweaking, then re-import in Godot.
- **Card glow / controller haptic** on a win (juice; XR Tools exposes haptics).
- **Robot heuristic:** if it holds the counter to the player's most-played type, prefer it.
  One-line bias over random; *apparent* intelligence, cheap. Stays "picks from own hand."
- **Physical draw beat:** player literally grabs the refill card from `DrawPile`.

---

## 10. Day-by-day plan

**Stage 0 — prove the pipeline (toolchain before code)**
- **New Godot 4.7 project** (already bootstrapped in-repo). Install matching export templates +
  the Android build template. Add the **Godot XR Tools** addon under `addons/`; enable OpenXR +
  the Meta OpenXR vendor. Enable Quest dev mode, accept USB debug *inside the headset*, confirm
  `adb devices`.
- **Deploy a minimal XR bring-up build to a Quest first**: copy the addon's `xr/start_xr.tscn`
  rig + a `function_pickup` per controller (or lift the whole `scenes/pickable_demo/` rig) with
  one grabbable test cube (= the addon's `grab_cube.tscn`), nothing else. Prove rig renders +
  grab + export/deploy **before** any game code. Never debug your code and the toolchain together.
- Build `Card.tscn` with its root extending `XRToolsPickable` (start from `saucer.tscn`'s tuning),
  flat mesh/collider (CCD on). Confirm grab + throw in-headset.

**Stage 1 — the brain, headless**
- Write `GameState.gd`; add as Autoload. Run the §5 self-test on **desktop** (no VR).
- Pass criteria in §5 all green before moving on.

**Stage 2 — wire VR to brain + art**
- Generate 18 sprites; build a `type → {neutral,blink,determined,determined_blink,smile,cry}` lookup.
- `CardFace.gd` as the `Card.tscn` root (extends `XRToolsPickable`, §6); blink timer working.
- `GameRoot.gd` spawns the player's hand cards from `GameState.player_hand` into the slots
  (initial deal + post-round refill) and clears consumed cards — the logic→scene glue.
- `PlayZone` `Area3D` → `GameState.play_round()`; smile/cry swap on the two played cards.

**Stage 3 — robot, draw, juice, REHEARSE**
- Robot throw (`RobotPlayer.gd`); score panel; round reset; first-to-3 end state.
- Then **stop adding features.** Tune throw feel. Rehearse a 90-second demo run.

---

## 11. Top risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Toolchain/export eats Day 1 — building the XR rig + Quest export from scratch | **High** | **Copy the addon's `pickable_demo` rig + `grab_cube` rather than hand-wiring `XROrigin3D`** — XR Tools ships the whole rig (ASSETS §1), so this is mostly config, not authoring. Deploy that **minimal bring-up build (rig + grab cube) first**, before any game code; follow XR Tools' Quest deploy docs exactly. Godot 4.7 + matching export + Android build templates. Budget all of Stage 0 for this. |
| Flat-card throw feels janky (tumbles, lands on edge) | High | Fatten collider; consider locking rotation; PlayZone box is generous + low so *any* entry counts. Budget Day-2 buffer. |
| Scope creep (esp. into the deck/hand layer) | Medium | Scope is frozen (§1). Complexity allowed only in `GameState.gd`. |
| Deck empties → crash mid-demo | Medium | `draw_one()` rebuilds on empty (already handled). Don't remove that guard. |
| Sprite framing inconsistent (jumpy faces) | Medium | Same crop/size/background for all 18 frames; check side-by-side before wiring. |
| Title *feel* off in JP (ordering/feng-shui echo) | Medium | Native speaker check at venue; 土空水競 (earth-sky-water) as exact-match fallback. |
| Animated walls cost framerate on Quest 3 | Medium | GPU shader only (`TIME`-driven), no per-frame GDScript; dim low-poly cylinder. Ambiance is **cut-first** — if it hitches, drop to a static painted shell (§4.5). |

---

## 12. Definition of done (demo-ready)

- [ ] Builds and runs on a Quest 3 from the Meta Quest preset.
- [ ] Player can grab and throw a card into the play zone reliably.
- [ ] Robot throws/reveals a card each round.
- [ ] Correct RPS resolution; winner smiles, loser cries, draw = both cry.
- [ ] Card characters blink at rest.
- [ ] Hand of 3 consumes + refills from the shared deck; hands drift over rounds.
- [ ] Score panel updates; first-to-3 ends the game; restart possible.
- [ ] Control panel works: Restart resets + recenters, Rules card shows, Language flips all text (EN ⇄ JP), Track cycles music.
- [ ] Background music loops from launch (retro-gaming) and ducks for the win/lose/draw jingle.
- [ ] A clean 90-second demo run rehearsed end-to-end.

---

## 13. Open threads / decisions log

- **DECIDED:** First-to-3 · shared deck · random-legal robot · cards always land in-zone ·
  2D sprite-swap faces (no rigging) · throw-to-play (not place) · single-player only.
- **DECIDED:** Robot is a procedural **wireframe character** opposite the player that reaches
  out, picks a card up, and lays it on the table (arm tween, no rig/IK; card landing snapped).
  Supersedes the earlier "robot card uses a physics throw" — the animated lay-down replaced it.
- **CORRECTED:** Physical draw-from-pile beat is **STRETCH** (FSD R28); **default = `GameRoot`
  auto-spawns the refill** (no `DrawPile` grab). An earlier draft wrongly listed this as committed.
- **REVISED:** Circular elemental room (§4.5) is ambiance outside the §1 frozen core. **Room shell
  = SHOULD** (a dark inverted cylinder); **animated Fire/Waves/Wind motifs = STRETCH / cut-first**
  (FSD R29 vs R30/R31) — default to a static shell, animate only with Day-2-PM slack.
- **DECIDED:** From-scratch Godot 4.7 project + **Godot XR Tools** addon for the rig +
  `XRToolsPickable`; we build the Quest export ourselves (§3). **The addon ships the full rig + a
  runnable `pickable_demo` — copy it, don't hand-wire** (ASSETS §1).
- **DECIDED (build structure):** `Card.tscn`'s **root extends `XRToolsPickable`** (a `RigidBody3D`)
  and carries `CardFace.gd` — one node is grabbable *and* owns its face, so `PlayZone` reads
  `card_type`/`show_smile()` off the entering body (§4, §6).
- **DECIDED (glue):** a `GameRoot.gd` presenter spawns/clears the player's hand cards from
  `GameState.player_hand` — the only logic→scene bridge (§4, §7, §10 Stage 2).
- **DECIDED:** Restart (R20/R33) = the control panel's **Restart button** → `PlayZone.restart()`
  (`GameState.new_game()`, `GameRoot` respawns hands, robot face reset, button-only player recenter),
  plus an auto-restart after the end state. A `_gen` counter cancels a mid-round restart's in-flight
  awaits. **Supersedes** the earlier "grabbable play-again card" — a button is one place and also
  covers on-demand mid-game restarts.
- **DECIDED:** In-game **control panel + language toggle** (R32–R35) = XR Tools `Viewport2Din3D`
  rendering a code-built retro 2D UI (`game/Hud.gd`/`Hud.tscn`), pressed by an XR Tools `Poke`
  (fingertip touch) on each hand or the `function_pointer` laser. i18n is one autoload, `game/Lang.gd`
  (`jp` flag + `changed` signal + `t(en, ja)`); every label is a `Lang.t(...)` call so the toggle
  re-languages the whole game. No menu framework, no locale files. *(The panel was moved to the
  player's right at eyeline/in-reach so touch works; an earlier draft put it on the far wall = laser-only.)*
- **DECIDED:** **Background music** (R36–R37) = one autoload `game/Music.gd` — a looping
  `AudioStreamPlayer` over `music/`, opening on retro-gaming; the music control is a split button
  (play/pause + skip; `next_track()` returns the name for a ~2 s HUD popup); `duck()`/`resume()` pause it
  around a jingle (PlayZone, on stinger play / `_sfx.finished`). Track list is the whole config.
- **VERIFY IN EDITOR:** `XRToolsPickable` API in the installed XR Tools version (props/signals);
  OpenXR + Meta vendor bring-up renders in-headset; flat-card collider behavior + CCD (§3, §7).
- **See `docs/ASSETS.md`** — full node/scene/asset manifest, collision layers, import settings.
