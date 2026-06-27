# game/RobotPlayer.gd — presents the robot's chosen card in the play area (DESIGN §8, FSD R15).
# ─────────────────────────────────────────────────────────────────────────────
# The robot does NOT grab. It asks GameRoot (the single card factory) for a card of the
# chosen type, spawns it at RobotThrowPoint, and either throws it (impulse) toward the
# zone or places it directly. Both robot and player cards always land in-zone (NFR5).
#
# ⚠️ STUB: exercised in-headset (T15), not by unit tests. Throw magnitude is tuned on device.
# Encodes E14 (card must appear in-zone): physics throw with a direct-placement fallback.
extends Node3D

# Tunables (FSD §5.1 — venue-calibratable): throw strength, and whether to throw vs place.
@export var throw_impulse: float = 4.0
@export var use_physics_throw: bool = true  # false → place directly (robust fallback)

@onready var _game_root: Node = get_parent()  # GameRoot.gd — the card factory (frames live there)
@onready var _throw_point: Node3D = $"../RobotThrowPoint"
@onready var _play_zone: Area3D = $"../PlayZone"


# Called by PlayZone during resolution. `t` is 0/1/2 (== GameState.Type ordering).
# Returns the spawned Card node so PlayZone can drive its face. null if it can't build one.
func present_card(t: int) -> Node:
	if not (_game_root and _game_root.has_method("make_card")):
		push_warning("RobotPlayer: GameRoot factory missing; cannot present robot card")
		return null
	var card: RigidBody3D = _game_root.make_card(t)
	get_tree().current_scene.add_child(card)
	card.global_position = _throw_point.global_position

	if use_physics_throw:
		# Aim at the zone and impulse toward it. CCD on the card (F3) guards against
		# tunneling through the trigger at speed.
		var aim: Vector3 = (_play_zone.global_position - card.global_position).normalized()
		card.apply_central_impulse(aim * throw_impulse)
	else:
		# Fallback (E14): drop it straight into the zone — guarantees an in-zone landing
		# if physics tuning is fiddly. The PLAYER's throw is the one that must feel good.
		card.global_position = _play_zone.global_position
	return card
