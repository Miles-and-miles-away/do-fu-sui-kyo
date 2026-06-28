# tests/test_recenter.gd — headless check that PlayZone.recenter() turns the player to face the
# table (world -Z) from ANY heading, without changing height (the bug center_on_hmd caused).
# ─────────────────────────────────────────────────────────────────────────────
# RUN:  godot --headless --path . --script res://tests/test_recenter.gd ; echo "exit=$?"
# Exit 0 = all pass, 1 = ≥1 failure (CI-friendly).
#
# WHY this works without a headset: with no XR interface running, the XRCamera3D's transform is
# NOT driven by a pose, so we can plant a "turned head" pose on it and call the REAL recenter().
# The yaw math is the error-prone bit (sign flips); the in-headset facing/pose-timing is by hand.
extends SceneTree

var _scene: Node
var _frames := 0
var _passes := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_scene = load("res://main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false  # let the scene's _ready() run (PlayZone resolves its @onready node paths)
	_run()
	_report()
	quit(0 if _failures.is_empty() else 1)  # CI-friendly exit code
	return true


func _run() -> void:
	var pz: Node = _scene.get_node("GameRoot/PlayZone")
	var cam: XRCamera3D = _scene.get_node("XRRig/XROrigin3D/XRCamera3D")
	# The one spot the head must always land at: centred on the felt (x=0), authored depth, eye_height.
	var seat := Vector3(0.0, pz.eye_height, pz._start_global.origin.z)
	# Vary BOTH the head's yaw AND where it physically is (off-centre, tall/short). recenter() must
	# pin the head to `seat` facing -Z every time — that's "no high, no left, no rotation".
	var poses := [
		[0, Vector3(0, 1.6, 0)],
		[90, Vector3(0.4, 1.7, -0.3)],
		[-90, Vector3(-0.25, 1.1, 0.5)],
		[150, Vector3(0.3, 1.5, 0.2)],
		[180, Vector3(0, 1.2, 0)],
		[45, Vector3(-0.5, 1.85, -0.5)],
	]
	for pose in poses:
		cam.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(pose[0])), pose[1])
		if not pz.recenter():
			_failures.append("yaw %d: recenter() returned false" % pose[0])
			continue
		var head: Transform3D = cam.global_transform
		var pos_err: float = head.origin.distance_to(seat)
		var fwd: Vector3 = -head.basis.z
		fwd.y = 0.0
		var face_err: float = fwd.normalized().distance_to(Vector3(0, 0, -1))
		if pos_err < 0.001 and face_err < 0.02:
			_passes += 1
		else:
			_failures.append("yaw %d: pos_err=%.4f face_err=%.3f" % [pose[0], pos_err, face_err])


func _report() -> void:
	print("\n──────── recenter test suite ────────")
	print("  passed: %d   failed: %d" % [_passes, _failures.size()])
	for f in _failures:
		print("  ✗ " + f)
	if _failures.is_empty():
		print("  ✓ recenter() pins the head to the seat (-Z, eye_height) from every pose")
