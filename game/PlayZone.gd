# game/PlayZone.gd — STUB (wired in Stage 2/3; DESIGN §7, FSD R3/R7/R18–R22).
# ─────────────────────────────────────────────────────────────────────────────
# Attach to the PlayZone Area3D. Fires once when a thrown card lands, calls the brain
# (GameState.play_round), drives the two cards' faces, updates score, and paces the round.
#
# ⚠️ STUB: node paths ($"../ScorePanel" etc.) resolve once the scene is authored.
#
# Encodes E10 (single-fire latch) and references finding F3 (anti-tunnel collider — set
# on the Area3D's CollisionShape3D in-editor, NOT here): make the box generous & not
# paper-thin, enable continuous_cd on cards, raise physics ticks (done in project.godot).
extends Area3D

# Time the robot gets to reach out and lay its card down before the win/lose verdict (R21).
# Must be ≥ RobotPlayer reach+wind+flight (default 1.08) so the thrown card has landed.
@export var settle_time: float = 1.1
# After the verdict faces show, how long to view them before the next round.
@export var reveal_pause: float = 2.0
# Auto-restart delay after game over (R20). ponytail: timer auto-restart is the robust
# default; a grabbable "play again" card is the polish path (DESIGN §7) — add later if wanted.
@export var restart_delay: float = 5.0
# Flat-landing layout (calibrate in-headset): table-top height the cards rest at, and the
# x-offset each card sits from the zone centre so player's and robot's cards never overlap.
@export var table_surface_y: float = 0.704
@export var card_spread: float = 0.1

var _round_active := true

@onready var _game_root: Node = get_parent()  # GameRoot.gd — owns hand spawning/clearing
@onready var _score_panel: Label3D = $"../ScorePanel"
@onready var _robot: Node = $"../RobotPlayer"  # RobotPlayer.gd, presents the robot's card (R15)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_score(0, 0)


func _on_body_entered(body: Node) -> void:
	# Single resolution per round: ignore further entries until the next round (R3, R22, E10).
	if not _round_active:
		return
	# Only react to cards (they expose show_smile()); ignore stray bodies.
	if not body.has_method("show_smile"):
		return
	_round_active = false

	# The brain does ALL rules; we only translate its result to visuals (R23/NFR8).
	var result: Dictionary = GameState.play_round(body.card_type)

	var player_card := body
	# The felt is a pure trigger: the player's thrown card is LEFT to fall and rest wherever it
	# lands inside the circle (GameRoot's monitor snaps it flat on contact) — no teleport to a
	# fixed spot, so the throw keeps its realism. Entering the felt is what makes the robot throw.
	var centre: Vector3 = global_position
	var robot_pos := Vector3(centre.x + card_spread, table_surface_y, centre.z)
	var robot_card = _robot.present_card(result.robot_card, robot_pos)

	# Wait for the robot to finish laying its card, THEN snap it flat & flip the verdict (R21).
	# settle_time must cover the robot's reach+wind+throw flight (RobotPlayer reach/wind/flight times).
	await get_tree().create_timer(settle_time).timeout
	if not is_instance_valid(self) or not is_instance_valid(player_card):
		return
	if is_instance_valid(robot_card):
		_place_flat(robot_card, robot_pos)

	match result.outcome:
		1:
			player_card.show_smile()
			if is_instance_valid(robot_card):
				robot_card.show_cry()
			_robot.show_loss()  # robot's face tears up
		-1:
			player_card.show_cry()
			if is_instance_valid(robot_card):
				robot_card.show_smile()
			_robot.show_win()  # robot's face smiles
		0:
			# Same card played — counts as a loss for both, so both cry.
			player_card.show_cry()
			if is_instance_valid(robot_card):
				robot_card.show_cry()
			_robot.show_loss()

	_update_score(result.player_score, result.robot_score)

	if result.game_over:
		_show_end_state(result.player_score >= 3)
	else:
		await get_tree().create_timer(reveal_pause).timeout
		if not is_instance_valid(self):
			return
		_begin_next_round()


# Snap a thrown card flat (face-up) and frozen onto the table at `pos`. The card's quad
# faces +Z, so tipping it -90° about X points the face straight up. ponytail: snap-flat is
# the robust default — thin cards land on edge otherwise; revisit if a physics rest looks better.
func _place_flat(card: Node, pos: Vector3) -> void:
	if not is_instance_valid(card):
		return
	if card is RigidBody3D:
		card.linear_velocity = Vector3.ZERO
		card.angular_velocity = Vector3.ZERO
		card.freeze = true
	card.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), pos)


func _update_score(p: int, r: int) -> void:
	if _score_panel:
		_score_panel.text = "You %d — %d Robot" % [p, r]  # R18


func _begin_next_round() -> void:
	# refill_hands() already ran inside play_round(); GameRoot clears the consumed cards
	# (player + robot, via the "card" group) and respawns the player's refreshed hand (R11).
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_round_active = true


func _show_end_state(player_won: bool) -> void:
	if _score_panel:
		_score_panel.text = "YOU WIN!" if player_won else "ROBOT WINS"  # R19
	# Restart (R20): after a pause, start a fresh game and re-deal so the demo loops cleanly.
	await get_tree().create_timer(restart_delay).timeout
	if not is_instance_valid(self):  # zone may be gone if scene reloaded (E13-style guard)
		return
	GameState.new_game()
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_update_score(0, 0)
	_round_active = true
