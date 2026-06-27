extends Node3D
# Throwaway: render the HARD robot's head for a screenshot, then quit.


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	env.environment = e
	add_child(env)

	var robot := preload("res://game/RobotPlayer.gd").new()
	add_child(robot)

	var cam := Camera3D.new()
	cam.position = Vector3(0.28, 1.52, -0.65)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.5, -1.3), Vector3.UP)

	GameState.set_difficulty(GameState.Difficulty.HARD)

	for _i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_horn_shot.png")
	get_tree().quit()
