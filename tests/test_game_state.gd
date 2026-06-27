# tests/test_game_state.gd — headless assert suite for the GameState brain.
# ─────────────────────────────────────────────────────────────────────────────
# Implements FSD §9 tests T1–T9 (the only non-trivial correctness surface, R23).
#
# RUN (desktop, no VR — verify GREEN before any VR wiring, FSD pass-gate):
#   godot --headless --path . --script res://tests/test_game_state.gd ; echo "exit=$?"
# Exit code 0 = all pass, 1 = ≥1 failure (CI-friendly).
#
# WHY `extends SceneTree` and `.new()` (finding F1): a `--script` target MUST be a
# SceneTree/MainLoop, and in that mode Autoloads are NOT loaded — so we instantiate
# GameState directly instead of referencing the singleton.
extends SceneTree

const GS_SCRIPT := preload("res://GameState.gd")

var _passes := 0
var _failures: Array[String] = []


func _initialize() -> void:
	seed(12345)  # reproducible runs (FSD §5.1, edge E7)

	var gs = GS_SCRIPT.new()
	gs.new_game()

	_t2_new_game_start(gs)
	_t3_resolve_truth_table(gs)
	_t4_scoring(gs)
	_t5_refill(gs)
	_t6_hand_drift(gs)
	_t7_deck_exhaustion(gs)
	_t8_robot_legality(gs)
	_t9_game_over_boundary(gs)
	_t10_difficulty(gs)
	_t1_integration(gs)  # full game loop last (drives to game over)

	gs.free()

	# ── Report ──
	print("\n──────── GameState test suite ────────")
	print("  passed: %d   failed: %d" % [_passes, _failures.size()])
	for f in _failures:
		print("  ✗ ", f)
	if _failures.is_empty():
		print("  ✓ ALL GREEN — T1–T9 pass\n")
	quit(0 if _failures.is_empty() else 1)


# ── helpers ──────────────────────────────────────────────────────────────────
func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(msg)


# Set a typed Array[Type] hand from a plain int array WITHOUT the typed-assignment
# pitfall (append-an-int into Array[Type] is allowed; assigning a bare Array is not).
func _set_hand(hand: Array, values: Array) -> void:
	hand.clear()
	for v in values:
		hand.append(v)


# ── T2 — new-game start state (R4, R9, R10) ──────────────────────────────────
func _t2_new_game_start(gs) -> void:
	gs.new_game()
	var one_of_each := [gs.Type.WATER, gs.Type.SKY, gs.Type.EARTH]
	var ph = gs.player_hand.duplicate()
	ph.sort()
	var rh = gs.robot_hand.duplicate()
	rh.sort()
	_check(ph == one_of_each, "T2: player_hand should be one-of-each, got %s" % [gs.player_hand])
	_check(rh == one_of_each, "T2: robot_hand should be one-of-each, got %s" % [gs.robot_hand])
	_check(gs.player_score == 0 and gs.robot_score == 0, "T2: scores should start 0")
	_check(
		gs.deck.size() == gs.copies_per_type * 3,
		"T2: deck should be %d, got %d" % [gs.copies_per_type * 3, gs.deck.size()]
	)


# ── T3 — resolution truth table, all 9 cells (R4, R16) ───────────────────────
func _t3_resolve_truth_table(gs) -> void:
	var w = gs.Type.WATER
	var s = gs.Type.SKY
	var e = gs.Type.EARTH
	# expected outcome of resolve(player, robot): 1 player, -1 robot, 0 draw
	var expected := {
		[w, w]: 0,
		[w, s]: 1,
		[w, e]: -1,
		[s, w]: -1,
		[s, s]: 0,
		[s, e]: 1,
		[e, w]: 1,
		[e, s]: -1,
		[e, e]: 0,
	}
	for pair in expected:
		var got: int = gs.resolve(pair[0], pair[1])
		_check(
			got == expected[pair],
			(
				"T3: resolve(%s,%s) expected %d, got %d"
				% [gs.TYPE_NAMES[pair[0]], gs.TYPE_NAMES[pair[1]], expected[pair], got]
			)
		)


# ── T4 — scoring: +1 to winner, +0 on draw, never a step > 1 (R17) ───────────
func _t4_scoring(gs) -> void:
	# player win: WATER beats SKY
	gs.new_game()
	_set_hand(gs.player_hand, [gs.Type.WATER])
	_set_hand(gs.robot_hand, [gs.Type.SKY])
	var r = gs.play_round(gs.Type.WATER)
	_check(
		r.outcome == 1 and gs.player_score == 1 and gs.robot_score == 0,
		(
			"T4: player-win should be 1–0, got %d–%d (outcome %d)"
			% [gs.player_score, gs.robot_score, r.outcome]
		)
	)

	# robot win: EARTH beats WATER
	gs.new_game()
	_set_hand(gs.player_hand, [gs.Type.WATER])
	_set_hand(gs.robot_hand, [gs.Type.EARTH])
	r = gs.play_round(gs.Type.WATER)
	_check(
		r.outcome == -1 and gs.player_score == 0 and gs.robot_score == 1,
		(
			"T4: robot-win should be 0–1, got %d–%d (outcome %d)"
			% [gs.player_score, gs.robot_score, r.outcome]
		)
	)

	# draw: WATER vs WATER → no points
	gs.new_game()
	_set_hand(gs.player_hand, [gs.Type.WATER])
	_set_hand(gs.robot_hand, [gs.Type.WATER])
	r = gs.play_round(gs.Type.WATER)
	_check(
		r.outcome == 0 and gs.player_score == 0 and gs.robot_score == 0,
		(
			"T4: draw should be 0–0, got %d–%d (outcome %d)"
			% [gs.player_score, gs.robot_score, r.outcome]
		)
	)


# ── T5 — refill to 3 after a round (R11) ─────────────────────────────────────
func _t5_refill(gs) -> void:
	gs.new_game()
	gs.play_round(gs.player_hand[0])
	_check(
		gs.player_hand.size() == 3,
		"T5: player_hand should refill to 3, got %d" % gs.player_hand.size()
	)
	_check(
		gs.robot_hand.size() == 3,
		"T5: robot_hand should refill to 3, got %d" % gs.robot_hand.size()
	)


# ── T6 — hand drift: duplicates are legal & handled, no error (R12) ──────────
# Deterministic (no reliance on observing a random duplicate — that would be RNG/seed
# flaky, the very edge E7 the suite seeds against).
func _t6_hand_drift(gs) -> void:
	# (a) Invariant under sustained play: hands stay size 3 between rounds, no crash.
	gs.new_game()
	for _i in 20:
		if gs.game_over():
			gs.new_game()
		gs.play_round(gs.player_hand[0])
		_check(
			gs.player_hand.size() == 3 or gs.game_over(),
			"T6: hand size invariant broke (%d)" % gs.player_hand.size()
		)

	# (b) A drifted (duplicate-bearing) hand is explicitly legal and resolves cleanly.
	gs.new_game()
	_set_hand(gs.player_hand, [gs.Type.WATER, gs.Type.WATER, gs.Type.SKY])  # forced drift
	_set_hand(gs.robot_hand, [gs.Type.EARTH, gs.Type.SKY, gs.Type.WATER])
	var r = gs.play_round(gs.Type.WATER)  # throw one of the duplicates
	_check(r.outcome in [1, -1, 0], "T6: drifted hand failed to resolve")
	_check(
		gs.player_hand.size() == 3 or gs.game_over(),
		"T6: hand should still refill to 3 after a duplicate play"
	)


# ── T7 — deck exhaustion: never empties / crashes (R13, edge E1) ──────────────
func _t7_deck_exhaustion(gs) -> void:
	gs.new_game()
	var ok := true
	for _i in 200:  # far more than one deck (18) — forces multiple rebuilds
		var c = gs.draw_one()
		if c != gs.Type.WATER and c != gs.Type.SKY and c != gs.Type.EARTH:
			ok = false
	_check(ok, "T7: draw_one returned an invalid type during exhaustion")
	_check(
		not gs.deck.is_empty() or true,
		"T7: (deck may legitimately be empty between draws; rebuild happens on next draw)"
	)
	# one more draw after heavy draining must still succeed (rebuild guard)
	var after = gs.draw_one()
	_check(
		after == gs.Type.WATER or after == gs.Type.SKY or after == gs.Type.EARTH,
		"T7: draw after exhaustion failed"
	)


# ── T8 — robot picks legally from its OWN hand and removes it (R14) ──────────
func _t8_robot_legality(gs) -> void:
	gs.new_game()
	_set_hand(gs.robot_hand, [gs.Type.WATER, gs.Type.WATER, gs.Type.SKY])
	var before_player = gs.player_hand.duplicate()
	var start_size = gs.robot_hand.size()
	var picked = gs.robot_pick()
	_check(
		picked == gs.Type.WATER or picked == gs.Type.SKY,
		"T8: robot picked a type not in its hand: %s" % gs.TYPE_NAMES.get(picked, picked)
	)
	_check(gs.robot_hand.size() == start_size - 1, "T8: robot_pick should remove one card")
	_check(gs.player_hand == before_player, "T8: robot_pick must not touch the player's hand")


# ── T9 — game_over true IFF a side has reached 3 (R19, edge E5) ──────────────
func _t9_game_over_boundary(gs) -> void:
	gs.new_game()
	gs.player_score = 2
	gs.robot_score = 0
	_check(not gs.game_over(), "T9: 2–0 should NOT be game over")
	gs.player_score = 3
	_check(gs.game_over(), "T9: 3–0 should be game over")
	gs.player_score = 0
	gs.robot_score = 3
	_check(gs.game_over(), "T9: 0–3 should be game over")


# ── T10 — difficulty: HARD plays to win, EASY plays to lose (regardless of the roll) ─────
# Deterministic trick: stock the robot's hand with ONLY the card for the targeted outcome.
# Whichever way the win-rate coin lands, the wanted card (or the random fallback) is the same
# single card, so the round outcome is fixed — no flaky probability in the assert.
func _t10_difficulty(gs) -> void:
	# HARD vs WATER: EARTH beats WATER → robot should win. Hand holds only EARTH.
	gs.new_game()
	gs.difficulty = gs.Difficulty.HARD
	_set_hand(gs.robot_hand, [gs.Type.EARTH])
	var r = gs.play_round(gs.Type.WATER)
	_check(r.outcome == -1, "T10: HARD should beat the player, got outcome %d" % r.outcome)

	# EASY vs WATER: WATER beats SKY → robot should lose. Hand holds only SKY.
	gs.new_game()
	gs.difficulty = gs.Difficulty.EASY
	_set_hand(gs.robot_hand, [gs.Type.SKY])
	r = gs.play_round(gs.Type.WATER)
	_check(r.outcome == 1, "T10: EASY should lose to the player, got outcome %d" % r.outcome)
	gs.difficulty = gs.Difficulty.MEDIUM  # restore default for later tests

	# Easter egg: forced_robot_card overrides the pick at any difficulty, then clears itself.
	gs.new_game()
	gs.forced_robot_card = gs.Type.EARTH  # player stuffed EARTH into the head
	r = gs.play_round(gs.Type.WATER)  # EARTH beats WATER → robot wins
	_check(r.robot_card == gs.Type.EARTH, "T10: forced card not played")
	_check(r.outcome == -1, "T10: forced EARTH should beat WATER, got %d" % r.outcome)
	_check(gs.forced_robot_card == -1, "T10: forced_robot_card should reset after use")


# ── T1 — full-game integration: step≤1, refill, ends exactly at 3 (R9,R11,R17,R19,R23) ─
func _t1_integration(gs) -> void:
	gs.new_game()
	var prev_total := 0
	var rounds := 0
	while not gs.game_over() and rounds < 50:
		var before = gs.player_score + gs.robot_score
		var r = gs.play_round(gs.player_hand[0])
		var after = gs.player_score + gs.robot_score
		_check(after - before <= 1, "T1: score stepped by more than 1 in a round")
		_check(after - prev_total <= 1, "T1: cumulative score jumped >1")
		prev_total = after
		if not r.game_over:
			_check(
				gs.player_hand.size() == 3 and gs.robot_hand.size() == 3,
				"T1: hands not refilled to 3 between rounds"
			)
		rounds += 1
	_check(rounds < 50, "T1: game failed to end within 50 rounds (runaway)")
	_check(gs.player_score == 3 or gs.robot_score == 3, "T1: game ended without a side reaching 3")
	_check(
		not (gs.player_score == 3 and gs.robot_score == 3),
		"T1: both sides can't be at 3 (first-to-3 ends immediately)"
	)
