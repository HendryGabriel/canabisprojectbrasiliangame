## Versioned, shareable source data for one directed 100x100 terrain tile.
class_name TerrainTileData
extends RefCounted


const FORMAT: String = "trumancraft_terrain_tile"
const VERSION: int = 2
const LEGACY_VERSION: int = 1
const TILE_SIZE: int = 100
const CELL_COUNT: int = TILE_SIZE * TILE_SIZE
const MIN_SURFACE_Y: int = -32
const MAX_SURFACE_Y: int = 96

const PROFILE_GRASS: int = 0
const PROFILE_ROCK: int = 1
const PROFILE_DIRT: int = 2
const PROFILE_MEADOW: int = 3

const ZONE_STRUCTURES: int = 1
const ZONE_PROTECTED: int = 2
const ZONE_FOREST: int = 4
const ZONE_DECORATION: int = 8
const ZONE_NO_CAVES: int = 16
const ALL_ZONE_FLAGS: int = ZONE_STRUCTURES | ZONE_PROTECTED | ZONE_FOREST | ZONE_DECORATION | ZONE_NO_CAVES


var tile_coord: Vector2i = Vector2i.ZERO
var draft_seed: int = 0
var heights: PackedInt32Array = PackedInt32Array()
var surface_profiles: PackedByteArray = PackedByteArray()
var cave_density: PackedByteArray = PackedByteArray()
var zone_flags: PackedByteArray = PackedByteArray()
var cave_entrances: Array = []
var cave_networks: Array = []
var cave_overrides: Dictionary = {"carve": [], "fill": []}
var anchors: Array = []
var source_path: String = ""


func _init() -> void:
	heights.resize(CELL_COUNT)
	heights.fill(16)
	surface_profiles.resize(CELL_COUNT)
	surface_profiles.fill(PROFILE_GRASS)
	cave_density.resize(CELL_COUNT)
	cave_density.fill(128)
	zone_flags.resize(CELL_COUNT)
	zone_flags.fill(ZONE_STRUCTURES | ZONE_DECORATION)


static func create_draft(seed: int, coord: Vector2i = Vector2i.ZERO):
	var tile = (load("res://src/terrain_tile_data.gd") as Script).new()
	tile.tile_coord = coord
	tile.draft_seed = seed
	var broad: FastNoiseLite = FastNoiseLite.new()
	broad.seed = seed
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.frequency = 0.009
	broad.fractal_octaves = 3
	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = seed + 31
	detail.frequency = 0.038
	detail.fractal_octaves = 2
	var ridge: FastNoiseLite = FastNoiseLite.new()
	ridge.seed = seed + 71
	ridge.frequency = 0.013
	ridge.fractal_octaves = 2
	var biome: FastNoiseLite = FastNoiseLite.new()
	biome.seed = seed + 113
	biome.frequency = 0.018
	for z in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var world_x: float = float(coord.x * TILE_SIZE + x)
			var world_z: float = float(coord.y * TILE_SIZE + z)
			var broad_value: float = broad.get_noise_2d(world_x, world_z)
			var detail_value: float = detail.get_noise_2d(world_x, world_z)
			var rare_value: float = maxf(0.0, abs(ridge.get_noise_2d(world_x, world_z)) - 0.62) / 0.38
			var rare_sign: float = 1.0 if ridge.get_noise_2d(world_x + 311.0, world_z - 173.0) >= 0.0 else -1.0
			var height: int = clampi(int(round(12.0 + broad_value * 1.35 + detail_value * 0.65 + rare_sign * rare_value * rare_value * 5.0)), MIN_SURFACE_Y, MAX_SURFACE_Y)
			var index: int = tile.index_of(x, z)
			tile.heights[index] = height
			var biome_value: float = biome.get_noise_2d(world_x, world_z)
			tile.surface_profiles[index] = PROFILE_MEADOW if biome_value > 0.42 else PROFILE_GRASS
			tile.cave_density[index] = clampi(int(round(82.0 + detail_value * 32.0)), 0, 255)
			var flags: int = ZONE_STRUCTURES | ZONE_DECORATION
			if biome_value > 0.18 and height < 62:
				flags |= ZONE_FOREST
			tile.zone_flags[index] = flags
	# New draft tiles reserve and soften the gameplay spawn. Authored tiles can
	# later repaint this area explicitly.
	var spawn_height: int = tile.get_height(50, 50)
	for z in range(41, 60):
		for x in range(41, 60):
			var distance: float = Vector2(float(x - 50), float(z - 50)).length()
			if distance <= 9.0:
				var blend: float = clampf(1.0 - distance / 9.0, 0.0, 1.0)
				var index: int = tile.index_of(x, z)
				tile.heights[index] = int(round(lerpf(float(tile.heights[index]), float(spawn_height), blend)))
				tile.zone_flags[index] = ZONE_PROTECTED
	if coord == Vector2i.ZERO:
		tile.cave_networks = _create_biome_one_cave_networks(tile)
	return tile


static func _create_biome_one_cave_networks(tile) -> Array:
	var entry_a_y: int = tile.get_height(22, 25) + 1
	var entry_b_y: int = tile.get_height(77, 72) + 1
	return [
		{
			"id": "plains_west", "name": "Galerias do Oeste",
			"nodes": [
				{"id": "wa0", "pos": [22, entry_a_y, 25], "radius": 3, "type": "entrance"},
				{"id": "wa1", "pos": [24, 5, 29], "radius": 4, "type": "route"},
				{"id": "wa2", "pos": [13, -3, 38], "radius": 4, "type": "route"},
				{"id": "wa3", "pos": [31, -9, 45], "radius": 5, "type": "route"},
				{"id": "wa4", "pos": [18, -18, 57], "radius": 7, "type": "chamber"},
				{"id": "wa5", "pos": [8, -26, 72], "radius": 4, "type": "route"},
				{"id": "wa6", "pos": [29, -31, 78], "radius": 5, "type": "route"},
				{"id": "wa7", "pos": [39, -39, 63], "radius": 6, "type": "chamber"},
				{"id": "wa8", "pos": [28, -46, 49], "radius": 4, "type": "route"},
				{"id": "wa9", "pos": [46, -55, 50], "radius": 5, "type": "route"},
			],
			"edges": [["wa0", "wa1"], ["wa1", "wa2"], ["wa2", "wa3"], ["wa3", "wa4"], ["wa4", "wa5"], ["wa4", "wa6"], ["wa5", "wa6"], ["wa6", "wa7"], ["wa7", "wa8"], ["wa8", "wa4"], ["wa8", "wa9"]],
		},
		{
			"id": "plains_east", "name": "Galerias do Leste",
			"nodes": [
				{"id": "eb0", "pos": [77, entry_b_y, 72], "radius": 4, "type": "entrance"},
				{"id": "eb1", "pos": [73, 5, 67], "radius": 4, "type": "route"},
				{"id": "eb2", "pos": [86, -4, 58], "radius": 5, "type": "route"},
				{"id": "eb3", "pos": [68, -11, 51], "radius": 4, "type": "route"},
				{"id": "eb4", "pos": [81, -20, 40], "radius": 8, "type": "chamber"},
				{"id": "eb5", "pos": [92, -28, 28], "radius": 4, "type": "route"},
				{"id": "eb6", "pos": [72, -34, 24], "radius": 5, "type": "route"},
				{"id": "eb7", "pos": [61, -42, 37], "radius": 6, "type": "chamber"},
				{"id": "eb8", "pos": [72, -48, 52], "radius": 4, "type": "route"},
				{"id": "eb9", "pos": [51, -54, 50], "radius": 5, "type": "route"},
			],
			"edges": [["eb0", "eb1"], ["eb1", "eb2"], ["eb2", "eb3"], ["eb3", "eb4"], ["eb4", "eb5"], ["eb4", "eb6"], ["eb5", "eb6"], ["eb6", "eb7"], ["eb7", "eb8"], ["eb8", "eb3"], ["eb8", "eb9"]],
		},
	]


func index_of(x: int, z: int) -> int:
	return z * TILE_SIZE + x if x >= 0 and x < TILE_SIZE and z >= 0 and z < TILE_SIZE else -1


func get_height(x: int, z: int, fallback: int = 0) -> int:
	var index: int = index_of(x, z)
	return int(heights[index]) if index >= 0 else fallback


func set_height(x: int, z: int, value: int) -> bool:
	var index: int = index_of(x, z)
	if index < 0:
		return false
	heights[index] = clampi(value, MIN_SURFACE_Y, MAX_SURFACE_Y)
	return true


func get_profile(x: int, z: int) -> int:
	var index: int = index_of(x, z)
	return int(surface_profiles[index]) if index >= 0 else PROFILE_GRASS


func get_cave_density(x: int, z: int) -> int:
	var index: int = index_of(x, z)
	return int(cave_density[index]) if index >= 0 else 0


func get_zone_flags(x: int, z: int) -> int:
	var index: int = index_of(x, z)
	return int(zone_flags[index]) if index >= 0 else 0


func has_zone_flag(x: int, z: int, flag: int) -> bool:
	return (get_zone_flags(x, z) & flag) != 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if tile_coord.x < 0 or tile_coord.x > 1 or tile_coord.y < 0 or tile_coord.y > 1:
		errors.append("tile_coord deve estar na grade 2x2.")
	if heights.size() != CELL_COUNT or surface_profiles.size() != CELL_COUNT or cave_density.size() != CELL_COUNT or zone_flags.size() != CELL_COUNT:
		errors.append("Grades do tile devem conter exatamente 10000 celulas.")
	for value in heights:
		if value < MIN_SURFACE_Y or value > MAX_SURFACE_Y:
			errors.append("Altura fora do intervalo -32..96.")
			break
	for value in surface_profiles:
		if int(value) < PROFILE_GRASS or int(value) > PROFILE_MEADOW:
			errors.append("Perfil de superficie desconhecido.")
			break
	for value in zone_flags:
		if (int(value) & ~ALL_ZONE_FLAGS) != 0:
			errors.append("Flags de zona desconhecidas.")
			break
	for raw_entrance in cave_entrances:
		if typeof(raw_entrance) != TYPE_DICTIONARY:
			errors.append("Entrada de caverna invalida.")
			continue
		var entrance: Dictionary = raw_entrance as Dictionary
		if index_of(int(entrance.get("x", -1)), int(entrance.get("z", -1))) < 0:
			errors.append("Entrada de caverna fora do tile.")
		if int(entrance.get("radius", 3)) < 1 or int(entrance.get("radius", 3)) > 8 or int(entrance.get("depth", 10)) < 3 or int(entrance.get("depth", 10)) > 32:
			errors.append("Entrada de caverna possui raio/profundidade invalidos.")
	errors.append_array(_validate_cave_networks())
	for override_type in ["carve", "fill"]:
		var raw_overrides: Variant = cave_overrides.get(override_type, [])
		if typeof(raw_overrides) != TYPE_ARRAY:
			errors.append("Overrides de caverna '%s' devem ser uma lista." % override_type)
			continue
		for raw_pos in raw_overrides as Array:
			var pos: Vector3i = _vector3i_from_value(raw_pos, Vector3i(-999, -999, -999))
			if index_of(pos.x, pos.z) < 0 or pos.y <= -65 or pos.y > 126:
				errors.append("Override de caverna '%s' fora dos limites." % override_type)
				break
	for raw_anchor in anchors:
		if typeof(raw_anchor) != TYPE_DICTIONARY:
			errors.append("Ancora de estrutura invalida.")
			continue
		var anchor: Dictionary = raw_anchor as Dictionary
		var x: int = int(anchor.get("x", -1))
		var z: int = int(anchor.get("z", -1))
		if index_of(x, z) < 0 or str(anchor.get("template_id", "")) == "":
			errors.append("Ancora de estrutura fora do tile ou sem template_id.")
		if int(anchor.get("rotation", 0)) < 0 or int(anchor.get("rotation", 0)) > 3:
			errors.append("Rotacao de ancora deve estar entre 0 e 3.")
		if str(anchor.get("mode", "surface_adaptive")) not in ["surface_adaptive", "cave_floor", "underground"]:
			errors.append("Modo de ancora desconhecido.")
	return errors


func to_dictionary() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"tile_coord": [tile_coord.x, tile_coord.y],
		"tile_size": TILE_SIZE,
		"min_surface_y": MIN_SURFACE_Y,
		"max_surface_y": MAX_SURFACE_Y,
		"draft_seed": draft_seed,
		"heights_rle": _encode_rle_int(heights),
		"surface_profiles_rle": _encode_rle_byte(surface_profiles),
		"cave_density_rle": _encode_rle_byte(cave_density),
		"zone_flags_rle": _encode_rle_byte(zone_flags),
		"cave_entrances": cave_entrances,
		"cave_networks": cave_networks,
		"cave_overrides": cave_overrides,
		"anchors": anchors,
	}


static func from_dictionary(data: Dictionary):
	var file_version: int = int(data.get("version", 0))
	if str(data.get("format", "")) != FORMAT or file_version not in [LEGACY_VERSION, VERSION] or int(data.get("tile_size", 0)) != TILE_SIZE:
		return null
	if bool(data.get("draft_only", false)):
		var raw_draft_coord: Variant = data.get("tile_coord", [0, 0])
		var draft_coord: Vector2i = Vector2i.ZERO
		if typeof(raw_draft_coord) == TYPE_ARRAY and (raw_draft_coord as Array).size() >= 2:
			draft_coord = Vector2i(int(raw_draft_coord[0]), int(raw_draft_coord[1]))
		var draft = create_draft(int(data.get("draft_seed", 0)), draft_coord)
		draft.cave_entrances = (data.get("cave_entrances", []) as Array).duplicate(true)
		if file_version >= VERSION and data.has("cave_networks") and typeof(data.get("cave_networks", [])) == TYPE_ARRAY:
			draft.cave_networks = (data.get("cave_networks", []) as Array).duplicate(true)
		elif not draft.cave_entrances.is_empty():
			draft.cave_networks = _networks_from_legacy_entrances(draft)
		if typeof(data.get("cave_overrides", {})) == TYPE_DICTIONARY:
			draft.cave_overrides = (data.get("cave_overrides", {}) as Dictionary).duplicate(true)
		draft.anchors = (data.get("anchors", []) as Array).duplicate(true)
		return draft
	var tile = (load("res://src/terrain_tile_data.gd") as Script).new()
	var raw_coord: Variant = data.get("tile_coord", [0, 0])
	if typeof(raw_coord) == TYPE_ARRAY and (raw_coord as Array).size() >= 2:
		tile.tile_coord = Vector2i(int(raw_coord[0]), int(raw_coord[1]))
	tile.draft_seed = int(data.get("draft_seed", 0))
	var decoded_heights: PackedInt32Array = _decode_rle_int(data.get("heights_rle", []), CELL_COUNT)
	var decoded_profiles: PackedByteArray = _decode_rle_byte(data.get("surface_profiles_rle", []), CELL_COUNT)
	var decoded_caves: PackedByteArray = _decode_rle_byte(data.get("cave_density_rle", []), CELL_COUNT)
	var decoded_zones: PackedByteArray = _decode_rle_byte(data.get("zone_flags_rle", []), CELL_COUNT)
	if decoded_heights.size() != CELL_COUNT or decoded_profiles.size() != CELL_COUNT or decoded_caves.size() != CELL_COUNT or decoded_zones.size() != CELL_COUNT:
		return null
	tile.heights = decoded_heights
	tile.surface_profiles = decoded_profiles
	tile.cave_density = decoded_caves
	tile.zone_flags = decoded_zones
	tile.cave_entrances = (data.get("cave_entrances", []) as Array).duplicate(true)
	if file_version >= VERSION and typeof(data.get("cave_networks", [])) == TYPE_ARRAY:
		tile.cave_networks = (data.get("cave_networks", []) as Array).duplicate(true)
	else:
		tile.cave_networks = _networks_from_legacy_entrances(tile)
	if typeof(data.get("cave_overrides", {})) == TYPE_DICTIONARY:
		tile.cave_overrides = (data.get("cave_overrides", {}) as Dictionary).duplicate(true)
	tile.anchors = (data.get("anchors", []) as Array).duplicate(true)
	return tile


static func load_from_file(path: String):
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var tile = from_dictionary(parsed as Dictionary)
	if tile != null:
		tile.source_path = path
	return tile


func save_to_file(path: String) -> Error:
	var errors: Array[String] = validate()
	if not errors.is_empty():
		push_error("TerrainTile invalido: %s" % "; ".join(errors))
		return ERR_INVALID_DATA
	var temporary_path: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	var absolute_target: String = ProjectSettings.globalize_path(path)
	var absolute_temporary: String = ProjectSettings.globalize_path(temporary_path)
	var backup_path: String = "%s.bak" % path
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	var had_target: bool = FileAccess.file_exists(path)
	if had_target:
		var backup_error: Error = DirAccess.rename_absolute(absolute_target, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return backup_error
	var rename_error: Error = DirAccess.rename_absolute(absolute_temporary, absolute_target)
	if rename_error != OK:
		if had_target:
			DirAccess.rename_absolute(absolute_backup, absolute_target)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(absolute_temporary)
		return rename_error
	if had_target and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	source_path = path
	return rename_error


func content_hash() -> String:
	return JSON.stringify(to_dictionary()).sha256_text()


func duplicate_tile():
	return from_dictionary(to_dictionary())


func _validate_cave_networks() -> Array[String]:
	var errors: Array[String] = []
	var network_ids: Dictionary = {}
	for raw_network in cave_networks:
		if typeof(raw_network) != TYPE_DICTIONARY:
			errors.append("Rede de caverna invalida.")
			continue
		var network: Dictionary = raw_network as Dictionary
		var network_id: String = str(network.get("id", "")).strip_edges()
		if network_id == "" or network_ids.has(network_id):
			errors.append("Rede de caverna sem ID ou com ID duplicado: %s." % network_id)
			continue
		network_ids[network_id] = true
		var node_ids: Dictionary = {}
		var raw_nodes: Variant = network.get("nodes", [])
		if typeof(raw_nodes) != TYPE_ARRAY:
			errors.append("Rede %s nao possui lista de nos." % network_id)
			continue
		for raw_node in raw_nodes as Array:
			if typeof(raw_node) != TYPE_DICTIONARY:
				errors.append("Rede %s possui no invalido." % network_id)
				continue
			var node: Dictionary = raw_node as Dictionary
			var node_id: String = str(node.get("id", "")).strip_edges()
			if node_id == "" or node_ids.has(node_id):
				errors.append("Rede %s possui ID de no vazio/duplicado: %s." % [network_id, node_id])
				continue
			node_ids[node_id] = true
			var pos: Vector3i = _vector3i_from_value(node.get("pos", []), Vector3i(-999, -999, -999))
			var node_type: String = str(node.get("type", "route"))
			var radius: int = int(node.get("radius", 0))
			if node_type not in ["route", "entrance", "chamber"]:
				errors.append("No %s/%s possui tipo desconhecido." % [network_id, node_id])
			if (node_type == "entrance" and (radius < 2 or radius > 7)) or (node_type != "entrance" and (radius < 3 or radius > 9)):
				errors.append("No %s/%s possui raio invalido." % [network_id, node_id])
			if index_of(pos.x, pos.z) < 0 or pos.y <= -65 or pos.y > 126:
				errors.append("No %s/%s esta fora do volume do mundo." % [network_id, node_id])
			elif pos.x - radius < 0 or pos.x + radius >= TILE_SIZE or pos.z - radius < 0 or pos.z + radius >= TILE_SIZE or pos.y - radius <= -65:
				errors.append("Raio do no %s/%s ultrapassa tile ou bedrock." % [network_id, node_id])
		var raw_edges: Variant = network.get("edges", [])
		if typeof(raw_edges) != TYPE_ARRAY:
			errors.append("Rede %s nao possui lista de arestas." % network_id)
			continue
		for raw_edge in raw_edges as Array:
			var endpoints: PackedStringArray = _edge_endpoints(raw_edge)
			if endpoints.size() != 2 or not node_ids.has(endpoints[0]) or not node_ids.has(endpoints[1]) or endpoints[0] == endpoints[1]:
				errors.append("Rede %s possui aresta orfa ou invalida." % network_id)
	return errors


static func _edge_endpoints(raw_edge: Variant) -> PackedStringArray:
	if typeof(raw_edge) == TYPE_ARRAY and (raw_edge as Array).size() >= 2:
		return PackedStringArray([str((raw_edge as Array)[0]), str((raw_edge as Array)[1])])
	if typeof(raw_edge) == TYPE_DICTIONARY:
		var edge: Dictionary = raw_edge as Dictionary
		return PackedStringArray([str(edge.get("from", "")), str(edge.get("to", ""))])
	return PackedStringArray()


static func _vector3i_from_value(raw_value: Variant, fallback: Vector3i = Vector3i.ZERO) -> Vector3i:
	if raw_value is Vector3i:
		return raw_value as Vector3i
	if typeof(raw_value) != TYPE_ARRAY or (raw_value as Array).size() < 3:
		return fallback
	var values: Array = raw_value as Array
	return Vector3i(int(values[0]), int(values[1]), int(values[2]))


static func _networks_from_legacy_entrances(tile) -> Array:
	var networks: Array = []
	var serial: int = 0
	for raw_entrance in tile.cave_entrances:
		if typeof(raw_entrance) != TYPE_DICTIONARY:
			continue
		var entrance: Dictionary = raw_entrance as Dictionary
		var x: int = int(entrance.get("x", -1))
		var z: int = int(entrance.get("z", -1))
		if tile.index_of(x, z) < 0:
			continue
		var radius: int = clampi(int(entrance.get("radius", 3)), 2, 7)
		var depth: int = clampi(int(entrance.get("depth", 10)), 3, 32)
		var surface: int = tile.get_height(x, z)
		var prefix: String = "legacy_%d" % serial
		networks.append({
			"id": prefix,
			"name": "Entrada legada %d" % (serial + 1),
			"nodes": [
				{"id": "%s_entry" % prefix, "pos": [x, surface + 1, z], "radius": radius, "type": "entrance"},
				{"id": "%s_end" % prefix, "pos": [x, maxi(-61, surface - depth), z], "radius": clampi(radius, 3, 9), "type": "route"},
			],
			"edges": [["%s_entry" % prefix, "%s_end" % prefix]],
		})
		serial += 1
	return networks


static func _encode_rle_int(values: PackedInt32Array) -> Array:
	var result: Array = []
	if values.is_empty():
		return result
	var current: int = int(values[0])
	var count: int = 1
	for index in range(1, values.size()):
		var value: int = int(values[index])
		if value == current:
			count += 1
		else:
			result.append([current, count])
			current = value
			count = 1
	result.append([current, count])
	return result


static func _encode_rle_byte(values: PackedByteArray) -> Array:
	var as_ints: PackedInt32Array = PackedInt32Array()
	as_ints.resize(values.size())
	for index in range(values.size()):
		as_ints[index] = int(values[index])
	return _encode_rle_int(as_ints)


static func _decode_rle_int(raw_value: Variant, expected_size: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if typeof(raw_value) != TYPE_ARRAY:
		return result
	for raw_run in raw_value as Array:
		if typeof(raw_run) != TYPE_ARRAY or (raw_run as Array).size() != 2:
			return PackedInt32Array()
		var run: Array = raw_run as Array
		var value: int = int(run[0])
		var count: int = int(run[1])
		if count <= 0 or result.size() + count > expected_size:
			return PackedInt32Array()
		for _index in range(count):
			result.append(value)
	return result if result.size() == expected_size else PackedInt32Array()


static func _decode_rle_byte(raw_value: Variant, expected_size: int) -> PackedByteArray:
	var decoded: PackedInt32Array = _decode_rle_int(raw_value, expected_size)
	var result: PackedByteArray = PackedByteArray()
	if decoded.size() != expected_size:
		return result
	result.resize(expected_size)
	for index in range(expected_size):
		result[index] = clampi(int(decoded[index]), 0, 255)
	return result
