# game/RobotPlayer.gd — STUB (wired in Stage 3; DESIGN §8, FSD R15).
# ─────────────────────────────────────────────────────────────────────────────
# Presents the robot's chosen card in the play area each round. The robot does NOT
# grab — it spawns a Card at RobotThrowPoint and either throws it (impulse) or places
# it directly. Both robot and player cards always land in-zone by design (NFR5).
#
# ⚠️ STUB: needs Card.tscn + a per-type texture lookup before it runs. Exercised in
# headset (T15), not by unit tests.
#
# Encodes E14 (card must appear in-zone): physics throw with a direct-placement fallback.
extends Node3D

# Card scene + the 12 frames, grouped per type (R8). Assign in the inspector.
@export var card_scene: PackedScene  # res://game/Card.tscn
@export var frames_water: Array[Texture2D]  # [neutral, blink, smile, cry]
@export var frames_sky: Array[Texture2D]
@export var frames_earth: Array[Texture2D]

# Tunables (FSD §5.1 — venue-calibratable): throw strength, and whether to throw vs place.
@export var throw_impulse: float = 4.0
@export var use_physics_throw: bool = true  # false → place directly (robust fallback)

@onready var _throw_point: Node3D = $"../RobotThrowPoint"
@onready var _play_zone: Area3D = $"../PlayZone"


# Called by PlayZone during resolution. `t` is 0/1/2 (== GameState.Type ordering).
# Returns the spawned Card node so PlayZone can drive its face.
func present_card(t: int) -> Node:
	var card := card_scene.instantiate()
	card.card_type = t
	_apply_frames(card, t)
	get_tree().current_scene.add_child(card)
	card.global_position = _throw_point.global_position

	if use_physics_throw:
		# Aim at the zone and impulse toward it. CCD on the card (F3) guards against
		# tunneling through the trigger at speed.
		var aim := (_play_zone.global_position - card.global_position).normalized()
		card.apply_central_impulse(aim * throw_impulse)
	else:
		# Fallback (E14): drop it straight into the zone — guarantees an in-zone landing
		# if physics tuning is fiddly on the day. The PLAYER's throw is the one that must feel good.
		card.global_position = _play_zone.global_position
	return card


func _apply_frames(card: Node, t: int) -> void:
	var frames: Array[Texture2D]
	match t:
		0:
			frames = frames_water
		1:
			frames = frames_sky
		2:
			frames = frames_earth
	if frames.size() == 4:
		card.tex_neutral = frames[0]
		card.tex_blink = frames[1]
		card.tex_smile = frames[2]
		card.tex_cry = frames[3]
