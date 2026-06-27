# game/GameRoot.gd — the ONE logic→scene bridge (DESIGN §4/§7/§10, ASSETS §3).
# ─────────────────────────────────────────────────────────────────────────────
# GameState is headless and holds only Array[Type]. THIS turns that data into
# grabbable Card.tscn instances at the hand slots, and clears them between rounds.
#
# It is also the single Card FACTORY: make_card(type) is used by both the player
# deal here AND by RobotPlayer — so the 12 face frames are assigned in ONE place
# (these exports), never duplicated. One source = no neutral/smile mismatch bugs.
#
# Wired in Stage 2 (ASSETS §7). Exercised in-headset, not by unit tests.
extends Node3D

# Every spawned card joins this group so clear_table() can free the whole table at once,
# whoever spawned it (player deal or robot). StringName literal = no per-call alloc (NFR6).
const CARD_GROUP := &"card"

# Card-landing behaviour (calibrate against the table in main.tscn).
const TABLE_REST_Y := 0.704  # height a card lies flat at — matches PlayZone.table_surface_y
const FELT_CENTRE := Vector2(0.0, -0.6)  # felt circle centre (x,z) — matches FeltCircle/PlayZone
const FELT_RADIUS := 0.25  # felt circle radius — ONLY inside here rests; anywhere else flies home
# Edge-rest rescue: a card (0.1×0.15×0.03 box, face = local +Z) balanced on an edge keeps its
# centre 5–7 cm above the flat-rest height, so the "still airborne" gate below would ignore it
# forever. We catch it once it's stopped AND not lying flat, and lay it down (_rest_on_table eases
# it flat). ponytail: calibrate these two knobs in-headset if the catch fires too eagerly/late.
const REST_SPEED := 0.05  # ≤ this linear (m/s) and angular (rad/s) = the card has stopped moving
const FLAT_FACE_DOT := 0.85  # |card-face · world-up|: above = lying flat, below = up on an edge
# ponytail: distance check, no head collider — head cube is ~0.26 wide, so a 0.2 catch radius
# is generous without snagging cards that merely pass nearby. Tune in-headset if it feels off.
const HEAD_CATCH_RADIUS := 0.2  # HARD easter egg: a card this close to the robot head sticks in it

# Card.tscn + the 18 frames grouped per type (R8). Assign ONCE in the inspector here.
# Canonical order (matches docs/SPRITES.md §8 + tools/sprites.py EXPRESSIONS):
#   [neutral, blink, determined, determined_blink, smile, cry]
@export var card_scene: PackedScene
@export var frames_water: Array[Texture2D]  # Fish (WATER)
@export var frames_sky: Array[Texture2D]  # Bird (SKY)
@export var frames_earth: Array[Texture2D]  # Dino (EARTH)

var _slots: Array = []

@onready var _play_zone: Node = $PlayZone  # resolves the round once a card rests inside the felt
@onready var _robot: Node = $RobotPlayer  # catches a head-thrown card for the HARD easter egg


func _ready() -> void:
	_slots = [$PlayerHandAnchors/Slot0, $PlayerHandAnchors/Slot1, $PlayerHandAnchors/Slot2]
	# GameState (autoload) already ran new_game() in its own _ready(), so player_hand is
	# populated by now (autoloads init before scene nodes). Just present it.
	deal_player_hand()


# Watch each free (thrown, not held) player card and decide where it ends up. Cheap — a
# handful of cards, simple checks (NFR6). Cards heading for the felt enter PlayZone first
# and get frozen there, so they're already skipped by the `freeze` guard.
# ponytail: snap-to-rest instead of trusting thin-card physics — fixes "sinks into the table"
# AND gives grabbable, re-throwable cards in one place.
func _physics_process(_delta: float) -> void:
	for c in get_tree().get_nodes_in_group(CARD_GROUP):
		if not is_instance_valid(c) or not (c is CardFace):
			continue
		var card: CardFace = c  # typed handle — card_type + RigidBody3D members resolve statically,
		# so the rest of the loop is type-checked instead of leaning on Variant (no := inference trap).
		if not card.has_meta("home"):  # robot card / not a player hand card
			continue
		if card.freeze:  # hovering, resting, resolved, or mid-return — all settled/controlled
			continue
		if card.is_picked_up():  # in the player's hand
			continue
		var pos := card.global_position
		# HARD easter egg: a card lobbed into the robot's head sticks there, and the robot plays
		# THAT card next (it picks from its head, not its hand) — so the player rigs the round.
		if (
			GameState.difficulty == GameState.Difficulty.HARD
			and pos.distance_to(_robot.head_position()) < HEAD_CATCH_RADIUS
		):
			GameState.forced_robot_card = card.card_type
			_robot.catch_in_head(card)
			continue
		if pos.y >= TABLE_REST_Y + 0.02:  # centre rides high
			# Usually that means mid-flight — leave the throw alone. EXCEPT a card that has stopped
			# moving up here, with its face NOT pointing up, isn't flying: it's standing on an edge
			# (centre high only because the card stands tall). Fall through so it gets laid flat;
			# anything still moving, or already lying flat (e.g. stacked on another card), is left be.
			var stopped := (
				card.linear_velocity.length() <= REST_SPEED
				and card.angular_velocity.length() <= REST_SPEED
			)
			var lying_flat := absf(card.global_transform.basis.z.dot(Vector3.UP)) > FLAT_FACE_DOT
			if not stopped or lying_flat:
				continue
		# It's settled — a normal landing or a card balanced on an edge. Inside the felt circle it's a
		# play: lay it flat (a smooth ease-out, frozen the instant we catch it so it can't sink
		# through). Anywhere else — outside the circle, or fallen to the floor — it missed → fly it
		# home (R-miss recovery).
		if Vector2(pos.x, pos.z).distance_to(FELT_CENTRE) < FELT_RADIUS:
			_rest_on_table(card)
		else:
			_return_to_slot(card)


# Lay a settled card flat (face-up) where it lies — whether a normal landing or one toppling off
# its edge. settle_to() freezes it (kinematic the instant we call, so a fast card can't sink
# through) and eases it down rather than popping. Still grabbable — XRToolsPickable unfreezes it.
func _rest_on_table(card: CardFace) -> void:
	var p := card.global_position
	card.settle_to(Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(p.x, TABLE_REST_Y, p.z)))
	# A good landing: hand off to PlayZone to gild the ring, throw the robot's card, and score. The
	# settle tween plays in parallel — resolve never moves the card, and its latch ignores re-calls.
	_play_zone.resolve(card)


# A card that fell off the table flies back up to its hovering slot (R-miss recovery).
# freeze = true makes it kinematic (follows the tween) AND keeps the monitor from re-processing
# it — so no "returning" flag is needed; it lands hovering and grabbable.
func _return_to_slot(card: RigidBody3D) -> void:
	card.linear_velocity = Vector3.ZERO
	card.angular_velocity = Vector3.ZERO
	card.freeze = true
	var tw := create_tween()
	tw.tween_property(card, "global_transform", card.get_meta("home"), 0.6)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Card factory (single source of cards + frames) ───────────────────────────
# t is 0/1/2, matching GameState.Type (WATER/SKY/EARTH). Returns an un-parented card;
# the caller add_child()s it where it belongs (slot for player, throw point for robot).
func make_card(t: int) -> Node:
	var card := card_scene.instantiate()
	card.card_type = t
	_apply_frames(card, t)
	card.add_to_group(CARD_GROUP)
	return card


func _apply_frames(card: Node, t: int) -> void:
	var f := _frames_for(t)
	# Assign by index in canonical order; tolerant of a short array (a missing determined pair
	# just won't be set — CardFace falls back to neutral, never breaks).
	var props := [
		"tex_neutral", "tex_blink", "tex_determined", "tex_determined_blink", "tex_smile", "tex_cry"
	]
	for i in mini(f.size(), props.size()):
		card.set(props[i], f[i])


func _frames_for(t: int) -> Array[Texture2D]:
	match t:
		0:
			return frames_water
		1:
			return frames_sky
		_:
			return frames_earth  # 2 = earth; cards are always 0/1/2 (NFR5)


# ── Table presentation ───────────────────────────────────────────────────────
# Free every card on the table (consumed player + robot cards). queue_free is deferred,
# so it's safe to call right before spawning the next hand (new cards aren't in the
# iterated set yet).
func clear_table() -> void:
	for c in get_tree().get_nodes_in_group(CARD_GROUP):
		c.queue_free()


# Rebuild the player's visible hand from GameState.player_hand at the slots (R1, R11).
# Called on new game and after each round (play_round already refilled the data).
func deal_player_hand() -> void:
	clear_table()
	var hand: Array = GameState.player_hand
	for i in mini(hand.size(), _slots.size()):
		var card := make_card(hand[i])
		add_child(card)
		card.global_transform = _slots[i].global_transform
		# Remember where this card hovers — a miss that falls to the floor flies back here.
		# Only player hand cards carry "home"; the robot's card never does, so the monitor
		# below leaves it alone.
		card.set_meta("home", _slots[i].global_transform)
		# Rest at the slot instead of falling off a floating anchor. XRToolsPickable
		# unfreezes the card on release so the throw still flies (R1/R2).
		# ponytail: freeze-at-anchor; swap to an XR Tools snap_zone only if it feels loose in-headset.
		card.freeze = true
