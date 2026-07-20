extends SceneTree


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const MainScript = preload("res://src/main.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions: Dictionary = BlockCatalogScript.blocks()
	var main = MainScript.new()
	main.block_defs = definitions
	main.item_defs = BlockCatalogScript.items()
	main.item_defs["micro_pattern"] = {"name": "Padrao de Microvoxels"}
	var cell = MicroCellScript.new(); cell.fill_region(Vector3i.ZERO, 2, "stone")
	var slot: Dictionary = {"item": "micro_pattern", "count": 1, "data": {"cell": cell.to_dictionary(), "hash": cell.content_hash()}}
	var slots: Array = main.call("_slots_from_data", [slot], 1) as Array
	_check(str((slots[0] as Dictionary).get("data", {}).get("hash", "")) == cell.content_hash(), "V5 inventory restores micro-pattern payloads")
	_check(MainScript.SAVE_PATH == "user://weedcraft_save_v5.json" and MainScript.OLD_SAVE_PATHS.size() == 4, "WEEDCRAFT exposes only its V5 save and four ignored legacy paths")
	main.free()

	var world_a = VoxelWorldScript.new(definitions); world_a.reset(77); world_a.set_tracking_changes(true)
	var world_b = VoxelWorldScript.new(definitions); world_b.reset(77); world_b.set_tracking_changes(true)
	var pos: Vector3i = Vector3i(4, 2, 4)
	_check(world_a.set_micro_cell(pos, cell) and world_b.set_micro_cell(pos, cell), "identical micro commands write deterministically")
	_check(world_a.get_voxel_hash() == world_b.get_voxel_hash(), "microcell content participates in the deterministic world hash")
	var saved: Dictionary = world_a.build_save_data()
	var restored = VoxelWorldScript.new(definitions); restored.reset(77)
	_check(restored.load_save_data(saved) and restored.has_micro_cell(pos), "finite voxel V4 save restores microcells")
	_check(restored.get_micro_cell(pos).content_hash() == cell.content_hash(), "restored microcell preserves its canonical content")

	var color_ids: Array = []
	for raw_id in definitions.keys():
		if str(raw_id).begins_with("color_"): color_ids.append(str(raw_id))
	color_ids.sort()
	_check(definitions.size() > 255 and not color_ids.is_empty(), "WEEDCRAFT keeps its extended 16-bit block palette")
	if not color_ids.is_empty():
		var color_pos: Vector3i = Vector3i(5, 2, 4)
		_check(restored.set_base_block(color_pos, str(color_ids[-1])) and restored.get_block_id(color_pos) == str(color_ids[-1]), "highest color block still round-trips after microvoxel integration")

	if failures == 0: print("WEEDCRAFT asset/save regression checks passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("WEEDCRAFT asset/save regression failed: %s" % message)
