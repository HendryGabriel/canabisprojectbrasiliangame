extends SceneTree


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")
const GenerationReportScript = preload("res://src/generation_report.gd")
const PlacedAssetSystemScript = preload("res://src/placed_asset_system.gd")
const StructurePlacerScript = preload("res://src/structure_placer.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions: Dictionary = BlockCatalogScript.blocks()
	var registry = StructureRegistryScript.empty_registry()
	var custom = StructureTemplateScript.new()
	custom.structure_id = "custom_test"; custom.display_name = "Custom Test"; custom.asset_kind = "custom_block"; custom.size = Vector3i.ONE
	var cell = MicroCellScript.new(); cell.fill_region(Vector3i.ZERO, 4, "stone"); custom.micro_cells[Vector3i.ZERO] = cell
	_check(custom.validate(definitions).is_empty(), "custom block accepts exactly one authored microcell")
	var restored = StructureTemplateScript.from_dictionary(custom.to_dictionary())
	_check(restored != null and restored.asset_kind == "custom_block" and int(restored.to_dictionary().get("version", 0)) == 4, "V4 custom block round-trips")
	var legacy_v3: Dictionary = custom.to_dictionary()
	legacy_v3["version"] = 3
	for field in ["asset_kind", "placement_mode", "utility_id", "anchor", "components", "requirements"]: legacy_v3.erase(field)
	var migrated = StructureTemplateScript.from_dictionary(legacy_v3)
	_check(migrated != null and migrated.asset_kind == "structure" and int(migrated.to_dictionary().get("version", 0)) == 4, "legacy V3 templates load as ordinary structures and serialize as V4")

	var atomic = StructureTemplateScript.new()
	atomic.structure_id = "atomic_test"; atomic.display_name = "Atomic Test"; atomic.asset_kind = "multiblock"; atomic.utility_id = "test_utility"; atomic.size = Vector3i(1, 2, 1); atomic.pivot = Vector3i.ZERO
	atomic.blocks[Vector3i.ZERO] = "cobblestone"; atomic.blocks[Vector3i.UP] = "wood"
	var assembled = StructureTemplateScript.new()
	assembled.structure_id = "assembled_test"; assembled.display_name = "Assembled Test"; assembled.asset_kind = "multiblock"; assembled.placement_mode = "assembled"; assembled.utility_id = "test_utility"; assembled.size = Vector3i(1, 2, 1); assembled.anchor = Vector3i.ZERO
	assembled.blocks[Vector3i.ZERO] = "cobblestone"; assembled.blocks[Vector3i.UP] = "wood"
	assembled.requirements = [
		{"pos": [0, 0, 0], "item_id": "cobblestone", "block_id": "cobblestone"},
		{"pos": [0, 1, 0], "item_id": "wood", "block_id": "wood"},
	]
	var component_assembly = StructureTemplateScript.new()
	component_assembly.structure_id = "component_assembly"; component_assembly.display_name = "Component Assembly"; component_assembly.asset_kind = "multiblock"; component_assembly.placement_mode = "assembled"; component_assembly.utility_id = "test_utility"; component_assembly.size = Vector3i(1, 2, 1); component_assembly.anchor = Vector3i.ZERO
	component_assembly.blocks[Vector3i.ZERO] = "cobblestone"; component_assembly.components = [{"asset_id": "custom_test", "pos": [0, 1, 0], "rotation": 1}]
	component_assembly.requirements = [
		{"pos": [0, 0, 0], "item_id": "cobblestone", "block_id": "cobblestone"},
		{"pos": [0, 1, 0], "item_id": "custom_test", "asset_id": "custom_test", "rotation": 1},
	]
	registry.assets = {custom.structure_id: custom, atomic.structure_id: atomic, assembled.structure_id: assembled, component_assembly.structure_id: component_assembly}

	var world = VoxelWorldScript.new(definitions); world.reset(123); world.set_tracking_changes(true)
	var system = PlacedAssetSystemScript.new(); system.configure(world, registry)
	_check(system.item_definitions().has("custom_test") and system.item_definitions().has("atomic_test") and not system.item_definitions().has("assembled_test"), "registry exposes custom and atomic items while assembly uses its anchor item")
	var placed: Dictionary = system.place_atomic("atomic_test", Vector3i(10, 5, 10), 1)
	_check(bool(placed.get("ok", false)) and world.get_block_id(Vector3i(10, 5, 10)) == "cobblestone" and world.get_block_id(Vector3i(10, 6, 10)) == "wood", "atomic multiblock writes its complete volume")
	var removed: Dictionary = system.remove_owned_at(Vector3i(10, 6, 10))
	_check(bool(removed.get("ok", false)) and str(removed.get("asset_id", "")) == "atomic_test" and not world.has_block(Vector3i(10, 5, 10)), "breaking any atomic part removes the complete instance")

	var anchor: Vector3i = Vector3i(20, 5, 20)
	world.set_block(anchor, "cobblestone")
	var begun: Dictionary = system.begin_assembly("assembled_test", anchor, 0)
	_check(bool(begun.get("ok", false)) and system.missing_requirements_at(anchor).size() == 1, "anchor starts an incomplete spatial recipe")
	world.set_block(anchor + Vector3i.UP, "wood"); system.notify_world_changed(anchor + Vector3i.UP)
	_check(bool(system.get_instance_at(anchor).get("active", false)), "last correct piece activates the assembly")
	world.remove_block(anchor + Vector3i.UP); system.notify_world_changed(anchor + Vector3i.UP)
	_check(not bool(system.get_instance_at(anchor).get("active", true)) and system.missing_requirements_at(anchor).size() == 1, "breaking one piece deactivates without removing the anchor")
	var component_anchor: Vector3i = Vector3i(24, 5, 24)
	world.set_block(component_anchor, "cobblestone")
	_check(bool(system.begin_assembly("component_assembly", component_anchor, 0).get("ok", false)), "assembled multiblock reserves a component recipe")
	_check(not bool(system.can_place(custom, component_anchor + Vector3i.UP, 0).get("ok", false)), "assembly ghost rejects the correct component in the wrong rotation")
	var component_result: Dictionary = system.place_atomic("custom_test", component_anchor + Vector3i.UP, 1)
	system.notify_world_changed(component_anchor + Vector3i.UP)
	_check(bool(component_result.get("ok", false)) and bool(system.get_instance_at(component_anchor).get("active", false)), "the exact custom asset can occupy its reserved assembly ghost")
	var saved: Array = system.build_save_data()
	var loaded = PlacedAssetSystemScript.new(); loaded.configure(world, registry)
	_check(loaded.load_save_data(saved) and loaded.get_instance_at(anchor).get("asset_id", "") == "assembled_test", "placed asset instances round-trip through save data")

	var parent = StructureTemplateScript.new(); parent.structure_id = "parent_structure"; parent.size = Vector3i.ONE
	parent.components = [{"asset_id": "custom_test", "pos": [0, 0, 0], "rotation": 0}]
	registry.assets[parent.structure_id] = parent
	var generation_world = VoxelWorldScript.new(definitions); generation_world.reset(123)
	var tile = TerrainTileScript.create_draft(123, Vector2i.ZERO)
	var report = GenerationReportScript.new(); var placer = StructurePlacerScript.new(); var origin: Vector3i = Vector3i(30, 5, 30)
	placer.apply_instances(generation_world, tile, registry, [{"template": parent, "origin": origin, "rotation": 0}], report)
	_check(generation_world.has_micro_cell(origin) and report.placed_assets.size() == 1 and str((report.placed_assets[0] as Dictionary).get("asset_id", "")) == "custom_test", "generated structures instantiate referenced custom assets without losing identity")

	if failures == 0: print("Placed asset regression checks passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("Placed asset regression failed: %s" % message)

