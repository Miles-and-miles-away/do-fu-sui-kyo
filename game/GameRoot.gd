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
const TABLE_CENTRE := Vector2(0.0, -0.6)  # table-disc centre (x,z) in world space
const TABLE_RADIUS := 0.55  # table-disc radius — inside = rests on top, outside = fell off
const FLOOR_Y := 0.5  # below this (and off the disc) a card has fallen → fly it home

# Card.tscn + the 18 frames grouped per type (R8). Assign ONCE in the inspector here.
# Canonical order (matches docs/SPRITES.md §8 + tools/sprites.py EXPRESSIONS):
#   [neutral, blink, determined, determined_blink, smile, cry]
@export var card_scene: PackedScene
@export var frames_water: Array[Texture2D]  # Fish (WATER)
@export var frames_sky: Array[Texture2D]  # Bird (SKY)
@export var frames_earth: Array[Texture2D]  # Dino (EARTH)

var _slots: Array = []


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
		if not is_instance_valid(c) or not (c is RigidBody3D):
			continue
		if not c.has_meta("home"):  # robot card / not a player hand card
			continue
		if c.freeze:  # hovering, resting, resolved, or mid-return — all settled/controlled
			continue
		if c.has_method("is_picked_up") and c.is_picked_up():  # in the player's hand
			continue
		var pos: Vector3 = c.global_position
		var over_table := Vector2(pos.x, pos.z).distance_to(TABLE_CENTRE) < TABLE_RADIUS
		# Over the disc and at/below the surface → snap flat on top the instant it touches,
		# whatever its speed, so a fast card can never sink through (the edge cases). Off the
		# disc and below floor level → it fell off → fly it home.
		if over_table and pos.y < TABLE_REST_Y + 0.02:
			_rest_on_table(c)
		elif not over_table and pos.y < FLOOR_Y:
			_return_to_slot(c)


# Snap a settled card flat (face-up) onto the table where it lies, frozen so it stays put
# and stops sinking. Still grabbable — XRToolsPickable unfreezes it on the next pickup.
func _rest_on_table(card: RigidBody3D) -> void:
	card.linear_velocity = Vector3.ZERO
	card.angular_velocity = Vector3.ZERO
	var p := card.global_position
	card.freeze = true
	card.global_transform = Transform3D(
		Basis(Vector3.RIGHT, -PI / 2), Vector3(p.x, TABLE_REST_Y, p.z)
	)


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
