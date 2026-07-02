extends Node
# Self-check do lockstep (GDD §9): duas sims com os MESMOS comandos tem que dar
# o MESMO hash em todo tick. Roda:
#   godot --headless --path . res://tests/determinism.tscn

func _ready() -> void:
	var a: Node = load("res://src/sim.gd").new()
	var b: Node = load("res://src/sim.gd").new()
	add_child(a)
	add_child(b)
	var falhas := 0
	for t in 600:
		for s in [a, b]:
			match t:  # roteiro fixo de comandos (os "inputs" do lockstep)
				5: s.cmd_place("canteiro", Vector2i(14, 12), 1)
				10: s.cmd_interact(Vector2i(14, 12))   # planta
				12: s.cmd_interact(Vector2i(14, 12))   # rega
				150: s.cmd_interact(Vector2i(14, 12))  # colhe
				160: s.cmd_place("esteira", Vector2i(3, 7), 3)
				161: s.cmd_place("esteira", Vector2i(2, 7), 3)
				170: s.tier = 1
				175: s.cmd_place("maq_pura", Vector2i(4, 12), 3)
				180: s.cmd_buy_seed("ruderalis")
			s._step()
		if a.state_hash() != b.state_hash():
			falhas += 1
			printerr("DIVERGIU no tick %d" % t)
			break
	if falhas == 0 and a.tick == 600 and a.state_hash() == b.state_hash():
		print("PASS: 600 ticks identicos (hash %d)" % a.state_hash())
		get_tree().quit(0)
	else:
		printerr("FAIL: simulacao nao deterministica")
		get_tree().quit(1)
