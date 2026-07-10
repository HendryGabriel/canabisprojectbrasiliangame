## Deterministic planning and application of directed/procedural structures.
class_name StructurePlacer
extends RefCounted


const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")


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

	for raw_rule in registry.get_rules():
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


func apply_instances(world, tile, instances: Array, report) -> void:
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
		for raw_local in template.metadata.keys():
			var target: Vector3i = origin + template.transform_position(raw_local as Vector3i, rotation, mirror_x, mirror_z)
			if world.is_inside_world(target):
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
		_apply_foundations(world, tile, instance)
		report.instances.append({"id": template.structure_id, "origin": origin, "mode": instance.get("mode", "surface_adaptive")})


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
			"underground":
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
			if mode == "underground" and maximum.y > tile.get_height(tx, tz) - int(rule.get("minimum_cover", 4)):
				return {"error": "cobertura subterranea insuficiente"}
	if mode == "cave_floor":
		if not _volume_is_clear(world, origin, maximum):
			return {"error": "volume da caverna esta obstruido"}
		if not _foundations_touch_floor(world, template, origin, rotation, mirror_x, mirror_z):
			return {"error": "fundacao nao encontra piso de caverna"}
	return {
		"template": template, "rule": rule, "origin": origin, "max": maximum,
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


func _apply_foundations(world, tile, instance: Dictionary) -> void:
	var template = instance["template"]
	var origin: Vector3i = instance["origin"]
	var rotation: int = int(instance["rotation"])
	var mirror_x: bool = bool(instance["mirror_x"])
	var mirror_z: bool = bool(instance["mirror_z"])
	var max_depth: int = int((instance["rule"] as Dictionary).get("max_support_depth", 24))
	for raw_marker in template.markers:
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("type", "")) != "foundation":
			continue
		var local_pos: Vector3i = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
		var target: Vector3i = origin + template.transform_position(local_pos, rotation, mirror_x, mirror_z)
		var block_id: String = str(marker.get("block", template.blocks.get(local_pos, "stone")))
		for depth in range(1, max_depth + 1):
			var support_pos: Vector3i = target - Vector3i(0, depth, 0)
			if world.has_block(support_pos):
				break
			if not _can_write(world, tile, support_pos):
				break
			world.set_base_block(support_pos, block_id)


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
