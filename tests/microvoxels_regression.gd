extends SceneTree


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const StructureWorkspaceScript = preload("res://src/structure_workspace.gd")
const VoxelSectionMesherScript = preload("res://src/voxel_section_mesher.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions: Dictionary = BlockCatalogScript.blocks()
	var cell = MicroCellScript.new()
	_check(cell.fill_region(Vector3i.ZERO, 4, "stone"), "1/2 voxel fills a 4-cubed aligned region")
	_check(cell.occupied_count() == 64, "canonical occupancy stores 64 eighths for a half-size piece")
	cell.fill_region(Vector3i(4, 0, 0), 2, "dirt")
	_check(cell.get_material(Vector3i(4, 0, 0)) == "dirt" and cell.get_piece_edge(Vector3i.ZERO) == 4 and cell.get_piece_edge(Vector3i(4, 0, 0)) == 2, "one cell preserves mixed materials and authored piece scales")
	_check(not cell.fill_region(Vector3i(2, 0, 0), 2, "dirt", true), "piece placement rejects any partially occupied target region")
	var restored = MicroCellScript.from_dictionary(cell.to_dictionary(), definitions)
	_check(restored != null and restored.content_hash() == cell.content_hash() and restored.get_piece_edge(Vector3i.ZERO) == 4, "microcell material and edge RLE round-trip deterministically")
	var rotated = cell.transformed(1)
	_check(rotated.occupied_count() == cell.occupied_count() and rotated.content_hash() != cell.content_hash() and rotated.get_piece_edge(Vector3i(7, 0, 0)) == 4, "rotation transforms occupancy while preserving piece scale")
	var cut = MicroCellScript.new(); cut.fill_region(Vector3i.ZERO, 4, "stone"); cut.clear_region(Vector3i.ZERO, 2)
	_check(cut.get_material(Vector3i.ZERO) == "" and cut.get_piece_edge(Vector3i(2, 0, 0)) == 2, "cutting a 1/2 piece with 1/4 subdivides every survivor to 1/4")
	cut.clear_region(Vector3i(2, 0, 0), 1)
	_check(cut.get_material(Vector3i(2, 0, 0)) == "" and cut.get_piece_edge(Vector3i(3, 0, 0)) == 1, "cutting a 1/4 survivor with 1/8 subdivides its survivors to 1/8")

	var template = StructureTemplateScript.new()
	template.structure_id = "micro_test"; template.display_name = "Micro Test"; template.size = Vector3i(2, 1, 1)
	template.micro_cells[Vector3i.ZERO] = cell
	var template_restored = StructureTemplateScript.from_dictionary(template.to_dictionary())
	_check(template_restored != null and int(template_restored.to_dictionary().get("version", 0)) == 4 and template_restored.micro_cells.size() == 1, "structure V4 embeds microcells while keeping sparse base coordinates")

	var workspace = StructureWorkspaceScript.new(definitions)
	workspace.set_micro_cell(Vector3i(2, 2, 2), cell)
	var hit = workspace.raycast_hit(Vector3(1.6875, 1.6875, 0.0), Vector3.BACK, 6.0)
	_check(hit != null and hit.is_micro and hit.pos == Vector3i(2, 2, 2), "two-level DDA hits occupied microvoxels in 3D")
	var snapshot: Dictionary = workspace.make_section_snapshot(Vector3i.ZERO)
	var mesh_result: Dictionary = VoxelSectionMesherScript.build(snapshot, workspace.get_render_palette(), false)
	_check(not (mesh_result.get("opaque", []) as Array).is_empty() and not (mesh_result.get("collision_faces", PackedVector3Array()) as PackedVector3Array).is_empty(), "microvoxels emit visible faces and matching collision")

	var uv_workspace = StructureWorkspaceScript.new(definitions)
	var uv_cell = MicroCellScript.new(); uv_cell.fill_region(Vector3i.ZERO, 4, "stone"); uv_cell.fill_region(Vector3i(4, 0, 0), 4, "stone")
	uv_workspace.set_micro_cell(Vector3i(2, 2, 2), uv_cell)
	var uv_mesh: Dictionary = VoxelSectionMesherScript.build(uv_workspace.make_section_snapshot(Vector3i.ZERO), uv_workspace.get_render_palette(), false)
	_check(_all_quads_fill_unit_tile(uv_mesh.get("opaque", []) as Array) and _count_normal_vertices(uv_mesh.get("opaque", []) as Array, Vector3.UP) == 8, "adjacent 1/2 pieces keep one complete texture and one top quad each")

	var mixed_workspace = StructureWorkspaceScript.new(definitions)
	mixed_workspace.set_block(Vector3i(2, 2, 2), "stone")
	var touching_cell = MicroCellScript.new(); touching_cell.set_material(Vector3i.ZERO, "stone")
	mixed_workspace.set_micro_cell(Vector3i(3, 2, 2), touching_cell)
	var mixed_mesh: Dictionary = VoxelSectionMesherScript.build(mixed_workspace.make_section_snapshot(Vector3i.ZERO), mixed_workspace.get_render_palette(), false)
	_check(_count_face_vertices(mixed_mesh.get("opaque", []) as Array, Vector3.RIGHT, 0, 2.5) == 4, "normal block keeps one full textured face beside a partial microcell")

	var world = VoxelWorldScript.new(definitions); world.reset(123); world.set_tracking_changes(true)
	world.set_micro_cell(Vector3i(4, 4, 4), cell)
	var saved: Dictionary = world.build_save_data()
	var loaded = VoxelWorldScript.new(definitions); loaded.reset(123)
	_check(loaded.load_save_data(saved) and loaded.has_micro_cell(Vector3i(4, 4, 4)) and loaded.get_micro_cell(Vector3i(4, 4, 4)).get_piece_edge(Vector3i.ZERO) == 4, "world V4 sparse micro delta preserves authored piece scale")
	var full = MicroCellScript.new(); full.fill_region(Vector3i.ZERO, 8, "stone")
	world.set_micro_cell(Vector3i(5, 5, 5), full)
	_check(world.get_block_id(Vector3i(5, 5, 5)) == "stone" and not world.has_micro_cell(Vector3i(5, 5, 5)), "full single-material microcell normalizes to a regular voxel")
	var small_full = MicroCellScript.new()
	for y in [0, 4]:
		for z in [0, 4]:
			for x in [0, 4]: small_full.fill_region(Vector3i(x, y, z), 4, "stone")
	world.set_micro_cell(Vector3i(6, 5, 5), small_full)
	_check(world.has_micro_cell(Vector3i(6, 5, 5)) and world.get_block_id(Vector3i(6, 5, 5)) == "", "a full cell made from eight 1/2 pieces keeps its piece scales")

	if failures == 0: print("Microvoxel regression checks passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("Microvoxel regression failed: %s" % message)


func _all_quads_fill_unit_tile(surfaces: Array) -> bool:
	var found_quad: bool = false
	for raw_surface in surfaces:
		var arrays: Array = (raw_surface as Dictionary).get("arrays", []) as Array
		if arrays.size() <= Mesh.ARRAY_TEX_UV or arrays[Mesh.ARRAY_TEX_UV] == null: continue
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		if uvs.size() % 4 != 0: return false
		for start in range(0, uvs.size(), 4):
			found_quad = true
			var minimum: Vector2 = uvs[start]
			var maximum: Vector2 = uvs[start]
			for offset in range(1, 4):
				minimum = minimum.min(uvs[start + offset])
				maximum = maximum.max(uvs[start + offset])
			if not minimum.is_equal_approx(Vector2.ZERO) or not maximum.is_equal_approx(Vector2.ONE): return false
	return found_quad


func _count_normal_vertices(surfaces: Array, wanted_normal: Vector3) -> int:
	var count: int = 0
	for raw_surface in surfaces:
		var arrays: Array = (raw_surface as Dictionary).get("arrays", []) as Array
		if arrays.size() <= Mesh.ARRAY_NORMAL or arrays[Mesh.ARRAY_NORMAL] == null: continue
		for normal in arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array:
			if normal.is_equal_approx(wanted_normal): count += 1
	return count


func _count_face_vertices(surfaces: Array, wanted_normal: Vector3, axis: int, coordinate: float) -> int:
	var count: int = 0
	for raw_surface in surfaces:
		var arrays: Array = (raw_surface as Dictionary).get("arrays", []) as Array
		if arrays.size() <= Mesh.ARRAY_NORMAL or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_NORMAL] == null: continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		for index in range(mini(vertices.size(), normals.size())):
			if normals[index].is_equal_approx(wanted_normal) and is_equal_approx(vertices[index][axis], coordinate): count += 1
	return count

