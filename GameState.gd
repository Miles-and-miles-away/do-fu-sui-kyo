# GameState.gd — Autoload singleton "GameState" (Project Settings → Autoload).
# ─────────────────────────────────────────────────────────────────────────────
# The BRAIN. Pure logic, NO 3D nodes, NO scene dependencies (FSD R23, NFR8).
# Runs headless on desktop; the VR layer calls exactly one method: play_round().
#
# Implements: docs/DESIGN.md §5 + docs/FSD.md §4/§5 (R4, R9–R23).
# Verified by: tests/test_game_state.gd (FSD T1–T9) and _dev_notes/logic_verification.md.
#
# Why `extends Node`: a Project-Settings Autoload is always instantiated as a Node at the
# tree root, which gives us global access + signals if ever needed. It holds NO scene
# geometry, so "pure logic, no nodes" (R23) is honored in spirit.
#
# ⚠️ Headless-test note (finding F1): `godot --headless --script` does NOT load Autoloads.
# tests/test_game_state.gd therefore does `load("res://GameState.gd").new()` and drives the
# instance directly. So: keep first-time setup in new_game() (callable), not only in _ready().
extends Node

# Three card types. WATER=Fish, SKY=Bird, EARTH=Dino. (R4)
enum Type { WATER, SKY, EARTH }

# Robot skill. EASY/HARD peek at the player's thrown card; MEDIUM stays blind (the original
# random pick). The numbers (DIFFICULTY_WIN_RATE) are the robot's target win rate.
enum Difficulty { EASY, MEDIUM, HARD }

# Cyclic "beats" table (R-P-S). Each type beats exactly one and loses to exactly one. (§4)
#   WATER → SKY → EARTH → WATER
# const so it is built ONCE, not allocated on every resolve() call (NFR6, no hot-path alloc).
const BEATS := {
	Type.WATER: Type.SKY,  # Fish beats Bird
	Type.SKY: Type.EARTH,  # Bird beats Dino
	Type.EARTH: Type.WATER,  # Dino beats Fish
}

const DIFFICULTY_WIN_RATE := {
	Difficulty.EASY: 0.3,
	Difficulty.HARD: 0.7,
}

# Display + sprite-lookup key (R8). Kept as Fish/Bird/Dino per the design.
const TYPE_NAMES := {
	Type.WATER: "Fish",
	Type.SKY: "Bird",
	Type.EARTH: "Dino",
}

# Tunable: copies of EACH type in a fresh deck. 6 → 18-card deck, easily outlasts a
# first-to-3 game (max 5 rounds → ≤10 cards drawn after the opening hands). (R9)
@export var copies_per_type: int = 6

# --- State (the authoritative shapes, FSD §5) ---
var difficulty: int = Difficulty.MEDIUM  # robot skill, set from the HUD
var deck: Array[Type] = []
var player_hand: Array[Type] = []
var robot_hand: Array[Type] = []
var player_score: int = 0
var robot_score: int = 0


func _ready() -> void:
	# Only fires when GameState is the live Autoload (game run), NOT under --script tests.
	new_game()


# ── Game setup ───────────────────────────────────────────────────────────────
func new_game() -> void:
	# Fresh match: zero scores, fresh shuffled deck, both hands one-of-each. (R10, R20)
	player_score = 0
	robot_score = 0
	_build_deck()
	player_hand = [Type.WATER, Type.SKY, Type.EARTH]
	robot_hand = [Type.WATER, Type.SKY, Type.EARTH]


func _build_deck() -> void:
	# Rebuild + shuffle the shared deck (R9, R13). Called on new game AND on empty-draw.
	deck.clear()
	for _i in copies_per_type:
		deck.append(Type.WATER)
		deck.append(Type.SKY)
		deck.append(Type.EARTH)
	deck.shuffle()


# ── Deck / hand operations (Array built-ins; FSD §5.1) ───────────────────────
func draw_one() -> Type:
	# Reshuffle guard: rebuild before drawing if empty so we NEVER pop an empty array
	# (R13, edge E1). This single line is what prevents a mid-demo crash — do not remove.
	if deck.is_empty():
		_build_deck()
	return deck.pop_back()


func refill_hands() -> void:
	# After a round, top both hands back up to 3 from the shared deck. (R11)
	while player_hand.size() < 3:
		player_hand.append(draw_one())
	while robot_hand.size() < 3:
		robot_hand.append(draw_one())


func robot_pick() -> Type:
	# Random-LEGAL card from the robot's OWN hand; removes and returns it. (R14)
	# Never reads the player's hand. Caller is responsible for a non-empty robot_hand
	# (always true between rounds: refill_hands keeps it at 3).
	var i := randi() % robot_hand.size()
	return robot_hand.pop_at(i)


# Difficulty-aware robot play. MEDIUM is the blind random pick; EASY/HARD roll their target
# win rate and then deliberately pick a card that beats (or, on a loss roll, loses to) the
# player's card. Falls back to random if the wanted card isn't in hand. (R14, difficulty)
func _robot_play(player_card: Type) -> Type:
	if difficulty == Difficulty.MEDIUM:
		return robot_pick()
	var want_win: bool = randf() < DIFFICULTY_WIN_RATE[difficulty]
	# The card the robot needs: one that beats player_card (win) or that player_card beats (loss).
	var wanted: Type = BEATS[BEATS[player_card]] if want_win else BEATS[player_card]
	var i := robot_hand.find(wanted)
	if i != -1:
		return robot_hand.pop_at(i)
	return robot_pick()  # wanted card not in hand → fall back to random


# ── Resolution (the 9-cell truth table — the key correctness surface, T3) ─────
# Returns: 1 = player wins, -1 = robot wins, 0 = draw. (R16)
func resolve(p: Type, r: Type) -> int:
	if p == r:
		return 0
	return 1 if BEATS[p] == r else -1


# ── The one call the VR layer makes (FSD §5) ─────────────────────────────────
# Pass the type the player threw; get back everything the scene needs to drive
# sprites + score. Consumes both played cards, scores, and refills hands. (R11, R17, R21)
func play_round(player_card: Type) -> Dictionary:
	# Defensive (edge E6): the thrown card should be in hand by construction, but if a
	# desync ever sends one that isn't, don't corrupt state — log and proceed with resolution.
	if not player_hand.has(player_card):
		push_warning(
			"play_round: %s not in player_hand %s" % [TYPE_NAMES[player_card], player_hand]
		)
	else:
		player_hand.erase(player_card)  # erase removes the first matching value (fine for value array)

	var robot_card := _robot_play(player_card)
	var outcome := resolve(player_card, robot_card)

	# Exactly one point to the winner; none on a draw; never a step > 1. (R17, edge E3)
	if outcome > 0:
		player_score += 1
	elif outcome < 0:
		robot_score += 1

	refill_hands()  # both hands back to 3 (R11). Drift is intended (R12, edge E6).

	return {
		"player_card": player_card,
		"robot_card": robot_card,
		"outcome": outcome,  # 1 / -1 / 0
		"player_score": player_score,
		"robot_score": robot_score,
		"game_over": game_over(),
	}


# First side to 3 ends the game. true IFF a side has reached 3 (R19, edge E5).
func game_over() -> bool:
	return player_score >= 3 or robot_score >= 3
