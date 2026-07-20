class_name GenerationReport
extends RefCounted


var errors: Array[String] = []
var warnings: Array[String] = []
var instances: Array = []
var entity_spawns: Array = []
var placed_assets: Array = []
var generated_columns: int = 0
var generated_blocks: int = 0
var carved_voxels: int = 0
var seed: int = 0
var tile_coord: Vector2i = Vector2i.ZERO
var candidate_counts: Dictionary = {} # profile key -> evaluated count
var rejection_counts: Dictionary = {} # profile key -> node id -> reason -> count
var relaxations: Array = []


func add_error(message: String) -> void:
	errors.append(message)


func add_warning(message: String) -> void:
	warnings.append(message)


func add_candidate(profile_key: String) -> void:
	candidate_counts[profile_key] = int(candidate_counts.get(profile_key, 0)) + 1


func add_rejection(profile_key: String, reason: Dictionary) -> void:
	var by_node: Dictionary = rejection_counts.get(profile_key, {}) as Dictionary
	var node_id: String = str(reason.get("node_id", "unknown"))
	var messages: Dictionary = by_node.get(node_id, {}) as Dictionary
	var message: String = str(reason.get("message", "Candidato rejeitado."))
	messages[message] = int(messages.get(message, 0)) + 1
	by_node[node_id] = messages
	rejection_counts[profile_key] = by_node


func add_relaxation(profile_key: String, node_id: String, original: float, effective: float) -> void:
	relaxations.append({"profile": profile_key, "node_id": node_id, "original": original, "effective": effective})


func rejection_summary(profile_key: String, limit: int = 3) -> String:
	var totals: Dictionary = {}
	for raw_messages in (rejection_counts.get(profile_key, {}) as Dictionary).values():
		for message in (raw_messages as Dictionary).keys():
			totals[message] = int(totals.get(message, 0)) + int((raw_messages as Dictionary)[message])
	var ranked: Array = totals.keys()
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool:
		var count_a: int = int(totals[a]); var count_b: int = int(totals[b])
		return count_a > count_b if count_a != count_b else str(a) < str(b)
	)
	var parts: Array[String] = []
	for index in range(mini(limit, ranked.size())):
		var message: String = str(ranked[index])
		parts.append("%s (%dx)" % [message, int(totals[ranked[index]])])
	return "; ".join(parts)


func is_ok() -> bool:
	return errors.is_empty()


func summary() -> String:
	if not errors.is_empty():
		return "Erros: %s" % "; ".join(errors)
	if not warnings.is_empty():
		return "Concluido com avisos [seed=%d, bioma=(%d,%d)]: %s" % [seed, tile_coord.x, tile_coord.y, "; ".join(warnings)]
	return "Geracao concluida: %d colunas, %d blocos, %d voxels escavados, %d estruturas." % [generated_columns, generated_blocks, carved_voxels, instances.size()]


func to_dictionary() -> Dictionary:
	return {
		"seed": seed, "tile_coord": [tile_coord.x, tile_coord.y],
		"errors": errors, "warnings": warnings, "instances": instances, "placed_assets": placed_assets,
		"candidate_counts": candidate_counts, "rejection_counts": rejection_counts,
		"relaxations": relaxations,
	}

