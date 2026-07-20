extends SceneTree


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")
const VoxelHitScript = preload("res://src/voxel_hit.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/structure_studio.tscn") as PackedScene
	if not _assert(packed != null, "Structure Studio scene loads"):
		return
	var studio: Node = packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame

	var player = studio.get("studio_player")
	if not _assert(player is TrumanPlayer and not bool(player.get("creative_flight")), "Studio starts with normal gameplay movement"):
		return
	studio.set("last_space_press_ms", -1000)
	studio.call("_handle_double_space")
	studio.call("_handle_double_space")
	if not _assert(bool(player.get("creative_flight")), "double Space toggles creative flight"):
		return

	var hotbar: Array = studio.get("hotbar_buttons") as Array
	var grid: GridContainer = studio.get("creative_grid") as GridContainer
	var first_slot: ItemSlot = grid.get_child(0) as ItemSlot if grid != null and grid.get_child_count() > 0 else null
	if not _assert(hotbar.size() == 9 and first_slot != null and first_slot.count_text_override == "∞", "creative inventory and hotbar reuse ItemSlot with infinite materials"):
		return
	var radial: Control = studio.get("radial_panel") as Control
	var voxel_size: OptionButton = studio.get("voxel_size_option") as OptionButton
	if not _assert(radial != null and voxel_size != null and voxel_size.item_count == 4, "Tab wheel exposes gameified tools and four voxel scales"):
		return
	var placement_outline: MeshInstance3D = studio.get("placement_outline") as MeshInstance3D
	if not _assert(placement_outline != null and placement_outline.mesh != null, "Studio creates a black placement outline for every voxel scale"):
		return
	for edge in [8, 4, 2, 1]:
		var outline_transform: Transform3D = studio.call("_placement_outline_transform", Vector3i(10, 2, 3), Vector3i.ZERO, edge)
		var expected_size: float = float(edge) / 8.0
		var expected_center: Vector3 = Vector3(10, 2, 3) - Vector3.ONE * 0.5 + Vector3.ONE * expected_size * 0.5
		if not _assert(outline_transform.basis.get_scale().is_equal_approx(Vector3.ONE * expected_size) and outline_transform.origin.is_equal_approx(expected_center), "placement outline matches the exact volume at edge %d" % edge):
			return
	var micro_base: Vector3i = Vector3i(20, 20, 20)
	var zero_normal_hit = VoxelHitScript.new(micro_base, Vector3i.ZERO, "stone", 4.5, Vector3i.ZERO, true)
	var face_cases: Array = [
		[Vector3(micro_base) + Vector3(-5, 0, 0), Vector3.RIGHT, Vector3i.LEFT],
		[Vector3(micro_base) + Vector3(5, 0, 0), Vector3.LEFT, Vector3i.RIGHT],
		[Vector3(micro_base) + Vector3(0, -5, 0), Vector3.UP, Vector3i.DOWN],
		[Vector3(micro_base) + Vector3(0, 5, 0), Vector3.DOWN, Vector3i.UP],
		[Vector3(micro_base) + Vector3(0, 0, -5), Vector3.BACK, Vector3i.FORWARD],
		[Vector3(micro_base) + Vector3(0, 0, 5), Vector3.FORWARD, Vector3i.BACK],
	]
	for face_case in face_cases:
		var expected_normal: Vector3i = face_case[2]
		var target: Vector3i = studio.call("_full_cell_target_for_ray", zero_normal_hit, face_case[0], face_case[1])
		if not _assert(target == micro_base + expected_normal, "full-cell placement resolves the outer microcell face %s" % expected_normal):
			return
	var small_hit = VoxelHitScript.new(micro_base, Vector3i.RIGHT, "stone", 4.5, Vector3i(7, 4, 6), true)
	var small_target: Dictionary = studio.call("_micro_target", small_hit, 2)
	if not _assert(small_target.get("base") == micro_base + Vector3i.RIGHT and small_target.get("local") == Vector3i(0, 4, 6), "smaller voxels keep their snapped microgrid boundary behavior"):
		return

	studio.call("_select_hotbar", 0)
	studio.call("_handle_tool_mouse", MOUSE_BUTTON_WHEEL_DOWN, false)
	if not _assert(int(studio.get("selected_hotbar")) == 1, "plain mouse wheel cycles the creative hotbar"):
		return
	studio.call("_handle_tool_mouse", MOUSE_BUTTON_WHEEL_UP, false)
	studio.set("active_tool", "brush"); studio.set("brush_radius", 1)
	studio.call("_handle_tool_mouse", MOUSE_BUTTON_WHEEL_UP, true)
	if not _assert(int(studio.get("selected_hotbar")) == 0 and int(studio.get("brush_radius")) == 2, "Shift plus wheel keeps the brush radius shortcut without changing slots"):
		return
	studio.set("active_tool", "hand")
	studio.call("_select_voxel_size", 2)
	if not _assert(int(studio.get("micro_edge")) == 2 and bool(studio.call("_uses_micro_placement")), "1/4 scale immediately changes normal hand construction"):
		return

	var copied_pattern = MicroCellScript.new(); copied_pattern.set_material(Vector3i.ZERO, "stone"); copied_pattern.set_material(Vector3i(7, 7, 7), "dirt")
	studio.call("_store_pattern_in_hotbar", copied_pattern)
	var patterns: Dictionary = studio.get("hotbar_patterns") as Dictionary
	var selected_slot: ItemSlot = hotbar[0] as ItemSlot
	if not _assert(patterns.has(0) and selected_slot.item_id.begins_with("studio_pattern_") and player.get("pending_item_block_mesh") != null and int(studio.call("_selected_removal_edge")) == 8, "middle-click pattern occupies the hotbar, appears in hand, and removes as a 1x item"):
		return
	studio.call("_select_hotbar", 1); studio.call("_select_hotbar", 0)
	if not _assert(bool(studio.get("pattern_stamp_active")), "returning to the copied-pattern slot restores stamping"):
		return
	studio.call("_choose_creative_block", "dirt")
	if not _assert(not (studio.get("hotbar_patterns") as Dictionary).has(0), "choosing a creative material replaces the copied pattern in that slot"):
		return

	var workspace = studio.get("workspace")
	workspace.reset()
	var occupied_micro = MicroCellScript.new(); occupied_micro.set_material(Vector3i.ZERO, "stone")
	workspace.set_micro_cell(Vector3i(8, 8, 8), occupied_micro)
	workspace.set_block(Vector3i(9, 8, 8), "dirt")
	var history = studio.get("history"); history.clear()
	var preserved_hash: String = workspace.get_micro_cell(Vector3i(8, 8, 8)).content_hash()
	if not _assert(not bool(studio.call("_can_place_full_cell", Vector3i(8, 8, 8))) and not bool(studio.call("_can_place_full_cell", Vector3i(9, 8, 8))) and workspace.get_micro_cell(Vector3i(8, 8, 8)).content_hash() == preserved_hash and workspace.get_block_id(Vector3i(9, 8, 8)) == "dirt" and not history.can_undo(), "full blocks and copied patterns reject occupied destinations without history or replacement"):
		return
	workspace.reset()
	studio.call("_create_guide_block")
	var full_workspace = workspace.to_template(Vector3i.ZERO, Vector3i(63, 63, 63), "test", "Test")
	if not _assert(full_workspace.blocks.size() == 1 and workspace.get_block_id(Vector3i(32, 0, 32)) == "stone" and bool(studio.get("guide_active")), "empty Studio contains only the central guide"):
		return
	var guide_template = studio.call("_make_current_template")
	if not _assert(guide_template.blocks.is_empty(), "active guide is omitted from export and autosave"):
		return
	studio.call("_apply_block_positions", [Vector3i(33, 0, 32)], "dirt")
	var adjacent_template = studio.call("_make_current_template")
	if not _assert(bool(studio.get("guide_active")) and adjacent_template.size == Vector3i(2, 1, 1) and not adjacent_template.blocks.has(Vector3i.ZERO) and str(adjacent_template.blocks.get(Vector3i(1, 0, 0), "")) == "dirt", "building beside the guide expands export bounds without exporting the guide"):
		return
	workspace.reset()
	studio.call("_create_guide_block")
	studio.call("_apply_block_positions", [Vector3i(32, 0, 32)], "dirt")
	var changed_template = studio.call("_make_current_template")
	if not _assert(not bool(studio.get("guide_active")) and str(changed_template.blocks.get(Vector3i.ZERO, "")) == "dirt", "replacing the guide authors that cell"):
		return
	var micro_cell = MicroCellScript.new(); micro_cell.fill_region(Vector3i.ZERO, 2, "stone")
	studio.call("_apply_micro_cell", Vector3i(33, 1, 32), micro_cell)
	var micro_template = studio.call("_make_current_template")
	if not _assert(micro_template.micro_cells.size() == 1 and int(micro_template.to_dictionary().get("version", 0)) == 4, "Studio exports mixed-resolution cells in structure V4"):
		return
	workspace.reset(); history.clear()
	var custom_cell = MicroCellScript.new(); custom_cell.fill_region(Vector3i.ZERO, 2, "stone"); workspace.set_micro_cell(Vector3i(10, 10, 10), custom_cell)
	studio.set("selection_a", Vector3i(10, 10, 10)); studio.set("selection_b", Vector3i(10, 10, 10))
	studio.call("_select_option_metadata", studio.get("asset_kind_option"), "custom_block")
	var custom_export = studio.call("_make_current_template")
	if not _assert(custom_export.asset_kind == "custom_block" and custom_export.validate(BlockCatalogScript.blocks()).is_empty(), "export selector produces a valid Custom Block from one microcell"):
		return
	var registry = studio.get("project_asset_registry"); custom_export.structure_id = "studio_component_test"; custom_export.display_name = "Studio Component"; registry.assets[custom_export.structure_id] = custom_export
	studio.get("studio_asset_system").configure(workspace, registry); workspace.reset(); history.clear()
	studio.call("_place_project_asset", custom_export, Vector3i(12, 12, 12))
	studio.set("selection_a", Vector3i(12, 12, 12)); studio.set("selection_b", Vector3i(12, 12, 12)); studio.call("_select_option_metadata", studio.get("asset_kind_option"), "structure")
	var component_export = studio.call("_make_current_template")
	if not _assert(component_export.components.size() == 1 and component_export.micro_cells.is_empty(), "Studio preserves a Custom Block as a component reference instead of flattening it"):
		return
	workspace.reset(); workspace.set_block(Vector3i(14, 12, 12), "cobblestone"); workspace.set_block(Vector3i(14, 13, 12), "wood")
	workspace.markers = [{"type": "anchor", "pos": [14, 12, 12]}]
	studio.set("selection_a", Vector3i(14, 12, 12)); studio.set("selection_b", Vector3i(14, 13, 12)); studio.call("_select_option_metadata", studio.get("asset_kind_option"), "multiblock"); studio.call("_select_option_metadata", studio.get("placement_mode_option"), "assembled"); studio.get("utility_id_edit").text = "studio_machine"
	var assembled_export = studio.call("_make_current_template")
	if not _assert(assembled_export.asset_kind == "multiblock" and assembled_export.placement_mode == "assembled" and assembled_export.requirements.size() == 2 and assembled_export.anchor == Vector3i.ZERO, "Studio exports an anchored assembled multiblock recipe"):
		return

	studio.queue_free()
	await process_frame
	print("Structure Studio regression checks passed.")
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Structure Studio regression failed: %s" % message)
	quit(1)
	return false

