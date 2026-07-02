extends Node2D
# Bootstrap: monta renderizador, avatar, camera e UI em codigo (cena unica).

func _ready() -> void:
	var render := Node2D.new()
	render.set_script(load("res://src/render.gd"))
	add_child(render)

	var player := Node2D.new()
	player.set_script(load("res://src/player.gd"))
	add_child(player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(1.4, 1.4)
	cam.position_smoothing_enabled = true
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = Sim.W * 32
	cam.limit_bottom = Sim.H * 32
	player.add_child(cam)

	var ui := CanvasLayer.new()
	ui.set_script(load("res://src/ui.gd"))
	add_child(ui)

	render.ui = ui
	player.ui = ui
	ui.cam = cam
