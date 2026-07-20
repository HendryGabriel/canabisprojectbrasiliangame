extends SceneTree


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const GenerationReportScript = preload("res://src/generation_report.gd")
const SpawnGraphScript = preload("res://src/structure_spawn_graph.gd")
const StructurePlacerScript = preload("res://src/structure_placer.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const TerrainGeneratorScript = preload("res://src/terrain_generator.gd")
const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
	var profile: Dictionary = SpawnGraphScript.default_profile(Vector2i.ZERO)
	for raw_node in profile.get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if str(node.get("type", "")) == "chance": (node.get("params", {}) as Dictionary)["value"] = 1.0
	var template = StructureTemplateScript.new()
	template.structure_id = "structure_v2_check"; template.display_name = "Structure V2 Check"
	template.size = Vector3i(2, 2, 2); template.pivot = Vector3i.ZERO
	template.blocks[Vector3i.ZERO] = "stone"; template.explicit_air[Vector3i(0, 1, 0)] = true
	template.markers.append({"type": "foundation", "pos": [0, 0, 0]})
	template.spawn_profiles = [profile]
	var path: String = "user://authoring/structure_v2_check.tstructure.json"
	_check(template.save_to_file(path, BlockCatalogScript.blocks()) == OK, "V2 asset saves atomically")
	var restored = StructureTemplateScript.load_from_file(path)
	_check(restored != null and restored.spawn_profiles.size() == 1 and int(restored.to_dictionary().get("version", 0)) == 4, "V4 structure and spawn graph round-trip in one file")
	var legacy: Dictionary = template.to_dictionary(); legacy["version"] = 1; legacy.erase("spawn_profiles")
	var migrated = StructureTemplateScript.from_dictionary(legacy)
	_check(migrated != null and migrated.spawn_profiles.is_empty() and int(migrated.to_dictionary().get("version", 0)) == 4, "V1 structure remains readable and saves as V4")
	var cyclic: Dictionary = profile.duplicate(true); (cyclic.get("connections", []) as Array).append({"from": "gerar", "to": "candidatos"})
	_check(not SpawnGraphScript.validate_profile(cyclic).is_empty(), "graph cycles are rejected")

	var tile = TerrainTileScript.create_draft(44017, Vector2i.ZERO)
	tile.heights.fill(8); tile.cave_networks.clear(); tile.cave_overrides = {"carve": [], "fill": []}; tile.anchors.clear()
	var world = VoxelWorldScript.new(BlockCatalogScript.blocks()); world.reset(44017)
	TerrainGeneratorScript.new().generate_into(world, tile, StructureRegistryScript.empty_registry(), 44017)
	var invalid_registry = StructureRegistryScript.empty_registry(); var invalid_compiled: Dictionary = SpawnGraphScript.compile(cyclic)
	invalid_registry.embedded_profiles.append({"id": "invalid_v2", "path": path, "profile_id": "cyclic", "profile": cyclic, "compiled": invalid_compiled, "compile_errors": invalid_compiled.get("errors", []), "embedded": true})
	var invalid_report = GenerationReportScript.new()
	_check(StructurePlacerScript.new().plan_instances(world, tile, invalid_registry, 1, invalid_report).is_empty() and not invalid_report.warnings.is_empty(), "invalid V2 profile is warned and skipped instead of aborting planning")
	var compiled: Dictionary = SpawnGraphScript.compile(profile)
	var registry = StructureRegistryScript.empty_registry()
	registry.embedded_profiles.append({"id": template.structure_id, "path": path, "profile_id": "perfil_principal", "profile": profile, "compiled": compiled, "compile_errors": [], "template_hash": template.content_hash(), "embedded": true})
	var report = GenerationReportScript.new()
	var placer = StructurePlacerScript.new()
	var instances: Array = placer.plan_instances(world, tile, registry, 44017, report)
	_check(instances.size() == 1 and not report.candidate_counts.is_empty(), "planner honors maximum-per-biome")
	if not instances.is_empty():
		var instance: Dictionary = instances[0] as Dictionary; var origin: Vector3i = instance.get("origin", Vector3i.ZERO)
		world.clear_base_block(origin - Vector3i(0, 1, 0))
		placer.apply_instances(world, tile, registry, [instance], report)
		_check(not world.has_block(origin - Vector3i(0, 1, 0)), "foundation never writes below authored voxels")
		_check(origin.x >= 0 and origin.x + template.size.x <= 100 and origin.z >= 0 and origin.z + template.size.z <= 100, "AABB remains inside owning biome")

	var relaxed_profile: Dictionary = profile.duplicate(true)
	for raw_node in relaxed_profile.get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if str(node.get("type", "")) == "maximum_count": node["type"] = "exact_count"; node["params"] = {"value": 1}
	(relaxed_profile.get("nodes", []) as Array).append({"id": "altura_flexivel", "type": "height", "position": [450, 450], "params": {"min": 100, "max": 110}, "flexible": true, "relax_priority": 0, "relax_limit": 100.0})
	(relaxed_profile.get("connections", []) as Array).append({"from": "candidatos", "to": "altura_flexivel"}); (relaxed_profile.get("connections", []) as Array).append({"from": "altura_flexivel", "to": "chance"})
	var relaxed_compiled: Dictionary = SpawnGraphScript.compile(relaxed_profile)
	var relaxed_registry = StructureRegistryScript.empty_registry(); relaxed_registry.embedded_profiles.append({"id": template.structure_id, "path": path, "profile_id": "relaxado", "profile": relaxed_profile, "compiled": relaxed_compiled, "compile_errors": relaxed_compiled.get("errors", []), "template_hash": template.content_hash(), "embedded": true})
	var relaxed_report = GenerationReportScript.new(); var relaxed_instances: Array = StructurePlacerScript.new().plan_instances(world, tile, relaxed_registry, 44017, relaxed_report)
	_check(relaxed_instances.size() == 1 and relaxed_report.relaxations.size() == 1, "exact count relaxes only the configured flexible node")

	if failures == 0: print("Structure V2 regression checks passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("Structure V2 regression failed: %s" % message)

