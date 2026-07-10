## Explicit outcome for an authoritative block mutation.
class_name EditResult
extends RefCounted


var succeeded: bool = false
var reason: String = ""
var pos: Vector3i = Vector3i.ZERO
var block_id: String = ""
var removed_blocks: Array = []
var affected_sections: Array = []


static func accepted(p_pos: Vector3i, p_block_id: String) -> EditResult:
	var result: EditResult = EditResult.new()
	result.succeeded = true
	result.pos = p_pos
	result.block_id = p_block_id
	return result


static func rejected(p_reason: String, p_pos: Vector3i = Vector3i.ZERO, p_block_id: String = "") -> EditResult:
	var result: EditResult = EditResult.new()
	result.reason = p_reason
	result.pos = p_pos
	result.block_id = p_block_id
	return result
