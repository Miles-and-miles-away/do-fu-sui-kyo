extends MeshInstance3D
# Drives the wall shader's speed by difficulty: EASY -20%, HARD +20%, MEDIUM unchanged.
# Brain-driven (difficulty_changed) so it tracks both HUD level picks AND new_game()'s reset
# on Restart, exactly like RobotPlayer's reskin.

const SCALE := {
	GameState.Difficulty.EASY: 0.8,
	GameState.Difficulty.MEDIUM: 1.0,
	GameState.Difficulty.HARD: 1.2,
}


func _ready() -> void:
	GameState.difficulty_changed.connect(_on_difficulty_changed)
	_on_difficulty_changed(GameState.difficulty)


func _on_difficulty_changed(level: int) -> void:
	(mesh.material as ShaderMaterial).set_shader_parameter("speed_scale", SCALE[level])
