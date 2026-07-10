## Immutable result of the authoritative voxel-DDA interaction ray.
class_name VoxelHit
extends RefCounted


var pos: Vector3i
var normal: Vector3i
var block_id: String
var distance: float


func _init(
	p_pos: Vector3i = Vector3i.ZERO,
	p_normal: Vector3i = Vector3i.ZERO,
	p_block_id: String = "",
	p_distance: float = 0.0,
) -> void:
	pos = p_pos
	normal = p_normal
	block_id = p_block_id
	distance = p_distance


func is_valid() -> bool:
	return block_id != ""


func to_dictionary() -> Dictionary:
	return {
		"pos": pos,
		"normal": normal,
		"block_id": block_id,
		"distance": distance,
	}
