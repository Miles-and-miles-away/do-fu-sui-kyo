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

# Tunable reveal pause so players see the win/lose reaction before the next round (R21).
@export var reveal_pause: float = 2.0
# Auto-restart delay after game over (R20). ponytail: timer auto-restart is the robust
# default; a grabbable "play again" card is the polish path (DESIGN §7) — add later if wanted.
@export var restart_delay: float = 5.0

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
	var robot_card = _robot.present_card(result.robot_card)  # spawn/place + return the node (R15)

	match result.outcome:
		1:
			player_card.show_smile()
			if robot_card:
				robot_card.show_cry()
		-1:
			player_card.show_cry()
			if robot_card:
				robot_card.show_smile()
		0:
			pass  # draw — both stay neutral/blinking (R7)

	_update_score(result.player_score, result.robot_score)

	if result.game_over:
		_show_end_state(result.player_score >= 3)
	else:
		await get_tree().create_timer(reveal_pause).timeout
		_begin_next_round()


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
