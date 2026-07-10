extends SceneTree

var failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main._create_world()
	main._create_player()
	main._give_start_items()
	main.voxel_world.set_tracking_changes(true)
	main._create_runtime_systems()
	main._begin_gameplay()
	_check(main.game_started, "gameplay starts")
	_check(main.player != null and main.entity_manager != null and main.light_registry != null, "runtime systems are created")
	if failed:
		quit(1)
		return

	var torch_pos := Vector3i.ZERO
	for z in range(40, 61):
		for x in range(40, 61):
			var y: int = main.voxel_world.get_surface_height(x, z, 0) + 1
			var candidate := Vector3i(x, y, z)
			if not main.voxel_world.has_block(candidate):
				torch_pos = candidate
				break
		if torch_pos != Vector3i.ZERO:
			break
	_check(main._set_block(torch_pos, "torch").succeeded, "torch placement uses voxel edit flow")
	_check(main.light_registry.is_spawn_blocked(Vector3(torch_pos)), "placed torch updates light registry")

	var expected_items: int = 0
	for slot in main.inventory_slots:
		expected_items += int((slot as Dictionary).get("count", 0))
	main.player.take_damage(20.0)
	await process_frame
	await process_frame
	_check(main.player.health == 20.0 and main.thumbstones.size() == 1, "death respawns player and creates thumbstone")
	_check(main._item_total("dirt") == 0, "death clears player inventory")
	var stone = main.thumbstones[0]
	stone.collect()
	await process_frame
	var recovered_items: int = 0
	for slot in main.inventory_slots:
		recovered_items += int((slot as Dictionary).get("count", 0))
	_check(main.thumbstones.is_empty() and recovered_items == expected_items, "thumbstone restores every item exactly once")
	if failed:
		quit(1)
		return
	print("Gameplay systems smoke check passed.")
	quit(0)

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Smoke check failed: %s" % label)
