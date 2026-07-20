## Directed terrain runtime. TerrainTileData is authoritative; seed only drives
## deterministic caves, ores, decoration, and procedural structure choices.
class_name TerrainGenerator
extends RefCounted


const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const GenerationReportScript = preload("res://src/generation_report.gd")
const StructurePlacerScript = preload("res://src/structure_placer.gd")
const CaveRasterizerScript = preload("res://src/cave_network_rasterizer.gd")

const BEDROCK_Y: int = -65


func generate_into(world, tile, registry, seed: int):
	var report = GenerationReportScript.new()
	report.seed = seed
	if tile != null:
		report.tile_coord = tile.tile_coord
	if world == null or tile == null:
		report.add_error("VoxelWorld ou TerrainTile ausente.")
		return report
	for error in tile.validate():
		report.add_error(error)
	if registry != null:
		for error in registry.validate():
			report.add_error(error)
		for warning in registry.get_diagnostics():
			report.add_warning(warning)
	if not report.is_ok():
		return report
	for z in range(TerrainTileScript.TILE_SIZE):
		for x in range(TerrainTileScript.TILE_SIZE):
			_generate_column(world, tile, x, z, seed, report)
	var cave_rasterizer = CaveRasterizerScript.new()
	cave_rasterizer.carve_into(world, tile, seed, report)
	if registry != null:
		var placer = StructurePlacerScript.new()
		var instances: Array = placer.plan_instances(world, tile, registry, seed, report)
		placer.apply_instances(world, tile, registry, instances, report)
	_generate_vegetation(world, tile, seed, report)
	return report


func regenerate_columns(world, tile, cell_indices: Array, seed: int) -> Array:
	var report = GenerationReportScript.new()
	var affected: Dictionary = {}
	var allowed_columns: Dictionary = {}
	for raw_index in cell_indices:
		var index: int = int(raw_index)
		if index < 0 or index >= TerrainTileScript.CELL_COUNT:
			continue
		var x: int = index % TerrainTileScript.TILE_SIZE
		var z: int = index / TerrainTileScript.TILE_SIZE
		allowed_columns[index] = true
		var world_x: int = tile.tile_coord.x * TerrainTileScript.TILE_SIZE + x
		var world_z: int = tile.tile_coord.y * TerrainTileScript.TILE_SIZE + z
		# Also remove authored trees and foliage above the maximum terrain height.
		for y in range(BEDROCK_Y, 127):
			world.clear_base_block(Vector3i(world_x, y, world_z))
		_generate_column(world, tile, x, z, seed, report)
		for section_y in range(12):
			var section: Vector3i = world.get_section_coord(Vector3i(world_x, BEDROCK_Y + section_y * 16, world_z))
			if world.is_valid_section(section):
				affected[section] = true
	var cave_rasterizer = CaveRasterizerScript.new()
	for section in cave_rasterizer.carve_into(world, tile, seed, report, allowed_columns).keys():
		affected[section] = true
	return affected.keys()


func _generate_column(world, tile, local_x: int, local_z: int, seed: int, report) -> void:
	var world_x: int = tile.tile_coord.x * TerrainTileScript.TILE_SIZE + local_x
	var world_z: int = tile.tile_coord.y * TerrainTileScript.TILE_SIZE + local_z
	var surface_y: int = tile.get_height(local_x, local_z)
	var profile: int = tile.get_profile(local_x, local_z)
	world.set_surface_height(world_x, world_z, surface_y)
	for y in range(BEDROCK_Y, surface_y + 1):
		var pos: Vector3i = Vector3i(world_x, y, world_z)
		var block_id: String
		if y == BEDROCK_Y:
			block_id = "bedrock"
		else:
			var depth: int = surface_y - y
			block_id = _block_for_profile(profile, depth, world_x, y, world_z, seed)
		if world.set_base_block(pos, block_id):
			report.generated_blocks += 1
	report.generated_columns += 1


func _block_for_profile(profile: int, depth: int, x: int, y: int, z: int, seed: int) -> String:
	if depth == 0:
		match profile:
			TerrainTileScript.PROFILE_ROCK: return "stone"
			TerrainTileScript.PROFILE_DIRT: return "dirt"
			_: return "grass"
	if depth <= 3 and profile != TerrainTileScript.PROFILE_ROCK:
		return "dirt"
	var roll: float = _hash01(x, y, z, seed + 123)
	if depth >= 70 and roll < 0.006: return "manita_ore"
	if depth >= 32 and roll < 0.022: return "iron_ore"
	if depth >= 12 and depth <= 72 and roll < 0.041: return "copper_ore"
	if depth >= 7 and roll < 0.067: return "coal_ore"
	return "stone"


func _generate_vegetation(world, tile, seed: int, report) -> void:
	for z in range(2, TerrainTileScript.TILE_SIZE - 2):
		for x in range(2, TerrainTileScript.TILE_SIZE - 2):
			if tile.has_zone_flag(x, z, TerrainTileScript.ZONE_PROTECTED):
				continue
			var surface_y: int = tile.get_height(x, z)
			var world_x: int = tile.tile_coord.x * TerrainTileScript.TILE_SIZE + x
			var world_z: int = tile.tile_coord.y * TerrainTileScript.TILE_SIZE + z
			var vegetation_pos: Vector3i = Vector3i(world_x, surface_y + 1, world_z)
			if world.get_block_id(Vector3i(world_x, surface_y, world_z)) != "grass" or world.has_block(vegetation_pos) or _inside_structure_reservation(vegetation_pos, report.instances):
				continue
			var roll: float = _hash01(world_x, surface_y, world_z, seed + 707)
			if tile.has_zone_flag(x, z, TerrainTileScript.ZONE_FOREST) and roll < 0.025:
				_place_tree(world, tile, vegetation_pos, seed, report)
			elif tile.has_zone_flag(x, z, TerrainTileScript.ZONE_DECORATION) and roll < 0.13:
				var decor_roll: float = _hash01(world_x, surface_y, world_z, seed + 808)
				var decor_id: String = "short_grass" if decor_roll < 0.58 else ("wild_grass" if decor_roll < 0.78 else ("dandelion" if decor_roll < 0.88 else ("poppy" if decor_roll < 0.96 else "cornflower")))
				if world.set_base_block(Vector3i(world_x, surface_y + 1, world_z), decor_id):
					report.generated_blocks += 1


func _place_tree(world, tile, base: Vector3i, seed: int, report) -> void:
	var height: int = 4 + int(floor(_hash01(base.x, base.y, base.z, seed + 505) * 3.0))
	for offset in range(height):
		var trunk_pos: Vector3i = base + Vector3i(0, offset, 0)
		if not _inside_structure_reservation(trunk_pos, report.instances) and world.set_base_block(trunk_pos, "wood"):
			report.generated_blocks += 1
	var center: Vector3i = base + Vector3i(0, height, 0)
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var distance: float = Vector3(float(dx), float(dy) * 1.25, float(dz)).length()
				if distance > 3.0 or _hash01(center.x + dx, center.y + dy, center.z + dz, seed + 612) < maxf(0.0, distance - 2.25) * 0.24:
					continue
				var pos: Vector3i = center + Vector3i(dx, dy, dz)
				var local_x: int = pos.x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE
				var local_z: int = pos.z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
				if tile.index_of(local_x, local_z) >= 0 and not tile.has_zone_flag(local_x, local_z, TerrainTileScript.ZONE_PROTECTED) and not world.has_block(pos) and not _inside_structure_reservation(pos, report.instances):
					if world.set_base_block(pos, "leaves"):
						report.generated_blocks += 1


static func _inside_structure_reservation(pos: Vector3i, instances: Array) -> bool:
	for raw_instance in instances:
		var instance: Dictionary = raw_instance as Dictionary
		var minimum: Vector3i = instance.get("origin", Vector3i.ZERO)
		var maximum: Vector3i = instance.get("max", minimum)
		if pos.x >= minimum.x and pos.x <= maximum.x and pos.y >= minimum.y and pos.y <= maximum.y and pos.z >= minimum.z and pos.z <= maximum.z:
			return true
	return false


static func _hash01(x: int, y: int, z: int, salt: int) -> float:
	var value: float = sin(float(x) * 12.9898 + float(y) * 78.233 + float(z) * 37.719 + float(salt) * 19.19) * 43758.5453
	return value - floor(value)
