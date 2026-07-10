## Stateless dependency rules shared by gameplay and authoring workspaces.
class_name VoxelDependencyResolver
extends RefCounted


static func collect_removal_positions(world, initial_pos: Vector3i, block_definitions: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if world == null or world.get_block_id(initial_pos) == "":
		return result
	result.append(initial_pos)
	var cursor: Vector3i = initial_pos + Vector3i.UP
	while world.get_block_id(cursor) != "":
		var block_id: String = world.get_block_id(cursor)
		if not is_plant(block_id, block_definitions):
			break
		result.append(cursor)
		cursor += Vector3i.UP
	return result


static func can_place(world, pos: Vector3i, block_id: String, block_definitions: Dictionary) -> bool:
	if not is_plant(block_id, block_definitions):
		return true
	return is_solid_support(world.get_block_id(pos + Vector3i.DOWN), block_definitions)


static func is_plant(block_id: String, block_definitions: Dictionary) -> bool:
	if block_id == "" or not block_definitions.has(block_id):
		return false
	return bool((block_definitions[block_id] as Dictionary).get("plant", false))


static func is_solid_support(block_id: String, block_definitions: Dictionary) -> bool:
	if block_id == "" or not block_definitions.has(block_id):
		return false
	var definition: Dictionary = block_definitions[block_id] as Dictionary
	return bool(definition.get("solid", true)) and not bool(definition.get("plant", false))
