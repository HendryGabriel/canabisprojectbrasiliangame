extends SceneTree

const BlockCatalogScript = preload("res://src/block_catalog.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")
const LightRegistryScript = preload("res://src/light_registry.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const GhostScript = preload("res://src/ghost.gd")
const RabbitScript = preload("res://src/rabbit.gd")
const ThumbstoneScript = preload("res://src/thumbstone.gd")
var failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(BlockCatalogScript.attack_damage("") == 1.0, "empty hand damage")
	_check(BlockCatalogScript.attack_damage("dirt") == 1.0, "block damage")
	_check(BlockCatalogScript.attack_damage("wooden_sword") == 5.0, "wood sword damage")
	_check(BlockCatalogScript.attack_damage("stone_sword") == 10.0, "stone sword damage")
	_check(BlockCatalogScript.attack_damage("iron_sword") == 15.0, "iron sword damage")
	_check(BlockCatalogScript.attack_damage("wooden_pickaxe") == 2.5, "wood tool damage")
	_check(BlockCatalogScript.attack_damage("stone_axe") == 5.0, "stone tool damage")
	_check(BlockCatalogScript.attack_damage("iron_shovel") == 7.5, "iron tool damage")
	_check(BlockCatalogScript.items().has("torch") and BlockCatalogScript.blocks().has("torch"), "torch catalog entries")

	var world = VoxelWorldScript.new(BlockCatalogScript.blocks())
	world.reset(7)
	world.set_tracking_changes(true)
	var torch_pos := Vector3i(10, 1, 10)
	_check(world.set_block(torch_pos, "torch"), "torch voxel placement")
	world.set_metadata(torch_pos, LightRegistryScript.METADATA_KEY, true)
	var lights = LightRegistryScript.new()
	root.add_child(lights)
	lights.configure(world)
	_check(lights.is_spawn_blocked(Vector3(10, 1, 10)), "torch suppresses nearby spawn")
	_check(not lights.is_spawn_blocked(Vector3(30, 1, 30)), "torch does not suppress distant spawn")

	var template = StructureTemplateScript.new()
	template.structure_id = "haunted_test"
	template.size = Vector3i(2, 2, 2)
	template.markers = [{"type": "entity_spawn", "entity_id": "ghost", "pos": [1, 1, 1]}]
	_check(template.validate().is_empty(), "valid ghost spawn marker")
	template.markers[0].erase("entity_id")
	_check(not template.validate().is_empty(), "spawn marker requires entity id")

	var ghost = GhostScript.new()
	ghost.configure(root, "ghost", 20.0)
	root.add_child(ghost)
	ghost.set_physics_process(false)
	ghost.take_damage(5.0)
	_check(ghost.health == 15.0 and ghost.is_in_group("creature") and ghost.get_node_or_null("VisualRoot") != null, "ghost health and replaceable visual root")
	var rabbit = RabbitScript.new()
	rabbit.configure(root, "rabbit", 5.0)
	root.add_child(rabbit)
	rabbit.set_physics_process(false)
	_check(rabbit.health == 5.0 and rabbit.is_in_group("creature"), "rabbit prototype")
	var stone = ThumbstoneScript.new()
	stone.configure(root, "test", [{"item": "coal", "count": 4}], Vector3.ZERO)
	root.add_child(stone)
	_check(stone.is_in_group("thumbstone") and stone.to_data().get("contents", []).size() == 1, "thumbstone keeps contents")
	if failed:
		quit(1)
		return
	print("Combat, creatures, light, and spawn regression checks passed.")
	quit(0)

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Regression failed: %s" % label)
