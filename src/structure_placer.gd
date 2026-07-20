## Deterministic planning and application of directed/procedural structures.
class_name StructurePlacer
extends RefCounted


const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const SpawnGraphScript = preload("res://src/structure_spawn_graph.gd")


var _template_cache: Dictionary = {}


func plan_instances(world, tile, registry, seed: int, report) -> Array:
	var planned: Array = []
	for raw_anchor in tile.anchors:
		if typeof(raw_anchor) != TYPE_DICTIONARY:
			continue
		var anchor: Dictionary = raw_anchor as Dictionary
		var template_id: String = str(anchor.get("template_id", ""))
		var rule: Dictionary = registry.get_rule(template_id)
		if rule.is_empty():
			report.add_error("Ancora referencia template ausente: %s" % template_id)
			continue
		var template = _load_template(rule)
		if template == null:
			report.add_error("Falha ao carregar estrutura %s." % template_id)
			continue
		var instance: Dictionary = _plan_at(world, tile, template, rule, anchor, seed)
		if instance.has("error"):
			report.add_error("Ancora %s invalida: %s" % [template_id, instance["error"]])
		elif _overlaps_any(instance, planned):
			report.add_error("Ancora %s sobrepoe outra estrutura." % template_id)
		else:
			planned.append(instance)

	var embedded_rules: Array = []
	var legacy_rules: Array = []
	for raw_rule in registry.get_rules():
		var rule: Dictionary = raw_rule as Dictionary
		if bool(rule.get("embedded", false)):
			embedded_rules.append(rule)
		else:
			legacy_rules.append(rule)
	planned.append_array(_plan_embedded_profiles(world, tile, embedded_rules, seed, report, planned))
	for raw_rule in legacy_rules:
		var rule: Dictionary = raw_rule as Dictionary
		if float(rule.get("weight", 0.0)) <= 0.0:
			continue
		var template = _load_template(rule)
		if template == null:
			report.add_warning("Template procedural ausente: %s" % rule.get("id", ""))
			continue
		var spacing: int = int(rule.get("spacing", 24))
		for z in range(spacing / 2, TerrainTileScript.TILE_SIZE, spacing):
			for x in range(spacing / 2, TerrainTileScript.TILE_SIZE, spacing):
				if (tile.get_zone_flags(x, z) & int(rule.get("zone_mask", TerrainTileScript.ZONE_STRUCTURES))) == 0 or tile.has_zone_flag(x, z, TerrainTileScript.ZONE_PROTECTED):
					continue
				var roll: float = _hash01(x + tile.tile_coord.x * 100, seed, z + tile.tile_coord.y * 100, str(rule.get("id", "")).hash())
				if roll > float(rule.get("weight", 0.0)):
					continue
				var rotations: Array = rule.get("rotations", [0]) as Array
				var rotation: int = int(rotations[int(floor(_hash01(x, seed, z, 81) * rotations.size())) % rotations.size()]) if not rotations.is_empty() else 0
				var anchor: Dictionary = {
					"template_id": str(rule.get("id", "")), "x": x, "z": z,
					"rotation": rotation,
					"mirror_x": bool(rule.get("allow_mirror_x", false)) and _hash01(x, seed, z, 82) > 0.5,
					"mirror_z": bool(rule.get("allow_mirror_z", false)) and _hash01(x, seed, z, 83) > 0.5,
				}
				var instance: Dictionary = _plan_at(world, tile, template, rule, anchor, seed)
				if not instance.has("error") and not _overlaps_any(instance, planned):
					planned.append(instance)
	return planned


func _plan_embedded_profiles(world, tile, rules: Array, seed: int, report, existing: Array) -> Array:
	var jobs: Array = []
	for raw_rule in rules:
		var rule: Dictionary = raw_rule as Dictionary
		var compiled: Dictionary = rule.get("compiled", {}) as Dictionary
		var profile_errors: Array = rule.get("compile_errors", compiled.get("errors", [])) as Array
		if not profile_errors.is_empty():
			report.add_warning("Perfil %s::%s ignorado: %s" % [rule.get("id", ""), rule.get("profile_id", ""), "; ".join(profile_errors)])
			continue
		var template = _load_template(rule)
		if template == null:
			report.add_warning("Template V2 ausente: %s." % rule.get("id", ""))
			continue
		jobs.append({"rule": rule, "template": template, "compiled": compiled})
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Dictionary = (a.get("compiled", {}) as Dictionary).get("settings", {}) as Dictionary
		var sb: Dictionary = (b.get("compiled", {}) as Dictionary).get("settings", {}) as Dictionary
		var exact_a: bool = int(sa.get("exact_count", -1)) >= 0; var exact_b: bool = int(sb.get("exact_count", -1)) >= 0
		if exact_a != exact_b: return exact_a
		var template_a = a.get("template"); var template_b = b.get("template")
		var volume_a: int = int(template_a.size.x * template_a.size.y * template_a.size.z)
		var volume_b: int = int(template_b.size.x * template_b.size.y * template_b.size.z)
		if volume_a != volume_b: return volume_a > volume_b
		var priority_a: int = int(sa.get("priority", 0)); var priority_b: int = int(sb.get("priority", 0))
		if priority_a != priority_b: return priority_a > priority_b
		return str((a.get("rule", {}) as Dictionary).get("profile_id", "")) < str((b.get("rule", {}) as Dictionary).get("profile_id", ""))
	)
	var additions: Array = []
	var reserved: Array = existing.duplicate()
	for raw_job in jobs:
		var placed: Array = _plan_embedded_profile(world, tile, raw_job as Dictionary, seed, report, reserved)
		additions.append_array(placed)
		reserved.append_array(placed)
	return additions


func _plan_embedded_profile(world, tile, job: Dictionary, seed: int, report, reserved: Array) -> Array:
	var source_rule: Dictionary = job.get("rule", {}) as Dictionary
	var template = job.get("template")
	var compiled: Dictionary = job.get("compiled", {}) as Dictionary
	var settings: Dictionary = compiled.get("settings", {}) as Dictionary
	var profile_key: String = "%s::%s" % [source_rule.get("id", ""), source_rule.get("profile_id", "")]
	var rotations: Array = settings.get("rotations", [0]) as Array
	var placement_rule: Dictionary = {
		"id": str(source_rule.get("id", "")), "path": str(source_rule.get("path", "")),
		"mode": str(settings.get("mode", "surface_adaptive")), "zone_mask": 0,
		"rotations": rotations, "allow_mirror_x": float(settings.get("mirror_x_chance", 0.0)) > 0.0,
		"allow_mirror_z": float(settings.get("mirror_z_chance", 0.0)) > 0.0,
		"max_slope": 126, "min_depth": int(settings.get("min_depth", 12)),
		"max_depth": int(settings.get("max_depth", 42)), "minimum_cover": int(settings.get("minimum_cover", 4)),
	}
	var spacing: int = int(settings.get("spacing", 24))
	var records: Array = []
	var passing: Array = []
	for z in range(spacing / 2, TerrainTileScript.TILE_SIZE, spacing):
		for x in range(spacing / 2, TerrainTileScript.TILE_SIZE, spacing):
			report.add_candidate(profile_key)
			var rotation: int = int(rotations[int(floor(_hash01(x, seed, z, profile_key.hash()) * rotations.size())) % rotations.size()]) if not rotations.is_empty() else 0
			var anchor: Dictionary = {
				"template_id": str(source_rule.get("id", "")), "x": x, "z": z, "rotation": rotation,
				"mode": str(settings.get("mode", "surface_adaptive")),
				"mirror_x": _hash01(x, seed, z, profile_key.hash() + 31) < float(settings.get("mirror_x_chance", 0.0)),
				"mirror_z": _hash01(x, seed, z, profile_key.hash() + 47) < float(settings.get("mirror_z_chance", 0.0)),
			}
			var instance: Dictionary = _plan_at(world, tile, template, placement_rule, anchor, seed)
			if instance.has("error"):
				var placement_reason: Dictionary = {"node_id": "placement", "message": str(instance.get("error", "candidato invalido"))}
				report.add_rejection(profile_key, placement_reason)
				continue
			instance["profile_id"] = str(source_rule.get("profile_id", ""))
			instance["score"] = _hash01(x, seed, z, profile_key.hash() + 101)
			var context: Dictionary = _candidate_context(world, tile, template, instance, compiled)
			var evaluation: Dictionary = SpawnGraphScript.evaluate(compiled, context)
			var record: Dictionary = {"instance": instance, "context": context, "evaluation": evaluation}
			records.append(record)
			if bool(evaluation.get("ok", false)):
				passing.append(instance)
			else:
				for raw_reason in evaluation.get("reasons", []) as Array: report.add_rejection(profile_key, raw_reason as Dictionary)
	var required: int = int(settings.get("exact_count", -1))
	if required < 0: required = int(settings.get("min_count", 0))
	var relaxations: Dictionary = {}
	var placed: Array = _reserve_profile_candidates(passing, settings, reserved, profile_key, report)
	if placed.size() < required:
		for raw_node in SpawnGraphScript.flexible_nodes(compiled):
			var node: Dictionary = raw_node as Dictionary
			var node_id: String = str(node.get("id", "")); var limit: float = float(node.get("relax_limit", 0.0))
			relaxations[node_id] = limit
			report.add_relaxation(profile_key, node_id, 0.0, limit)
			passing.clear()
			for raw_record in records:
				var record: Dictionary = raw_record as Dictionary
				var evaluation: Dictionary = SpawnGraphScript.evaluate(compiled, record.get("context", {}) as Dictionary, relaxations)
				if bool(evaluation.get("ok", false)): passing.append(record.get("instance", {}) as Dictionary)
			placed = _reserve_profile_candidates(passing, settings, reserved, profile_key, report)
			if placed.size() >= required: break
	if placed.size() < required:
		var reasons: String = report.rejection_summary(profile_key)
		var detail: String = " Motivos principais: %s" % reasons if reasons != "" else ""
		report.add_warning("Perfil %s solicitou %d estrutura(s), mas apenas %d puderam ser reservadas.%s" % [profile_key, required, placed.size(), detail])
	return placed


func _reserve_profile_candidates(passing: Array, settings: Dictionary, reserved: Array, profile_key: String, report) -> Array:
	passing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("score", 0.0)) < float(b.get("score", 0.0)))
	var exact_count: int = int(settings.get("exact_count", -1))
	var required: int = exact_count if exact_count >= 0 else int(settings.get("min_count", 0))
	var maximum: int = exact_count if exact_count >= 0 else int(settings.get("max_count", -1))
	var chance: float = float(settings.get("chance", 1.0))
	var candidate_pool: Array = []
	for raw_instance in passing:
		var instance: Dictionary = raw_instance as Dictionary
		if exact_count >= 0 or float(instance.get("score", 0.0)) <= chance:
			candidate_pool.append(instance)
	if candidate_pool.size() < required:
		for raw_instance in passing:
			if not candidate_pool.has(raw_instance): candidate_pool.append(raw_instance)
	var placed: Array = []
	for raw_instance in candidate_pool:
		if maximum >= 0 and placed.size() >= maximum: break
		var instance: Dictionary = raw_instance as Dictionary
		if _overlaps_any(instance, reserved) or _overlaps_any(instance, placed):
			report.add_rejection(profile_key, {"node_id": "reservation", "message": "AABB sobrepoe outra estrutura reservada."})
			continue
		if not _respects_profile_distance(instance, placed, float(settings.get("min_distance", 0.0))):
			report.add_rejection(profile_key, {"node_id": "minimum_distance", "message": "Distancia minima entre estruturas nao atendida."})
			continue
		placed.append(instance)
	return placed


func _candidate_context(world, tile, template, instance: Dictionary, compiled: Dictionary) -> Dictionary:
	var origin: Vector3i = instance.get("origin", Vector3i.ZERO)
	var maximum: Vector3i = instance.get("max", Vector3i.ZERO)
	var anchor: Vector3i = instance.get("anchor", origin)
	var local_x: int = anchor.x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE
	var local_z: int = anchor.z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
	var surface_y: int = tile.get_height(local_x, local_z)
	var context: Dictionary = {
		"tile_coord": tile.tile_coord, "zone_flags": tile.get_zone_flags(local_x, local_z),
		"mode": instance.get("mode", "surface_adaptive"), "anchor_y": anchor.y,
		"depth": surface_y - anchor.y,
		"distance_edge": mini(local_x, mini(local_z, mini(TerrainTileScript.TILE_SIZE - 1 - local_x, TerrainTileScript.TILE_SIZE - 1 - local_z))),
		"distance_spawn": Vector2(float(local_x - 50), float(local_z - 50)).length(),
		"sky_visible": anchor.y >= surface_y,
		"slope": 0, "volume_air_ratio": 0.0, "support_blocks_ok": true,
	}
	if _graph_has_type(compiled, "slope"):
		context["slope"] = _surface_slope(tile, origin, maximum)
	if _graph_has_type(compiled, "volume_air"):
		context["volume_air_ratio"] = _volume_air_ratio(world, origin, maximum)
	if _graph_has_type(compiled, "support_block"):
		context["support_blocks_ok"] = _foundation_blocks_allowed(world, template, instance, compiled)
	return context


func _surface_slope(tile, origin: Vector3i, maximum: Vector3i) -> int:
	var minimum_height: int = 9999; var maximum_height: int = -9999
	for world_z in range(origin.z, maximum.z + 1):
		for world_x in range(origin.x, maximum.x + 1):
			var x: int = world_x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE; var z: int = world_z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
			var height: int = tile.get_height(x, z)
			minimum_height = mini(minimum_height, height); maximum_height = maxi(maximum_height, height)
	return maximum_height - minimum_height


func _volume_air_ratio(world, origin: Vector3i, maximum: Vector3i) -> float:
	var air: int = 0; var total: int = 0
	for y in range(origin.y, maximum.y + 1):
		for z in range(origin.z, maximum.z + 1):
			for x in range(origin.x, maximum.x + 1):
				total += 1
				if not world.has_block(Vector3i(x, y, z)): air += 1
	return float(air) / float(total) if total > 0 else 0.0


func _foundation_blocks_allowed(world, template, instance: Dictionary, compiled: Dictionary) -> bool:
	var allowed: Array = []
	for raw_node in (compiled.get("nodes", {}) as Dictionary).values():
		var node: Dictionary = raw_node as Dictionary
		if str(node.get("type", "")) == "support_block": allowed.append_array((node.get("params", {}) as Dictionary).get("blocks", []) as Array)
	var origin: Vector3i = instance.get("origin", Vector3i.ZERO); var rotation: int = int(instance.get("rotation", 0)); var mirror_x: bool = bool(instance.get("mirror_x", false)); var mirror_z: bool = bool(instance.get("mirror_z", false))
	for raw_marker in template.markers:
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("type", "")) != "foundation": continue
		var local_pos: Vector3i = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
		var block_id: String = world.get_block_id(origin + template.transform_position(local_pos, rotation, mirror_x, mirror_z) - Vector3i(0, 1, 0))
		if not allowed.has(block_id): return false
	return true


static func _graph_has_type(compiled: Dictionary, type: String) -> bool:
	for node_id in (compiled.get("reachable", {}) as Dictionary).keys():
		if str(((compiled.get("nodes", {}) as Dictionary).get(node_id, {}) as Dictionary).get("type", "")) == type: return true
	return false


static func _respects_profile_distance(instance: Dictionary, others: Array, minimum_distance: float) -> bool:
	if minimum_distance <= 0.0: return true
	var anchor: Vector3i = instance.get("anchor", instance.get("origin", Vector3i.ZERO))
	for raw_other in others:
		var other: Dictionary = raw_other as Dictionary
		var other_anchor: Vector3i = other.get("anchor", other.get("origin", Vector3i.ZERO))
		if Vector2(float(anchor.x - other_anchor.x), float(anchor.z - other_anchor.z)).length() < minimum_distance: return false
	return true


func apply_instances(world, tile, registry, instances: Array, report) -> void:
	for raw_instance in instances:
		var instance: Dictionary = raw_instance as Dictionary
		var template = instance["template"]
		var origin: Vector3i = instance["origin"]
		var rotation: int = int(instance.get("rotation", 0))
		var mirror_x: bool = bool(instance.get("mirror_x", false))
		var mirror_z: bool = bool(instance.get("mirror_z", false))
		for raw_local in template.explicit_air.keys():
			var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
			if _can_write(world, tile, target):
				world.clear_base_block(target)
		for raw_local in template.blocks.keys():
			var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
			if _can_write(world, tile, target):
				world.set_base_block(target, str(template.blocks[raw_local]))
		for raw_local in template.micro_cells.keys():
			var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
			if _can_write(world, tile, target):
				world.set_base_micro_cell(target, template.micro_cells[raw_local].transformed(rotation, mirror_x, mirror_z))
		for raw_local in template.metadata.keys():
			var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
			if _can_write(world, tile, target):
				var entry: Dictionary = template.metadata[raw_local] as Dictionary
				for key in entry.keys():
					world.set_metadata(target, str(key), entry[key])
		for raw_marker in template.markers:
			var marker: Dictionary = raw_marker as Dictionary
			if str(marker.get("type", "")) != "entity_spawn":
				continue
			var local_pos: Vector3i = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
			var target: Vector3i = origin + template.transform_position(local_pos, rotation, mirror_x, mirror_z)
			report.entity_spawns.append({
				"entity_id": str(marker.get("entity_id", "")),
				"position": Vector3(target),
			})
		for raw_component in template.components:
			var component: Dictionary = raw_component as Dictionary
			var child = registry.get_asset(str(component.get("asset_id", ""))) if registry != null else null
			if child == null: continue
			var component_local: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
			var component_pivot: Vector3i = origin + template.transform_position(component_local, rotation, mirror_x, mirror_z)
			_apply_component(world, tile, registry, child, component_pivot, rotation + int(component.get("rotation", 0)), mirror_x, mirror_z, report, {})
		report.instances.append({"id": template.structure_id, "profile_id": instance.get("profile_id", ""), "origin": origin, "max": instance.get("max", origin), "mode": instance.get("mode", "surface_adaptive"), "rotation": rotation, "mirror_x": mirror_x, "mirror_z": mirror_z})


func _apply_component(world, tile, registry, template, pivot_world: Vector3i, rotation: int, mirror_x: bool, mirror_z: bool, report, visiting: Dictionary) -> void:
	if visiting.has(template.structure_id): return
	visiting[template.structure_id] = true
	var transformed_pivot: Vector3i = template.transform_position(template.pivot, rotation, mirror_x, mirror_z)
	var origin: Vector3i = pivot_world - transformed_pivot
	for raw_local in template.explicit_air.keys():
		var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
		if _can_write(world, tile, target): world.clear_base_block(target)
	for raw_local in template.blocks.keys():
		var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
		if _can_write(world, tile, target): world.set_base_block(target, str(template.blocks[raw_local]))
	for raw_local in template.micro_cells.keys():
		var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
		if _can_write(world, tile, target): world.set_base_micro_cell(target, template.micro_cells[raw_local].transformed(rotation, mirror_x, mirror_z))
	for raw_component in template.components:
		var component: Dictionary = raw_component as Dictionary
		var child = registry.get_asset(str(component.get("asset_id", ""))) if registry != null else null
		if child == null: continue
		var local: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
		var child_pivot: Vector3i = origin + template.transform_position(local, rotation, mirror_x, mirror_z)
		_apply_component(world, tile, registry, child, child_pivot, rotation + int(component.get("rotation", 0)), mirror_x, mirror_z, report, visiting.duplicate())
	report.placed_assets.append({"asset_id": template.structure_id, "origin": [pivot_world.x, pivot_world.y, pivot_world.z], "rotation": posmod(rotation, 4), "state": {}, "assembled": template.asset_kind == "multiblock" and template.placement_mode == "assembled", "active": true})


func _plan_at(world, tile, template, rule: Dictionary, anchor: Dictionary, seed: int) -> Dictionary:
	var local_x: int = int(anchor.get("x", -1))
	var local_z: int = int(anchor.get("z", -1))
	if tile.index_of(local_x, local_z) < 0:
		return {"error": "coordenada fora do tile"}
	var rotation: int = posmod(int(anchor.get("rotation", 0)), 4)
	var mirror_x: bool = bool(anchor.get("mirror_x", false))
	var mirror_z: bool = bool(anchor.get("mirror_z", false))
	var allowed_rotations: Array = rule.get("rotations", [0, 1, 2, 3]) as Array
	if not allowed_rotations.has(rotation):
		return {"error": "rotacao nao permitida pela regra"}
	if mirror_x and not bool(rule.get("allow_mirror_x", false)):
		return {"error": "espelhamento X nao permitido pela regra"}
	if mirror_z and not bool(rule.get("allow_mirror_z", false)):
		return {"error": "espelhamento Z nao permitido pela regra"}
	var zone_mask: int = int(rule.get("zone_mask", TerrainTileScript.ZONE_STRUCTURES))
	if zone_mask != 0 and (tile.get_zone_flags(local_x, local_z) & zone_mask) == 0:
		return {"error": "zona da ancora nao permite esta estrutura"}
	var pivot: Vector3i = template.transform_position(template.pivot, rotation, mirror_x, mirror_z)
	var world_x: int = tile.tile_coord.x * TerrainTileScript.TILE_SIZE + local_x
	var world_z: int = tile.tile_coord.y * TerrainTileScript.TILE_SIZE + local_z
	var mode: String = str(anchor.get("mode", rule.get("mode", "surface_adaptive")))
	var anchor_y: int = int(anchor.get("y", 9999))
	if anchor_y == 9999:
		match mode:
			"surface_adaptive":
				anchor_y = _surface_anchor_height(tile, template, local_x, local_z, rotation, mirror_x, mirror_z, int(rule.get("max_slope", 8)))
				if anchor_y < -1000:
					return {"error": "fundacao excede inclinacao/limites"}
			"cave_floor":
				anchor_y = _find_cave_floor(world, world_x, world_z, tile.get_height(local_x, local_z), template.transformed_size(rotation).y)
				if anchor_y < -1000:
					return {"error": "nenhum piso de caverna compativel"}
			"underground", "buried":
				var min_depth: int = int(rule.get("min_depth", 12))
				var max_depth: int = maxi(min_depth, int(rule.get("max_depth", 42)))
				var depth: int = min_depth + int(floor(_hash01(world_x, seed, world_z, template.structure_id.hash()) * float(max_depth - min_depth + 1)))
				anchor_y = tile.get_height(local_x, local_z) - depth
			_:
				return {"error": "modo de colocacao desconhecido"}
	var origin: Vector3i = Vector3i(world_x, anchor_y, world_z) - pivot
	var transformed_size: Vector3i = template.transformed_size(rotation)
	var maximum: Vector3i = origin + transformed_size - Vector3i.ONE
	if not world.is_inside_world(origin) or not world.is_inside_world(maximum):
		return {"error": "bounds fora do mundo"}
	if origin.y <= -65:
		return {"error": "bounds intersectam bedrock"}
	for z in range(origin.z, maximum.z + 1):
		for x in range(origin.x, maximum.x + 1):
			var tx: int = x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE
			var tz: int = z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
			if tile.index_of(tx, tz) < 0 or tile.has_zone_flag(tx, tz, TerrainTileScript.ZONE_PROTECTED):
				return {"error": "intersecta limite ou area protegida"}
			if mode == "buried" and maximum.y > tile.get_height(tx, tz) - int(rule.get("minimum_cover", 4)):
				return {"error": "cobertura subterranea insuficiente"}
	if mode == "cave_floor":
		if not _volume_is_clear(world, origin, maximum):
			return {"error": "volume da caverna esta obstruido"}
		if not _foundations_touch_floor(world, template, origin, rotation, mirror_x, mirror_z):
			return {"error": "fundacao nao encontra piso de caverna"}
	elif not _foundations_touch_floor(world, template, origin, rotation, mirror_x, mirror_z):
		return {"error": "ponto de fundacao nao toca apoio solido"}
	return {
		"template": template, "rule": rule, "origin": origin, "max": maximum,
		"anchor": Vector3i(world_x, anchor_y, world_z),
		"rotation": rotation, "mirror_x": mirror_x, "mirror_z": mirror_z, "mode": mode,
	}


func _surface_anchor_height(tile, template, local_x: int, local_z: int, rotation: int, mirror_x: bool, mirror_z: bool, max_slope: int) -> int:
	var samples: Array[int] = []
	for raw_marker in template.markers:
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("type", "")) != "foundation":
			continue
		var marker_pos: Vector3i = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
		var transformed: Vector3i = template.transform_position(marker_pos, rotation, mirror_x, mirror_z)
		var x: int = local_x + transformed.x - template.transform_position(template.pivot, rotation, mirror_x, mirror_z).x
		var z: int = local_z + transformed.z - template.transform_position(template.pivot, rotation, mirror_x, mirror_z).z
		if tile.index_of(x, z) < 0:
			return -9999
		samples.append(tile.get_height(x, z))
	if samples.is_empty():
		samples.append(tile.get_height(local_x, local_z))
	samples.sort()
	if samples.back() - samples.front() > max_slope:
		return -9999
	return samples[samples.size() / 2]


func _find_cave_floor(world, x: int, z: int, surface_y: int, required_height: int) -> int:
	for y in range(surface_y - 4, -62, -1):
		if world.has_block(Vector3i(x, y, z)) or not world.has_block(Vector3i(x, y - 1, z)):
			continue
		var clear: bool = true
		for offset in range(required_height):
			if world.has_block(Vector3i(x, y + offset, z)):
				clear = false
				break
		if clear:
			return y
	return -9999


func _volume_is_clear(world, minimum: Vector3i, maximum: Vector3i) -> bool:
	for y in range(minimum.y, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				if world.has_block(Vector3i(x, y, z)):
					return false
	return true


func _foundations_touch_floor(world, template, origin: Vector3i, rotation: int, mirror_x: bool, mirror_z: bool) -> bool:
	for raw_marker in template.markers:
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("type", "")) != "foundation":
			continue
		var local_pos: Vector3i = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
		var target: Vector3i = origin + template.transform_position(local_pos, rotation, mirror_x, mirror_z)
		if not world.has_block(target - Vector3i(0, 1, 0)):
			return false
	# Templates without foundation markers use the pivot floor already found by
	# _find_cave_floor; marked templates validate every authored contact point.
	return true


func _load_template(rule: Dictionary):
	var path: String = str(rule.get("path", ""))
	if _template_cache.has(path):
		return _template_cache[path]
	var template = StructureTemplateScript.load_from_file(path)
	if template != null:
		_template_cache[path] = template
	return template


func _can_write(world, tile, pos: Vector3i) -> bool:
	if not world.is_inside_world(pos) or pos.y <= -65:
		return false
	var x: int = pos.x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE
	var z: int = pos.z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
	return tile.index_of(x, z) >= 0 and not tile.has_zone_flag(x, z, TerrainTileScript.ZONE_PROTECTED)


static func _overlaps_any(instance: Dictionary, others: Array) -> bool:
	for raw_other in others:
		var other: Dictionary = raw_other as Dictionary
		var a_min: Vector3i = instance["origin"]
		var a_max: Vector3i = instance["max"]
		var b_min: Vector3i = other["origin"]
		var b_max: Vector3i = other["max"]
		if a_min.x <= b_max.x and a_max.x >= b_min.x and a_min.y <= b_max.y and a_max.y >= b_min.y and a_min.z <= b_max.z and a_max.z >= b_min.z:
			return true
	return false


static func _hash01(x: int, y: int, z: int, salt: int) -> float:
	var value: float = sin(float(x) * 12.9898 + float(y) * 78.233 + float(z) * 37.719 + float(salt) * 19.19) * 43758.5453
	return value - floor(value)

