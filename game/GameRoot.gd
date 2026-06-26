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

# Card.tscn + the 12 frames grouped per type (R8). Assign ONCE in the inspector here.
@export var card_scene: PackedScene
@export var frames_water: Array[Texture2D]  # [neutral, blink, smile, cry]  (Fish)
@export var frames_sky: Array[Texture2D]  # [neutral, blink, smile, cry]  (Bird)
@export var frames_earth: Array[Texture2D]  # [neutral, blink, smile, cry]  (Dino)

var _slots: Array = []


func _ready() -> void:
	_slots = [$PlayerHandAnchors/Slot0, $PlayerHandAnchors/Slot1, $PlayerHandAnchors/Slot2]
	# GameState (autoload) already ran new_game() in its own _ready(), so player_hand is
	# populated by now (autoloads init before scene nodes). Just present it.
	deal_player_hand()


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
	if f.size() == 4:
		card.tex_neutral = f[0]
		card.tex_blink = f[1]
		card.tex_smile = f[2]
		card.tex_cry = f[3]


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
		# Rest at the slot instead of falling off a floating anchor. XRToolsPickable
		# unfreezes the card on release so the throw still flies (R1/R2).
		# ponytail: freeze-at-anchor; swap to an XR Tools snap_zone only if it feels loose in-headset.
		card.freeze = true
