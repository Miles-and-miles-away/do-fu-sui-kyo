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
# Non-positional player: the win/lose stinger is UI feedback, not a world sound (both ears).
var _sfx := AudioStreamPlayer.new()

@onready var _game_root: Node = get_parent()  # GameRoot.gd — owns hand spawning/clearing
@onready var _score_panel: Label3D = $"../ScorePanel"
@onready var _robot: Node = $"../RobotPlayer"  # RobotPlayer.gd, presents the robot's card (R15)
@onready var _felt_mat: ShaderMaterial = $"../FeltCircle".mesh.material  # gilds on a good landing


func _ready() -> void:
	add_child(_sfx)
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
	_set_target_lit(true)  # card's on the felt — gild the rim to confirm a good landing

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
	var won: bool = result.outcome == 1
	_flourish(Color(0.45, 1.0, 0.55) if won else Color(1.0, 0.55, 0.4), 1.3, 24, false)

	if result.game_over:
		_show_end_state(result.player_score >= 3)
	else:
		_play_stinger(result.outcome)  # win/lose/draw each round; game-over plays its own below
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


# Round stinger by outcome (1 win / -1 lose / 0 draw). tools/gen_sfx.py renders these;
# load() (not preload) so a not-yet-imported wav just means silence, never a load failure.
func _play_stinger(outcome: int) -> void:
	var sound := "win" if outcome > 0 else "lose" if outcome < 0 else "draw"
	var stream := load("res://art/%s.wav" % sound)
	if stream:
		_sfx.stream = stream
		_sfx.play()


func _set_target_lit(on: bool) -> void:
	if _felt_mat:
		_felt_mat.set_shader_parameter("active", 1.0 if on else 0.0)


func _update_score(p: int, r: int) -> void:
	if _score_panel:
		# Bilingual scoreline: English over Japanese (おぬし = playful archaic "you") (R18).
		_score_panel.text = "You %d : %d Robot\nおぬし %d : %d ロボット" % [p, r, p, r]
		_score_panel.modulate = Color.WHITE  # clear any held end-game tint on restart


# Pop the score, flash it a colour, and throw a little sparkle when it changes.
# `hold` keeps the colour (end-game banner); otherwise it fades back to white.
func _flourish(tone: Color, grow: float, sparks: int, hold: bool) -> void:
	if not _score_panel:
		return
	_score_panel.modulate = tone
	var pop := create_tween()
	(
		pop
		. tween_property(_score_panel, "scale", Vector3.ONE * grow, 0.12)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		pop
		. tween_property(_score_panel, "scale", Vector3.ONE, 0.3)
		. set_trans(Tween.TRANS_BOUNCE)
		. set_ease(Tween.EASE_OUT)
	)
	if not hold:
		create_tween().tween_property(_score_panel, "modulate", Color.WHITE, 0.5)
	_sparkle(sparks)


# One-shot sparkle burst at the score panel. ponytail: CPUParticles is plenty for a
# ~couple-dozen-spark pop; switch to GPUParticles only if Quest profiling flags it.
func _sparkle(amount: int) -> void:
	if not _score_panel:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.6)
	mat.albedo_color = Color(1.0, 0.95, 0.6)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.014, 0.014)
	quad.material = mat
	var fx := CPUParticles3D.new()
	fx.mesh = quad
	fx.amount = amount
	fx.lifetime = 0.9
	fx.one_shot = true
	fx.explosiveness = 0.95
	fx.spread = 180.0
	fx.initial_velocity_min = 0.4
	fx.initial_velocity_max = 1.0
	fx.gravity = Vector3(0.0, -0.5, 0.0)
	fx.scale_amount_min = 0.5
	fx.scale_amount_max = 1.5
	_score_panel.add_child(fx)
	fx.emitting = true
	await get_tree().create_timer(fx.lifetime + 0.3).timeout
	if is_instance_valid(fx):
		fx.queue_free()


func _begin_next_round() -> void:
	# refill_hands() already ran inside play_round(); GameRoot clears the consumed cards
	# (player + robot, via the "card" group) and respawns the player's refreshed hand (R11).
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_robot.reset_face()  # clear last round's smile/tear
	_set_target_lit(false)  # back to plain felt for the fresh throw
	_round_active = true


func _show_end_state(player_won: bool) -> void:
	if _score_panel:
		# End banner, English over Japanese (R19). お前 = casual "you".
		var win_text := "YOU WIN\nお前の勝ち"
		var lose_text := "YOU LOSE\nお前の負け"
		_score_panel.text = win_text if player_won else lose_text
		_flourish(Color(0.4, 1.0, 0.5) if player_won else Color(1.0, 0.4, 0.4), 1.8, 60, true)
	_play_stinger(1 if player_won else -1)  # game over is win or lose, never a draw
	# Restart (R20): after a pause, start a fresh game and re-deal so the demo loops cleanly.
	await get_tree().create_timer(restart_delay).timeout
	if not is_instance_valid(self):  # zone may be gone if scene reloaded (E13-style guard)
		return
	GameState.new_game()
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_robot.reset_face()  # fresh game → neutral face
	_set_target_lit(false)
	_update_score(0, 0)
	_round_active = true
