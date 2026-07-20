## Canonical mixed-material occupancy for one normal voxel cell.
class_name MicroCellData
extends RefCounted


const SIZE: int = 8
const VOLUME: int = SIZE * SIZE * SIZE


var palette: PackedStringArray = PackedStringArray([""])
var voxels: PackedByteArray = PackedByteArray()
var piece_edges: PackedByteArray = PackedByteArray()


func _init() -> void:
	voxels.resize(VOLUME)
	voxels.fill(0)
	piece_edges.resize(VOLUME)
	piece_edges.fill(0)


func duplicate_cell():
	var copy = (load("res://src/micro_cell_data.gd") as Script).new()
	copy.palette = palette.duplicate()
	copy.voxels = voxels.duplicate()
	copy.piece_edges = piece_edges.duplicate()
	return copy


func is_inside(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < SIZE and pos.y >= 0 and pos.y < SIZE and pos.z >= 0 and pos.z < SIZE


func get_material(pos: Vector3i) -> String:
	if not is_inside(pos):
		return ""
	var palette_id: int = int(voxels[_index(pos)])
	return str(palette[palette_id]) if palette_id > 0 and palette_id < palette.size() else ""


func get_piece_edge(pos: Vector3i) -> int:
	return int(piece_edges[_index(pos)]) if is_inside(pos) else 0


func get_piece_origin(pos: Vector3i) -> Vector3i:
	var edge: int = get_piece_edge(pos)
	return Vector3i((pos.x / edge) * edge, (pos.y / edge) * edge, (pos.z / edge) * edge) if edge > 0 else pos


func set_material(pos: Vector3i, material_id: String, piece_edge: int = 1) -> bool:
	if not is_inside(pos) or (material_id != "" and piece_edge not in [1, 2, 4, 8]):
		return false
	var palette_id: int = _palette_id(material_id)
	if material_id != "" and palette_id == 0:
		return false
	var index: int = _index(pos)
	var normalized_edge: int = piece_edge if material_id != "" else 0
	if int(voxels[index]) == palette_id and int(piece_edges[index]) == normalized_edge:
		return false
	voxels[index] = palette_id
	piece_edges[index] = normalized_edge
	return true


func fill_region(origin: Vector3i, edge: int, material_id: String, require_empty: bool = false) -> bool:
	if edge not in [1, 2, 4, 8] or material_id == "" or not _region_inside(origin, edge):
		return false
	if require_empty:
		for y in range(origin.y, origin.y + edge):
			for z in range(origin.z, origin.z + edge):
				for x in range(origin.x, origin.x + edge):
					if int(voxels[_index(Vector3i(x, y, z))]) != 0:
						return false
	var changed: bool = false
	for y in range(origin.y, origin.y + edge):
		for z in range(origin.z, origin.z + edge):
			for x in range(origin.x, origin.x + edge):
				changed = set_material(Vector3i(x, y, z), material_id, edge) or changed
	return changed


func clear_region(origin: Vector3i, edge: int) -> bool:
	if edge not in [1, 2, 4, 8] or not _region_inside(origin, edge):
		return false
	var split_pieces: Dictionary = {}
	for y in range(origin.y, origin.y + edge):
		for z in range(origin.z, origin.z + edge):
			for x in range(origin.x, origin.x + edge):
				var pos: Vector3i = Vector3i(x, y, z)
				var old_edge: int = get_piece_edge(pos)
				if old_edge > edge:
					var piece_origin: Vector3i = get_piece_origin(pos)
					split_pieces["%d:%d:%d:%d" % [piece_origin.x, piece_origin.y, piece_origin.z, old_edge]] = [piece_origin, old_edge]
	var changed: bool = false
	for y in range(origin.y, origin.y + edge):
		for z in range(origin.z, origin.z + edge):
			for x in range(origin.x, origin.x + edge):
				changed = set_material(Vector3i(x, y, z), "") or changed
	for raw_piece in split_pieces.values():
		var piece: Array = raw_piece as Array
		var piece_origin: Vector3i = piece[0]
		var old_edge: int = int(piece[1])
		for y in range(piece_origin.y, piece_origin.y + old_edge):
			for z in range(piece_origin.z, piece_origin.z + old_edge):
				for x in range(piece_origin.x, piece_origin.x + old_edge):
					var pos: Vector3i = Vector3i(x, y, z)
					if get_material(pos) != "" and get_piece_edge(pos) == old_edge:
						piece_edges[_index(pos)] = edge
	return changed


func is_empty() -> bool:
	return occupied_count() == 0


func occupied_count() -> int:
	var count: int = 0
	for palette_id in voxels:
		if palette_id != 0:
			count += 1
	return count


func full_material() -> String:
	if voxels.is_empty() or int(voxels[0]) == 0:
		return ""
	var expected: int = int(voxels[0])
	for palette_id in voxels:
		if int(palette_id) != expected:
			return ""
	return str(palette[expected]) if expected < palette.size() else ""


func normalizable_material() -> String:
	var material_id: String = full_material()
	if material_id == "": return ""
	for piece_edge in piece_edges:
		if int(piece_edge) != SIZE: return ""
	return material_id


func to_dictionary() -> Dictionary:
	var palette_rows: Array = []
	for material_id in palette: palette_rows.append(material_id)
	return {"size": SIZE, "palette": palette_rows, "runs": _encode_runs(voxels), "edge_runs": _encode_runs(piece_edges)}


static func from_dictionary(data: Dictionary, block_definitions: Dictionary = {}):
	if int(data.get("size", 0)) != SIZE or typeof(data.get("palette", [])) != TYPE_ARRAY or typeof(data.get("runs", [])) != TYPE_ARRAY:
		return null
	var raw_palette: Array = data.get("palette", []) as Array
	if raw_palette.is_empty() or str(raw_palette[0]) != "" or raw_palette.size() > 256:
		return null
	var result = (load("res://src/micro_cell_data.gd") as Script).new()
	result.palette = PackedStringArray()
	for raw_material in raw_palette:
		var material_id: String = str(raw_material)
		if material_id != "" and not block_definitions.is_empty() and not block_definitions.has(material_id):
			return null
		result.palette.append(material_id)
	var cursor: int = 0
	for raw_run in data.get("runs", []) as Array:
		if typeof(raw_run) != TYPE_ARRAY or (raw_run as Array).size() < 2:
			return null
		var run: Array = raw_run as Array
		var length: int = int(run[0])
		var value: int = int(run[1])
		if length <= 0 or value < 0 or value >= result.palette.size() or cursor + length > VOLUME:
			return null
		for index in range(cursor, cursor + length):
			result.voxels[index] = value
		cursor += length
	if cursor != VOLUME: return null
	if data.has("edge_runs") and typeof(data.get("edge_runs")) != TYPE_ARRAY: return null
	var raw_edge_runs: Array = data.get("edge_runs", []) as Array
	if raw_edge_runs.is_empty():
		for index in range(VOLUME):
			result.piece_edges[index] = 1 if int(result.voxels[index]) > 0 else 0
		return result
	cursor = 0
	for raw_run in raw_edge_runs:
		if typeof(raw_run) != TYPE_ARRAY or (raw_run as Array).size() < 2: return null
		var run: Array = raw_run as Array
		var length: int = int(run[0]); var value: int = int(run[1])
		if length <= 0 or value not in [0, 1, 2, 4, 8] or cursor + length > VOLUME: return null
		for index in range(cursor, cursor + length): result.piece_edges[index] = value
		cursor += length
	if cursor != VOLUME: return null
	for index in range(VOLUME):
		if (int(result.voxels[index]) == 0) != (int(result.piece_edges[index]) == 0): return null
	return result


func content_hash() -> String:
	return JSON.stringify(to_dictionary()).sha256_text()


func transformed(rotation_quarters: int, mirror_x: bool = false, mirror_z: bool = false):
	var result = (load("res://src/micro_cell_data.gd") as Script).new()
	for y in range(SIZE):
		for z in range(SIZE):
			for x in range(SIZE):
				var source: Vector3i = Vector3i(x, y, z)
				var material_id: String = get_material(source)
				if material_id == "":
					continue
				var target: Vector3i = source
				if mirror_x:
					target.x = SIZE - 1 - target.x
				if mirror_z:
					target.z = SIZE - 1 - target.z
				match posmod(rotation_quarters, 4):
					1: target = Vector3i(SIZE - 1 - target.z, target.y, target.x)
					2: target = Vector3i(SIZE - 1 - target.x, target.y, SIZE - 1 - target.z)
					3: target = Vector3i(target.z, target.y, SIZE - 1 - target.x)
				result.set_material(target, material_id, get_piece_edge(source))
	return result


static func _encode_runs(values: PackedByteArray) -> Array:
	var runs: Array = []
	var start: int = 0
	while start < values.size():
		var value: int = int(values[start]); var length: int = 1
		while start + length < values.size() and int(values[start + length]) == value: length += 1
		runs.append([length, value]); start += length
	return runs


func _palette_id(material_id: String) -> int:
	if material_id == "":
		return 0
	var existing: int = palette.find(material_id)
	if existing >= 0:
		return existing
	if palette.size() >= 256:
		return 0
	palette.append(material_id)
	return palette.size() - 1


func _region_inside(origin: Vector3i, edge: int) -> bool:
	return is_inside(origin) and is_inside(origin + Vector3i.ONE * (edge - 1))


static func _index(pos: Vector3i) -> int:
	return (pos.y * SIZE + pos.z) * SIZE + pos.x

