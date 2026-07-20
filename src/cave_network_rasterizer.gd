## Converts authored cave graphs into deterministic voxel tunnels.
class_name CaveNetworkRasterizer
extends RefCounted


const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const BEDROCK_Y: int = -65


func carve_into(world, tile, seed: int, report = null, allowed_columns: Dictionary = {}) -> Dictionary:
	var affected: Dictionary = {}
	for raw_network in tile.cave_networks:
		if typeof(raw_network) != TYPE_DICTIONARY:
			continue
		var network: Dictionary = raw_network as Dictionary
		var nodes: Dictionary = {}
		for raw_node in network.get("nodes", []) as Array:
			if typeof(raw_node) == TYPE_DICTIONARY:
				var node: Dictionary = raw_node as Dictionary
				nodes[str(node.get("id", ""))] = node
		for raw_edge in network.get("edges", []) as Array:
			var endpoints: PackedStringArray = TerrainTileScript._edge_endpoints(raw_edge)
			if endpoints.size() != 2 or not nodes.has(endpoints[0]) or not nodes.has(endpoints[1]):
				continue
			_carve_segment(world, tile, nodes[endpoints[0]] as Dictionary, nodes[endpoints[1]] as Dictionary, raw_edge, seed, allowed_columns, affected, report)
		for raw_node in nodes.values():
			var node: Dictionary = raw_node as Dictionary
			var local_center: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
			var radius: float = float(node.get("radius", 3))
			var vertical_scale: float = 1.15 if str(node.get("type", "route")) == "chamber" else 0.82
			_carve_ellipsoid(world, tile, Vector3(local_center), radius, vertical_scale, seed, allowed_columns, affected, report)
	_apply_overrides(world, tile, allowed_columns, affected, report)
	return affected


func _carve_segment(world, tile, a: Dictionary, b: Dictionary, raw_edge: Variant, seed: int, allowed_columns: Dictionary, affected: Dictionary, report) -> void:
	var start: Vector3 = Vector3(TerrainTileScript._vector3i_from_value(a.get("pos", [])))
	var finish: Vector3 = Vector3(TerrainTileScript._vector3i_from_value(b.get("pos", [])))
	var start_radius: float = float(a.get("radius", 3))
	var end_radius: float = float(b.get("radius", 3))
	var vertical_scale: float = 0.82
	if typeof(raw_edge) == TYPE_DICTIONARY:
		var edge: Dictionary = raw_edge as Dictionary
		if edge.has("radius"):
			start_radius = float(edge["radius"])
			end_radius = start_radius
		vertical_scale = clampf(float(edge.get("vertical_scale", vertical_scale)), 0.55, 1.5)
	var distance: float = start.distance_to(finish)
	var steps: int = maxi(1, ceili(distance / 0.42))
	for step in range(steps + 1):
		var t: float = float(step) / float(steps)
		var center: Vector3 = start.lerp(finish, t)
		var radius: float = lerpf(start_radius, end_radius, t)
		_carve_ellipsoid(world, tile, center, radius, vertical_scale, seed, allowed_columns, affected, report)


func _carve_ellipsoid(world, tile, local_center: Vector3, radius: float, vertical_scale: float, seed: int, allowed_columns: Dictionary, affected: Dictionary, report) -> void:
	var y_radius: float = maxf(2.0, radius * vertical_scale)
	var extent: int = ceili(radius + 1.0)
	var y_extent: int = ceili(y_radius + 1.0)
	var tile_origin: Vector2i = tile.tile_coord * TerrainTileScript.TILE_SIZE
	for dy in range(-y_extent, y_extent + 1):
		for dz in range(-extent, extent + 1):
			for dx in range(-extent, extent + 1):
				var local_x: int = roundi(local_center.x) + dx
				var local_y: int = roundi(local_center.y) + dy
				var local_z: int = roundi(local_center.z) + dz
				var column_index: int = tile.index_of(local_x, local_z)
				if column_index < 0 or local_y <= BEDROCK_Y or local_y > 126:
					continue
				if not allowed_columns.is_empty() and not allowed_columns.has(column_index):
					continue
				# ZONE_PROTECTED is a surface/editor reservation. Applying it to every
				# Y would turn that 2D mask into an underground wall and sever authored
				# cave networks that legitimately pass below the protected area.
				var normalized: float = sqrt(pow(float(dx) / radius, 2.0) + pow(float(dy) / y_radius, 2.0) + pow(float(dz) / radius, 2.0))
				var density: float = float(tile.get_cave_density(local_x, local_z)) / 255.0
				var wall_noise: float = (_hash01(local_x, local_y, local_z, seed + 941) - 0.5) * density * 0.22
				if normalized > 1.0 + wall_noise:
					continue
				var world_pos: Vector3i = Vector3i(tile_origin.x + local_x, local_y, tile_origin.y + local_z)
				if world.clear_base_block(world_pos):
					for section in world.get_affected_sections(world_pos): affected[section] = true
					if report != null:
						report.carved_voxels += 1


func _apply_overrides(world, tile, allowed_columns: Dictionary, affected: Dictionary, report) -> void:
	var tile_origin: Vector2i = tile.tile_coord * TerrainTileScript.TILE_SIZE
	for raw_pos in tile.cave_overrides.get("carve", []) as Array:
		var local_pos: Vector3i = TerrainTileScript._vector3i_from_value(raw_pos)
		var index: int = tile.index_of(local_pos.x, local_pos.z)
		if index < 0 or tile.has_zone_flag(local_pos.x, local_pos.z, TerrainTileScript.ZONE_PROTECTED) or (not allowed_columns.is_empty() and not allowed_columns.has(index)):
			continue
		var world_pos: Vector3i = Vector3i(tile_origin.x + local_pos.x, local_pos.y, tile_origin.y + local_pos.z)
		if world.clear_base_block(world_pos):
			for section in world.get_affected_sections(world_pos): affected[section] = true
			if report != null: report.carved_voxels += 1
	for raw_pos in tile.cave_overrides.get("fill", []) as Array:
		var local_pos: Vector3i = TerrainTileScript._vector3i_from_value(raw_pos)
		var index: int = tile.index_of(local_pos.x, local_pos.z)
		if index < 0 or tile.has_zone_flag(local_pos.x, local_pos.z, TerrainTileScript.ZONE_PROTECTED) or (not allowed_columns.is_empty() and not allowed_columns.has(index)):
			continue
		var world_pos: Vector3i = Vector3i(tile_origin.x + local_pos.x, local_pos.y, tile_origin.y + local_pos.z)
		if world.set_base_block(world_pos, "stone"):
			for section in world.get_affected_sections(world_pos): affected[section] = true


static func _hash01(x: int, y: int, z: int, salt: int) -> float:
	var value: float = sin(float(x) * 12.9898 + float(y) * 78.233 + float(z) * 37.719 + float(salt) * 19.19) * 43758.5453
	return value - floor(value)
