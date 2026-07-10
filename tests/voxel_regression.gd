extends SceneTree

const VoxelWorldScript = preload("res://src/voxel_world.gd")
const VoxelSectionMesherScript = preload("res://src/voxel_section_mesher.gd")
const VoxelTextureArrayScript = preload("res://src/voxel_texture_array.gd")
const TerrainTileDataScript = preload("res://src/terrain_tile_data.gd")
const TerrainGeneratorScript = preload("res://src/terrain_generator.gd")
const CaveNetworkRasterizerScript = preload("res://src/cave_network_rasterizer.gd")
const TerrainMap2DScript = preload("res://src/terrain_map_2d.gd")
const StructureTemplateDataScript = preload("res://src/structure_template_data.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const StructurePlacerScript = preload("res://src/structure_placer.gd")
const StructureWorkspaceScript = preload("res://src/structure_workspace.gd")
const AuthoringHistoryScript = preload("res://src/authoring_history.gd")
const GenerationReportScript = preload("res://src/generation_report.gd")
const AuthoringBaseScript = preload("res://src/authoring_scene_base.gd")
const TerrainEditorScript = preload("res://src/terrain_editor.gd")
const StructureStudioScript = preload("res://src/structure_studio.gd")
const BlockCatalogScript = preload("res://src/block_catalog.gd")
const VoxelDependencyResolverScript = preload("res://src/voxel_dependency_resolver.gd")
const VoxelDebrisSystemScript = preload("res://src/voxel_debris_system.gd")
# Compile smoke coverage for the runtime integration scripts as well.
const PerformanceProfileScript = preload("res://src/performance_profile.gd")
const VoxelSectionSystemScript = preload("res://src/voxel_section_system.gd")
const MainScript = preload("res://src/main.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var directed_tile = TerrainTileDataScript.create_draft(99173, Vector2i.ZERO)
	var restored_tile = TerrainTileDataScript.from_dictionary(directed_tile.to_dictionary())
	_assert(restored_tile != null and restored_tile.content_hash() == directed_tile.content_hash(), "directed terrain RLE round-trips exactly")
	_assert(int(directed_tile.to_dictionary().get("version", 0)) == 2 and directed_tile.cave_networks.size() == 2, "Terrain Tile V2 stores the two authored cave networks")
	_assert(directed_tile.get_height(50, 50) >= TerrainTileDataScript.MIN_SURFACE_Y and directed_tile.get_height(50, 50) <= TerrainTileDataScript.MAX_SURFACE_Y, "directed draft respects authored altitude bounds")
	var plains_cells: int = 0
	for height in directed_tile.heights:
		if abs(int(height) - 12) <= 2: plains_cells += 1
	_assert(plains_cells >= 8500, "Biome 1 draft keeps at least 85 percent of its surface in the plains band")
	var legacy_data: Dictionary = directed_tile.to_dictionary()
	legacy_data["version"] = 1
	legacy_data.erase("cave_networks"); legacy_data.erase("cave_overrides")
	legacy_data["cave_entrances"] = [{"x": 20, "z": 20, "radius": 3, "depth": 12}]
	var migrated_tile = TerrainTileDataScript.from_dictionary(legacy_data)
	_assert(migrated_tile != null and migrated_tile.cave_networks.size() == 1 and int(migrated_tile.to_dictionary().get("version", 0)) == 2, "Terrain Tile V1 entrances migrate in memory and export as V2")
	var bad_network_tile = directed_tile.duplicate_tile()
	((bad_network_tile.cave_networks[0] as Dictionary).get("nodes", []) as Array)[0]["radius"] = 8
	_assert(not bad_network_tile.validate().is_empty(), "entry radii outside 2 through 7 are rejected")
	var template = StructureTemplateDataScript.new()
	template.structure_id = "regression_hut"
	template.display_name = "Regression Hut"
	template.size = Vector3i(3, 3, 2)
	template.pivot = Vector3i(1, 0, 1)
	template.blocks[Vector3i(0, 0, 0)] = "stone"
	template.metadata[Vector3i(0, 0, 0)] = {"custom_name": "pedra de teste"}
	template.explicit_air[Vector3i(1, 1, 0)] = true
	template.markers.append({"type": "foundation", "pos": [0, 0, 0], "block": "stone"})
	var restored_template = StructureTemplateDataScript.from_dictionary(template.to_dictionary())
	_assert(restored_template != null and restored_template.blocks.get(Vector3i.ZERO, "") == "stone" and restored_template.explicit_air.has(Vector3i(1, 1, 0)) and restored_template.metadata.get(Vector3i.ZERO, {}).get("custom_name", "") == "pedra de teste", "structure blocks, metadata, markers, and explicit air round-trip")
	_assert(template.transform_position(Vector3i(0, 0, 0), 1) == Vector3i(1, 0, 0) and template.transformed_size(1) == Vector3i(2, 3, 3), "structure quarter rotation transforms bounds deterministically")
	_assert(template.transform_position(Vector3i(0, 0, 0), 0, true, true) == Vector3i(2, 0, 1), "structure mirroring transforms sparse coordinates deterministically")
	var invalid_template = StructureTemplateDataScript.from_dictionary(template.to_dictionary())
	invalid_template.explicit_air[Vector3i.ZERO] = true
	_assert(not invalid_template.validate(BlockCatalogScript.blocks()).is_empty(), "template validation rejects block and explicit-air overlap")
	var workspace = StructureWorkspaceScript.new(BlockCatalogScript.blocks())
	workspace.set_block(Vector3i(2, 2, 2), "planks")
	workspace.pivot = Vector3i(2, 2, 2)
	var workspace_template = workspace.to_template(Vector3i(1, 1, 1), Vector3i(3, 3, 3), "workspace_test", "Workspace Test")
	_assert(workspace_template.blocks.get(Vector3i(1, 1, 1), "") == "planks" and workspace_template.pivot == Vector3i(1, 1, 1), "Structure Workspace exports selection-local coordinates")
	var history = AuthoringHistoryScript.new()
	history.push({"type": "test", "before": 1, "after": 2})
	_assert(history.pop_undo().get("before", 0) == 1 and history.pop_redo().get("after", 0) == 2, "authoring history preserves undo/redo commands")
	var deterministic_world_a = VoxelWorldScript.new(BlockCatalogScript.blocks())
	var deterministic_world_b = VoxelWorldScript.new(BlockCatalogScript.blocks())
	deterministic_world_a.reset(99173)
	deterministic_world_b.reset(99173)
	var empty_registry = StructureRegistryScript.empty_registry()
	var directed_generator = TerrainGeneratorScript.new()
	_assert(directed_generator.generate_into(deterministic_world_a, directed_tile, empty_registry, 99173).is_ok(), "directed terrain generation succeeds")
	_assert(directed_generator.generate_into(deterministic_world_b, restored_tile, empty_registry, 99173).is_ok(), "restored directed tile generation succeeds")
	_assert(deterministic_world_a.get_voxel_hash() == deterministic_world_b.get_voxel_hash(), "directed generation is deterministic by tile and seed")
	_assert(not deterministic_world_a.has_block(Vector3i(18, -18, 57)) and not deterministic_world_a.has_block(Vector3i(49, -55, 50)), "authored chambers and the deep cross-network connection are rasterized")
	_assert(deterministic_world_a.has_block(Vector3i(50, -20, 10)) and deterministic_world_a.get_block_id(Vector3i(50, -65, 10)) == "bedrock", "random caves outside authored networks are gone and bedrock remains intact")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
	var placed_template = StructureTemplateDataScript.new()
	placed_template.structure_id = "anchored_test"
	placed_template.display_name = "Anchored Test"
	placed_template.size = Vector3i(3, 3, 3)
	placed_template.pivot = Vector3i(1, 0, 1)
	placed_template.blocks[Vector3i(1, 0, 1)] = "crafting_table"
	placed_template.explicit_air[Vector3i(1, 1, 1)] = true
	placed_template.markers.append({"type": "foundation", "pos": [1, 0, 1], "block": "stone"})
	var placed_template_path: String = "user://authoring/regression_anchor.tstructure.json"
	_assert(placed_template.save_to_file(placed_template_path, BlockCatalogScript.blocks()) == OK, "structure template exports atomically")
	var placement_tile = TerrainTileDataScript.create_draft(77881, Vector2i.ZERO)
	placement_tile.anchors.append({"template_id": "anchored_test", "x": 12, "z": 12, "rotation": 0, "mode": "surface_adaptive"})
	var placement_registry = StructureRegistryScript.empty_registry()
	placement_registry.entries["anchored_test"] = {"id": "anchored_test", "path": placed_template_path, "mode": "surface_adaptive", "zone_mask": TerrainTileDataScript.ZONE_STRUCTURES, "weight": 0.0, "spacing": 24, "rotations": [0], "allow_mirror_x": false, "allow_mirror_z": false, "max_slope": 16, "max_support_depth": 24, "min_depth": 12, "max_depth": 42, "minimum_cover": 4}
	var placement_world = VoxelWorldScript.new(BlockCatalogScript.blocks())
	placement_world.reset(77881)
	var placement_report = directed_generator.generate_into(placement_world, placement_tile, placement_registry, 77881)
	_assert(placement_report.is_ok() and placement_report.instances.size() == 1, "manual surface anchor plans one structure")
	if not placement_report.instances.is_empty():
		var instance_origin: Vector3i = placement_report.instances[0].get("origin", Vector3i.ZERO)
		_assert(placement_world.get_block_id(instance_origin + Vector3i(1, 0, 1)) == "crafting_table" and not placement_world.has_block(instance_origin + Vector3i(1, 1, 1)), "structure blocks and explicit air override directed terrain")
	var placer = StructurePlacerScript.new()
	var invalid_rotation_tile = placement_tile.duplicate_tile()
	invalid_rotation_tile.anchors = [{"template_id": "anchored_test", "x": 12, "z": 12, "rotation": 1, "mode": "surface_adaptive"}]
	var invalid_rotation_report = GenerationReportScript.new()
	_assert(placer.plan_instances(placement_world, invalid_rotation_tile, placement_registry, 77881, invalid_rotation_report).is_empty() and not invalid_rotation_report.errors.is_empty(), "manual anchor rejects rotations not allowed by its registry rule")
	var protected_tile = placement_tile.duplicate_tile()
	protected_tile.zone_flags[protected_tile.index_of(12, 12)] = TerrainTileDataScript.ZONE_PROTECTED
	protected_tile.anchors = [{"template_id": "anchored_test", "x": 12, "z": 12, "rotation": 0, "mode": "surface_adaptive"}]
	var protected_report = GenerationReportScript.new()
	_assert(placer.plan_instances(placement_world, protected_tile, placement_registry, 77881, protected_report).is_empty() and not protected_report.errors.is_empty(), "manual anchor visibly rejects protected terrain")
	var bedrock_tile = placement_tile.duplicate_tile()
	bedrock_tile.anchors = [{"template_id": "anchored_test", "x": 12, "z": 12, "y": -65, "rotation": 0, "mode": "underground"}]
	var bedrock_report = GenerationReportScript.new()
	_assert(placer.plan_instances(placement_world, bedrock_tile, placement_registry, 77881, bedrock_report).is_empty() and not bedrock_report.errors.is_empty(), "manual anchor rejects structure bounds intersecting bedrock")
	var overlap_tile = placement_tile.duplicate_tile()
	overlap_tile.anchors = [
		{"template_id": "anchored_test", "x": 12, "z": 12, "rotation": 0, "mode": "surface_adaptive"},
		{"template_id": "anchored_test", "x": 13, "z": 12, "rotation": 0, "mode": "surface_adaptive"},
	]
	var overlap_report = GenerationReportScript.new()
	_assert(placer.plan_instances(placement_world, overlap_tile, placement_registry, 77881, overlap_report).size() == 1 and not overlap_report.errors.is_empty(), "overlapping manual structures keep the first plan and report the conflict")
	var world = VoxelWorldScript.new(BlockCatalogScript.blocks())
	world.reset(1235571)
	var texture_array = VoxelTextureArrayScript.new()
	_assert(texture_array.build(BlockCatalogScript.blocks()), "16x16 texture array builds from normalized source images")
	var opaque_shader: String = texture_array._shader_code_for("opaque")
	var cutout_shader: String = texture_array._shader_code_for("cutout")
	var micro_shader: String = texture_array._shader_code_for("micro_foliage")
	_assert(opaque_shader.find("ALPHA =") == -1, "opaque texture-array shader stays in the depth-writing opaque pipeline")
	_assert(cutout_shader.find("ALPHA = step") >= 0 and cutout_shader.find("ALPHA_SCISSOR_THRESHOLD") >= 0, "cutout shader keeps binary foliage transparency")
	_assert(micro_shader.contains("voxel_player_position") and micro_shader.contains("voxel_player_velocity") and micro_shader.contains("COLOR.a"), "micro foliage shader reacts to wind and player movement")
	world.configure_texture_layers(texture_array.layer_by_path)
	var grass_descriptor: Dictionary = {}
	for raw_descriptor in world.get_render_palette().values():
		var descriptor: Dictionary = raw_descriptor as Dictionary
		if str(descriptor.get("block_id", "")) == "grass":
			grass_descriptor = descriptor
			break
	var grass_layers: Dictionary = grass_descriptor.get("texture_layers", {}) as Dictionary
	_assert(not grass_layers.is_empty() and grass_layers.get("top", -1) != grass_layers.get("north", -1) and grass_layers.get("bottom", -1) != grass_layers.get("top", -1), "grass top, side, and bottom use distinct texture-array layers")
	var stone_pos: Vector3i = Vector3i(4, 0, 4)
	_assert(world.set_base_block(stone_pos, "stone"), "base block writes to packed storage")
	_assert(world.get_block_id(stone_pos) == "stone", "palette lookup round-trips")
	_assert(world.get_block_id(Vector3i(200, 0, 0)) == "", "world bounds reject out-of-range positions")
	_assert(not world.set_block(Vector3i(100, 0, 4), "stone"), "locked biomes reject edits")
	var hit: Dictionary = world.raycast_voxels(Vector3(4.0, 0.0, 8.0), Vector3(0.0, 0.0, -1.0), 8.0)
	_assert(not hit.is_empty() and hit.get("pos", Vector3i.ZERO) == stone_pos, "DDA finds a voxel without physics bodies")
	_assert(hit.get("normal", Vector3i.ZERO) == Vector3i(0, 0, 1), "DDA reports the placement normal")
	_assert(world.set_base_block(Vector3i(5, 0, 4), "stone"), "adjacent base voxel writes")
	var section: Vector3i = world.get_section_coord(stone_pos)
	var result: Dictionary = VoxelSectionMesherScript.build(world.make_section_snapshot(section), world.get_render_palette(), false)
	_assert(not (result.get("opaque", []) as Array).is_empty(), "mesher emits opaque geometry")
	_assert(not (result.get("collision_faces", PackedVector3Array()) as PackedVector3Array).is_empty(), "mesher emits static collision triangles")
	var outward_by_face: Dictionary = {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"east": Vector3(1, 0, 0),
		"west": Vector3(-1, 0, 0),
		"top": Vector3(0, 1, 0),
		"bottom": Vector3(0, -1, 0),
	}
	for face_name in outward_by_face.keys():
		var corners: PackedVector3Array = VoxelSectionMesherScript._face_corners(str(face_name), Vector3i.ZERO, Vector2i(1, 1))
		var winding_normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
		_assert(winding_normal.dot(outward_by_face[face_name]) < -0.99, "%s face keeps Godot clockwise outward winding" % face_name)
	var top_uvs: PackedVector2Array = VoxelSectionMesherScript._face_uvs(Vector2i(1, 1), "top", 0)
	var side_uvs: PackedVector2Array = VoxelSectionMesherScript._face_uvs(Vector2i(1, 1), "north", 0)
	_assert(top_uvs[0] == Vector2.ZERO and side_uvs[0] == Vector2(0, 1), "top and side UV orientation matches legacy block textures")
	var greedy_index_count: int = 0
	for surface in result.get("opaque", []) as Array:
		var arrays: Array = (surface as Dictionary).get("arrays", []) as Array
		greedy_index_count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	_assert(greedy_index_count == 36, "greedy mesher reduces an adjacent pair to six quads")
	var plant_pos: Vector3i = Vector3i(8, 1, 8)
	_assert(world.set_base_block(plant_pos, "poppy"), "plant voxel writes without a physics body")
	var plant_result: Dictionary = VoxelSectionMesherScript.build(world.make_section_snapshot(world.get_section_coord(plant_pos)), world.get_render_palette(), false)
	var plant_surfaces: Array = plant_result.get("cutout", []) as Array
	_assert(not plant_surfaces.is_empty() and str((plant_surfaces[0] as Dictionary).get("render_class", "")) == "cutout", "plants use alpha-scissored cutout rendering")
	var support_pos: Vector3i = Vector3i(9, 0, 8)
	_assert(world.set_base_block(support_pos, "dirt") and world.set_base_block(support_pos + Vector3i.UP, "poppy"), "supported plant test voxels write")
	var dependent_removals: Array[Vector3i] = VoxelDependencyResolverScript.collect_removal_positions(world, support_pos, BlockCatalogScript.blocks())
	_assert(dependent_removals.size() == 2 and dependent_removals.has(support_pos + Vector3i.UP), "breaking plant support cascades to the flower")
	_assert(VoxelDependencyResolverScript.can_place(world, support_pos + Vector3i.UP, "poppy", BlockCatalogScript.blocks()) and not VoxelDependencyResolverScript.can_place(world, Vector3i(10, 1, 8), "poppy", BlockCatalogScript.blocks()), "plant placement requires solid support")
	var micro_pos: Vector3i = Vector3i(11, 0, 8)
	_assert(world.set_base_block(micro_pos, "grass") and world.set_base_block(micro_pos + Vector3i(2, 0, 0), "leaves"), "micro foliage source blocks write")
	var micro_low: Dictionary = VoxelSectionMesherScript.build(world.make_section_snapshot(world.get_section_coord(micro_pos)), world.get_render_palette(), false, 2)
	var micro_high: Dictionary = VoxelSectionMesherScript.build(world.make_section_snapshot(world.get_section_coord(micro_pos)), world.get_render_palette(), false, 4)
	var low_vertices: int = 0
	var high_vertices: int = 0
	for surface in micro_low.get("micro_foliage", []) as Array:
		low_vertices += (((surface as Dictionary).get("arrays", []) as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for surface in micro_high.get("micro_foliage", []) as Array:
		high_vertices += (((surface as Dictionary).get("arrays", []) as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_assert(low_vertices > 0 and high_vertices > low_vertices, "grass tops and exposed leaf faces emit preset-scaled microgeometry")
	var debris = VoxelDebrisSystemScript.new()
	root.add_child(debris)
	debris.configure(BlockCatalogScript.blocks(), 8)
	debris.emit_burst(micro_pos, Vector3i.UP, "grass", 12)
	_assert(debris.active_count() == 8, "voxel debris reuses its fixed preset capacity")
	debris.update_particles(0.016, world)
	debris.queue_free()
	var edge_pos: Vector3i = Vector3i(15, 0, 4)
	var edge_section: Vector3i = world.get_section_coord(edge_pos)
	var neighbor_section: Vector3i = edge_section + Vector3i(1, 0, 0)
	var edge_revision: int = world.get_section_revision(edge_section)
	var neighbor_revision: int = world.get_section_revision(neighbor_section)
	world.set_tracking_changes(true)
	_assert(world.set_block(edge_pos, "dirt"), "editable section-boundary voxel writes")
	_assert(world.get_section_revision(edge_section) > edge_revision and world.get_section_revision(neighbor_section) > neighbor_revision, "boundary edit invalidates both sections")
	var chest_pos: Vector3i = Vector3i(7, 0, 4)
	_assert(world.set_base_block(chest_pos, "chest"), "stateful chest base voxel writes")
	_assert(world.set_metadata(chest_pos, "chest_inventory", [{"item": "planks", "count": 3}]), "sparse chest metadata writes")
	_assert(world.remove_block(stone_pos), "removing an existing voxel succeeds")
	var save_data: Dictionary = world.build_save_data()
	_assert(int(save_data.get("palette_version", 0)) == 1, "V3 saves record the stable palette version")
	var restored = VoxelWorldScript.new(BlockCatalogScript.blocks())
	restored.reset(1235571)
	restored.set_base_block(stone_pos, "stone")
	restored.set_base_block(Vector3i(5, 0, 4), "stone")
	restored.set_base_block(chest_pos, "chest")
	_assert(restored.load_save_data(save_data), "V3 save data loads")
	_assert(restored.get_block_id(stone_pos) == "", "V3 sparse delta preserves removals")
	_assert(restored.has_metadata(chest_pos, "chest_inventory"), "V3 sparse chest metadata round-trips")
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_assert(main_scene != null, "main scene loads")
	var main_node: Node = main_scene.instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	_assert(is_instance_valid(main_node), "main scene starts without parser or ready errors")
	main_node.call("_start_new_game")
	await process_frame
	var loaded: bool = false
	for _frame in range(1800):
		await process_frame
		if not bool(main_node.get("is_loading_world")) and bool(main_node.get("game_started")):
			loaded = true
			break
	_assert(loaded, "finite voxel world loads through the section worker pipeline")
	var runtime_player: CharacterBody3D = main_node.get("player") as CharacterBody3D
	_assert(runtime_player != null, "runtime player exists after section colliders are uploaded")
	for _physics_frame in range(120):
		await physics_frame
	var expected_floor_y: float = float(main_node.call("_surface_y_at", 50, 50)) + 0.5
	_assert(runtime_player.is_on_floor() and abs(runtime_player.global_position.y - expected_floor_y) < 0.2, "section concave collider supports the player on top faces")
	main_node.queue_free()
	await process_frame
	var terrain_editor_scene: PackedScene = load("res://scenes/terrain_editor.tscn") as PackedScene
	var terrain_editor: Node = terrain_editor_scene.instantiate()
	root.add_child(terrain_editor)
	await process_frame
	await process_frame
	_assert(terrain_editor.get("tile") != null and terrain_editor.get("section_system") != null, "Terrain Editor starts with a directed tile and live voxel preview")
	_assert(terrain_editor.get("map_2d") != null and bool((terrain_editor.get("map_2d") as Control).visible), "Terrain Editor starts in the editable 100x100 map view")
	terrain_editor.queue_free()
	await process_frame
	var structure_studio_scene: PackedScene = load("res://scenes/structure_studio.tscn") as PackedScene
	var structure_studio: Node = structure_studio_scene.instantiate()
	root.add_child(structure_studio)
	await process_frame
	await process_frame
	_assert(structure_studio.get("workspace") != null and structure_studio.get("section_system") != null, "Structure Studio starts with an independent 64-cubed workspace")
	_assert(structure_studio.get("creative_inventory_panel") != null and (structure_studio.get("hotbar_blocks") as Array).size() == 9 and not bool((structure_studio.get("advanced_panel") as Control).visible), "Structure Studio starts in creative building mode with inventory, hotbar, and hidden advanced bar")
	var creative_player = structure_studio.get("studio_player")
	var studio_workspace = structure_studio.get("workspace")
	_assert(creative_player is TrumanPlayer and bool(creative_player.get("creative_flight")) and creative_player.get("camera").current, "Structure Studio reuses the gameplay TrumanPlayer in creative flight mode")
	_assert(studio_workspace.get_block_id(Vector3i(32, 0, 32)) == "grass", "Structure Studio always restores a visible grass guide floor")
	structure_studio.queue_free()
	await process_frame
	_assert(FileAccess.file_exists("res://tools/terrain_editor_web/index.html"), "standalone HTML terrain editor is included")
	var html_file: FileAccess = FileAccess.open("res://tools/terrain_editor_web/index.html", FileAccess.READ)
	var html_source: String = html_file.get_as_text() if html_file != null else ""
	_assert(html_source.contains("Importar heightmap PNG") and html_source.contains("JSON textual") and html_source.contains("cave_networks"), "HTML editor exposes image, text, and cave-network authoring")
	print("Voxel regression checks passed.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Voxel regression failed: %s" % message)
	quit(1)
