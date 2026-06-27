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

# Floated in the middle as the win celebration (player-victory only). 1500×1500.
const ICON := preload("res://art/icon.png")

# Time the robot gets to reach out and lay its card down before the win/lose verdict (R21).
# Must be ≥ RobotPlayer reach+wind+flight (default 1.08) so the thrown card has landed.
@export var settle_time: float = 1.1
# After the verdict faces show, how long to view them before the next round.
@export var reveal_pause: float = 2.0
# Flat-landing layout (calibrate in-headset): table-top height the cards rest at, and the
# x-offset each card sits from the zone centre so player's and robot's cards never overlap.
@export var table_surface_y: float = 0.704
@export var card_spread: float = 0.1

var _round_active := true
# Last score shown + whether the game has ended (0 none / 1 player won / 2 player lost), so a
# mid-game language toggle can re-render the current panel in the new language (Lang.changed).
var _score := Vector2i.ZERO
var _ended := 0
# Bumped on every restart so an in-flight round's awaits can bail instead of dealing over a
# fresh hand (a player can hit Restart mid-round). ponytail: a counter is the cheap guard.
var _gen := 0
# Non-positional player: the win/lose stinger is UI feedback, not a world sound (both ears).
var _sfx := AudioStreamPlayer.new()
# Win celebration node (icon + fireworks); held so a restart can clear it mid-show.
var _party: Node3D

@onready var _game_root: Node = get_parent()  # GameRoot.gd — owns hand spawning/clearing
@onready var _score_panel: Label3D = $"../ScorePanel"
@onready var _robot: Node = $"../RobotPlayer"  # RobotPlayer.gd, presents the robot's card (R15)
@onready var _felt_mat: ShaderMaterial = $"../FeltCircle".mesh.material  # gilds on a good landing
@onready var _xr_origin: XROrigin3D = $"../../XRRig/XROrigin3D"

# The rig's authored start offset (eyeline of the robot, sized to the table). center_on_hmd would
# clobber it from the live HMD pose and drop the player to the floor, so reset just restores this.
@onready var _start_xform: Transform3D = _xr_origin.transform


func _ready() -> void:
	add_child(_sfx)
	# Resume the background music once a jingle finishes (it's ducked while the sting plays).
	_sfx.finished.connect(Music.resume)
	# GameRoot drives resolution: it calls resolve() once a thrown card SETTLES ≥50% inside the
	# felt (centre within FELT_RADIUS). The Area3D's own body_entered isn't used — it would fire
	# on any edge-clip while the card's still airborne, before we know where it actually lands.
	# Restart button (Hud) reaches us by group; language toggle re-renders the live panel.
	add_to_group("game_control")
	Lang.changed.connect(_on_lang_changed)
	_update_score(0, 0)


# Called by GameRoot when a thrown player card comes to rest ≥50% inside the felt circle.
func resolve(card: Node) -> void:
	# Single resolution per round: ignore further landings until the next round (R3, R22, E10).
	if not _round_active:
		return
	# Only react to cards (they expose show_smile()); ignore stray bodies.
	if not card.has_method("show_smile"):
		return
	_round_active = false
	var gen := _gen  # if Restart bumps this mid-round, the awaits below bail out
	_set_target_lit(true)  # card's on the felt — gild the rim to confirm a good landing

	# The brain does ALL rules; we only translate its result to visuals (R23/NFR8).
	var result: Dictionary = GameState.play_round(card.card_type)

	var player_card := card
	# The felt is a pure trigger: the player's thrown card is LEFT to fall and rest wherever it
	# lands inside the circle (GameRoot's monitor snaps it flat on contact) — no teleport to a
	# fixed spot, so the throw keeps its realism. Entering the felt is what makes the robot throw.
	var centre: Vector3 = global_position
	var robot_pos := Vector3(centre.x + card_spread, table_surface_y, centre.z)
	var robot_card = _robot.present_card(result.robot_card, robot_pos)

	# Wait for the robot to finish laying its card, THEN snap it flat & flip the verdict (R21).
	# settle_time must cover the robot's reach+wind+throw flight (RobotPlayer reach/wind/flight times).
	await get_tree().create_timer(settle_time).timeout
	if not is_instance_valid(self) or not is_instance_valid(player_card) or gen != _gen:
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
		if not is_instance_valid(self) or gen != _gen:
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
		Music.duck()  # pause the soundtrack so the jingle is heard clean; resumed on _sfx.finished
		_sfx.stream = stream
		_sfx.play()


func _set_target_lit(on: bool) -> void:
	if _felt_mat:
		_felt_mat.set_shader_parameter("active", 1.0 if on else 0.0)


func _update_score(p: int, r: int) -> void:
	_score = Vector2i(p, r)
	_ended = 0
	if _score_panel:
		# Scoreline in the chosen language (おぬし = playful archaic "you"). (R18)
		_score_panel.text = Lang.t("You %d : %d Robot" % [p, r], "おぬし %d : %d ロボット" % [p, r])
		_score_panel.modulate = Color.WHITE  # clear any held end-game tint on restart


# Re-render the live panel when the language flips (Hud's 日本/EN toggle).
func _on_lang_changed() -> void:
	if _ended != 0:
		_render_banner()
	else:
		_update_score(_score.x, _score.y)


func _render_banner() -> void:
	if _score_panel:
		_score_panel.text = (
			Lang.t("YOU WIN", "お前の勝ち") if _ended == 1 else Lang.t("YOU LOSE", "お前の負け")
		)


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


# An unshaded, billboarded one-shot spark emitter tinted `tone`, quads `size` wide. Shared by
# the score-panel sparkle and the win fireworks — caller sets amount/velocity/gravity/lifetime.
func _spark_emitter(tone: Color, size: float) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = tone
	mat.albedo_color = tone
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	var fx := CPUParticles3D.new()
	fx.mesh = quad
	fx.one_shot = true
	fx.explosiveness = 0.95
	return fx


# One-shot sparkle burst at the score panel. ponytail: CPUParticles is plenty for a
# ~couple-dozen-spark pop; switch to GPUParticles only if Quest profiling flags it.
func _sparkle(amount: int) -> void:
	if not _score_panel:
		return
	var fx := _spark_emitter(Color(1.0, 0.95, 0.6), 0.014)
	fx.amount = amount
	fx.lifetime = 0.9
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


# Player won the match: float the app icon in the middle (eye level, in front of the player) where
# it pops in and bobs, and ring it with staggered firework bursts for the length of the celebration.
# Runs as a coroutine alongside _show_end_state's restart wait; restart() bumps _gen so it bails.
func _celebrate() -> void:
	_stop_celebration()
	var gen := _gen
	var anchor := Node3D.new()
	add_child(anchor)
	anchor.global_position = Vector3(0.0, 1.55, -1.05)
	_party = anchor

	var icon := Sprite3D.new()
	icon.texture = ICON
	icon.pixel_size = 0.5 / ICON.get_width()  # ~0.5 m tall regardless of source resolution
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # always faces the player
	icon.scale = Vector3.ZERO
	anchor.add_child(icon)

	# Pop in, then bob gently up and down for as long as the icon lives.
	var pop := create_tween()
	pop.tween_property(icon, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var bob := create_tween().set_loops()
	bob.tween_property(icon, "position", Vector3(0.0, 0.05, 0.0), 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(icon, "position", Vector3(0.0, -0.05, 0.0), 1.2).set_trans(Tween.TRANS_SINE)

	# Fireworks: a burst every ~0.6 s, circling the icon in rotating party colours.
	var tones := [
		Color(1.0, 0.4, 0.5), Color(0.5, 0.8, 1.0), Color(1.0, 0.9, 0.4), Color(0.6, 1.0, 0.6)
	]
	for i in 8:
		if gen != _gen or not is_instance_valid(anchor):
			return
		var ang := i * TAU / 5.0  # not 8 — so successive bursts land at different angles
		var off := Vector3(cos(ang) * 0.4, sin(ang) * 0.3, 0.0)
		_firework(anchor, off, tones[i % tones.size()])
		await get_tree().create_timer(0.6).timeout


# One firework pop at `offset` within the celebration anchor: a fast, wide, gravity-pulled burst.
func _firework(anchor: Node3D, offset: Vector3, tone: Color) -> void:
	var fx := _spark_emitter(tone, 0.022)
	fx.position = offset
	fx.amount = 40
	fx.lifetime = 1.1
	fx.explosiveness = 1.0
	fx.spread = 180.0
	fx.initial_velocity_min = 0.9
	fx.initial_velocity_max = 1.7
	fx.gravity = Vector3(0.0, -0.9, 0.0)
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.4
	anchor.add_child(fx)
	fx.emitting = true
	await get_tree().create_timer(fx.lifetime + 0.3).timeout
	if is_instance_valid(fx):
		fx.queue_free()


func _stop_celebration() -> void:
	if is_instance_valid(_party):
		_party.queue_free()
	_party = null


func _begin_next_round() -> void:
	# refill_hands() already ran inside play_round(); GameRoot clears the consumed cards
	# (player + robot, via the "card" group) and respawns the player's refreshed hand (R11).
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_robot.reset_face()  # clear last round's smile/tear
	_set_target_lit(false)  # back to plain felt for the fresh throw
	_round_active = true


func _show_end_state(player_won: bool) -> void:
	# End banner (R19). お前 = casual "you". _ended drives a re-render on a language flip.
	_ended = 1 if player_won else 2
	_render_banner()
	_flourish(Color(0.4, 1.0, 0.5) if player_won else Color(1.0, 0.4, 0.4), 1.8, 60, true)
	if player_won:
		_celebrate()  # icon floats up in the middle, ringed by fireworks (coroutine, runs alongside)
		Music.victory()  # swap the soundtrack to the victory anthem until Restart
	_play_stinger(1 if player_won else -1)  # game over is win or lose, never a draw
	# Game stays on the end banner until the player hits Restart (Hud button → restart()).


# Fresh match: reset logic + scene, and (for the Hud's Restart button) recenter the player.
# Bumping _gen makes any in-flight round's awaits bail so we never deal over the hand this
# just dealt.
func restart(recenter: bool = true) -> void:
	_gen += 1
	_round_active = false
	_stop_celebration()  # clear any win party from the match just ended
	Music.reset_track()  # turn off the victory anthem, back to the cycled track
	GameState.new_game()
	if _game_root and _game_root.has_method("deal_player_hand"):
		_game_root.deal_player_hand()
	_robot.reset_face()
	_set_target_lit(false)
	_update_score(0, 0)
	if recenter:
		_xr_origin.transform = _start_xform
	_round_active = true
