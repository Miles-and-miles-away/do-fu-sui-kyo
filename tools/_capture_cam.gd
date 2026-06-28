extends Camera3D
# Throwaway flatscreen capture camera. Forces itself current over the XRCamera every frame
# (no headset → no standing height, so the rig camera sits floor-low) and frames the table +
# robot at standing eyeline. Used only by tools/capture.tscn — delete both when done.
# Also poses the demo: 鬼 (HARD) difficulty so the robot wears its red oni reskin, and the
# Rules card open on the HUD instead of the auto-opened Story card.
@export var eye := Vector3(0.05, 1.42, 0.6)
@export var target := Vector3(0.6, 0.95, -0.7)
# true → HARD (red robot + horns) with Rules card; false → MEDIUM + Story card
@export var oni := false


func _ready() -> void:
	fov = 67.0
	global_position = eye
	look_at(target, Vector3.UP)
	_pose_demo()


func _pose_demo() -> void:
	# Let main.tscn finish: the robot connects difficulty_changed in its _ready, and the
	# Viewport2Din3D instances the HUD scene a frame or two in.
	await get_tree().process_frame
	await get_tree().process_frame
	if not oni:
		return  # normal mode: leave MEDIUM (cyan robot) + the auto-opened Story card
	GameState.set_difficulty(GameState.Difficulty.HARD)  # red oni reskin + horns

	var hud := get_node_or_null("../Main/Hud3D")
	if hud == null:
		return
	for _i in 60:
		if is_instance_valid(hud.scene_node):
			break
		await get_tree().process_frame
	var panel: Node = hud.scene_node
	if panel:
		panel._set_rules_visible(true)  # swap the startup Story card for the Rules card
		panel._update_difficulty_highlight()  # light the 鬼 button to match the new difficulty


func _process(_d: float) -> void:
	current = true
