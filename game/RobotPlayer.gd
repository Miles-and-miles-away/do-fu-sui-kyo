# game/RobotPlayer.gd — the wireframe robot opponent that sits opposite the player,
# reaches to its own deck, picks a card up, and lays it on the table (DESIGN §8, FSD R15).
# ─────────────────────────────────────────────────────────────────────────────
# Built procedurally and glowing, all see-through wireframe: torso, arms + neck are 6-sided
# wireframe cylinders (line prisms); pedestal, head + claw are line meshes too — no model
# file, no rig, no skeletal animation. All share one unshaded emissive material. The arm and
# head are separate pivot nodes that AIM with the built-in look_at() — the lazy distillation
# of godot-demo-projects 3d/ik (its ik_look_at boils down to Transform3D.looking_at), so no
# Skeleton3D/IK solver. On its turn the arm look_at()s its deck, touches a card, winds up, and
# THROWS it — a quick forward flick that releases the card so it arcs free onto the table, the
# arm following through rather than escorting it the whole way. The claw points where it throws.
# The head continuously look_at()s the player for a spark of life.
# Built procedurally on purpose: no .tscn/UID wiring, so it survives the headless export loop.
#
# ⚠️ Exercised in-headset, not by unit tests. Geometry/timing are calibration knobs.
extends Node3D

# ── Placement (world coords; RobotPlayer sits at the scene origin) ─────────────
@export var body_origin := Vector3(0.0, 0.0, -1.3)  # robot stands here, faces +Z (toward player)
@export var deck_point := Vector3(0.0, 0.72, -1.08)  # invisible throw origin in front of the robot
@export var wire_color := Color(0.25, 1.0, 0.85)  # cyan circuit glow (normal)
@export var menace_color := Color(1.0, 0.18, 0.2)  # red glow on the 鬼 (HARD) difficulty
@export var tear_color := Color(0.4, 0.8, 1.0)  # neon blue — the loss tear, set apart from the face
@export var wire_energy: float = 1.6
@export var body_radius: float = 0.2  # torso cylinder radius
@export var limb_radius: float = 0.03  # arm cylinder radius

# ── Arm animation (seconds; the reach AIM is automatic via look_at, no angles) ─
@export var reach_time: float = 0.45  # rest → deck (reach down, touch a card)
@export var wind_time: float = 0.18  # deck → wind-up (cock the throw, card in claw)
@export var throw_time: float = 0.28  # wind-up → release (arm snaps forward and lets go)
@export var flight_time: float = 0.45  # card's airborne arc to the table after release
@export var return_time: float = 0.4  # follow-through → rest (withdraw)

var _mat: StandardMaterial3D
var _tear_mat: StandardMaterial3D
var _arm: Node3D  # shoulder pivot — look_at()s its aim point
var _head: Node3D  # head pivot — look_at()s the player
var _mouth: MeshInstance3D  # swaps flat ↔ smile on win/loss
var _mouth_flat: ArrayMesh  # neutral line mouth
var _mouth_smile: ArrayMesh  # upturned mouth, shown on a win
var _tear: MeshInstance3D  # neon tear, hidden until the robot loses
var _eyes: MeshInstance3D  # swaps square ↔ round (round + cuter on EASY)
var _eyes_square: ArrayMesh  # default rectangular eyes
var _eyes_round: ArrayMesh  # big round eyes, shown on EASY
var _horns: MeshInstance3D  # red 鬼 horns, shown only on HARD
var _arm_l: Node3D  # left shoulder pivot (mirrors _arm; both animate in the victory dance)
var _elbow: Node3D  # right elbow joint — bends the forearm for the dance (rest = straight)
var _elbow_l: Node3D  # left elbow joint
var _shoulder: Vector3  # right arm pivot world position
var _shoulder_l: Vector3  # left arm pivot world position
var _rest_aim: Vector3  # where the right arm points when idle (down-forward, never vertical)
var _rest_aim_l: Vector3  # idle aim for the left arm
var _head_card: Node = null  # card the player lobbed into the head (HARD); played next

@onready var _game_root: Node = get_parent()  # GameRoot.gd — the card factory (frames live there)


func _ready() -> void:
	_build_body()
	# Reskin to red on 鬼 (HARD), back to cyan otherwise. Driven by the brain so it always tracks
	# the live difficulty — including new_game()'s reset to MEDIUM.
	GameState.difficulty_changed.connect(_on_difficulty_changed)
	_on_difficulty_changed(GameState.difficulty)


func _on_difficulty_changed(level: int) -> void:
	var c: Color = menace_color if level == GameState.Difficulty.HARD else wire_color
	if _mat:
		_mat.albedo_color = c
		_mat.emission = c
	if _horns:
		_horns.visible = level == GameState.Difficulty.HARD
	if _eyes:
		_eyes.mesh = _eyes_round if level == GameState.Difficulty.EASY else _eyes_square


# Head tracks the player every frame — one look_at on one node, negligible cost.
# ponytail: raw look_at, no smoothing; add a lerp only if it snaps too hard in-headset.
func _process(_delta: float) -> void:
	if not _head:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and _head.global_position.distance_to(cam.global_position) > 0.05:
		_head.look_at(cam.global_position, Vector3.UP)  # eyes sit on the head's -Z face


# ── Called by PlayZone during resolution ─────────────────────────────────────
# `t` is 0/1/2 (== GameState.Type). `lay_pos` is where the card should end up on the table.
# Returns the card node immediately so PlayZone can drive its face after the settle window;
# the reach/throw animation plays out asynchronously and PlayZone snaps the card flat at settle.
func present_card(t: int, lay_pos: Vector3) -> Node:
	# Easter egg: if the player stuffed a card into the head, the robot throws THAT one from
	# the head instead of dealing a fresh card from the deck (GameState forced its type to match).
	if _head_card and is_instance_valid(_head_card):
		var head_card := _head_card
		_head_card = null
		# _head_card is typed Node (cards pass around as Node here); global_position lives on
		# Node3D, so name the type explicitly rather than inferring it off a Node-typed local.
		var grab_at: Vector3 = head_card.global_position  # where it's stuck — arm reaches up to here
		head_card.reparent(get_tree().current_scene)  # back to world space, keeps its pose
		if head_card is RigidBody3D:
			head_card.freeze = true
		_play_card(head_card, lay_pos, grab_at)
		return head_card
	if not (_game_root and _game_root.has_method("make_card")):
		push_warning("RobotPlayer: GameRoot factory missing; cannot present robot card")
		return null
	var card: RigidBody3D = _game_root.make_card(t, true)  # robot's machine trio, not the animals
	get_tree().current_scene.add_child(card)
	card.freeze = true  # carried kinematically; no gravity while it waits/travels
	card.global_position = deck_point
	_play_card(card, lay_pos, deck_point)  # fire-and-forget; awaits internally
	return card


# World position of the head — GameRoot uses it to detect a card lobbed into the head (HARD).
func head_position() -> Vector3:
	return _head.global_position if _head else Vector3.INF


# Stick a thrown player card to the head: freeze it, parent it to the head so it rides the
# head's look_at swivel, and hold it until the robot plays it next via present_card.
# ponytail: ignore a second throw while one's already stuck — one rigged card per round.
func catch_in_head(card: Node) -> void:
	if _head_card and is_instance_valid(_head_card):
		return
	if card is RigidBody3D:
		card.linear_velocity = Vector3.ZERO
		card.angular_velocity = Vector3.ZERO
		card.freeze = true
	card.reparent(_head)
	# Plant it flat against the front face, looking back at the player. The head's -Z faces the
	# player (eyes live there), and a card's face is its +Z — so rotate 180° about Y to turn the
	# face outward, then push it out along -Z. Explicit basis kills the tumbling throw-rotation
	# (which left the thin quad edge-on and invisible). Ease into place rather than snapping — the
	# card slides onto the head over a beat. Local transform, so it rides the head's look_at swivel.
	var stuck := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -0.16))
	var tw := create_tween()
	tw.tween_property(card, "transform", stuck, 0.15)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_head_card = card


# Face expressions, mirroring the robot card (PlayZone calls these on resolution).
func show_win() -> void:  # robot won → smile, no tear
	if _mouth:
		_mouth.mesh = _mouth_smile
	if _tear:
		_tear.visible = false


func show_loss() -> void:  # robot lost (or draw) → flat mouth + neon tear
	if _mouth:
		_mouth.mesh = _mouth_flat
	if _tear:
		_tear.visible = true


func reset_face() -> void:  # back to neutral between rounds
	if _mouth:
		_mouth.mesh = _mouth_flat
	if _tear:
		_tear.visible = false


# Reach to the deck to TOUCH a card, wind up, then THROW it: the card leaves the claw and
# arcs free to the table while the arm follows through — it isn't escorted the whole way.
func _play_card(card: Node, lay_pos: Vector3, from_point: Vector3) -> void:
	if _arm:
		await _tween_aim(_rest_aim, from_point, reach_time)  # reach to the card (deck or head)
		if not is_instance_valid(self) or not is_instance_valid(card):
			return

	# Wind-up: lift the card up-and-back into the claw, arm tracking it (cock the throw).
	var wind := from_point + Vector3(0.0, 0.32, -0.12)
	if _arm:
		create_tween().tween_method(_aim_arm, from_point, wind, wind_time)
	var wind_tw := create_tween()
	wind_tw.tween_property(card, "global_position", wind, wind_time)
	await wind_tw.finished
	if not is_instance_valid(self) or not is_instance_valid(card):
		return

	# Throw: arm snaps forward toward the table (throw_time) and RELEASES — the card flies on
	# its own over an apex to lay_pos (flight_time, longer), so it visibly leaves the claw.
	if _arm:
		create_tween().tween_method(_aim_arm, wind, lay_pos, throw_time)
	var apex := (wind + lay_pos) * 0.5 + Vector3(0.0, 0.28, 0.0)
	var flight := create_tween()
	flight.tween_property(card, "global_position", apex, flight_time * 0.4).set_ease(Tween.EASE_OUT)
	flight.tween_property(card, "global_position", lay_pos, flight_time * 0.6).set_ease(
		Tween.EASE_IN
	)
	await flight.finished

	# Follow-through: withdraw the now-empty arm to rest. PlayZone snaps the card flat at settle.
	if _arm and is_instance_valid(self):
		await _tween_aim(lay_pos, _rest_aim, return_time)


# Sweep the arm's aim point from → to, look_at()ing it each step (built-in IK-free aim).
func _tween_aim(from_pt: Vector3, to_pt: Vector3, secs: float) -> void:
	var tw := create_tween()
	tw.tween_method(_aim_arm, from_pt, to_pt, secs)
	await tw.finished


func _aim_arm(point: Vector3) -> void:
	_aim(_arm, point)


func _aim_arm_l(point: Vector3) -> void:
	_aim(_arm_l, point)


# Point a shoulder pivot's local -Z (and thus the whole limb) at `point` via the built-in look_at.
func _aim(arm: Node3D, point: Vector3) -> void:
	if arm and arm.global_position.distance_to(point) > 0.001:
		arm.look_at(point, Vector3.UP)


# ── Procedural wireframe body (line meshes; cylinders are 6-sided line prisms; no rig) ──
func _build_body() -> void:
	_mat = _make_glow_mat(wire_color)
	_tear_mat = _make_glow_mat(tear_color)

	var o := body_origin
	# Pedestal stays a wireframe box (head + cylinder limbs built separately below).
	var pts := PackedVector3Array()
	_box(pts, o + Vector3(0.0, 0.25, -0.05), Vector3(0.45, 0.5, 0.35))  # pedestal
	_add_mesh(pts)

	# Torso — a see-through wireframe cylinder (the robot's body), upright (height 0.55).
	var torso_c := o + Vector3(0.0, 0.85, -0.02)
	_cyl_between(
		self, torso_c - Vector3(0.0, 0.275, 0.0), torso_c + Vector3(0.0, 0.275, 0.0), body_radius
	)

	# Neck — a thin wireframe cylinder.
	_cyl_between(self, o + Vector3(0.0, 1.12, -0.02), o + Vector3(0.0, 1.24, 0.0), limb_radius)

	# Deck has no geometry; deck_point is just the throw origin.

	# Head — its own pivot at the head centre so look_at() (in _process) swings it to face the
	# player. Geometry is head-local; EYES sit on the -Z face because look_at points -Z at the
	# target, so the eyes end up looking at whatever the head tracks.
	_head = Node3D.new()
	_head.position = o + Vector3(0.0, 1.36, 0.0)
	add_child(_head)
	var head := PackedVector3Array()
	_box(head, Vector3.ZERO, Vector3(0.26, 0.24, 0.24))  # head cube
	var head_mesh := MeshInstance3D.new()
	head_mesh.mesh = _line_mesh(head)
	_head.add_child(head_mesh)

	# Eyes — own node so EASY can swap the default squares for big round ones (cuter). On the -Z
	# face (the side look_at points at the player). Square is the default; round is shown on EASY.
	_eyes_square = _line_mesh(_eye_shape(false))
	_eyes_round = _line_mesh(_eye_shape(true))
	_eyes = MeshInstance3D.new()
	_eyes.mesh = _eyes_square
	_head.add_child(_eyes)

	# Mouth — its own node so we can swap line ↔ smile. Starts flat (neutral).
	_mouth_flat = _line_mesh(_mouth_line(false))
	_mouth_smile = _line_mesh(_mouth_line(true))
	_mouth = MeshInstance3D.new()
	_mouth.mesh = _mouth_flat
	_head.add_child(_mouth)

	# Tear — neon, at the bottom-left corner of the left eye; hidden until the robot loses.
	_tear = MeshInstance3D.new()
	_tear.mesh = _line_mesh(_tear_shape(), _tear_mat)
	_tear.visible = false
	_head.add_child(_tear)

	# 鬼 horns — two red wireframe cones standing on the head's top face, one over each half
	# (split at x=0). Their own red material; hidden unless HARD (toggled in _on_difficulty_changed).
	# Child of _head so they ride its swivel like the eyes/mouth.
	var top := 0.12  # head box half-height — the top face
	var horns := PackedVector3Array()
	_cone(horns, Vector3(-0.065, top, 0.0), Vector3(-0.095, 0.26, 0.0), 0.045)  # left half
	_cone(horns, Vector3(0.065, top, 0.0), Vector3(0.095, 0.26, 0.0), 0.045)  # right half
	_horns = MeshInstance3D.new()
	_horns.mesh = _line_mesh(horns, _make_glow_mat(menace_color))
	_horns.visible = false  # _on_difficulty_changed sets the real state on _ready
	_head.add_child(_horns)

	# Both arms — shoulder pivots aimed via look_at, each with an elbow joint child so the forearm
	# can bend for the victory dance (rest pose = elbow straight).
	# Idle aim is down-forward, never straight down (vertical would break look_at's up vector).
	_shoulder = o + Vector3(0.24, 1.05, -0.02)
	_rest_aim = _shoulder + Vector3(0.0, -0.5, 0.25)
	var r := _build_arm(_shoulder, _rest_aim, true)  # right arm throws → has the claw
	_arm = r[0]
	_elbow = r[1]
	_shoulder_l = o + Vector3(-0.24, 1.05, -0.02)
	_rest_aim_l = _shoulder_l + Vector3(0.0, -0.5, 0.25)
	var l := _build_arm(_shoulder_l, _rest_aim_l, false)  # left arm is static-looking until the dance
	_arm_l = l[0]
	_elbow_l = l[1]


# Build a shoulder→elbow→forearm pivot at `shoulder`, aimed down-forward at rest. Geometry runs
# along local -Z so look_at(point) aims the whole limb; the elbow node bends the forearm for the
# dance. `with_claw` adds the gripper prongs (right arm only). Returns [shoulder_node, elbow_node].
func _build_arm(shoulder: Vector3, rest_aim: Vector3, with_claw: bool) -> Array:
	var arm := Node3D.new()
	arm.position = shoulder
	add_child(arm)
	var elbow_pt := Vector3(0.0, -0.04, -0.28)
	_cyl_between(arm, Vector3.ZERO, elbow_pt, limb_radius)  # upper arm (toward -Z)
	var elbow := Node3D.new()
	elbow.position = elbow_pt
	arm.add_child(elbow)
	var wrist := Vector3(0.0, -0.06, -0.27)  # forearm end, relative to the elbow joint
	_cyl_between(elbow, Vector3.ZERO, wrist, limb_radius)  # forearm (under the elbow)
	if with_claw:
		var claw := PackedVector3Array()
		_seg(claw, wrist, wrist + Vector3(0.05, -0.02, -0.06))
		_seg(claw, wrist, wrist + Vector3(-0.05, -0.02, -0.06))
		var claw_mesh := MeshInstance3D.new()
		claw_mesh.mesh = _line_mesh(claw)
		elbow.add_child(claw_mesh)
	_aim(arm, rest_aim)  # start at idle aim
	return [arm, elbow]


# Victory dance: throw both arms up, pump the elbows (bend ↔ stretch) a few times, then drop back
# to rest. PlayZone calls this on a decisive robot match win. Timing/angles are calibration knobs.
func celebrate() -> void:
	if not (_arm and _arm_l and _elbow and _elbow_l):
		return
	# Arms raise OUT to the sides and up, above the head; then the elbows flex so the forearms
	# swing inward to meet at the centre above the head, straighten back out, and repeat.
	var up_r := _shoulder + Vector3(0.45, 0.5, 0.08)  # right arm up-and-out to the side, elbow high
	var up_l := _shoulder_l + Vector3(-0.45, 0.5, 0.08)  # left arm up-and-out to the side
	var bend := 1.9  # +ve elbow rotation swings both forearms inward to meet over the head
	await _dance_step(_rest_aim, up_r, _rest_aim_l, up_l, 0.0, 0.0, 0.25)  # arms out to the sides
	for _i in 3:
		await _dance_step(up_r, up_r, up_l, up_l, 0.0, bend, 0.18)  # forearms in to the centre
		await _dance_step(up_r, up_r, up_l, up_l, bend, 0.0, 0.18)  # straighten back out
	await _dance_step(up_r, _rest_aim, up_l, _rest_aim_l, 0.0, 0.0, 0.3)  # lower to rest
	_aim_arm(_rest_aim)  # leave the throwing arm exactly at its idle aim


# One dance beat: tween both shoulder aims and both elbow bends in parallel over `secs`.
func _dance_step(
	ar0: Vector3, ar1: Vector3, al0: Vector3, al1: Vector3, e0: float, e1: float, secs: float
) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_aim_arm, ar0, ar1, secs)
	tw.tween_method(_aim_arm_l, al0, al1, secs)
	tw.tween_method(_set_elbows, e0, e1, secs)
	await tw.finished


func _set_elbows(angle: float) -> void:
	_elbow.rotation.x = angle
	_elbow_l.rotation.x = angle


func _add_mesh(pts: PackedVector3Array) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _line_mesh(pts)
	add_child(mi)


# A see-through WIREFRAME cylinder spanning a→b: a 6-sided prism — 6 vertical wires (the
# "tubes") closed by an end ring at each cap. Drawn as line segments via _line_mesh, so it
# glows and stays see-through exactly like the old wire body. `parent` owns the mesh.
func _cyl_between(parent: Node3D, a: Vector3, b: Vector3, radius: float) -> void:
	var sides := 6
	var basis := _basis_from_y((b - a).normalized())  # circle plane ⊥ the a→b axis
	var x := basis.x * radius
	var z := basis.z * radius
	var pts := PackedVector3Array()
	var prev_a := a
	var prev_b := b
	for i in sides + 1:
		var ang := TAU * i / sides
		var off := x * cos(ang) + z * sin(ang)
		var pa := a + off  # point on the bottom-cap ring
		var pb := b + off  # point on the top-cap ring
		if i > 0:
			_seg(pts, prev_a, pa)  # bottom ring edge
			_seg(pts, prev_b, pb)  # top ring edge
		if i < sides:
			_seg(pts, pa, pb)  # one of the 6 vertical wire tubes
		prev_a = pa
		prev_b = pb
	var mi := MeshInstance3D.new()
	mi.mesh = _line_mesh(pts)
	parent.add_child(mi)


# A wireframe cone spanning base→apex: a `sides`-gon base ring (the lines "around the base")
# plus one slant line from each base vertex up to `apex`. Appends segments to `pts` so several
# cones can batch into one mesh. Default 6 sides → 6 lines around the base, matching the body.
func _cone(
	pts: PackedVector3Array, base: Vector3, apex: Vector3, radius: float, sides: int = 6
) -> void:
	var basis := _basis_from_y((apex - base).normalized())  # ring plane ⊥ the base→apex axis
	var x := basis.x * radius
	var z := basis.z * radius
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + x * cos(a0) + z * sin(a0)
		var p1 := base + x * cos(a1) + z * sin(a1)
		_seg(pts, p0, p1)  # base ring edge (one of the 6 lines around the base)
		_seg(pts, p0, apex)  # slant edge up to the horn tip


# Orthonormal basis whose +Y column is `y`, so a Y-aligned primitive points along it.
func _basis_from_y(y: Vector3) -> Basis:
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _line_mesh(pts: PackedVector3Array, mat: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, mat if mat else _mat)  # default to the cyan body glow
	return mesh


# One unshaded, fully-emissive line material (the neon glow), tinted `color`.
func _make_glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = wire_energy
	return m


func _seg(pts: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	pts.push_back(a)
	pts.push_back(b)


# 12 edges of an axis-aligned box as line-segment pairs.
func _box(pts: PackedVector3Array, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var corner := func(sx: float, sy: float, sz: float) -> Vector3:
		return c + Vector3(sx * h.x, sy * h.y, sz * h.z)
	var signs := [-1.0, 1.0]
	# edges along X (vary x, fix y,z), along Y, along Z.
	for sy in signs:
		for sz in signs:
			_seg(pts, corner.call(-1.0, sy, sz), corner.call(1.0, sy, sz))
	for sx in signs:
		for sz in signs:
			_seg(pts, corner.call(sx, -1.0, sz), corner.call(sx, 1.0, sz))
	for sx in signs:
		for sy in signs:
			_seg(pts, corner.call(sx, sy, -1.0), corner.call(sx, sy, 1.0))


# The two eyes on the -Z face. `round_eyes` → big round circles (EASY, cuter); else the default
# rectangles. Same two centres either way so the tear still hangs off the left eye.
func _eye_shape(round_eyes: bool) -> PackedVector3Array:
	var z := -0.12  # the face plane (head half-depth)
	var pts := PackedVector3Array()
	for cx in [-0.06, 0.06]:
		if round_eyes:
			_circle(pts, Vector3(cx, 0.03, z), 0.032, 14)  # round + a touch bigger than the squares
		else:
			_box(pts, Vector3(cx, 0.02, z), Vector3(0.06, 0.05, 0.0))  # default rectangle
	return pts


# A flat ring of `segments` line segments, radius `r`, centred at `c` in the XY plane (the face).
func _circle(pts: PackedVector3Array, c: Vector3, r: float, segments: int) -> void:
	var prev := c + Vector3(r, 0.0, 0.0)
	for i in range(1, segments + 1):
		var ang := TAU * i / segments
		var p := c + Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		_seg(pts, prev, p)
		prev = p


# Mouth on the -Z face below the eyes: a flat line, or an upturned ∪ smile when `smiling`.
func _mouth_line(smiling: bool) -> PackedVector3Array:
	var z := -0.12  # the face plane (head half-depth), same as the eyes
	var pts := PackedVector3Array()
	if smiling:
		_seg(pts, Vector3(-0.06, -0.05, z), Vector3(-0.03, -0.085, z))  # left corner up
		_seg(pts, Vector3(-0.03, -0.085, z), Vector3(0.03, -0.085, z))  # valley
		_seg(pts, Vector3(0.03, -0.085, z), Vector3(0.06, -0.05, z))  # right corner up
	else:
		_seg(pts, Vector3(-0.06, -0.07, z), Vector3(0.06, -0.07, z))  # flat
	return pts


# A small diamond teardrop hanging off the bottom-left corner of the left eye (-Z face).
func _tear_shape() -> PackedVector3Array:
	var z := -0.12
	var cx := -0.088  # under the left eye's outer-bottom corner
	var top := Vector3(cx, -0.01, z)
	var bot := Vector3(cx, -0.06, z)
	var lft := Vector3(cx - 0.013, -0.035, z)
	var rgt := Vector3(cx + 0.013, -0.035, z)
	var pts := PackedVector3Array()
	_seg(pts, top, lft)
	_seg(pts, lft, bot)
	_seg(pts, bot, rgt)
	_seg(pts, rgt, top)
	return pts
