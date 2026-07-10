extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Unable to load main scene.")
		quit(1)
		return
	var main_node: Node = scene.instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	if not is_instance_valid(main_node):
		push_error("Main scene was freed during startup.")
		quit(1)
		return
	print("Main scene smoke check passed.")
	quit(0)
